"""SeedCell parametric model -- THE source of truth (headless, reproducible).

Regenerate:
  flatpak run --command=freecadcmd org.freecad.FreeCAD \
      /home/eddy/Projects/SeedCell/scripts/build_model.py

Authoring workflow mirrors the sibling HiveCell project (ADR-0002): the model is
git-tracked Python run via freecadcmd; cad/SeedCell.FCStd is a generated artifact; the
GUI is a viewer, never a pencil. All master parameters live in the Spreadsheet aliased
cells below; every part and every downstream script reads them from there.

COORDINATE CONVENTION (shared by the twin + export):
  origin  = centre of the mouth (public wall plane), on the bore axis
  +X      = depth INTO the machine (the motion axis; piston parks deep to clean)
  +Z      = up, +Y = width; units = millimetres
The bore is round (no corners -> best hygiene + easiest full-perimeter scraping): the
whole food-contact story is a cylinder + a flat piston face (ADR-0001, ADR-0003).
Piston is modelled in the PRESENT/flush pose (face at X=0); motion is a single +X
translation applied by validate_kinematics.py / the twin, not baked into the geometry.
Flush (X=0) is also the COOK pose, not just PRESENT's start point: the piston presses
to flush right after HYDRATE and holds there through the bake (ADR-0019). CHARGE and
HYDRATE happen with the piston retracted to X=chargeDepth instead, in the open chamber.
"""
import FreeCAD as App
import Part

DOC = "/home/eddy/Projects/SeedCell/cad/SeedCell.FCStd"

# (alias, value/formula, comment) -- the single source of truth (ADR-0002 style).
PARAMS = [
	("flatbreadDia",     "160 mm",  "delivered flatbread diameter (= piston face)"),
	("flatbreadThk",     "8 mm",    "pressed/baked flatbread thickness"),
	("runningClearance", "2 mm",    "piston-to-bore radial gap (scraper seals bridge it)"),
	("boreDia",          "=flatbreadDia + 2*runningClearance", "cook bore diameter (derived)"),
	("pistonDia",        "=boreDia - 2*runningClearance",      "piston diameter (derived)"),
	("wallThickness",    "8 mm",    "bore wall (structural + thermal mass) TBD"),
	("pistonLength",     "120 mm",  "piston depth (resists tilt/jam; houses heater)"),
	("chargeDepth",      "60 mm",   "piston retract that opens the charge+hydrate chamber "
	                                "-- COOK happens flush, not here (ADR-0019)"),
	("sterilizeStow",    "150 mm",  "extra retract so the face parks in the sterilize zone"),
	("stroke",           "=chargeDepth + sterilizeStow", "max piston travel (present<->clean)"),
	("dieThk",           "10 mm",   "mouth die/peeler ring thickness (proud of the wall)"),
	("deliveryDia",      "=flatbreadDia - 4 mm", "die inner bore: shears/peels the bread rim"),
	("sealLipThk",       "4 mm",    "scraper lip axial thickness"),
	("sealLipCount",     "2",       "SF3 scraper lips per piston (face-side + rear)"),
	("barrelLength",     "=chargeDepth + pistonLength + sterilizeStow", "fixed bore length"),
	("cookPlatenC",      "230",     "hot bore-end + piston-face platen temperature (C)"),
]


def build_parameters(doc):
	sheet = doc.addObject("Spreadsheet::Sheet", "Parameters")
	r = 1
	for alias, val, comment in PARAMS:
		sheet.set(f"A{r}", alias)
		sheet.set(f"B{r}", str(val))
		sheet.set(f"C{r}", comment)
		sheet.setAlias(f"B{r}", alias)
		r += 1
	doc.recompute()
	return sheet


def _tube(outer_d, inner_d, length, x0):
	"""A round tube (annulus extruded along +X), from X=x0 to x0+length."""
	outer = Part.makeCylinder(outer_d / 2.0, length, App.Vector(x0, 0, 0), App.Vector(1, 0, 0))
	inner = Part.makeCylinder(inner_d / 2.0, length, App.Vector(x0, 0, 0), App.Vector(1, 0, 0))
	return outer.cut(inner)


def _feature(doc, name, shape):
	obj = doc.addObject("Part::Feature", name)
	obj.Shape = shape
	return obj


def build(doc, s):
	bore = s.boreDia.Value
	wall = s.wallThickness.Value
	blen = s.barrelLength.Value
	pdia = s.pistonDia.Value
	plen = s.pistonLength.Value

	# CookBarrel -- fixed heated bore, open at both ends (mouth X=0, service X=blen).
	barrel = _tube(bore + 2 * wall, bore, blen, 0.0)
	_feature(doc, "CookBarrel", barrel)

	# Piston -- the single moving part, modelled at the flush/present pose (face at X=0).
	piston = Part.makeCylinder(pdia / 2.0, plen, App.Vector(0, 0, 0), App.Vector(1, 0, 0))
	_feature(doc, "Piston", piston)

	# ScraperSeals -- SF3 lip rings on the piston perimeter that bridge the running gap,
	# scrape the bore clean each stroke, and define the food-contact boundary.
	lips = int(s.sealLipCount)
	lipt = s.sealLipThk.Value
	seals = None
	for i in range(lips):
		x = 6.0 + i * (plen - 12.0) / max(1, lips - 1)  # face-side + rear
		ring = _tube(bore, pdia - 1.0, lipt, x)
		seals = ring if seals is None else seals.fuse(ring)
	_feature(doc, "ScraperSeals", seals)

	# MouthDie -- fixed hardened peeler ring at the mouth (proud of the wall, X<0), inner
	# = deliveryDia < pistonDia so it shears the flatbread rim off on ejection + is the
	# front hard stop. Sits OUTSIDE the piston's X>=0 travel (no modelled interference).
	die = _tube(bore + 2 * wall, s.deliveryDia.Value, s.dieThk.Value, -s.dieThk.Value)
	_feature(doc, "MouthDie", die)

	# HydrationRing -- fixed jet ring just inside the mouth: injects water+oil into the
	# dry charge to hydrate + mix WITHOUT a blade (ADR-0006). Space claim.
	_feature(doc, "HydrationRing", _tube(bore + 22, bore + 4, 12.0, 40.0))

	# SterilizeRing -- fixed steam / hot-water sanitize ring in the service zone the
	# piston face parks against for cleaning (SF2). Space claim.
	xs = s.chargeDepth.Value + s.sterilizeStow.Value
	_feature(doc, "SterilizeRing", _tube(bore + 22, bore + 4, 14.0, xs - 20.0))

	# HotAirKnife -- fixed drying ring just ahead of the sterilize ring (SF2 dry step).
	_feature(doc, "HotAirKnife", _tube(bore + 20, bore + 4, 10.0, xs - 44.0))

	# WasteChute -- diverts an unsafe (under-cooked) batch away from the mouth to waste
	# (ADR-0009 divert path). A box below the bore on the service side. Space claim.
	wc = Part.makeBox(90, 120, 140, App.Vector(s.chargeDepth.Value, -60, -(bore / 2 + 140)))
	_feature(doc, "WasteChute", wc)

	# DryStorage -- sealed dry-ingredient hoppers above the bore (dry = no cleaning).
	hop = Part.makeBox(260, 300, 300, App.Vector(30, -150, bore / 2 + wall + 10))
	_feature(doc, "DryStorage", hop)

	# ServicePlant -- back-of-house envelope (drive, heaters, steam gen, dosers).
	sp = Part.makeBox(220, 360, 360, App.Vector(blen, -180, -180))
	_feature(doc, "ServicePlant", sp)

	doc.recompute()


def report(doc, s):
	bore = s.boreDia.Value
	piston = doc.getObject("Piston")
	barrel = doc.getObject("CookBarrel")
	pbb = piston.Shape.BoundBox
	print("--- SeedCell model build ---")
	print(f"bore diameter      : {bore:8.1f} mm")
	print(f"piston diameter    : {s.pistonDia.Value:8.1f} mm  (clearance {s.runningClearance.Value:.1f} mm/side)")
	print(f"barrel length      : {s.barrelLength.Value:8.1f} mm")
	print(f"stroke (present<->clean): {s.stroke.Value:6.1f} mm")
	print(f"flatbread          : {s.flatbreadDia.Value:.0f} dia x {s.flatbreadThk.Value:.0f} mm thick")
	print(f"seal perimeter     : {3.14159 * s.boreDia.Value / 1000.0:8.3f} m  x {int(s.sealLipCount)} lips")
	print(f"piston bbox X      : [{pbb.XMin:.1f}, {pbb.XMax:.1f}] mm  (flush/present pose)")
	# sanity: piston fits inside the bore with clearance
	gap = (bore - s.pistonDia.Value) / 2.0
	print(f"running gap check  : {gap:8.2f} mm/side  {'OK' if abs(gap - s.runningClearance.Value) < 1e-6 else 'MISMATCH'}")
	print(f"parts              : {', '.join(o.Name for o in doc.Objects if o.TypeId == 'Part::Feature')}")


doc = App.newDocument("SeedCell")
sheet = build_parameters(doc)
build(doc, sheet)
report(doc, sheet)
doc.saveAs(DOC)
print(f"saved: {DOC}")
