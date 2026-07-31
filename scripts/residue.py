"""SeedCell residue + release -- first-principles check on the master variable.

Run:  python3 scripts/residue.py

SeedCell's analog of HiveCell's seal_drag.py: a first-principles bracket on the ONE
number the whole machine hinges on. For HiveCell it was seal drag; for SeedCell it is
how much cooked-food RESIDUE remains on a food-contact surface after one bake+clean
cycle, and how hard the flatbread is to RELEASE from that surface. These couple:
  - SF2 (can the surface be self-cleaned to a safe residual every cycle?),
  - SF3 (the scraper/seal that does the mechanical part of that cleaning),
  - the surface material spec (PTFE / ceramic / seasoned steel), and
  - whether the "self-releasing flatbread" concept (ADR-0008) even works.
Three scenarios bracket the credible range. As with seal drag, the conclusion is the
same: specify a low-adhesion surface + a dry-flour boundary layer, and MEASURE it on a
real coupon (docs/residue_bench_test.md) before freezing the cleaning + scraper design.
"""
import math

# Contact area of one flatbread face (a disc); both faces + the bore band get soiled.
DIAM_MM = 160.0
area_cm2 = math.pi * (DIAM_MM / 20.0) ** 2       # one face, cm^2
peel_len_mm = math.pi * DIAM_MM                  # release crack runs around the rim

# scenario: (label, work of adhesion J/m^2, dry-flour boundary layer?, clean efficiency)
#   w_adh   -- dough<->surface adhesion energy after the bake (the driver)
#   boundary-- a dusted dry-flour film that bakes into the crust and leaves WITH the bread
#   clean_eff- fraction of the adhered film a scrape+steam+heat pass removes per cycle
SCEN = [
	("LOW  (PTFE + flour dusting, lean dough)", 0.010, True,  0.995),
	("NOMINAL (ceramic + flour dusting)",       0.040, True,  0.980),
	("HIGH (bare seasoned steel, no dusting)",  0.300, False, 0.900),
]

# An adhered wet-film areal density if NOTHING released (upper bound), scaled by how
# much the bake + boundary layer let the bread self-release before cleaning even runs.
FILM_MG_CM2_MAX = 8.0     # mg/cm^2 if the whole contact film stayed behind

print("--- SeedCell residue + release (first principles) ---")
print(f"one face area      : {area_cm2:8.1f} cm^2   (disc dia {DIAM_MM:.0f} mm)")
print(f"release crack length: {peel_len_mm/10:7.1f} cm   (around the rim)")
print()
print(f"{'scenario':42s} {'release kPa':>12s} {'residue mg/cm^2':>15s} {'per-serving mg':>14s}")
lo_res = None
hi_res = None
for label, w_adh, boundary, clean_eff in SCEN:
	# Release stress ~ work of adhesion over a crust-scale opening displacement (~0.5 mm).
	# A dry-flour boundary layer roughly halves the effective adhesion (bakes into crust).
	w_eff = w_adh * (0.5 if boundary else 1.0)
	release_kpa = (w_eff / 0.0005) / 1000.0
	# Residue after one clean pass: the fraction of the max film that both stays behind
	# after self-release (~ proportional to effective adhesion) AND survives cleaning.
	stuck_frac = min(1.0, w_eff / 0.30)          # 0.30 J/m^2 ~= "sticks completely"
	residue_mg_cm2 = FILM_MG_CM2_MAX * stuck_frac * (1.0 - clean_eff)
	per_serving_mg = residue_mg_cm2 * area_cm2 * 2.0   # both faces
	lo_res = residue_mg_cm2 if lo_res is None else min(lo_res, residue_mg_cm2)
	hi_res = residue_mg_cm2 if hi_res is None else max(hi_res, residue_mg_cm2)
	print(f"{label:42s} {release_kpa:12.3f} {residue_mg_cm2:15.4f} {per_serving_mg:14.2f}")

print()
print(f"credible residual range: {lo_res*1000:.2f} - {hi_res*1000:.0f} ug/cm^2 per cycle")
print("VERDICT: a low-adhesion surface + dry-flour boundary layer keeps release forces")
print("  low and per-cycle residue in the ug/cm^2 range -- plausibly self-cleanable. Bare")
print("  hot steel with no boundary layer sticks ~30x harder and leaves ~100x the residue,")
print("  smearing across servings. So (as with HiveCell's seal): make LOW adhesion a hard")
print("  requirement (ADR-0008/0011), and MEASURE residue + release on a real baked coupon")
print("  before freezing the cleaning method (SF2), the scraper (SF3), and the surface spec.")
