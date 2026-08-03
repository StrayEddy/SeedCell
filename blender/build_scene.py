"""Build + render the SeedCell hero still (headless Cycles/CPU).

Run:
  blender --background --factory-startup --python blender/build_scene.py

Reads blender/models/ (exported by scripts/export_blender.py) for the real part
dimensions, assembles a "night at the wall" product shot -- an armored flush public
wall bored with the delivery mouth, the L-shaped delivery run behind it (long
horizontal tube out to the face, vertical drop chute 0.8 m back, piston parked
behind the chute), and a fresh flatbread just delivered at the mouth (the warm
focal point) -- lights it, and renders to assets/hero.png (committed; renders/ is
gitignored).
Env:
  SEED_SAMPLES  default 48 (OIDN denoises, so this is plenty)
  SEED_RES      default 1600x1000
  SEED_SECTION  "slot" (default, rounded square bore) | "round" (original circular bore)
  SEED_THROAT   in-tube service-light energy, default 0.8. Raise to inspect the delivery
                run; keep it low enough that the bread stays the brightest thing.
  SEED_OUT      output path, default assets/hero.png (use it to render variants safely)
"""
import json
import math
import os
import bmesh
import bpy
from mathutils import Vector

ROOT = "/home/eddy/Projects/SeedCell"
MODELS = os.path.join(ROOT, "blender", "models")
OUT = os.environ.get("SEED_OUT", os.path.join(ROOT, "assets", "hero.png"))
S = json.load(open(os.path.join(MODELS, "scene.json")))

SAMPLES = int(os.environ.get("SEED_SAMPLES", "48"))
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
	b.inputs["Emission Strength"].default_value = 0.05
	# crust bump
	n2 = nt.nodes.new("ShaderNodeTexNoise"); n2.inputs["Scale"].default_value = 55.0
	n2.inputs["Detail"].default_value = 3.0
	bump = nt.nodes.new("ShaderNodeBump"); bump.inputs["Strength"].default_value = 0.28
	nt.links.new(n2.outputs["Fac"], bump.inputs["Height"])
	nt.links.new(bump.outputs["Normal"], b.inputs["Normal"])
	return m


mat_wall = matte_bumped("wall", (0.020, 0.022, 0.026), 0.62, 9.0, 0.10)
mat_steel = simple("steel", (0.60, 0.62, 0.65), metallic=1.0, rough=0.20, aniso=0.6)
# Bore liner: bead-blasted food-grade stainless. Roughness has to stay HIGH -- at a
# polished 0.5 the in-tube service light smears into hard diagonal streaks across the
# liner (a specular reflection of the lamp, not a shadow, so no amount of broadening
# the source removes it). Dark, so the run reads as depth and never outshines the bread.
mat_liner = simple("liner", (0.22, 0.23, 0.25), metallic=1.0, rough=0.78)
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


def cyl(radius, depth, loc, axis="X", verts=128):
	"""A cylinder with its axis along X (default) or Z, baked to its location."""
	bpy.ops.mesh.primitive_cylinder_add(radius=radius, depth=depth, vertices=verts)
	o = bpy.context.active_object
	if axis == "X":
		o.rotation_euler = (0, math.radians(90), 0)
	o.location = loc
	bpy.ops.object.transform_apply(rotation=True, location=True)
	return o


def rr_profile(w, h, r, segs=8):
	"""Rounded-rectangle outline in the local (y, z) plane, CCW, centred on the origin."""
	a, b = w / 2.0, h / 2.0
	r = min(r, a, b)
	pts = []
	for (sy, sz, a0) in ((1, -1, -90.0), (1, 1, 0.0), (-1, 1, 90.0), (-1, -1, 180.0)):
		cy, cz = sy * (a - r), sz * (b - r)
		for k in range(segs + 1):
			t = math.radians(a0 + 90.0 * k / segs)
			pts.append((cy + r * math.cos(t), cz + r * math.sin(t)))
	return pts


def prism(x0, x1, sec0, sec1, name, segs=8):
	"""A rounded-rect prism (or frustum) along local +X, from section sec0=(w,h,r) at x0
	to sec1 at x1. This is the slot-section counterpart to cyl()."""
	p0, p1 = rr_profile(*sec0, segs), rr_profile(*sec1, segs)
	n = len(p0)
	verts = [(x0, y, z) for (y, z) in p0] + [(x1, y, z) for (y, z) in p1]
	faces = [(i, (i + 1) % n, (i + 1) % n + n, i + n) for i in range(n)]
	faces.append(tuple(range(n - 1, -1, -1)))   # cap at x0
	faces.append(tuple(range(n, 2 * n)))        # cap at x1
	me = bpy.data.meshes.new(name)
	me.from_pydata(verts, [], faces)
	me.update()
	ob = bpy.data.objects.new(name, me)
	bpy.context.collection.objects.link(ob)
	bm = bmesh.new()
	bm.from_mesh(me)
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)   # booleans need consistent normals
	bm.to_mesh(me)
	bm.free()
	return ob


def place(ob, rot=(0, 0, 0), loc=(0, 0, 0)):
	"""Bake a rotation + location into an object's mesh (so booleans see world coords)."""
	ob.rotation_euler = rot
	ob.location = loc
	bpy.context.view_layer.objects.active = ob
	bpy.ops.object.transform_apply(rotation=True, location=True)
	return ob


def cut(target, cutter, name="cut"):
	"""Boolean-difference `cutter` out of `target`, apply, and delete the cutter."""
	m = target.modifiers.new(name, "BOOLEAN")
	m.operation = "DIFFERENCE"
	m.object = cutter
	bpy.context.view_layer.objects.active = target
	bpy.ops.object.modifier_apply(modifier=name)
	bpy.data.objects.remove(cutter, do_unlink=True)


# ---- the delivery run: an "L" laid on its side ----------------------------
# Vertical leg  = the drop chute the baked bread falls down, deep inside the wall.
# Horizontal leg = the delivery tube the piston pushes the bread along, out to the
# public face. The tube is deliberately LONGER THAN AN ARM: someone at the mouth
# can never reach the chute to block or foul it -- they wait for the piston.
#
#   face x=0                                            chute      piston bay
#      |<----------- REACH_BLOCK (0.80 m) ------------->|<- 0.18 ->|
#      [ =========== delivery tube ====================][    ]     ] back cap
#                                                        || chute rises here
# There is NO tray. The bread rests directly on the floor of the bore -- the single
# surface the customer can touch, and the one the clean cycle scrubs between orders.
# A separate tray would add a second food-contact surface that never gets cleaned,
# plus two crumb-trapping seams where it meets the liner.
#
# SEED_SECTION picks the bore cross-section:
#   "slot"  (default) rounded SQUARE, 190 x 190. The FLAT floor is what makes "the bread
#           rests on the bore" work: a rigid flatbread on a flat floor sits dead flat.
#           Square rather than letterbox so the bore is tall enough for the camera to
#           look down into it -- a shallow slot hides the depth behind the bread. The
#           cost is opening area: 35,000 vs 45,200 mm^2, only ~1.3x better than the
#           circle (a 190 x 90 letterbox would be 2.7x). The 0.80 m run below is what
#           actually keeps hands away from the chute.
#   "round" the original syringe-style circular bore. Kept for comparison: it is the
#           stronger graphic, but a rigid disc in a round bore rests on two contact
#           lines with a void beneath it.
SECTION = os.environ.get("SEED_SECTION", "slot")
LINER_T = 0.008                 # stainless liner wall
REACH_BLOCK = 0.80              # face -> chute. An adult arm through an opening this size
                                # reaches ~0.65 m (no shoulder entry), so the chute is
                                # unreachable with margin -- nobody can foul or block it.
CHUTE_X = REACH_BLOCK
TUBE_BACK = CHUTE_X + 0.19      # tube runs past the chute to park the retracted piston
CHAM_OUT = 0.05                 # how far the countersink opens beyond the bore, at the face
cham_d = 0.045                  # depth at which the funnel meets the bore

SLOT_W, SLOT_H, SLOT_R = 0.190, 0.190, 0.035    # square bore, inside the liner
MOUTH_R = 0.120                                 # round mouth radius
TUBE_IR = MOUTH_R - LINER_T
BORE_R = MOUTH_R + 0.0015       # wall bore sits 1.5 mm proud of the liner (no coincident faces)
SLOT = SECTION == "slot"

br = S["flatbread_dia_m"] / 2.0
bt = S["flatbread_thk_m"]
if SLOT:
	FLOOR_Z = -SLOT_H / 2.0                     # flat floor: the bread lies dead flat on it
else:
	# a rigid disc in a round bore only touches where its rim meets the cylinder
	FLOOR_Z = -math.sqrt(TUBE_IR ** 2 - br ** 2)
BREAD_Z = FLOOR_Z + bt / 2 + 0.0005
# The liner floor only begins where the countersink ends, so the bread has to come to
# rest fully behind that -- otherwise its leading edge overhangs the chamfer void with
# nothing under it. Parking it here also sets it back from the rim, out of the weather.
BREAD_X = cham_d + br + 0.010


def bore_sec(off=0.0):
	"""Slot section (w, h, r) offset outward by `off` on every side."""
	return (SLOT_W + 2 * off, SLOT_H + 2 * off, max(SLOT_R + off, 0.001))

# ---- armored public wall with the mouth bored INTO it ---------------------
# Syringe-style, like HiveCell: the mouth is a hole bored *through* the flush wall,
# not a part stuck on it. Nothing is ever proud of the wall face (x=0).
wall_w, wall_h, wall_d = 3.2, 2.4, 0.35
bpy.ops.mesh.primitive_cube_add(size=2.0)   # unit-radius cube (+-1), scaled by half-extents
wall = bpy.context.active_object
wall.name = "PublicWall"
wall.scale = (wall_d / 2, wall_w / 2, wall_h / 2)
wall.location = (wall_d / 2, 0, 0)
bpy.ops.object.transform_apply(scale=True, location=True)
# The countersink must *cross* the bore surface at a healthy angle, not land tangent
# to it: a funnel ending exactly on the bore produces sliver faces along the seam that
# render as hard triangular flaps. So it starts 10 mm proud of the face (no coplanar
# cap with the wall front) and runs 30 mm PAST the depth where it meets the bore.
cone_x0, cone_x1 = -0.010, cham_d + 0.030
slope = CHAM_OUT / cham_d                     # width lost per metre of depth, per side
if SLOT:
	# through cutter: bores the full wall depth
	cut(wall, place(prism(-0.1, wall_d + 0.1, bore_sec(LINER_T + 0.0015),
	                      bore_sec(LINER_T + 0.0015), "cut_mouth")), "mouth")
	# countersunk funnel: a uniform outward offset that shrinks with depth
	off0 = LINER_T + 0.0015 + CHAM_OUT + slope * (-cone_x0)
	off1 = LINER_T + 0.0015 - slope * (cone_x1 - cham_d)
	cut(wall, place(prism(cone_x0, cone_x1, bore_sec(off0), bore_sec(off1), "cut_cham")), "chamfer")
else:
	cut(wall, cyl(BORE_R, wall_d + 0.2, (wall_d / 2, 0, 0)), "mouth")
	cham_r0 = BORE_R + CHAM_OUT               # rim radius, at the wall face
	bpy.ops.mesh.primitive_cone_add(
		radius1=cham_r0 + slope * (-cone_x0), # extrapolated back to cone_x0
		radius2=BORE_R - slope * (cone_x1 - cham_d),
		depth=cone_x1 - cone_x0, vertices=128)
	cone = bpy.context.active_object
	cone.rotation_euler = (0, math.radians(90), 0)
	cone.location = ((cone_x0 + cone_x1) / 2, 0, 0)
	bpy.ops.object.transform_apply(rotation=True, location=True)
	cut(wall, cone, "chamfer")
# auto-smooth: the curved bore + chamfer shade cleanly, the flat face stays crisp
bpy.context.view_layer.objects.active = wall
try:
	bpy.ops.object.shade_auto_smooth(angle=math.radians(30))
except Exception:
	pass
set_mat(wall, mat_wall)

# ---- delivery tube (horizontal leg of the L) ------------------------------
# Starts where the countersink ends, so the chamfer stays clean concrete and the
# steel liner begins as a crisp step just inside. Its floor IS the delivery surface.
tube_len = TUBE_BACK - cham_d
mid = (cham_d + TUBE_BACK) / 2
if SLOT:
	tube = place(prism(cham_d, TUBE_BACK, bore_sec(LINER_T), bore_sec(LINER_T), "DeliveryTube"))
	# bore it out, stopping 20 mm short of the back so the tube is capped behind the piston
	cut(tube, place(prism(cham_d - 0.02, TUBE_BACK - 0.02, bore_sec(), bore_sec(), "cut_bore")), "bore")
	# open the roof where the chute lands. The cutter starts above the floor, so it
	# removes the top wall only -- the floor stays continuous under the drop point.
	chute_in = (SLOT_W, 0.185, SLOT_R)          # local h maps to world X once rotated
	cut(tube, place(prism(FLOOR_Z + 0.025, 0.70, chute_in, chute_in, "cut_port"),
	                rot=(0, math.radians(-90), 0), loc=(CHUTE_X, 0, 0)), "chute_port")
else:
	tube = cyl(MOUTH_R, tube_len, (mid, 0, 0))
	tube.name = "DeliveryTube"
	cut(tube, cyl(TUBE_IR, tube_len, (mid - 0.02, 0, 0)), "bore")
	cut(tube, cyl(TUBE_IR, 0.80, (CHUTE_X, 0, 0.30), axis="Z", verts=96), "chute_port")
bpy.context.view_layer.objects.active = tube
try:
	bpy.ops.object.shade_auto_smooth(angle=math.radians(30))
except Exception:
	pass
set_mat(tube, mat_liner)

# ---- drop chute (vertical leg of the L) -----------------------------------
# Baked bread falls down this and lands on the bore floor, 0.80 m back from daylight.
if SLOT:
	chute_out = (SLOT_W + 2 * LINER_T, 0.185 + 2 * LINER_T, SLOT_R + LINER_T)
	chute = place(prism(0.040, 0.70, chute_out, chute_out, "DropChute"),
	              rot=(0, math.radians(-90), 0), loc=(CHUTE_X, 0, 0))
	cut(chute, place(prism(0.020, 0.75, chute_in, chute_in, "cut_cbore"),
	                 rot=(0, math.radians(-90), 0), loc=(CHUTE_X, 0, 0)), "bore")
else:
	chute = cyl(MOUTH_R, 0.60, (CHUTE_X, 0, 0.40), axis="Z", verts=96)
	chute.name = "DropChute"
	cut(chute, cyl(TUBE_IR, 0.70, (CHUTE_X, 0, 0.40), axis="Z", verts=96), "bore")
set_mat(chute, mat_liner)

# ---- piston, parked behind the chute --------------------------------------
# Shown retracted: it has just pushed this bread the full 0.80 m out to the face
# and withdrawn behind the drop point. Invisible from outside -- which is the point.
if SLOT:
	piston = place(prism(CHUTE_X + 0.10, CHUTE_X + 0.14, bore_sec(-0.003), bore_sec(-0.003),
	                     "DeliveryPiston"))
else:
	piston = cyl(TUBE_IR - 0.003, 0.04, (CHUTE_X + 0.10, 0, 0))
	piston.name = "DeliveryPiston"
	smooth(piston)
set_mat(piston, mat_steel)

# ---- the flatbread: the warm hero, delivered at the mouth -----------------
# Lying FLAT and face-up on the bore floor, just inside the rim -- the piston has run
# it all the way out. Behind it the tube recedes 0.8 m into black.
bpy.ops.mesh.primitive_cylinder_add(radius=br, depth=bt, vertices=128)
bread = bpy.context.active_object
bread.name = "Flatbread"
bread.location = (BREAD_X, 0, BREAD_Z)
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


def add_area(name, loc, energy, color, size, target=Vector((0, 0, 0)), glossy=True):
	ld = bpy.data.lights.new(name, "AREA")
	ld.energy = energy; ld.color = color; ld.size = size
	ob = bpy.data.objects.new(name, ld)
	bpy.context.collection.objects.link(ob)
	ob.location = loc
	ob.rotation_euler = (target - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
	ob.visible_camera = False        # illuminate, but never show the lamp itself through the bore
	# Glossy visibility must stay ON: the liner/tray/piston are metallic, and a metal has
	# no diffuse lobe -- with glossy off the lamps simply do not light the delivery run.
	ob.visible_glossy = glossy
	return ob


bread_p = Vector((BREAD_X, 0.0, BREAD_Z))
mouth_c = Vector((0.0, 0.0, 0.0))
# key rakes the chamfered rim + wall face from the front (the countersink reads the
# hole); a contained warm light inside lights the bread; the deep bore stays dark.
# One big soft warm key does the work (large source -> no hard light-shafts on the
# bore wall); a faint cool fill keeps the flush wall from going pure black.
add_area("key", (-0.55, -0.45, 0.45), 42.0, (1.0, 0.63, 0.32), 2.2, bread_p)   # soft warm on bread + rim
add_area("fill", (-1.2, -0.3, 0.25), 4.0, (0.7, 0.75, 0.9), 2.6, mouth_c)      # faint wall lift
# service light inside the tube, aimed AWAY from camera down the run. Without it the
# tube is a flat black disc and all the depth is thrown away; with it the liner and
# tray rim up and recede toward the chute before falling off to black.
# Aim it DOWN onto the floor mid-run, not straight down the axis: pointed at the back
# the light hits the tube's end cap square-on and that bright flat panel makes the whole
# 0.99 m run read as a shallow box. Grazing the floor instead gives a near-to-far
# gradient, and the end cap plus the open chute port stay dark.
# Warm, and set back clear of the bread (which ends at x=0.215) -- closer than that and
# it backlights the bread's far edge into a pale washed band.
add_area("throat", (0.34, 0, FLOOR_Z + 0.11), float(os.environ.get("SEED_THROAT", "0.8")),
         (1.00, 0.82, 0.62), 0.14, Vector((0.52, 0, FLOOR_Z)))

# ---- camera (looking down INTO the mouth, ~23 deg) -------------------------
# Raised off dead-head-on: the tray and tube wall then recede visibly toward the
# dark chute end, which is what sells the depth -- and it puts the bread's golden
# face toward the lens instead of edge-on.
cd = bpy.data.cameras.new("cam")
cam = bpy.data.objects.new("cam", cd)
bpy.context.collection.objects.link(cam)
if SLOT:
	# a square bore is tall enough to look down into: from here the roof clears the floor
	# out to ~0.76 m, so almost the whole run recedes into frame behind the bread.
	cd.lens = 48
	cam.location = (-0.56, -0.06, 0.235)
else:
	cd.lens = 48
	cam.location = (-0.62, -0.06, 0.24)
# Aim between the mouth and the bread, not at the bread: the bread sits deep and low, and
# pointing straight at it shoves the opening into the top-left corner of the frame.
aim = Vector(((0.0 + BREAD_X) / 2, 0.0, (0.0 + BREAD_Z) / 2))
cam.rotation_euler = (aim - cam.location).to_track_quat("-Z", "Y").to_euler()
bpy.context.scene.camera = cam
cd.dof.use_dof = True
cd.dof.focus_distance = (bread_p - cam.location).length
cd.dof.aperture_fstop = 6.3

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
