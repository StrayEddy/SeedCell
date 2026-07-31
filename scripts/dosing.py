"""SeedCell serving dosing -- nutrition + cost from the dry blend (first-order).

Run:  python3 scripts/dosing.py

No FreeCAD / no deps: this is a mass-balance over the ingredient blend, the food
analog of a bill-of-materials. It answers the nutrition + cost half of the design
targets (README): ~500-700 kcal, ~20-30 g protein, ~$0.15-0.25 ingredient cost per
serving. Tune the grams below; everything downstream (kcal, protein, cost) follows.
The blend itself is a placeholder pending the residue/anti-stick work (ADR-0012) --
a stickier, higher-hydration dough may be forced leaner to release cleanly.
"""

# ingredient: (grams, kcal/100g, protein g/100g, USD/kg bulk)   -- refine with real data
BLEND = {
	"whole wheat flour": (60.0, 340.0, 13.2, 0.90),
	"chickpea flour":    (45.0, 387.0, 22.0, 1.80),
	"red lentil flour":  (35.0, 350.0, 24.0, 1.60),
	"vegetable oil":     ( 8.0, 884.0,  0.0, 1.50),
	"salt":              ( 2.0,   0.0,  0.0, 0.30),
	"micronutrient premix": (0.5, 0.0, 0.0, 8.00),  # fortificant: iron, B12, iodine, zinc, folate
}
WATER_G = 70.0          # injected to hydrate (ADR-0006); ~free ingredient, utility cost elsewhere
BAKE_LOSS_FRAC = 0.10   # mass fraction lost as steam during the bake (affects served mass only)

# design targets (README)
KCAL_TARGET = (500.0, 700.0)
PROTEIN_TARGET = (20.0, 30.0)
COST_TARGET = (0.15, 0.25)

dry_g = sum(v[0] for v in BLEND.values())
kcal = sum(v[0] / 100.0 * v[1] for v in BLEND.values())
protein = sum(v[0] / 100.0 * v[2] for v in BLEND.values())
cost = sum(v[0] / 1000.0 * v[3] for v in BLEND.values())
dough_g = dry_g + WATER_G
served_g = dough_g * (1.0 - BAKE_LOSS_FRAC)


def _flag(x, lo, hi):
	return "OK " if lo <= x <= hi else ("LOW" if x < lo else "HIGH")


print("--- SeedCell serving dosing (first-order) ---")
print(f"{'ingredient':22s} {'g':>6s} {'kcal':>7s} {'protein':>8s} {'USD':>8s}")
for name, (g, kc, pr, usd) in BLEND.items():
	print(f"{name:22s} {g:6.1f} {g/100*kc:7.1f} {g/100*pr:8.1f} {g/1000*usd:8.4f}")
print(f"{'water (injected)':22s} {WATER_G:6.1f} {'-':>7s} {'-':>8s} {'-':>8s}")
print("-" * 54)
print(f"dry blend mass     : {dry_g:8.1f} g")
print(f"dough mass (w/water): {dough_g:8.1f} g")
print(f"served mass (baked) : {served_g:8.1f} g   (-{BAKE_LOSS_FRAC*100:.0f}% steam loss)")
print(f"energy             : {kcal:8.0f} kcal   [{_flag(kcal, *KCAL_TARGET)}] target {KCAL_TARGET[0]:.0f}-{KCAL_TARGET[1]:.0f}")
print(f"protein            : {protein:8.1f} g     [{_flag(protein, *PROTEIN_TARGET)}] target {PROTEIN_TARGET[0]:.0f}-{PROTEIN_TARGET[1]:.0f}")
print(f"protein energy %   : {protein*4/kcal*100:8.1f} %")
print(f"ingredient cost    : {cost:8.4f} USD  [{_flag(cost, *COST_TARGET)}] target {COST_TARGET[0]:.2f}-{COST_TARGET[1]:.2f}")
print()
print("NOTE: utilities (cook energy, cleaning water/heat) and maintenance are separate --")
print("      see cook_energy.py; the README operating-cost target adds them on top.")
