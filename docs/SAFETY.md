# SeedCell — Safety & Hygiene (living document)

Food-safety and machine-safety analysis for an unattended public machine that bakes and
serves food. Method: identify hazards (ISO 12100 for the machine + HACCP for the food),
rate risk, assign safety functions. Users are assumed VULNERABLE — food-insecure, possibly
without other options, eating a machine-made ration repeatedly, with no recourse if it
harms them. The primary hazards are therefore FOODBORNE (a bad serving), not just mechanical.

## Design principle (order matters)
1. **PROVE, don't assume** — never present a serving unless the cook kill-step is positively
   proven (SF1) AND the food-contact surfaces were sanitized since the last serving (SF2).
2. **DIVERT on doubt** — a failed cook, failed clean, or any safety-relevant fault sends the
   batch to WASTE and locks the line, never to a person.
3. **DESIGN OUT contact** — the fewest food-contact surfaces possible, self-releasing food,
   dry storage: less to contaminate, less to clean (defense by inherent design).

"Serve it anyway" is NOT a food-safety case. A batch that isn't provably safe is waste.

## Hazard register
Risk = Severity (1-4) × Likelihood (1-4). Severity 4 = serious/widespread illness or injury.

| # | Hazard | Scenario | S | L | R | Required safety function |
|---|--------|----------|---|---|---|--------------------------|
| H1 | Under-cooked serving (pathogen survival) | Kill-step missed; raw/undercooked flatbread served | 4 | 3 | 12 | SF1 proven-lethal cook; divert on fail; never serve on assumption |
| H2 | Cross-contamination via residue | Baked-on film/crumbs from a prior serving smear into the next | 4 | 3 | 12 | SF2 sanitation every cycle; ADR-0008 self-releasing food + low-adhesion surface; SF3 scrape |
| H3 | Spoiled / wet ingredient served | Damp hopper grows mould; spoiled oil | 3 | 2 | 6 | SF6 spoilage lockout (moisture/temp); dry storage (ADR-0012) |
| H4 | Burn at the mouth | Hot piston face / just-baked bread scalds a hand/mouth | 3 | 3 | 9 | SF4 delivered-surface temperature cap; brief present; edge geometry |
| H5 | Pinch / crush at the mouth | Hand reaches in as the piston presents, OR is still at the mouth as the piston withdraws after a delivery | 3 | 2 | 6 | SF4 force cap + safety edge → abort present; **SF9** mouth-clear guard → hold position (never withdraw across a hand), bounded, then alarm (ADR-0020); SF5 slow final approach |
| H6 | Contaminant ingress / tampering | Foreign object, fluid, or vandalism pushed into the mouth | 4 | 2? | 8? | Mouth flush + sealed except during present; presence gate; inspect-on-open. **⚠ This mitigation does not currently hold — see ADR-0017. The L=2 score assumed a sealed mouth; it is optimistic and must be re-scored once ADR-0017 is decided.** The *delivery* window is bounded (SF8, ADR-0018); the *bake* window is narrower than it was — ADR-0019 (2026-08-04) decided the piston presses flush right after HYDRATE, so the open-mouth exposure is now CHARGE+HYDRATE+PRESS (~9 s default), not the full ~90 s cook — but it is still open, not sealed, so ADR-0017 remains undecided. |
| H7 | Cleaning-chemical residue on food surface | A disinfectant (if used) left on the piston face | 4 | 1 | 4 | ADR-0010 thermal+steam, NO per-cycle chemical; if added, a dose+rinse verify + fail-safe |
| H8 | Foreign body from mechanism wear | Coating flake / seal fragment ends up in the bread | 3 | 2 | 6 | Food-grade materials; SF3 wear budget; inspection; frangible-part exclusion from food path |
| H9 | Allergen exposure | Wheat/legume allergens inherent to the formula | 3 | 3 | 9 | Clear fixed labelling at the machine; formula is fixed + published (facility-level) |
| H10 | Spore outgrowth in a held batch | *B. cereus* spores survive the bake (H1's kill-step cannot reach them) and outgrow while a finished batch waits; the emetic toxin is heat-stable, so no later heating can fix it | 4 | 2 | 8 | SF7 bake→serve hold budget, temperature-gated, divert on timeout (ADR-0016) |
| H11 | Uncollected serving | Nobody takes the presented batch (the requester left, was frightened off, or dropped it): the mouth stays open on it, a person is debited a ration they never received (ADR-0013), and street-exposed food is drawn back through the bore | 4 | 2 | 8 | SF8 collection proof — `served` only on a proven loaded→empty transition; bounded delivery window; condemn + divert on timeout (ADR-0018) |

## Safety functions
Status: **[sim]** = logic implemented and machine-checked in the digital twin — NOT rated
hardware, no performance-level claim yet. **[decision]** = chosen, not yet implemented.
**[cad]** = geometry/space-claim in the FreeCAD model. **[todo]** = not started.

- **SF1 Cook lethality (primary)** — *[sim: fail-safe voting]* every serving must positively
  prove an accumulated time-temperature lethality (F-value) before it may be presented.
  Diverse-redundant channels (2× core thermocouple + IR surface pyrometer + independent
  F-value integrator), AND-toward-safe, fault-is-unsafe. Fault or unproven ⇒ divert to waste.
  Architecture + logic in **ADR-0009** / `godot/cook_lethality.gd`. The target is now set
  (**ADR-0015**): **F₇₀ ≥ 13.9 equivalent seconds, z = 6.29 °C** — a 7-log *Salmonella*
  reduction fitted to the FDA Food Code 3-401.11 table, integrated from the **coldest**
  core probe, with no credit below 60 °C and no carry-over between batches
  (`godot/lethality_model.gd`). Probe parts, coldest-point placement and challenge-study
  validation remain TBD. This is the food analog of HiveCell's SF1 occupancy detection.
- **SF2 Surface sanitation (primary)** — *[sim + decision]* the food-contact surfaces (bore +
  piston face) must be scraped, sanitized, and verified clean after every serving before the
  next charge. Unverified ⇒ re-clean; repeated failure ⇒ LOCKOUT (no service). Method in
  **ADR-0010** (scrape + steam + reused-heat sterilize + dry); verification sensor TBD.
- **SF3 Contamination barrier / scraper seal** — *[cad: gap-fill + drag budget]* circular
  scraper lips on the piston bridge the running gap, wipe the full bore perimeter each
  stroke (the syringe-native squeegee, ADR-0010 step 1), and separate the public mouth side
  from the sealed service side. Aggressiveness couples to residue (ADR-0011) and wear (H8) —
  **measure residue/release before fixing lip count + interference** (`docs/residue_bench_test.md`).
- **SF4 Burn + pinch guard (public safety)** — *[sim: abort logic]* the present stroke is
  gated on a touch-safe delivered-surface temperature (burn, H4) AND no over-limit mouth
  force / no reach-in (pinch, H5). Either unsafe ⇒ abort the present and retract; never push a
  serving through a hand or serve a scalding surface. `mouth_safe()` in
  `godot/process_interlock.gd`; force cap + presence sensor + surface thermometer TBD.
- **SF5 Motion signalling + soft profile** — *[sim]* status beacon (green ready / blue working
  / amber presenting / orange closed / flashing-red alarm) + soft-start/stop + speed-limited
  final approach at the mouth (`godot/soft_profile.gd`, shared unchanged with HiveCell).
  Defense-in-depth only — never a primary safeguard.
- **SF6 Ingredient integrity / spoilage lockout** — *[decision]* hopper moisture + temperature
  monitoring refuses to charge from a wet/spoiled hopper (H3), fail-safe like an SF1 sensor
  fault. Dry storage (ADR-0012) makes spoilage unlikely; the lockout catches seal failure.
- **SF7 Bake→serve hold (primary, spore control)** — *[sim: gate logic]* SF1 proves the batch
  was *cooked*; SF7 proves it has not since sat long enough for the ***B. cereus* spores that
  survived that cook** to outgrow. Their toxin is heat-stable, so this is the one food hazard
  that no amount of heat can fix after the fact — the control is **time**. A temperature-gated
  clock accrues only sub-60 °C time from end-of-bake; past the budget (default **15 min**,
  a facility-level parameter) the batch is diverted to waste, never served. A dead thermometer
  accrues risk rather than pausing the clock. **ADR-0016** / `godot/spore_hold.gd`. The batch
  left uncollected at the mouth — the case SF7 did not cover — is now **SF8**.
- **SF8 Collection proof (accounting + exposure)** — *[sim: transition-proven]* a serving is not
  *served* until a person has positively **taken** it. Collection is read as a **transition**
  (the face seen carrying the batch, then seen empty), never as a level, so a sensor stuck at
  either end fails to waste instead of manufacturing a phantom serving. The whole delivery —
  stroke plus the `AWAIT_COLLECT` wait — is bounded by a window (default **120 s**); on expiry
  the batch is withdrawn, condemned and diverted, never re-offered. The window is nested inside
  SF7's hold budget, so the food-safety bound always dominates; what SF8 bounds is the open-mouth
  exposure (H6) and one person's ability to hold the machine out of service. Sensor: loss-of-mass
  on the actuator force channel SF4 already needs. **ADR-0018** / `godot/collection_guard.gd`.
- **SF9 Retract mouth-clear guard (public safety, H5)** — *[sim: gate logic]* the piston must
  never withdraw across a hand. `RETRACT` holds position (no crushing force while stationary,
  the same reasoning `AWAIT_COLLECT` uses for its pinch-cap exemption) until the mouth presence
  sensor reads clear, bounded by a 60 s timeout — shorter than SF8's 120 s, because by this point
  collection is already settled one way or the other. On timeout it does not force the withdrawal
  through: it alarms (`LOCKOUT`), the same escalation CLEAN_VERIFY already uses for "cannot make
  safe automatically." Mirrors HiveCell's core rule (never move until proven clear) applied to
  SeedCell's one comparable motion. Sensor: the same mouth presence/safety-edge device SF4 needs
  for the present-stroke pinch cap, read through withdrawal too. **ADR-0020** /
  `godot/process_interlock.gd`.

## FMEA — under-cook / cross-contamination chain (basis for the SF1/SF2 decisions)
Component-level companion to the hazard register: how the cook/clean path can fail and what
reaches a person. Scale 1-4 each (engineering judgment): **S**everity, **O**ccurrence,
**D**etection (4 = hard to detect / nothing catches it). RPN = S×O×D.

| # | Failure mode | Cause | Effect | S | O | D | RPN | Mitigation / decision |
|---|--------------|-------|--------|---|---|---|-----|-----------------------|
| F1 | Core probe reads false-hot | drift, air gap, mis-seat | a raw batch looks cooked | 4 | 2 | 3 | 24 | diverse redundant SF1 (2nd probe + IR + F-value integrator); AND-toward-safe |
| F2 | F1, but a diverse channel dissents | — | SF1 vote fails → DIVERT to waste, not served | 1 | 2 | 1 | 2 | designed defense-in-depth path (verified in sim) |
| F3 | ALL cook sensing lost / stale | power blip, bus fault, blackout | cannot prove lethality | 4 | 1 | 1 | 4 | fault = unsafe ⇒ no serve (fail-safe); nothing is presented without positive proof |
| F4 | Clean cycle skipped/partial | timing fault, low water, clog | residue smears next serving (H2) | 4 | 2 | 2 | 16 | SF2 verify-clean gate; unverified ⇒ re-clean/LOCKOUT before any charge |
| F5 | Clean verify sensor false-clean | fouled sensor | dirty surface passes | 4 | 1 | 3 | 12 | diverse/periodic-self-test verify; conservative threshold; scheduled human audit |
| F6 | Under-cooked batch reaches the mouth | logic error | a person is served raw food | 4 | 1 | 4 | 16 | **DIVERT-only architecture (SF1)** — PRESENT is unreachable except via a passed lethality check; enforced by self-test |
| F7 | Chemical residue on the face | per-cycle disinfectant not rinsed | chemical ingestion (H7) | 4 | 1 | 3 | 12 | **no per-cycle chemical (ADR-0010)** — thermal+steam only; H7 designed out |

The drivers are **F1** (a plausible sensor lie that only diversity catches) and **F6**
(serving raw — Severity 4, and once served nothing can act, D=4). High severity + no
post-hoc recovery ⇒ they must be *designed out*: SF1's PRESENT state is reachable **only**
through a passed lethality vote, and that invariant is enforced by
`godot/tests/test_interlock.gd` on every push.

## Implementation status (digital twin)
The process *logic* has a reference implementation in the Godot twin. It models behaviour
and is regression-checked; it is NOT rated hardware and makes no performance-level claim.

- `godot/process_interlock.gd` — the serve-cycle state machine. The core invariant: PRESENT
  (delivering to a person) is entered ONLY from a passed LETHALITY_CHECK, on surfaces that
  were sanitized since the last serving; any failed cook/clean routes to DIVERT/CLEAN/LOCKOUT.
  SF4 aborts a present on a mouth pinch or too-hot surface.
- `godot/cook_lethality.gd` — SF1 diverse-redundant, fail-safe lethality voter (2× core probe
  + IR + F-value integrator): AND-toward-safe, fault-is-unsafe, with a runtime `self_test()`.
- `godot/tests/test_interlock.gd` — headless self-test of the invariant "a raw or unclean
  batch is never served (and a good one is)", across: good batch, under-cook, sensor fault,
  un-sanitizable → LOCKOUT, and mouth-guard abort. Runs on every push via `.githooks/pre-push`.
- `godot/tests/test_cook_lethality.gd` — fault-injects each channel/mode, checks staleness,
  and exhaustively verifies the vote invariant across all 3⁴ combinations.
- `godot/lethality_model.gd` (+ `test_lethality_model.gd`) — the SF1 kill-step TARGET
  (ADR-0015): F₇₀ ≥ 13.9 s, 7-log *Salmonella*, checked against the FDA Food Code rows it is
  fitted to, plus the integrator's floor / fault-latch / per-batch behaviour.
- `godot/spore_hold.gd` (+ `test_spore_hold.gd`) — SF7 bake→serve hold (ADR-0016): only
  sub-60 °C time accrues, a dead sensor accrues rather than pauses, an over-held batch is
  diverted and never served, and every batch is accounted for as served or wasted.
- `godot/collection_guard.gd` (+ `test_collection.gd`) — SF8 collection proof (ADR-0018):
  collection is the loaded→empty transition, a stuck or blind sensor times out to waste,
  the mouth does not stay open past the window, and `served` counts people fed rather than
  strokes completed. The served + wasted accounting invariant is re-asserted over the new
  `AWAIT_COLLECT` state.
- `godot/soft_profile.gd` (+ `test_soft_profile.gd`) — SF5 soft motion profile, shared with HiveCell.
- `scripts/build_model.py` — SF3 scraper lips (2 circular rings) + the minimal food-contact
  geometry; `scripts/residue.py` brackets the master residue/release variable (ADR-0011);
  `scripts/cook_energy.py` checks SF1 cook time/lethality/energy; `scripts/actuator_sizing.py`
  budgets the piston force (dough forming dominates).

Addressed in sim: H1 by SF1 (+ fail-safe divert), H10 by SF7 (hold budget + divert-on-timeout),
H11 by SF8 (collection proof + bounded delivery window),
H2 by SF2 + ADR-0008 (residue TBV by test),
H4/H5 by SF4 abort logic + SF9 retract guard, H3 by SF6 (decision), H7 designed out by ADR-0010. H6/H8/H9 are
facility/material/label items below.

## Siting & facility rules
Install constraints on the operator/installer, not device functions.

**Plumbing.** Potable mains in (backflow-prevented) + a wash drain to sewer for the small
per-cycle cleaning effluent. Outdoor units need trace-heat / self-drain freeze protection.

**Labelling (H9).** The fixed formula's allergens (wheat, legumes) and full nutrition must be
clearly, permanently displayed at the machine — an inherent, not detectable, hazard.

**Ingredient service.** Refill dry hoppers + oil + water; replace filters; inspect. NOT
cleaning food residue (SF2 does it) — see README maintenance scope. A scheduled human audit
of the SF2 clean-verify (F5) is a commissioning requirement.

**Responsibility.** The formula, the F-value lethality target, and the ration policy
(ADR-0013) are facility-level decisions carrying a named sign-off; the device enforces, it
does not choose them.

## Open items
- **⚠ Mouth is not sealed during the bake (H6, ADR-0017) — OPEN, blocks freezing the bore.**
  Found by drawing the CAD 1:1 (`docs/cell_anatomy.svg`). `MouthDie` is an annulus with a
  Ø156 bore; ADR-0007 bakes against "the heated bore-end/die"; ADR-0001 rules out a separate
  door or shutter. The piston sits retracted 60 mm through CHARGE → HYDRATE, then **presses
  flush and holds through COOK (ADR-0019, 2026-08-04)** — so the open-mouth window is now
  CHARGE + HYDRATE + PRESS (~9 s default), not the full ~90 s bake, but it is still a real
  opening: the bread's own pressed face is what plugs the die, not a mechanical seal. This is
  not an unimplemented item — it is a stated mitigation that the current geometry contradicts,
  so H6's risk score is optimistic until it is resolved. Also note the CAD gives no workable hot
  platen at the die end: only the 2 mm annular ledge between die ID and bore ID, which cannot
  bake a Ø160 disc — ADR-0019 does not touch this half of the problem. Resolution options and
  trade-offs are in **ADR-0017**; the decision is not yet made.
- **SF1 real sensing (ADR-0009/0015):** the F-value target is set (F₇₀ ≥ 13.9 s, 7-log
  *Salmonella*) — what remains is hardware and proof: choose probe parts; validate that they
  read the true geometric **coldest point** (get this wrong and the integral measures the
  wrong place); run a challenge study on the real product; build the integrity dossier for
  the safety controller.
- **Bacillus cereus spores (SF7, ADR-0016):** the control is implemented — a temperature-gated
  bake→serve budget with divert-on-timeout (`godot/spore_hold.gd`). What remains: confirm the
  15-minute default against a challenge study on the real product. The uncollected-batch case
  it left open is now closed by SF8 (ADR-0018).
- **SF8 collection sensing (ADR-0018):** the logic is implemented and the sensing principle is
  chosen (loss-of-mass on the actuator force channel, read as a transition). What remains is
  hardware: confirm a ~120 g batch is resolvable against the piston's own load and friction,
  and revisit the 120 s window from real siting observation — it is an engineering judgement
  about dignity and throughput, not a measured number. **Adjacent gap now closed (logic):**
  retracting while a hand is still at the mouth predated SF8 and `AWAIT_COLLECT` only made it
  visible; it is now guarded by **SF9** (ADR-0020) — RETRACT holds position until the mouth
  reads clear, bounded, then alarms. Hardware is the same open item as the SF4 line below.
- **SF2 clean verification (ADR-0010):** the hardest open problem — an unattended, reliable
  *sensor* that proves a food surface is clean (residue below a safe threshold) every cycle.
  Bench the thermal+steam+scrape log-reduction; decide go/no-go on avoiding chemicals.
- **SF3 scraper + residue (ADR-0011):** MEASURE residue + release on a real baked coupon
  (`docs/residue_bench_test.md`) before fixing lip count/interference; couples SF2, the surface
  spec (ADR-0008), and H8 wear. The master variable.
- **SF4 burn/pinch:** set the touch-safe surface cap from burn-threshold data; select the mouth
  presence sensor + safety edge + delivered-surface thermometer. That same presence sensor is
  what **SF9** (ADR-0020) reads through withdrawal, not just delivery — the logic side of the
  retract-with-a-hand-present case is closed; the hardware choice is shared with this item.
- **ADR-0013 ration/identity:** privacy + fairness review of ephemeral on-device recognition;
  bias testing across skin tones/occlusion; legal review; a no-camera fallback.
