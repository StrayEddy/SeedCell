# Contributing to SeedCell

Thanks for your interest. SeedCell is open-source hardware research — an autonomous public
machine that bakes a fresh, nutritious flatbread on demand so that no one goes hungry for
lack of money. It is the food sibling of [HiveCell](../HiveCell) and shares its workflow.

## Before anything else: read the safety context
SeedCell makes **food for vulnerable people, unattended, for years**. The core invariant is
non-negotiable: **a batch that is not provably cooked (SF1) and served on a provably clean
surface (SF2) is waste, never a serving.** Read [`docs/SAFETY.md`](docs/SAFETY.md) and
[`docs/DECISIONS.md`](docs/DECISIONS.md) first. This is uncertified research: there is no
built hardware, no microbiological validation, and no food-safety certification yet.

## Ways to help (most useful first)
- **Physical de-risking — the residue + release bench test** ([`docs/residue_bench_test.md`](docs/residue_bench_test.md)).
  The single highest-value contribution: measure SeedCell's master variable (ADR-0011) on a
  real baked coupon. ~$150–250 of kitchen-grade gear.
- **Food-safety review** — the F-value lethality target for a low-moisture legume flatbread
  (SF1/ADR-0009); the clean-cycle log-reduction question (SF2/ADR-0010).
- **Sensing** — the hardest open problem: a reliable unattended sensor that proves a food
  surface is clean every cycle (SF2 verify).
- **Food/formula** — a least-sticky, nutritionally-complete fortified flatbread (research
  questions #1/#4); jet-hydration dough trials (ADR-0006).
- **Simulation / CAD** — extend the twin (`godot/`) or the parametric model (`scripts/build_model.py`).

## How the project is organized
- **Decisions** are ADRs in [`docs/DECISIONS.md`](docs/DECISIONS.md).
- **CAD is code-first:** `scripts/build_model.py` run via `freecadcmd` is the source of truth;
  `cad/SeedCell.FCStd` is a generated artifact — never hand-edit it (ADR-0002).
- **The process logic is a headless-testable state machine** (`godot/process_interlock.gd`)
  with self-tests that enforce the core invariant.
- **First-order analysis lives in `scripts/`** (`dosing.py`, `cook_energy.py`, `residue.py`,
  `actuator_sizing.py`) — pure, reproducible, assumptions flagged and env-overridable.

## Workflow
1. Open an issue to discuss anything non-trivial before a large change.
2. Keep PRs focused.
3. Run the self-tests before pushing (they gate a pre-push hook):
   ```sh
   git config core.hooksPath .githooks   # once, after cloning
   ./scripts/run_selftest.sh
   ```
   (set `GODOT_BIN` if Godot 4 isn't on `PATH`.)

## Licensing of contributions
By contributing you agree your work is licensed under the project's per-medium scheme:
hardware/CAD under CERN-OHL-S-2.0, docs under CC-BY-4.0, software under Apache-2.0
(see [`LICENSE`](LICENSE)). SeedCell is public-good infrastructure — improvements stay open.
