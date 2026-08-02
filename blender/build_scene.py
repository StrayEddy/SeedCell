"""Build + render the SeedCell hero still (headless Cycles/CPU).

Run:
  blender --background --factory-startup --python blender/build_scene.py

Reads blender/models/ (exported by scripts/export_blender.py) for the real part
dimensions, assembles a "night at the wall" product shot -- an armored flush public
wall with a recessed delivery mouth, the stainless mouth die, and a fresh flatbread
presented in the mouth (the warm focal point) -- lights it, and renders to
assets/hero.png (committed; renders/ is gitignored).
Env: SEED_SAMPLES (default 128), SEED_RES (default 1600x1000).
"""
import json
import math
import os
import bpy
from mathutils import Vector

ROOT = "/home/eddy/Projects/SeedCell"
MODELS = os.path.join(ROOT, "blender", "models")
OUT = os.path.join(ROOT, "assets", "hero.png")
S = json.load(open(os.path.join(MODELS, "scene.json")))

SAMPLES = int(os.environ.get("SEED_SAMPLES", "128"))
RES = os.environ.get("SEED_RES", "1600x1000").split("x")

bpy.ops.wm.read_factory_settings(use_empty=True)


def new_mat(name):
	m = bpy.data.materials.new(name)
	m.use_nodes = True
	return m, m.node_tree, m.node_tree.nodes["Principled BSDF"]


def simple(name, base, metallic=0.0, rough=0.5, aniso=0.0):
	m, nt, b = new_mat(name)
	b.inputs["Base Color"].default_value = (*base, 1.0)
	b.inputs["Metallic"].default_value = metallic
	b.inputs["Roughness"].default_value = rough
	if "Anisotropic" in b.inputs:
		b.inputs["Anisotropic"].default_value = aniso
	return m


def matte_bumped(name, base, rough, noise_scale, bump_strength):
	"""A matte surface with a subtle procedural bump so a flat panel still reads as material."""
	m, nt, b = new_mat(name)
	b.inputs["Base Color"].default_value = (*base, 1.0)
	b.inputs["Metallic"].default_value = 0.0
	b.inputs["Roughness"].default_value = rough
	tex = nt.nodes.new("ShaderNodeTexNoise")
	tex.inputs["Scale"].default_value = noise_scale
	tex.inputs["Detail"].default_value = 6.0
	bump = nt.nodes.new("ShaderNodeBump")
	bump.inputs["Strength"].default_value = bump_strength
	nt.links.new(tex.outputs["Fac"], bump.inputs["Height"])
	nt.links.new(bump.outputs["Normal"], b.inputs["Normal"])
	return m


def bread_mat():
	"""Baked flatbread: color varies with noise, crust bump from a finer noise."""
	m, nt, b = new_mat("bread")
	b.inputs["Metallic"].default_value = 0.0
	b.inputs["Roughness"].default_value = 0.82
	# colour variation
	n1 = nt.nodes.new("ShaderNodeTexNoise"); n1.inputs["Scale"].default_value = 9.0
	n1.inputs["Detail"].default_value = 4.0
	ramp = nt.nodes.new("ShaderNodeValToRGB")
	ramp.color_ramp.elements[0].position = 0.30
	ramp.color_ramp.elements[0].color = (0.34, 0.17, 0.07, 1)   # deep toasted
	ramp.color_ramp.elements[1].position = 0.70
	ramp.color_ramp.elements[1].color = (0.66, 0.42, 0.18, 1)   # rich golden
	nt.links.new(n1.outputs["Fac"], ramp.inputs["Fac"])
	nt.links.new(ramp.outputs["Color"], b.inputs["Base Color"])
	# a faint warmth so it reads as fresh/warm, but it is LIT not glowing
	b.inputs["Emission Color"].default_value = (0.8, 0.4, 0.15, 1)
	b.inputs["Emission Strength"].default_value = 0.08
	# crust bump
	n2 = nt.nodes.new("ShaderNodeTexNoise"); n2.inputs["Scale"].default_value = 55.0
	n2.inputs["Detail"].default_value = 3.0
	bump = nt.nodes.new("ShaderNodeBump"); bump.inputs["Strength"].default_value = 0.28
	nt.links.new(n2.outputs["Fac"], bump.inputs["Height"])
	nt.links.new(bump.outputs["Normal"], b.inputs["Normal"])
	return m


mat_wall = matte_bumped("wall", (0.020, 0.022, 0.026), 0.62, 9.0, 0.10)
mat_steel = simple("steel", (0.60, 0.62, 0.65), metallic=1.0, rough=0.20, aniso=0.6)
mat_floor = matte_bumped("floor", (0.02, 0.02, 0.024), 0.55, 4.0, 0.06)
mat_bread = bread_mat()


def set_mat(obj, mat):
	obj.data.materials.clear()
	obj.data.materials.append(mat)


def imp(name):
	before = set(bpy.data.objects)
	bpy.ops.wm.obj_import(filepath=os.path.join(MODELS, f"{name}.obj"))
	new = list(set(bpy.data.objects) - before)
	return new[0] if new else None


def smooth(o):
	try:
		bpy.context.view_layer.objects.active = o
		bpy.ops.object.shade_smooth()
	except Exception:
		pass


# ---- armored public wall with a recessed round mouth ----------------------
bore_r = S["bore_dia_m"] / 2.0
hole_r = bore_r + S["wall_thk_m"] + 0.003
wall_w, wall_h, wall_d = 3.2, 2.4, 0.35
bpy.ops.mesh.primitive_cube_add(size=1.0)
wall = bpy.context.active_object
wall.name = "PublicWall"
wall.scale = (wall_d / 2, wall_w / 2, wall_h / 2)
wall.location = (wall_d / 2, 0, 0)
bpy.ops.object.transform_apply(scale=True, location=True)
bpy.ops.mesh.primitive_cylinder_add(radius=hole_r, depth=wall_d * 3, vertices=128)
cutter = bpy.context.active_object
cutter.rotation_euler = (0, math.radians(90), 0)
cutter.location = (wall_d / 2, 0, 0)
bpy.ops.object.transform_apply(rotation=True, location=True)
boo = wall.modifiers.new("mouth", "BOOLEAN")
boo.operation = "DIFFERENCE"; boo.object = cutter
bpy.context.view_layer.objects.active = wall
bpy.ops.object.modifier_apply(modifier="mouth")
bpy.data.objects.remove(cutter, do_unlink=True)
set_mat(wall, mat_wall)

# ---- recessed cook chamber (dark interior behind the mouth) ----------------
# An open dark tube gives the mouth real depth so the warm bread reads against a
# shadowed interior. Primitives only: the imported CAD parts land at their FreeCAD
# origins -- the solid Piston (x[0,0.12], r0.08) sits square in the mouth and
# occludes the bread -- so they belong to the /godot twin, not this beauty shot.
chamber_len = S["barrel_len_m"]
bpy.ops.mesh.primitive_cylinder_add(radius=bore_r, depth=chamber_len, vertices=128,
	end_fill_type="NOTHING")
chamber = bpy.context.active_object
chamber.name = "CookChamber"
chamber.rotation_euler = (0, math.radians(90), 0)
chamber.location = (S["die_thk_m"] + chamber_len / 2, 0, 0)
bpy.ops.object.transform_apply(rotation=True)
set_mat(chamber, mat_wall); smooth(chamber)

# ---- stainless mouth die (the one bright ring that frames the aperture) ----
die_or = hole_r
die_ir = S["delivery_dia_m"] / 2.0
bpy.ops.mesh.primitive_cylinder_add(radius=die_or, depth=S["die_thk_m"], vertices=128)
die = bpy.context.active_object
die.rotation_euler = (0, math.radians(90), 0)
die.location = (S["die_thk_m"] / 2, 0, 0)
bpy.ops.object.transform_apply(rotation=True, location=True)
bpy.ops.mesh.primitive_cylinder_add(radius=die_ir, depth=S["die_thk_m"] * 4, vertices=128)
dcut = bpy.context.active_object
dcut.rotation_euler = (0, math.radians(90), 0)
dcut.location = (S["die_thk_m"] / 2, 0, 0)
bpy.ops.object.transform_apply(rotation=True, location=True)
dboo = die.modifiers.new("aperture", "BOOLEAN")
dboo.operation = "DIFFERENCE"; dboo.object = dcut
bpy.context.view_layer.objects.active = die
bpy.ops.object.modifier_apply(modifier="aperture")
bpy.data.objects.remove(dcut, do_unlink=True)
die.name = "MouthDie"
dbev = die.modifiers.new("edge", "BEVEL"); dbev.width = 0.003; dbev.segments = 3
set_mat(die, mat_steel); smooth(die)

# ---- the flatbread: the warm hero, seated just inside the mouth ------------
br = S["flatbread_dia_m"] / 2.0
bt = S["flatbread_thk_m"]
bpy.ops.mesh.primitive_cylinder_add(radius=br, depth=bt, vertices=128)
bread = bpy.context.active_object
bread.name = "Flatbread"
bread.rotation_euler = (0, math.radians(90), 0)
bread.location = (S["die_thk_m"] + bt, 0, 0)   # proud of the die, framed by the ring
bpy.ops.object.transform_apply(rotation=True)
bev = bread.modifiers.new("edge", "BEVEL"); bev.width = 0.005; bev.segments = 4
set_mat(bread, mat_bread); smooth(bread)

# ---- floor (sidewalk, for warm bounce) ------------------------------------
bpy.ops.mesh.primitive_plane_add(size=14.0)
floor = bpy.context.active_object
floor.location = (0, 0, -wall_h / 2)
set_mat(floor, mat_floor)

# ---- lighting ("night at the wall") ---------------------------------------
world = bpy.data.worlds.new("W")
bpy.context.scene.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.008, 0.01, 0.016, 1)
world.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.0


def add_area(name, loc, energy, color, size, target=Vector((0, 0, 0))):
	ld = bpy.data.lights.new(name, "AREA")
	ld.energy = energy; ld.color = color; ld.size = size
	ob = bpy.data.objects.new(name, ld)
	bpy.context.collection.objects.link(ob)
	ob.location = loc
	ob.rotation_euler = (target - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
	return ob


add_area("key", (-0.9, -0.85, 0.5), 90.0, (1.0, 0.6, 0.26), 0.8)     # warm pool at the mouth
add_area("fill", (-1.5, -0.7, 0.1), 12.0, (1.0, 0.72, 0.5), 1.8)     # gentle lift
add_area("rim", (0.2, 1.1, 1.0), 95.0, (0.45, 0.6, 1.0), 0.9)         # cool rim defines the steel die
gp = bpy.data.lights.new("mouthglow", "POINT")
gp.energy = 14.0; gp.color = (1.0, 0.52, 0.2); gp.shadow_soft_size = 0.06
gpo = bpy.data.objects.new("mouthglow", gp)
bpy.context.collection.objects.link(gpo)
gpo.location = (0.06, 0, 0)   # just proud of the die, warming the bread face

# ---- camera (tight 3/4 hero on the mouth) ---------------------------------
cd = bpy.data.cameras.new("cam"); cd.lens = 62
cam = bpy.data.objects.new("cam", cd)
bpy.context.collection.objects.link(cam)
cam.location = (-0.82, -0.62, 0.16)
_t = Vector((0.02, 0.0, 0.0))
cam.rotation_euler = (_t - cam.location).to_track_quat("-Z", "Y").to_euler()
bpy.context.scene.camera = cam
cd.dof.use_dof = True
cd.dof.focus_distance = (Vector((S["die_thk_m"] + bt, 0, 0)) - cam.location).length
cd.dof.aperture_fstop = 5.6

# ---- render ---------------------------------------------------------------
sc = bpy.context.scene
sc.render.engine = "CYCLES"; sc.cycles.device = "CPU"
sc.cycles.samples = SAMPLES; sc.cycles.use_denoising = True
try:
	sc.cycles.denoiser = "OPENIMAGEDENOISE"
except Exception:
	pass
sc.render.resolution_x = int(RES[0]); sc.render.resolution_y = int(RES[1])
sc.render.image_settings.file_format = "PNG"
try:
	sc.view_settings.view_transform = "AgX"
except Exception:
	sc.view_settings.view_transform = "Filmic"
sc.view_settings.exposure = -0.6           # keep it moody, not washed out
sc.render.filepath = OUT
os.makedirs(os.path.dirname(OUT), exist_ok=True)
bpy.ops.render.render(write_still=True)
print(f"HERO RENDER WRITTEN: {OUT}")
