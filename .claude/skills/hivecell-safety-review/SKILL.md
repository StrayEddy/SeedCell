---
name: hivecell-safety-review
description: Use before merging or pushing a change that touches SeedCell's safety-critical process logic (godot/process_interlock.gd, cook_lethality.gd, lethality_model.gd, spore_hold.gd, collection_guard.gd, soft_profile.gd) or a safety function/hazard entry in docs/SAFETY.md.
---

# hivecell-safety-review

## Overview
SeedCell's core invariant — a batch that is not provably cooked (SF1) and
served on a provably clean surface (SF2) is waste, never a serving — is
enforced by headless Godot self-tests, gated on every push by a local git
hook. There is no separate CI. This skill is the pre-merge/pre-push checklist
for a change touching that logic.

## When to use
Before pushing or merging any change to `godot/process_interlock.gd`,
`cook_lethality.gd`, `lethality_model.gd`, `spore_hold.gd`,
`collection_guard.gd`, `soft_profile.gd`, or any test under `godot/tests/`;
or any change to a safety function (SF1-SF9) / hazard (H1-H11) entry in
`docs/SAFETY.md`.

## Procedure
1. Confirm the pre-push hook is active for this clone (once):
   `git config core.hooksPath .githooks`. Without it, `git push` does not
   run the safety gate at all.
2. Run the self-tests directly before pushing:
   `./scripts/run_selftest.sh`
   (set `GODOT_BIN` if Godot 4 isn't on `PATH`; it also checks
   `/home/eddy/Godot/Godot_v4.7.1-stable_linux.x86_64`). It must print
   `run_selftest: all tests passed.` — all six suites (`test_interlock.gd`,
   `test_cook_lethality.gd`, `test_lethality_model.gd`, `test_spore_hold.gd`,
   `test_collection.gd`, `test_soft_profile.gd`) must exit 0.
3. Verify the core invariant is enforced structurally, not just passing by
   coincidence: `PRESENT` must be reachable only through a passed
   `LETHALITY_CHECK` (SF1), and any failed cook/clean/collection/mouth-clear
   path must route to `DIVERT`/`CLEAN`/`LOCKOUT`, never to a person. If the
   change adds a new state or transition, add a matching scenario to the
   relevant `test_*.gd` rather than trusting existing coverage.
4. Cross-check `docs/SAFETY.md` is still accurate: the affected SF's status
   tag (`[sim]`/`[decision]`/`[cad]`/`[todo]`), the hazard register row's
   "Required safety function" column, the FMEA table if a failure mode's
   S/O/D changed, and the "Implementation status (digital twin)" list naming
   the `.gd` file. Update the ADR citation if the change stems from a new or
   amended ADR.
5. If the change resolves or reopens anything in `docs/SAFETY.md`'s "Open
   items" list, update it in the same commit.
6. Only push once `run_selftest.sh` passes locally — `.githooks/pre-push`
   re-runs it (and uploads Git LFS objects first) and will block the push
   otherwise.

## Common mistakes
- Pushing without `core.hooksPath` configured, so the gate silently never
  runs.
- Treating a green `run_selftest.sh` as sufficient without adding a scenario
  for a genuinely new state/transition — the suite only catches what it has
  a scenario for (see the exhaustive 3⁴-combination check in
  `test_cook_lethality.gd` as the bar).
- Editing a `.gd` safety file without updating `docs/SAFETY.md`'s status tag
  or hazard row — `SAFETY.md` is SeedCell's only traceability record, so a
  stale entry has nothing else to catch it.
- Forgetting that SF7's bake→serve hold budget and SF8's collection window
  are nested (SF7 must dominate) — a change to one that isn't re-checked
  against the other can silently break the nesting invariant.
- Assuming CI runs this — SeedCell has no GitHub Actions workflow; the only
  gate is the local pre-push hook.
