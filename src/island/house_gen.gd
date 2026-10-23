class_name HouseGen
extends RefCounted
## One house on one lot of the new island, in the town's painted-model style.
## Dense lots get tall terraced houses wall to wall, each its own colour; thin
## lots get detached houses with side windows, front hedges and a tree out back.
## On a slope the house stands on a stone plinth. Built in world space, as the
## raw arrays the town merges into one mesh per patch.
##
## Every quarter of the island has its own style kit: whitewashed harbour
## houses by the sea, pastel terraces, red-brick streets, cream stone under
## slate, terracotta south with shutters, painted nordic timber. The kit picks
## the colours, the materials, the roofs and the details on the facades.

const FH := 0.62
const STONE := Color(0.74, 0.71, 0.66)
const TERRACE := [Color("f3c6a5"), Color("c9dbe9"), Color("f6dca7"), Color("cfe0c3"), Color("e7d3ec"), Color("fbf1df"), Color("f2b8a8"), Color("b9d4c8"), Color("fff1c4")]
const DOORS := [Color("8b5a44"), Color("4a7bb5"), Color("3d8a6a"), Color("b04a4a"), Color("2f3a48"), Color("e0b44a")]
const IRON := Color(0.22, 0.24, 0.27)

enum { HARBOUR, PASTEL, BRICK, STONE_SLATE, SOUTH, NORDIC }
const KIT_NAMES := ["harbour", "pastel", "brick", "stone", "south", "nordic"]
# roof weights: [ridge along the street, gable end to the street, hip, flat]
const KITS := [
	{
		"walls": [Color("ffffff"), Color("f8f6f0"), Color("e3f0f7"), Color("fdf3dc"), Color("f1f6f8")],
		"roofs": [Color("3f7cc4"), Color("4f8fb0"), Color("e0805e"), Color("3aa6a0")],
		"doors": [Color("3f7cc4"), Color("3aa6a0"), Color("2f5d8a"), Color("e0b44a")],
		"shutters": [Color("3f7cc4"), Color("3aa6a0"), Color("5fa8d3")], "shutter": 0.55,
		"brick": 0.0, "siding": 0.05, "pitch": Vector2(0.45, 0.7), "roof": [0.45, 0.25, 0.1, 0.2],
		"chimney": 0.3, "dormer": 0.1, "balcony": 0.2, "boxes": 0.35, "trim": Color(0.98, 0.98, 0.97),
	},
	{
		"walls": TERRACE,
		"roofs": [Color("d9694f"), Color("b9503f"), Color("8b5a44"), Color("5d6b84"), Color("c9774b"), Color("6f8a5b")],
		"doors": DOORS,
		"shutters": [Color(0.97, 0.97, 0.95)], "shutter": 0.12,
		"brick": 0.12, "siding": 0.1, "pitch": Vector2(0.55, 0.95), "roof": [0.6, 0.2, 0.15, 0.05],
		"chimney": 0.6, "dormer": 0.3, "balcony": 0.15, "boxes": 0.3, "trim": null,
	},
	{
		"walls": [Color("c2684f"), Color("b55d4a"), Color("d48a6a"), Color("a9574a"), Color("bf7357")],
		"roofs": [Color("5d4a42"), Color("8b5a44"), Color("b9503f"), Color("a4553f"), Color("4b5262")],
		"doors": [Color("2f3a48"), Color("3d6a4a"), Color("6a2f2f"), Color("1f2a38")],
		"shutters": [], "shutter": 0.0,
		"brick": 0.9, "siding": 0.0, "pitch": Vector2(0.7, 1.0), "roof": [0.55, 0.35, 0.1, 0.0],
		"chimney": 0.9, "dormer": 0.45, "balcony": 0.05, "boxes": 0.15, "trim": Color(0.95, 0.92, 0.86),
	},
	{
		"walls": [Color("efe4d2"), Color("f3e6cc"), Color("fbf1df"), Color("e8d8bc"), Color("f6ead6")],
		"roofs": [Color("5d6b84"), Color("6a7a94"), Color("4b5262"), Color("7a8a6a")],
		"doors": [Color("3d6a5a"), Color("2f3a48"), Color("7a3b3b"), Color("4a6a8a")],
		"shutters": [Color("7f9a8a"), Color("8a9aa8")], "shutter": 0.25,
		"brick": 0.0, "siding": 0.0, "pitch": Vector2(0.8, 1.1), "roof": [0.5, 0.15, 0.35, 0.0],
		"chimney": 0.75, "dormer": 0.5, "balcony": 0.1, "boxes": 0.2, "trim": Color(0.96, 0.94, 0.9),
	},
	{
		"walls": [Color("f2d4a8"), Color("efc49a"), Color("f6e3c4"), Color("e9b88f"), Color("f4dcb8"), Color("e8a98a")],
		"roofs": [Color("c9774b"), Color("d9694f"), Color("b9503f"), Color("d08850")],
		"doors": [Color("6f8f4a"), Color("4a7bb5"), Color("8b5a44"), Color("3d8a6a")],
		"shutters": [Color("6f9a5a"), Color("4f86b5"), Color("3d8a6a"), Color("8a6a3a")], "shutter": 0.75,
		"brick": 0.0, "siding": 0.0, "pitch": Vector2(0.35, 0.5), "roof": [0.4, 0.1, 0.4, 0.1],
		"chimney": 0.2, "dormer": 0.0, "balcony": 0.4, "boxes": 0.6, "trim": Color(0.98, 0.95, 0.88),
	},
	{
		"walls": [Color("b9503f"), Color("e0b44a"), Color("4f7f9e"), Color("e9e2d0"), Color("6f8f6a"), Color("c96a4a")],
		"roofs": [Color("3a3f47"), Color("5b4a42"), Color("2f3a48"), Color("4b5a4a")],
		"doors": [Color("2f3a48"), Color("e9e2d0"), Color("3a3f47")],
		"shutters": [], "shutter": 0.0,
		"brick": 0.0, "siding": 0.9, "pitch": Vector2(1.0, 1.3), "roof": [0.5, 0.5, 0.0, 0.0],
		"chimney": 0.5, "dormer": 0.2, "balcony": 0.05, "boxes": 0.1, "trim": Color(0.97, 0.96, 0.93),
	},
]

static var _quarters: FastNoiseLite
static var _quarters_seed := -1


## The style kit of the quarter at p: harbour by the sea, otherwise the quarter's own.
static func kit_at(land: Land, p: Vector2) -> int:
	var sd := land._noise.seed
	if _quarters == null or _quarters_seed != sd:
		_quarters = FastNoiseLite.new()
		_quarters.noise_type = FastNoiseLite.TYPE_CELLULAR
		_quarters.cellular_return_type = FastNoiseLite.RETURN_CELL_VALUE
		_quarters.frequency = 1.0 / 36.0
		_quarters.seed = sd + 77
		_quarters_seed = sd
	for k in 8:
		var q := p + Vector2.from_angle(k * TAU / 8.0) * 9.0
		if land.height_at(q.x, q.y) < 0.0:
			return HARBOUR
	var v := _quarters.get_noise_2d(p.x, p.y) * 0.5 + 0.5
	return 1 + clampi(int(v * 5.0), 0, 4)


static func build(l: Town.Lot, land: Land, street_y: float, seed_value: int, main := false) -> Array:
	var mk := MeshKit.new(seed_value)
	mk.quiet_sprites = true
	var rng := mk.rng
	var kit: int = l.kit
	var K: Dictionary = KITS[kit]
	var dense := l.dense > 0.6
	var right := Vector2(cos(l.yaw), -sin(l.yaw))
	var fwd := Vector2(sin(l.yaw), cos(l.yaw))
	var setback := lerpf(0.0, 0.12, rng.randf()) if dense else lerpf(0.3, 0.8, rng.randf())
	var hd := clampf(l.depth * (lerpf(0.5, 0.68, rng.randf()) if dense else lerpf(0.36, 0.52, rng.randf())), 1.3, 2.8)
	var gap := 0.0 if dense else lerpf(0.25, 0.5, rng.randf())
	var hw := maxf(l.width - gap * 2.0, 1.2)
	var cz := -setback - hd * 0.5
	# the ground under the house, from its four corners
	var lo := INF
	var hi := -INF
	for c in [Vector2(-hw * 0.5, -setback), Vector2(hw * 0.5, -setback), Vector2(hw * 0.5, -setback - hd), Vector2(-hw * 0.5, -setback - hd)]:
		var p: Vector2 = l.origin + right * c.x + fwd * c.y
		var g := land.height_at(p.x, p.y)
		lo = minf(lo, g)
		hi = maxf(hi, g)
	var y0 := maxf(street_y, (lo + hi) * 0.5 + 0.04)
	# brick and stone terraces are built as matching rows down each side of a street
	var row := RandomNumberGenerator.new()
	row.seed = hash([l.street, int(l.side), kit])
	var rowed := dense and (kit == BRICK or kit == STONE_SLATE) and rng.randf() < 0.85
	var floors: int
	if dense:
		var g := row if rowed else rng
		floors = 2 + int(g.randf() < l.dense - 0.35) + int(g.randf() < l.dense - 0.75)
	else:
		floors = 1 + int(rng.randf() < 0.45)
	# a busy main street keeps shops on the ground floor
	var shop := main and dense and floors >= 2 and rng.randf() < 0.6
	l.floors = floors
	l.shop = shop
	var hgt := floors * FH + 0.06
	var walls: Array = K.walls
	var wall: Color = walls[rng.randi() % walls.size()]
	var roof: Color = K.roofs[(row if rowed else rng).randi() % K.roofs.size()]
	var trim: Color = K.trim if K.trim != null else wall.lightened(0.45)
	var we := 0.0
	var r := rng.randf()
	if r < K.brick:
		if kit != BRICK:
			wall = Palette.BRICK[rng.randi() % 3]
		we = MeshKit.BRICKS
		trim = Color(0.95, 0.93, 0.88)
	elif r < K.brick + K.siding and (not dense or kit == NORDIC):
		we = MeshKit.SIDING
		if kit == NORDIC:
			trim = Color(0.97, 0.96, 0.93)
	var shutters: Color = K.shutters[rng.randi() % K.shutters.size()] if rng.randf() < K.shutter else Color(0, 0, 0, 0)
	var boxes: bool = rng.randf() < K.boxes
	var door: Color = K.doors[rng.randi() % K.doors.size()]

	mk.push_at(Vector3(l.origin.x, y0, l.origin.y), l.yaw)
	# stone plinth where the ground falls away
	if y0 - lo > 0.04:
		var bottom := lo - y0 - 0.12
		mk.box(Vector3(0, bottom * 0.5 + 0.02, cz), Vector3(hw + 0.04, 0.04 - bottom, hd + 0.04), STONE.darkened(0.08 * rng.randf()))
	mk.push_at(Vector3(0, 0, cz))
	# the roof covers the top
	mk.box_faces(Vector3(0, hgt * 0.5, 0), Vector3(hw, hgt, hd), wall, MeshKit.FRONT | MeshKit.BACK | MeshKit.LEFT | MeshKit.RIGHT, we)
	mk.bands(FH + 0.03, hw, hd, FH, floors - 1, 0.035, trim)
	if we == MeshKit.SIDING:
		# painted corner boards
		for cx: float in [-1.0, 1.0]:
			mk.box_faces(Vector3(cx * (hw * 0.5 - 0.02), hgt * 0.5, hd * 0.5 - 0.02), Vector3(0.07, hgt, 0.07), trim,
				MeshKit.FRONT | (MeshKit.RIGHT if cx > 0.0 else MeshKit.LEFT))
	elif kit == STONE_SLATE and we == 0.0 and not dense:
		# dressed stone quoins up the front corners
		var qc := wall.darkened(0.1)
		for cx: float in [-1.0, 1.0]:
			var y := 0.0
			while y < hgt - 0.1:
				mk.box_faces(Vector3(cx * (hw * 0.5 - 0.07), y + 0.07, hd * 0.5 - 0.068), Vector3(0.16, 0.13, 0.16), qc,
					MeshKit.FRONT | (MeshKit.RIGHT if cx > 0.0 else MeshKit.LEFT))
				y += 0.26
	var count := maxi(1, int(hw / 0.55))
	var side_count := maxi(1, int(hd / 0.62))
	var door_x := 0.0 if shop else ((hw * 0.5 - 0.32) * (1.0 if rng.randf() < 0.5 else -1.0) if count > 1 else 0.0)
	var front := hd * 0.5
	for fl in floors:
		var y := fl * FH + FH * 0.55
		if fl == 0:
			if shop:
				_shopfront(mk, rng, hw, front, wall)
			elif count > 1:
				# the door takes one bay of the ground floor
				var len := hw - 0.6
				mk.window_row(Vector3(-signf(door_x) * 0.3, y, front), Vector3.BACK, len, count - 1, 0.24, 0.32, Palette.GLASS, true)
				if shutters.a > 0.0:
					_shutters(mk, -signf(door_x) * 0.3, y, front, len, count - 1, shutters)
		else:
			mk.window_row(Vector3(0, y, front), Vector3.BACK, hw, count, 0.24, 0.32, Palette.GLASS, true)
			if shutters.a > 0.0:
				_shutters(mk, 0.0, y, front, hw, count, shutters)
			if boxes and fl == 1:
				_window_boxes(mk, rng, y, front, hw, count)
		mk.window_row(Vector3(0, y, -hd * 0.5), Vector3.FORWARD, hw, count, 0.24, 0.32, Palette.GLASS, true)
		if not dense and hd > 1.0:
			for sx: float in [-1.0, 1.0]:
				mk.window_row(Vector3(sx * hw * 0.5, y, 0), Vector3.RIGHT * sx, hd, side_count, 0.24, 0.32, Palette.GLASS, true)
	# a little iron balcony under one upper window
	if floors >= 2 and rng.randf() < K.balcony and not boxes:
		var fl := 1 + rng.randi() % (floors - 1)
		var bx := -hw * 0.5 + (rng.randi() % count + 0.5) * hw / count
		var by := fl * FH + 0.08
		mk.box_faces(Vector3(bx, by, front + 0.12), Vector3(0.46, 0.04, 0.24), STONE, MeshKit.TOP | MeshKit.FRONT | MeshKit.LEFT | MeshKit.RIGHT)
		mk.box_faces(Vector3(bx, by + 0.11, front + 0.235), Vector3(0.46, 0.18, 0.012), IRON, MeshKit.FRONT | MeshKit.BACK)
	# front door with a step, and on some a little canopy
	if not shop:
		mk.box_faces(Vector3(door_x, 0.27, front + 0.015), Vector3(0.3, 0.5, 0.03), door, MeshKit.FRONT | MeshKit.LEFT | MeshKit.RIGHT | MeshKit.TOP)
		mk.box_faces(Vector3(door_x, -0.02, front + 0.1), Vector3(0.44, 0.07, 0.2), STONE, MeshKit.FRONT | MeshKit.TOP | MeshKit.LEFT | MeshKit.RIGHT)
		if rng.randf() < 0.4:
			mk.box_faces(Vector3(door_x, 0.58, front + 0.1), Vector3(0.5, 0.04, 0.2), trim, MeshKit.FRONT | MeshKit.TOP | MeshKit.LEFT | MeshKit.RIGHT)
	_roof(mk, rng, K, hw, hd, hgt, roof, wall, dense)
	mk.pop()
	if not dense:
		_garden(mk, rng, l, hw, hd, setback, door_x, land, y0)
	elif l.depth - setback - hd > 1.4 and rng.randf() < 0.5:
		var tz := -setback - hd - (l.depth - setback - hd) * 0.5
		_tree(mk, rng, Vector3(lerpf(-0.4, 0.4, rng.randf()) * l.width, 0.0, tz), land, l, y0)
	# a street lamp on the pavement every few houses
	if posmod(seed_value, 3) == 0:
		CivicGen._lamp(mk, Vector3(l.width * 0.5, street_y - y0, 0.36))
	mk.pop()
	return [mk.verts, mk.norms, mk.cols, mk.uvs, mk.dverts, mk.dnorms, mk.dcols, mk.duvs, mk.sverts, mk.snorms,
		mk.bverts, mk.bcols, mk.buvs, mk.bradius, mk.qverts, mk.qcols, mk.quvs, mk.qradius]


## A shop on the ground floor: display windows either side of the door, a
## striped awning and a sign board, lit up at night.
static func _shopfront(mk: MeshKit, rng: RandomNumberGenerator, hw: float, front: float, wall: Color) -> void:
	var awn: Color = Palette.AWNINGS[rng.randi() % Palette.AWNINGS.size()]
	var z := front + 0.012
	# a painted frame round the whole front
	mk.box_faces(Vector3(0, 0.29, front + 0.01), Vector3(hw - 0.1, 0.5, 0.02), awn.darkened(0.4), MeshKit.FRONT)
	for s: float in [-1.0, 1.0]:
		mk.window(Vector3(s * hw * 0.27, 0.32, z), Vector3.BACK, hw * 0.34, 0.36, Palette.GLASS_LIGHT, Color(0, 0, 0, 0), false)
	mk.box_faces(Vector3(0, 0.24, front + 0.02), Vector3(0.26, 0.44, 0.02), Color(0.95, 0.93, 0.88), MeshKit.FRONT)
	mk.window(Vector3(0, 0.27, front + 0.032), Vector3.BACK, 0.16, 0.32, Palette.GLASS_LIGHT, Color(0, 0, 0, 0), true)
	# striped awning, tilted out over the pavement
	var stripes := 5
	var aw := hw - 0.14
	for k in stripes:
		var col := awn if k % 2 == 0 else Color(0.98, 0.97, 0.94)
		var sx := -aw * 0.5 + (k + 0.5) * aw / stripes
		mk.push(Transform3D(Basis(Vector3.RIGHT, 0.45), Vector3(sx, 0.6, front + 0.02)))
		mk.box_faces(Vector3(0, 0, 0.17), Vector3(aw / stripes, 0.025, 0.34), col, MeshKit.TOP | MeshKit.FRONT | (MeshKit.LEFT if k == 0 else 0) | (MeshKit.RIGHT if k == stripes - 1 else 0))
		mk.pop()
	# sign board above the awning
	mk.box_faces(Vector3(0, 0.74, front + 0.025), Vector3(hw * 0.62, 0.13, 0.05), wall.lightened(0.6), MeshKit.FRONT | MeshKit.TOP)
	mk.box_faces(Vector3(0, 0.74, front + 0.051), Vector3(hw * 0.46, 0.05, 0.004), awn.darkened(0.25), MeshKit.FRONT, 2.0)


## Painted shutters either side of each window in a row.
static func _shutters(mk: MeshKit, cx: float, y: float, front: float, length: float, count: int, col: Color) -> void:
	var cell := length / count
	for k in count:
		var x := cx - length * 0.5 + (k + 0.5) * cell
		for s: float in [-1.0, 1.0]:
			mk.box_faces(Vector3(x + s * 0.205, y - 0.02, front + 0.008), Vector3(0.08, 0.36, 0.012), col, MeshKit.FRONT)


## Flower boxes under the windows of the first floor.
static func _window_boxes(mk: MeshKit, rng: RandomNumberGenerator, y: float, front: float, hw: float, count: int) -> void:
	var cell := hw / count
	for k in count:
		var x := -hw * 0.5 + (k + 0.5) * cell
		mk.box_faces(Vector3(x, y - 0.27, front + 0.04), Vector3(0.3, 0.06, 0.08), Color(0.55, 0.38, 0.28), MeshKit.FRONT | MeshKit.TOP)
		mk.blob(Vector3(x, y - 0.22, front + 0.05), Vector3(0.15, 0.05, 0.05), Palette.FLOWERS[rng.randi() % Palette.FLOWERS.size()], 0.02)


static func _roof(mk: MeshKit, rng: RandomNumberGenerator, K: Dictionary, hw: float, hd: float, hgt: float, roof: Color, wall: Color, dense: bool) -> void:
	var weights: Array = K.roof
	var pick: float = rng.randf() * (weights[0] + weights[1] + weights[2] + weights[3])
	var kind := 0
	while kind < 3 and pick > weights[kind]:
		pick -= weights[kind]
		kind += 1
	# detached houses rarely have flat roofs; terraces never turn their gables to the street
	if kind == 3 and not dense:
		kind = 2
	if kind == 1 and dense:
		kind = 0
	var pitch := lerpf(K.pitch.x, K.pitch.y, rng.randf())
	if kind == 3:
		# flat roof behind a parapet
		mk.ledge(Vector3(0, hgt + 0.06, 0), Vector3(hw + 0.04, 0.12, hd + 0.04), 0.02, wall.lightened(0.35))
		mk.box_faces(Vector3(0, hgt + 0.1, 0), Vector3(hw - 0.1, 0.02, hd - 0.1), Color(0.55, 0.55, 0.57), MeshKit.TOP)
		return
	var rh := hd * 0.5 * pitch
	if kind == 0:
		# ridge along the street, eaves to the front
		mk.gable_roof(Vector3(0, hgt, 0), hw, hd, rh, 0.07, roof, wall)
		if rh > 0.42 and hw > 1.4 and rng.randf() < K.dormer:
			var n := 1 if hw < 2.2 else 2
			for k in n:
				_dormer(mk, (k + 0.5 - n * 0.5) * hw / n, hd, hgt, rh, roof, wall)
	elif kind == 1:
		# gable end to the street
		rh = hw * 0.5 * pitch
		mk.push_at(Vector3.ZERO, PI * 0.5)
		mk.gable_roof(Vector3(0, hgt, 0), hd, hw, rh, 0.07, roof, wall)
		mk.pop()
	else:
		rh = minf(hw, hd) * 0.5 * pitch
		mk.hip_roof(Vector3(0, hgt, 0), hw, hd, rh, 0.08, roof)
	if rng.randf() < K.chimney:
		var cx := hw * lerpf(0.2, 0.38, rng.randf()) * (1.0 if rng.randf() < 0.5 else -1.0)
		mk.box(Vector3(cx, hgt + rh * 0.6, -hd * 0.12), Vector3(0.16, rh + 0.2, 0.16), Color(0.62, 0.42, 0.36))


## A dormer window standing out of the front slope of the roof.
static func _dormer(mk: MeshKit, x: float, hd: float, hgt: float, rh: float, roof: Color, wall: Color) -> void:
	var zf := hd * 0.22
	# where the roof is at the dormer's front
	var base := hgt + rh * (1.0 - zf / (hd * 0.5))
	mk.box_faces(Vector3(x, base + 0.1, zf - 0.22), Vector3(0.4, 0.34, 0.44), wall, MeshKit.FRONT | MeshKit.LEFT | MeshKit.RIGHT)
	mk.window(Vector3(x, base + 0.12, zf), Vector3.BACK, 0.18, 0.18, Palette.GLASS, Color(1, 1, 1, 1))
	mk.push_at(Vector3(x, base + 0.27, zf - 0.2), PI * 0.5)
	mk.gable_roof(Vector3.ZERO, 0.46, 0.4, 0.15, 0.04, roof, wall, 0.05)
	mk.pop()


static func _garden(mk: MeshKit, rng: RandomNumberGenerator, l: Town.Lot, hw: float, hd: float, setback: float, door_x: float, land: Land, y0: float) -> void:
	# a low hedge or picket fence along the front, open at the path
	if setback > 0.35:
		var hedge := rng.randf() < 0.6
		var col: Color = Palette.LEAF[rng.randi() % Palette.LEAF.size()].darkened(0.15) if hedge else Color(0.97, 0.97, 0.95)
		var hh := 0.16 if hedge else 0.12
		var z := -0.08
		for sx: float in [-1.0, 1.0]:
			var x0 := door_x + sx * 0.25
			var x1 := sx * l.width * 0.5 - sx * 0.05
			if absf(x1 - x0) < 0.2 or signf(x1 - x0) != sx:
				continue
			# too low to throw a shadow worth drawing
			mk.shadow = false
			mk.box_faces(Vector3((x0 + x1) * 0.5, hh * 0.5, z), Vector3(absf(x1 - x0), hh, 0.1 if hedge else 0.04), col, MeshKit.TOP | MeshKit.FRONT | MeshKit.BACK)
			mk.shadow = true
		mk.box_faces(Vector3(door_x, 0.01, -setback * 0.5), Vector3(0.28, 0.02, setback), Color(0.84, 0.8, 0.74), MeshKit.TOP)
		for k in 2:
			mk.blob(Vector3(door_x + (0.5 + 0.3 * k) * (1.0 if k == 0 else -1.0), 0.1, -setback * 0.6), Vector3(0.1, 0.08, 0.1), Palette.FLOWERS[rng.randi() % Palette.FLOWERS.size()], 0.03)
	var back := l.depth - setback - hd
	if back > 1.0:
		_tree(mk, rng, Vector3(lerpf(-0.3, 0.3, rng.randf()) * l.width, 0.0, -setback - hd - back * 0.55), land, l, y0)


## A garden tree, standing on the real ground wherever the garden slopes to.
static func _tree(mk: MeshKit, rng: RandomNumberGenerator, at: Vector3, land: Land, l: Town.Lot, y0: float) -> void:
	var p := l.origin + Vector2(cos(l.yaw), -sin(l.yaw)) * at.x + Vector2(sin(l.yaw), cos(l.yaw)) * at.z
	at.y = land.height_at(p.x, p.y) - y0
	var s := lerpf(0.75, 1.15, rng.randf())
	mk.pole(at, 0.05 * s, 0.5 * s, 5, Color(0.45, 0.33, 0.24))
	var leaf: Color = Palette.LEAF[rng.randi() % Palette.LEAF.size()]
	mk.blob(at + Vector3(0, 0.75 * s, 0), Vector3(0.42, 0.4, 0.42) * s, leaf, 0.1)
	mk.blob(at + Vector3(0.18 * s, 0.98 * s, 0.05), Vector3(0.28, 0.26, 0.28) * s, leaf.lightened(0.08), 0.1)
