# Engineering Decision Log

Append-only record of significant engineering decisions (an ADR — Architecture
Decision Record — log). Each entry: what we decided, why, and what it rules out.
Newest at the bottom. SeedCell is the food analog of the sibling
[HiveCell](../../HiveCell) project and deliberately reuses its workflow and conventions.

---

## ADR-0001 — Motion principle: the hot syringe (cook-in-bore, eject-through-mouth)
**Date:** 2026-07-31
**Status:** Accepted

**Decision.** SeedCell is a single heated piston moving inside a fixed heated tube
("bore"), directly mirroring HiveCell's true-syringe topology — but the product is a
flatbread ejected through the mouth, not a cavity presented to a person.
- Idle: the piston face sits flush at the mouth (the public wall plane, X=0), sealing
  the machine. The face IS the flush public wall — no separate door or shutter.
- Make: the piston retracts, opening a short cook chamber in the bore; dry blend is
  metered in and hydrated in place; the piston presses the dough into a thin disc and
  the two hot faces (bore-end/die + piston face) bake it.
- Deliver: the piston advances back toward the mouth and ejects the finished flatbread
  through the fixed mouth die (which shears/peels it free); the face returns to flush.
- Clean: the piston parks deep in a sealed sterilize zone where its face and the bore
  are scraped, steamed, heat-sterilized and dried before the next serving.

**Why.** Fewest moving parts (one primary piston, one drive) → best reliability, cost,
simplicity — the same reasoning that made HiveCell a syringe. Crucially, it collapses
the **food-contact surfaces to the absolute minimum**: the bore wall, the piston face,
and the mouth die lip — "one chamber, one transfer, one delivery surface" (the stated
design goal). The piston face does quadruple duty (flush wall + cook platen + delivery
surface + cleaning interface), exactly as HiveCell's piston is floor + door + squeegee.

**Rejected alternatives.**
- A — Conveyor/station line (dose → mix → press → griddle → deliver): a bakery in a
  box. Every transfer is another food-contact surface to clean; the opposite of the goal.
- B — Vending of pre-made items: not fresh, needs packaging, not the mission.
- C — Rotary drum / carousel of pans: most mechanism + many pans to clean.

**Accepted costs / constraints.** A few hidden service-side helpers may still be needed
(a mouth die, hydration jets, cleaning stations) — SeedCell will accrete them the way
HiveCell accreted spray rings and a service squeegee. The single-chamber ideal has a
real tension: charging + hydration ports are extra small contact points (see ADR-0006);
tracked, not hidden. Bore/piston dimensions are first-pass (`scripts/build_model.py`).

---

## ADR-0002 — Authoring workflow: code-first FreeCAD scripting
**Date:** 2026-07-31
**Status:** Accepted

**Decision.** The model is authored as git-tracked Python (`scripts/build_model.py`)
run headless via `freecadcmd`. The Python is the source of truth; `cad/SeedCell.FCStd`
is a generated build artifact. The GUI is used only to view/measure, never to hand-edit.

**Why.** Identical rationale to HiveCell ADR-0002 (same author, same toolchain): fast,
diffable, fully parametric, version-controlled, with a headless motion-preview path into
the Godot twin. Reusing the sibling project's proven workflow costs nothing to adopt.

**Regenerate command.**
`flatpak run --command=freecadcmd org.freecad.FreeCAD scripts/build_model.py`

---

## ADR-0003 — Cross-section: round bore (cylinder), not a capsule
**Date:** 2026-07-31
**Status:** Accepted

**Decision.** The bore is a plain circular cylinder; the flatbread is a disc.

**Why.** HiveCell needed a rounded-*rectangle* because a person lies on a flat floor.
SeedCell has no such constraint, so it takes the cylinder HiveCell's ADR-0001 originally
wanted: **no internal corners at all** → the easiest possible full-perimeter scraping
(a single circular lip wipes the entire bore), best hygiene, best vandal resistance, and
axisymmetric heating for an even bake. A disc flatbread is also the most natural hand
food. `boreDia = flatbreadDia + 2·runningClearance`; `pistonDia = boreDia − 2·clearance`.

---

## ADR-0004 — CookBarrel = fixed heated barrel, open at both ends
**Date:** 2026-07-31
**Status:** Accepted

**Decision.** `CookBarrel` is the fixed syringe barrel: a uniform-wall tube, open at the
mouth (X=0, public/delivery) and at the deep service end (X=barrelLength, sterilize +
drive). Its near-mouth band is a heated **griddle zone** (the front cook platen). The
wall carries the small charge/hydration ports (ADR-0006).

**Why.** An open-ended sleeve is the true syringe barrel and keeps each part
independently manufacturable, exactly as HiveCell ADR-0004. Heating only the near-mouth
band (not the whole 330 mm) concentrates thermal mass where the bake happens and where
sterilization heat is reused (ADR-0010). `wallThickness` 8 mm is structural/thermal TBD.

---

## ADR-0005 — Piston: the single heated moving part
**Date:** 2026-07-31
**Status:** Accepted

**Decision.** The `Piston` is a cylindrical plug riding in the bore on a
`runningClearance` (2 mm/side), scraper lips bridging the gap (SF3). Its flat front face
is a **heated cook platen** and, at full advance, the flush public wall. Modelled in the
DEPLOYED/flush pose (face at X=0); the whole mechanism's motion is this ONE part
translating +X by `stroke` — ideal for the digital twin (`godot/process_interlock.gd`).

**Why.** A running fit prevents binding; the lips scrape the bore and separate the public
mouth side from the sealed service side. Depth (`pistonLength` 120 mm) resists tilt/jam
and houses the face heater + its thermocouples (SF1 core probes, ADR-0009). One heated
moving part means one thing to clean and one thing that can fail — the syringe bargain.

**Placeholders.** Solid plug now; the face heater, embedded probes, and lightweighting
are later milestones. `pistonLength`, `runningClearance`, `chargeDepth` are tunable.

---

## ADR-0006 — Hydration by injection, not a mixer blade (mixing with no food-contact mover)
**Date:** 2026-07-31
**Status:** Accepted

**Context.** Research question #2: can mixing/pressing/cooking collapse into one chamber?
A stirring blade or auger would be a food-contact moving part with vanes, a shaft seal,
and crevices — a cleaning nightmare and a reliability risk, the exact thing the syringe
philosophy forbids.

**Decision.** Do the mixing with **fluid, not a blade.** Dry blend is metered into the
bore; then water (+ dissolved oil/salt/fortificant) is **injected as high-shear jets**
through a fixed ring (`HydrationRing`) into the dry powder. The jet turbulence hydrates
and mixes the dough in place. The piston then presses it. No rotating element, no shaft
into the food, no blade to clean — the mixer is a set of nozzles that only ever touch
clean water on the supply side.

**Why.** Removes the single worst food-contact moving part from the machine and keeps the
whole cook in one chamber. Jet hydration of flour is well-understood (continuous dough
systems, spray hydration). Reuses the same nozzle hardware the cleaning cycle wants
anyway (ADR-0010).

**Rejected alternatives.**
- Blade/paddle/auger mixer: food-contact mover + shaft seal + crevices. Rejected.
- Pre-mix a wet batter externally: reintroduces a wet reservoir that spoils and must be
  cleaned — breaks "everything upstream stays dry" (ADR-0012).

**Accepted costs / to verify.** Jet-only mixing may leave dry pockets or need a specific
flour grind / injection sequence; the piston's press adds kneading. The wall ports are
small extra food-contact points (ADR-0001 tension) — they are wiped by the passing seal
each stroke. Dough uniformity + hydration time are bench items (research question #1).

---

## ADR-0007 — Cook: two-sided conduction bake in the one chamber
**Date:** 2026-07-31
**Status:** Accepted

**Decision.** Cook by **conduction between two hot platens** — the heated bore-end/die
and the heated piston face — pressing the thin dough disc between them (a contact
griddle). No separate oven, no hot air, no radiant element in the food space.

**Why (quantified, `scripts/cook_energy.py`).** A thin flatbread is ideal for
conduction: at 8 mm thickness heated from both sides at 230 °C, the core clears a 75 °C
kill target in tens of seconds (Fourier analysis), and ~59 Wh/serving covers the bake.
Conduction reuses the *same* hot surfaces that (a) form the bread and (b) get
heat-sterilized during cleaning (ADR-0010) — one set of heated surfaces does forming,
cooking, and sanitizing. That is the single-chamber collapse research question #2 asked
for: **mix (ADR-0006) + press + cook all happen against the piston face and bore, with
no transfer.**

**Rejected alternatives.**
- Convection/impingement oven: hot-air ducting + fan = more surfaces + a fouling air path.
- Radiant/IR or microwave: uneven for a dense legume dough; adds emitters in the food zone.
- Deep-fry / steam-only: oil bath or water bath to maintain, spoil, and clean.

**Accepted costs / to verify.** Contact baking browns the two faces but not edges — fine
for a flatbread; verify crust/cook uniformity and that the core lethality (SF1) is met at
the geometric worst case (thickest/coldest point), not just the mean. The real control is
an accumulated time-temperature lethality (F-value), not a single set-point (ADR-0009).

---

## ADR-0008 — Anti-stick: low-adhesion face + sacrificial dry-flour boundary layer + self-releasing bread
**Date:** 2026-07-31
**Status:** Accepted

**Context.** Research questions #1 and #4: the least-sticky nutritionally-complete
flatbread, and designing the food itself to minimise residue. Dough sticking to the hot
surfaces is the whole hygiene problem: a stuck film cooks onto the platen and smears into
the next serving (H2 cross-contamination).

**Decision.** Attack stickiness three ways at once:
1. **Low-adhesion food-contact surface** — PTFE / seasoned-ceramic-coated stainless on the
   piston face + griddle band. Low work of adhesion so the bread lets go.
2. **A sacrificial dry-flour boundary layer** — the surfaces are dusted with dry flour
   *before* the dry blend + water arrive, so the wet dough contacts a flour film, never
   bare metal. The film bakes into the bread's own crust and **leaves with the bread** —
   like semolina on a pizza peel. The anti-stick consumable is just more of the food.
3. **A lean, self-releasing formula** — keep hydration and fat moderate and let the bake
   dry the crust so the disc *shrinks and self-releases* before the piston even ejects it.

**Why (quantified, `scripts/residue.py`).** A low-adhesion surface + flour boundary layer
drops the release stress and per-cycle residue by ~2 orders of magnitude vs bare hot
steel, into the µg/cm² range — plausibly self-cleanable every cycle. Designing the food
to leave (points 2–3) means the cleaning system (ADR-0010) starts from "almost clean",
not "scrub baked-on dough".

**Rejected / not chosen.** Oil-flood release (a fryer by another name; rancid film to
clean). Aggressive high-hydration dough for a softer bread (sticks hard; trends to the
residue HIGH case). Both revisitable if the bench test allows.

**Accepted costs / to verify.** PTFE/ceramic durability under repeated scraping + 230 °C
+ steam is a hard material spec (couples SF3 scraper aggressiveness). "Self-releasing"
and "µg/cm² residue" are asserted — **measure both on a real baked coupon**
(`docs/residue_bench_test.md`) before freezing the surface, the formula, and the cleaning
method. This is SeedCell's master-variable trap (ADR-0011).

---

## ADR-0009 — SF1 cook lethality is the primary safeguard: never present a batch that isn't provably cooked
**Date:** 2026-07-31
**Status:** Accepted (architecture + fail-safe logic); sensor part numbers + validation TBD

**Context.** SeedCell is HiveCell's mission inverted: HiveCell must never *move* until it
proves a space is empty; SeedCell must never *serve* until it proves a batch is cooked.
Both users are VULNERABLE — a homeless or food-insecure person eating a machine-made
ration daily, with no recourse if it makes them ill. A missed kill-step can cause
foodborne illness at scale. So the PRIMARY safeguard is the cook lethality check, and it
must fail safe: absence of proof of a cook is never "cooked".

**Decision.**
1. **The kill-step is proven, not assumed.** Every serving must reach a validated core
   time-temperature lethality (an accumulated F-value) before it may be presented. The
   gate lives in `godot/process_interlock.gd` (LETHALITY_CHECK → PRESENT or → DIVERT):
   **there is no "serve it anyway" branch.** A batch that fails is diverted to the waste
   chute, never to the mouth.
2. **Diverse-redundant, fail-safe voting** (`godot/cook_lethality.gd`), the direct analog
   of HiveCell's occupancy fusion (ADR-0012 there), inverted to "prove safe":
   - **AND toward safe** — serve only when EVERY channel positively confirms the kill-step.
   - **fault = unsafe** — any channel faulted, out-of-range, or stale reads "not cooked".
   - **diversity** — two independent core thermocouples + a surface pyrometer + an
     independent time-temperature (F-value) integrator, so no single common-cause fault
     can wave a raw batch through.
3. **SF4 mouth guard is separate** — even a perfectly cooked batch is not pushed through a
   hand (pinch) or served scalding (burn); the present stroke aborts if the mouth is
   unsafe (ADR-0011 mechanical, SAFETY.md SF4).

**Why.** No single temperature reading can be trusted for an unattended public food
machine running for years. Diverse redundancy + prove-safe + fault-is-unsafe is the only
way to a high-integrity kill-step. The twin already encodes the LOGIC and self-tests it
exhaustively (`tests/test_cook_lethality.gd`, all 3⁴ vote combinations); this ADR fixes
the architecture and the fail-safe direction.

**Rejected alternatives.**
- Single thermocouple / fixed timer: common-cause blind spots; a stuck probe serves raw.
- Camera / colour "doneness" AI as primary: opaque failure modes, hard to trust for a
  safety kill-step. Auxiliary at most.
- "Cook long enough and assume": no proof; drifts as ingredients/ambient change.

**Accepted costs / to verify.** Cost of 4 diverse channels + a rated controller — justified
by the every-serving vulnerable-user case. Validate F-value targets against a real
pathogen-lethality model for a low-moisture legume flatbread; set the target from food-
safety data, not a guessed 75 °C. Probe placement must read the geometric coldest point.
This is `[sim]` — logic + architecture, no physical probes yet.

---

## ADR-0010 — Cleaning: scrape + steam-sanitize + heat-sterilize + dry, in a sealed service-side chamber
**Date:** 2026-07-31
**Status:** Accepted (architecture + method); sizing, water/energy, sewer + freeze TBD

**Context.** Research question #3: clean every food-contact surface automatically after
each serving. SeedCell's advantage over HiveCell is that the contaminated area is tiny
(one bore + one face) and mostly DRY residue (baked crumbs + a µg film, ADR-0008), not
bodily fluids. The disadvantage: it must reach food-grade sanitation, every cycle, with
no human.

**Decision.** A four-step motion-driven cycle, all on the sealed service side (the piston
parks deep; nothing cleaning-related is on the public face — the HiveCell ADR-0016 lesson):
1. **Scrape (mechanical).** The piston's own circular scraper lips (SF3) wipe the full
   bore perimeter as it retracts — the syringe-native squeegee — pushing dry crumbs to a
   waste path. This alone removes the bulk, because the food was designed to leave (ADR-0008).
2. **Steam / hot-water sanitize** (`SterilizeRing`) — a fixed ring wets + thermally
   sanitizes the parked face and bore band.
3. **Heat-sterilize (nearly free).** The griddle surfaces are ALREADY at ~230 °C from the
   bake; holding them hot dry-heat-sterilizes the food-contact metal between servings at
   no extra heat-up — a genuine advantage of a hot machine (contrast HiveCell, which had
   to reject pyrolysis because its cavity held people and sensors).
4. **Hot-air dry** (`HotAirKnife`) — present the next bread on a dry surface.

**Why.** Dry-designed residue + a full-perimeter scraper + reused bake heat means most
sanitation is mechanical + thermal and essentially free; steam closes the gap. Keeping it
all service-side keeps the public face a plain flush wall (vandal resistance #1).

**Rejected alternatives.**
- Pyrolytic burn-off only: works thermally but wastes heat cycling and can't shift a wet
  film alone. Kept only as the *reused-heat* sterilize step, not a full burn.
- Flood/CIP immersion: asks a scraper seal to hold a water column; water/energy/dry/freeze.
- Chemical disinfectant every cycle (HiveCell's choice for fluids): here the residue is
  cooked starch, not pathogen-laden fluid, so thermal + steam should suffice — avoiding a
  disinfectant consumable AND its H7 chemical-residue-on-food hazard. Revisit only if the
  bench log-reduction proves marginal.

**Accepted costs / to verify.** Material spec: the low-adhesion coating must survive
scraping + 230 °C + steam repeatedly (couples ADR-0008, SF3). Prove the thermal + steam +
scrape log-reduction is enough for a food surface without chemicals (the key bench gate).
Quantify water + drying energy per cycle. Sewer tie for the (small) wash effluent; outdoor
freeze protection. Confirm the scraper actually clears crumbs to waste and not into the
running gap.

---

## ADR-0011 — Residue + release is the master variable (measure it before freezing the design)
**Date:** 2026-07-31
**Status:** Accepted

**Context.** Exactly as seal drag is HiveCell's master lever (their ADR-0011), SeedCell has
ONE number the whole machine hinges on: how much cooked-food **residue** remains on a
food-contact surface after one bake+clean cycle, and how hard the flatbread is to
**release**. It couples SF2 (can the surface self-clean to a safe residual every cycle?),
SF3 (how aggressive the scraper must be — which feeds back into its drag and wear),
the surface material spec (ADR-0008), and whether the self-releasing-bread concept even
holds. `scripts/residue.py` (first principles) brackets it across surface × boundary-layer
× hydration and finds a ~1000× spread (µg/cm² for PTFE+flour vs near-1 mg/cm² for bare steel).

**Decision.** Make **low adhesion a hard requirement** (ADR-0008), and MEASURE residue +
release on a real baked coupon before freezing the surface, the formula, the scraper (SF3),
and the cleaning method (SF2). A ~$150–250 bench procedure to do exactly that is
[`docs/residue_bench_test.md`](residue_bench_test.md) — the highest-value next experiment
and the best first contribution (the direct analog of HiveCell's seal-drag bench test).

**Why (quantified, `residue.py`).** Above a per-cycle residue threshold the design must
*change* (different coating, thicker boundary layer, leaner dough, or add a chemical step —
ADR-0010's rejected option) rather than just resize; below it, thermal+steam+scrape suffices
with no chemical consumable. The measurement is a go/no-go on the whole "no-chemicals,
self-cleaning" claim, just as HiveCell's seal-drag number was a go/no-go on its 2-lip seal.

**Follow-ups.** Once measured, re-run `residue.py` / `actuator_sizing.py`
(`SCRAPER_DRAG_PER_M=<n>`) and revisit ADR-0010 (chemical step?) and SF3 (lip count/interference).

---

## ADR-0012 — Ingredients: dry storage + injection hydration; everything upstream stays dry (SF6)
**Date:** 2026-07-31
**Status:** Accepted

**Decision.** All ingredients are stored **dry** (flours, salt, micronutrient premix) in
sealed hoppers (`DryStorage`); oil is a small sealed reservoir; water is mains. Nothing
wet exists until the injection at hydration (ADR-0006). Dosing is gravimetric/volumetric
augers/valves that meter dry powder into the bore. A spoilage-lockout (SF6) monitors hopper
moisture + temperature and refuses to charge from a wet/spoiled hopper (fail-safe, like a
sensor fault in SF1).

**Why.** Dry storage is shelf-stable for the machine's long unattended fill cycles, doesn't
grow anything, and needs no cleaning — the whole upstream path has zero food-contact
cleaning burden (the README maintenance goal: refill, don't wash). Wetness only ever exists
for the ~2 minutes of a bake, inside the one chamber that cleans itself.

**Rejected alternatives.** Refrigerated wet/perishable ingredients (spoilage, energy, a
cold wet path to clean). Pre-hydrated dough cartridges (packaging + a wet reservoir).

**Accepted costs / to verify.** Dry powders bridge/clog and vary in flow with humidity —
dosing accuracy + anti-bridging is a real mechanism item; gravimetric feedback helps.
Micronutrient premix uniformity at 0.5 g/serving (segregation risk). Hopper moisture-ingress
sealing for an outdoor unit.

---

## ADR-0013 — User identification: privacy-preserving ration check, no biometric database
**Date:** 2026-07-31
**Status:** Accepted (principle); implementation + policy review TBD

**Context.** The mission is "no one goes hungry", but a public machine needs to prevent
one person from draining a day's stock (abuse) while RESPECTING the dignity + privacy of
people who are already vulnerable. Fingerprint scanners and a permanent identity database
are both a hygiene problem (a touched public sensor) and a surveillance problem (a registry
of who is hungry).

**Decision.** No fingerprint scanner, no permanent identity database. Instead: a protected
camera behind armored glass does **on-device, ephemeral** recent-serving recognition — "has
*this* face been served in the last N hours?" — with templates that live only in volatile
memory for a rolling window and are never persisted or transmitted. The default failure mode
is **generous**: ambiguity serves the person (the cost of an extra flatbread is trivial vs
the cost of denying a hungry person). The ration policy (interval, per-day cap) is a tunable,
transparent config, not a judgement about the individual.

**Why.** Prevents gross abuse (stock-draining) with the lightest possible touch on privacy
and dignity, and keeps the public face contactless (hygiene + vandal resistance). Erring
generous is consistent with the mission — SeedCell rations to protect *supply for everyone*,
not to police individuals.

**Rejected alternatives.** Fingerprint / touched biometric: hygiene + dignity + a durable
registry. Cloud identity / accounts: excludes the unbanked/undocumented — the exact people
the machine is for. Payment: excluded by the mission (it's free).

**Accepted costs / to verify.** On-device ephemeral recognition accuracy + fairness across
skin tones, occlusion (hoods, masks), and lighting — a real ML + ethics review item; bias
here directly harms the vulnerable. Legal review of even ephemeral biometrics per
jurisdiction. Anti-spoofing vs the generous default (accept some gaming as the price of
dignity). Consider a no-camera fallback (simple time-token) where camera use is unacceptable.

---

## ADR-0014 — CAD → twin / render export conventions
**Date:** 2026-07-31
**Status:** Accepted

**Decision.** `scripts/export_godot.py` (later) writes one OBJ per part to `godot/models/`
plus `seedcell.json` (stroke, timings), baking to Godot space at export: scale ×0.001
(mm→m) and rotate −90° about X (FreeCAD Z-up → Godot Y-up), i.e. (x,y,z)→(x,z,−y). The +X
motion axis is preserved, so the whole cycle is a single −X/+X translation of the Piston
node. Same convention as HiveCell ADR-0006, so the two twins share tooling.

**Rule.** Any new part added to `build_model.py` must be added to `PARTS` in the export
scripts and (if it moves) wired in the Godot scene.

---

## ADR-0015 — SF1 kill-step target: 7-log Salmonella as an F-value, not a core temperature
**Date:** 2026-08-03
**Status:** Accepted (target + model); challenge-study validation and probe placement TBD

**Context.** ADR-0009 fixed the *architecture* of the cook-lethality safeguard — diverse
channels, AND-toward-safe, fault-is-unsafe — but left the actual criterion as an
acknowledged guess: "core reaches 75 °C". That is not a kill-step. It names a temperature
and says nothing about how long it is held, so it cannot distinguish a core that touched
75 °C for a millisecond from one held there for a minute; and it assigns no value at all
to a cook that stalled at 68 °C. The `ft_integrator` channel had no physics behind it —
it was a boolean somebody else had to set.

**Decision.**
1. **The criterion is an accumulated F-value, not a set-point.** Lethality accrues at
   `rate(T) = 10^((T − T_ref)/z)` and `F = ∫ rate dt`, i.e. equivalent seconds held at the
   reference temperature. Implemented in `godot/lethality_model.gd`.
2. **Reference organism: *Salmonella* spp.**, the controlling vegetative pathogen for
   cereal and legume flours. *E. coli* O157:H7 is less heat-resistant and is covered by
   the same margin. The dough core is hydrated during the bake, so moist-heat resistance
   applies.
3. **Target: 7-log reduction**, matching the most stringent common regulatory cooking
   standard. Justified by the vulnerable-user case already argued in ADR-0009.
4. **Constants are fitted to the FDA Food Code 3-401.11 table**, which encodes that
   7-log reduction in two rows — 63 °C/3 min and 66 °C/1 min. Fitting both gives
   `z = 3/log₁₀(3) = 6.29 °C`, and the model reproduces the table exactly rather than
   approximating it. **Target: F₇₀ ≥ 13.9 equivalent seconds.**
5. **A 60 °C accumulation floor.** Below it, lethality credit is discarded rather than
   integrated.
6. **Integrate the coldest point**, never a mean and never the platen: `CookLethality.coldest()`
   takes the lowest core probe, and an empty probe set returns NAN, which reads as a fault.
7. **F is per-batch and never carried across one** (`new_batch()`), and a single
   implausible sample latches the batch suspect no matter how much F was banked.

**Why the floor (6) is a safety rule, not a numerical convenience.** The model is happy to
accrue lethality at 55 °C, and that is mathematically correct — but reaching the target
purely by dwelling there takes ~80 minutes sitting in the bacterial growth zone. Without a
floor, a batch that was never really baked, just left warm, would eventually be declared
cooked. Refusing sub-60 °C credit makes a marginal cook read as a *failed* cook, which is
the direction that diverts to waste.

**What this does NOT cover.** ***Bacillus cereus* spores**, endemic to cereal and legume
flours, are not killed by any bake this machine can perform — spore D-values are minutes at
retort temperature. Their control is not lethality but **time**: serve immediately, never
hold warm. This is a distinct hazard and belongs in SAFETY.md, not in the F-value.

**Consequence — the margin is enormous, and that is the point.** A hydrated core plateaus
near 100 °C, where lethality accrues ~250,000× faster than at the 70 °C reference:
`scripts/cook_energy.py` shows the target cleared at ~24 s and a nominal 90 s cycle banking
~2.6×10⁵ times the requirement. The F-value is not there to constrain the good cook. It is
there to catch the **failed** one — a cold core, a truncated cycle, a dead probe — and to
make "cooked" a quantity a channel can positively prove rather than assert.

**Rejected alternatives.**
- *Keep a core set-point (75 °C, 85 °C, …)*: silent on hold time; the blind spot above.
- *A round literature z of 6.0 °C*: undercuts the Food Code's own 66 °C row by 5% (demands
  57 s where the table says 60 s), i.e. lenient against the regulation it claims to encode.
- *Low-moisture (low-aw) Salmonella resistance data*: far more conservative, but wrong
  physics for a hydrated core; it would be conservatism bought by modelling the wrong thing.
- *Fixed bake timer*: no proof; drifts with ambient, ingredient and platen condition.

**Accepted costs / to verify.** The constants are regulatory and literature values for a
design model, **not a validated process**: a served product needs its own challenge study
(SAFETY.md "Open items", ROADMAP #10). Probe placement must be shown to read the true
geometric coldest point, otherwise the whole integral is measuring the wrong place. The
`CORE_PLATEAU_C = 100 °C` cap in `cook_energy.py` is a modelling assumption about free
water, conservative but unmeasured. Asserted by `godot/tests/test_lethality_model.gd`.

---

## ADR-0016 — SF7 bake→serve hold: *Bacillus cereus* is controlled by time, not heat
**Date:** 2026-08-03
**Status:** Accepted (control + logic); the hold budget is a facility-level parameter

**Context.** ADR-0015 set the SF1 kill-step and, in the same breath, named the hazard it
cannot reach. *B. cereus* is endemic to cereal and legume flours; its **spores survive any
bake this machine can perform** (spore D-values are minutes at retort temperature, against
a bake measured in seconds), so no accumulated F-value touches them. Worse, the emetic
toxin (cereulide) is **heat-stable** — once it has been produced, re-baking cannot undo it.
A machine that proved lethality perfectly and then let the bread sit would still make
people ill, and SF1 would report everything was fine.

**Decision.**
1. **The control is time, not heat.** A batch has a bounded budget between end-of-bake and
   collection; past it, it is waste. `godot/spore_hold.gd`, gate in `process_interlock.gd`.
2. **The clock is temperature-gated, not wall-clock.** Only time spent **below 60 °C**
   accrues. Above that, outgrowth is suppressed and the batch ages for free.
3. **60 °C is deliberately the same number as `LethalityModel.T_FLOOR`** — one threshold
   for "where biology stops", used as a floor for lethality credit in ADR-0015 and as a
   ceiling for risk accrual here. It also sits at the top of the conventional hot-hold
   band (57–60 °C), so it is defensible from both directions.
4. **Default budget 15 minutes** (`DEFAULT_MAX_HOLD_S = 900`), far tighter than the
   4-hour regulatory ceiling for time-as-a-public-health-control. **This is a
   facility-level parameter** in the same class as the formula and the ration policy: the
   device enforces it, it does not choose it.
5. **A dead thermometer accrues risk time rather than pausing the clock**, and latches the
   batch unprovable.
6. **The clock starts at end-of-cook, not at PRESENT** — risk accrues wherever the batch
   waits, including through an abort that never reaches the mouth.

**Why 15 minutes and not 4 hours.** SeedCell bakes **on demand**: the nominal bake→collect
interval is on the order of ten seconds, so 15 minutes is already ~90× the normal case. A
batch that exceeds it has not been *waiting*, it has been **stuck** — a jam, an aborted
delivery, a slow clean — and a stuck batch is precisely the one that must never be handed
to anyone. Spending the regulatory maximum here would buy nothing operationally and give
away the entire safety margin.

**Why a dead sensor must not pause the clock (5).** The intuitive failure handling — "no
reading, don't accrue" — is exactly backwards. A failed thermometer is *correlated* with a
machine that has stopped attending to the batch, so it is the moment a batch is most likely
to be sitting forgotten. Pausing the clock there would grant unlimited holding time in
precisely the fault where it is least deserved.

**Consequential fix.** Wiring the gate exposed an accounting gap that predates it: an abort
mid-delivery (SF4 pinch/burn trip) fell through `RETRACT → CLEAN` and was silently scraped
away, counted as neither served nor wasted. Both abort paths now condemn the batch and
route through `DIVERT`, so **served + wasted accounts for every batch made**. Asserted by
`tests/test_spore_hold.gd` scenario S6.

**Rejected alternatives.**
- *Wall-clock timer from end-of-bake*: condemns a batch still sitting hot in the bore, and
  gives a fast-cooling batch the same budget as one held hot. Wrong physics, both ways.
- *Rely on the SF1 kill-step*: cannot work — spores survive it by orders of magnitude.
- *Re-bake a held batch instead of discarding it*: cereulide is heat-stable; a re-bake
  sterilises the evidence, not the toxin.
- *Hot-hold indefinitely above 60 °C*: technically suppresses outgrowth, but bakes the
  product to leather and burns standby energy for a machine whose whole premise is
  on-demand. The bounded budget is cheaper and simpler.

**Accepted costs / to verify.** The budget is a policy number, not a measured one — a
challenge study on the real product should confirm 15 min at ambient is comfortably inside
the safe envelope. The guard needs a batch thermometer; it reuses the delivered-surface
sensor the SF4 burn guard already requires, so no new hardware. **Not covered:** an
uncollected batch left presented at the mouth — that needs a collection sensor and an
`AWAIT_COLLECT` state, which is separate work (ROADMAP).

---

## Component tree (one cell) — reference for ADR-0001

1. Structure/enclosure: fixed heated `CookBarrel` (bore), wall-interface flange & trim,
   `MouthDie` (fixed peeler/hard-stop ring), armored public face.
2. Motion/actuation: piston linear drive, bore-as-guide (no external rails, HiveCell
   ADR-0007 lesson), actuator-to-piston coupling, mechanical hard stops, passive flush latch.
3. Food path (kept minimal): `DryStorage` hoppers + dosers, oil reservoir, `HydrationRing`
   (injection mix, ADR-0006), the bore + piston face (form + cook), `WasteChute` (divert).
4. Sensing/safety/control: SF1 diverse lethality probes (2× core thermocouple + IR pyrometer
   + F-value integrator, ADR-0009), SF6 hopper spoilage sensors, piston position + limits,
   mouth presence + safety edge (SF4), delivered-surface thermometer (burn guard), rated
   safety controller.
5. Services: power, water in + wash drain, `SterilizeRing` (steam/hot-water), `HotAirKnife`
   (dry), heaters (griddle + face), status beacon (SF5).
6. Cleaning subsystem (ADR-0010): piston scraper lips (SF3) + SterilizeRing + HotAirKnife +
   reused bake heat; all service-side; nothing on the public face.
7. User interface: exterior availability/status beacon (SF5), privacy-preserving ration
   camera (ADR-0013), delivery aperture (the mouth), no buttons/handles.
