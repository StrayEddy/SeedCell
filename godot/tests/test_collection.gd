extends SceneTree
## Headless self-test for the SF8 collection proof (ADR-0018).
## Run:  Godot_v4.7.1 --headless --path godot --script res://tests/test_collection.gd
## Exits 0 on pass, 1 on any failure.
##
## ADR-0016 named the gap this closes: a batch presented at the mouth and never taken. The
## interlock used to count `served` the moment the piston stroke finished, i.e. it assumed
## collection was instant and infallible. Two properties are under test:
##   1. The GUARD -- collection is the transition loaded -> empty, never a level, so a
##      sensor stuck at either end fails to WASTE rather than to a phantom serving.
##   2. Its WIRING -- an uncollected batch is withdrawn, condemned and counted as waste;
##      the mouth does not stay open indefinitely; and a collected batch is still served
##      (SF8 must not become a denial of service dressed up as a safety feature).

const Guard := preload("res://collection_guard.gd")
const Interlock := preload("res://process_interlock.gd")
const DT := 1.0 / 60.0

var failures: int = 0


func _fail(msg: String) -> void:
	failures += 1
	push_error("FAIL: " + msg)
	print("  FAIL: ", msg)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_fail(msg)


func _new_pi():
	var pi = Interlock.new()
	pi.charge_seconds = 0.2
	pi.hydrate_seconds = 0.2
	pi.press_seconds = 0.2
	pi.cook_seconds = 0.3
	pi.clean_seconds = 0.3
	pi.stroke_seconds = 0.3
	pi.collection.window_s = 2.0     # short window so an uncollected batch times out fast
	return pi


## Step the interlock. `take_after` simulates a person: once the delivery has been live for
## that many seconds, the face sensor stops seeing the batch. INF = nobody ever takes it.
##
## Every frame asserts the property the file exists to protect: `served` may only increment
## on a proven collection.
func _run(pi, n: int, take_after: float, tag: String) -> void:
	var live := 0.0
	for i in n:
		if pi.mouth_open():
			live += DT
			pi.face_loaded = live < take_after
		else:
			live = 0.0
			pi.face_loaded = true
		var served_before: int = pi.served
		# The transition the serve must rest on: the guard had already seen the batch on
		# the face, and this frame's sample sees it gone. Read before step(), because
		# _hand_over() resets the guard on the very frame it credits the serving.
		var seen_loaded_before: bool = pi.collection.seen_loaded
		var face_now: bool = pi.face_loaded
		pi.step(DT)
		if pi.served > served_before:
			_check(seen_loaded_before and not face_now,
				"%s: SERVED a batch that was never proven collected" % tag)


func _initialize() -> void:
	print("== SeedCell collection self-test (SF8 / ADR-0018) ==")

	# ---- 1. the guard in isolation --------------------------------------------------
	_check(Guard.self_test(), "CollectionGuard.self_test() returned false")

	# A guard that was never started is not a collected delivery.
	var g0 = Guard.new()
	_check(not g0.collected(), "an unstarted guard reported a collection")
	_check(not g0.expired(), "an unstarted guard reported expiry")

	# The transition, not the level. A face that reads EMPTY from the very first sample
	# (a broken-open sensor) must never be read as "the batch was taken".
	var stuck_empty = Guard.new()
	stuck_empty.start()
	stuck_empty.window_s = 1.0
	for i in 600:
		stuck_empty.observe(0.01, false, true)
	_check(not stuck_empty.collected(),
		"a sensor stuck at EMPTY reported a phantom collection (level was read as a transition)")
	_check(stuck_empty.expired(), "a stuck-empty delivery did not time out")

	# ...and the opposite stuck failure lands in the same place.
	var stuck_full = Guard.new()
	stuck_full.start()
	stuck_full.window_s = 1.0
	for i in 600:
		stuck_full.observe(0.01, true, true)
	_check(not stuck_full.collected(), "a sensor stuck at OCCUPIED reported a collection")
	_check(stuck_full.expired(), "a stuck-occupied delivery did not time out")

	# A blind sensor proves nothing, and must not stop the clock: a delivery nobody can
	# see the end of times out to waste rather than hanging the mouth open.
	var blind = Guard.new()
	blind.start()
	blind.window_s = 1.0
	for i in 600:
		blind.observe(0.01, false, false)
	_check(not blind.collected(), "a blind sensor reported a collection")
	_check(blind.expired(), "a blind delivery PAUSED the clock instead of timing out")

	# Unlike SporeHold there is no suspect latch: this reads a persistent STATE, so a fault
	# that clears still tells the truth.
	var recovered = Guard.new()
	recovered.start()
	recovered.observe(0.1, true, true)
	recovered.observe(0.1, false, false)
	_check(not recovered.collected(), "credited a collection from a blind sample")
	recovered.observe(0.1, false, true)
	_check(recovered.collected(), "a recovered sensor's true reading was ignored")

	# ---- 2. liveness: a collected batch is still served ------------------------------
	var p1 = _new_pi()
	p1.request = true
	p1.cook_ok = true
	_run(p1, 400, 0.05, "S1 collected batch")
	_check(p1.served >= 1, "S1: a batch that WAS taken was never served (SF8 broke liveness)")
	_check(p1.wasted == 0, "S1: a collected batch was wasted")

	# ---- 3. the guard bites: nobody comes ---------------------------------------------
	var p2 = _new_pi()
	p2.request = true
	p2.cook_ok = true
	_run(p2, 1200, INF, "S2 uncollected batch")
	_check(p2.served == 0,
		"S2: counted a serving for a batch nobody took (presented is not served)")
	_check(p2.wasted >= 1, "S2: an uncollected batch was not condemned to waste")
	_check(p2.state != Interlock.State.AWAIT_COLLECT,
		"S2: still waiting at the mouth long after the window expired")

	# The mouth does not stay open past the window. This is the H6 exposure bound: measure
	# the longest unbroken run of open-mouth frames and hold it to the window (+ the stroke
	# and a frame of slack).
	var p3 = _new_pi()
	p3.request = true
	p3.cook_ok = true
	var open_s := 0.0
	var worst_open := 0.0
	for i in 1200:
		p3.face_loaded = true                     # nobody ever takes it
		p3.step(DT)
		open_s = open_s + DT if p3.mouth_open() else 0.0
		worst_open = maxf(worst_open, open_s)
	_check(worst_open <= p3.collection.window_s + p3.stroke_seconds + DT,
		"S3: mouth stayed open %.2f s, over the %.2f s delivery window" %
		[worst_open, p3.collection.window_s])

	# ---- 4. accounting ----------------------------------------------------------------
	# Every batch made ends up served or wasted -- the invariant ADR-0016 established, now
	# extended over the state it did not model.
	var p4 = _new_pi()
	p4.request = true
	p4.cook_ok = true
	var made := 0
	var was_charging := false
	for i in 2400:
		p4.face_loaded = true                     # never collected: every batch times out
		p4.step(DT)
		var charging: bool = p4.state == Interlock.State.CHARGE
		if charging and not was_charging:
			made += 1
		was_charging = charging
		p4.request = true                         # a queue of people who all walk away
	# Let whatever is in flight finish, so the last batch is resolved rather than counted
	# as made-but-pending.
	p4.request = false
	for i in 2400:
		p4.face_loaded = true
		p4.step(DT)
		if p4.state == Interlock.State.IDLE:
			break
	_check(p4.state == Interlock.State.IDLE, "S4: machine never came back to rest")
	_check(made >= 2, "S4: setup -- expected several batches, got %d" % made)
	_check(p4.served + p4.wasted == made,
		"S4: %d batches made but %d served + %d wasted" % [made, p4.served, p4.wasted])
	_check(p4.served == 0, "S4: served a batch in a run where nobody ever collected")

	# ---- 5. SF7 still dominates -------------------------------------------------------
	# The collection window is nested INSIDE the hold budget and must never be able to
	# extend it: a batch whose spore-hold expires while it waits is condemned where it
	# stands, without waiting out the rest of the window.
	var p5 = _new_pi()
	p5.request = true
	p5.cook_ok = true
	p5.batch_temp_c = 20.0                        # cools instantly, so the clock runs
	p5.collection.window_s = 600.0                # a window far longer than the budget
	p5.spore_hold.max_hold_s = 0.5
	_run(p5, 1200, INF, "S5 hold expires while waiting")
	_check(p5.served == 0, "S5: served a batch whose hold budget expired at the mouth")
	_check(p5.wasted >= 1, "S5: an over-held waiting batch was not condemned")
	_check(p5.state != Interlock.State.AWAIT_COLLECT,
		"S5: the collection window outlived the SF7 hold budget")

	# ---- 6. mid-stroke collection ------------------------------------------------------
	# Someone takes the bread off the face before the stroke completes. That is a real
	# collection: stop pushing, count it, withdraw -- do not keep driving an empty hot face
	# out into the mouth.
	var p6 = _new_pi()
	p6.stroke_seconds = 2.0
	p6.request = true
	p6.cook_ok = true
	var saw_await := false
	for i in 600:
		if p6.mouth_open():
			p6.face_loaded = p6.progress < 0.5    # taken half-way out
		if p6.state == Interlock.State.AWAIT_COLLECT:
			saw_await = true
		p6.step(DT)
	_check(p6.served >= 1, "S6: a batch taken mid-stroke was not counted as served")
	_check(not saw_await, "S6: kept pushing to full extension after the batch was taken")

	# ---- 7. SF4 splits at the mouth ----------------------------------------------------
	# The BURN cap still bites while the batch waits: a surface that stops being touch-safe
	# is withdrawn out of reach, not left held out.
	var p8 = _new_pi()
	p8.request = true
	p8.cook_ok = true
	for i in 1200:
		p8.face_loaded = true
		if p8.state == Interlock.State.AWAIT_COLLECT:
			p8.surface_touch_safe = false          # goes scalding while waiting
		p8.step(DT)
	_check(p8.served == 0, "S8: served a batch off a surface that was not touch-safe")
	_check(p8.wasted >= 1, "S8: a batch withdrawn on the burn guard was not counted as waste")

	# The PINCH cap does not: a hand pressing on the face while collecting is the intended
	# event, not a fault, and must not condemn the serving.
	var p9 = _new_pi()
	p9.request = true
	p9.cook_ok = true
	for i in 600:
		if p9.state == Interlock.State.AWAIT_COLLECT:
			p9.contact_over_limit = true           # a hand resting on the face...
			p9.face_loaded = false                 # ...taking the bread
		p9.step(DT)
	_check(p9.served >= 1,
		"S9: condemned a batch for being collected (the pinch cap gated a stationary piston)")

	# ---- 8. no carry-over ---------------------------------------------------------------
	var p7 = _new_pi()
	p7.request = true
	p7.cook_ok = true
	_run(p7, 400, 0.05, "S7 first batch")
	_check(p7.served >= 1, "S7: setup -- first batch should have been served")
	_check(not p7.collection.running, "S7: the guard stayed live after the delivery ended")
	_check(not p7.collection.taken, "S7: a stale collection proof survived into the next batch")

	if failures == 0:
		print("PASS: presented is not served -- an uncollected batch is withdrawn and wasted.")
		quit(0)
	else:
		print("FAILED: %d assertion(s)." % failures)
		quit(1)
