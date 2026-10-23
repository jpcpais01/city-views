class_name WorkGen
extends RefCounted
## Workplaces: office towers (CityGen._office), low glass studios with green
## roofs, and hotels with balconies, a rooftop pool and a glowing sign.

const H := CityGen.H
const FRAME := CityGen.FRAME
const GLASS := CityGen.GLASS
const GLASS_LIGHT := CityGen.GLASS_LIGHT
const SIDEWALK := CityGen.SIDEWALK
const TIMBER := Color(0.7, 0.52, 0.36)


static func build(mk: MeshKit, x: int, z: int) -> void:
	var g := Game.grw(x, z)
	if g == 0:
		CityGen._lot(mk, x, z)
		return
	match Game.sub(x, z):
		Game.WORK.STUDIO: _studio(mk, x, z, g)
		Game.WORK.HOTEL: _hotel(mk, x, z, g)
		_: CityGen._office(mk, x, z)


## A flat green roof with a few shrubs and a skylight.
static func green_roof(mk: MeshKit, x: int, z: int, c: Vector3, w: float, d: float) -> void:
	mk.box_faces(c + Vector3(0, 0.02, 0), Vector3(w - 0.08, 0.04, d - 0.08), Color(0.52, 0.72, 0.38), MeshKit.TOP, MeshKit.MOWN_X)
	mk.blob(c + Vector3(-w * 0.28, 0.1, d * 0.15), Vector3(0.12, 0.08, 0.12), CityGen.pick(CityGen.LEAF, x, z, 120), 0.04)
	mk.blob(c + Vector3(w * 0.3, 0.09, -d * 0.2), Vector3(0.1, 0.07, 0.1), CityGen.pick(CityGen.FLOWERS, x, z, 121), 0.04)
	mk.box_faces(c + Vector3(w * 0.05, 0.06, 0), Vector3(0.3, 0.08, 0.2), GLASS_LIGHT, MeshKit.TOP | MeshKit.FRONT | MeshKit.BACK | MeshKit.LEFT | MeshKit.RIGHT, 1.0)


# ------------------------------------------------------------------ studios

static func _studio(mk: MeshKit, x: int, z: int, g: int) -> void:
	var f := CityGen.facing(x, z)
	var shell: Color = CityGen.pick([Color("f0ece4"), Color("3a3f47"), Color("dfe6ec"), TIMBER], x, z, 122)
	var dark := shell.v < 0.5
	var trim := Color(0.97, 0.97, 0.95) if dark else Color(0.28, 0.3, 0.34)
	mk.push_at(Vector3.ZERO, CityGen.yaw_of(f))
	# a timber deck and a strip of lawn in front
	mk.rbox(Vector3(0, 0.03, 0), Vector3(1.96, 0.06, 1.96), 0.03, Color(0.56, 0.78, 0.44), null, false, MeshKit.MOWN_X)
	mk.box_faces(Vector3(0, 0.07, 0.55), Vector3(1.5, 0.02, 0.5), TIMBER, MeshKit.TOP, MeshKit.SIDING)
	var w := 1.6
	var d := 0.95
	var cz := -0.32
	var fh := 0.6
	# ground floor: a glass box with a solid end wall
	mk.rbox(Vector3(0, 0.07 + fh * 0.5, cz), Vector3(w, fh, d), 0.02, shell, null, false, MeshKit.SIDING if shell == TIMBER else 0.0)
	mk.window(Vector3(-0.1, 0.07 + fh * 0.5, cz + d * 0.5), Vector3.BACK, w * 0.72, fh * 0.76, GLASS_LIGHT)
	mk.rbox(Vector3(w * 0.38, 0.07 + fh * 0.4, cz + d * 0.5 + 0.02), Vector3(0.24, fh * 0.7, 0.03), 0.01, trim)
	var top := 0.07 + fh
	if g == 1:
		green_roof(mk, x, z, Vector3(0, top, cz), w, d)
	else:
		# upper floor cantilevered out over the deck
		var shift := 0.22 if Game.hashf(x, z, 123) > 0.5 else -0.22
		var uw := w * 0.78
		var ud := d + 0.2
		mk.rbox(Vector3(shift, top + fh * 0.5, cz + 0.12), Vector3(uw, fh, ud), 0.02, trim if not dark else shell.lightened(0.1))
		mk.window(Vector3(shift, top + fh * 0.5, cz + 0.12 + ud * 0.5), Vector3.BACK, uw * 0.9, fh * 0.6, GLASS)
		CityGen._windows_row(mk, top + fh * 0.5, uw, ud, 0, 2, GLASS, Color(0, 0, 0, 0), [false, true, false, true], 0.3, fh * 0.5)
		top += fh
		if g == 3:
			# a second wing joined by a glazed sky bridge
			mk.rbox(Vector3(-0.55, 0.07 + fh, 0.55), Vector3(0.6, fh * 2.0, 0.6), 0.02, shell)
			mk.window_row(Vector3(-0.55, 0.07 + fh * 0.5, 0.85), Vector3.BACK, 0.5, 2, 0.18, fh * 0.6, GLASS_LIGHT, false)
			mk.window_row(Vector3(-0.55, 0.07 + fh * 1.5, 0.85), Vector3.BACK, 0.5, 2, 0.18, fh * 0.6, GLASS, false)
			mk.box_faces(Vector3(-0.55, 0.07 + fh * 1.5, 0.1), Vector3(0.3, fh * 0.6, 0.32), GLASS_LIGHT, MeshKit.TOP | MeshKit.LEFT | MeshKit.RIGHT, 1.0)
			green_roof(mk, x, z, Vector3(-0.55, 0.07 + fh * 2.0, 0.55), 0.6, 0.6)
		HomeGen.solar(mk, Vector3(shift, top, cz + 0.12), uw * 0.8, ud * 0.7)
	# bike rack and a young tree
	for k in 3:
		mk.box(Vector3(0.45 + k * 0.12, 0.16, 0.9), Vector3(0.015, 0.16, 0.12), Color(0.55, 0.57, 0.6))
	CityGen._round_tree(mk, Vector3(0.75, 0.06, 0.3), 0.36, CityGen.pick(CityGen.LEAF, x, z, 124))
	mk.pop()


# ------------------------------------------------------------------ hotel

static func _hotel(mk: MeshKit, x: int, z: int, g: int) -> void:
	var f := CityGen.facing(x, z)
	var sea := CityGen.coastal(x, z)
	var tone: Color = CityGen.pick([Color("fbf1df"), Color("f2d9c4"), Color("f8f6f0"), Color("e8dcc6")] if not sea else CityGen.SEA_WALLS, x, z, 130)
	var accent: Color = CityGen.pick([Color("3fae8c"), Color("2f6fb5"), Color("c9774b"), Color("8a6fd6")], x, z, 131)
	var trim := Color(0.98, 0.97, 0.94)
	mk.push_at(Vector3.ZERO, CityGen.yaw_of(f))
	CityGen._plot(mk, SIDEWALK.lightened(0.04))
	var w := 1.7
	var d := 1.1
	var cz := -0.32
	var floors: int = [0, 4, 7, 10][g] + (mini(3, CityGen.density(x, z) / 6) if g == 3 else 0)
	var base := 0.66
	var fh := 0.46
	var hgt := base + (floors - 1) * fh
	var front := cz + d * 0.5
	mk.rbox_walls(Vector3(0, 0.06 + hgt * 0.5, cz), Vector3(w, hgt, d), 0.04, tone)
	# lobby: glass, a long canopy out to the kerb, flags beside the doors
	mk.window_row(Vector3(0, 0.36, front), Vector3.BACK, w * 0.86, 3, w * 0.24, 0.42, GLASS_LIGHT, false)
	mk.box_faces(Vector3(0, 0.66, front + 0.36), Vector3(0.6, 0.05, 0.72), accent, MeshKit.TOP | MeshKit.FRONT | MeshKit.LEFT | MeshKit.RIGHT)
	for s in [-1, 1]:
		mk.pole(Vector3(s * 0.27, 0.06, front + 0.68), 0.015, 0.6, 4, Color(0.85, 0.75, 0.45))
	for k in 3:
		var fx := -0.75 + k * 0.08
		mk.pole(Vector3(fx, 0.06, 0.86), 0.008, 0.62, 4, Color(0.9, 0.9, 0.92))
		mk.box_faces(Vector3(fx + 0.045, 0.6, 0.86), Vector3(0.08, 0.06, 0.004), [accent, Color.WHITE, Color("e85d5d")][k], MeshKit.FRONT | MeshKit.BACK)
	# guest floors: a balcony for every room, facing the street (and the sea)
	mk.bands(0.06 + base, w, d, fh, floors - 1, 0.03, trim)
	var rooms := 4
	for fl in range(1, floors):
		var yy := 0.06 + base + (fl - 1) * fh + fh * 0.5
		mk.window_row(Vector3(0, yy + 0.02, front), Vector3.BACK, w * 0.92, rooms, w * 0.92 / rooms * 0.55, fh * 0.66, GLASS, false)
		mk.box_faces(Vector3(0, yy - fh * 0.42, front + 0.1), Vector3(w * 0.94, 0.03, 0.2), trim, MeshKit.TOP | MeshKit.FRONT | MeshKit.LEFT | MeshKit.RIGHT)
		mk.box_faces(Vector3(0, yy - fh * 0.3, front + 0.198), Vector3(w * 0.94, 0.17, 0.01), Color(0.78, 0.9, 0.96), MeshKit.FRONT | MeshKit.BACK)
		CityGen._windows_row(mk, yy, w, d, rooms, 2, GLASS, Color(0, 0, 0, 0), [false, true, true, true], 0.2, fh * 0.6)
	# divider fins between the balconies
	for k in range(1, rooms):
		mk.box_faces(Vector3(-w * 0.47 + k * w * 0.94 / rooms, 0.06 + base + (floors - 1) * fh * 0.5, front + 0.1), Vector3(0.025, (floors - 1) * fh, 0.2), accent.lightened(0.2), MeshKit.FRONT | MeshKit.LEFT | MeshKit.RIGHT)
	var top := 0.06 + hgt
	mk.ledge(Vector3(0, top + 0.05, cz), Vector3(w + 0.04, 0.1, d + 0.04), 0.02, trim)
	# the sign, lit at night
	mk.box(Vector3(0, top + 0.28, front - 0.12), Vector3(0.04, 0.36, 0.04), Color(0.3, 0.32, 0.36))
	mk.rbox(Vector3(0, top + 0.42, front - 0.1), Vector3(0.9, 0.2, 0.05), 0.02, accent)
	mk.window(Vector3(0, top + 0.42, front - 0.07), Vector3.BACK, 0.7, 0.09, Color(1, 0.96, 0.86), Color(0, 0, 0, 0), true)
	if g >= 2:
		# rooftop pool with loungers and parasols
		mk.rbox(Vector3(0, top + 0.12, cz - 0.15), Vector3(1.0, 0.06, 0.5), 0.02, Color(0.96, 0.95, 0.92), null, false, MeshKit.PAVING)
		mk.box_faces(Vector3(0, top + 0.153, cz - 0.15), Vector3(0.84, 0.004, 0.36), Color(0.35, 0.75, 0.9), MeshKit.TOP, 3.0)
		for s in [-1, 1]:
			mk.box_faces(Vector3(s * 0.66, top + 0.14, cz - 0.15), Vector3(0.12, 0.03, 0.26), Color.WHITE, MeshKit.TOP | MeshKit.LEFT | MeshKit.RIGHT)
			mk.pole(Vector3(s * 0.66, top + 0.1, cz + 0.2), 0.01, 0.3, 4, Color(0.9, 0.9, 0.9))
			mk.cone(Vector3(s * 0.66, top + 0.4, cz + 0.2), 0.18, 0.07, 8, accent if s < 0 else Color.WHITE)
	else:
		HomeGen._roof_kit(mk, x, z, w, d, top + 0.1)
	# palms out front by the sea, clipped bay trees in town
	for s in [-1, 1]:
		var p := Vector3(s * 0.82, 0.06, 0.62)
		if sea:
			CityGen._palm(mk, p, 0.5, Game.hash2(x, z, 132 + s) % 100)
		else:
			mk.rbox(p + Vector3(0, 0.08, 0), Vector3(0.16, 0.16, 0.16), 0.03, Color(0.74, 0.72, 0.68))
			mk.pole(p + Vector3(0, 0.16, 0), 0.015, 0.2, 4, Color(0.5, 0.36, 0.25))
			mk.blob(p + Vector3(0, 0.44, 0), Vector3(0.12, 0.12, 0.12), Color("4e8f45"), 0.04)
	mk.pop()
