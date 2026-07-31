extends SceneTree
## Headless self-test for the SF5 soft motion profile.
## Run:  Godot_v4.7.1 --headless --path godot --script res://tests/test_soft_profile.gd
## Exits 0 on pass, 1 on any failure.

const Profile := preload("res://soft_profile.gd")

var failures: int = 0


func _check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		push_error("FAIL: " + msg)
		print("  FAIL: ", msg)


func _initialize() -> void:
	print("== SeedCell soft-profile self-test ==")
	var sp = Profile.new()

	# Velocity envelope: never zero (motion always completes), never above cruise.
	for i in 101:
		var p := float(i) / 100.0
		var v := sp.velocity(p)
		_check(v >= sp.v_min - 1e-6, "velocity below the floor at p=%.2f (%.3f)" % [p, v])
		_check(v <= 1.0 + 1e-6, "velocity above cruise at p=%.2f (%.3f)" % [p, v])

	# Ends are soft (reduced speed at start and finish vs mid-travel).
	_check(sp.velocity(0.0) < sp.velocity(0.5), "no soft-start (v0 >= v_mid)")
	_check(sp.velocity(1.0) < sp.velocity(0.5), "no soft-stop (v_end >= v_mid)")

	# Final approach is speed-limited (lower contact energy at the mouth).
	_check(sp.velocity(0.95) <= sp.approach_ratio + 1e-6, "final approach not speed-limited")

	# advance(): monotonic, reaches 1.0, and takes ~duration seconds.
	var duration := 5.0
	var dt := 1.0 / 240.0
	var p := 0.0
	var last := -1.0
	var elapsed := 0.0
	var guard := 0
	while p < 1.0 and guard < 1000000:
		var np: float = sp.advance(p, dt, duration)
		_check(np >= last - 1e-6, "advance() went backwards")
		last = p
		p = np
		elapsed += dt
		guard += 1
	_check(p >= 1.0 - 1e-6, "advance() never reached 1.0")
	_check(abs(elapsed - duration) < 0.5, "advance() timing off: %.2fs vs %.2fs" % [elapsed, duration])

	if failures == 0:
		print("PASS: soft profile is bounded, soft-ended, speed-limited on approach, and completes on time.")
		quit(0)
	else:
		print("FAILED: %d assertion(s)." % failures)
		quit(1)
