extends RefCounted
class_name LethalityModel
## SF1 kill-step TARGET and F-value integrator (ADR-0015; refines ADR-0009).
##
## ADR-0009 fixed the fail-safe VOTING architecture but left the actual criterion as a
## guessed "75 C core". That number is not a kill-step: it names a temperature and says
## nothing about how long it is held, and nothing about what a 68 C cook is worth. This
## module replaces it with the standard thermal-death model, so "cooked" becomes a
## quantity the ft_integrator channel can positively prove.
##
## THE MODEL. Microbial thermal death is log-linear in time and log-linear in
## temperature. Lethality accrues at a rate relative to a reference temperature:
##
##     rate(T) = 10 ^ ((T - T_REF) / Z_VALUE)          [dimensionless]
##     F       = integral of rate(T(t)) dt             [seconds at T_REF]
##
## F is therefore "equivalent seconds held at T_REF". The batch is cooked when F reaches
## TARGET_LOG decimal reductions of the reference organism, i.e. F >= F_TARGET.
##
## THE TARGET ORGANISM is Salmonella spp. It is the controlling vegetative pathogen for
## cereal/legume flours (the flour-recall pathogen, alongside E. coli O157:H7, which is
## less heat-resistant and is covered by the same margin). The dough core is HYDRATED
## during the bake, so moist-heat resistance applies; the dry-flour boundary layer
## (ADR-0008) is a crust-side film that sees platen temperature directly.
##
## THE NUMBERS are taken from the FDA Food Code 3-401.11 cooking table, which encodes a
## 7-log Salmonella reduction across two rows: 63 C for 3 minutes and 66 C for 1 minute.
## Both the D-value and z are FITTED to those two rows, so the model reproduces the
## regulatory table exactly rather than approximating it:
##
##     z = (66 - 63) / log10(180 / 60) = 6.29 C
##
## A first pass used a round literature z of 6.0 C. It was rejected: it undercuts the
## Food Code's own 66 C row by 5% (57 s demanded where the table says 60 s), i.e. it is
## LENIENT against the regulation it claims to encode. The fitted z lands inside the
## published moist-heat Salmonella range (5.0-6.5 C), so nothing is being stretched to
## make the fit work -- both self_test() and tests/test_lethality_model.gd assert this.
##
## WHAT THIS DOES NOT COVER -- read before trusting it:
##   * BACILLUS CEREUS SPORES. Endemic to rice/cereal/legume flours and NOT killed by any
##     bake this machine can perform; spore D121 is minutes at retort temperature. The
##     control is not lethality, it is TIME: serve immediately, never hold warm. The
##     60 C accumulation floor below exists partly for this -- see the comment there.
##   * The COLDEST POINT. F must be integrated from the coldest point of the batch, not
##     an average and not the platen. Probe placement is the hardware-side open item.
##   * VALIDATION. These are literature/regulatory values for a design model. A served
##     product needs its own challenge study; see docs/SAFETY.md "Open items".

# --- the thermal-death constants ------------------------------------------------
const T_REF := 70.0              ## C   reference temperature; F is quoted as F70
const Z_VALUE := 6.29            ## C   temperature change for a 10x change in D.
                                 ##     FITTED to the two Food Code rows below, not
                                 ##     chosen; sits inside the published moist-heat
                                 ##     Salmonella range of 5.0-6.5 C. A larger z is
                                 ##     also the conservative direction here, since the
                                 ##     bake banks its F above T_REF where a larger z
                                 ##     earns lethality credit more slowly.
const Z_RANGE_MIN := 5.0         ## C   published moist-heat Salmonella range, asserted
const Z_RANGE_MAX := 6.5         ## C   in self_test() so a future edit cannot drift out

# Regulatory anchors: FDA Food Code 3-401.11, both rows == 7-log Salmonella.
const ANCHOR_T := 63.0           ## C   primary anchor, sets the D-value
const ANCHOR_SECONDS := 180.0    ## s
const ANCHOR2_T := 66.0          ## C   second anchor, sets z with the first
const ANCHOR2_SECONDS := 60.0    ## s
const TARGET_LOG := 7.0          ## log10 reductions of Salmonella required to serve

## D-value at the anchor temperature, then transposed to T_REF by the z-model.
const D_ANCHOR := ANCHOR_SECONDS / TARGET_LOG                     ## s  (~25.7 s at 63 C)

## Accumulation floor. Below this, lethality credit is DISCARDED rather than integrated.
## The model says 55 C accrues a little lethality, and mathematically that is true -- but
## reaching F_TARGET purely by dwelling at 55 C would take ~80 minutes sitting in the
## bacterial growth zone, which is a spoiled batch that the model would have called
## "cooked". Refusing sub-60 C credit makes a marginal cook read as a FAILED cook, which
## is the direction that diverts to waste. Fail-safe beats mathematically complete.
const T_FLOOR := 60.0            ## C   no lethality credit accrues below this

## Plausibility band for a core reading. Outside it the sample is a sensor fault, not
## data: it is discarded AND the batch is flagged suspect (see Integrator.suspect).
const T_MIN_PLAUSIBLE := -20.0   ## C   below this the probe is disconnected/railed low
const T_MAX_PLAUSIBLE := 300.0   ## C   above this it is railed high / touching a platen


## D-value at an arbitrary temperature [s]: time for one decimal reduction.
static func d_value(temp_c: float) -> float:
	return D_ANCHOR * pow(10.0, (ANCHOR_T - temp_c) / Z_VALUE)


## F-value target [equivalent seconds at T_REF] for the required log reduction.
static func f_target() -> float:
	return TARGET_LOG * d_value(T_REF)


## Instantaneous lethal rate at a temperature, in equivalent-seconds-at-T_REF per second.
## Returns 0.0 below the accumulation floor (see T_FLOOR).
static func lethal_rate(temp_c: float) -> float:
	if temp_c < T_FLOOR:
		return 0.0
	return pow(10.0, (temp_c - T_REF) / Z_VALUE)


## Seconds of HOLD at a constant temperature needed to reach the target. INF below the
## floor. This is the function that turns the target back into something a human can
## sanity-check against a cooking table.
static func hold_seconds_required(temp_c: float) -> float:
	var rate := lethal_rate(temp_c)
	if rate <= 0.0:
		return INF
	return f_target() / rate


## Is a temperature sample usable as data at all?
static func plausible(temp_c: float) -> bool:
	if is_nan(temp_c) or is_inf(temp_c):
		return false
	return temp_c >= T_MIN_PLAUSIBLE and temp_c <= T_MAX_PLAUSIBLE


## Per-batch F-value accumulator -- the `ft_integrator` channel's physics.
##
## Fail-safe by construction: it only ever ADDS credit for samples it can justify, and a
## single implausible sample latches `suspect` for the whole batch, which makes
## reached() false no matter how much F was banked. Reset per batch, never across one.
class Integrator extends RefCounted:
	var f_value := 0.0        ## accumulated equivalent seconds at T_REF
	var suspect := false      ## a sample was implausible => this batch cannot be proven
	var samples := 0          ## samples integrated (0 => nothing was ever measured)
	var peak_c := -INF        ## hottest plausible sample seen (diagnostics)

	## Integrate one sample of the COLDEST-POINT temperature over dt seconds.
	func accumulate(temp_c: float, dt: float) -> void:
		if dt <= 0.0:
			return
		if not LethalityModel.plausible(temp_c):
			suspect = true          # latched: a blind spot in the trace is never "cooked"
			return
		samples += 1
		peak_c = max(peak_c, temp_c)
		f_value += LethalityModel.lethal_rate(temp_c) * dt

	## Has this batch positively proven its kill-step?
	func reached() -> bool:
		if suspect or samples == 0:
			return false
		return f_value >= LethalityModel.f_target()

	## Fraction of the target accumulated, for UI / telemetry. Not a safety read.
	func progress() -> float:
		return clampf(f_value / LethalityModel.f_target(), 0.0, 1.0)

	## New batch. MUST be called between batches -- banked F is per-batch, never carried.
	func reset() -> void:
		f_value = 0.0
		suspect = false
		samples = 0
		peak_c = -INF


## Runtime self-test. Checks the model against the regulatory table it is anchored on,
## then checks the integrator's fail-safe behaviour. Returns true on pass.
static func self_test() -> bool:
	# 1. The anchor reproduces itself: 7-log at 63 C takes 180 s.
	if absf(TARGET_LOG * d_value(ANCHOR_T) - ANCHOR_SECONDS) > 0.01:
		return false

	# 2. Second regulatory row: 66 C for 1 minute. z is fitted to make this exact, so
	#    this catches an edit to z/anchors that silently breaks the fit.
	if absf(hold_seconds_required(ANCHOR2_T) - ANCHOR2_SECONDS) > 0.5:
		return false

	# 3. The fitted z must still be a physically published value, not whatever number
	#    happened to make the table line up.
	var z_fit := (ANCHOR2_T - ANCHOR_T) / (log(ANCHOR_SECONDS / ANCHOR2_SECONDS) / log(10.0))
	if absf(z_fit - Z_VALUE) > 0.02:
		return false
	if Z_VALUE < Z_RANGE_MIN or Z_VALUE > Z_RANGE_MAX:
		return false

	# 4. The target is more conservative at 70 C than the Food Code's rounded
	#    "<1 second" row, i.e. we demand a real, measurable hold.
	if hold_seconds_required(T_REF) < 5.0:
		return false

	# 5. Monotonicity: hotter must never require longer.
	var prev := INF
	for i in 60:
		var t := 60.0 + float(i)
		var need := hold_seconds_required(t)
		if need > prev:
			return false
		prev = need

	# 6. Floor: no credit accrues below T_FLOOR, however long it dwells.
	var cold := Integrator.new()
	for i in 100000:
		cold.accumulate(T_FLOOR - 0.1, 0.1)     # ~2.8 hours just under the floor
	if cold.f_value != 0.0 or cold.reached():
		return false

	# 7. A real bake reaches the target; a short one does not.
	var hot := Integrator.new()
	hot.accumulate(100.0, 1.0)                   # 1 s at boiling core
	if not hot.reached():
		return false
	var brief := Integrator.new()
	brief.accumulate(T_REF, 1.0)                 # 1 s at the reference temp
	if brief.reached():
		return false

	# 8. Fault latching: one implausible sample poisons an otherwise-passing batch.
	var faulted := Integrator.new()
	faulted.accumulate(100.0, 10.0)
	faulted.accumulate(NAN, 0.1)
	if faulted.reached():
		return false
	# ... and a reset clears it.
	faulted.reset()
	if faulted.reached() or faulted.f_value != 0.0 or faulted.suspect:
		return false

	# 9. Nothing measured is never "cooked".
	var empty := Integrator.new()
	if empty.reached():
		return false

	return true
