extends SceneTree
## Headless self-test for the SeedCell process interlock.
## Run:  Godot_v4.7.1 --headless --path godot --script res://tests/test_interlock.gd
## Exits 0 on pass, 1 on any failure (so it can gate CI / a pre-push check).
##
## The invariant that matters (docs/SAFETY.md): the machine must NEVER present food to
## a person unless the batch's cook kill-step was proven (SF1). Everything else is
## secondary. We also assert the safe path still WORKS (a good batch IS served), so a
## trivially-frozen machine that never serves anything can't pass.

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


## Step `n` frames. Every frame enforce the master invariants:
##  - never at the open mouth with an unvalidated batch;
##  - the served counter never increments for a batch that was not lethal-validated.
##
## Since ADR-0018 a batch is only served once a person is proven to have TAKEN it, so these
## scenarios simulate a collector: `auto_collect` clears the face sensor as soon as the
## batch is presented. Scenarios that want an uncollected batch live in test_collection.gd.
var auto_collect := true


func _run(pi, n: int, tag: String) -> void:
	for i in n:
		if auto_collect and pi.state == Interlock.State.AWAIT_COLLECT:
			pi.face_loaded = false
		var served_before: int = pi.served
		pi.step(DT)
		if pi.mouth_open():
			_check(pi._batch_lethal, "%s: opened the mouth on an unvalidated (raw) batch" % tag)
		if pi.served > served_before:
			_check(pi._batch_lethal, "%s: SERVED a batch whose cook was not proven lethal" % tag)


func _new_pi():
	var pi = Interlock.new()
	# short timings so the test runs fast
	pi.charge_seconds = 0.2
	pi.hydrate_seconds = 0.2
	pi.press_seconds = 0.2
	pi.cook_seconds = 0.3
	pi.clean_seconds = 0.3
	pi.stroke_seconds = 0.3
	return pi


func _initialize() -> void:
	print("== SeedCell process interlock self-test ==")

	# Scenario 1 -- a good batch on a clean, ready machine MUST be served (liveness).
	var p1 = _new_pi()
	p1.request = true
	p1.cook_ok = true
	_run(p1, 300, "S1 good batch")
	_check(p1.served >= 1, "S1: a valid batch was never served (liveness)")
	_check(p1.wasted == 0, "S1: wasted a batch that should have been served")

	# Scenario 2 -- under-cooked batch: the kill-step is NOT proven, so it must be
	# diverted to waste and NEVER presented to a person (the core safety property).
	var p2 = _new_pi()
	p2.request = true
	p2.cook_ok = false
	_run(p2, 300, "S2 under-cooked")
	_check(p2.served == 0, "S2: served an under-cooked batch (must never happen)")
	_check(p2.wasted >= 1, "S2: under-cooked batch was not diverted to waste")

	# Scenario 3 -- a safety-relevant sensor fault: fail safe, make no food.
	var p3 = _new_pi()
	p3.request = true
	p3.cook_ok = true
	p3.sensor_fault = true
	_run(p3, 300, "S3 sensor fault")
	_check(p3.served == 0, "S3: served despite a sensor fault (must fail safe)")

	# Scenario 4 -- surfaces cannot be verified clean: never serve, and eventually
	# LOCK OUT rather than dispensing onto an unsanitized food-contact surface.
	var p4 = _new_pi()
	p4.request = true
	p4.cook_ok = true
	p4.sanitized = false          # start dirty
	p4.surface_sanitized = false  # and cleaning never verifies
	_run(p4, 600, "S4 cannot sanitize")
	_check(p4.served == 0, "S4: served without ever proving the surfaces clean")
	_check(p4.state == Interlock.State.LOCKOUT,
		"S4: did not lock out when it could not sanitize (state=%d)" % p4.state)

	# Scenario 5 -- SF4 mouth guard: a pinch/jam (or too-hot surface) during delivery
	# must ABORT the present stroke -- never push a serving through a hand or a burn.
	var p5 = _new_pi()
	p5.request = true
	p5.cook_ok = true
	p5.contact_over_limit = true   # mouth force over the safe cap, from the start
	var saw_present := false
	for i in 600:
		if p5.state == Interlock.State.AWAIT_COLLECT:
			p5.face_loaded = false
		p5.step(DT)
		if p5.state == Interlock.State.PRESENT:
			saw_present = true
		_check(p5.progress <= 0.999,
			"S5: piston pushed fully through the mouth while a pinch trip was active")
	_check(saw_present, "S5: never reached a PRESENT attempt to test the abort")
	_check(p5.served == 0, "S5: completed a delivery through an active pinch trip")

	if failures == 0:
		print("PASS: interlock held (a raw or unclean batch is never served; a good one is).")
		quit(0)
	else:
		print("FAILED: %d assertion(s)." % failures)
		quit(1)
