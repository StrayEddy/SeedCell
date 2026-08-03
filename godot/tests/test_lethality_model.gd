extends SceneTree
## Headless self-test for the SF1 kill-step target + F-value integrator (ADR-0015).
## Run:  Godot_v4.7.1 --headless --path godot --script res://tests/test_lethality_model.gd
## Exits 0 on pass, 1 on any failure.
##
## Two things are under test here, and they fail for different reasons:
##   1. The MODEL is the right shape and reproduces the regulatory table it claims to
##      encode (FDA Food Code 3-401.11). A wrong z or a wrong anchor shows up here.
##   2. The INTEGRATOR is fail-safe: it refuses credit it cannot justify, it latches on
##      sensor faults, and it never carries lethality from one batch into the next.
## Neither proves the food is safe -- that needs a challenge study (docs/SAFETY.md).

const Model := preload("res://lethality_model.gd")
const Lethality := preload("res://cook_lethality.gd")

var failures: int = 0


func _fail(msg: String) -> void:
	failures += 1
	push_error("FAIL: " + msg)
	print("  FAIL: ", msg)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_fail(msg)


func _close(a: float, b: float, tol: float) -> bool:
	return absf(a - b) <= tol


func _initialize() -> void:
	print("== SeedCell cook-lethality TARGET self-test (ADR-0015) ==")

	# ---- 1. the model against the regulatory table -------------------------------
	# Anchor row, by construction: 63 C for 3 min == 7-log.
	_check(_close(Model.hold_seconds_required(Model.ANCHOR_T), 180.0, 0.5),
		"anchor row: 7-log at 63 C should need 180 s, got %.1f" % Model.hold_seconds_required(Model.ANCHOR_T))

	# Second row: Food Code 66 C / 1 min. z is fitted to make this exact, so any drift
	# here means the anchors or z were edited apart.
	var t66 := Model.hold_seconds_required(Model.ANCHOR2_T)
	_check(_close(t66, Model.ANCHOR2_SECONDS, 0.5),
		"Food Code 66 C row: expected 60 s, model says %.1f s (z or anchor is wrong)" % t66)

	# z is fitted, but it must still be a published moist-heat Salmonella value rather
	# than whatever number made the table line up.
	var z_fit: float = (Model.ANCHOR2_T - Model.ANCHOR_T) / (log(Model.ANCHOR_SECONDS / Model.ANCHOR2_SECONDS) / log(10.0))
	_check(_close(z_fit, Model.Z_VALUE, 0.02),
		"Z_VALUE %.3f does not match the fit from the two Food Code rows (%.3f)" % [Model.Z_VALUE, z_fit])
	_check(Model.Z_VALUE >= Model.Z_RANGE_MIN and Model.Z_VALUE <= Model.Z_RANGE_MAX,
		"fitted z %.2f fell outside the published 5.0-6.5 C range" % Model.Z_VALUE)

	# The published target itself.
	var ft := Model.f_target()
	_check(ft > 12.0 and ft < 16.0, "F70 target drifted out of the ~14 s band: %.2f s" % ft)
	print("  F%.0f target = %.2f equivalent seconds (%.0f-log Salmonella, z = %.1f C)"
		% [Model.T_REF, ft, Model.TARGET_LOG, Model.Z_VALUE])
	print("  hold required: 63 C %.0fs | 66 C %.0fs | 70 C %.1fs | 80 C %.2fs | 100 C %.4fs"
		% [Model.hold_seconds_required(63.0), t66, Model.hold_seconds_required(70.0),
		   Model.hold_seconds_required(80.0), Model.hold_seconds_required(100.0)])

	# Hotter is never slower.
	var prev := INF
	for i in 60:
		var need := Model.hold_seconds_required(60.0 + float(i))
		_check(need <= prev, "monotonicity broken at %.0f C" % (60.0 + float(i)))
		prev = need

	# ---- 2. the accumulation floor ------------------------------------------------
	# Dwelling just under the floor must earn NOTHING, however long. Without this a
	# batch could sit in the growth zone for ~80 min and be called cooked.
	var cold := Model.Integrator.new()
	for i in 60000:
		cold.accumulate(Model.T_FLOOR - 0.5, 0.1)   # ~100 minutes at 59.5 C
	_check(cold.f_value == 0.0, "sub-floor dwell accumulated F = %.3f (should be 0)" % cold.f_value)
	_check(not cold.reached(), "100 minutes at 59.5 C was reported as cooked")

	# ---- 3. a real bake, and a failed one ------------------------------------------
	# The normal case: a hydrated core plateaus near boiling, so the target is cleared
	# almost instantly. That is the intended property -- the F-value exists to catch the
	# FAILED cook, not to constrain the good one.
	var good := Model.Integrator.new()
	good.accumulate(98.0, 1.0)
	_check(good.reached(), "1 s at a 98 C core did not reach the target (F = %.1f)" % good.f_value)

	# The failure the old "75 C core" rule could not express: hot enough, far too brief.
	var brief := Model.Integrator.new()
	brief.accumulate(75.0, 0.5)
	_check(not brief.reached(), "0.5 s at 75 C was accepted; the 75 C rule's blind spot is back")
	# ... and the same temperature held long enough IS accepted.
	var held := Model.Integrator.new()
	for i in 100:
		held.accumulate(75.0, 0.1)                   # 10 s at 75 C
	_check(held.reached(), "10 s at 75 C should clear the target (F = %.1f)" % held.f_value)

	# A cook that stalls short of the kill-step.
	var stalled := Model.Integrator.new()
	for i in 600:
		stalled.accumulate(64.0, 0.1)                # 60 s at 64 C
	_check(not stalled.reached(), "60 s at 64 C was reported cooked (F = %.1f)" % stalled.f_value)

	# ---- 4. fail-safe integrator behaviour ------------------------------------------
	var empty := Model.Integrator.new()
	_check(not empty.reached(), "an unmeasured batch reported itself cooked")

	for bad in [NAN, INF, -273.0, 9999.0]:
		var f := Model.Integrator.new()
		f.accumulate(98.0, 10.0)                     # bank plenty of real lethality
		_check(f.reached(), "setup: 10 s at 98 C should have passed")
		f.accumulate(bad, 0.1)                       # one bad sample
		_check(f.suspect, "implausible sample %s did not latch suspect" % str(bad))
		_check(not f.reached(), "implausible sample %s did not withhold the batch" % str(bad))

	# Reset clears everything, including the latch.
	var reused := Model.Integrator.new()
	reused.accumulate(98.0, 10.0)
	reused.accumulate(NAN, 0.1)
	reused.reset()
	_check(reused.f_value == 0.0 and not reused.suspect and not reused.reached(),
		"reset() did not fully clear the batch state")

	# Zero / negative dt earns nothing.
	var dtz := Model.Integrator.new()
	dtz.accumulate(200.0, 0.0)
	dtz.accumulate(200.0, -5.0)
	_check(dtz.f_value == 0.0 and not dtz.reached(), "non-positive dt accumulated lethality")

	# ---- 5. wiring into the SF1 voter ------------------------------------------------
	# coldest() must pick the lowest probe, because that is where the kill is unproven.
	_check(Lethality.coldest([98.0, 71.0, 88.0]) == 71.0, "coldest() did not return the minimum")
	_check(is_nan(Lethality.coldest([])), "coldest([]) should be NAN so it reads as a fault")

	var voter = Lethality.new()
	for c in voter.channels:
		c.confirmed = true
		c.healthy = true
		c.plausible = true
		c.age = 0.0
	voter.new_batch()
	_check(not voter.confirmed(), "new_batch() left the F-value channel confirming")

	# Drive it from a plausible cook: the channel should flip on measured lethality alone.
	for i in 20:
		voter.integrate(Lethality.coldest([99.0, 97.5]), 0.1)
	for c in voter.channels:
		if c.name != "ft_integrator":
			c.confirmed = true; c.age = 0.0
	_check(voter.confirmed(), "a fully-cooked batch did not confirm through the voter")
	_check(voter.f_value() > Model.f_target(), "voter f_value() did not track the integrator")

	# A dead probe mid-batch must pull the whole vote unsafe via the channel's plausibility.
	voter.integrate(NAN, 0.1)
	_check(voter.unsafe(), "a dead core probe mid-batch did not force unsafe")

	# And a fresh batch starts from zero, never from the last one's credit.
	voter.new_batch()
	_check(voter.f_value() == 0.0, "new_batch() carried lethality across batches")
	_check(voter.unsafe(), "a fresh, uncooked batch did not read unsafe")

	# ---- 6. the modules' own runtime hooks --------------------------------------------
	_check(Model.self_test(), "LethalityModel.self_test() returned false")
	_check(Lethality.self_test(), "CookLethality.self_test() regressed")

	if failures == 0:
		print("PASS: kill-step target is anchored, floored, fail-safe, and per-batch.")
		quit(0)
	else:
		print("FAILED: %d assertion(s)." % failures)
		quit(1)
