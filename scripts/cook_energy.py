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
T_KILL = 75.0            # C   NOT the kill-step any more -- kept only as a familiar
                         #     landmark on the heating curve. The kill-step is the
                         #     F-value in section 2 (ADR-0015).
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


def core_temp(t):
    """Core (mid-plane) temperature at time t [s], capped at the moisture plateau.

    The conduction solution alone runs the core asymptotically toward T_PLATEN, which
    is wrong for a wet dough: while free water remains, the core stalls near boiling
    because the energy goes into evaporation, not sensible heat. Capping at
    CORE_PLATEAU_C keeps the lethality integral honest AND conservative -- it is the
    lower of the two curves everywhere.
    """
    theta = min(1.0, (4.0 / math.pi) * math.exp(-((math.pi / 2.0) ** 2) * ALPHA * t / (L * L)))
    return min(CORE_PLATEAU_C, T_PLATEN - theta * (T_PLATEN - T_START))


# --- 2. lethality: accumulate the real F-value over the core's temperature history ---
# Mirrors godot/lethality_model.gd (ADR-0015) -- keep the constants in step. The old
# check here was "does the core pass 75 C", which is not a kill-step: it says nothing
# about hold time. What matters is F = integral of 10^((T - T_REF)/z) dt.
T_REF = 70.0             # C   reference temperature for the F-value
Z_VALUE = 6.29           # C   fitted to FDA Food Code 3-401.11 (63C/3min, 66C/1min)
TARGET_LOG = 7.0         # log10 reductions of Salmonella required to serve
T_FLOOR = 60.0           # C   no lethality credit accrues below this
CORE_PLATEAU_C = 100.0   # C   wet-core evaporation plateau (see core_temp)
D_REF = (180.0 / TARGET_LOG) * 10.0 ** ((63.0 - T_REF) / Z_VALUE)   # s, D-value at T_REF
F_TARGET = TARGET_LOG * D_REF                                       # s, equivalent at T_REF

DT = 0.01
T_MAX = 600.0
f_value = 0.0
t_floor = None           # first time the core clears the accumulation floor
t_lethal = None          # first time the accumulated F clears the target
steps = int(T_MAX / DT)
for i in range(steps):
    t = i * DT
    tc = core_temp(t)
    if t_floor is None and tc >= T_FLOOR:
        t_floor = t
    if tc >= T_FLOOR:
        f_value += 10.0 ** ((tc - T_REF) / Z_VALUE) * DT
    if t_lethal is None and f_value >= F_TARGET:
        t_lethal = t
        break

lethal = t_lethal is not None
# F banked by the end of the nominal cycle the interlock actually runs.
f_at_cycle = 0.0
for i in range(int(90.0 / DT)):
    tc = core_temp(i * DT)
    if tc >= T_FLOOR:
        f_at_cycle += 10.0 ** ((tc - T_REF) / Z_VALUE) * DT

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
print()
print(f"--- SF1 kill-step (ADR-0015: {TARGET_LOG:.0f}-log Salmonella, z={Z_VALUE} C) ---")
print(f"F{T_REF:.0f} target          : {F_TARGET:8.2f} equivalent seconds at {T_REF:.0f} C")
print(f"core clears {T_FLOOR:.0f} C    : {t_floor if t_floor is None else round(t_floor, 1):>8} s")
print(f"F target reached at : {t_lethal if t_lethal is None else round(t_lethal, 1):>8} s"
      f"   ({'' if not lethal else f'{t_lethal/60:.1f} min'})")
print(f"F banked in a 90 s cycle: {f_at_cycle:8.0f} s-equivalent"
      f"   ({f_at_cycle/F_TARGET:,.0f}x the target)")
print(f"LETHALITY (SF1)     : {'PASS -- kill-step is cleared well inside the cycle' if lethal else 'FAIL -- F never reaches target'}")
print(f"energy into food    : {e_food/1000:8.1f} kJ   (sensible {e_sensible/1000:.0f} + latent {e_latent/1000:.0f})")
print(f"energy from mains    : {e_input/1000:8.1f} kJ   (eta={ETA_HEAT})")
print(f"ENERGY per serving  : {wh_serving:8.1f} Wh")
print()
print("NOTE: this sizes the on-demand bake only. Holding the platens hot between")
print("      servings, and the cleaning steam/hot-water (SF2), add to the utility")
print("      budget -- quantify alongside cleaning_budget once the cycle is fixed.")
print()
print("NOTE: the huge margin on F is the expected result, not a green light. A hydrated")
print("      core plateaus near 100 C, where lethality accrues ~250,000x faster than at")
print("      the 70 C reference, so ANY genuine bake overshoots the target enormously.")
print("      The F-value exists to catch the FAILED cook -- a cold core, a short cycle, a")
print("      dead probe -- not to constrain the good one. It also says nothing about")
print("      Bacillus cereus spores, which survive this bake; those are controlled by")
print("      serving immediately and never holding warm (see lethality_model.gd).")
