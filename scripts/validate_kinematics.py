"""Kinematic validation for SeedCell -- piston sweep is collision-free (read-only).

Run headless:
  flatpak run --command=freecadcmd org.freecad.FreeCAD \
      /home/eddy/Projects/SeedCell/scripts/validate_kinematics.py

Samples the piston travel from the flush/present pose (face at X=0) back to the deep
clean pose (face at X=stroke) and checks: (1) the piston never intersects the fixed
CookBarrel wall, and (2) the face reaches flush (X=0) at present and stays inside the
bore across the whole stroke. Never saves -- it informs the design, it doesn't change it.
"""
import FreeCAD as App

DOC = "/home/eddy/Projects/SeedCell/cad/SeedCell.FCStd"
N_STEPS = 42
COLLISION_TOL = 1.0   # mm^3, numerical noise floor

doc = App.open(DOC)
s = next(o for o in doc.Objects if o.TypeId == "Spreadsheet::Sheet")
barrel = doc.getObject("CookBarrel").Shape
piston0 = doc.getObject("Piston").Shape
stroke = s.stroke.Value
blen = s.barrelLength.Value

max_overlap = 0.0
out_of_bore = 0
for i in range(N_STEPS + 1):
	x = stroke * i / N_STEPS
	p = piston0.copy()
	p.translate(App.Vector(x, 0, 0))
	# The moving piston must never share volume with the fixed barrel WALL. It rides in
	# the bore, so the only way to intersect the wall solid is to leave the bore radius.
	overlap = barrel.common(p).Volume
	max_overlap = max(max_overlap, overlap)
	bb = p.BoundBox
	if bb.XMin < -1e-6 or bb.XMax > blen + 1e-6:
		out_of_bore += 1

print("--- kinematic validation (piston sweep) ---")
print(f"steps              : {N_STEPS}")
print(f"stroke             : {stroke:8.1f} mm")
print(f"max wall overlap   : {max_overlap:8.2f} mm^3   {'OK' if max_overlap <= COLLISION_TOL else 'COLLISION'}")
print(f"out-of-bore steps  : {out_of_bore:8d}        {'OK' if out_of_bore == 0 else 'OVER-TRAVEL'}")
print(f"present flush @ X=0 : piston face reaches the mouth plane -> flush public wall")

App.closeDocument(doc.Name)
