extends RefCounted
class_name ProcessInterlock
## Pure, headless-testable process state machine for the SeedCell serve cycle.
## No scene/visual dependencies, so it can be unit-tested without a viewport.
##
## THE RULE (see docs/SAFETY.md): the machine may only PRESENT food to a person when
## (1) the batch's cook kill-step is positively proven (SF1 lethality, ADR-0009) AND
## (2) the food-contact surfaces were sanitized since the last serving (SF2, ADR-0010).
## Any failed cook, failed clean, or sensor fault means "assume unsafe": the batch is
## DIVERTED TO WASTE and the surfaces are re-cleaned -- never served. A serving is only
## counted once a person has positively taken it (SF8 collection proof, ADR-0018), and the
## mouth is open only for that bounded delivery window. (During the BAKE the mouth is not
## in fact sealed at all -- see ADR-0017, open.) This is the food analog of HiveCell's
## "never move the piston while life is present": here, never open the mouth
## to a person around food that is not provably cooked and served on a clean surface.

enum State {
	IDLE,             # flush, sealed, sanitized, ready
	RATION_CHECK,     # confirm this person is due a serving (ADR-0013)
	CHARGE,           # piston retracted (chargeDepth open): meter dry blend into the bore
	                  # (surfaces now dirty)
	HYDRATE,          # piston still retracted: inject water + oil -> dough in the open
	                  # chamber (no mixer blade, ADR-0006)
	PRESS,            # advance piston from retracted to flush: closes the mouth from the
	                  # inside and becomes the second hot platen for the bake (ADR-0006,
	                  # ADR-0007, ADR-0019). The mouth-open window this ADR-0017 worries
	                  # about ends here, not at COOK.
	COOK,             # piston held flush: heated bore + piston conduction-cook the flatbread
	LETHALITY_CHECK,  # SF1: is the kill-step proven? else divert
	PRESENT,          # advance piston, deliver the flatbread out the mouth
	AWAIT_COLLECT,    # SF8: presented at the mouth, waiting for a person to take it
	RETRACT,          # withdraw into the sealed sterilization zone; SF9 holds position
	                  # (does not advance) while the mouth reads occupied (ADR-0020)
	CLEAN,            # scrape + steam + heat-sterilize + dry (SF2)
	CLEAN_VERIFY,     # SF2: are surfaces provably sanitized? else re-clean
	DIVERT,           # dump an unsafe batch to waste, then clean
	LOCKOUT,          # cannot make the line safe -> refuse service, alert a human
}
enum SignalLevel { READY, WORKING, PRESENTING, CLOSED, ALARM }  # green/blue/amber/orange/flashing-red

var profile := SoftProfile.new()    # SF5 soft velocity profile (shapes the present/retract stroke)

## SF1 cook-lethality voter (ADR-0009). When set, cook_lethal() consults the
## diverse-redundant, fail-safe voter instead of the simplified ground-truth field
## below. Left null in the pure-logic interlock tests (which drive cook_ok directly).
## The twin/real line attaches a real probe suite.
var lethality: CookLethality = null

## SF7 bake->serve hold guard (ADR-0016) -- the B. cereus spore control. SF1 proves the
## batch was COOKED; this proves it has not since sat around long enough for the spores
## that survived that cook to outgrow. Always present (unlike `lethality`), because it
## needs no hardware beyond a thermometer the burn guard already requires.
var spore_hold := SporeHold.new()

## SF8 collection proof (ADR-0018) -- the other half of the gap ADR-0016 named. SF7 bounds
## how long a batch may WAIT; this proves the batch actually LEFT, so `served` means a
## person was fed rather than that the piston completed its stroke. Always present: like
## SF7 it reuses sensing the SF4 guard already requires.
var collection := CollectionGuard.new()

# --- tuning (short in tests, realistic in the twin) ---
var charge_seconds := 3.0
var hydrate_seconds := 2.0
var press_seconds := 4.0        # piston travel from open (chargeDepth) to flush; matches
                                 # PRESS_S in scripts/actuator_sizing.py (ADR-0019)
var cook_seconds := 90.0        # thin flatbread, two hot platens (see scripts/cook_energy.py)
var clean_seconds := 25.0
var stroke_seconds := 6.0       # present / retract stroke duration (SF5-shaped)
var relean_limit := 3           # consecutive failed cleans before LOCKOUT
var retract_clear_timeout_s := 60.0  ## SF9: how long RETRACT may sit blocked waiting for the
                                      ## mouth to read clear before it stops waiting and alarms.
                                      ## Shorter than SF8's 120 s collection window on purpose --
                                      ## by the time we are here, either the batch was just
                                      ## collected (person is right there, done in seconds) or
                                      ## the delivery was condemned with nobody home (nothing to
                                      ## wait for). A hand still present a full minute later is
                                      ## more likely a stuck sensor or a foreign object than a
                                      ## slow person (ADR-0020).

# --- simulated inputs (ground truth the twin/test drives) ---
var request := false            ## someone is asking for a serving
var ration_ok := true           ## SF6/ADR-0013: this person is entitled to one now
var cook_ok := true             ## ground-truth kill-step reached (used only when lethality == null)
var sensor_fault := false       ## a faulted/unknown sensor anywhere safety-relevant (fail unsafe)
var surface_sanitized := true   ## SF2: post-clean verification reads the surfaces clean
var surface_touch_safe := true  ## SF4: delivered surface temp is safe to touch (burn guard)
var contact_over_limit := false ## SF4: measured mouth force over the safe cap (pinch/jam)
var hand_present := false       ## SF9: the mouth-presence sensor sees something there right
                                 ## now (hand, object) -- read continuously, not just during
                                 ## PRESENT. Same presence/safety-edge sensor SF4 needs for the
                                 ## pinch cap, read through RETRACT too (ADR-0020).
var batch_temp_c := 95.0        ## SF7: the batch's current temperature, post-bake. Drives
                                ## the spore-hold clock, which only runs below 60 C. The
                                ## twin/real line feeds the delivered-surface thermometer
                                ## the burn guard already needs; tests drive it directly.
var face_loaded := true         ## SF8: does the face sensor still see the batch on the piston?
                                ## Defaults TRUE -- "nobody has taken it" is the pessimistic
                                ## reading, and a delivery must be positively observed to end.
                                ## The twin/real line reads loss-of-mass on the actuator force
                                ## channel SF4's contact cap already needs.

# --- state ---
var state: int = State.IDLE
var progress := 0.0             ## 0 = piston flush/sealed, 1 = piston fully presented at the
                                 ## mouth. Only tracks the PRESENT<->RETRACT delivery stroke;
                                 ## the CHARGE/HYDRATE<->PRESS travel (open <-> flush) is a
                                 ## separate axis this twin does not position-track, timed
                                 ## instead like CHARGE/HYDRATE themselves (ADR-0019).
var t := 0.0                    ## time in current state
var sanitized := true           ## surfaces are clean RIGHT NOW (consumed at CHARGE, restored at CLEAN_VERIFY)
var reclean_count := 0          ## consecutive failed clean-verifies
var served := 0                 ## flatbreads delivered to a person (safe path liveness)
var wasted := 0                 ## batches diverted to waste (never served)
var _batch_lethal := false      ## did the batch currently in the machine pass its kill-step?
var _batch_condemned := false   ## an abort mid-delivery marked this batch for waste. Set on
                                ## an SF4 mouth abort or an SF7 hold expiry, consumed at the
                                ## end of RETRACT, which then routes to DIVERT instead of
                                ## CLEAN so the batch is counted as wasted rather than
                                ## silently scraped away by the next clean cycle.


## Fail-safe cook check: the kill-step must be POSITIVELY proven. A fault, a stale
## reading, or any dissenting channel reads "not cooked". Mirrors HiveCell's
## life_present() fail-safe, inverted (proof of safety, not proof of danger).
func cook_lethal() -> bool:
	if sensor_fault:
		return false
	if lethality != null:
		return not lethality.unsafe()
	return cook_ok


## SF7 gate: has this batch been cool for too long to hand over? (ADR-0016)
## Fail-safe like every other gate here -- an unarmed or unprovable guard reads "no".
func hold_ok() -> bool:
	if sensor_fault:
		return false
	return spore_hold.servable()


## SF4 gate for opening the mouth to a person: no pinch/jam and nothing too hot to touch.
func mouth_safe() -> bool:
	return not contact_over_limit and surface_touch_safe


## SF9 gate: is it safe to keep withdrawing right now? Fail-safe like every other gate here
## -- a faulted or absent presence reading means "something might still be there" (ADR-0020).
func retract_clear() -> bool:
	if sensor_fault:
		return false
	return not hand_present


## True only in the PRESENT stroke -- the one motion that exposes a person to the food
## and the hot piston. It must never begin unless cook_lethal() and sanitized held.
func presenting() -> bool:
	return state == State.PRESENT


## True whenever the mouth is open to the street with food in it: the delivery stroke AND
## the wait for collection. This, not presenting(), is the H6 ingress-exposure window --
## SF8's whole reason for bounding the wait is to bound this.
func mouth_open() -> bool:
	return state == State.PRESENT or state == State.AWAIT_COLLECT


## SF5 signalling: green ready / blue working / amber presenting / orange closed /
## flashing red = cannot make safe (alarm).
func signal_level() -> int:
	match state:
		State.IDLE:
			return SignalLevel.READY
		State.PRESENT, State.AWAIT_COLLECT:
			return SignalLevel.PRESENTING
		State.RETRACT, State.CLEAN, State.CLEAN_VERIFY:
			return SignalLevel.CLOSED
		State.LOCKOUT:
			return SignalLevel.ALARM
		_:
			return SignalLevel.WORKING


func step(delta: float) -> void:
	t += delta
	if lethality != null:
		lethality.tick(delta)   # age the probe channels; unrefreshed => stale => unsafe
	# SF7: risk time accrues from end-of-cook onward, wherever the batch happens to be.
	# Deliberately ticked before the state machine runs, so a batch cannot slip through a
	# gate on a clock that had not yet been advanced this frame.
	spore_hold.tick(delta, batch_temp_c)
	match state:
		State.IDLE:
			progress = 0.0
			# Never start a batch on dirty surfaces: clean first, then serve.
			if not sanitized:
				_goto(State.CLEAN)
			elif request and not sensor_fault:
				_goto(State.RATION_CHECK)
		State.RATION_CHECK:
			if not ration_ok:
				request = false
				_goto(State.IDLE)          # politely refuse; no food made
			else:
				sanitized = false          # surfaces are about to get dirty
				_batch_lethal = false
				_batch_condemned = false
				spore_hold.reset()         # never inherit the last batch's clock
				collection.reset()         # nor the last delivery's collection proof
				_goto(State.CHARGE)
		State.CHARGE:
			if t >= charge_seconds:
				_goto(State.HYDRATE)
		State.HYDRATE:
			if t >= hydrate_seconds:
				_goto(State.PRESS)
		State.PRESS:
			if t >= press_seconds:
				_goto(State.COOK)
		State.COOK:
			if t >= cook_seconds:
				# End of bake: the batch is now food that can spoil. Start SF7's clock
				# here, not at PRESENT -- the risk accrues while it waits, wherever it
				# waits, including through an abort/retry that never reaches the mouth.
				spore_hold.start_hold()
				_goto(State.LETHALITY_CHECK)
		State.LETHALITY_CHECK:
			# THE food-safety gate. Serve only a batch that is provably cooked (SF1)
			# AND has not since been held long enough for surviving spores to outgrow
			# (SF7, ADR-0016). Otherwise the batch goes to waste. There is no
			# "serve it anyway" branch.
			if cook_lethal() and hold_ok():
				_batch_lethal = true
				# SF8's window opens with the STROKE, not with the wait: a batch lifted
				# off the face on its way out has still been collected.
				collection.start()
				_goto(State.PRESENT)
			else:
				_goto(State.DIVERT)
		State.PRESENT:
			# Reachable only via a passed LETHALITY_CHECK, on sanitized surfaces. If the
			# mouth becomes unsafe (pinch or too-hot surface), abort the delivery and
			# retract -- never push through a hand or serve a burn.
			if not mouth_safe() or not hold_ok():
				# Abort the delivery. Either way the batch is condemned: it is half out
				# of a machine that just decided it must not be handed over, so it goes
				# to waste rather than back into service.
				_batch_condemned = true
				_goto(State.RETRACT)
			else:
				# SF8: watch the face for the whole stroke, not just at the end. A batch
				# taken off the piston on its way out is collected, and the right response
				# is to stop pushing and withdraw -- not to keep driving an empty hot face
				# out into the mouth.
				collection.observe(delta, face_loaded, not sensor_fault)
				if collection.collected():
					_hand_over()
				elif collection.expired():
					# The stroke itself has outrun the delivery window -- a stalled or jammed
					# advance. The window bounds the WHOLE delivery, not just the wait, so
					# this batch is condemned like any other that timed out.
					_batch_condemned = true
					_goto(State.RETRACT)
				else:
					progress = profile.advance(progress, delta, stroke_seconds)
					if progress >= 1.0:
						# Fully presented and still on the face: hold it out and wait for a
						# person. THIS is where `served` used to be incremented, on the
						# strength of the piston having moved. It is not a serving until
						# somebody takes it.
						_goto(State.AWAIT_COLLECT)
		State.AWAIT_COLLECT:
			# The batch is held out at the mouth. SF4 splits here, on purpose:
			#  - the PINCH cap does NOT gate this state. The piston is stationary and
			#    generates no crushing force, and a hand at the mouth is the INTENDED event.
			#    Gating the wait on contact force would condemn batches for being collected.
			#  - the BURN cap still does. If the presented surface stops being touch-safe,
			#    withdrawing it takes the hot thing out of reach, which is the protective
			#    move; leaving it out is not.
			# SF7 also keeps running -- a batch that outlives its hold budget while waiting
			# is condemned where it stands.
			progress = 1.0
			if not hold_ok() or not surface_touch_safe:
				_batch_condemned = true
				_goto(State.RETRACT)
			else:
				collection.observe(delta, face_loaded, not sensor_fault)
				if collection.collected():
					_hand_over()
				elif collection.expired():
					# Nobody came. The batch has sat in public air at an open mouth and may
					# have been handled, so it is condemned rather than re-offered or left
					# lying at the die. Withdrawing it back through the bore is safe only
					# because DIVERT is always followed by CLEAN + CLEAN_VERIFY before any
					# next charge -- the same gate that lets the machine bake at all.
					_batch_condemned = true
					_goto(State.RETRACT)
		State.RETRACT:
			# SF9 (ADR-0020): a hand-over just happened, or a batch was condemned at the
			# mouth -- either way this is exactly when a hand is most likely to be right
			# there. Don't withdraw across it: hold position (no crushing force generated
			# by sitting still, same reasoning AWAIT_COLLECT already uses for the pinch
			# cap) until the mouth reads clear, bounded by retract_clear_timeout_s so a
			# stuck sensor or a dropped object can't strand the machine silently forever.
			if not retract_clear():
				if t >= retract_clear_timeout_s:
					_goto(State.LOCKOUT)
			else:
				# Withdraw toward flush: advance (1-progress) from wherever we are toward 1,
				# so progress decreases monotonically to 0 following the same soft shape.
				var back := profile.advance(1.0 - progress, delta, stroke_seconds)
				progress = clampf(1.0 - back, 0.0, 1.0)
				if progress <= 0.001:
					progress = 0.0
					# An aborted batch is counted as waste, not quietly scraped away by the
					# next clean cycle: served + wasted must account for every batch made.
					_goto(State.DIVERT if _batch_condemned else State.CLEAN)
		State.CLEAN:
			# Scrape + steam + heat-sterilize + dry the small food-contact area.
			if t >= clean_seconds:
				_goto(State.CLEAN_VERIFY)
		State.CLEAN_VERIFY:
			# SF2: only a PROVEN-clean surface returns the line to service.
			if surface_sanitized and not sensor_fault:
				sanitized = true
				reclean_count = 0
				_goto(State.IDLE)
			else:
				reclean_count += 1
				if reclean_count >= relean_limit:
					_goto(State.LOCKOUT)   # cannot self-clean -> stop serving, alert
				else:
					_goto(State.CLEAN)     # try again; stays out of service meanwhile
		State.DIVERT:
			# The unsafe batch is dumped to the waste chute, never to the mouth.
			wasted += 1
			request = false
			_batch_lethal = false
			_batch_condemned = false
			spore_hold.reset()
			collection.reset()
			_goto(State.CLEAN)
		State.LOCKOUT:
			# Out of service, holding wherever the actuator stopped -- an alarm state
			# freezes position, it does not command new motion. Two entry paths land here
			# and recover differently, distinguished by `progress` (never touched while
			# LOCKOUT sits, so it still reflects which one this is):
			#  - stuck mid-RETRACT (SF9, ADR-0020): progress > 0, piston short of flush.
			#    Recovers the moment the mouth reads clear again and resumes withdrawing --
			#    no human action needed if it was a transient obstruction.
			#  - stuck at CLEAN_VERIFY (SF2): progress == 0 (RETRACT already finished).
			#    Recovers only when a clean verification passes -- needs an actual human
			#    service call, not just a clear read.
			if progress > 0.0:
				if retract_clear():
					_goto(State.RETRACT)
			elif surface_sanitized and not sensor_fault:
				sanitized = true
				reclean_count = 0
				_goto(State.IDLE)


## A person has taken the batch: the ONE path that increments `served`. Reached from the
## delivery stroke or from the wait at the mouth, and only ever via CollectionGuard's
## loaded -> empty transition, so the counter means "somebody was fed" rather than "the
## piston completed its travel".
func _hand_over() -> void:
	served += 1
	request = false
	spore_hold.reset()      # batch has left the machine
	collection.reset()
	_goto(State.RETRACT)


func _goto(s: int) -> void:
	state = s
	t = 0.0
