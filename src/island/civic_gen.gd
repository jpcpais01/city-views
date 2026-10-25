class_name CivicGen
extends RefCounted
## The lots of the new island that are not houses: parks where the player
## painted green, paved squares with a fountain on busy main streets, a
## church for each part of town, a town hall in the heart of it, schools among
## the homes, market halls where it is busy and the city's services (fire
## stations, police stations and hospitals), built in the style of its quarter. Built in
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
		"hall":
			_town_hall(mk, l)
		"school":
			_school(mk, l)
		"market":
			_market(mk, l)
		"fire":
			_fire_station(mk, l)
		"police":
			_police_station(mk, l)
		"hospital":
			_hospital(mk, l)
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


# ------------------------------------------------------------------ public buildings

## The quarter's wall, roof and trim colours for a public building, and the
## wall's surface pattern: dressed stone, or the quarter's brick or siding.
static func _civic_colours(l: Town.Lot, rng: RandomNumberGenerator) -> Array:
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
	else:
		wall = wall.lerp(Color(0.9, 0.86, 0.78), 0.5)
	return [wall, roof, trim, we]


## A town hall: two tall floors behind a columned portico, a clock tower on
## the roof and a flag flying over the forecourt.
static func _town_hall(mk: MeshKit, l: Town.Lot) -> void:
	var c := _civic_colours(l, mk.rng)
	var wall: Color = c[0]
	var roof: Color = c[1]
	var trim: Color = c[2]
	var bw := minf(l.width - 0.8, 4.2)
	var bd := minf(l.depth - 1.1, 2.6)
	var bh := 1.7
	var bz := -1.0 - bd * 0.5
	var zf := bz + bd * 0.5
	mk.shadow = false
	mk.box_faces(Vector3(0, 0.0, -0.5), Vector3(l.width, 0.05, 1.0), PAVING, MeshKit.TOP)
	mk.shadow = true
	mk.box_faces(Vector3(0, bh * 0.5, bz), Vector3(bw, bh, bd), wall, MeshKit.FRONT | MeshKit.BACK | MeshKit.LEFT | MeshKit.RIGHT, c[3])
	mk.ledge(Vector3(0, bh + 0.04, bz), Vector3(bw + 0.1, 0.08, bd + 0.1), 0.02, trim)
	mk.hip_roof(Vector3(0, bh + 0.08, bz), bw, bd, 0.5, 0.06, roof)
	# tall windows on both floors all round
	for fl in 2:
		var y := 0.45 + fl * 0.82
		mk.window_row(Vector3(0, y, zf), Vector3.BACK, bw - 0.3, int(bw / 0.5), 0.2, 0.42, Palette.GLASS_LIGHT, true)
		mk.window_row(Vector3(0, y, bz - bd * 0.5), Vector3.FORWARD, bw - 0.3, int(bw / 0.5), 0.2, 0.42, Palette.GLASS_LIGHT, true)
		for sx: float in [-1.0, 1.0]:
			mk.window_row(Vector3(sx * bw * 0.5, y, bz), Vector3.RIGHT * sx, bd - 0.3, int(bd / 0.5), 0.2, 0.42, Palette.GLASS_LIGHT, true)
	# the portico: steps, four columns, an entablature and a pediment
	var pz := zf + 0.36
	mk.box_faces(Vector3(0, 0.05, pz), Vector3(1.7, 0.1, 0.72), PAVING.darkened(0.06), MeshKit.TOP | MeshKit.FRONT | MeshKit.LEFT | MeshKit.RIGHT)
	for x: float in [-0.66, -0.22, 0.22, 0.66]:
		mk.pole(Vector3(x, 0.1, pz + 0.24), 0.05, 0.96, 6, trim)
	mk.box_faces(Vector3(0, 1.12, pz), Vector3(1.66, 0.14, 0.72), trim, MeshKit.FRONT | MeshKit.LEFT | MeshKit.RIGHT)
	mk.push_at(Vector3(0, 1.19, pz), PI * 0.5)
	mk.gable_roof(Vector3.ZERO, 0.72, 1.66, 0.32, 0.04, roof, trim)
	mk.pop()
	mk.box_faces(Vector3(0, 0.42, zf + 0.012), Vector3(0.42, 0.64, 0.02), Color(0.42, 0.28, 0.2), MeshKit.FRONT)
	# the clock tower rising from the middle of the roof
	var tw := 0.72
	var ty := bh + 0.08
	mk.push_at(Vector3(0, ty, bz))
	mk.box_faces(Vector3(0, 0.55, 0), Vector3(tw, 1.1, tw), wall, MeshKit.FRONT | MeshKit.BACK | MeshKit.LEFT | MeshKit.RIGHT, c[3])
	mk.ledge(Vector3(0, 1.13, 0), Vector3(tw + 0.08, 0.06, tw + 0.08), 0.02, trim)
	for k in 4:
		var out: Vector3 = [Vector3.BACK, Vector3.RIGHT, Vector3.FORWARD, Vector3.LEFT][k]
		mk.window(out * tw * 0.5 + Vector3(0, 0.78, 0), out, 0.32, 0.32, Color(0.98, 0.96, 0.9), Color(0, 0, 0, 0), true)
	mk.hip_roof(Vector3(0, 1.16, 0), tw, tw, 0.42, 0.04, roof)
	mk.pole(Vector3(0, 1.56, 0), 0.015, 0.22, 4, Color(0.9, 0.8, 0.4))
	mk.pop()
	# a flag over the forecourt and lamps either side
	var fx := l.width * 0.5 - 0.4
	mk.pole(Vector3(-fx, 0.0, -0.3), 0.02, 1.9, 4, Color(0.9, 0.9, 0.88))
	mk.box_faces(Vector3(-fx + 0.24, 1.72, -0.3), Vector3(0.44, 0.28, 0.01), Color("c8553d"), MeshKit.FRONT | MeshKit.BACK)
	_lamp(mk, Vector3(fx, 0.0, -0.3))
	_bench(mk, Vector3(fx - 0.6, 0.0, -0.75), 0.0)


## A school: a long two-storey block at the back of a playground marked out
## for games, a bell cupola over the door and railings along the street.
static func _school(mk: MeshKit, l: Town.Lot) -> void:
	var rng := mk.rng
	var c := _civic_colours(l, rng)
	var wall: Color = c[0]
	var roof: Color = c[1]
	var trim: Color = c[2]
	var bw := l.width - 0.8
	var bd := 1.6
	var bh := HouseGen.FH * 2.0
	var bz := -l.depth + 0.4 + bd * 0.5
	var zf := bz + bd * 0.5
	# the playground, with a court painted on it
	var yd := zf + 0.1
	mk.shadow = false
	mk.box_faces(Vector3(0, 0.0, yd * 0.5), Vector3(l.width - 0.3, 0.05, -yd), Color(0.6, 0.6, 0.6), MeshKit.TOP)
	var cw := minf(bw - 0.6, 3.2)
	var cd := minf(-yd - 0.8, 1.8)
	var cz := yd * 0.5
	var line := Color(0.96, 0.96, 0.94)
	for sz: float in [-1.0, 1.0]:
		mk.box_faces(Vector3(0, 0.03, cz + sz * cd * 0.5), Vector3(cw, 0.01, 0.04), line, MeshKit.TOP)
	for sx: float in [-1.0, 0.0, 1.0]:
		mk.box_faces(Vector3(sx * cw * 0.5, 0.03, cz), Vector3(0.04, 0.01, cd), line, MeshKit.TOP)
	mk.shadow = true
	# a hoop at each end of the court
	for sx: float in [-1.0, 1.0]:
		var hx := sx * (cw * 0.5 + 0.15)
		mk.pole(Vector3(hx, 0.0, cz), 0.02, 0.62, 4, IRON)
		mk.box_faces(Vector3(hx - sx * 0.03, 0.62, cz), Vector3(0.02, 0.2, 0.3), Color(0.96, 0.96, 0.94), MeshKit.LEFT | MeshKit.RIGHT | MeshKit.TOP)
	# the school building, gable ends to the sides
	mk.box_faces(Vector3(0, bh * 0.5, bz), Vector3(bw, bh, bd), wall, MeshKit.FRONT | MeshKit.BACK | MeshKit.LEFT | MeshKit.RIGHT, c[3])
	mk.push_at(Vector3(0, 0, bz))
	mk.bands(HouseGen.FH, bw, bd, 1.0, 1, 0.04, trim)
	mk.pop()
	mk.gable_roof(Vector3(0, bh, bz), bw, bd, 0.42, 0.08, roof, wall)
	# big classroom windows on both floors, a canopy over the door
	for fl in 2:
		var y := HouseGen.FH * (fl + 0.55)
		mk.window_row(Vector3(0, y, zf), Vector3.BACK, bw - 0.5, int(bw / 0.45), 0.32, 0.34, Palette.GLASS_LIGHT, true)
		mk.window_row(Vector3(0, y, bz - bd * 0.5), Vector3.FORWARD, bw - 0.5, int(bw / 0.45), 0.32, 0.34, Palette.GLASS_LIGHT, true)
	mk.box_faces(Vector3(0, 0.3, zf + 0.015), Vector3(0.5, 0.56, 0.03), Color("2f6f8f"), MeshKit.FRONT | MeshKit.LEFT | MeshKit.RIGHT)
	mk.box_faces(Vector3(0, 0.64, zf + 0.22), Vector3(0.9, 0.04, 0.44), trim, MeshKit.TOP | MeshKit.FRONT | MeshKit.LEFT | MeshKit.RIGHT)
	# a little bell cupola on the ridge
	var ry := bh + 0.42
	mk.box_faces(Vector3(0, ry + 0.12, bz), Vector3(0.26, 0.26, 0.26), trim, MeshKit.FRONT | MeshKit.BACK | MeshKit.LEFT | MeshKit.RIGHT)
	mk.cone(Vector3(0, ry + 0.25, bz), 0.24, 0.26, 4, roof)
	# railings along the street, with the gate in the middle
	for sx: float in [-1.0, 1.0]:
		var run := l.width * 0.5 - 0.7
		mk.box_faces(Vector3(sx * (0.5 + run * 0.5), 0.14, -0.12), Vector3(run, 0.28, 0.02), IRON, MeshKit.FRONT | MeshKit.BACK | MeshKit.TOP)
	for sx: float in [-1.0, 1.0]:
		if rng.randf() < 0.75:
			_tree(mk, rng, Vector3(sx * (l.width * 0.5 - 0.4), 0.0, -0.55))


## A market hall: a big gabled hall end-on to the street, a glazed lantern
## along its ridge, a great round window over the doors and stalls outside.
static func _market(mk: MeshKit, l: Town.Lot) -> void:
	var rng := mk.rng
	var c := _civic_colours(l, rng)
	var wall: Color = c[0]
	var roof: Color = c[1].lerp(Color(0.38, 0.42, 0.46), 0.5)
	var trim: Color = c[2]
	var hw := l.width - 0.6
	var hd := minf(l.depth - 0.9, 3.6)
	var wh := 1.15
	var hz := -0.8 - hd * 0.5
	var zf := hz + hd * 0.5
	var rise := hw * 0.36
	mk.shadow = false
	mk.box_faces(Vector3(0, 0.0, -0.4), Vector3(l.width, 0.05, 0.8), COBBLES, MeshKit.TOP)
	mk.shadow = true
	mk.box_faces(Vector3(0, wh * 0.5, hz), Vector3(hw, wh, hd), wall, MeshKit.FRONT | MeshKit.BACK | MeshKit.LEFT | MeshKit.RIGHT, c[3])
	mk.push_at(Vector3(0, wh, hz), PI * 0.5)
	mk.gable_roof(Vector3.ZERO, hd, hw, rise, 0.1, roof, wall)
	mk.pop()
	# the glazed lantern letting light down the middle of the hall
	mk.box_faces(Vector3(0, wh + rise + 0.04, hz), Vector3(0.36, 0.14, hd * 0.8), Color(0.72, 0.84, 0.9), MeshKit.TOP | MeshKit.LEFT | MeshKit.RIGHT | MeshKit.FRONT | MeshKit.BACK)
	# tall arched windows down the sides, a big round one in the gable
	for sx: float in [-1.0, 1.0]:
		mk.window_row(Vector3(sx * hw * 0.5, wh * 0.55, hz), Vector3.RIGHT * sx, hd - 0.4, int(hd / 0.6), 0.26, 0.62, Palette.GLASS_LIGHT, true)
	mk.window(Vector3(0, wh + rise * 0.42, zf), Vector3.BACK, rise * 0.75, rise * 0.75, Color(1.0, 0.9, 0.7), Color(1, 1, 1, 1), true)
	# wide doors under a sign
	mk.box_faces(Vector3(0, 0.38, zf + 0.012), Vector3(0.9, 0.72, 0.02), Color(0.36, 0.24, 0.18), MeshKit.FRONT)
	mk.box_faces(Vector3(0, 0.86, zf + 0.03), Vector3(1.3, 0.16, 0.05), trim, MeshKit.FRONT | MeshKit.TOP)
	for sx: float in [-1.0, 1.0]:
		mk.window(Vector3(sx * hw * 0.32, 0.42, zf), Vector3.BACK, 0.4, 0.5, Palette.GLASS_LIGHT, Color(1, 1, 1, 1), true)
	# market stalls out front under striped canopies, with produce on show
	var fruit := [Color("e8503a"), Color("f2b33d"), Color("6fb35a"), Color("f08a24"), Color("8c5aa8")]
	for sx: float in [-1.0, 1.0]:
		var x := sx * (l.width * 0.5 - 0.75)
		var awn: Color = Palette.AWNINGS[rng.randi() % Palette.AWNINGS.size()]
		mk.box_faces(Vector3(x, 0.17, -0.45), Vector3(0.8, 0.06, 0.4), Color(0.62, 0.45, 0.3), MeshKit.TOP | MeshKit.FRONT | MeshKit.LEFT | MeshKit.RIGHT)
		for k in 3:
			mk.box_faces(Vector3(x + (k - 1) * 0.25, 0.215, -0.45), Vector3(0.2, 0.03, 0.3), fruit[rng.randi() % fruit.size()], MeshKit.TOP)
		for px: float in [-0.38, 0.38]:
			mk.pole(Vector3(x + px, 0.0, -0.27), 0.012, 0.5, 4, IRON)
		for k in 2:
			mk.push(Transform3D(Basis(Vector3.RIGHT, 0.3), Vector3(x, 0.5, -0.45)))
			mk.box_faces(Vector3((k - 0.5) * 0.43, 0, 0), Vector3(0.43, 0.02, 0.5), awn if k == 0 else Color(0.98, 0.97, 0.94), MeshKit.TOP | MeshKit.FRONT)
			mk.pop()


## A vehicle parked at `at` facing `yaw` (0: nose to the street): a body, a
## stripe down its sides, and a cabin with a light bar (a car) or a
## windscreen with lamps over it (a van or an engine).
static func _vehicle(mk: MeshKit, at: Vector3, yaw: float, body: Color, stripe: Color, lamp: Color, length: float, tall: float) -> void:
	mk.push_at(at, yaw)
	var car := length < 0.8
	var w := 0.34 if car else 0.42
	var all := MeshKit.TOP | MeshKit.FRONT | MeshKit.BACK | MeshKit.LEFT | MeshKit.RIGHT
	mk.box_faces(Vector3(0, 0.03 + tall * 0.5, 0), Vector3(w, tall, length), body, all)
	mk.box_faces(Vector3(0, 0.03 + tall * 0.42, 0), Vector3(w + 0.01, 0.05, length + 0.01), stripe, MeshKit.FRONT | MeshKit.BACK | MeshKit.LEFT | MeshKit.RIGHT)
	if car:
		mk.box_faces(Vector3(0, 0.03 + tall + 0.07, -0.02), Vector3(w - 0.04, 0.14, length * 0.5), Color(0.25, 0.32, 0.38), all, 1.0)
		mk.box(Vector3(0, 0.03 + tall + 0.17, -0.02), Vector3(0.22, 0.07, 0.08), lamp, null, false, 2.0)
	else:
		mk.box_faces(Vector3(0, 0.03 + tall * 0.75, length * 0.5 + 0.005), Vector3(w - 0.06, tall * 0.3, 0.01), Color(0.25, 0.32, 0.38), MeshKit.FRONT, 1.0)
		for sx: float in [-1.0, 1.0]:
			mk.box(Vector3(sx * (w * 0.5 - 0.07), 0.03 + tall + 0.035, length * 0.5 - 0.1), Vector3(0.08, 0.07, 0.08), lamp, null, false, 2.0)
	mk.pop()


## A fire station: a two-storey brick hall with three tall red engine doors
## on the street, one of them open with its engine out on the apron, and the
## tall tower at the side where the hoses hang to dry.
static func _fire_station(mk: MeshKit, l: Town.Lot) -> void:
	var rng := mk.rng
	var wall := Color("a9503b")
	var trim := Color(0.95, 0.93, 0.88)
	var red := Color("d33a2c")
	var all := MeshKit.TOP | MeshKit.FRONT | MeshKit.BACK | MeshKit.LEFT | MeshKit.RIGHT
	var tw := 0.9
	var bw := minf(l.width - 0.5, 4.0) - tw
	var bd := minf(l.depth - 1.0, 2.4)
	var bh := HouseGen.FH * 2.0 + 0.12
	var bx := -tw * 0.5
	var bz := -1.0 - bd * 0.5
	var zf := bz + bd * 0.5
	# the apron the engines roll out onto, a yellow line before each door
	mk.shadow = false
	mk.box_faces(Vector3(0, 0.0, -0.5), Vector3(l.width, 0.05, 1.0), Color(0.7, 0.7, 0.68), MeshKit.TOP)
	for k in 3:
		mk.box_faces(Vector3(bx + (k - 1) * bw / 3.0, 0.03, -0.5), Vector3(0.05, 0.01, 0.9), Color(0.95, 0.82, 0.3), MeshKit.TOP)
	mk.shadow = true
	# the hall, its flat roof behind a white parapet, a white sign band
	mk.box_faces(Vector3(bx, bh * 0.5, bz), Vector3(bw, bh, bd), wall, MeshKit.FRONT | MeshKit.BACK | MeshKit.LEFT | MeshKit.RIGHT, MeshKit.BRICKS)
	mk.box_faces(Vector3(bx, bh + 0.05, bz), Vector3(bw + 0.06, 0.1, bd + 0.06), trim, all)
	mk.box_faces(Vector3(bx, 0.86, zf + 0.02), Vector3(bw - 0.2, 0.14, 0.04), trim, MeshKit.FRONT | MeshKit.TOP)
	mk.window_row(Vector3(bx, HouseGen.FH * 1.55, zf), Vector3.BACK, bw - 0.4, int(bw / 0.5), 0.24, 0.3, Palette.GLASS_LIGHT, true)
	# the engine doors, red in white frames, one open with its engine out
	var open := rng.randi() % 3
	for k in 3:
		var dx := bx + (k - 1) * bw / 3.0
		var dw := bw / 3.0 - 0.18
		mk.box_faces(Vector3(dx, 0.39, zf + 0.012), Vector3(dw + 0.08, 0.78, 0.02), trim, MeshKit.FRONT)
		mk.box_faces(Vector3(dx, 0.37, zf + 0.022), Vector3(dw, 0.72, 0.02), Color(0.12, 0.11, 0.11) if k == open else red, MeshKit.FRONT)
		if k == open:
			_vehicle(mk, Vector3(dx, 0.0, zf + 0.62), 0.0, red, trim, Color(0.35, 0.55, 1.0), 1.15, 0.42)
			mk.box_faces(Vector3(dx, 0.5, zf + 0.5), Vector3(0.16, 0.05, 0.95), Color(0.85, 0.86, 0.88), MeshKit.TOP | MeshKit.LEFT | MeshKit.RIGHT)
	# the hose tower at the side, slit windows up it and a lamp on top
	var tx := bx + bw * 0.5 + tw * 0.5
	var th := HouseGen.FH * 4.0
	var tz := bz - 0.2
	mk.box_faces(Vector3(tx, th * 0.5, tz), Vector3(tw - 0.1, th, tw - 0.1), wall, MeshKit.FRONT | MeshKit.BACK | MeshKit.LEFT | MeshKit.RIGHT, MeshKit.BRICKS)
	mk.box_faces(Vector3(tx, th + 0.05, tz), Vector3(tw, 0.1, tw), trim, all)
	for fl in 3:
		mk.window(Vector3(tx, 0.7 + fl * 0.62, tz + (tw - 0.1) * 0.5), Vector3.BACK, 0.14, 0.34, Palette.GLASS_LIGHT, Color(0, 0, 0, 0), fl == 0)
	mk.box(Vector3(tx, th + 0.16, tz), Vector3(0.12, 0.12, 0.12), Color(0.95, 0.85, 0.6), null, false, 2.75)


## A police station: a three-storey block in pale stone with a dark blue
## band under the roof, glass doors under a canopy with the blue lamp beside
## them, and patrol cars parked out front.
static func _police_station(mk: MeshKit, l: Town.Lot) -> void:
	var rng := mk.rng
	var c := _civic_colours(l, rng)
	var wall: Color = (c[0] as Color).lerp(Color(0.86, 0.87, 0.88), 0.6)
	var blue := Color("24467f")
	var all := MeshKit.TOP | MeshKit.FRONT | MeshKit.BACK | MeshKit.LEFT | MeshKit.RIGHT
	var bw := minf(l.width - 0.6, 3.4)
	var bd := minf(l.depth - 1.2, 2.0)
	var floors := 3
	var bh := HouseGen.FH * floors + 0.1
	var bz := -1.15 - bd * 0.5
	var zf := bz + bd * 0.5
	mk.shadow = false
	mk.box_faces(Vector3(0, 0.0, -0.58), Vector3(l.width, 0.05, 1.15), Color(0.66, 0.66, 0.65), MeshKit.TOP)
	mk.shadow = true
	mk.box_faces(Vector3(0, bh * 0.5, bz), Vector3(bw, bh, bd), wall, MeshKit.FRONT | MeshKit.BACK | MeshKit.LEFT | MeshKit.RIGHT)
	mk.box_faces(Vector3(0, bh - 0.12, bz), Vector3(bw + 0.02, 0.24, bd + 0.02), blue, MeshKit.FRONT | MeshKit.BACK | MeshKit.LEFT | MeshKit.RIGHT)
	mk.box_faces(Vector3(0, bh + 0.04, bz), Vector3(bw + 0.08, 0.08, bd + 0.08), Color(0.32, 0.34, 0.38), all)
	mk.window_grid(Vector3(0, HouseGen.FH, zf), Vector3.BACK, bw - 0.3, int(bw / 0.42), floors - 1, 0.24, Palette.GLASS, 1)
	for sx: float in [-1.0, 1.0]:
		mk.window_grid(Vector3(sx * bw * 0.5, HouseGen.FH, bz), Vector3.RIGHT * sx, bd - 0.3, int(bd / 0.42), floors - 1, 0.24, Palette.GLASS, 1)
	mk.window_row(Vector3(-bw * 0.3, 0.38, zf), Vector3.BACK, bw * 0.3, 2, 0.26, 0.3, Palette.GLASS_LIGHT, true)
	# the way in: glass doors under a canopy, the blue lamp on its post
	mk.box_faces(Vector3(0.3, 0.3, zf + 0.012), Vector3(0.6, 0.56, 0.02), Color(0.3, 0.42, 0.5), MeshKit.FRONT, 1.0)
	mk.box_faces(Vector3(0.3, 0.66, zf + 0.25), Vector3(1.1, 0.05, 0.5), blue, MeshKit.TOP | MeshKit.FRONT | MeshKit.LEFT | MeshKit.RIGHT)
	mk.pole(Vector3(0.95, 0.0, zf + 0.35), 0.02, 0.62, 4, Color(0.2, 0.2, 0.22))
	mk.box(Vector3(0.95, 0.7, zf + 0.35), Vector3(0.12, 0.14, 0.12), Color(0.35, 0.55, 1.0), null, false, 2.0)
	# patrol cars, white with a blue stripe, nose to the street
	var white := Color(0.96, 0.96, 0.95)
	for sx: float in [-1.0, 1.0]:
		if sx < 0.0 or rng.randf() < 0.6:
			_vehicle(mk, Vector3(sx * (l.width * 0.5 - 0.55), 0.0, -0.62), 0.0, white, blue, Color(0.35, 0.55, 1.0), 0.66, 0.16)


## A hospital: a tall white block with rows of windows, the red cross lit on
## its front, a helipad on the roof, and a low wing out to the street with
## the emergency entrance under a wide canopy and an ambulance waiting.
static func _hospital(mk: MeshKit, l: Town.Lot) -> void:
	var rng := mk.rng
	var white := Color(0.95, 0.95, 0.93)
	var green := Color("4f9a8a")
	var red := Color("d9363e")
	var all := MeshKit.TOP | MeshKit.FRONT | MeshKit.BACK | MeshKit.LEFT | MeshKit.RIGHT
	var bw := minf(l.width - 0.6, 5.2)
	var bd := minf(l.depth - 1.8, 2.2)
	var floors := 5
	var bh := HouseGen.FH * floors + 0.1
	var bz := -l.depth + 0.25 + bd * 0.5
	var zf := bz + bd * 0.5
	mk.shadow = false
	mk.box_faces(Vector3(0, 0.0, zf * 0.5), Vector3(l.width, 0.05, -zf), Color(0.68, 0.68, 0.67), MeshKit.TOP)
	mk.shadow = true
	# the ward block, green bands at its ends
	mk.box_faces(Vector3(0, bh * 0.5, bz), Vector3(bw, bh, bd), white, MeshKit.FRONT | MeshKit.BACK | MeshKit.LEFT | MeshKit.RIGHT)
	mk.box_faces(Vector3(0, bh + 0.04, bz), Vector3(bw + 0.06, 0.08, bd + 0.06), Color(0.78, 0.8, 0.8), all)
	mk.window_grid(Vector3(0, HouseGen.FH, zf), Vector3.BACK, bw - 0.7, int(bw / 0.46), floors - 1, 0.22, Palette.GLASS, 1)
	mk.window_grid(Vector3(0, HouseGen.FH, bz - bd * 0.5), Vector3.FORWARD, bw - 0.7, int(bw / 0.46), floors - 1, 0.22, Palette.GLASS, 1)
	for sx: float in [-1.0, 1.0]:
		mk.window_grid(Vector3(sx * bw * 0.5, HouseGen.FH, bz), Vector3.RIGHT * sx, bd - 0.3, int(bd / 0.46), floors - 1, 0.22, Palette.GLASS, 1)
		mk.box_faces(Vector3(sx * (bw * 0.5 - 0.15), bh * 0.5, zf + 0.012), Vector3(0.3, bh - 0.05, 0.02), green, MeshKit.FRONT)
	# the red cross, lit, high on the front
	var cy := bh - 0.42
	mk.box_faces(Vector3(0, cy, zf + 0.02), Vector3(0.62, 0.62, 0.03), white, MeshKit.FRONT)
	mk.box_faces(Vector3(0, cy, zf + 0.04), Vector3(0.48, 0.15, 0.02), red, MeshKit.FRONT, 2.75)
	mk.box_faces(Vector3(0, cy, zf + 0.04), Vector3(0.15, 0.48, 0.02), red, MeshKit.FRONT, 2.75)
	# the helipad on the roof: a dark pad, a yellow ring and the white H
	var ry := bh + 0.08
	var px := minf(0.5, bw * 0.5 - 1.0)
	mk.shadow = false
	mk.box_faces(Vector3(px, ry + 0.01, bz), Vector3(1.6, 0.02, minf(1.6, bd)), Color(0.3, 0.32, 0.34), MeshKit.TOP)
	var ring := 0.62
	for k in 8:
		var a0 := k * TAU / 8.0
		var a1 := (k + 1) * TAU / 8.0
		var o := Vector3(px, ry + 0.022, bz)
		mk.quad(o + Vector3(cos(a0), 0, sin(a0)) * ring, o + Vector3(cos(a1), 0, sin(a1)) * ring, o + Vector3(cos(a1), 0, sin(a1)) * (ring - 0.07), o + Vector3(cos(a0), 0, sin(a0)) * (ring - 0.07), Vector3.UP, Color(0.95, 0.8, 0.25))
	for sx: float in [-1.0, 1.0]:
		mk.box_faces(Vector3(px + sx * 0.17, ry + 0.024, bz), Vector3(0.08, 0.004, 0.5), white, MeshKit.TOP)
	mk.box_faces(Vector3(px, ry + 0.026, bz), Vector3(0.34, 0.004, 0.08), white, MeshKit.TOP)
	mk.shadow = true
	mk.box_faces(Vector3(-bw * 0.5 + 0.6, ry + 0.18, bz), Vector3(0.8, 0.36, bd * 0.6), Color(0.72, 0.74, 0.74), all)
	# the low emergency wing out towards the street
	var ww := bw * 0.5
	var wd := minf(-zf - 0.85, 1.3)
	var wx := -bw * 0.5 + ww * 0.5 + 0.1
	var wz := zf + wd * 0.5
	var wh := HouseGen.FH + 0.05
	mk.box_faces(Vector3(wx, wh * 0.5, wz), Vector3(ww, wh, wd), white, MeshKit.FRONT | MeshKit.LEFT | MeshKit.RIGHT)
	mk.box_faces(Vector3(wx, wh + 0.03, wz), Vector3(ww + 0.04, 0.06, wd + 0.04), Color(0.82, 0.84, 0.84), all)
	mk.box_faces(Vector3(wx, wh - 0.06, wz + wd * 0.5 + 0.02), Vector3(ww, 0.12, 0.02), green, MeshKit.FRONT)
	mk.box_faces(Vector3(wx, 0.3, wz + wd * 0.5 + 0.012), Vector3(ww - 0.4, 0.46, 0.02), Palette.GLASS_LIGHT, MeshKit.FRONT, 1.0)
	# the canopy over the ambulance bay beside it, on two posts
	var cx := wx + ww * 0.5 + 0.6
	mk.box_faces(Vector3(cx, 0.6, wz), Vector3(1.1, 0.05, wd), green, all)
	for sz: float in [-1.0, 1.0]:
		mk.pole(Vector3(cx + 0.5, 0.0, wz + sz * (wd * 0.5 - 0.05)), 0.025, 0.58, 4, Color(0.85, 0.86, 0.86))
	_vehicle(mk, Vector3(cx, 0.0, wz + 0.1), 0.0, Color(0.97, 0.88, 0.3), green, Color(0.35, 0.55, 1.0), 0.95, 0.36)
	for sx: float in [-1.0, 1.0]:
		if rng.randf() < 0.7:
			_tree(mk, rng, Vector3(sx * (l.width * 0.5 - 0.35), 0.0, -0.4))
