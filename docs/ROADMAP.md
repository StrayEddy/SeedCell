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
| 3 | **Close the mouth during the bake** (decide ADR-0017) | safety | A stated H6 mitigation the geometry does not deliver: the mouth is an open Ø156 hole into a 230 °C chamber for the whole ~90 s cook. **Blocks freezing the bore.** |
| 4 | Uncollected-batch handling (collection sensor + `AWAIT_COLLECT`) | food-safety | The gap ADR-0016 left open: SF7 guards the bake→collect interval, but a serving left sitting at the mouth is outside it. |

## Next (medium priority)
| # | Item | Area | Why |
|---|------|------|-----|
| 5 | Jet-hydration dough trials | food | Does blade-free injection mixing (ADR-0006) give uniform dough? Research question #2. |
| 6 | Low-adhesion coating durability | materials | PTFE/ceramic under scrape + 230 °C + steam (ADR-0008/0010); couples SF3 wear (H8). |
| 7 | Export pipeline → twin/render | sim | `export_godot.py` + a visual `process_demo` scene (ADR-0014); currently logic-only. |
| 8 | SF4 burn/pinch hardware | safety | Surface-temp cap from burn data; mouth presence + safety edge. |

## Done
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
  Still open: the uncollected-batch case, now Now #4.

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
