class_name ShopGen
extends RefCounted
## Shops, one generator per sub-type: the corner shop (CityGen._shop), cafés
## that spill out onto terraces, markets that grow into halls, department stores.

const H := CityGen.H
const FRAME := CityGen.FRAME
const GLASS := CityGen.GLASS
const GLASS_LIGHT := CityGen.GLASS_LIGHT
const SIDEWALK := CityGen.SIDEWALK
const WOOD := Color(0.62, 0.45, 0.3)
const PRODUCE := [Color("ef5b5b"), Color("f2b33d"), Color("97c45a"), Color("f28b3c"), Color("8a6fd6"), Color("e8d45a")]


static func build(mk: MeshKit, x: int, z: int) -> void:
	var g := Game.grw(x, z)
	if g == 0:
		CityGen._lot(mk, x, z)
		return
	match Game.sub(x, z):
		Game.SHOP_SUB.CAFE: _cafe(mk, x, z, g)
		Game.SHOP_SUB.MARKET: _market(mk, x, z, g)
		Game.SHOP_SUB.STORE: _store(mk, x, z, g)
		_: CityGen._shop(mk, x, z)


static func _joins(x: int, z: int, dir: int) -> bool:
	return CityGen.joined(x, z, dir, Game.K.SHOP) or CityGen.joined(x, z, dir, Game.K.HOUSE)


static func _paved(mk: MeshKit, col := SIDEWALK) -> void:
	mk.rbox(Vector3(0, 0.03, 0), Vector3(1.96, 0.06, 1.96), 0.03, col, null, false, MeshKit.PAVING)


## A little round table with two chairs under a parasol.
static func table(mk: MeshKit, p: Vector3, parasol: Color, chairs := true) -> void:
	mk.box_faces(p + Vector3(0, 0.21, 0), Vector3(0.18, 0.02, 0.18), Color(0.97, 0.97, 0.95), MeshKit.TOP)
	mk.pole(p, 0.012, 0.2, 4, Color(0.35, 0.36, 0.4))
	if chairs:
		for s in [-1, 1]:
			mk.box_faces(p + Vector3(s * 0.15, 0.1, 0), Vector3(0.08, 0.02, 0.08), Color(0.3, 0.32, 0.36), MeshKit.TOP)
			mk.box_faces(p + Vector3(s * 0.19, 0.16, 0), Vector3(0.015, 0.12, 0.08), Color(0.3, 0.32, 0.36), MeshKit.LEFT | MeshKit.RIGHT)
	if parasol.a > 0.0:
		mk.pole(p + Vector3(0, 0.2, 0), 0.01, 0.34, 4, Color(0.9, 0.9, 0.9))
		mk.cone(p + Vector3(0, 0.5, 0), 0.26, 0.1, 8, parasol)


## Festoon lights: little lamps that glow at night (one quad each).
static func string_lights(mk: MeshKit, a: Vector3, b: Vector3, n: int) -> void:
	mk.box(((a + b) * 0.5), Vector3(absf(b.x - a.x) + 0.01, 0.006, absf(b.z - a.z) + 0.01), Color(0.25, 0.25, 0.28))
	for k in n:
		var t := (k + 0.5) / n
		var p := a.lerp(b, t) + Vector3(0, -0.03 - sin(t * PI) * 0.04, 0)
		mk.window(p, Vector3.UP, 0.035, 0.035, Color(1, 0.86, 0.55), Color(0, 0, 0, 0), true)
		mk.window(p, Vector3.BACK, 0.035, 0.035, Color(1, 0.86, 0.55), Color(0, 0, 0, 0), true)


# ------------------------------------------------------------------ café

static func _cafe(mk: MeshKit, x: int, z: int, g: int) -> void:
	var f := CityGen.facing(x, z)
	var jl := _joins(x, z, (f + 3) % 4)
	var jr := _joins(x, z, (f + 1) % 4)
	var wall: Color = CityGen.district_wall(x, z, 80)
	var awn: Color = CityGen.pick(CityGen.AWNINGS, x, z, 81)
	# the view decides the mood: by the sea it's blue and white, by a park leafy
	var sea := CityGen.sea_dir(x, z, 2) >= 0
	var leafy := CityGen.around(x, z, Game.K.PARK) > 0 or CityGen.around(x, z, Game.K.TREE) > 1
	if sea:
		awn = CityGen.pick([Color("3f7cc4"), Color("4b86d6"), Color.WHITE], x, z, 82)
		wall = CityGen.pick(CityGen.SEA_WALLS, x, z, 83)
	mk.push_at(Vector3.ZERO, CityGen.yaw_of(f))
	_paved(mk, Color(0.9, 0.86, 0.79))
	var x0 := -H if jr else -0.75
	var x1 := H if jl else 0.75
	var w := x1 - x0
	var cx := (x0 + x1) * 0.5
	var d := 0.95
	var cz := -0.5
	var fh := 0.64
	var floors := g
	var hgt := floors * fh + 0.1
	var front := cz + d * 0.5
	mk.push_at(Vector3(cx, 0, 0))
	mk.rbox_walls(Vector3(0, 0.06 + hgt * 0.5, cz), Vector3(w, hgt, d), 0.04, wall, MeshKit.SIDING if Game.hashf(x, z, 84) > 0.6 else 0.0)
	# wide glass front with the door in the middle, under a scalloped awning
	mk.window_row(Vector3(0, 0.38, front), Vector3.BACK, w * 0.84, 3, w * 0.24, 0.44, GLASS_LIGHT, false)
	mk.rbox(Vector3(0, 0.33, front + 0.02), Vector3(0.22, 0.5, 0.03), 0.01, Color(0.36, 0.26, 0.2))
	mk.push(Transform3D(Basis(Vector3.RIGHT, 0.35), Vector3(0, 0.72, front + 0.01)))
	mk.box_faces(Vector3(0, 0, 0.2), Vector3(w * 0.92, 0.025, 0.4), awn, MeshKit.TOP | MeshKit.FRONT)
	mk.pop()
	for k in 6:
		mk.blob(Vector3(-w * 0.4 + k * w * 0.16, 0.58, front + 0.38), Vector3(0.07, 0.035, 0.03), awn)
	# hanging sign
	mk.box(Vector3(w * 0.5 + 0.06, 0.95, front - 0.1), Vector3(0.14, 0.02, 0.02), Color(0.2, 0.2, 0.22))
	mk.rbox(Vector3(w * 0.5 + 0.1, 0.84, front - 0.1), Vector3(0.02, 0.16, 0.16), 0.01, awn.darkened(0.2))
	for fl in range(1, floors):
		var yy := 0.06 + fl * fh + fh * 0.5
		mk.window_row(Vector3(0, yy, front), Vector3.BACK, w * 0.8, 3, 0.22, 0.32, CityGen.GLASS)
		CityGen._windows_row(mk, yy, w, d, 0, 2, GLASS, FRAME, [false, not jl, false, not jr])
	if g == 2:
		# balcony seating over the awning, strung with lights
		mk.box_faces(Vector3(0, fh + 0.08, front + 0.18), Vector3(w * 0.8, 0.04, 0.36), Color(0.75, 0.58, 0.4), MeshKit.TOP | MeshKit.FRONT)
		mk.box(Vector3(0, fh + 0.2, front + 0.36), Vector3(w * 0.8, 0.12, 0.015), Color(0.22, 0.24, 0.27))
		table(mk, Vector3(-w * 0.2, fh + 0.1, front + 0.18), Color(0, 0, 0, 0), false)
		table(mk, Vector3(w * 0.2, fh + 0.1, front + 0.18), Color(0, 0, 0, 0), false)
	var top := 0.06 + hgt
	mk.ledge(Vector3(0, top + 0.04, cz), Vector3(w + 0.04, 0.08, d + 0.04), 0.02, wall.lightened(0.15))
	if g == 3:
		# a rooftop restaurant: pergola, planters and festoon lights
		for px in [-1, 1]:
			for pz in [-1, 1]:
				mk.box(Vector3(px * w * 0.4, top + 0.28, cz + pz * d * 0.38), Vector3(0.04, 0.48, 0.04), WOOD)
		for k in 4:
			mk.box_faces(Vector3(-w * 0.36 + k * w * 0.24, top + 0.53, cz), Vector3(0.035, 0.035, d * 0.84), WOOD, MeshKit.TOP | MeshKit.LEFT | MeshKit.RIGHT)
		string_lights(mk, Vector3(-w * 0.4, top + 0.5, cz + d * 0.38), Vector3(w * 0.4, top + 0.5, cz + d * 0.38), 6)
		table(mk, Vector3(-w * 0.2, top + 0.08, cz), Color(0, 0, 0, 0))
		table(mk, Vector3(w * 0.2, top + 0.08, cz), Color(0, 0, 0, 0))
		mk.blob(Vector3(w * 0.42, top + 0.2, cz - d * 0.3), Vector3(0.12, 0.12, 0.12), CityGen.pick(CityGen.LEAF, x, z, 85), 0.04)
	mk.pop()
	# the terrace out front: tables and parasols, fenced by planters or rope
	var tables := 2 if w < 1.7 else 3
	for k in tables:
		var tx := cx - w * 0.33 + k * (w * 0.66 / maxf(tables - 1, 1))
		table(mk, Vector3(tx, 0.06, 0.38 + (k % 2) * 0.14), awn if k % 2 == 0 else Color(0.98, 0.97, 0.94))
	if leafy or sea:
		mk.rbox(Vector3(cx, 0.14, 0.9), Vector3(w * 0.9, 0.16, 0.12), 0.04, Color(0.72, 0.62, 0.5))
		for k in 4:
			mk.blob(Vector3(cx - w * 0.34 + k * w * 0.23, 0.26, 0.9), Vector3(0.09, 0.07, 0.07), CityGen.pick(CityGen.FLOWERS if leafy else CityGen.LEAF, x, z, 86 + k), 0.04)
	else:
		for s in [-1, 1]:
			mk.pole(Vector3(cx + s * w * 0.44, 0.06, 0.9), 0.015, 0.22, 4, Color(0.75, 0.62, 0.3))
		mk.box_faces(Vector3(cx, 0.24, 0.9), Vector3(w * 0.88, 0.015, 0.015), Color(0.55, 0.2, 0.2), MeshKit.TOP | MeshKit.FRONT)
	mk.pop()


# ------------------------------------------------------------------ market

static func _market(mk: MeshKit, x: int, z: int, g: int) -> void:
	var f := CityGen.facing(x, z)
	# neighbouring markets run together into one long row of stalls or one hall
	var ml := CityGen.same(x, z, (f + 3) % 4)
	var mr := CityGen.same(x, z, (f + 1) % 4)
	mk.push_at(Vector3.ZERO, CityGen.yaw_of(f))
	_paved(mk, Color(0.86, 0.8, 0.7))
	var x0 := -H if mr else -0.85
	var x1 := H if ml else 0.85
	var w := x1 - x0
	var cx := (x0 + x1) * 0.5
	if g == 3:
		_market_hall(mk, x, z, cx, w, ml, mr)
		mk.pop()
		return
	if g == 2:
		# covered market: a green iron shed over the stalls
		var iron := Color("3f6b5a")
		for px in [x0 + 0.06, cx, x1 - 0.06]:
			for pz in [-0.6, 0.55]:
				mk.pole(Vector3(px, 0.06, pz), 0.025, 0.86, 6, iron)
		mk.box(Vector3(cx, 0.93, 0.55), Vector3(w, 0.05, 0.05), iron)
		mk.box(Vector3(cx, 0.93, -0.6), Vector3(w, 0.05, 0.05), iron)
		mk.gable_roof(Vector3(cx, 0.94, -0.03), w, 1.3, 0.38, 0.08, Color("6f9a83"), iron, 0.04)
		if not ml and not mr:
			mk.rbox(Vector3(cx, 1.42, -0.03), Vector3(0.36, 0.16, 0.05), 0.02, Color(0.98, 0.95, 0.86))
	# the stalls: counters heaped with produce under striped canopies
	var n := maxi(1, int(round(w / 0.56)))
	for k in n:
		var sx := x0 + (k + 0.5) * w / n
		var cc: Color = CityGen.AWNINGS[(Game.hash2(x, z, 90 + k) + k) % CityGen.AWNINGS.size()]
		mk.box(Vector3(sx, 0.17, 0.25), Vector3(w / n * 0.82, 0.22, 0.3), WOOD)
		for p in 3:
			mk.blob(Vector3(sx - 0.12 + p * 0.12, 0.31, 0.25 + (p % 2) * 0.05 - 0.03), Vector3(0.07, 0.05, 0.07), PRODUCE[(Game.hash2(x, z, 100 + k * 3 + p)) % PRODUCE.size()])
		if g == 1:
			mk.pole(Vector3(sx - w / n * 0.38, 0.06, 0.04), 0.012, 0.62, 4, Color(0.4, 0.3, 0.22))
			mk.pole(Vector3(sx + w / n * 0.38, 0.06, 0.04), 0.012, 0.62, 4, Color(0.4, 0.3, 0.22))
			mk.push(Transform3D(Basis(Vector3.RIGHT, 0.3), Vector3(sx, 0.68, 0.04)))
			mk.box_faces(Vector3(0, 0, 0.2), Vector3(w / n * 0.86, 0.025, 0.42), cc, MeshKit.TOP | MeshKit.FRONT)
			mk.pop()
		# crates stacked behind
		mk.box(Vector3(sx + 0.1, 0.13, -0.15), Vector3(0.18, 0.14, 0.16), Color(0.78, 0.62, 0.42))
		if k % 2 == 0:
			mk.box(Vector3(sx + 0.1, 0.27, -0.15), Vector3(0.16, 0.12, 0.14), Color(0.72, 0.56, 0.38))
	mk.pop()


static func _market_hall(mk: MeshKit, x: int, z: int, cx: float, w: float, ml: bool, mr: bool) -> void:
	var brick := Color("b8735a")
	var stone := Color(0.93, 0.9, 0.84)
	var d := 1.6
	var cz := -0.1
	var hh := 1.25
	mk.rbox(Vector3(cx, 0.06 + hh * 0.5, cz), Vector3(w, hh, d), 0.03, brick, null, false, MeshKit.BRICKS)
	# tall arched windows down both long walls, a stone plinth and cornice
	mk.box_faces(Vector3(cx, 0.14, cz + d * 0.5 + 0.01), Vector3(w, 0.16, 0.03), stone, MeshKit.FRONT | MeshKit.TOP)
	mk.window_row(Vector3(cx, 0.7, cz + d * 0.5), Vector3.BACK, w * 0.86, 3, 0.26, 0.7, CityGen.GLASS_LIGHT)
	CityGen._windows_row(mk, 0.7, w, d, 0, 3, CityGen.GLASS_LIGHT, FRAME, [false, not ml, true, not mr], 0.24, 0.66)
	mk.rbox(Vector3(cx, 0.06 + hh + 0.04, cz), Vector3(w + 0.04, 0.08, d + 0.04), 0.02, stone)
	# raised clerestory down the middle letting light into the hall
	mk.rbox(Vector3(cx, hh + 0.3, cz), Vector3(w, 0.4, d * 0.46), 0.02, brick, null, false, MeshKit.BRICKS)
	mk.window_row(Vector3(cx, hh + 0.3, cz + d * 0.23), Vector3.BACK, w * 0.9, 4, 0.18, 0.2, CityGen.GLASS_LIGHT)
	mk.gable_roof(Vector3(cx, hh + 0.5, cz), w, d * 0.46, 0.22, 0.06, Color("5d6b84"), brick, 0.04)
	for s in [-1, 1]:
		mk.box_faces(Vector3(cx, hh + 0.12, cz + s * d * 0.37), Vector3(w, 0.03, d * 0.28), Color("5d6b84"), MeshKit.TOP)
	# grand entrance with a clock over it
	mk.rbox(Vector3(cx, 0.42, cz + d * 0.5 + 0.02), Vector3(0.44, 0.72, 0.05), 0.03, Color(0.3, 0.22, 0.18))
	mk.rbox(Vector3(cx, 0.88, cz + d * 0.5 + 0.12), Vector3(0.7, 0.06, 0.26), 0.02, stone)
	if not ml and not mr:
		mk.push(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(cx, 1.08, cz + d * 0.5 + 0.03)))
		mk.cylinder(Vector3.ZERO, 0.14, 0.03, 12, Color(0.98, 0.96, 0.9), true, null, -1.0, 2.0)
		mk.pop()
	# produce boxes out front
	for k in 2:
		mk.box(Vector3(cx - 0.5 + k * 1.0, 0.14, 0.86), Vector3(0.3, 0.16, 0.18), WOOD)
		mk.blob(Vector3(cx - 0.5 + k * 1.0, 0.26, 0.86), Vector3(0.12, 0.05, 0.07), PRODUCE[(x + z + k) % PRODUCE.size()])


# ------------------------------------------------------------------ department store

static func _store(mk: MeshKit, x: int, z: int, g: int) -> void:
	var f := CityGen.facing(x, z)
	var jl := _joins(x, z, (f + 3) % 4)
	var jr := _joins(x, z, (f + 1) % 4)
	var tone: Color = CityGen.pick([Color("e8e2d6"), Color("f0ece4"), Color("dfe6ec"), Color("e9d6c4")], x, z, 110)
	var brand: Color = CityGen.pick([Color("8a6fd6"), Color("3fae8c"), Color("e85d5d"), Color("2f6fb5"), Color("f2b33d")], x, z, 111)
	mk.push_at(Vector3.ZERO, CityGen.yaw_of(f))
	_paved(mk)
	var x0 := -H if jr else -0.92
	var x1 := H if jl else 0.92
	var w := x1 - x0
	var cx := (x0 + x1) * 0.5
	var d := 1.62
	var cz := -0.1
	var floors: int = [0, 2, 3, 4][g]
	var base := 0.72
	var fh := 0.56
	var hgt := base + (floors - 1) * fh
	var front := cz + d * 0.5
	mk.push_at(Vector3(cx, 0, 0))
	mk.rbox_walls(Vector3(0, 0.06 + hgt * 0.5, cz), Vector3(w, hgt, d), 0.03, tone)
	# full-height display windows lit up at night, a canopy and the brand band
	mk.window_row(Vector3(0, 0.38, front), Vector3.BACK, w * 0.9, 4, w * 0.2, 0.5, GLASS_LIGHT, false)
	mk.rbox(Vector3(0, 0.33, front + 0.02), Vector3(0.3, 0.5, 0.03), 0.01, Color(0.3, 0.32, 0.36))
	mk.box_faces(Vector3(0, 0.68, front + 0.14), Vector3(w * 0.94, 0.05, 0.28), brand.darkened(0.15), MeshKit.TOP | MeshKit.FRONT | MeshKit.LEFT | MeshKit.RIGHT)
	mk.box_faces(Vector3(0, base - 0.02, front + 0.012), Vector3(w, 0.12, 0.02), brand, MeshKit.FRONT | MeshKit.TOP)
	mk.window(Vector3(0, base - 0.02, front + 0.03), Vector3.BACK, w * 0.4, 0.07, Color(1, 1, 1), Color(0, 0, 0, 0), true)
	var fins := Game.hashf(x, z, 112) > 0.5
	for fl in range(1, floors):
		var yy := 0.06 + base + (fl - 1) * fh + fh * 0.5
		if fins:
			mk.window_row(Vector3(0, yy, front), Vector3.BACK, w * 0.9, 6, w * 0.9 / 6 * 0.7, fh * 0.7, GLASS, false)
		else:
			mk.window(Vector3(0, yy, front), Vector3.BACK, w * 0.9, fh * 0.55, GLASS)
		CityGen._windows_row(mk, yy, w, d, 0, 4, GLASS, Color(0, 0, 0, 0), [false, not jl, true, not jr], 0.24, fh * 0.6)
	if fins and floors > 1:
		# vertical fins up the front
		for k in 5:
			mk.box_faces(Vector3(-w * 0.45 + (k + 0.5) * w * 0.9 / 5, 0.06 + base + (floors - 1) * fh * 0.5, front + 0.03), Vector3(0.04, (floors - 1) * fh, 0.06), tone.lightened(0.3), MeshKit.FRONT | MeshKit.LEFT | MeshKit.RIGHT)
	else:
		mk.bands(0.06 + base + fh, w, d, fh, floors - 2, 0.03, tone.darkened(0.08))
	var top := 0.06 + hgt
	mk.ledge(Vector3(0, top + 0.04, cz), Vector3(w + 0.04, 0.08, d + 0.04), 0.02, tone.lightened(0.15))
	if g == 3 and not (jl and jr):
		# a glass dome over the atrium, flags along the parapet
		mk.cylinder(Vector3(0, top + 0.06, cz), 0.42, 0.12, 12, tone.darkened(0.1))
		mk.blob(Vector3(0, top + 0.16, cz), Vector3(0.38, 0.32, 0.38), Color(0.6, 0.78, 0.88))
	else:
		mk.rbox(Vector3(-w * 0.25, top + 0.155, cz - 0.3), Vector3(0.34, 0.19, 0.3), 0.03, Color(0.8, 0.82, 0.85))
		mk.rbox(Vector3(w * 0.22, top + 0.14, cz + 0.2), Vector3(0.22, 0.16, 0.22), 0.03, Color(0.8, 0.82, 0.85))
	for k in 3:
		var fx := -w * 0.36 + k * w * 0.36
		mk.pole(Vector3(fx, top + 0.08, front - 0.04), 0.008, 0.36, 4, Color(0.85, 0.85, 0.88))
		mk.box(Vector3(fx + 0.07, top + 0.38, front - 0.04), Vector3(0.13, 0.08, 0.006), brand if k != 1 else Color.WHITE)
	mk.pop()
	mk.pop()
