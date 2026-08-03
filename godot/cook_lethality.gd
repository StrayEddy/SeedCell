extends RefCounted
class_name CookLethality
## SF1 cook-lethality voter (ADR-0009) -- the PRIMARY food-safety safeguard.
##
## SeedCell's analog of HiveCell's occupancy fusion, inverted: instead of proving a
## space is EMPTY before moving, it must positively prove a batch reached its
## pathogen kill-step (a validated core temperature held for a validated time,
## i.e. an accumulated lethality F-value) before that batch may be PRESENTED to a
## person. Diverse-redundant, fail-safe voting:
##   - AND toward safe  -- serve only when EVERY channel positively confirms the
##                         kill-step. One dissenting or silent channel is enough to
##                         withhold the serving.
##   - fault = unsafe   -- any channel faulted, out-of-range, or stale reads
##                         "not lethal". Absence of proof of a cook is never "cooked".
##   - diversity        -- two independent core probes + a surface pyrometer + an
##                         independent time-temperature integrator fail differently,
##                         so no single common-cause fault can wave a raw batch through.
## Pure + headless-testable; no scene dependency. A failed vote never crashes the
## line -- it diverts the batch to waste (see process_interlock.gd), never to a person.

enum Vote { CONFIRM, DENY, FAULT }   # CONFIRM = this channel positively sees the kill-step met


## One diverse lethality channel. `confirmed` is the channel's raw reading (kill-step
## reached); a channel only counts as CONFIRM if it is also healthy, plausible, and fresh.
class Channel:
	var name := ""
	var confirmed := false     ## sensor positively reads the kill-step reached
	var healthy := true        ## hardware / self-test OK
	var plausible := true      ## reading in range, not railed / disconnected
	var age := 0.0             ## seconds since last fresh sample
	var max_stale := 2.0       ## older than this => stale => fault

	func _init(n: String) -> void:
		name = n

	func vote() -> int:
		if not healthy or not plausible or age > max_stale:
			return Vote.FAULT           # fault reads UNSAFE -- never "cooked"
		return Vote.CONFIRM if confirmed else Vote.DENY


var channels: Array[Channel] = []

## SF1 kill-step model (ADR-0015). While null, the `ft_integrator` channel is driven by
## hand -- which is what the pure-logic voting tests do. Once integrate() is called, that
## channel stops being an opinion and becomes a measured F-value: it confirms only when
## the accumulated lethality clears LethalityModel.f_target().
var integrator: LethalityModel.Integrator = null


func _init() -> void:
	# Diverse physics so no single common cause blinds the kill-step:
	channels = [
		Channel.new("core_probe_a"),   # embedded thermocouple, dough core
		Channel.new("core_probe_b"),   # second, independent core thermocouple (redundant)
		Channel.new("ir_surface"),     # non-contact surface pyrometer (crust temperature)
		Channel.new("ft_integrator"),  # independent time-temperature lethality (F-value) accumulator
	]


func get_channel(n: String) -> Channel:
	for c in channels:
		if c.name == n:
			return c
	return null


## AND toward safe: the batch is lethal-confirmed only when EVERY channel votes CONFIRM.
func confirmed() -> bool:
	for c in channels:
		if c.vote() != Vote.CONFIRM:
			return false
	return true


## Fail-safe read used by the interlock: true if the batch is NOT provably cooked
## (any DENY or FAULT). This is the direction that withholds a serving.
func unsafe() -> bool:
	return not confirmed()


## Age every channel one frame. Unrefreshed channels go stale -> fault -> unsafe.
func tick(delta: float) -> void:
	for c in channels:
		c.age += delta


## A sensor produced a fresh sample: reset its staleness clock.
func refresh(n: String) -> void:
	var c := get_channel(n)
	if c != null:
		c.age = 0.0


## Feed the batch's COLDEST-POINT core temperature to the F-value channel (ADR-0015).
## Pass the lowest of the core probes, never a mean and never the platen: lethality is
## only proven where the batch is coldest. Drives `ft_integrator` from real physics --
## confirmed when F clears the target, implausible (=> FAULT => unsafe) if any sample in
## this batch was out of band.
func integrate(coldest_core_c: float, dt: float) -> void:
	if integrator == null:
		integrator = LethalityModel.Integrator.new()
	integrator.accumulate(coldest_core_c, dt)
	var c := get_channel("ft_integrator")
	if c != null:
		c.confirmed = integrator.reached()
		c.plausible = not integrator.suspect
		c.age = 0.0


## Lowest reading among the core probes -- the coldest point as measured. Returns NAN for
## an empty set, which integrate() then treats as an implausible sample (fail-safe).
static func coldest(core_temps: Array) -> float:
	if core_temps.is_empty():
		return NAN
	var lo: float = INF
	for t in core_temps:
		lo = min(lo, float(t))
	return lo


## Start a new batch: banked lethality is per-batch and is NEVER carried across one.
## The channel is dropped back to "not cooked" in the same breath.
func new_batch() -> void:
	if integrator != null:
		integrator.reset()
	var c := get_channel("ft_integrator")
	if c != null:
		c.confirmed = false


## Accumulated equivalent seconds at the reference temperature, for telemetry/UI.
func f_value() -> float:
	return integrator.f_value if integrator != null else 0.0


## Runtime self-test: exhaustively drive every channel's vote and assert the two
## invariants that matter -- (1) confirmed() only when ALL channels CONFIRM, and
## (2) any single fault forces unsafe(). Mirrors OccupancyFusion.self_test() in the
## sibling project. Returns true on pass.
static func self_test() -> bool:
	var f := CookLethality.new()
	# All confirming & fresh => confirmed, not unsafe.
	for c in f.channels:
		c.confirmed = true
		c.age = 0.0
	if not f.confirmed() or f.unsafe():
		return false
	# Each channel, each fault mode, must force unsafe (fault = not cooked).
	for i in f.channels.size():
		for mode in 4:
			for c in f.channels:
				c.confirmed = true; c.healthy = true; c.plausible = true; c.age = 0.0
			match mode:
				0: f.channels[i].confirmed = false     # channel says "not cooked"
				1: f.channels[i].healthy = false        # hardware fault
				2: f.channels[i].plausible = false      # railed / disconnected
				3: f.channels[i].age = 999.0            # stale
			if f.confirmed() or not f.unsafe():
				return false
	return true
