# SeedCell — Roadmap

At this stage the highest-value work is **reducing uncertainty**, not more CAD. SeedCell
is design + first-order simulation; the numbers that matter (residue, cook lethality,
clean log-reduction) are estimated, not measured. This file is versioned narrative; live
state belongs in GitHub Issues once the repo is public.

## Now (high priority)
| # | Item | Area | Why |
|---|------|------|-----|
| 1 | Residue + release bench test | food/hygiene | The master variable (ADR-0011); gates SF2, SF3, the surface + formula. See below. |
| 2 | Clean-verify sensor survey | sensing | The hardest open problem: prove a food surface is clean, every cycle, unattended (SF2). |
| 3 | **Decide what belongs at the bore end** (ADR-0017) | safety | Reframed 2026-08-05 by ADR-0021, which removed the mouth die: the bore now ends in a plain open cylinder, so there is **no closure and no second cook platen** — the bake is one-sided and ADR-0007's energy/lethality numbers are optimistic. Exposure is bounded at ~9 s by ADR-0019, but the cheap "3 + 4" answer no longer adds up (4 is spent, 3 was never a platen answer). The live fork: a **closure at the face** (mechanism in public, must preserve the new 8 mm-proud delivery) vs an **anvil deeper in the bore** (mechanism in the clean zone, costs a transfer). **Blocks freezing the bore.** |

## Next (medium priority)
| # | Item | Area | Why |
|---|------|------|-----|
| 5 | Jet-hydration dough trials | food | Does blade-free injection mixing (ADR-0006) give uniform dough? Research question #2. |
| 6 | Low-adhesion coating durability | materials | PTFE/ceramic under scrape + 230 °C + steam (ADR-0008/0010); couples SF3 wear (H8). |
| 7 | Export pipeline → twin/render | sim | `export_godot.py` + a visual `process_demo` scene (ADR-0014); currently logic-only. |
| 8 | SF4 burn/pinch hardware | safety | Surface-temp cap from burn data; mouth presence + safety edge — the same sensor SF9 (ADR-0020) now also reads through withdrawal. Logic side of retract-with-a-hand-present is closed; this item is the hardware selection both SF4 and SF9 are waiting on. |

## Done
- **Removed the mouth die** — **ADR-0021**, 2026-08-05. A Ø156 hardened ring standing 10 mm proud
  of the wall, present since the first commit and never justified by an ADR. Of its three jobs:
  rim-shearing duplicated ADR-0008's self-release (and made crumbs at the public face with
  nowhere to go), the "second cook platen" was 2 mm of contact and never worked, and the hard
  stop moved to drive-side end stops (HiveCell precedent) out of the food path. Removing it made
  ADR-0001's flush wall literally true and turned the serving from **2 mm recessed inside a hole**
  into **8 mm proud of a flat wall** — an accessibility fix nobody had been scoring for.
  **Deliberately makes Now #3 harder**, and surfaced *delivery ergonomics* as a fifth criterion
  ADR-0017's options had never been judged against.
- **Retract mouth-clear guard / SF9** (was Now #4) — **ADR-0020**, 2026-08-04. The gap ADR-0018
  named: the piston retracted the instant a delivery ended, exactly when a hand is most likely
  to be at the mouth. `RETRACT` now holds position (no crushing force while stationary, same
  reasoning `AWAIT_COLLECT` uses for its own pinch-cap exemption) until the mouth presence sensor
  reads clear, bounded (60 s, half of SF8's window), then alarms via `LOCKOUT` rather than forcing
  the withdrawal through. Fixed a latent bug `LOCKOUT` had carried since it only had one entry
  path before: it unconditionally forced `progress = 0.0` on entry, which was harmless for
  CLEAN_VERIFY failure (piston already at flush) but would have been actively wrong for this new
  path (piston stopped mid-bore). Sensor hardware remains item 8's open question.
- **Press order** (prerequisite to Now #3) — **ADR-0019**, 2026-08-04. Piston presses flush
  right after HYDRATE and holds through COOK — already implied by ADR-0006/ADR-0007's prose and
  `cook_energy.py`'s pressed-thickness assumption, just never implemented. New `PRESS` state in
  `godot/process_interlock.gd`; fixed a real bug it surfaced in `actuator_sizing.py` (press-stroke
  velocity was computed off the full present↔clean stroke, not the actual 60 mm charge↔flush
  travel — force number was fine, power/energy were overstated ~3.5x). Narrows ADR-0017's
  open-mouth window from ~90 s to ~9 s; does not decide ADR-0017 itself.
- **F-value lethality target** (was Now #2) — **ADR-0015**, 2026-08-03. F₇₀ ≥ 13.9 equivalent
  seconds, 7-log *Salmonella*, z = 6.29 °C fitted to the FDA Food Code table; replaces the
  placeholder 75 °C core assumption. `godot/lethality_model.gd` + `tests/test_lethality_model.gd`.
  Note what this did *not* close: probe parts, coldest-point validation and a challenge study
  are still gated hardware work (items 11/12 below), and it surfaced a new hazard — closed below.
- **SF7 bake→serve hold** (was Now #3) — **ADR-0016**, 2026-08-03. *B. cereus* spores survive
  the bake and their toxin is heat-stable, so the control is time: a temperature-gated clock
  accruing only sub-60 °C time, 15-minute default budget, divert-on-timeout.
  `godot/spore_hold.gd` + `tests/test_spore_hold.gd`. Also closed a pre-existing accounting
  gap — a delivery aborted mid-stroke was counted as neither served nor wasted.
- **Uncollected-batch handling / SF8** (was Now #4) — **ADR-0018**, 2026-08-04. The gap ADR-0016
  named. A new `AWAIT_COLLECT` state holds the batch out and `served` now increments only on a
  proven **loaded→empty transition** on the face sensor — so a sensor stuck at either end fails
  to waste rather than manufacturing a phantom serving, and `served` means *a person was fed*
  rather than *the piston moved* (it was the twin's liveness measure, so it was measuring the
  wrong event). The delivery window (120 s) is nested inside SF7's hold budget and bounds
  open-mouth exposure, not food safety. `godot/collection_guard.gd` +
  `tests/test_collection.gd`. **Surfaced a new gap** — retracting while a hand is still at the
  mouth was unguarded, pre-existing — **now closed by SF9 (ADR-0020)**, above.

## Critical-path experiment (not desk work)
**Residue + release is SeedCell's master variable** — the food equivalent of HiveCell's
seal drag. It couples the cleaning method (SF2), the scraper (SF3), the surface material and
the food formula (ADR-0008), and it is currently only *estimated* across a ~1000× range
(`scripts/residue.py`: µg/cm² for a low-adhesion surface + flour boundary layer, vs near
1 mg/cm² for bare hot steel). Everything downstream — whether the machine can be chemical-free
and self-cleaning at all — hinges on which end of that range is real. A ~$150–250 bench
procedure to measure it on a real baked coupon is [`residue_bench_test.md`](residue_bench_test.md).
Keep it visible so the paperwork above never quietly defers it.

## Physical validation & certification (hardware / context gated)
| # | Item | Area | Gate |
|---|------|------|------|
| 9 | Single-chamber cook prototype (form + jet-mix + bake) | food/mech | **proves ADR-0006/0007** — bench rig, no public serving |
| 10 | Clean-cycle log-reduction validation | food-safety | microbiology lab; go/no-go on the no-chemical SF2 claim |
| 11 | Food-safety certification dossier (HACCP + local food law) | compliance | none of this exists yet; required before any real serving |
| 12 | SF1 lethality controller integrity | safety | probe parts + a rated controller + coldest-point validation |

## Explicitly deprioritized
- Cinematic renders / website polish (later; presentation, not de-risking).
- Menu variety / flavour: the mission is a guaranteed nutritious ration, not a restaurant.
- Multi-machine fleet/telemetry: premature before one unit is proven safe.

## Conventions
- Decisions → ADRs in [`DECISIONS.md`](DECISIONS.md). Safety/hygiene changes → [`SAFETY.md`](SAFETY.md).
- Issues tagged `roadmap` + `area:*` (food / food-safety / sensing / materials / sim / safety) + `priority:*`.
- The invariant that gates everything: **a batch that isn't provably cooked AND served on a
  provably clean surface is waste, never a serving** — enforced by `godot/tests/test_interlock.gd`.
