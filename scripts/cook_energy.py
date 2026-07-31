"""SeedCell cook thermodynamics -- cook time, lethality, energy (first-order).

Run:  python3 scripts/cook_energy.py

No FreeCAD / no deps. First-order model of the ADR-0007 conduction bake: a thin
flatbread pressed between two hot platens (the heated bore end/die and the heated
piston face). Answers three things the design leans on:
  1. COOK TIME  -- how long the core takes to reach the kill-step (conduction).
  2. LETHALITY   -- does the core clear the pathogen-kill target (SF1, ADR-0009)?
  3. ENERGY      -- Wh per serving to heat + partly dry the dough (utility cost).
All ASSUMPTIONS are constants below and are the biggest unknowns (dough properties,
platen temp); refine with real data. Override the platen temp with env COOK_PLATEN_C.
"""
import math
import os

# --- dough + geometry assumptions (refine with real data) ------------------
THICKNESS_MM = 8.0        # pressed flatbread thickness (two-sided heating)
DOUGH_KG = 0.220          # dough mass per serving (see dosing.py: dry + water)
RHO = 700.0               # kg/m^3   pressed dough
C_DOUGH = 2800.0          # J/kg.K   specific heat of wet dough
K_DOUGH = 0.30            # W/m.K    thermal conductivity of dough
ALPHA = K_DOUGH / (RHO * C_DOUGH)   # m^2/s   thermal diffusivity (~1.5e-7)

T_START = 20.0            # C   dough start temp
T_PLATEN = float(os.environ.get("COOK_PLATEN_C", "230.0"))  # C   hot platen/bore/piston face
T_KILL = 75.0            # C   core target for the kill-step (conservative; hold verified separately)
WATER_EVAP_G = 30.0      # g   water driven off as crust steam during the bake
H_FG = 2.26e6            # J/kg   latent heat of vaporization of water

# --- 1. cook time: conduction to the mid-plane of a two-sided-heated slab ---
# One-term series solution of the 1-D heat equation for a slab of half-thickness L,
# both faces held at T_PLATEN. Core (mid-plane) dimensionless temp theta reaches
#   theta = (T_PLATEN - T_core) / (T_PLATEN - T_START)
# with theta ~= (4/pi) * exp(-(pi/2)^2 * Fo),   Fo = alpha*t / L^2.
L = (THICKNESS_MM / 1000.0) / 2.0
theta_target = (T_PLATEN - T_KILL) / (T_PLATEN - T_START)
Fo = -math.log(theta_target * math.pi / 4.0) / (math.pi / 2.0) ** 2
t_cook = Fo * L * L / ALPHA          # s, to bring the CORE to T_KILL

# --- 2. lethality verdict ---------------------------------------------------
lethal = T_PLATEN > T_KILL and Fo > 0.0

# --- 3. energy per serving --------------------------------------------------
# Sensible heat to lift the whole mass to ~100 C, plus latent heat of the crust steam.
e_sensible = DOUGH_KG * C_DOUGH * (100.0 - T_START)      # J
e_latent = (WATER_EVAP_G / 1000.0) * H_FG                # J
e_food = e_sensible + e_latent                           # J into the food
ETA_HEAT = 0.55                                          # platen/thermal-mass/loss efficiency
e_input = e_food / ETA_HEAT                              # J drawn from the mains
wh_serving = e_input / 3600.0                            # Wh per serving

print("--- SeedCell cook thermodynamics (first-order) ---")
print(f"thermal diffusivity : {ALPHA*1e7:8.2f} e-7 m^2/s")
print(f"platen temperature  : {T_PLATEN:8.0f} C   (env COOK_PLATEN_C)")
print(f"flatbread thickness : {THICKNESS_MM:8.1f} mm  (half = {THICKNESS_MM/2:.1f} mm heated both sides)")
print(f"Fourier number Fo   : {Fo:8.3f}")
print(f"COOK TIME to core {T_KILL:.0f}C: {t_cook:7.0f} s   ({t_cook/60:.1f} min)")
print(f"LETHALITY (SF1)     : {'PASS -- core clears the kill target' if lethal else 'FAIL -- core never reaches target'}")
print(f"energy into food    : {e_food/1000:8.1f} kJ   (sensible {e_sensible/1000:.0f} + latent {e_latent/1000:.0f})")
print(f"energy from mains    : {e_input/1000:8.1f} kJ   (eta={ETA_HEAT})")
print(f"ENERGY per serving  : {wh_serving:8.1f} Wh")
print()
print("NOTE: this sizes the on-demand bake only. Holding the platens hot between")
print("      servings, and the cleaning steam/hot-water (SF2), add to the utility")
print("      budget -- quantify alongside cleaning_budget once the cycle is fixed.")
print("      T_KILL is a conservative core target; the real control is an accumulated")
print("      time-temperature lethality (F-value) integrated by SF1's ft_integrator.")
