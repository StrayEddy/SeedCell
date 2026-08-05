"""Export the SeedCell CAD parts to Blender-ready meshes + a dims manifest.

Run headless:
  flatpak run --command=freecadcmd org.freecad.FreeCAD \
      /home/eddy/Projects/SeedCell/scripts/export_blender.py

Writes one OBJ per Part::Feature to blender/models/ and a scene.json of key dimensions.
Blender uses the same Z-up axis as FreeCAD, so the only transform is mm -> m (x0.001);
the +X motion axis is preserved (ADR-0014). These are regenerable artifacts (gitignored);
the committed hero render is produced from them by blender/build_scene.py.
"""
import json
import os
import FreeCAD as App

DOC = "/home/eddy/Projects/SeedCell/cad/SeedCell.FCStd"
OUT = "/home/eddy/Projects/SeedCell/blender/models"
DEFLECTION = 0.2   # mm linear deflection -> smooth silhouettes for render

os.makedirs(OUT, exist_ok=True)
doc = App.open(DOC)
s = next(o for o in doc.Objects if o.TypeId == "Spreadsheet::Sheet")

parts = [o for o in doc.Objects if o.TypeId == "Part::Feature"]
for o in parts:
	verts, facets = o.Shape.tessellate(DEFLECTION)
	path = os.path.join(OUT, f"{o.Name}.obj")
	with open(path, "w") as f:
		f.write(f"# SeedCell {o.Name} (mm->m x0.001, Z-up)\n")
		f.write(f"o {o.Name}\n")
		for v in verts:
			f.write(f"v {v.x/1000.0:.6f} {v.y/1000.0:.6f} {v.z/1000.0:.6f}\n")
		for a, b, c in facets:
			f.write(f"f {a+1} {b+1} {c+1}\n")
	print(f"wrote {path}  ({len(verts)} v, {len(facets)} f)")

manifest = {
	"units": "metres, Z-up (Blender/FreeCAD)",
	"bore_dia_m": s.boreDia.Value / 1000.0,
	"wall_thk_m": s.wallThickness.Value / 1000.0,
	"barrel_len_m": s.barrelLength.Value / 1000.0,
	"piston_len_m": s.pistonLength.Value / 1000.0,
	"stroke_m": s.stroke.Value / 1000.0,
	"charge_depth_m": s.chargeDepth.Value / 1000.0,
	"flatbread_dia_m": s.flatbreadDia.Value / 1000.0,
	"flatbread_thk_m": s.flatbreadThk.Value / 1000.0,
	# No die keys since ADR-0021 -- the bore ends in a plain open cylinder at the wall
	# plane. The bread's protrusion at full presentation is just flatbread_thk_m.
	"parts": [o.Name for o in parts],
}
with open(os.path.join(OUT, "scene.json"), "w") as f:
	json.dump(manifest, f, indent=2)
print(f"wrote {os.path.join(OUT, 'scene.json')}")

App.closeDocument(doc.Name)
