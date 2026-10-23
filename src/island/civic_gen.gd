class_name CivicGen
extends RefCounted
## The lots of the new island that are not houses: parks where the player
## painted green, paved squares with a fountain on busy main streets, and a
## church for each part of town, built in the style of its quarter. Built in
## the lot's frame like HouseGen (local +Z faces the street, the lot runs back
## to -depth) and returned as the same raw arrays.

const PAVING := Color(0.86, 0.82, 0.76)
const COBBLES := Color(0.78, 0.74, 0.69)
const WATER := Color(0.45, 0.72, 0.86)
const BENCH := Color(0.55, 0.38, 0.26)
const IRON := Color(0.22, 0.24, 0.27)


static func build(l: Town.Lot, land: Land, street_y: float, seed_value: int) -> Array:
	var mk := MeshKit.new(seed_value)
	mk.quiet_sprites = true
	var y0 := street_y
	if l.type == "park":
		# parks keep the lie of the land
		y0 = land.height_at(l.origin.x, l.origin.y)
	mk.push_at(Vector3(l.origin.x, y0, l.origin.y), l.yaw)
	match l.type:
		"park":
			_park(mk, l, land, y0)
		"square":
			_square(mk, l, land, y0)
		"church":
			_church(mk, l)
	mk.pop()
	return [mk.verts, mk.norms, mk.cols, mk.uvs, mk.dverts, mk.dnorms, mk.dcols, mk.duvs, mk.sverts, mk.snorms,
		mk.bverts, mk.bcols, mk.buvs, mk.bradius, mk.qverts, mk.qcols, mk.quvs, mk.qradius]


## Height of the real ground at a point of the lot, relative to the lot's base.
static func _ground(l: Town.Lot, land: Land, x: float, z: float, y0: float) -> float:
	var p := l.origin + Vector2(cos(l.yaw), -sin(l.yaw)) * x + Vector2(sin(l.yaw), cos(l.yaw)) * z
	return land.height_at(p.x, p.y) - y0


# ------------------------------------------------------------------ parks

static func _park(mk: MeshKit, l: Town.Lot, land: Land, y0: float) -> void:
	var rng := mk.rng
	var hw := l.width * 0.5
	# a few trees, kept off the path along the front
	var trees := 2 + rng.randi() % 3
	for k in trees:
		var x := lerpf(-hw + 0.4, hw - 0.4, rng.randf())
		var z := -lerpf(1.2, l.depth - 0.5, rng.randf())
		_tree(mk, rng, Vector3(x, _ground(l, land, x, z, y0), z))
	var feature := rng.randf()
	var fz := -l.depth * 0.45
	var gy := _ground(l, land, 0.0, fz, y0)
	if feature < 0.35:
		# a bench under a lamp, facing the street
		_bench(mk, Vector3(-0.3, _ground(l, land, -0.3, -0.7, y0), -0.7), 0.0)
		_lamp(mk, Vector3(0.45, _ground(l, land, 0.45, -0.6, y0), -0.6))
	elif feature < 0.65:
		# a round flower bed
		mk.shadow = false
		mk.cylinder(Vector3(0, gy - 0.02, fz), 0.5, 0.08, 10, Color(0.55, 0.42, 0.32), true, Color(0.42, 0.3, 0.22))
		mk.shadow = true
		for k in 6:
			var a := k * TAU / 6.0
			mk.blob(Vector3(cos(a) * 0.32, gy + 0.1, fz + sin(a) * 0.32), Vector3(0.12, 0.08, 0.12), Palette.FLOWERS[rng.randi() % Palette.FLOWERS.size()], 0.03)
	elif feature < 0.8:
		# a little pond with reeds
		mk.shadow = false
		mk.cylinder(Vector3(0, gy - 0.02, fz), 0.7, 0.05, 12, Color(0.7, 0.66, 0.6), true, WATER)
		mk.shadow = true
		for k in 3:
			mk.blob(Vector3(0.55 * cos(k * 2.1), gy + 0.1, fz + 0.55 * sin(k * 2.1)), Vector3(0.08, 0.14, 0.08), Color("5e9a4a"), 0.04)
	# shrubs dotted about the lawn
	for k in 2:
		var x := lerpf(-hw + 0.3, hw - 0.3, rng.randf())
		var z := -lerpf(0.5, l.depth - 0.3, rng.randf())
		mk.blob(Vector3(x, _ground(l, land, x, z, y0) + 0.12, z), Vector3(0.22, 0.16, 0.22), Palette.LEAF[rng.randi() % Palette.LEAF.size()].darkened(0.1), 0.06)


static func _tree(mk: MeshKit, rng: RandomNumberGenerator, at: Vector3) -> void:
	var s := lerpf(0.85, 1.35, rng.randf())
	mk.pole(at, 0.055 * s, 0.55 * s, 5, Color(0.45, 0.33, 0.24))
	var leaf: Color = Palette.LEAF[rng.randi() % Palette.LEAF.size()]
	if rng.randf() < 0.15:
		leaf = Palette.BLOSSOM[rng.randi() % Palette.BLOSSOM.size()]
	mk.blob(at + Vector3(0, 0.8 * s, 0), Vector3(0.48, 0.44, 0.48) * s, leaf, 0.1)
	mk.blob(at + Vector3(0.2 * s, 1.06 * s, -0.05), Vector3(0.32, 0.3, 0.32) * s, leaf.lightened(0.08), 0.1)


static func _bench(mk: MeshKit, at: Vector3, yaw: float) -> void:
	mk.push_at(at, yaw)
	mk.box_faces(Vector3(0, 0.12, 0), Vector3(0.5, 0.03, 0.14), BENCH, MeshKit.TOP | MeshKit.FRONT | MeshKit.LEFT | MeshKit.RIGHT)
	mk.box_faces(Vector3(0, 0.22, -0.07), Vector3(0.5, 0.12, 0.025), BENCH, MeshKit.FRONT | MeshKit.BACK | MeshKit.TOP)
	for sx: float in [-0.2, 0.2]:
		mk.box_faces(Vector3(sx, 0.055, 0), Vector3(0.03, 0.11, 0.12), IRON, MeshKit.FRONT | MeshKit.LEFT | MeshKit.RIGHT)
	mk.pop()


static func _lamp(mk: MeshKit, at: Vector3) -> void:
	mk.pole(at, 0.03, 0.85, 4, IRON)
	mk.box(at + Vector3(0, 0.9, 0), Vector3(0.11, 0.12, 0.11), Color(1, 0.88, 0.62), null, false, 2.0)
	mk.cone(at + Vector3(0, 0.96, 0), 0.1, 0.08, 4, IRON)


# ------------------------------------------------------------------ squares

static func _square(mk: MeshKit, l: Town.Lot, land: Land, y0: float) -> void:
	var rng := mk.rng
	var w := l.width
	var d := l.depth
	var cz := -d * 0.5
	# cobbled square edged with paving, sunk a little into its levelled plot
	# where the hillside falls away, the square stands on a stone retaining wall
	var lo := 0.0
	for c: Vector2 in [Vector2(-w * 0.5, 0.0), Vector2(w * 0.5, 0.0), Vector2(-w * 0.5, -d), Vector2(w * 0.5, -d), Vector2(0, cz)]:
		lo = minf(lo, _ground(l, land, c.x, c.y, y0))
	mk.shadow = false
	mk.box_faces(Vector3(0, (0.03 + lo - 0.1) * 0.5, cz), Vector3(w, 0.03 - lo + 0.1, d), PAVING, MeshKit.TOP)
	mk.shadow = true
	if lo < -0.06:
		mk.box_faces(Vector3(0, (0.02 + lo - 0.1) * 0.5, cz), Vector3(w + 0.02, 0.02 - lo + 0.1, d + 0.02), HouseGen.STONE, MeshKit.LEFT | MeshKit.RIGHT | MeshKit.BACK)
	mk.shadow = false
	mk.box_faces(Vector3(0, 0.032, cz), Vector3(w - 0.5, 0.01, d - 0.5), COBBLES, MeshKit.TOP, MeshKit.COBBLE)
	mk.shadow = true
	# a fountain in the middle
	var fc := Vector3(0, 0.03, cz)
	mk.cylinder(fc, 0.75, 0.16, 14, Color(0.8, 0.77, 0.72), true, WATER)
	mk.cylinder(fc + Vector3(0, 0.16, 0), 0.16, 0.36, 8, Color(0.8, 0.77, 0.72))
	mk.cylinder(fc + Vector3(0, 0.52, 0), 0.32, 0.06, 10, Color(0.84, 0.81, 0.76), true, WATER)
	mk.blob(fc + Vector3(0, 0.68, 0), Vector3(0.08, 0.16, 0.08), WATER.lightened(0.4), 0.02)
	# trees at the back corners, benches facing the fountain, lamps at the front
	for sx: float in [-1.0, 1.0]:
		_tree(mk, rng, Vector3(sx * (w * 0.5 - 0.5), 0.03, -d + 0.55))
		_bench(mk, Vector3(sx * 1.4, 0.03, cz), -sx * PI * 0.5)
		_lamp(mk, Vector3(sx * (w * 0.5 - 0.3), 0.03, -0.3))
	# a market stall or two, awnings bright
	for k in rng.randi() % 3:
		var sx := (k * 2 - 1) * (w * 0.5 - 1.1)
		var awn: Color = Palette.AWNINGS[rng.randi() % Palette.AWNINGS.size()]
		mk.box(Vector3(sx, 0.2, -0.95), Vector3(0.7, 0.34, 0.36), Color(0.62, 0.45, 0.32))
		for px: float in [-0.32, 0.32]:
			mk.pole(Vector3(sx + px, 0.03, -0.8), 0.015, 0.62, 4, Color(0.4, 0.4, 0.4))
		mk.push(Transform3D(Basis(Vector3.RIGHT, 0.3), Vector3(sx, 0.66, -0.9)))
		mk.box_faces(Vector3.ZERO, Vector3(0.82, 0.03, 0.5), awn, MeshKit.TOP | MeshKit.FRONT | MeshKit.LEFT | MeshKit.RIGHT)
		mk.pop()
		for j in 3:
			mk.blob(Vector3(sx - 0.2 + j * 0.2, 0.42, -0.85), Vector3(0.07, 0.05, 0.07), Palette.FLOWERS[rng.randi() % Palette.FLOWERS.size()], 0.02)


# ------------------------------------------------------------------ churches

static func _church(mk: MeshKit, l: Town.Lot) -> void:
	var rng := mk.rng
	var K: Dictionary = HouseGen.KITS[l.kit]
	var wall: Color = K.walls[rng.randi() % K.walls.size()]
	var roof: Color = K.roofs[rng.randi() % K.roofs.size()]
	var trim: Color = K.trim if K.trim != null else wall.lightened(0.45)
	var we := 0.0
	if l.kit == HouseGen.BRICK:
		we = MeshKit.BRICKS
		trim = Color(0.95, 0.92, 0.86)
	elif l.kit == HouseGen.NORDIC:
		we = MeshKit.SIDING
	elif l.kit == HouseGen.STONE_SLATE:
		wall = Color(0.82, 0.78, 0.7)
	var nw := minf(l.width - 1.6, 2.2)
	var nd := minf(l.depth - 1.6, 4.2)
	var nh := 1.55
	var tw := 0.95
	var th := 3.1 if l.kit != HouseGen.NORDIC else 2.6
	# a forecourt, the tower at the front, the nave behind it
	var tz := -0.7 - tw * 0.5
	var nz := tz - tw * 0.5 - nd * 0.5 + 0.1
	mk.shadow = false
	mk.box_faces(Vector3(0, 0.0, -0.35), Vector3(l.width, 0.05, 0.7), CivicGen.PAVING, MeshKit.TOP)
	mk.shadow = true
	# nave, gable end towards the street
	mk.push_at(Vector3(0, 0, nz))
	mk.box_faces(Vector3(0, nh * 0.5, 0), Vector3(nw, nh, nd), wall, MeshKit.FRONT | MeshKit.BACK | MeshKit.LEFT | MeshKit.RIGHT, we)
	var pitch := clampf(lerpf(K.pitch.x, K.pitch.y, 0.7) + 0.25, 0.6, 1.4)
	mk.push_at(Vector3.ZERO, PI * 0.5)
	mk.gable_roof(Vector3(0, nh, 0), nd, nw, nw * 0.5 * pitch, 0.1, roof, wall)
	mk.pop()
	# tall windows down both sides, a rose window at the back
	for sx: float in [-1.0, 1.0]:
		mk.window_row(Vector3(sx * nw * 0.5, nh * 0.52, 0), Vector3.RIGHT * sx, nd - 0.4, int(nd / 0.8), 0.22, 0.72, Palette.GLASS_LIGHT, true)
	mk.window(Vector3(0, nh + 0.25, -nd * 0.5), Vector3.FORWARD, 0.36, 0.36, Palette.GLASS_LIGHT, Color(1, 1, 1, 1))
	mk.pop()
	# the tower: stages marked by bands, a door, belfry openings and a clock
	mk.push_at(Vector3(0, 0, tz))
	mk.box_faces(Vector3(0, th * 0.5, 0), Vector3(tw, th, tw), wall, MeshKit.FRONT | MeshKit.BACK | MeshKit.LEFT | MeshKit.RIGHT, we)
	mk.bands(th * 0.42, tw, tw, th * 0.34, 2, 0.05, trim)
	mk.box_faces(Vector3(0, 0.34, tw * 0.5 + 0.015), Vector3(0.34, 0.62, 0.03), Color(0.42, 0.28, 0.2), MeshKit.FRONT | MeshKit.LEFT | MeshKit.RIGHT | MeshKit.TOP)
	mk.box_faces(Vector3(0, 0.67, tw * 0.5 + 0.04), Vector3(0.44, 0.05, 0.06), trim, MeshKit.FRONT | MeshKit.TOP)
	for k in 4:
		var out: Vector3 = [Vector3.BACK, Vector3.RIGHT, Vector3.FORWARD, Vector3.LEFT][k]
		mk.window(out * tw * 0.5 + Vector3(0, th - 0.42, 0), out, 0.22, 0.38, Color(0.18, 0.2, 0.24), Color(1, 1, 1, 1))
		if k == 0:
			mk.window(out * tw * 0.5 + Vector3(0, th * 0.62, 0), out, 0.3, 0.3, Color(0.98, 0.96, 0.9), Color(0, 0, 0, 0), true)
	var top := Vector3(0, th, 0)
	match l.kit:
		HouseGen.SOUTH:
			# a campanile with a low tiled cap
			mk.ledge(top + Vector3(0, 0.05, 0), Vector3(tw + 0.1, 0.1, tw + 0.1), 0.02, trim)
			mk.hip_roof(top + Vector3(0, 0.1, 0), tw, tw, 0.32, 0.06, roof)
		HouseGen.HARBOUR:
			# a white tower with a blue dome
			mk.ledge(top + Vector3(0, 0.05, 0), Vector3(tw + 0.1, 0.1, tw + 0.1), 0.02, trim)
			mk.cylinder(top + Vector3(0, 0.1, 0), tw * 0.42, 0.22, 12, wall)
			mk.cylinder(top + Vector3(0, 0.32, 0), tw * 0.44, 0.22, 12, roof, true, null, tw * 0.3)
			mk.cylinder(top + Vector3(0, 0.54, 0), tw * 0.3, 0.12, 12, roof, true, null, tw * 0.1)
			mk.pole(top + Vector3(0, 0.66, 0), 0.02, 0.3, 4, Color(0.9, 0.8, 0.4))
		_:
			# a spire, steep and slender
			mk.ledge(top + Vector3(0, 0.04, 0), Vector3(tw + 0.08, 0.08, tw + 0.08), 0.02, trim)
			var spire := 1.9 if l.kit != HouseGen.NORDIC else 1.5
			mk.cone(top + Vector3(0, 0.08, 0), tw * 0.62, spire, 4, roof)
			mk.pole(top + Vector3(0, spire + 0.02, 0), 0.015, 0.28, 4, Color(0.9, 0.8, 0.4))
	mk.pop()
	# a churchyard tree or two
	for sx: float in [-1.0, 1.0]:
		if rng.randf() < 0.6:
			_tree(mk, rng, Vector3(sx * (l.width * 0.5 - 0.45), 0.0, nz - nd * 0.3))
