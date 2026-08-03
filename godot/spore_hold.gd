extends RefCounted
class_name SporeHold
## SF7 bake->serve hold guard: the Bacillus cereus control (ADR-0016).
##
## ADR-0015 set the SF1 kill-step and, in doing so, named the hazard it CANNOT touch.
## B. cereus is endemic to cereal and legume flours, and its spores survive any bake this
## machine can perform -- spore D-values are minutes at retort temperature, against a bake
## measured in seconds. No accumulated F-value reaches them. Worse, the emetic toxin
## (cereulide) is heat-stable, so even a re-bake cannot undo the damage once it is made.
##
## THE CONTROL IS THEREFORE TIME, NOT HEAT. Surviving spores germinate and outgrow once
## the product cools out of the hot-holding band. So this guard does not ask "is it hot
## enough" -- SF1 already did. It asks "how long has this batch been cool enough to grow",
## and forces a batch that has waited too long to waste.
##
## WHY A TEMPERATURE-GATED CLOCK, NOT A WALL CLOCK. Time spent above HOT_HOLD_C is not
## dangerous: outgrowth is suppressed there. Only time BELOW it accrues risk. A plain
## wall-clock timer would either condemn a batch still sitting hot in the bore, or -- much
## worse -- give the same budget to a batch that cooled fast as to one that stayed hot.
## Integrating only the sub-threshold time is both the physically honest reading and the
## one that fails in the right direction when a heater dies.
##
## SCOPE. This guards the bake -> collection interval for ONE batch. It is not a shelf-life
## model, and it says nothing about the dry ingredients upstream (SF6) or about surface
## sanitation between batches (SF2, ADR-0010).

## Hot-holding threshold. Above this, B. cereus outgrowth is suppressed and no risk time
## accrues. Deliberately the same 60 C as LethalityModel.T_FLOOR: one number for "the
## temperature at which biology stops", used as a floor for lethality credit there and as
## a ceiling for risk accrual here. It also sits at the top of the conventional hot-hold
## band (57-60 C), so the choice is defensible from both directions.
const HOT_HOLD_C := 60.0

## The budget: seconds a batch may spend below HOT_HOLD_C before it is waste, not food.
##
## THIS IS A FACILITY-LEVEL PARAMETER (docs/SAFETY.md "Responsibility"): the device
## enforces it, it does not choose it. The default is deliberately far tighter than the
## regulatory ceiling for time-as-a-public-health-control (4 hours at ambient, after which
## discard is mandatory), for a reason specific to this machine: SeedCell bakes ON DEMAND,
## so the normal bake->collect interval is on the order of ten seconds. 15 minutes is
## already ~90x the nominal case. A batch that exceeds it has not been "waiting" -- it has
## been STUCK, and a stuck batch is exactly the one that should never be handed to anyone.
const DEFAULT_MAX_HOLD_S := 900.0

var max_hold_s := DEFAULT_MAX_HOLD_S

## Seconds accrued below the hot-hold threshold for the batch currently in the machine.
var elapsed := 0.0

## Has a batch been armed for this guard? A batch that reaches the serve gate without the
## guard having been armed at end-of-cook is a CONTROL-FLOW fault, not a fresh batch, and
## servable() refuses it. Absence of a clock is never "the clock says fine".
var armed := false

## Latched: a temperature sample was unusable at some point during this batch. The clock
## kept running (see tick), but the batch is additionally marked unprovable.
var suspect := false

## Peak risk-time reached, for telemetry after a reset.
var last_elapsed := 0.0


## Arm the guard at END OF COOK -- the moment the batch becomes food that can spoil.
func start_hold() -> void:
	armed = true
	elapsed = 0.0
	suspect = false


## Advance the guard by dt using the batch's current temperature.
##
## Fail-safe on both axes. An unusable sample (NAN/INF/out of band) does NOT pause the
## clock: it accrues risk time as if the batch were cold, AND latches suspect. A dead
## thermometer must never be able to buy a batch unlimited holding time -- the failure of
## a sensor is precisely when a batch is most likely to be sitting forgotten.
func tick(delta: float, temp_c: float) -> void:
	if delta <= 0.0 or not armed:
		return
	if not LethalityModel.plausible(temp_c):
		suspect = true
		elapsed += delta          # unknown temperature is treated as cool
		return
	if temp_c < HOT_HOLD_C:
		elapsed += delta


## Has the batch outlived its budget?
func expired() -> bool:
	return armed and elapsed >= max_hold_s


## May this batch still be handed to a person? Requires an armed, unexpired, unsuspect
## guard -- all three, all in the safe direction.
func servable() -> bool:
	return armed and not expired() and not suspect


## Fraction of the budget consumed, for UI / telemetry. Not a safety read.
func fraction() -> float:
	if max_hold_s <= 0.0:
		return 1.0
	return clampf(elapsed / max_hold_s, 0.0, 1.0)


## Batch left the machine (served or diverted). Disarms until the next end-of-cook.
func reset() -> void:
	last_elapsed = elapsed
	armed = false
	elapsed = 0.0
	suspect = false


## Runtime self-test. Returns true on pass.
static func self_test() -> bool:
	var g := SporeHold.new()

	# Unarmed is never servable -- no clock is not a passing clock.
	if g.servable() or g.expired():
		return false

	# Hot holding accrues nothing, however long.
	g.start_hold()
	for i in 100000:
		g.tick(0.1, HOT_HOLD_C + 5.0)        # ~2.8 hours held hot
	if g.elapsed != 0.0 or g.expired() or not g.servable():
		return false

	# Cool holding accrues, and expires exactly at the budget. Stepped in 0.5 s -- an
	# exactly-representable binary fraction -- so the boundary check is testing the
	# guard's comparison rather than float accumulation error.
	g.start_hold()
	g.max_hold_s = 10.0
	for i in 19:
		g.tick(0.5, 20.0)                    # 9.5 s cool
	if g.expired() or not g.servable():
		return false
	g.tick(0.5, 20.0)                        # 10.0 s -- the budget, exactly
	if not g.expired() or g.servable():
		return false

	# A dead sensor accrues risk time rather than pausing the clock.
	g.start_hold()
	g.max_hold_s = 10.0
	for i in 200:
		g.tick(0.1, NAN)
	if not g.expired() or not g.suspect or g.servable():
		return false

	# Suspect alone withholds a batch even well inside the budget.
	g.start_hold()
	g.max_hold_s = 1000.0
	g.tick(0.1, INF)
	if g.expired() or g.servable():
		return false

	# Reset disarms and clears.
	g.reset()
	if g.armed or g.elapsed != 0.0 or g.suspect or g.servable():
		return false

	# Boundary: the threshold itself is hot enough (>= is safe, < accrues).
	g.start_hold()
	g.max_hold_s = 1.0
	for i in 100:
		g.tick(0.1, HOT_HOLD_C)
	if g.expired():
		return false

	return true
