---
name: hivecell-design-change
description: Use when proposing or making a change to SeedCell's mechanism, geometry, sensor suite, or a safety function (SF1-SF9) — a new/changed part or parameter in the FreeCAD model, a rework of an existing ADR's decision, or anything touching cad/, scripts/build_model.py, godot/*.gd process logic, or the hazard register/safety functions in docs/SAFETY.md.
---

# hivecell-design-change

## Overview
SeedCell records every engineering decision as an append-only ADR in
`docs/DECISIONS.md`, then updates the parametric CAD
(`scripts/build_model.py`, the source of truth per ADR-0002), then — if the
decision changes simulated behavior — the Godot process-logic twin
(`godot/*.gd`), and — if a safety function or hazard is touched —
`docs/SAFETY.md`. SeedCell keeps its hazard register, safety functions and
traceability in that one living document; there is no separate
`TRACEABILITY.md`. Mirrors the sibling HiveCell project's workflow (same
author/toolchain, ADR-0002).

## When to use
Any change to: the mechanism/motion, a part's geometry or parameters, the
food-contact surface story, a sensor suite, or a safety function's logic.
Also anything that would need explaining to a future contributor. Not needed
for pure rendering/site-copy changes with no decision behind them.

## Procedure
1. Write the ADR first in `docs/DECISIONS.md` (append-only, newest at the
   bottom). Find the next number with
   `grep -o 'ADR-[0-9]\{4\}' docs/DECISIONS.md | sort -u | tail -1`.
   Follow the existing shape: `## ADR-NNNN — <title>`, **Date**, **Status**,
   **Decision**, **Why**, **Rejected alternatives**, **Accepted costs /
   constraints** (or leave it explicitly open, as ADR-0017 did, if
   implementation isn't done yet), **Implementation** (list every file the
   decision touches — this becomes your checklist for the rest of this
   procedure).
2. Update the parametric CAD in `scripts/build_model.py`, and any first-order
   analysis script under `scripts/` whose numbers derive from the same
   parameters (`dosing.py`, `cook_energy.py`, `residue.py`,
   `actuator_sizing.py` — SeedCell's ADR history shows these get touched
   alongside geometry changes). Regenerate with:
   `flatpak run --command=freecadcmd org.freecad.FreeCAD scripts/build_model.py`
   Never hand-edit `cad/SeedCell.FCStd` in the GUI (ADR-0002) — it is a
   generated artifact and edits are lost on the next regenerate.
3. If the decision changes simulated process behavior (not just geometry),
   update the relevant file under `godot/` (`process_interlock.gd`,
   `cook_lethality.gd`, `lethality_model.gd`, `spore_hold.gd`,
   `collection_guard.gd`, `soft_profile.gd`) and its paired test in
   `godot/tests/`. Note: SeedCell has no CAD-to-Godot mesh export yet
   (ADR-0014 names `scripts/export_godot.py` as a future script, not written)
   — today's "twin" is the process-logic simulation only, kept in sync by
   hand-editing the `.gd` files, not by a regenerate step. If the change is
   purely visual/render, update `scripts/export_blender.py` and
   `blender/build_scene.py` instead.
4. If a safety function (SF1-SF9) or hazard (H1-H11) is affected, update
   `docs/SAFETY.md`: the hazard register row, the affected SF's status tag
   and description, the FMEA table if a failure mode changes, the
   "Implementation status (digital twin)" list, and the "Open items" list.
   Cite the ADR number. There is no separate traceability doc — `SAFETY.md`
   is the traceability record.
5. Update cross-references in the same change set: `docs/ROADMAP.md` and
   `TODO.md` (Now/Next items), `docs/cell_anatomy.svg` if the diagram shows
   the changed part, and `README.md` / `index.html` if either describes the
   changed mechanism (ADR-0021's implementation touched all of these).
6. Run `./scripts/run_selftest.sh` before pushing — see the
   `hivecell-safety-review` skill for the full checklist. It's also enforced
   by `.githooks/pre-push` once `git config core.hooksPath .githooks` is set.

## Common mistakes
- Hand-editing `cad/SeedCell.FCStd` in the FreeCAD GUI instead of
  `scripts/build_model.py` — silently discarded on the next regenerate.
- Skipping the ADR and going straight to CAD/logic changes — `DECISIONS.md`
  is append-only and expected to carry the *why*, not just the *what*.
- Assuming a CAD change auto-propagates to the Godot twin — there is no mesh
  export pipeline yet; only the process-logic files are kept in sync by hand.
- Touching a safety function's logic or geometry without updating
  `docs/SAFETY.md` — there is no separate `TRACEABILITY.md` to catch this.
- Forgetting downstream analysis scripts (`cook_energy.py`,
  `actuator_sizing.py`, `dosing.py`, `residue.py`) that derive from the same
  parameters as `build_model.py`.
- Renumbering or reusing an ADR number.
