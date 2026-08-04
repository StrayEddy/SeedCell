extends SceneTree
## Headless self-test for the SF7 bake->serve hold guard (ADR-0016).
## Run:  Godot_v4.7.1 --headless --path godot --script res://tests/test_spore_hold.gd
## Exits 0 on pass, 1 on any failure.
##
## SF1 (ADR-0015) proves a batch was COOKED. It cannot touch Bacillus cereus spores, which
## survive the bake. This guard is the other half: it proves the batch has not since sat
## cool long enough for those survivors to outgrow. Two things are under test:
##   1. The GUARD itself -- the clock runs on sub-60 C time only, and fails in the safe
##      direction on a dead sensor (accrue, don't pause).
##   2. Its WIRING into the interlock -- an over-held batch is diverted, never served, and
##      every batch made is accounted for as either served or wasted.

const Guard := preload("res://spore_hold.gd")
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
	return pi


## Step the interlock, asserting throughout that a batch is NEVER served while its hold
## guard says it is unservable. This is the property the whole file exists to protect.
func _run(pi, n: int, tag: String) -> void:
	for i in n:
		# A batch is only served once someone takes it (SF8, ADR-0018); simulate a
		# collector so these scenarios still exercise the SF7 gate rather than timing out.
		if pi.state == Interlock.State.AWAIT_COLLECT:
			pi.face_loaded = false
		var served_before: int = pi.served
		var servable_before: bool = pi.spore_hold.servable()
		pi.step(DT)
		if pi.served > served_before:
			_check(servable_before, "%s: SERVED a batch that had outlived its hold budget" % tag)


func _initialize() -> void:
	print("== SeedCell spore-hold self-test (SF7 / ADR-0016) ==")

	# ---- 1. the guard in isolation --------------------------------------------------
	_check(Guard.self_test(), "SporeHold.self_test() returned false")

	# An unarmed guard is not a passing guard.
	var g0 = Guard.new()
	_check(not g0.servable(), "an unarmed guard reported the batch servable")
	_check(not g0.expired(), "an unarmed guard reported expiry")

	# Hot time is free; cool time is not.
	var hot = Guard.new()
	hot.start_hold()
	hot.max_hold_s = 5.0
	for i in 6000:
		hot.tick(0.01, 80.0)                       # 60 s held well above hot-hold
	_check(hot.elapsed == 0.0, "hot holding accrued %.2f s of risk time" % hot.elapsed)
	_check(hot.servable(), "a batch held hot was refused")

	var cool = Guard.new()
	cool.start_hold()
	cool.max_hold_s = 5.0
	for i in 400:
		cool.tick(0.01, 25.0)                      # 4 s cool -- inside budget
	_check(cool.servable(), "a batch inside its budget was refused")
	for i in 200:
		cool.tick(0.01, 25.0)                      # now 6 s -- over budget
	_check(cool.expired() and not cool.servable(), "an over-held batch was still servable")

	# Mixed history: only the sub-threshold portion counts.
	var mixed = Guard.new()
	mixed.start_hold()
	mixed.max_hold_s = 10.0
	for i in 1000:
		mixed.tick(0.01, 90.0)                     # 10 s hot -- must not count
	for i in 300:
		mixed.tick(0.01, 30.0)                     # 3 s cool
	_check(abs(mixed.elapsed - 3.0) < 0.05,
		"mixed history accrued %.2f s, expected ~3 s (hot time leaked into the clock)" % mixed.elapsed)

	# A dead thermometer must not buy unlimited holding time.
	var blind = Guard.new()
	blind.start_hold()
	blind.max_hold_s = 2.0
	for i in 300:
		blind.tick(0.01, NAN)
	_check(blind.elapsed > 0.0, "a dead sensor PAUSED the clock instead of accruing risk")
	_check(blind.expired() and not blind.servable(), "a blind batch was not withheld")

	# ---- 2. the good path is not disturbed -------------------------------------------
	# A normal hot batch must still be served. If SF7 broke liveness it would be a denial
	# of service dressed up as a safety feature.
	var p1 = _new_pi()
	p1.request = true
	p1.cook_ok = true
	p1.batch_temp_c = 95.0
	_run(p1, 300, "S1 good hot batch")
	_check(p1.served >= 1, "S1: a good hot batch was never served (SF7 broke liveness)")
	_check(p1.wasted == 0, "S1: a good hot batch was wasted")

	# Even a batch that cools fast is served, as long as it is collected promptly.
	var p2 = _new_pi()
	p2.request = true
	p2.cook_ok = true
	p2.batch_temp_c = 20.0                          # cools immediately, but budget is huge
	_run(p2, 300, "S2 prompt cool batch")
	_check(p2.served >= 1, "S2: a promptly-collected batch was refused for cooling")

	# ---- 3. the guard bites --------------------------------------------------------
	# A batch held past its budget before the serve gate must be diverted, never served.
	var p3 = _new_pi()
	p3.request = true
	p3.cook_ok = true
	p3.batch_temp_c = 20.0
	p3.spore_hold.max_hold_s = DT / 2.0             # expires on the first tick after the bake
	_run(p3, 400, "S3 over-held batch")
	_check(p3.served == 0, "S3: served a batch that had outlived its hold budget")
	_check(p3.wasted >= 1, "S3: an over-held batch was not diverted to waste")

	# Expiry DURING the delivery stroke aborts the hand-over.
	var p4 = _new_pi()
	p4.stroke_seconds = 2.0                          # long stroke, so expiry lands mid-way
	p4.request = true
	p4.cook_ok = true
	p4.batch_temp_c = 20.0
	p4.spore_hold.max_hold_s = 0.5
	_run(p4, 600, "S4 expiry mid-stroke")
	_check(p4.served == 0, "S4: completed a hand-over after the hold expired mid-stroke")
	_check(p4.wasted >= 1, "S4: a batch aborted mid-stroke was not counted as waste")

	# A sensor fault anywhere safety-relevant reads the hold as unprovable.
	var p5 = _new_pi()
	p5.request = true
	p5.cook_ok = true
	p5.batch_temp_c = 95.0
	_run(p5, 60, "S5 setup")
	p5.sensor_fault = true
	_check(not p5.hold_ok(), "S5: hold_ok() ignored a sensor fault")

	# ---- 4. accounting + no carry-over ------------------------------------------------
	# Every batch that gets made must end up either served or wasted. Before ADR-0016 an
	# abort mid-delivery fell through to CLEAN and was silently scraped away, counted as
	# neither.
	var p6 = _new_pi()
	p6.request = true
	p6.cook_ok = true
	p6.contact_over_limit = true                     # SF4 pinch trip: abort every delivery
	_run(p6, 600, "S6 aborted delivery")
	_check(p6.served == 0, "S6: served through a pinch trip")
	_check(p6.wasted >= 1, "S6: an aborted batch was neither served nor counted as waste")

	# The clock does not survive into the next batch.
	var p7 = _new_pi()
	p7.request = true
	p7.cook_ok = true
	p7.batch_temp_c = 20.0
	p7.spore_hold.max_hold_s = 3600.0
	_run(p7, 300, "S7 first batch")
	_check(p7.served >= 1, "S7: setup -- first batch should have been served")
	_check(not p7.spore_hold.armed, "S7: the guard stayed armed after the batch left")
	_check(p7.spore_hold.elapsed == 0.0,
		"S7: %.2f s of the previous batch's risk time carried over" % p7.spore_hold.elapsed)

	if failures == 0:
		print("PASS: an over-held batch is never served, and every batch is accounted for.")
		quit(0)
	else:
		print("FAILED: %d assertion(s)." % failures)
		quit(1)
