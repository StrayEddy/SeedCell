extends RefCounted
class_name CollectionGuard
## SF8 collection proof: a serving is not SERVED until a person has actually taken it.
##
## ADR-0016 closed the bake->collect interval (SF7) and named what it could not reach: a
## batch left presented at the mouth. Until now the interlock did not model that case at
## all -- it counted `served` the instant the piston stroke completed and immediately
## retracted, i.e. it assumed collection was instantaneous and always successful. Three
## separate things hide in that assumption:
##
##   1. ACCOUNTING. "Presented" is not "served". The ration policy (ADR-0013) debits a
##      person for a serving; debiting someone for bread they never received is a real
##      harm to exactly the population this machine exists for, and `served` is also the
##      twin's liveness measure -- it should mean "somebody ate", not "the piston moved".
##   2. EXPOSURE. Waiting for collection holds the mouth open. That window must be
##      BOUNDED, or a machine nobody came back to sits open to the street (H6).
##   3. RE-ENTRY. An uncollected batch has sat in public air, and may have been touched,
##      before the piston withdraws it back through the bore. It must be condemned, not
##      re-offered -- and it is safe to withdraw it precisely because DIVERT is always
##      followed by a mandatory CLEAN + CLEAN_VERIFY before the next charge.
##
## COLLECTION IS A TRANSITION, NOT A LEVEL. This is the whole integrity argument. The
## guard does not ask "is the face empty?" -- it requires the face to be seen CARRYING the
## batch first, and only then seen EMPTY. A sensor stuck at "empty" never arms, so it can
## never report a collection; a sensor stuck at "occupied" never sees the transition. Both
## stuck failures therefore run the window out and send the batch to waste, which is the
## direction every other guard in this machine fails in.
##
## WHY THERE IS NO `suspect` LATCH (unlike SporeHold). SporeHold integrates time, so a
## blind interval is information that is gone forever and must be assumed dangerous. This
## guard reads a STATE that persists: a sensor that faults and recovers can still see the
## face and the truth is unchanged. A blind interval costs only the clock that runs through
## it, and running out that clock already means waste. Nothing to latch.
##
## SCOPE. This proves the batch LEFT. It does not prove who took it (ADR-0013), and it does
## not make retracting safe while a hand is at the mouth -- that is SF4 mouth-presence
## hardware and is explicitly still open (ADR-0018, ROADMAP).

## How long the mouth may stay open waiting for a batch to be taken, in seconds.
##
## NOT a food-safety number, and deliberately so: whether the window is 60 s or 180 s, an
## expired batch is waste either way. What it bounds is EXPOSURE (H6 -- how long the mouth
## hangs open on a public street) and AVAILABILITY (how long one person who walked away can
## keep the machine out of service for the next). It is nested INSIDE SF7's hold budget --
## 120 s against a 900 s default -- so the safety bound always dominates; if the two ever
## crossed, SF7 would still condemn the batch first, and that ordering is the point.
##
## 120 s is chosen to be generous to the person, not to the machine: the requester was
## standing at the mouth seconds ago (the ADR-0013 ration check just identified them), so
## the normal case is a few seconds, and the margin is there for someone slow, encumbered,
## or unsure -- not for someone who has left.
const DEFAULT_WINDOW_S := 120.0

var window_s := DEFAULT_WINDOW_S

## The delivery is live: the batch is on its way out or waiting at the mouth.
var running := false

## The face was positively observed CARRYING the batch. Arms the transition; without it no
## collection can ever be reported.
var seen_loaded := false

## Latched: having been seen loaded, the face was then positively observed empty. Latching
## is safe because the interlock consumes it on the same frame and immediately retracts.
var taken := false

## Seconds the delivery has been live (stroke + wait). Runs regardless of sensor health.
var elapsed := 0.0

## Peak window used, for telemetry after a reset.
var last_elapsed := 0.0


## Begin a delivery. Called when the present stroke starts, not when it finishes, so a
## batch taken off the face mid-stroke still counts as collected.
func start() -> void:
	running = true
	seen_loaded = false
	taken = false
	elapsed = 0.0


## Advance the window and read the face sensor.
##
## `face_loaded` is the sensor's view of whether the batch is still on the piston face
## (loss-of-mass on the actuator's force channel, which SF4's contact cap already needs).
## `sensor_ok` is false whenever that reading cannot be trusted. A blind sample changes no
## state but does NOT pause the clock -- a delivery nobody can see the end of must time out
## to waste rather than hang the mouth open indefinitely.
func observe(delta: float, face_loaded: bool, sensor_ok: bool) -> void:
	if delta <= 0.0 or not running:
		return
	elapsed += delta
	if not sensor_ok:
		return
	if face_loaded:
		seen_loaded = true
	elif seen_loaded:
		taken = true


## Has this batch been positively proven to have left the machine? Requires the full
## loaded -> empty transition on a live delivery: never true from a level alone.
func collected() -> bool:
	return running and seen_loaded and taken


## Has the collection window run out? An expired delivery is waste, not a retry.
func expired() -> bool:
	return running and elapsed >= window_s


## Fraction of the window consumed, for UI / telemetry. Not a safety read.
func fraction() -> float:
	if window_s <= 0.0:
		return 1.0
	return clampf(elapsed / window_s, 0.0, 1.0)


## The delivery is over (collected, aborted, or timed out). Disarms until the next one.
func reset() -> void:
	last_elapsed = elapsed
	running = false
	seen_loaded = false
	taken = false
	elapsed = 0.0


## Runtime self-test. Returns true on pass.
static func self_test() -> bool:
	var g := CollectionGuard.new()

	# Not running is never collected and never expired -- no delivery is not a done delivery.
	if g.collected() or g.expired():
		return false
	g.observe(1000.0, false, true)
	if g.collected() or g.elapsed != 0.0:
		return false

	# The normal case: seen loaded, then seen empty -> collected.
	g.start()
	g.observe(0.5, true, true)
	if g.collected():
		return false            # loaded alone is not collection
	g.observe(0.5, false, true)
	if not g.collected() or g.expired():
		return false

	# A sensor STUCK AT EMPTY never arms, so it can never report a collection, however long.
	g.start()
	g.window_s = 10.0
	for i in 40:
		g.observe(0.5, false, true)
	if g.seen_loaded or g.collected():
		return false
	if not g.expired():
		return false            # ...and it runs the window out to waste

	# A sensor STUCK AT OCCUPIED never sees the transition -- same destination.
	g.start()
	g.window_s = 10.0
	for i in 40:
		g.observe(0.5, true, true)
	if g.collected() or not g.expired():
		return false

	# A blind sensor changes no state but does not stop the clock.
	g.start()
	g.window_s = 5.0
	for i in 20:
		g.observe(0.5, false, false)
	if g.seen_loaded or g.collected():
		return false
	if not g.expired():
		return false

	# A fault that clears still reads the truth: this is a state, not an event. Stepped in
	# 0.5 s (exactly representable) so the boundary tests the comparison, not float drift.
	g.start()
	g.window_s = 100.0
	g.observe(0.5, true, true)      # seen carrying the batch
	g.observe(0.5, false, false)    # blind for a moment
	if g.collected():
		return false
	g.observe(0.5, false, true)     # sight returns: the face really is empty
	if not g.collected():
		return false

	# Expiry lands exactly on the budget, not a frame early.
	g.start()
	g.window_s = 10.0
	for i in 19:
		g.observe(0.5, true, true)
	if g.expired():
		return false
	g.observe(0.5, true, true)      # 10.0 s -- the window, exactly
	if not g.expired():
		return false

	# Reset disarms and clears; nothing carries into the next delivery.
	g.reset()
	if g.running or g.seen_loaded or g.taken or g.elapsed != 0.0 or g.collected():
		return false

	return true
