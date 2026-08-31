<!-- BOARD
url: https://claude.ai/code/artifact/95ab8c92-9521-4003-a6eb-bbed1aa530a9
headline: On hold since 2026-08-05; the residue/release bench test is the master variable blocking SF2/SF3. ADR-0017 is decided and committed, so the bore geometry is no longer blocked.
now:
- P0 1 residue + release bench test (~$150-250, `docs/residue_bench_test.md`, ADR-0011) — the master variable; gates SF2, SF3, surface + formula
review:
-->

# SeedCell — TODO

**Status: on hold** since 2026-08-05. Narrative + priorities live in `docs/ROADMAP.md`. This file is the actionable checklist the desktop board reads — keep the two in sync.

## Now
- [ ] 1 Residue + release bench test (~$150–250, `docs/residue_bench_test.md`, ADR-0011) — the master variable; gates SF2, SF3, surface + formula
- [ ] 2 Clean-verify sensor survey — prove a food surface is clean every cycle, unattended (SF2)
- [ ] 3 Implement ADR-0017 in CAD + twin — retractable heated anvil at ≥ 850 mm, freeze bore geometry, add `bakeDepth`

## Next
- [ ] 5 Jet-hydration dough trials — does blade-free injection mixing (ADR-0006) give uniform dough?
- [ ] 6 Low-adhesion coating durability — PTFE/ceramic under scrape + 230 °C + steam
- [ ] 7 Export pipeline → twin/render (`export_godot.py` + visual `process_demo` scene, ADR-0014)
- [ ] 8 SF4 burn/pinch hardware — surface-temp cap, mouth presence + safety edge
- [x] Commit the 3 uncommitted files in the working tree (site caption / ADR-0021 follow-up, 2026-08-05)

## Hardware / context gated
- [ ] 9 Single-chamber cook prototype (proves ADR-0006/0007)
- [ ] 10 Clean-cycle log-reduction validation (microbiology lab)
- [ ] 11 Food-safety certification dossier (HACCP + local food law)
- [ ] 12 SF1 lethality controller integrity (probe parts + rated controller)

## Done
- [x] Bore end: retractable heated anvil at ≥ 850 mm (ADR-0017) — 2026-08-11
- [x] Removed the mouth die (ADR-0021) — 2026-08-05
- [x] SF9 retract mouth-clear guard (ADR-0020) — 2026-08-04
- [x] Press order / `PRESS` state (ADR-0019) — 2026-08-04
- [x] SF8 uncollected-batch handling (ADR-0018) — 2026-08-04
- [x] F-value lethality target (ADR-0015) + SF7 bake→serve hold (ADR-0016) — 2026-08-03
