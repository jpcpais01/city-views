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
## pale stone, concrete and dark cladding for office blocks
const OFFICE_WALLS := [Color("dedad2"), Color("c9ced1"), Color("ebe5d8"), Color("97a3ab"), Color("b8b2a6")]
const OFFICE_GLASS := Color(0.38, 0.5, 0.6)
const APARTMENT_WALLS := [Color("e8b07a"), Color("d98b6a"), Color("efd29a"), Color("c9d3b0"), Color("e6c2b0"), Color("b8c9cf"), Color("f0e2c8"), Color("cf7f5f")]
## a tower's look: [wall tones, glass, window width, offices, brick]
const TOWER_SCHEMES := [
	[[Color("4f6f86"), Color("3f5a6e"), Color("5a7d8c"), Color("344b5c")], Color(0.24, 0.38, 0.5), 0.56, true, false],
	[[Color("5e8c8c"), Color("4c7a7d"), Color("6b9a92")], Color(0.26, 0.45, 0.46), 0.56, true, false],
	[[Color("f2f1ec"), Color("e8e6df"), Color("dfe3e4")], OFFICE_GLASS, 0.42, true, false],
	[[Color("d6c3a5"), Color("cbb595"), Color("e0d1b6")], Color(0.32, 0.42, 0.5), 0.34, false, false],
	[[Color("a65a43"), Color("9a4f3c"), Color("b26a4f")], Palette.GLASS, 0.28, false, true],
]

enum { HARBOUR, PASTEL, BRICK, STONE_SLATE, SOUTH, NORDIC }
## the districts painted with the Grow brush (Land.USES)
enum { HOMES, SHOPS, OFFICES, INDUSTRY }
const SHED_WALLS := [Color("a9b2b8"), Color("8e9aa6"), Color("c9c2b0"), Color("b4614a"), Color("7f97a8"), Color("d6d0c2")]
const SHED_ROOFS := [Color("6f767c"), Color("5d6872"), Color("8a8f92"), Color("4f5a63")]
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
	l.use = "home"
	if l.district == INDUSTRY:
		return build_industry(l, land, street_y, seed_value)
	if l.stage >= 5 or l.district == OFFICES:
		# apartments, towers and offices are blocks, even on a plot of their own
		return build_block([l], land, street_y, seed_value, main)
	# a house grows through stages: cottage, two-floor house, terrace, taller terrace, tall terrace
	var dense := l.stage >= 2
	var right := Vector2(cos(l.yaw), -sin(l.yaw))
	var fwd := Vector2(sin(l.yaw), cos(l.yaw))
	var setback := lerpf(0.0, 0.12, rng.randf()) if dense else lerpf(0.3, 0.8, rng.randf())
	var hd := clampf(l.depth * (lerpf(0.5, 0.68, rng.randf()) if dense else lerpf(0.36, 0.52, rng.randf())), 1.3, 2.8)
	var gap := 0.0 if dense else lerpf(0.25, 0.5, rng.randf())
	var hw := maxf(l.width - gap * 2.0, 1.2)
	# fit the house to its plot: never deeper than the plot is behind it. A
	# detached house slides over to the deeper side where the plot tapers; a
	# terrace keeps its full front and squeezes its back to the plot's shape
	var hx := 0.0
	var fit := l.room(-hw * 0.5, hw * 0.5) - setback - 0.45
	if not dense and fit < hd:
		for cw: float in [hw, hw * 0.8, hw * 0.65]:
			for sx: float in [-1.0, 1.0]:
				var x := sx * (l.width * 0.5 - gap - cw * 0.5)
				var r := l.room(x - cw * 0.5, x + cw * 0.5) - setback - 0.45
				if cw >= 1.2 and minf(r, hd) * cw > minf(fit, hd) * hw + 0.05:
					fit = r
					hw = cw
					hx = x
	var squeeze := PackedVector2Array()
	if dense and l.room(-hw * 0.5, hw * 0.5) - setback - 0.1 < hd:
		squeeze = _squeezed(l, hw, hd, setback)
	elif not dense:
		hd = maxf(minf(hd, fit), 1.0)
	var cz := -setback - hd * 0.5
	# the ground under the house, from its four corners
	var lo := INF
	var hi := -INF
	for c in [Vector2(hx - hw * 0.5, -setback), Vector2(hx + hw * 0.5, -setback), Vector2(hx + hw * 0.5, -setback - hd), Vector2(hx - hw * 0.5, -setback - hd)]:
		var p: Vector2 = l.origin + right * c.x + fwd * c.y
		var g := land.height_at(p.x, p.y)
		lo = minf(lo, g)
		hi = maxf(hi, g)
	# the floor sits just above the ground the plot was levelled to (or the
	# ground under it, on a plot never levelled), never below the street
	var y0 := maxf(street_y, (l.level if l.level > -INF else (lo + hi) * 0.5) + 0.04)
	# the house's own footprint is dug or banked up to just under its floor,
	# easing out a little round it (never out over the pavement in front), so
	# the stone base below only shows where the plot drops away at its edges
	var foot := PackedVector2Array()
	for c in [Vector2(hx - hw * 0.5 - 0.3, -setback + 0.02), Vector2(hx + hw * 0.5 + 0.3, -setback + 0.02), Vector2(hx + hw * 0.5 + 0.3, -setback - hd - 0.3), Vector2(hx - hw * 0.5 - 0.3, -setback - hd - 0.3)]:
		foot.append(l.origin + right * c.x + fwd * c.y)
	var o := l.origin
	land.pad(foot, y0 - 0.04, 1.0, func(p: Vector2) -> bool: return (p - o).dot(fwd) > -0.05)
	lo = INF
	for c in [Vector2(hx - hw * 0.5, -setback), Vector2(hx + hw * 0.5, -setback), Vector2(hx + hw * 0.5, -setback - hd), Vector2(hx - hw * 0.5, -setback - hd)]:
		var p: Vector2 = l.origin + right * c.x + fwd * c.y
		lo = minf(lo, land.height_at(p.x, p.y))
	l.plinth = y0 - lo
	# brick and stone terraces are built as matching rows down each side of a street
	var row := RandomNumberGenerator.new()
	row.seed = hash([l.street, int(l.side), kit])
	var rowed := dense and (kit == BRICK or kit == STONE_SLATE) and rng.randf() < 0.85
	var floors: int = [1, 2, 2, 3, 4][clampi(l.stage, 0, 4)]
	if l.stage == 2 and (row if rowed else rng).randf() < 0.35:
		floors = 3
	# a busy main street keeps shops on the ground floor, and in a shopping
	# district every house has one
	var shop := (main and dense and floors >= 2 and rng.randf() < 0.6) or l.district == SHOPS
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
		# its shadow falls inside the house's own
		mk.shadow = false
		mk.box(Vector3(hx, bottom * 0.5 + 0.02, cz), Vector3(hw + 0.04, 0.04 - bottom, hd + 0.04), STONE.darkened(0.08 * rng.randf()))
		mk.shadow = true
	mk.push_at(Vector3(hx, 0, cz))
	if squeeze.is_empty():
		# the roof covers the top, and casts the top's shadow
		mk.shadow = false
		mk.box_faces(Vector3(0, hgt * 0.5, 0), Vector3(hw, hgt, hd), wall, MeshKit.FRONT | MeshKit.BACK | MeshKit.LEFT | MeshKit.RIGHT, we)
		mk.shadow = true
		mk.shadow_faces(Vector3(0, hgt * 0.5, 0), Vector3(hw, hgt, hd), MeshKit.FRONT | MeshKit.BACK | MeshKit.LEFT | MeshKit.RIGHT)
		mk.bands(FH + 0.03, hw, hd, FH, floors - 1, 0.035, trim)
	else:
		_prism(mk, squeeze, hgt, wall, we, floors, trim)
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
				l.trade = _shopfront(mk, rng, hw, front, wall)
			elif count > 1:
				# the door takes one bay of the ground floor
				var len := hw - 0.6
				mk.window_row(Vector3(-signf(door_x) * 0.3, y, front), Vector3.BACK, len, count - 1, 0.24, 0.32, Palette.GLASS, true)
				if shutters.a > 0.0:
					_shutters(mk, -signf(door_x) * 0.3, y, front, len, count - 1, shutters)
		else:
			if shutters.a > 0.0:
				_shutters(mk, 0.0, y, front, hw, count, shutters)
			if boxes and fl == 1:
				_window_boxes(mk, rng, y, front, hw, count)
	# the windows of every upper floor at the front, and every floor behind and at the sides
	mk.window_grid(Vector3(0, FH, front), Vector3.BACK, hw, count, floors - 1, 0.24, Palette.GLASS)
	if squeeze.is_empty():
		mk.window_grid(Vector3(0, 0, -hd * 0.5), Vector3.FORWARD, hw, count, floors, 0.24, Palette.GLASS, 1)
	if not dense and hd > 1.0:
		for sx: float in [-1.0, 1.0]:
			mk.window_grid(Vector3(sx * hw * 0.5, 0, 0), Vector3.RIGHT * sx, hd, side_count, floors, 0.24, Palette.GLASS, 1)
	elif l.corner != 0.0 and squeeze.is_empty() and hd > 1.0:
		# on a corner the end wall looks onto the other street: windows there too
		mk.window_grid(Vector3(l.corner * hw * 0.5, 0, 0), Vector3.RIGHT * l.corner, hd, side_count, floors, 0.24, Palette.GLASS)
	# a little iron balcony under one upper window
	if floors >= 2 and rng.randf() < K.balcony and not boxes:
		var fl := 1 + rng.randi() % (floors - 1)
		var bx := -hw * 0.5 + (rng.randi() % count + 0.5) * hw / count
		var by := fl * FH + 0.08
		mk.box_faces(Vector3(bx, by, front + 0.12), Vector3(0.46, 0.04, 0.24), STONE, MeshKit.TOP | MeshKit.FRONT)
		mk.box_faces(Vector3(bx, by + 0.11, front + 0.235), Vector3(0.46, 0.18, 0.012), IRON, MeshKit.FRONT)
	# front door with a step, and on some a little canopy
	if not shop:
		# (their sides are too shallow to ever show)
		mk.box_faces(Vector3(door_x, 0.27, front + 0.015), Vector3(0.3, 0.5, 0.03), door, MeshKit.FRONT)
		mk.box_faces(Vector3(door_x, -0.02, front + 0.1), Vector3(0.44, 0.07, 0.2), STONE, MeshKit.FRONT | MeshKit.TOP)
		if rng.randf() < 0.4:
			mk.box_faces(Vector3(door_x, 0.58, front + 0.1), Vector3(0.5, 0.04, 0.2), trim, MeshKit.FRONT | MeshKit.TOP)
	if squeeze.is_empty():
		_roof(mk, rng, K, hw, hd, hgt, roof, wall, dense)
	else:
		_flat_roof(mk, squeeze, hgt, wall)
	mk.pop()
	# a back extension where the plot runs deeper behind one half of the house
	var wing := Vector2.ZERO
	if squeeze.is_empty() and hw > 1.4:
		var behind_l := l.room(hx - hw * 0.5, hx) - setback - hd
		var behind_r := l.room(hx, hx + hw * 0.5) - setback - hd
		if maxf(behind_l, behind_r) > 1.3 and rng.randf() < (0.55 if dense else 0.4):
			wing.x = -1.0 if behind_l > behind_r else 1.0
			wing.y = minf(maxf(behind_l, behind_r) - 0.6, minf(hd * 0.9, 1.7))
			_wing(mk, rng, K, hx + wing.x * hw * 0.25, -setback - hd, hw, wing, floors, dense, wall, we, roof)
	if not dense:
		_garden(mk, rng, l, hx, hw, hd, setback, door_x + hx, land, y0, wing)
		l.foot = Rect2()
	else:
		# a townhouse leaves the rest of its plot to the yards round it
		l.foot = Rect2(hx - hw * 0.5, -setback - hd - wing.y, hw, setback + hd + wing.y)
	# a street lamp on the pavement every few houses
	if posmod(seed_value, 3) == 0 and not l.inner:
		CivicGen._lamp(mk, Vector3(l.width * 0.5, street_y - y0, 0.36))
	mk.pop()
	return [mk.verts, mk.norms, mk.cols, mk.uvs, mk.dverts, mk.dnorms, mk.dcols, mk.duvs, mk.sverts, mk.snorms,
		mk.bverts, mk.bcols, mk.buvs, mk.bradius, mk.qverts, mk.qcols, mk.quvs, mk.qradius]


## A shop on the ground floor: display windows either side of the door, a
## striped awning and a sign board, lit up at night.
## The street front of one bay of an office block: a glazed lobby floor
## under a canopy at the entrance, then bands of wide windows all the way up.
static func _office_front(mk: MeshKit, rng: RandomNumberGenerator, run: float, floors: int, wall: Color, entrance: bool) -> void:
	var count := maxi(1, int(run / 0.6))
	mk.box_faces(Vector3(0, FH * 0.5, 0.004), Vector3(run, FH, 0.008), wall.darkened(0.25), MeshKit.FRONT)
	mk.window_row(Vector3(0, FH * 0.5, 0.01), Vector3.BACK, run - 0.2, count, 0.5, 0.46, OFFICE_GLASS, false)
	if entrance:
		mk.box_faces(Vector3(0, FH * 0.92, 0.2), Vector3(minf(run * 0.6, 1.6), 0.04, 0.4), IRON, MeshKit.TOP | MeshKit.FRONT | MeshKit.LEFT | MeshKit.RIGHT)
	mk.window_grid(Vector3(0, FH, 0.0), Vector3.BACK, run, count, floors - 1, run / count - 0.1, OFFICE_GLASS, 1)


## What a shop sells, by chance: each has its own front.
const TRADES := ["shop", "shop", "cafe", "cafe", "bakery", "grocer", "pharmacy"]


## A shopfront across the ground floor (house-local, front face at z =
## `front`), dressed for its trade. Returns the trade.
static func _shopfront(mk: MeshKit, rng: RandomNumberGenerator, hw: float, front: float, wall: Color) -> String:
	var trade: String = TRADES[rng.randi() % TRADES.size()]
	var awn: Color = Palette.AWNINGS[rng.randi() % Palette.AWNINGS.size()]
	match trade:
		"bakery":
			awn = Color("c98a4b")
		"pharmacy":
			awn = Color("3fae6a")
		"grocer":
			awn = Color("3fae8c") if rng.randf() < 0.5 else Color("e85d5d")
	var z := front + 0.012
	# a painted frame round the whole front
	mk.box_faces(Vector3(0, 0.29, front + 0.01), Vector3(hw - 0.1, 0.5, 0.02), awn.darkened(0.4), MeshKit.FRONT)
	# a bakery's windows glow warm with the ovens behind
	var glass: Color = Color(1.0, 0.86, 0.6) if trade == "bakery" else Palette.GLASS_LIGHT
	for s: float in [-1.0, 1.0]:
		mk.window(Vector3(s * hw * 0.27, 0.32, z), Vector3.BACK, hw * 0.34, 0.36, glass, Color(0, 0, 0, 0), trade == "bakery")
	mk.box_faces(Vector3(0, 0.24, front + 0.02), Vector3(0.26, 0.44, 0.02), Color(0.95, 0.93, 0.88), MeshKit.FRONT)
	mk.window(Vector3(0, 0.27, front + 0.032), Vector3.BACK, 0.16, 0.32, Palette.GLASS_LIGHT, Color(0, 0, 0, 0), true)
	# striped awning, tilted out over the pavement (a pharmacy keeps a plain one)
	var stripes := 5
	var aw := hw - 0.14
	for k in stripes:
		var col := awn if k % 2 == 0 or trade == "pharmacy" else Color(0.98, 0.97, 0.94)
		var sx := -aw * 0.5 + (k + 0.5) * aw / stripes
		mk.push(Transform3D(Basis(Vector3.RIGHT, 0.45), Vector3(sx, 0.6, front + 0.02)))
		mk.box_faces(Vector3(0, 0, 0.17), Vector3(aw / stripes, 0.025, 0.34), col, MeshKit.TOP | MeshKit.FRONT | (MeshKit.LEFT if k == 0 else 0) | (MeshKit.RIGHT if k == stripes - 1 else 0))
		mk.pop()
	# sign board above the awning
	mk.box_faces(Vector3(0, 0.74, front + 0.025), Vector3(hw * 0.62, 0.13, 0.05), wall.lightened(0.6), MeshKit.FRONT | MeshKit.TOP)
	mk.box_faces(Vector3(0, 0.74, front + 0.051), Vector3(hw * 0.46, 0.05, 0.004), awn.darkened(0.25), MeshKit.FRONT, 2.0)
	match trade:
		"cafe":
			# a couple of tables with parasols out on the pavement
			for s: float in [-1.0, 1.0]:
				var tx := s * hw * 0.25
				mk.box_faces(Vector3(tx, 0.1, front + 0.26), Vector3(0.12, 0.02, 0.12), Color(0.95, 0.95, 0.93), MeshKit.TOP | MeshKit.FRONT)
				mk.pole(Vector3(tx, 0.0, front + 0.26), 0.008, 0.32, 4, IRON)
				mk.cone(Vector3(tx, 0.28, front + 0.26), 0.17, 0.08, 6, awn if s > 0.0 else Color(0.98, 0.97, 0.94))
		"grocer":
			# crates of fruit and greens under the awning
			var fruit := [Color("e8503a"), Color("f2b33d"), Color("6fb35a"), Color("f08a24")]
			for k in 3:
				var cx := (k - 1) * 0.2
				# the sides between neighbouring crates never show
				mk.box_faces(Vector3(cx, 0.08, front + 0.13), Vector3(0.17, 0.16, 0.16), Color("a87b50"), MeshKit.TOP | MeshKit.FRONT | (MeshKit.LEFT if k == 0 else 0) | (MeshKit.RIGHT if k == 2 else 0))
				mk.box_faces(Vector3(cx, 0.165, front + 0.13), Vector3(0.15, 0.012, 0.14), fruit[(k + rng.randi()) % fruit.size()], MeshKit.TOP)
		"pharmacy":
			# a green cross standing out from the wall, lit at night
			mk.box(Vector3(hw * 0.5 - 0.12, 0.86, front + 0.12), Vector3(0.03, 0.16, 0.05), Color("3fd17a"), null, false, 2.0)
			mk.box(Vector3(hw * 0.5 - 0.12, 0.86, front + 0.12), Vector3(0.03, 0.05, 0.16), Color("3fd17a"), null, false, 2.0)
	return trade


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
		_parapet(mk, Vector3(0, hgt, 0), hw + 0.04, hd + 0.04, 0.12, wall.lightened(0.35))
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


static func _garden(mk: MeshKit, rng: RandomNumberGenerator, l: Town.Lot, hx: float, hw: float, hd: float, setback: float, door_x: float, land: Land, y0: float, wing: Vector2) -> void:
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
	var back := l.depth - setback - hd - wing.y
	var tree_x := 0.0
	if back > 1.0:
		tree_x = lerpf(-0.3, 0.3, rng.randf()) * l.width
		if wing.y > 0.0:
			# on the open side, away from the extension
			tree_x = -wing.x * lerpf(0.15, 0.3, rng.randf()) * l.width
		_tree(mk, rng, Vector3(tree_x, 0.0, -setback - hd - wing.y - back * 0.55), land, l, y0)
	if back > 0.8:
		_backyard(mk, rng, l, -setback - hd - wing.y, tree_x, land, y0)


## A joined building over two to four neighbouring plots that have grown tall:
## one outline from the plots' own (its front along the street, bending with
## it, its back following the block), four to seven floors, shops or doors
## along the ground floor of each plot's front, windows on every face, and a
## parapet, or a slate attic set back on top in the older quarters.
static func build_block(ls: Array, land: Land, street_y: float, seed_value: int, main := false) -> Array:
	var h: Town.Lot = ls[0]
	var mk := MeshKit.new(seed_value)
	mk.quiet_sprites = true
	var rng := mk.rng
	var kit: int = h.kit
	var K: Dictionary = KITS[kit]
	var right := Vector2(cos(h.yaw), -sin(h.yaw))
	var fwd := Vector2(sin(h.yaw), cos(h.yaw))
	var stage := 0
	for l: Town.Lot in ls:
		stage = maxi(stage, l.stage)
	# four to five floors in a city, up to seven in a centre, eight to ten
	# for apartments and twelve to sixteen for a tower
	var floors: int = [4 + rng.randi() % 2, 5 + rng.randi() % 3, 8 + rng.randi() % 3, 12 + rng.randi() % 5][clampi(stage - 3, 0, 3)]
	var district: int = h.district
	if district == OFFICES and stage < 3:
		# a low office building on the edge of a business district
		floors = 2 + stage
	if stage >= 6 and ls.size() >= 2:
		# a skyscraper: twenty to forty floors, more over a wider plot
		floors = 20 + rng.randi() % 12 + mini(ls.size() - 2, 2) * 4
	# in a centre, and now and then on a city's main street, the big building is offices
	var office: bool = rng.randf() < [0.2 if main else 0.0, 0.45, 0.3, 0.6][clampi(stage - 3, 0, 3)] or district == OFFICES
	if district == SHOPS:
		office = false
	var tower := stage >= 6
	# where tall plots have joined up downtown, the tower is a skyscraper
	var sky := tower and ls.size() >= 2
	var pts := block_outline(ls)
	var box := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		box = box.expand(p)
	h.foot = box
	var fronts := pts.slice(0, ls.size() + 1)
	var backs := pts.slice(ls.size() + 1)
	# the ground under it, and the floor it stands on
	var lo := INF
	var hi := -INF
	for p in pts:
		var w := h.origin + right * p.x + fwd * p.y
		var g := land.height_at(w.x, w.y)
		lo = minf(lo, g)
		hi = maxf(hi, g)
	var y0 := maxf(street_y, (lo + hi) * 0.5 + 0.04)
	var hgt := floors * FH + 0.06
	var walls: Array = K.walls
	var wall: Color = walls[rng.randi() % walls.size()]
	var trim: Color = K.trim if K.trim != null else wall.lightened(0.45)
	var we := 0.0
	if rng.randf() < K.brick:
		if kit != BRICK:
			wall = Palette.BRICK[rng.randi() % 3]
		we = MeshKit.BRICKS
		trim = Color(0.95, 0.93, 0.88)
	var roof: Color = K.roofs[rng.randi() % K.roofs.size()]
	if stage >= 5 and not office and rng.randf() < 0.6:
		# apartment blocks in warm renders
		wall = APARTMENT_WALLS[rng.randi() % APARTMENT_WALLS.size()]
		we = 0.0
		trim = wall.lightened(0.4)
	if office:
		wall = OFFICE_WALLS[rng.randi() % OFFICE_WALLS.size()]
		we = 0.0
		trim = wall.lightened(0.3)
		floors += 1
		hgt = floors * FH + 0.06
	# a tower: a podium over the whole plot, the shaft rising from it set back,
	# in glass, white or warm stone, now and then brick
	var shaft := PackedVector2Array()
	var glass_col: Color = OFFICE_GLASS if office else Palette.GLASS
	var win_w := 0.5 if office else 0.24
	if tower:
		# skyscrapers are mostly glass or white
		var scheme: Array = TOWER_SCHEMES[rng.randi() % (3 if sky and rng.randf() < 0.8 else TOWER_SCHEMES.size())]
		var tones: Array = scheme[0]
		wall = tones[rng.randi() % tones.size()]
		glass_col = scheme[1]
		win_w = scheme[2]
		office = scheme[3] or district == OFFICES
		we = MeshKit.BRICKS if scheme[4] else 0.0
		trim = wall.lightened(0.3) if not scheme[4] else Color(0.95, 0.93, 0.88)
	var all_floors := floors
	if tower:
		var inner := Geometry2D.offset_polygon(pts, -0.45)
		if inner.size() == 1 and inner[0].size() >= 3 and outline_ok(inner[0]):
			shaft = inner[0]
			floors = 3
			hgt = floors * FH + 0.06
	mk.push_at(Vector3(h.origin.x, y0, h.origin.y), h.yaw)
	if y0 - lo > 0.04:
		# a stone base where the ground falls away
		mk.shadow = false
		_walls(mk, pts, lo - y0 - 0.12, 0.02, STONE.darkened(0.06))
		mk.shadow = true
	# sides and back: windows and floor bands, no ledges (they'd cost more than the rest of it)
	_prism(mk, pts, hgt, wall, we, floors, trim, fronts.size() - 1, office, win_w, glass_col, 0)
	# each plot's front: shops or a door below, windows above, a balcony or two
	var cw := Geometry2D.is_polygon_clockwise(pts)
	for k in fronts.size() - 1:
		var a := fronts[k]
		var b := fronts[k + 1]
		var run := a.distance_to(b)
		if run < 0.4:
			continue
		var t := (b - a) / run
		var out := Vector2(-t.y, t.x) if cw else Vector2(t.y, -t.x)
		var m := (a + b) * 0.5
		var l: Town.Lot = ls[k]
		mk.push_at(Vector3(m.x, 0, m.y), atan2(out.x, out.y))
		if office:
			_office_front(mk, rng, run, floors, wall, k == fronts.size() / 2 - 1 or fronts.size() == 2)
			l.floors = all_floors
			l.shop = false
			l.use = "office"
			if posmod(seed_value + k, 3) == 0:
				CivicGen._lamp(mk, Vector3(run * 0.5, street_y - y0, 0.36))
			mk.pop()
			continue
		l.use = "home"
		var shop := (main or district == SHOPS or rng.randf() < 0.45) and run > 1.3
		l.floors = all_floors
		l.shop = shop
		# the ground floor in a heavier base: stone under brick, a darker render elsewhere
		var base := STONE if we == MeshKit.BRICKS else wall.darkened(0.12)
		mk.box_faces(Vector3(0, FH * 0.5, 0.004), Vector3(run, FH, 0.008), base, MeshKit.FRONT)
		var count := maxi(1, int(run / 0.55))
		if shop:
			l.trade = _shopfront(mk, rng, run, 0.0, wall)
		else:
			var door: Color = K.doors[rng.randi() % K.doors.size()]
			mk.box_faces(Vector3(0, 0.3, 0.015), Vector3(0.34, 0.56, 0.03), door, MeshKit.FRONT | MeshKit.LEFT | MeshKit.RIGHT | MeshKit.TOP)
			mk.box_faces(Vector3(0, 0.62, 0.08), Vector3(0.5, 0.04, 0.16), trim, MeshKit.FRONT | MeshKit.TOP | MeshKit.LEFT | MeshKit.RIGHT)
			if count > 2:
				for sx: float in [-1.0, 1.0]:
					mk.window_row(Vector3(sx * (run * 0.25 + 0.1), FH * 0.55, 0.0), Vector3.BACK, run * 0.5 - 0.3, maxi(1, (count - 1) / 2), 0.24, 0.32, Palette.GLASS, true)
		# tall fronts: one sill course per floor (a ledge per window costs too much)
		mk.window_grid(Vector3(0, FH, 0.0), Vector3.BACK, run, count, floors - 1, 0.24, Palette.GLASS, 1)
		if rng.randf() < K.balcony + 0.25 and count >= 2:
			# a stack of iron balconies up one bay
			var bx := -run * 0.5 + (rng.randi() % count + 0.5) * run / count
			mk.shadow = false
			for fl in range(1, floors):
				var by := fl * FH + 0.08
				mk.box_faces(Vector3(bx, by, 0.12), Vector3(0.46, 0.04, 0.24), STONE, MeshKit.TOP | MeshKit.FRONT)
				mk.box_faces(Vector3(bx, by + 0.11, 0.235), Vector3(0.46, 0.18, 0.012), IRON, MeshKit.FRONT)
			mk.shadow = true
		if posmod(seed_value + k, 3) == 0:
			CivicGen._lamp(mk, Vector3(run * 0.5, street_y - y0, 0.36))
		mk.pop()
	# the top: a slate attic set back behind the parapet in the old quarters,
	# a plain parapet and a few boxes on the roof elsewhere
	if not shaft.is_empty():
		_flat_roof(mk, pts, hgt, wall)
		mk.push_at(Vector3(0, hgt, 0))
		var rest := all_floors - floors
		# a skyscraper steps in once or twice on the way up
		var tiers: Array = [[shaft, rest]]
		if sky and rest > 12:
			var parts := 1 + rng.randi() % 3
			var outline := shaft
			var left := rest
			tiers = []
			for t in parts:
				var fl := left if t == parts - 1 else int(left * rng.randf_range(0.45, 0.65))
				tiers.append([outline, fl])
				left -= fl
				if t < parts - 1:
					var nxt := Geometry2D.offset_polygon(outline, -rng.randf_range(0.25, 0.45))
					if nxt.size() != 1 or nxt[0].size() < 3 or not outline_ok(nxt[0]):
						tiers[tiers.size() - 1][1] += left
						break
					outline = nxt[0]
		mk.pop()
		for t in tiers.size():
			var outline: PackedVector2Array = tiers[t][0]
			var fl: int = tiers[t][1]
			if t > 0:
				_flat_roof(mk, tiers[t - 1][0], hgt, wall)
			mk.push_at(Vector3(0, hgt, 0))
			_prism(mk, outline, fl * FH + 0.06, wall, we, fl, trim, 0, office, win_w, glass_col, 0)
			mk.pop()
			hgt += fl * FH + 0.06
			shaft = outline
		# a crown: a plain set-back top storey for the plant, and a mast on some
		var crown := Geometry2D.offset_polygon(shaft, -0.3)
		if crown.size() == 1 and crown[0].size() >= 3 and outline_ok(crown[0]):
			_flat_roof(mk, shaft, hgt, wall)
			mk.push_at(Vector3(0, hgt, 0))
			_prism(mk, crown[0], FH * 0.9, wall.darkened(0.12), 0.0, 0, trim, 0)
			mk.pop()
			# floodlit round the top of the shaft, seen across the city at night
			mk.shadow = false
			var lamp_col := Color(0.86, 0.93, 1.0) if office else Color(1.0, 0.86, 0.62)
			for k in shaft.size():
				var a2: Vector2 = shaft[k]
				var b2: Vector2 = shaft[(k + 1) % shaft.size()]
				var out := Vector2(b2.y - a2.y, a2.x - b2.x).normalized() * 0.012
				if _area(shaft) < 0.0:
					out = -out
				var a3 := Vector3(a2.x + out.x, hgt - 0.16, a2.y + out.y)
				var b3 := Vector3(b2.x + out.x, hgt - 0.16, b2.y + out.y)
				mk.quad(a3, b3, b3 + Vector3(0, 0.1, 0), a3 + Vector3(0, 0.1, 0), Vector3(out.x, 0, out.y).normalized(), lamp_col, 2.7)
			mk.shadow = true
			hgt += FH * 0.9
			shaft = crown[0]
			var mc := Vector2.ZERO
			for p in shaft:
				mc += p
			mc /= shaft.size()
			if sky and rng.randf() < 0.55:
				# a spire, with a beacon on top
				var tall := rng.randf_range(2.2, 4.0)
				mk.cylinder(Vector3(mc.x, hgt, mc.y), 0.09, tall, 4, Color(0.82, 0.84, 0.86), false, null, 0.015)
				mk.box(Vector3(mc.x, hgt + tall, mc.y), Vector3(0.08, 0.08, 0.08), Color(1.0, 0.12, 0.08), null, false, 2.7)
			elif rng.randf() < 0.4:
				mk.cylinder(Vector3(mc.x, hgt, mc.y), 0.03, 1.8, 4, IRON, false)
				mk.box(Vector3(mc.x, hgt + 1.8, mc.y), Vector3(0.07, 0.07, 0.07), Color(1.0, 0.12, 0.08), null, false, 2.7)
		pts = shaft
		backs = shaft
	var attic := shaft.is_empty() and not office and (kit == BRICK or kit == STONE_SLATE or kit == NORDIC or kit == PASTEL) and rng.randf() < 0.7
	var inset: Array[PackedVector2Array] = []
	if attic:
		inset = Geometry2D.offset_polygon(pts, -0.32)
	if attic and inset.size() == 1 and (inset[0] as PackedVector2Array).size() >= 3:
		var top: PackedVector2Array = inset[0]
		_flat_roof(mk, pts, hgt, wall)
		mk.push_at(Vector3(0, hgt, 0))
		_prism(mk, top, FH * 0.8, roof, MeshKit.ROOF_TILES, 1, roof, 0, false)
		_flat_roof(mk, top, FH * 0.8, roof)
		mk.pop()
	else:
		_flat_roof(mk, pts, hgt, wall)
		var c := Vector2.ZERO
		for p in backs:
			c += p
		c /= backs.size()
		c = c.lerp(fronts[fronts.size() / 2], 0.45)
		mk.box(Vector3(c.x, hgt + 0.25, c.y), Vector3(0.7, 0.5, 0.55), wall.darkened(0.08))
		if office:
			# plant on the roof, and a mast now and then
			mk.box(Vector3(c.x - 0.9, hgt + 0.18, c.y), Vector3(0.8, 0.36, 0.5), Color(0.62, 0.64, 0.66))
			if rng.randf() < 0.5:
				mk.cylinder(Vector3(c.x + 0.5, hgt + 0.5, c.y), 0.025, 0.9, 4, IRON, false)
		elif rng.randf() < 0.6:
			mk.cylinder(Vector3(c.x + 0.8, hgt + 0.02, c.y), 0.22, 0.45, 6, Color(0.6, 0.5, 0.42))
	mk.pop()
	return [mk.verts, mk.norms, mk.cols, mk.uvs, mk.dverts, mk.dnorms, mk.dcols, mk.duvs, mk.sverts, mk.snorms,
		mk.bverts, mk.bcols, mk.buvs, mk.bradius, mk.qverts, mk.qcols, mk.quvs, mk.qradius]


## Twice the signed area of an outline (its winding: > 0 one way, < 0 the other).
static func _area(pts: PackedVector2Array) -> float:
	var a := 0.0
	for k in pts.size():
		a += pts[k].cross(pts[(k + 1) % pts.size()])
	return a


## The outline of a joined building, in its first plot's frame: the fronts
## in order, then each plot's back, last to first, brought in to leave a yard.
static func block_outline(ls: Array) -> PackedVector2Array:
	var h: Town.Lot = ls[0]
	var right := Vector2(cos(h.yaw), -sin(h.yaw))
	var fwd := Vector2(sin(h.yaw), cos(h.yaw))
	var stage := 0
	for l: Town.Lot in ls:
		stage = maxi(stage, l.stage)
	var deepest: float = [4.4, 5.0, 5.4, 5.6][clampi(stage - 3, 0, 3)]
	var fronts := PackedVector2Array()
	var backs := PackedVector2Array()
	for l: Town.Lot in ls:
		var a := l.quad[0]
		var b := l.quad[1]
		if fronts.is_empty():
			fronts.append(_local(a, h.origin, right, fwd))
		fronts.append(_local(b, h.origin, right, fwd))
	for li in range(ls.size() - 1, -1, -1):
		# a straight back wall per plot, slanting where the plot tapers: as
		# deep as the shallower half of the plot allows at each end
		var l: Town.Lot = ls[li]
		var n := l.quad.size() - 2
		var d_a := INF
		var d_b := INF
		for j in n:
			var u := (n - 1 - j) / float(maxi(n - 1, 1))
			var d := l.quad[2 + j].distance_to(l.quad[0].lerp(l.quad[1], u))
			if u >= 0.5:
				d_b = minf(d_b, d)
			if u <= 0.5:
				d_a = minf(d_a, d)
		var na := (l.quad[l.quad.size() - 1] - l.quad[0]).normalized()
		var nb := (l.quad[2] - l.quad[1]).normalized()
		backs.append(_local(l.quad[1] + nb * clampf(d_b - 0.5, 1.2, deepest), h.origin, right, fwd))
		backs.append(_local(l.quad[0] + na * clampf(d_a - 0.5, 1.2, deepest), h.origin, right, fwd))
	var pts := fronts.duplicate()
	pts.append_array(backs)
	return pts


## Whether an outline is one clean shape: no edge crossing another, and
## enough of it to put a roof on.
static func outline_ok(raw: PackedVector2Array) -> bool:
	var pts := PackedVector2Array()
	for p in raw:
		if pts.is_empty() or p.distance_to(pts[pts.size() - 1]) > 0.02:
			pts.append(p)
	if pts.size() > 1 and pts[0].distance_to(pts[pts.size() - 1]) <= 0.02:
		pts.remove_at(pts.size() - 1)
	var n := pts.size()
	if n < 3 or Geometry2D.triangulate_polygon(pts).is_empty():
		return false
	for i in n:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		for j in range(i + 2, n):
			if (j + 1) % n == i:
				continue
			if Geometry2D.segment_intersects_segment(a, b, pts[j], pts[(j + 1) % n]) != null:
				return false
	return true


static func _local(p: Vector2, origin: Vector2, right: Vector2, fwd: Vector2) -> Vector2:
	var q := p - origin
	return Vector2(q.dot(right), q.dot(fwd))


## Plain walls round an outline from y0 up to y1 (a stone base, a plinth).
static func _walls(mk: MeshKit, pts: PackedVector2Array, y0: float, y1: float, col: Color) -> void:
	var cw := Geometry2D.is_polygon_clockwise(pts)
	for k in pts.size():
		var a := pts[k]
		var b := pts[(k + 1) % pts.size()]
		if a.distance_to(b) < 0.02:
			continue
		var t := (b - a).normalized()
		var out := Vector2(-t.y, t.x) if cw else Vector2(t.y, -t.x)
		mk.quad(Vector3(a.x, y0, a.y), Vector3(b.x, y0, b.y), Vector3(b.x, y1, b.y), Vector3(a.x, y1, a.y), Vector3(out.x, 0, out.y), col)


## A one or two storey extension behind half of the house, on its `wing.x`
## side, `wing.y` deep: a gabled outshot behind a house, a flat-roofed one
## behind a terrace.
static func _wing(mk: MeshKit, rng: RandomNumberGenerator, K: Dictionary, x: float, z0: float, hw: float, wing: Vector2, floors: int, dense: bool,
		wall: Color, we: float, roof: Color) -> void:
	var ww := hw * 0.5
	var wf := 1 if floors <= 2 else 2
	var wh := wf * FH + 0.04
	var wz := z0 - wing.y * 0.5
	mk.box_faces(Vector3(x, wh * 0.5, wz), Vector3(ww, wh, wing.y), wall, MeshKit.BACK | MeshKit.LEFT | MeshKit.RIGHT, we)
	mk.window_grid(Vector3(x, 0, z0 - wing.y), Vector3.FORWARD, ww, maxi(1, int(ww / 0.6)), wf, 0.24, Palette.GLASS, 1)
	if dense:
		_parapet(mk, Vector3(x, wh, wz), ww + 0.04, wing.y + 0.02, 0.08, wall.lightened(0.3))
	else:
		# its ridge runs back from the house
		var pitch := lerpf(K.pitch.x, K.pitch.y, rng.randf()) * 0.8
		mk.push_at(Vector3(x, wh, wz), PI * 0.5)
		mk.gable_roof(Vector3.ZERO, wing.y, ww, ww * 0.5 * pitch, 0.05, roof, wall)
		mk.pop()


## A low parapet round a flat felt roof, its foot centred at `base`: outer
## walls, a rim along the top, and the felt sunk well below the rim so the two
## never sit close enough to flicker against each other.
static func _parapet(mk: MeshKit, base: Vector3, w: float, d: float, h: float, col: Color) -> void:
	var was := mk.shadow
	mk.shadow = false
	mk.box_faces(base + Vector3(0, h * 0.5, 0), Vector3(w, h, d), col, MeshKit.FRONT | MeshKit.BACK | MeshKit.LEFT | MeshKit.RIGHT)
	var rim := 0.05
	var y := base.y + h
	for sz: float in [-1.0, 1.0]:
		mk.box_faces(Vector3(base.x, y, base.z + sz * (d - rim) * 0.5), Vector3(w, 0.0, rim), col, MeshKit.TOP)
	for sx: float in [-1.0, 1.0]:
		mk.box_faces(Vector3(base.x + sx * (w - rim) * 0.5, y, base.z), Vector3(rim, 0.0, d - rim * 2.0), col, MeshKit.TOP)
	mk.box_faces(base + Vector3(0, h - 0.05, 0), Vector3(w - rim * 2.0, 0.0, d - rim * 2.0), Color(0.55, 0.55, 0.57), MeshKit.TOP)
	mk.shadow = was


## The outline of a terrace whose plot is too shallow at one end for a full
## rectangle (house-local, centred on the house): a straight front, and a back
## that follows the plot's back line where it cuts in.
static func _squeezed(l: Town.Lot, hw: float, hd: float, setback: float) -> PackedVector2Array:
	var front := hd * 0.5
	var xs: Array[float] = [-hw * 0.5]
	for p in l.back:
		if p.x > -hw * 0.5 + 0.1 and p.x < hw * 0.5 - 0.1:
			xs.append(p.x)
	xs.append(hw * 0.5)
	var pts := PackedVector2Array([Vector2(-hw * 0.5, front), Vector2(hw * 0.5, front)])
	for k in range(xs.size() - 1, -1, -1):
		var d := clampf(l.depth_at(xs[k]) - setback - 0.1, 0.6, hd)
		pts.append(Vector2(xs[k], front - d))
	return pts


## Walls round an outline (house-local, front edge first), with floor bands and
## windows on every wall but the front, which the house dresses itself.
static func _prism(mk: MeshKit, pts: PackedVector2Array, hgt: float, wall: Color, we: float, floors: int, trim: Color, fronts := 1, every_floor := true,
		win_w := 0.24, glass := Palette.GLASS, sills := 2) -> void:
	var cw := Geometry2D.is_polygon_clockwise(pts)
	for k in pts.size():
		var a := pts[k]
		var b := pts[(k + 1) % pts.size()]
		var run := a.distance_to(b)
		if run < 0.02:
			continue
		var t := (b - a) / run
		var out := Vector2(-t.y, t.x) if cw else Vector2(t.y, -t.x)
		var o3 := Vector3(out.x, 0, out.y)
		mk.quad(Vector3(a.x, 0, a.y), Vector3(b.x, 0, b.y), Vector3(b.x, hgt, b.y), Vector3(a.x, hgt, a.y), o3, wall, we)
		if k < fronts or run < 0.5:
			continue
		var m := (a + b) * 0.5
		mk.window_grid(Vector3(m.x, 0, m.y), o3, run, maxi(1, int(run / 0.6)), floors, win_w, glass, sills)
		# floor bands as thin strips standing just proud of the wall (one quad,
		# the gaps between them cut out by the shader)
		if floors >= 2:
			var a2 := a + out * 0.012
			var b2 := b + out * 0.012
			mk.band_wall(Vector3(a2.x, 0, a2.y), Vector3(b2.x, 0, b2.y), o3, FH + 0.03, FH, floors - 1 if every_floor else 1, 0.036, trim)


## A flat roof over an outline, behind a low parapet.
static func _flat_roof(mk: MeshKit, pts: PackedVector2Array, hgt: float, wall: Color) -> void:
	var tris := Geometry2D.triangulate_polygon(pts)
	# grey felt, dark tar, pale gravel, and now and then a planted roof
	var top: Color = [Color(0.55, 0.55, 0.57), Color(0.55, 0.55, 0.57), Color(0.55, 0.55, 0.57), Color(0.38, 0.39, 0.42), Color(0.38, 0.39, 0.42),
		Color(0.68, 0.64, 0.57), Color(0.68, 0.64, 0.57), Color(0.5, 0.6, 0.4)][mk.rng.randi() % 8]
	for k in range(0, tris.size(), 3):
		var a := pts[tris[k]]
		var b := pts[tris[k + 1]]
		var c := pts[tris[k + 2]]
		mk.tri(Vector3(a.x, hgt + 0.02, a.y), Vector3(b.x, hgt + 0.02, b.y), Vector3(c.x, hgt + 0.02, c.y), top, 0.0, 0.0, Vector3.UP)
	var cw := Geometry2D.is_polygon_clockwise(pts)
	var lip := wall.lightened(0.35)
	# the parapet is too low to cast a shadow worth its triangles
	var casts := mk.shadow
	mk.shadow = false
	for k in pts.size():
		var a := pts[k]
		var b := pts[(k + 1) % pts.size()]
		if a.distance_to(b) < 0.02:
			continue
		var t := (b - a).normalized()
		var out := Vector2(-t.y, t.x) if cw else Vector2(t.y, -t.x)
		var a2 := a + out * 0.03
		var b2 := b + out * 0.03
		var o3 := Vector3(out.x, 0, out.y)
		mk.quad(Vector3(a2.x, hgt, a2.y), Vector3(b2.x, hgt, b2.y), Vector3(b2.x, hgt + 0.12, b2.y), Vector3(a2.x, hgt + 0.12, a2.y), o3, lip)
		mk.quad(Vector3(a2.x, hgt + 0.12, a2.y), Vector3(b2.x, hgt + 0.12, b2.y), Vector3(b.x - out.x * 0.05, hgt + 0.12, b.y - out.y * 0.05), Vector3(a.x - out.x * 0.05, hgt + 0.12, a.y - out.y * 0.05), Vector3.UP, lip)
	mk.shadow = casts


## The back garden behind a house (from z = `z0` to the back of the lot): a
## fence or hedge round it, and often a shed, a vegetable patch or washing
## hung out on a line. All low and kept off the shadow map.
static func _backyard(mk: MeshKit, rng: RandomNumberGenerator, l: Town.Lot, z0: float, tree_x: float, land: Land, y0: float) -> void:
	var right := Vector2(cos(l.yaw), -sin(l.yaw))
	var fwd := Vector2(sin(l.yaw), cos(l.yaw))
	var ground := func(x: float, z: float) -> float:
		var p: Vector2 = l.origin + right * x + fwd * z
		return land.height_at(p.x, p.y) - y0
	var hedge := rng.randf() < 0.45
	var col: Color = Palette.LEAF[rng.randi() % Palette.LEAF.size()].darkened(0.2) if hedge else [Color(0.97, 0.97, 0.95), Color(0.62, 0.46, 0.33)][rng.randi() % 2]
	var hh := 0.18 if hedge else 0.13
	var th := 0.12 if hedge else 0.04
	var hw := l.width * 0.5
	mk.shadow = false
	# along the back of the plot, whatever its shape, and down the right-hand
	# side (the neighbour's fence closes the left), following the ground
	var pts: Array[Vector3] = []
	for x: float in _steps(-hw, hw):
		var z := -l.depth_at(x) + 0.06
		pts.append(Vector3(x, ground.call(x, z), z))
	for z: float in _steps(-l.depth_at(hw - 0.03) + 0.06, z0).slice(1):
		pts.append(Vector3(hw - 0.03, ground.call(hw - 0.03, z), z))
	_fence(mk, pts, hh, th, col)
	mk.shadow = true
	var side := -1.0 if tree_x > 0.0 else 1.0
	# the far corner on that side, wherever the back runs
	var zb := -l.room(side * hw * 0.2, side * hw) + 0.06
	var run := z0 - zb
	var roll := rng.randf()
	if roll < 0.3 and run > 0.75:
		# a garden shed in the far corner, away from the tree
		var c := Vector3(side * (hw - 0.42), 0.0, zb + 0.36)
		c.y = ground.call(c.x, c.z)
		var wall: Color = [Color("8a6a4f"), Color("6f8a6a"), Color("e8e2d4"), Color("5f7a94")][rng.randi() % 4]
		mk.box(c + Vector3(0, 0.22, 0), Vector3(0.56, 0.54, 0.46), wall)
		mk.box_faces(c + Vector3(0.1, 0.2, 0.235), Vector3(0.18, 0.36, 0.012), wall.darkened(0.3), MeshKit.FRONT)
		mk.window(c + Vector3(-0.15, 0.3, 0.232), Vector3.BACK, 0.12, 0.12, Palette.GLASS)
		mk.gable_roof(c + Vector3(0, 0.49, 0), 0.56, 0.46, 0.18, 0.05, Color("5a4a44"), wall, 0.03)
	elif roll < 0.55 and run > 0.75:
		# a vegetable patch: dark soil with rows of greens
		var c := Vector3(side * (hw - 0.5), 0.0, zb + 0.4)
		c.y = ground.call(c.x, c.z)
		mk.shadow = false
		mk.box_faces(c + Vector3(0, 0.02, 0), Vector3(0.7, 0.06, 0.55), Color(0.42, 0.31, 0.22), MeshKit.TOP | MeshKit.FRONT | MeshKit.BACK | MeshKit.LEFT | MeshKit.RIGHT)
		mk.shadow = true
		for r in 3:
			for j in 3:
				mk.blob(c + Vector3(-0.22 + j * 0.22, 0.08, -0.17 + r * 0.17), Vector3(0.07, 0.05, 0.07), Color("5e9e48").lightened(0.1 * r), 0.02)
	elif roll < 0.85 and run > 0.9 and absf(tree_x - side * (hw - 0.3)) > 0.55:
		# washing hung out on a line down the side of the garden, clear of the tree
		var x := side * (hw - 0.3)
		var za := z0 - 0.2
		var zc := zb + 0.2
		var ya: float = ground.call(x, za)
		var yb: float = ground.call(x, zc)
		mk.pole(Vector3(x, ya, za), 0.012, 0.6, 3, Color(0.85, 0.85, 0.85))
		mk.pole(Vector3(x, yb, zc), 0.012, 0.6, 3, Color(0.85, 0.85, 0.85))
		var top := (ya + yb) * 0.5 + 0.58
		mk.box_faces(Vector3(x, top, (za + zc) * 0.5), Vector3(0.008, 0.008, za - zc), Color(0.9, 0.9, 0.9), MeshKit.TOP | MeshKit.LEFT)
		var clothes := clampi(int((za - zc) / 0.3), 1, 4)
		for k in clothes:
			var z := lerpf(zc + 0.1, za - 0.1, (k + 0.5) / clothes)
			var cw := rng.randf_range(0.14, 0.22)
			var ch := rng.randf_range(0.14, 0.26)
			mk.box_faces(Vector3(x, top - ch * 0.5, z), Vector3(0.012, ch, cw), Palette.LAUNDRY[rng.randi() % Palette.LAUNDRY.size()], MeshKit.LEFT | MeshKit.RIGHT)


## Evenly spaced stops from `a` to `b`, about 0.6 m apart, both ends included.
static func _steps(a: float, b: float) -> Array[float]:
	var n := maxi(1, ceili(absf(b - a) / 0.6))
	var out: Array[float] = []
	for k in n + 1:
		out.append(lerpf(a, b, float(k) / n))
	return out


## A low fence or hedge through ground points `pts`: two sides and a top per
## stretch, its foot tucked a little into the ground so slopes never show a gap.
static func _fence(mk: MeshKit, pts: Array[Vector3], hh: float, th: float, col: Color) -> void:
	# stops where the ground or the line turns; straight even runs are one piece
	var keep: Array[Vector3] = [pts[0]]
	for k in range(1, pts.size() - 1):
		var a := keep[keep.size() - 1]
		var c := pts[k + 1]
		var t := clampf((pts[k] - a).dot(c - a) / maxf((c - a).length_squared(), 1e-6), 0.0, 1.0)
		if pts[k].distance_to(a.lerp(c, t)) > 0.025:
			keep.append(pts[k])
	keep.append(pts[pts.size() - 1])
	pts = keep
	for k in pts.size() - 1:
		var a := pts[k]
		var b := pts[k + 1]
		var along := Vector3(b.x - a.x, 0, b.z - a.z).normalized()
		var n := Vector3(-along.z, 0, along.x) * th * 0.5
		var up := Vector3(0, hh, 0)
		var dn := Vector3(0, -0.05, 0)
		mk.quad(a + n + dn, b + n + dn, b + n + up, a + n + up, n, col)
		mk.quad(a - n + dn, b - n + dn, b - n + up, a - n + up, -n, col)
		mk.quad(a + n + up, b + n + up, b - n + up, a - n + up, Vector3.UP, col.lightened(0.06))


## A garden tree, standing on the real ground wherever the garden slopes to.
static func _tree(mk: MeshKit, rng: RandomNumberGenerator, at: Vector3, land: Land, l: Town.Lot, y0: float) -> void:
	var p := l.origin + Vector2(cos(l.yaw), -sin(l.yaw)) * at.x + Vector2(sin(l.yaw), cos(l.yaw)) * at.z
	at.y = land.height_at(p.x, p.y) - y0
	var s := lerpf(0.75, 1.15, rng.randf())
	mk.pole(at, 0.05 * s, 0.5 * s, 5, Color(0.45, 0.33, 0.24))
	var leaf: Color = Palette.LEAF[rng.randi() % Palette.LEAF.size()]
	mk.blob(at + Vector3(0, 0.75 * s, 0), Vector3(0.42, 0.4, 0.42) * s, leaf, 0.1)
	mk.blob(at + Vector3(0.18 * s, 0.98 * s, 0.05), Vector3(0.28, 0.26, 0.28) * s, leaf.lightened(0.08), 0.1)


# ------------------------------------------------------------------ industry

## A works on an industrial plot: a corrugated shed filling most of it, with
## a sawtooth roof of north lights as it grows, a big loading door and a
## concrete yard in front; tanks or silos alongside, and a chimney stack
## on the bigger works.
static func build_industry(l: Town.Lot, land: Land, street_y: float, seed_value: int) -> Array:
	var mk := MeshKit.new(seed_value)
	mk.quiet_sprites = true
	var rng := mk.rng
	l.use = "industry"
	l.shop = false
	l.floors = 1
	l.smoke = Vector3.INF
	var big := l.stage >= 3
	var yard := 0.35 + rng.randf() * 0.3
	var hw := maxf(l.width - 0.3, 1.2)
	var hd := clampf(l.room(-hw * 0.5, hw * 0.5) - yard - 0.2, 1.2, 5.2)
	var hgt := 0.9 + minf(l.stage, 4) * 0.22 + rng.randf() * 0.2
	var right := Vector2(cos(l.yaw), -sin(l.yaw))
	var fwd := Vector2(sin(l.yaw), cos(l.yaw))
	var lo := INF
	var hi := -INF
	for c in [Vector2(-hw * 0.5, -yard), Vector2(hw * 0.5, -yard), Vector2(hw * 0.5, -yard - hd), Vector2(-hw * 0.5, -yard - hd)]:
		var p: Vector2 = l.origin + right * c.x + fwd * c.y
		var g := land.height_at(p.x, p.y)
		lo = minf(lo, g)
		hi = maxf(hi, g)
	var y0 := maxf(street_y, (l.level if l.level > -INF else (lo + hi) * 0.5) + 0.04)
	l.plinth = y0 - lo
	l.foot = Rect2(-hw * 0.5, -yard - hd, hw, yard + hd)
	var wall: Color = SHED_WALLS[rng.randi() % SHED_WALLS.size()]
	var roof: Color = SHED_ROOFS[rng.randi() % SHED_ROOFS.size()]
	mk.push_at(Vector3(l.origin.x, y0, l.origin.y), l.yaw)
	if y0 - lo > 0.04:
		mk.shadow = false
		mk.box(Vector3(0, (lo - y0) * 0.5 - 0.04, -yard - hd * 0.5), Vector3(hw + 0.04, y0 - lo + 0.1, hd + 0.04), STONE.darkened(0.1))
		mk.shadow = true
	# the concrete yard between the street and the shed
	mk.shadow = false
	mk.box_faces(Vector3(0, 0.01, -yard * 0.5), Vector3(hw, 0.02, yard), Color(0.74, 0.73, 0.7), MeshKit.TOP)
	mk.shadow = true
	var cz := -yard - hd * 0.5
	mk.box_faces(Vector3(0, hgt * 0.5, cz), Vector3(hw, hgt, hd), wall, MeshKit.FRONT | MeshKit.BACK | MeshKit.LEFT | MeshKit.RIGHT, MeshKit.SIDING)
	if big and hd > 1.6:
		# a sawtooth roof: steep glazed faces looking one way, long slopes the other
		var teeth := maxi(2, int(hd / 0.9))
		var step := hd / teeth
		for t in teeth:
			var z1 := -yard - t * step
			var z0 := z1 - step
			var rise := minf(step * 0.55, 0.45)
			mk.quad(Vector3(-hw * 0.5, hgt, z0), Vector3(hw * 0.5, hgt, z0), Vector3(hw * 0.5, hgt + rise, z1), Vector3(-hw * 0.5, hgt + rise, z1), Vector3(0, step, -rise), roof)
			mk.quad(Vector3(-hw * 0.5, hgt, z1), Vector3(hw * 0.5, hgt, z1), Vector3(hw * 0.5, hgt + rise, z1), Vector3(-hw * 0.5, hgt + rise, z1), Vector3.BACK, OFFICE_GLASS, 1.0)
			for sx: float in [-1.0, 1.0]:
				mk.tri(Vector3(sx * hw * 0.5, hgt, z0), Vector3(sx * hw * 0.5, hgt, z1), Vector3(sx * hw * 0.5, hgt + rise, z1), wall, 0.0, 0.0, Vector3(sx, 0, 0))
	else:
		# a shallow roof behind a parapet, with a vent or two
		mk.box_faces(Vector3(0, hgt + 0.01, cz), Vector3(hw, 0.02, hd), roof, MeshKit.TOP)
		mk.box(Vector3(hw * 0.2, hgt + 0.15, cz), Vector3(0.35, 0.3, 0.35), Color(0.7, 0.72, 0.74))
	# the loading door, and a little office window beside it
	var door := minf(hw * 0.45, 1.2)
	mk.box_faces(Vector3(-hw * 0.18, minf(hgt * 0.4, 0.5), -yard + 0.01), Vector3(door, minf(hgt * 0.8, 1.0), 0.02), Color(0.55, 0.58, 0.6) if rng.randf() < 0.6 else Color("d08a2e"), MeshKit.FRONT)
	mk.window_row(Vector3(hw * 0.3, hgt * 0.55, -yard), Vector3.BACK, hw * 0.3, 2, 0.3, 0.26, OFFICE_GLASS, false)
	# tanks or silos alongside, on a plot with room for them
	if l.stage >= 1 and rng.randf() < 0.55 and hw > 2.0:
		var n := 1 + rng.randi() % 2
		var r := 0.28 + rng.randf() * 0.12
		var tank: Color = [Color(0.88, 0.88, 0.86), Color(0.75, 0.78, 0.8), Color("b7c7b0")][rng.randi() % 3]
		for k in n:
			var x := hw * 0.5 - r - 0.08 - k * (r * 2.0 + 0.1)
			mk.cylinder(Vector3(x, 0.0, -yard * 0.5 + 0.02), r, hgt * (0.9 + rng.randf() * 0.5), 8, tank, true, tank.darkened(0.1))
	# a chimney stack with a red and white top on the bigger works
	if big and rng.randf() < 0.65:
		var cx := -hw * 0.5 + 0.35
		var ch := hgt + 1.6 + rng.randf() * 1.6
		mk.cylinder(Vector3(cx, 0.0, cz - hd * 0.3), 0.16, ch - 0.4, 8, Color("a35a45"), false, null, 0.13)
		mk.cylinder(Vector3(cx, ch - 0.4, cz - hd * 0.3), 0.13, 0.4, 8, Color(0.95, 0.95, 0.93), true, Color(0.2, 0.2, 0.2), 0.125)
		l.smoke = mk.xf * Vector3(cx, ch, cz - hd * 0.3)
	# a container or two stacked in the yard
	if rng.randf() < 0.5 and yard > 0.45:
		var cc := [Color("c8553d"), Color("2f8f83"), Color("e3a33b"), Color("3d5f8f")]
		mk.box(Vector3(-hw * 0.5 + 0.55, 0.14, -yard * 0.5), Vector3(0.9, 0.26, 0.3), cc[rng.randi() % cc.size()])
	mk.pop()
	return [mk.verts, mk.norms, mk.cols, mk.uvs, mk.dverts, mk.dnorms, mk.dcols, mk.duvs, mk.sverts, mk.snorms,
		mk.bverts, mk.bcols, mk.buvs, mk.bradius, mk.qverts, mk.qcols, mk.quvs, mk.qradius]
