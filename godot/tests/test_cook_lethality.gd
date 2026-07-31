extends SceneTree
## Headless self-test for the SF1 cook-lethality voter (ADR-0009).
## Run:  Godot_v4.7.1 --headless --path godot --script res://tests/test_cook_lethality.gd
## Exits 0 on pass, 1 on any failure.
##
## Mirrors the sibling HiveCell occupancy-fusion test, inverted: instead of "empty only
## when every channel positively reads clear", here "cooked only when every channel
## positively confirms the kill-step", and any fault reads UNSAFE (never "cooked").

const Fusion := preload("res://cook_lethality.gd")
const DT := 1.0 / 60.0

var failures: int = 0


func _fail(msg: String) -> void:
	failures += 1
	push_error("FAIL: " + msg)
	print("  FAIL: ", msg)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_fail(msg)


func _all_confirm(f) -> void:
	for c in f.channels:
		c.confirmed = true
		c.healthy = true
		c.plausible = true
		c.age = 0.0


func _initialize() -> void:
	print("== SeedCell cook-lethality self-test ==")

	# Baseline: every channel confirms & fresh => confirmed, not unsafe.
	var f = Fusion.new()
	_all_confirm(f)
	_check(f.confirmed(), "baseline: all channels confirm but confirmed() is false")
	_check(not f.unsafe(), "baseline: all channels confirm but unsafe() is true")

	# AND toward safe: a single dissenting channel withholds the serving.
	for i in f.channels.size():
		_all_confirm(f)
		f.channels[i].confirmed = false
		_check(not f.confirmed(), "one DENY on '%s' still read as confirmed" % f.channels[i].name)
		_check(f.unsafe(), "one DENY on '%s' did not read unsafe" % f.channels[i].name)

	# Fault = unsafe: every fault mode on every channel forces "not cooked".
	for i in f.channels.size():
		for mode in 3:
			_all_confirm(f)
			match mode:
				0: f.channels[i].healthy = false      # hardware fault
				1: f.channels[i].plausible = false     # railed / disconnected
				2: f.channels[i].age = 999.0           # stale
			_check(not f.confirmed(), "fault mode %d on '%s' read as confirmed" % [mode, f.channels[i].name])
			_check(f.unsafe(), "fault mode %d on '%s' did not read unsafe" % [mode, f.channels[i].name])

	# Staleness over time: unrefreshed channels go stale -> unsafe; refreshing all clears it.
	_all_confirm(f)
	for s in 200:  # ~3.3 s at DT, past max_stale (2.0)
		f.tick(DT)
	_check(f.unsafe(), "stale (unrefreshed) channels did not read unsafe")
	for c in f.channels:
		f.refresh(c.name)
	_check(f.confirmed(), "refreshing every channel did not restore confirmed()")

	# Exhaustive invariant across all 3^4 vote combinations of (confirm / deny / fault):
	# confirmed() must be true ONLY when every channel is CONFIRM, and unsafe() == not confirmed().
	var n: int = f.channels.size()
	var combos: int = 1
	for k in n:
		combos *= 3
	for mask in combos:
		var m := mask
		var expect_all := true
		for i in n:
			var v := m % 3
			m /= 3
			var c = f.channels[i]
			c.confirmed = true; c.healthy = true; c.plausible = true; c.age = 0.0
			match v:
				0: pass                      # CONFIRM
				1: c.confirmed = false        # DENY
				2: c.healthy = false          # FAULT
			if v != 0:
				expect_all = false
		_check(f.confirmed() == expect_all, "combo %d: confirmed() != (all CONFIRM)" % mask)
		_check(f.unsafe() == (not expect_all), "combo %d: unsafe() != not confirmed()" % mask)

	# The module's own runtime self-test hook.
	_check(Fusion.self_test(), "CookLethality.self_test() returned false")

	if failures == 0:
		print("PASS: lethality voting is fail-safe (cooked only when every channel proves it).")
		quit(0)
	else:
		print("FAILED: %d assertion(s)." % failures)
		quit(1)
