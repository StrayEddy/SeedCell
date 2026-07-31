extends RefCounted
class_name ProcessInterlock
## Pure, headless-testable process state machine for the SeedCell serve cycle.
## No scene/visual dependencies, so it can be unit-tested without a viewport.
##
## THE RULE (see docs/SAFETY.md): the machine may only PRESENT food to a person when
## (1) the batch's cook kill-step is positively proven (SF1 lethality, ADR-0009) AND
## (2) the food-contact surfaces were sanitized since the last serving (SF2, ADR-0010).
## Any failed cook, failed clean, or sensor fault means "assume unsafe": the batch is
## DIVERTED TO WASTE and the surfaces are re-cleaned -- never served. The mouth stays
## flush and sealed except during the brief PRESENT window. This is the food analog of
## HiveCell's "never move the piston while life is present": here, never open the mouth
## to a person around food that is not provably cooked and served on a clean surface.

enum State {
	IDLE,             # flush, sealed, sanitized, ready
	RATION_CHECK,     # confirm this person is due a serving (ADR-0013)
	CHARGE,           # meter dry blend into the bore (surfaces now dirty)
	HYDRATE,          # inject water + oil -> dough (no mixer blade, ADR-0006)
	COOK,             # heated bore + piston conduction-cook the flatbread
	LETHALITY_CHECK,  # SF1: is the kill-step proven? else divert
	PRESENT,          # advance piston, deliver the flatbread out the mouth
	RETRACT,          # withdraw into the sealed sterilization zone
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

# --- tuning (short in tests, realistic in the twin) ---
var charge_seconds := 3.0
var hydrate_seconds := 2.0
var cook_seconds := 90.0        # thin flatbread, two hot platens (see scripts/cook_energy.py)
var clean_seconds := 25.0
var stroke_seconds := 6.0       # present / retract stroke duration (SF5-shaped)
var relean_limit := 3           # consecutive failed cleans before LOCKOUT

# --- simulated inputs (ground truth the twin/test drives) ---
var request := false            ## someone is asking for a serving
var ration_ok := true           ## SF6/ADR-0013: this person is entitled to one now
var cook_ok := true             ## ground-truth kill-step reached (used only when lethality == null)
var sensor_fault := false       ## a faulted/unknown sensor anywhere safety-relevant (fail unsafe)
var surface_sanitized := true   ## SF2: post-clean verification reads the surfaces clean
var surface_touch_safe := true  ## SF4: delivered surface temp is safe to touch (burn guard)
var contact_over_limit := false ## SF4: measured mouth force over the safe cap (pinch/jam)

# --- state ---
var state: int = State.IDLE
var progress := 0.0             ## 0 = piston flush/sealed, 1 = piston fully presented at the mouth
var t := 0.0                    ## time in current state
var sanitized := true           ## surfaces are clean RIGHT NOW (consumed at CHARGE, restored at CLEAN_VERIFY)
var reclean_count := 0          ## consecutive failed clean-verifies
var served := 0                 ## flatbreads delivered to a person (safe path liveness)
var wasted := 0                 ## batches diverted to waste (never served)
var _batch_lethal := false      ## did the batch currently in the machine pass its kill-step?


## Fail-safe cook check: the kill-step must be POSITIVELY proven. A fault, a stale
## reading, or any dissenting channel reads "not cooked". Mirrors HiveCell's
## life_present() fail-safe, inverted (proof of safety, not proof of danger).
func cook_lethal() -> bool:
	if sensor_fault:
		return false
	if lethality != null:
		return not lethality.unsafe()
	return cook_ok


## SF4 gate for opening the mouth to a person: no pinch/jam and nothing too hot to touch.
func mouth_safe() -> bool:
	return not contact_over_limit and surface_touch_safe


## True only in the PRESENT stroke -- the one motion that exposes a person to the food
## and the hot piston. It must never begin unless cook_lethal() and sanitized held.
func presenting() -> bool:
	return state == State.PRESENT


## SF5 signalling: green ready / blue working / amber presenting / orange closed /
## flashing red = cannot make safe (alarm).
func signal_level() -> int:
	match state:
		State.IDLE:
			return SignalLevel.READY
		State.PRESENT:
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
				_goto(State.CHARGE)
		State.CHARGE:
			if t >= charge_seconds:
				_goto(State.HYDRATE)
		State.HYDRATE:
			if t >= hydrate_seconds:
				_goto(State.COOK)
		State.COOK:
			if t >= cook_seconds:
				_goto(State.LETHALITY_CHECK)
		State.LETHALITY_CHECK:
			# THE food-safety gate. Serve only a provably-cooked batch; otherwise the
			# batch goes to waste. There is no "serve it anyway" branch.
			if cook_lethal():
				_batch_lethal = true
				_goto(State.PRESENT)
			else:
				_goto(State.DIVERT)
		State.PRESENT:
			# Reachable only via a passed LETHALITY_CHECK, on sanitized surfaces. If the
			# mouth becomes unsafe (pinch or too-hot surface), abort the delivery and
			# retract -- never push through a hand or serve a burn.
			if not mouth_safe():
				_goto(State.RETRACT)
			else:
				progress = profile.advance(progress, delta, stroke_seconds)
				if progress >= 1.0:
					served += 1
					request = false
					_goto(State.RETRACT)
		State.RETRACT:
			# Withdraw toward flush: advance (1-progress) from wherever we are toward 1,
			# so progress decreases monotonically to 0 following the same soft shape.
			var back := profile.advance(1.0 - progress, delta, stroke_seconds)
			progress = clampf(1.0 - back, 0.0, 1.0)
			if progress <= 0.001:
				progress = 0.0
				_goto(State.CLEAN)
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
			_goto(State.CLEAN)
		State.LOCKOUT:
			# Out of service. Recover only when a clean verification passes again
			# (e.g. after a human services it and the fault clears).
			progress = 0.0
			if surface_sanitized and not sensor_fault:
				sanitized = true
				reclean_count = 0
				_goto(State.IDLE)


func _goto(s: int) -> void:
	state = s
	t = 0.0
