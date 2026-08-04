"""Piston-drive sizing for SeedCell -- first-order numbers (reproducible).

Run headless:
  flatpak run --command=freecadcmd org.freecad.FreeCAD \
      /home/eddy/Projects/SeedCell/scripts/actuator_sizing.py

Horizontal, slow motion => inertia negligible, gravity carried by the bore/guidance.
Unlike HiveCell (where seal drag dominated), SeedCell's piston mostly fights the DOUGH
PRESSING force that forms the flatbread; scraper drag + bread release are secondary.
All ASSUMPTIONS are constants below and are the biggest unknowns; override the scraper
drag with env SCRAPER_DRAG_PER_M and the forming pressure with env FORM_KPA.
"""
import math
import os
import FreeCAD as App

DOC = "/home/eddy/Projects/SeedCell/cad/SeedCell.FCStd"

# --- assumptions (refine with real data / tests) ---------------------------
G = 9.81
FORM_KPA = float(os.environ.get("FORM_KPA", "50.0"))          # kPa dough forming pressure
SCRAPER_DRAG_PER_M = float(os.environ.get("SCRAPER_DRAG_PER_M", "80.0"))  # N/m per lip (see residue.py)
RELEASE_KPA = 0.6         # kPa to peel a cooked bread off a low-adhesion surface (residue.py HIGH)
PRESS_S = 4.0            # s   forming stroke duration
SAFETY = 2.0            # design safety factor on force
ETA = 0.5               # drivetrain efficiency

doc = App.open(DOC)
s = next(o for o in doc.Objects if o.TypeId == "Spreadsheet::Sheet")

pdia = s.pistonDia.Value / 1000.0        # m
area = math.pi * (pdia / 2.0) ** 2        # m^2 piston face
perim = math.pi * s.boreDia.Value / 1000.0  # m
lips = int(s.sealLipCount)
close_travel = s.chargeDepth.Value / 1000.0  # m -- open (charge/hydrate) to flush; this
                                              # IS the forming/press stroke (ADR-0019), not
                                              # the full present<->clean stroke below it

# forces
f_form = FORM_KPA * 1000.0 * area                 # press the dough into a thin disc
f_scrape = SCRAPER_DRAG_PER_M * perim * lips      # SF3 scraper drag over the stroke
f_release = RELEASE_KPA * 1000.0 * area           # peel the baked bread off the face
f_close = f_form + f_scrape                        # forming stroke: press + scrape (demanding)
f_eject = f_release + f_scrape                     # ejection stroke: peel + scrape
f_design = SAFETY * max(f_close, f_eject)

# speed / power / energy on the forming (demanding) stroke
v = close_travel / PRESS_S
p_mech = f_close * v
p_elec = p_mech / ETA
energy_wh = p_elec * PRESS_S / 3600.0

print("--- piston-drive sizing (first-order) ---")
print(f"piston face area   : {area*1e4:8.1f} cm^2")
print(f"scraper perimeter  : {perim:8.3f} m   ({lips} lips -> {perim*lips:.3f} m contact)")
print(f"force FORM dough    : {f_form:8.0f} N   (@ {FORM_KPA:.0f} kPa)")
print(f"force SCRAPER drag  : {f_scrape:8.0f} N   (@ {SCRAPER_DRAG_PER_M:.0f} N/m x {lips} lips)")
print(f"force RELEASE bread : {f_release:8.0f} N   (@ {RELEASE_KPA:.1f} kPa)")
print(f"force CLOSE (form)   : {f_close:8.0f} N   <-- press + scrape (demanding stroke)")
print(f"force EJECT          : {f_eject:8.0f} N   (peel + scrape)")
print(f"force DESIGN (x{SAFETY:.0f})  : {f_design:8.0f} N   <-- pick actuator >= this")
print(f"travel speed        : {v*1000:8.1f} mm/s")
print(f"power  electrical   : {p_elec:8.1f} W   (eta={ETA})")
print(f"energy per stroke   : {energy_wh:8.3f} Wh")
print()
print("NOTE: dough forming pressure dominates (vs seal drag in HiveCell). Scraper drag")
print("      is the SF3<->cleaning lever here -- MEASURE it with residue (residue.py).")

App.closeDocument(doc.Name)
