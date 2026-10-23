class_name CityGen
extends RefCounted
## Procedural generators for every tile type. Buildings read their surroundings:
## they face the street, join into terraced rows, take seaside / hillside styles
## and grow taller with density.

const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]
const H := 1.0  # half tile

const WALLS := [Color("fbf1df"), Color("f6dca7"), Color("f3c6a5"), Color("e9b8a5"), Color("cfe0c3"), Color("c9dbe9"), Color("efe4d2")]
const ROOFS := [Color("d9694f"), Color("b9503f"), Color("8b5a44"), Color("5d6b84"), Color("c9774b"), Color("6f8a5b")]
const SEA_WALLS := [Color("ffffff"), Color("f8f6f0"), Color("cfe8f5"), Color("d9f2e6"), Color("ffe0d2"), Color("fff1c4")]
const SEA_ROOFS := [Color("3f7cc4"), Color("e0805e"), Color("3aa6a0"), Color("ffffff")]
const HILL_WALLS := [Color("d8d0c4"), Color("c9bfb2"), Color("efe7d8"), Color("b8ab9c")]
const HILL_ROOFS := [Color("4b5262"), Color("5b4a42"), Color("3f4a56")]
const BRICK := [Color("c2684f"), Color("b55d4a"), Color("d48a6a"), Color("e8d2b0"), Color("a8b8c8")]
const AWNINGS := [Color("e85d5d"), Color("3fae8c"), Color("4b86d6"), Color("f2b33d"), Color("ef7fa8"), Color("8a6fd6")]
const GLASS := Color(0.32, 0.47, 0.6)
const GLASS_LIGHT := Color(0.55, 0.72, 0.84)
const FRAME := Color(0.97, 0.97, 0.95)
const DOOR := Color(0.45, 0.3, 0.22)
const ASPHALT := Color(0.36, 0.38, 0.43)
const SIDEWALK := Color(0.88, 0.85, 0.8)
const LEAF := [Color("6fb35a"), Color("5ea552"), Color("82c063"), Color("4e9a54"), Color("97c45a")]
const AUTUMN := [Color("e89a3c"), Color("d9673a"), Color("f2c14e")]
const BLOSSOM := [Color("f4a7c0"), Color("f7c2d4"), Color("ee8fb0"), Color("fbe3ea")]
const FLOWERS := [Color("ef5b5b"), Color("f2c14e"), Color("ffffff"), Color("8a6fd6"), Color("ef7fa8"), Color("4b86d6"), Color("f28b3c")]
# [walls, roofs] per district: seaside whites, pastels, warm brick, cream & slate,
# terracotta south, painted nordic timber
const DISTRICTS := [
	[[Color("ffffff"), Color("f8f6f0"), Color("e3f0f7"), Color("fdf3dc")], [Color("3f7cc4"), Color("4f8fb0"), Color("e0805e")]],
	[[Color("f6dca7"), Color("cfe0c3"), Color("c9dbe9"), Color("f3c6a5"), Color("e7d3ec")], [Color("d9694f"), Color("6f8a5b"), Color("5d6b84")]],
	[[Color("c2684f"), Color("b55d4a"), Color("d48a6a"), Color("a9574a")], [Color("5d4a42"), Color("4b5262"), Color("8b5a44")]],
	[[Color("efe4d2"), Color("e8dcc6"), Color("fbf1df"), Color("dcd3c3")], [Color("4b5262"), Color("5d6b84"), Color("3f4a56")]],
	[[Color("f2d4a8"), Color("efc49a"), Color("f6e3c4"), Color("e9b88f")], [Color("c9774b"), Color("d9694f"), Color("b9503f")]],
	[[Color("b9503f"), Color("e0b44a"), Color("4f7f9e"), Color("e9e2d0"), Color("6f8f6a")], [Color("3a3f47"), Color("5b4a42"), Color("2f3a48")]],
]


# ------------------------------------------------------------------ roads

## Which of the 4 directions a road tile links to. Roads link on equal height, and ramps
## (a straight road climbing one terrace) link up to the next level.
static func road_links(x: int, z: int) -> Array:
	var out := [false, false, false, false]
	if Game.knd(x, z) != Game.K.ROAD:
		return out
	var l := Game.road_level(x, z)
	var rd := ramp_dir(x, z)
	for i in 4:
		var d := DIRS[i]
		var nx := x + d.x
		var nz := z + d.y
		if Game.knd(nx, nz) != Game.K.ROAD:
			continue
		var nl := Game.road_level(nx, nz)
		if nl == l:
			out[i] = true
		elif nl == l + 1 and rd == i:
			out[i] = true
		elif nl == l - 1 and ramp_dir(nx, nz) == (i + 2) % 4:
			out[i] = true
	return out


## Returns the direction index a road ramps up toward, or -1.
static func ramp_dir(x: int, z: int) -> int:
	if Game.knd(x, z) != Game.K.ROAD or Game.lvl(x, z) == 0:
		return -1
	var l := Game.road_level(x, z)
	var found := -1
	for i in 4:
		var d := DIRS[i]
		if Game.knd(x + d.x, z + d.y) == Game.K.ROAD and Game.road_level(x + d.x, z + d.y) == l + 1:
			if found >= 0:
				return -1
			found = i
	if found < 0:
		return -1
	# side links at the same level would make it a junction, not a ramp
	for s in [(found + 1) % 4, (found + 3) % 4]:
		var d := DIRS[s]
		if Game.knd(x + d.x, z + d.y) == Game.K.ROAD and Game.road_level(x + d.x, z + d.y) == l:
			return -1
	return found


## Height of the road surface at a local point inside the tile (relative to the tile top).
static func road_height(x: int, z: int, local: Vector2) -> float:
	var rd := ramp_dir(x, z)
	var base := Game.LEVEL_Y[Game.road_level(x, z)] - Game.tile_y(x, z)
	if rd < 0:
		return base
	var d := DIRS[rd]
	var t := (local.x * d.x + local.y * d.y + H) / (2.0 * H)
	var rise := Game.LEVEL_Y[Game.road_level(x, z) + 1] - Game.LEVEL_Y[Game.road_level(x, z)]
	return base + clampf(t, 0.0, 1.0) * rise


static func _road(mk: MeshKit, x: int, z: int, root: Node3D, mat: Material) -> void:
	var links := road_links(x, z)
	var count := 0
	for b in links:
		if b: count += 1
	var water := Game.lvl(x, z) == 0
	var lift := Game.LEVEL_Y[Game.road_level(x, z)] - Game.tile_y(x, z)
	var rd := ramp_dir(x, z)
	if rd >= 0:
		_ramp(mk, x, z, rd, links)
		return
	mk.push_at(Vector3(0, lift, 0))
	var w := 0.62  # half width of asphalt
	var rs := Game.sub(x, z)
	# cobbled lanes swap the asphalt for setts; avenues are a touch darker
	var top := ASPHALT
	var te := 0.0
	if rs == Game.ROAD_SUB.LANE:
		top = Color(0.64, 0.6, 0.55)
		te = MeshKit.COBBLE
	elif rs == Game.ROAD_SUB.AVENUE:
		top = ASPHALT.darkened(0.08)
	if water:
		# bridge deck with rails and pillars down to the sea floor
		var deck := Color(0.9, 0.86, 0.8)
		mk.rbox(Vector3(0, -0.07, 0), Vector3(2.0, 0.14, 2.0), 0.04, deck)
		var depth := lift + 0.1
		for px in [-0.75, 0.75]:
			for pz in [-0.75, 0.75]:
				mk.pole(Vector3(px, -depth - 0.1, pz), 0.12, depth, 8, deck.darkened(0.15))
		for i in 4:
			if not links[i]:
				var d := DIRS[i]
				var side := Vector3(d.x, 0, d.y) * 0.92
				var along := Vector3(absf(d.y), 0, absf(d.x)) * 2.0
				mk.rbox(side + Vector3(0, 0.12, 0), along + Vector3(absf(d.x), 0, absf(d.y)) * 0.1 + Vector3(0, 0.2, 0), 0.04, Color(1, 1, 1))
	# asphalt: centre plus every linked arm
	if water:
		mk.box(Vector3(0, 0.03, 0), Vector3(w * 2, 0.06, w * 2), top, null, false, te)
	else:
		_flat(mk, -w, -w, w, w, 0.06, top, te)
	for i in 4:
		if links[i]:
			var d := DIRS[i]
			var c := Vector3(d.x, 0, d.y) * (w + (H - w) * 0.5)
			var sz := Vector3(H - w if d.x != 0 else w * 2, 0.06, H - w if d.y != 0 else w * 2)
			if water:
				mk.box(c + Vector3(0, 0.03, 0), sz, top, null, false, te)
			else:
				_flat(mk, c.x - sz.x * 0.5, c.z - sz.z * 0.5, c.x + sz.x * 0.5, c.z + sz.z * 0.5, 0.06, top, te)
	if not water:
		# sidewalks fill everything else; only the curbs that can be seen get a face
		var open_side := []
		for i in 4:
			var d := DIRS[i]
			open_side.append(Game.knd(x + d.x, z + d.y) != Game.K.ROAD)
		for cx in [-1, 1]:
			for cz in [-1, 1]:
				_flat(mk, minf(cx * w, cx * H), minf(cz * w, cz * H), maxf(cx * w, cx * H), maxf(cz * w, cz * H), 0.1, SIDEWALK)
				var ix := 0 if cx > 0 else 2
				var iz := 1 if cz > 0 else 3
				if links[iz]:
					_curb(mk, Vector3(cx * w, 0, cz * w), Vector3(cx * H, 0, cz * w), Vector3(0, 0, -cz), 0.04)
				if links[ix]:
					_curb(mk, Vector3(cx * w, 0, cz * w), Vector3(cx * w, 0, cz * H), Vector3(-cx, 0, 0), 0.04)
				if open_side[ix]:
					_curb(mk, Vector3(cx * H, 0, cz * w), Vector3(cx * H, 0, cz * H), Vector3(cx, 0, 0), 0.0)
				if open_side[iz]:
					_curb(mk, Vector3(cx * w, 0, cz * H), Vector3(cx * H, 0, cz * H), Vector3(0, 0, cz), 0.0)
		for i in 4:
			if not links[i]:
				var d := DIRS[i]
				var a := Vector3(d.x, 0, d.y) * w
				var b := Vector3(d.x, 0, d.y) * H
				var t := Vector3(absf(d.y), 0, absf(d.x)) * w
				_flat(mk, minf(a.x, b.x) - t.x, minf(a.z, b.z) - t.z, maxf(a.x, b.x) + t.x, maxf(a.z, b.z) + t.z, 0.1, SIDEWALK)
				_curb(mk, a - t, a + t, -Vector3(d.x, 0, d.y), 0.04)
				if open_side[i]:
					_curb(mk, b - t, b + t, Vector3(d.x, 0, d.y), 0.0)
	# markings
	var paint := Color(0.97, 0.95, 0.88)
	var straight: bool = count == 2 and ((links[0] and links[2]) or (links[1] and links[3]))
	if rs == Game.ROAD_SUB.LANE:
		# no paint on cobbles: lanterns and flower pots instead
		if not water:
			var sgn := 1.0 if (x + z) % 2 == 0 else -1.0
			var lp := Vector3(0.9, 0.1, 0.9 * sgn) if (links[1] or links[3]) and not (links[0] or links[2]) else Vector3(0.9 * sgn, 0.1, 0.9)
			if straight and (links[1] and links[3]):
				lp = Vector3(0.92 * sgn, 0.1, 0.0)
			elif straight:
				lp = Vector3(0.0, 0.1, 0.92 * sgn)
			_lantern(mk, lp)
			if Game.hash2(x, z, 82) % 2 == 0:
				mk.pole(-lp * Vector3(1, 0, 1) * 0.98 + Vector3(0, 0.1, 0), 0.06, 0.1, 6, Color("c9774b"))
				mk.blob(-lp * Vector3(1, 0, 1) * 0.98 + Vector3(0, 0.24, 0), Vector3(0.07, 0.06, 0.07), pick(FLOWERS, x, z, 83))
		mk.pop()
		return
	if rs == Game.ROAD_SUB.AVENUE and straight and not water:
		# a planted median with little trees, lane lines either side, lamps both sides
		var ax: bool = links[0]
		var along := Vector3(1, 0, 0) if ax else Vector3(0, 0, 1)
		var across := Vector3(along.z, 0, along.x)
		mk.box_faces(Vector3(0, 0.1, 0), along * 2.0 + across * 0.18 + Vector3(0, 0.08, 0), SIDEWALK.darkened(0.04), MeshKit.TOP | (MeshKit.FRONT | MeshKit.BACK if ax else MeshKit.LEFT | MeshKit.RIGHT))
		mk.box_faces(Vector3(0, 0.145, 0), along * 1.96 + across * 0.13, Color("6fa84e"), MeshKit.TOP)
		for k in 2:
			var tp := along * (-0.5 + k * 1.0) + Vector3(0, 0.14, 0)
			if (x + z + k) % 2 == 0:
				_round_tree(mk, tp, 0.34, pick(LEAF, x, z, 84 + k))
			else:
				mk.blob(tp + Vector3(0, 0.08, 0), Vector3(0.12, 0.08, 0.12), pick(FLOWERS, x, z, 86 + k), 0.04)
		for sgn in [-1.0, 1.0]:
			for k in 2:
				var o := -0.5 + k * 1.0
				_paint(mk, along * o + across * 0.58 * sgn + Vector3(0, 0.062, 0), Vector2(0.4, 0.03) if ax else Vector2(0.03, 0.4), paint)
			if (x + z) % 2 == 0:
				_lamp(mk, across * 0.86 * sgn + Vector3(0, 0.1, 0))
		mk.pop()
		return
	if straight:
		var along_x: bool = links[0]
		for k in 3:
			var o := -0.66 + k * 0.66
			var p := Vector3(o, 0.062, 0) if along_x else Vector3(0, 0.062, o)
			_paint(mk, p, Vector2(0.34, 0.05) if along_x else Vector2(0.05, 0.34), paint)
	elif count >= 3:
		for i in 4:
			if links[i]:
				var d := DIRS[i]
				for k in 5:
					var o := -0.48 + k * 0.24
					var p := Vector3(d.x * 0.8, 0.062, d.y * 0.8) + Vector3(d.y, 0, d.x) * o
					_paint(mk, p, Vector2(0.24 if d.x != 0 else 0.12, 0.12 if d.x != 0 else 0.24), paint)
	elif count == 2:
		# corner: a little curved dash at the centre
		_paint(mk, Vector3(0, 0.062, 0), Vector2(0.12, 0.12), paint)
	elif count == 0:
		# lonely road piece: a round little plaza
		mk.cylinder(Vector3(0, 0.0, 0), 0.5, 0.07, 14, SIDEWALK.darkened(0.05))
	# street lamps on some corners (every corner along an avenue)
	if not water and (Game.hash2(x, z, 77) % 3 == 0 or rs == Game.ROAD_SUB.AVENUE):
		var corner := Vector3(0.82, 0.1, 0.82) * Vector3([-1, 1][Game.hash2(x, z, 78) % 2], 1, [-1, 1][Game.hash2(x, z, 79) % 2])
		_lamp(mk, corner)
	# a tree in the empty sidewalk of dead ends
	if not water and count == 1 and Game.hash2(x, z, 80) % 2 == 0:
		for i in 4:
			if links[i]:
				var d := DIRS[(i + 2) % 4]
				_round_tree(mk, Vector3(d.x, 0, d.y) * 0.78 + Vector3(0, 0.1, 0), 0.55, LEAF[Game.hash2(x, z, 81) % LEAF.size()])
				break
	mk.pop()


static func _ramp(mk: MeshKit, x: int, z: int, rd: int, _links: Array) -> void:
	var d := DIRS[rd]
	var rise := Game.LEVEL_Y[Game.road_level(x, z) + 1] - Game.LEVEL_Y[Game.road_level(x, z)]
	mk.push_at(Vector3.ZERO, atan2(d.x, d.y))
	# local +Z climbs. Asphalt slab, side curbs and earth fill beneath.
	var a := Vector3(-0.62, 0.06, -H)
	var b := Vector3(0.62, 0.06, -H)
	var c := Vector3(0.62, 0.06 + rise, H)
	var e := Vector3(-0.62, 0.06 + rise, H)
	var n := Vector3(0, 2.0, -rise).normalized()
	mk.quad(a, b, c, e, n, ASPHALT)
	for s in [-1.0, 1.0]:
		var x0: float = s * 0.62
		var x1: float = s * H
		var top0 := 0.1
		var top1 := 0.1 + rise
		mk.quad(Vector3(x0, top0, -H), Vector3(x1, top0, -H), Vector3(x1, top1, H), Vector3(x0, top1, H), n, SIDEWALK)
		# outer face down to the ground
		var out := Vector3(s, 0, 0)
		mk.quad(Vector3(x1, top0, -H), Vector3(x1, top1, H), Vector3(x1, 0, H), Vector3(x1, 0, -H), out, Color(0.74, 0.64, 0.5))
		mk.quad(Vector3(x0, 0.06, -H), Vector3(x0, 0.06 + rise, H), Vector3(x0, top1, H), Vector3(x0, top0, -H), -out, SIDEWALK.darkened(0.1))
	mk.quad(Vector3(-H, 0, H), Vector3(H, 0, H), Vector3(H, 0.1 + rise, H), Vector3(-H, 0.1 + rise, H), Vector3.BACK, Color(0.74, 0.64, 0.5))
	for k in 3:
		var t := 0.2 + k * 0.3
		mk.box(Vector3(0, 0.07 + rise * t, -H + 2.0 * H * t), Vector3(0.05, 0.01, 0.3), Color(0.97, 0.95, 0.88))
	mk.pop()


## Upward rectangle at height y (x0..x1, z0..z1).
static func _flat(mk: MeshKit, x0: float, z0: float, x1: float, z1: float, y: float, col: Color, e := 0.0) -> void:
	var was := mk.shadow
	mk.shadow = false
	mk.quad(Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z1), Vector3.UP, col, e)
	mk.shadow = was


## Sidewalk curb face from a to b (on the ground plane), facing `out`, down to `bottom`.
static func _curb(mk: MeshKit, a: Vector3, b: Vector3, out: Vector3, bottom: float) -> void:
	var was := mk.shadow
	mk.shadow = false
	mk.quad(a + Vector3(0, bottom, 0), b + Vector3(0, bottom, 0), b + Vector3(0, 0.1, 0), a + Vector3(0, 0.1, 0), out, SIDEWALK.darkened(0.06))
	mk.shadow = was


## Road paint: a flat decal quad just above the asphalt, never in the shadow pass.
static func _paint(mk: MeshKit, p: Vector3, size: Vector2, col: Color) -> void:
	var hx := size.x * 0.5
	var hz := size.y * 0.5
	var y := p.y + 0.003
	mk.detail = true
	mk.quad(Vector3(p.x - hx, y, p.z - hz), Vector3(p.x + hx, y, p.z - hz), Vector3(p.x + hx, y, p.z + hz), Vector3(p.x - hx, y, p.z + hz), Vector3.UP, col)
	mk.detail = false


## Black iron lantern on a post, for the old cobbled lanes.
static func _lantern(mk: MeshKit, p: Vector3) -> void:
	var iron := Color(0.18, 0.19, 0.22)
	mk.pole(p, 0.03, 0.78, 4, iron)
	mk.box(p + Vector3(0, 0.84, 0), Vector3(0.1, 0.11, 0.1), Color(1, 0.86, 0.58), null, false, 2.0)
	mk.cone(p + Vector3(0, 0.895, 0), 0.09, 0.08, 4, iron)


static func _lamp(mk: MeshKit, p: Vector3) -> void:
	mk.pole(p, 0.035, 0.9, 4, Color(0.25, 0.27, 0.3))
	mk.rbox(p + Vector3(0, 0.95, 0), Vector3(0.16, 0.12, 0.16), 0.04, Color(0.25, 0.27, 0.3))
	mk.box(p + Vector3(0, 0.88, 0), Vector3(0.12, 0.06, 0.12), Color(1, 0.9, 0.7), null, true, 2.0)


# ------------------------------------------------------------------ helpers

static func facing(x: int, z: int) -> int:
	var start := Game.hash2(x, z, 2) % 4
	for k in 4:
		var i := (start + k) % 4
		var d := DIRS[i]
		if Game.knd(x + d.x, z + d.y) == Game.K.ROAD:
			return i
	for k in 4:
		var i := (start + k) % 4
		var d := DIRS[i]
		if Game.lvl(x + d.x, z + d.y) < Game.lvl(x, z):
			return i
	return start


static func yaw_of(i: int) -> float:
	var d := DIRS[i]
	return atan2(d.x, d.y)


static func pick(arr: Array, x: int, z: int, salt: int) -> Color:
	return arr[Game.hash2(x, z, salt) % arr.size()]


static func coastal(x: int, z: int) -> bool:
	if Game.lvl(x, z) == 1:
		return true
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			if Game.inside(x + dx, z + dz) and Game.lvl(x + dx, z + dz) == 0:
				return true
	return false


static func joined(x: int, z: int, dir: int, k: int) -> bool:
	var d := DIRS[dir]
	var nx := x + d.x
	var nz := z + d.y
	return Game.knd(nx, nz) == k and Game.lvl(nx, nz) == Game.lvl(x, z) and Game.grw(nx, nz) >= 1


static func density(x: int, z: int) -> int:
	var n := 0
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			var k := Game.knd(x + dx, z + dz)
			if k == Game.K.OFFICE:
				n += 2
			elif k == Game.K.HOUSE or k == Game.K.SHOP:
				n += 1
	return n


## World direction index -> the matching axis in a building's local frame
## (local +Z faces DIRS[f]; local +X is DIRS[(f + 3) % 4]).
static func local_dir(f: int, i: int) -> Vector3:
	return [Vector3.BACK, Vector3.LEFT, Vector3.FORWARD, Vector3.RIGHT][(i - f + 4) % 4]


## A side street: the road beside the building, if it stands on a corner.
static func side_street(x: int, z: int, f: int) -> int:
	for i in [(f + 1) % 4, (f + 3) % 4]:
		var d := DIRS[i]
		if Game.knd(x + d.x, z + d.y) == Game.K.ROAD:
			return i
	return -1


## Direction towards the nearest open water within `r` tiles, or -1.
static func sea_dir(x: int, z: int, r := 3) -> int:
	var best := -1
	var best_d := 1e9
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if (dx != 0 or dz != 0) and Game.inside(x + dx, z + dz) and Game.lvl(x + dx, z + dz) == 0:
				var dd := float(dx * dx + dz * dz)
				if dd < best_d:
					best_d = dd
					best = (0 if dx > 0 else 2) if absi(dx) >= absi(dz) else (1 if dz > 0 else 3)
	return best


## Neighbourhoods share a look: tiles a few streets apart fall into the same
## district (with wobbly borders), and each district has its own palette.
static func district(x: int, z: int) -> int:
	var wx := x + int(round(sin(z * 0.61 + Game.seed_value) * 1.6))
	var wz := z + int(round(sin(x * 0.53 - Game.seed_value) * 1.6))
	return Game.hash2(int(floor(wx / 5.0)), int(floor(wz / 5.0)), 321) % DISTRICTS.size()


static func district_wall(x: int, z: int, salt: int) -> Color:
	var pal: Array = DISTRICTS[district(x, z)][0]
	var c: Color = pal[Game.hash2(x, z, salt) % pal.size()]
	# no two houses quite the same
	return c.lightened(Game.hashf(x, z, salt + 1) * 0.06)


static func district_roof(x: int, z: int, salt: int) -> Color:
	var pal: Array = DISTRICTS[district(x, z)][1]
	return pal[Game.hash2(x, z, salt) % pal.size()]


## Count of tiles of kind `k` (optionally a sub-type) in the 8 around (x, z).
static func around(x: int, z: int, k: int, s := -1) -> int:
	var n := 0
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			if (dx != 0 or dz != 0) and Game.knd(x + dx, z + dz) == k and (s < 0 or Game.sub(x + dx, z + dz) == s):
				n += 1
	return n


## Same kind and sub-type next door in direction i (for things that join up).
static func same(x: int, z: int, i: int) -> bool:
	var d := DIRS[i]
	return Game.knd(x + d.x, z + d.y) == Game.knd(x, z) and Game.sub(x + d.x, z + d.y) == Game.sub(x, z) and Game.lvl(x + d.x, z + d.y) == Game.lvl(x, z)


static func _round_tree(mk: MeshKit, p: Vector3, s: float, col: Color) -> void:
	mk.pole(p, 0.05 * s / 0.6, 0.35 * s / 0.6, 4, Color(0.5, 0.36, 0.25))
	mk.blob(p + Vector3(0, 0.55 * s / 0.6, 0), Vector3(0.32, 0.36, 0.32) * s / 0.6, col, 0.06)


static func _pine(mk: MeshKit, p: Vector3, s: float, col: Color) -> void:
	mk.pole(p, 0.05 * s, 0.25 * s, 6, Color(0.45, 0.32, 0.22))
	for k in 3:
		mk.cone(p + Vector3(0, (0.2 + k * 0.28) * s, 0), (0.42 - k * 0.1) * s, 0.5 * s, 9, col.lightened(k * 0.05))


static func _palm(mk: MeshKit, p: Vector3, s: float, seed_i: int, toward := -1) -> void:
	var lean := Vector3(sin(seed_i * 1.7), 0, cos(seed_i * 1.7)) * 0.07
	if toward >= 0:
		# palms lean out towards the sea, each a little differently
		lean = (Vector3(DIRS[toward].x, 0, DIRS[toward].y) * 0.09 + lean * 0.35) * (0.8 + (seed_i % 10) * 0.04)
	var pos := p
	for k in 5:
		mk.pole(pos, 0.055 * s - k * 0.004, 0.24 * s, 6, Color(0.66, 0.52, 0.36).darkened(k % 2 * 0.06))
		pos += Vector3(0, 0.24 * s, 0) + lean * (k + 1) * s
	var green := Color("5fae4e")
	for f in 6:
		var a := TAU * f / 6.0 + seed_i
		var dir := Vector3(cos(a), 0, sin(a))
		mk.push(Transform3D(Basis.looking_at(-dir, Vector3.UP).rotated(Vector3(dir.z, 0, -dir.x), 0.45), pos + dir * 0.28 * s))
		# a frond is a thin leaf: its top and underside are all that ever shows
		var fc := green.darkened(f % 2 * 0.08)
		var hw := 0.09 * s
		var hl := 0.31 * s
		mk.quad(Vector3(-hw, -0.032, -hl), Vector3(hw, -0.032, -hl), Vector3(hw, -0.032, hl), Vector3(-hw, -0.032, hl), Vector3.UP, fc)
		var sh := mk.shadow
		mk.shadow = false
		mk.quad(Vector3(-hw, -0.068, -hl), Vector3(hw, -0.068, -hl), Vector3(hw, -0.068, hl), Vector3(-hw, -0.068, hl), Vector3.DOWN, fc.darkened(0.15))
		mk.shadow = sh
		mk.pop()
	mk.blob(pos, Vector3(0.09, 0.08, 0.09) * s, Color(0.55, 0.4, 0.25))


static func _plot(mk: MeshKit, col: Color) -> void:
	mk.rbox(Vector3(0, 0.03, 0), Vector3(1.96, 0.06, 1.96), 0.03, col)


static func _windows_row(mk: MeshKit, y: float, w: float, d: float, count_front: int, count_side: int, glass: Color, frame: Color, sides := [true, true, true, true], ww := 0.22, wh := 0.3) -> void:
	# sides: front(+z), right(+x), back(-z), left(-x); each side is one quad of windows
	var framed := frame.a > 0.0
	if sides[0]:
		mk.window_row(Vector3(0, y, d * 0.5), Vector3.BACK, w, count_front, ww, wh, glass, framed)
	if sides[2]:
		mk.window_row(Vector3(0, y, -d * 0.5), Vector3.FORWARD, w, count_front, ww, wh, glass, framed)
	if sides[1]:
		mk.window_row(Vector3(w * 0.5, y, 0), Vector3.RIGHT, d, count_side, ww, wh, glass, framed)
	if sides[3]:
		mk.window_row(Vector3(-w * 0.5, y, 0), Vector3.LEFT, d, count_side, ww, wh, glass, framed)


static func _lot(mk: MeshKit, x: int, z: int) -> void:
	# construction site: dirt, timber frame, fence posts. Tells players "needs a road".
	mk.rbox(Vector3(0, 0.03, 0), Vector3(1.9, 0.06, 1.9), 0.03, Color(0.74, 0.62, 0.47))
	var wood := Color(0.86, 0.7, 0.48)
	for k in 8:
		var a := TAU * k / 8.0
		var p := Vector3(cos(a), 0, sin(a)) * 0.85
		p = p.clamp(Vector3(-0.85, 0, -0.85), Vector3(0.85, 0, 0.85))
		mk.box(p + Vector3(0, 0.15, 0), Vector3(0.05, 0.22, 0.05), wood)
	mk.box(Vector3(0, 0.22, 0.85), Vector3(1.7, 0.04, 0.03), Color(1, 0.55, 0.3))
	mk.box(Vector3(0, 0.22, -0.85), Vector3(1.7, 0.04, 0.03), Color(1, 0.55, 0.3))
	mk.box(Vector3(0.85, 0.22, 0), Vector3(0.03, 0.04, 1.7), Color(1, 0.55, 0.3))
	mk.box(Vector3(-0.85, 0.22, 0), Vector3(0.03, 0.04, 1.7), Color(1, 0.55, 0.3))
	for px in [-0.4, 0.4]:
		for pz in [-0.4, 0.4]:
			mk.box(Vector3(px, 0.4, pz), Vector3(0.06, 0.7, 0.06), wood)
	mk.box(Vector3(0, 0.76, -0.4), Vector3(0.86, 0.06, 0.06), wood)
	mk.box(Vector3(0, 0.76, 0.4), Vector3(0.86, 0.06, 0.06), wood)
	# little "needs road" sign
	mk.box(Vector3(0.6, 0.3, 0.7), Vector3(0.04, 0.5, 0.04), wood)
	mk.rbox(Vector3(0.6, 0.58, 0.72), Vector3(0.36, 0.22, 0.04), 0.02, Color(1, 0.8, 0.3))
	mk.box(Vector3(0.6, 0.58, 0.745), Vector3(0.22, 0.04, 0.01), Color(0.3, 0.3, 0.35))
	mk.rbox(Vector3(-0.5, 0.12, 0.55), Vector3(0.3, 0.18, 0.3), 0.05, Color(0.8, 0.78, 0.74))


# ------------------------------------------------------------------ shops

static func _shop(mk: MeshKit, x: int, z: int) -> void:
	var g := Game.grw(x, z)
	if g == 0:
		_lot(mk, x, z)
		return
	var f := facing(x, z)
	var awn := pick(AWNINGS, x, z, 30)
	var wall := pick(WALLS + BRICK, x, z, 31)
	var jl := joined(x, z, (f + 3) % 4, Game.K.SHOP) or joined(x, z, (f + 3) % 4, Game.K.HOUSE)
	var jr := joined(x, z, (f + 1) % 4, Game.K.SHOP) or joined(x, z, (f + 1) % 4, Game.K.HOUSE)
	mk.push_at(Vector3.ZERO, yaw_of(f))
	_plot(mk, SIDEWALK)
	var w := 1.6
	var d := 1.4
	var x0 := -w * 0.5
	var x1 := w * 0.5
	if jr: x0 = -H
	if jl: x1 = H
	w = x1 - x0
	var cx := (x0 + x1) * 0.5
	var floors := 1 if g == 1 else (2 + Game.hash2(x, z, 32) % 2 if g == 2 else 3 + Game.hash2(x, z, 32) % 2)
	var fh := 0.66
	var hgt := floors * fh + 0.2
	mk.push_at(Vector3(cx, 0, -0.15))
	mk.rbox_walls(Vector3(0, 0.06 + hgt * 0.5, 0), Vector3(w, hgt, d), 0.05, wall)
	# shop front: big lit display windows, door, sign and striped awning
	var sf := d * 0.5
	mk.rbox(Vector3(0, 0.45, sf + 0.01), Vector3(w - 0.12, 0.72, 0.04), 0.02, awn.darkened(0.35))
	for s in [-1, 1]:
		mk.window(Vector3(s * w * 0.26, 0.45, sf + 0.02), Vector3.BACK, w * 0.36, 0.5, GLASS_LIGHT, Color(0, 0, 0, 0), false)
	mk.rbox(Vector3(0, 0.36, sf + 0.04), Vector3(0.24, 0.5, 0.04), 0.02, Color(0.95, 0.93, 0.88))
	mk.window(Vector3(0, 0.4, sf + 0.06), Vector3.BACK, 0.14, 0.34, GLASS_LIGHT, Color(0, 0, 0, 0), true)
	# awning stripes
	var stripes := 7
	var aw := w - 0.1
	for k in stripes:
		var col := awn if k % 2 == 0 else Color(0.98, 0.97, 0.94)
		var sx := -aw * 0.5 + (k + 0.5) * aw / stripes
		var p0 := Vector3(sx, 0.9, sf + 0.02)
		mk.push(Transform3D(Basis(Vector3.RIGHT, 0.5), p0))
		# neighbouring stripes hide each other's sides; the back meets the wall
		mk.box_faces(Vector3(0, 0, 0.2), Vector3(aw / stripes, 0.03, 0.42), col, MeshKit.TOP | MeshKit.FRONT | (MeshKit.LEFT if k == 0 else 0) | (MeshKit.RIGHT if k == stripes - 1 else 0))
		mk.pop()
	mk.box_faces(Vector3(0, 0.74, sf + 0.38), Vector3(aw, 0.08, 0.02), awn, MeshKit.FRONT | MeshKit.BACK | MeshKit.TOP)
	# on a corner the shop front wraps round onto the side street
	var sd := side_street(x, z, f)
	if sd >= 0:
		var ld := local_dir(f, sd)
		if (ld.x > 0.0 and not jl) or (ld.x < 0.0 and not jr):
			var sx := ld.x * w * 0.5
			mk.window(Vector3(sx, 0.45, 0.05), ld, d * 0.6, 0.5, GLASS_LIGHT, Color(0, 0, 0, 0), false)
			mk.push(Transform3D(Basis(Vector3.BACK, -ld.x * 0.5), Vector3(sx, 0.9, 0.05)))
			mk.box_faces(Vector3(ld.x * 0.2, 0, 0), Vector3(0.42, 0.03, d * 0.72), awn, MeshKit.TOP | (MeshKit.RIGHT if ld.x > 0.0 else MeshKit.LEFT))
			mk.pop()
	# sign board
	mk.rbox(Vector3(0, 1.08, sf + 0.04), Vector3(w * 0.6, 0.2, 0.06), 0.04, Color(0.98, 0.95, 0.86))
	mk.box_faces(Vector3(0, 1.08, sf + 0.075), Vector3(w * 0.45, 0.07, 0.01), awn.darkened(0.2), MeshKit.FRONT, 2.0)
	# upper floors
	for fl in range(1, floors):
		var yy := 0.2 + fl * fh + fh * 0.5
		_windows_row(mk, yy, w, d, 3, 2, GLASS, FRAME, [true, not jl, true, not jr])
		if g == 2 and fl == 1:
			for s in [-1, 0, 1]:
				mk.blob(Vector3(s * w * 0.32, yy - 0.2, sf + 0.06), Vector3(0.1, 0.06, 0.06), Color("e86a6a").lerp(Color("6fb35a"), 0.6))
	var top := 0.06 + hgt
	mk.ledge(Vector3(0, top + 0.05, 0), Vector3(w + 0.05, 0.1, d + 0.05), 0.03, wall.lightened(0.15))
	if g == 3:
		# rooftop billboard
		mk.box(Vector3(0, top + 0.3, -0.2), Vector3(0.04, 0.5, 0.04), Color(0.3, 0.3, 0.32))
		mk.rbox(Vector3(0, top + 0.6, -0.2), Vector3(w * 0.7, 0.36, 0.06), 0.03, awn)
		mk.box(Vector3(0, top + 0.6, -0.165), Vector3(w * 0.5, 0.12, 0.01), Color(1, 1, 1), null, false, 2.0)
	else:
		mk.rbox(Vector3(w * 0.25, top + 0.155, -0.25), Vector3(0.3, 0.19, 0.3), 0.04, Color(0.82, 0.84, 0.86))
	mk.pop()
	# café table outside
	if g <= 2 and Game.hashf(x, z, 33) > 0.35:
		var tz := 0.82
		mk.cylinder(Vector3(cx + 0.4, 0.06, tz), 0.15, 0.24, 8, Color(0.95, 0.95, 0.95))
		mk.pole(Vector3(cx + 0.4, 0.06, tz), 0.02, 0.62, 5, Color(0.4, 0.4, 0.4))
		mk.cone(Vector3(cx + 0.4, 0.62, tz), 0.36, 0.16, 10, awn)
	mk.pop()


# ------------------------------------------------------------------ offices

static func _office(mk: MeshKit, x: int, z: int) -> void:
	var g := Game.grw(x, z)
	if g == 0:
		_lot(mk, x, z)
		return
	var f := facing(x, z)
	mk.push_at(Vector3.ZERO, yaw_of(f))
	_plot(mk, SIDEWALK.lightened(0.05))
	var dens := density(x, z)
	var tone := pick([Color("dfe6ec"), Color("c9d6e0"), Color("e8e2d6"), Color("f2d9c4"), Color("cfe3d6"), Color("e9c9b5"), Color("f0ece4")], x, z, 40)
	var corner := 0.05 if Game.hash2(x, z, 44) % 3 != 0 else 0.28
	var glass := pick([Color(0.36, 0.55, 0.7), Color(0.3, 0.55, 0.58), Color(0.42, 0.6, 0.72), Color(0.52, 0.45, 0.38)], x, z, 41)
	var fh := 0.5
	var floors := 3
	if g == 2:
		floors = 5 + Game.hash2(x, z, 42) % 4 + mini(3, dens / 6)
	elif g == 3:
		floors = 9 + Game.hash2(x, z, 42) % 7 + mini(5, dens / 4)
	var w := 1.6
	var d := 1.6
	var y := 0.06
	# podium lobby
	mk.rbox(Vector3(0, y + 0.3, 0), Vector3(w + 0.1, 0.6, d + 0.1), 0.05, tone.darkened(0.1))
	mk.window(Vector3(0, y + 0.3, (d + 0.1) * 0.5), Vector3.BACK, w * 0.8, 0.42, GLASS_LIGHT, Color(0, 0, 0, 0), true)
	y += 0.6
	var tiers := 1 if g < 3 else 3
	var remaining := floors - 1
	for t in tiers:
		var nf := remaining if t == tiers - 1 else int(remaining * (0.55 if t == 0 else 0.6))
		remaining -= nf
		var hh := nf * fh
		mk.rbox_walls(Vector3(0, y + hh * 0.5, 0), Vector3(w, hh, d), corner, tone)
		var cols := 3 if w > 1.2 else 2
		for fl in nf:
			var yy := y + fl * fh + fh * 0.5
			if g == 1:
				# ribbon windows
				for side in 4:
					var out: Vector3 = [Vector3.BACK, Vector3.RIGHT, Vector3.FORWARD, Vector3.LEFT][side]
					var c: Vector3 = out * (d * 0.5 if side % 2 == 0 else w * 0.5)
					mk.window(c + Vector3(0, yy, 0), out, (w if side % 2 == 0 else d) * 0.86, fh * 0.5, glass)
			else:
				_windows_row(mk, yy, w, d, cols + 1, cols + 1, glass, Color(0, 0, 0, 0), [true, true, true, true], w / (cols + 1) * 0.78, fh * 0.7)
		# mullion lines between floors
		mk.bands(y + fh, w, d, fh, nf - 1, 0.03, tone.lightened(0.2))
		y += hh
		mk.ledge(Vector3(0, y + 0.04, 0), Vector3(w + 0.06, 0.08, d + 0.06), 0.03, tone.lightened(0.25))
		y += 0.08
		w *= 0.78
		d *= 0.78
	if g == 3:
		# every skyline needs different crowns
		match Game.hash2(x, z, 45) % 4:
			0:
				mk.cylinder(Vector3(0, y, 0), 0.06, 0.9, 6, Color(0.8, 0.82, 0.85), true, null, 0.02)
				mk.blob(Vector3(0, y + 0.92, 0), Vector3(0.06, 0.06, 0.06), Color(1, 0.25, 0.2), 0.0, 2.0)
			1:
				# helipad
				mk.cylinder(Vector3(0, y, 0), minf(w, d) * 0.45, 0.05, 12, Color(0.32, 0.34, 0.38))
				mk.detail = true
				var hy := y + 0.056
				for s in [-1, 1]:
					mk.quad(Vector3(s * 0.12 - 0.025, hy, -0.15), Vector3(s * 0.12 + 0.025, hy, -0.15), Vector3(s * 0.12 + 0.025, hy, 0.15), Vector3(s * 0.12 - 0.025, hy, 0.15), Vector3.UP, Color(0.97, 0.95, 0.88))
				mk.quad(Vector3(-0.1, hy, -0.025), Vector3(0.1, hy, -0.025), Vector3(0.1, hy, 0.025), Vector3(-0.1, hy, 0.025), Vector3.UP, Color(0.97, 0.95, 0.88))
				mk.detail = false
			2:
				# a lit crown that glows over the city at night
				mk.box_faces(Vector3(0, y + 0.2, 0), Vector3(w * 0.9, 0.3, d * 0.9), glass.lightened(0.3), MeshKit.FRONT | MeshKit.BACK | MeshKit.LEFT | MeshKit.RIGHT, 2.0)
				mk.box_faces(Vector3(0, y + 0.36, 0), Vector3(w * 0.9, 0.02, d * 0.9), tone, MeshKit.TOP)
				mk.cylinder(Vector3(0, y + 0.36, 0), 0.04, 0.5, 5, Color(0.85, 0.86, 0.9), false, null, 0.01)
			_:
				# stepped glass top
				mk.rbox(Vector3(0, y + 0.2, 0), Vector3(w * 0.7, 0.4, d * 0.7), 0.04, glass.lightened(0.15))
				mk.rbox(Vector3(0, y + 0.5, 0), Vector3(w * 0.4, 0.2, d * 0.4), 0.04, tone)
	else:
		mk.rbox(Vector3(-0.2, y + 0.135, 0.1), Vector3(0.4, 0.19, 0.3), 0.04, Color(0.75, 0.77, 0.8))
		mk.pole(Vector3(0.3, y, -0.3), 0.04, 0.4, 5, Color(0.6, 0.6, 0.6))
	mk.pop()
	# little plaza trees
	_round_tree(mk, Vector3(-0.82, 0.06, 0.82), 0.35, pick(LEAF, x, z, 43))


# ------------------------------------------------------------------ parks & trees

static func _park(mk: MeshKit, x: int, z: int) -> void:
	mk.rbox(Vector3(0, 0.04, 0), Vector3(2.0, 0.08, 2.0), 0.03, Color(0.47, 0.76, 0.4))
	var path := Color(0.93, 0.87, 0.74)
	var linked := 0
	for i in 4:
		var d := DIRS[i]
		var k := Game.knd(x + d.x, z + d.y)
		if k == Game.K.PARK or k == Game.K.ROAD:
			linked += 1
			var c := Vector3(d.x, 0, d.y) * 0.5
			mk.box_faces(c + Vector3(0, 0.085, 0), Vector3(1.0 if d.x != 0 else 0.34, 0.012, 1.0 if d.y != 0 else 0.34), path, MeshKit.TOP)
	mk.cylinder(Vector3(0, 0.08, 0), 0.32, 0.015, 12, path)
	var r := Game.hash2(x, z, 50) % 4
	if r == 0:
		# pond with lily pads
		mk.cylinder(Vector3(0.45, 0.08, -0.45), 0.42, 0.02, 14, Color(0.36, 0.7, 0.85), true, null, -1.0, 3.0)
		for k in 3:
			mk.cylinder(Vector3(0.35 + k * 0.12, 0.1, -0.5 + (k % 2) * 0.15), 0.06, 0.01, 6, Color(0.4, 0.7, 0.35))
	else:
		_round_tree(mk, Vector3(0.55, 0.08, -0.55), 0.6, pick(LEAF, x, z, 51))
	_round_tree(mk, Vector3(-0.6, 0.08, -0.5), 0.5, pick(LEAF, x, z, 52))
	if r != 1:
		_round_tree(mk, Vector3(0.6, 0.08, 0.6), 0.45, pick(LEAF + AUTUMN, x, z, 53))
	# flower bed
	var fc := pick(AWNINGS, x, z, 54)
	for k in 5:
		mk.blob(Vector3(-0.65 + k * 0.08, 0.13, 0.55 + (k % 2) * 0.08), Vector3(0.06, 0.05, 0.06), fc if k % 2 == 0 else Color(1, 0.95, 0.6))
	# bench
	mk.rbox(Vector3(-0.1, 0.2, 0.5), Vector3(0.4, 0.04, 0.12), 0.015, Color(0.7, 0.5, 0.33))
	mk.rbox(Vector3(-0.1, 0.28, 0.56), Vector3(0.4, 0.12, 0.03), 0.01, Color(0.7, 0.5, 0.33))
	for s in [-1, 1]:
		mk.box(Vector3(-0.1 + s * 0.17, 0.14, 0.5), Vector3(0.03, 0.12, 0.1), Color(0.3, 0.3, 0.32))
	if Game.hash2(x, z, 55) % 2 == 0:
		_lamp(mk, Vector3(0.3, 0.08, 0.3))


static func _trees(mk: MeshKit, x: int, z: int) -> void:
	var l := Game.lvl(x, z)
	var count := 1 + (Game.prm(x, z) & 3) % 3 + (1 if l >= 2 else 0)
	var sd := sea_dir(x, z, 4) if l == 1 else -1
	for k in count:
		var p := Vector3(Game.hashf(x, z, 60 + k) * 1.3 - 0.65, 0.0, Game.hashf(x, z, 70 + k) * 1.3 - 0.65)
		var s := 0.5 + Game.hashf(x, z, 80 + k) * 0.35
		if l == 1:
			_palm(mk, p, s * 1.1, Game.hash2(x, z, 90 + k) % 100, sd)
		elif l >= 4 or (l == 3 and Game.hashf(x, z, 95 + k) > 0.5):
			_pine(mk, p, s * 1.3, pick([Color("3f7f4f"), Color("4b8b55"), Color("36704a")], x, z, 100 + k))
		else:
			var col := pick(LEAF, x, z, 110 + k)
			if Game.hashf(x, z, 120 + k) > 0.86:
				col = pick(AUTUMN, x, z, 130 + k)
			_round_tree(mk, p, s, col)
	if l >= 2 and Game.hashf(x, z, 140) > 0.6:
		mk.blob(Vector3(Game.hashf(x, z, 141) - 0.5, 0.06, Game.hashf(x, z, 142) - 0.5), Vector3(0.18, 0.12, 0.16), Color("5c9e4e"), 0.04)


# ------------------------------------------------------------------ landmarks

static func _landmark(mk: MeshKit, x: int, z: int, root: Node3D, mat: Material, beam_mat: Material) -> void:
	var t := Game.prm(x, z)
	var f := facing(x, z)
	match t:
		Game.LM.FOUNTAIN:
			mk.rbox(Vector3(0, 0.04, 0), Vector3(2.0, 0.08, 2.0), 0.03, Color(0.9, 0.86, 0.78))
			for k in 12:
				var a := TAU * k / 12.0
				mk.box(Vector3(cos(a) * 0.86, 0.09, sin(a) * 0.86), Vector3(0.14, 0.01, 0.14), Color(0.82, 0.76, 0.66))
			mk.cylinder(Vector3(0, 0.08, 0), 0.72, 0.22, 20, Color(0.92, 0.9, 0.86))
			mk.cylinder(Vector3(0, 0.26, 0), 0.64, 0.02, 20, Color(0.45, 0.78, 0.92), true, null, -1.0, 3.0)
			mk.cylinder(Vector3(0, 0.08, 0), 0.1, 0.7, 10, Color(0.92, 0.9, 0.86))
			mk.cylinder(Vector3(0, 0.6, 0), 0.32, 0.1, 16, Color(0.92, 0.9, 0.86))
			mk.cylinder(Vector3(0, 0.69, 0), 0.27, 0.02, 16, Color(0.5, 0.82, 0.95), true, null, -1.0, 3.0)
			mk.blob(Vector3(0, 0.95, 0), Vector3(0.1, 0.3, 0.1), Color(0.75, 0.92, 1.0), 0.0, 3.0)
			for k in 4:
				var a := TAU * k / 4.0 + PI / 4
				_round_tree(mk, Vector3(cos(a) * 0.85, 0.08, sin(a) * 0.85), 0.35, LEAF[k % LEAF.size()])
			_lamp(mk, Vector3(0.9, 0.08, 0))
			_lamp(mk, Vector3(-0.9, 0.08, 0))
			var spray := MeshKit.new()
			for k in 8:
				var a := TAU * k / 8.0
				spray.blob(Vector3(cos(a) * 0.42, 0.55, sin(a) * 0.42), Vector3(0.05, 0.12, 0.05), Color(0.85, 0.95, 1.0), 0.0, 3.0)
			_spinner(root, spray.commit(mat), Vector3(0, 0, 0), Vector3.UP, 0.8)
		Game.LM.LIGHTHOUSE:
			mk.rbox(Vector3(0, 0.1, 0), Vector3(1.5, 0.2, 1.5), 0.08, Color(0.72, 0.7, 0.66))
			var hgt := 3.4
			var seg := 5
			for k in seg:
				var r0 := 0.5 - k * 0.05
				var r1 := 0.5 - (k + 1) * 0.05
				var col := Color(0.97, 0.96, 0.93) if k % 2 == 0 else Color("d9534f")
				mk.cylinder(Vector3(0, 0.2 + k * hgt / seg, 0), r0, hgt / seg, 16, col, false, null, r1)
			var top := 0.2 + hgt
			mk.cylinder(Vector3(0, top, 0), 0.42, 0.08, 16, Color(0.25, 0.27, 0.3))
			mk.cylinder(Vector3(0, top + 0.08, 0), 0.24, 0.42, 12, Color(1, 0.9, 0.6), false, null, -1.0, 2.0)
			mk.cone(Vector3(0, top + 0.5, 0), 0.34, 0.36, 12, Color("d9534f"))
			mk.blob(Vector3(0, top + 0.9, 0), Vector3(0.06, 0.06, 0.06), Color(0.25, 0.27, 0.3))
			for k in 2:
				mk.window(Vector3(0, 1.0 + k * 1.2, 0.46 - k * 0.06), Vector3.BACK, 0.14, 0.22, GLASS, FRAME)
			mk.rbox(Vector3(0.75, 0.4, 0), Vector3(0.6, 0.6, 0.7), 0.05, Color(0.97, 0.96, 0.93))
			mk.push_at(Vector3(0.75, 0.7, 0), PI * 0.5)
			mk.gable_roof(Vector3.ZERO, 0.7, 0.6, 0.3, 0.06, Color("d9534f"), Color(0.97, 0.96, 0.93))
			mk.pop()
			# rotating light beam (visible at night): two soft cones fading toward the tips
			var beam := _beam_mesh(beam_mat)
			var bn := _spinner(root, beam, Vector3(0, top + 0.28, 0), Vector3.UP, 0.9)
			bn.set_meta("night_only", true)
			bn.set_meta("beam", true)
			bn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		Game.LM.WINDMILL:
			mk.rbox(Vector3(0, 0.05, 0), Vector3(1.7, 0.1, 1.7), 0.05, Color(0.62, 0.8, 0.45))
			mk.cylinder(Vector3(0, 0.1, 0), 0.62, 2.2, 14, Color(0.93, 0.9, 0.84), false, null, 0.42)
			mk.cone(Vector3(0, 2.3, 0), 0.52, 0.6, 14, Color("8b5a44"))
			mk.rbox(Vector3(0, 0.38, 0.55), Vector3(0.3, 0.56, 0.1), 0.04, DOOR)
			mk.window(Vector3(0, 1.4, 0.52), Vector3.BACK, 0.18, 0.24, GLASS, FRAME)
			mk.rbox(Vector3(0, 2.1, 0.5), Vector3(0.16, 0.16, 0.3), 0.04, Color(0.4, 0.3, 0.22))
			var blades := MeshKit.new()
			for k in 4:
				blades.push(Transform3D(Basis(Vector3.BACK, TAU * k / 4.0), Vector3.ZERO))
				blades.box(Vector3(0, 0.8, 0), Vector3(0.06, 1.6, 0.04), Color(0.45, 0.33, 0.24))
				blades.box(Vector3(0.14, 0.95, 0.0), Vector3(0.24, 1.15, 0.02), Color(0.97, 0.95, 0.9))
				blades.pop()
			blades.blob(Vector3.ZERO, Vector3(0.1, 0.1, 0.1), Color(0.35, 0.27, 0.2))
			var sp := _spinner(root, blades.commit(mat), Vector3(0, 2.1, 0.68), Vector3.BACK, 0.7, blades.commit_shadow(shadow_material()))
			var pv := sp.get_parent() as Node3D
			pv.rotation.y = yaw_of(f)
			pv.position = Vector3(sin(yaw_of(f)), 0, cos(yaw_of(f))) * 0.68 + Vector3(0, 2.1, 0)
			root.get_child(0).rotation.y = yaw_of(f)
		Game.LM.CLOCKTOWER:
			mk.rbox(Vector3(0, 0.04, 0), Vector3(2.0, 0.08, 2.0), 0.03, Color(0.86, 0.82, 0.74))
			var brick := Color("c97b5a")
			mk.rbox(Vector3(0, 0.08 + 1.6, 0), Vector3(0.9, 3.2, 0.9), 0.06, brick)
			for k in 4:
				mk.box(Vector3(0, 0.6 + k * 0.8, 0), Vector3(0.96, 0.06, 0.96), Color(0.95, 0.9, 0.82))
			var cy := 2.8
			for i in 4:
				var out: Vector3 = [Vector3.BACK, Vector3.RIGHT, Vector3.FORWARD, Vector3.LEFT][i]
				var c: Vector3 = out * 0.46 + Vector3(0, cy, 0)
				var xa: Vector3 = Vector3.UP.cross(out).normalized()
				mk.push(Transform3D(Basis(xa, out, xa.cross(out)), c))
				mk.cylinder(Vector3(0, 0, 0), 0.3, 0.04, 16, Color(0.98, 0.96, 0.9), true, null, -1.0, 2.0)
				mk.pop()
				mk.window(Vector3(0, 1.4, 0) + out * 0.45, out, 0.2, 0.4, GLASS, FRAME)
			mk.rbox(Vector3(0, 3.38, 0), Vector3(1.04, 0.16, 1.04), 0.04, Color(0.95, 0.9, 0.82))
			mk.hip_roof(Vector3(0, 3.46, 0), 0.96, 0.96, 1.1, 0.05, Color("4b5a70"))
			mk.pole(Vector3(0, 4.5, 0), 0.02, 0.4, 4, Color(0.9, 0.75, 0.3))
			for k in 4:
				var a := TAU * k / 4.0 + PI / 4
				mk.rbox(Vector3(cos(a) * 0.85, 0.3, sin(a) * 0.85), Vector3(0.3, 0.44, 0.3), 0.12, Color("5c9e4e"))
			# clock hands (two spinners per face would be heavy: one shared slow hand per face)
			for i in 4:
				var out: Vector3 = [Vector3.BACK, Vector3.RIGHT, Vector3.FORWARD, Vector3.LEFT][i]
				var hand := MeshKit.new()
				hand.box(Vector3(0, 0.1, 0), Vector3(0.03, 0.22, 0.01), Color(0.15, 0.15, 0.18))
				hand.box(Vector3(0.06, 0, 0), Vector3(0.14, 0.035, 0.01), Color(0.15, 0.15, 0.18))
				var hn := _spinner(root, hand.commit(mat), out * 0.49 + Vector3(0, cy, 0), Vector3.BACK, 0.15)
				hn.rotation.y = atan2(out.x, out.z)
		Game.LM.BANDSTAND:
			mk.rbox(Vector3(0, 0.04, 0), Vector3(2.0, 0.08, 2.0), 0.03, Color(0.47, 0.76, 0.4), null, false, MeshKit.MOWN_X)
			var path := Color(0.93, 0.87, 0.74)
			mk.cylinder(Vector3(0, 0.08, 0), 0.9, 0.01, 16, path)
			# octagonal stage on a brick base, eight slim columns and a green roof
			var green := Color("3f8a6a")
			mk.cylinder(Vector3(0, 0.08, 0), 0.62, 0.22, 8, Color("c97b5a"), true, Color(0.9, 0.84, 0.74), -1.0, MeshKit.BRICKS)
			for k in 3:
				mk.box(Vector3(0, 0.12 + k * 0.05, 0.66 - k * 0.07), Vector3(0.36, 0.05, 0.1), Color(0.86, 0.82, 0.76))
			for k in 8:
				var a := TAU * (k + 0.5) / 8.0
				mk.pole(Vector3(cos(a) * 0.54, 0.3, sin(a) * 0.54), 0.025, 0.62, 4, Color.WHITE)
			mk.cylinder(Vector3(0, 0.9, 0), 0.66, 0.06, 8, Color.WHITE)
			mk.cone(Vector3(0, 0.96, 0), 0.7, 0.42, 8, green)
			mk.blob(Vector3(0, 1.42, 0), Vector3(0.05, 0.05, 0.05), Color("f2c14e"))
			# bunting between the columns, lamps under the eaves for evening concerts
			for k in 8:
				var a := TAU * (k + 0.5) / 8.0
				var b := TAU * (k + 1.5) / 8.0
				var mid := Vector3(cos(a) + cos(b), 0, sin(a) + sin(b)) * 0.27 + Vector3(0, 0.8, 0)
				mk.blob(mid, Vector3(0.04, 0.04, 0.04), AWNINGS[k % AWNINGS.size()])
				mk.window(Vector3(cos(a) * 0.5, 0.86, sin(a) * 0.5), Vector3.DOWN, 0.06, 0.06, Color(1, 0.86, 0.55), Color(0, 0, 0, 0), true)
			for k in 4:
				var a := TAU * k / 4.0 + PI / 4.0
				ParkGen.bench(mk, Vector3(cos(a), 0, sin(a)) * 0.84 + Vector3(0, 0.08, 0), atan2(-cos(a), -sin(a)))
			_round_tree(mk, Vector3(0.82, 0.08, -0.82), 0.5, LEAF[0])
			_round_tree(mk, Vector3(-0.84, 0.08, 0.8), 0.45, LEAF[2])
		Game.LM.PIER:
			# runs from the shore out over the water; local +Z points out to sea
			var land := 0
			for i in 4:
				var d := DIRS[i]
				if Game.inside(x + d.x, z + d.y) and Game.lvl(x + d.x, z + d.y) >= 1:
					land = i
					break
			var lift := Game.LEVEL_Y[1] + 0.04 - Game.tile_y(x, z)
			var sea_y := -Game.tile_y(x, z)
			mk.push_at(Vector3(0, lift, 0), yaw_of((land + 2) % 4))
			var plank := Color(0.72, 0.56, 0.38)
			mk.box(Vector3(0, -0.03, -0.1), Vector3(0.7, 0.06, 1.8), plank, null, false, MeshKit.SIDING)
			mk.box(Vector3(0, -0.03, 0.62), Vector3(1.3, 0.06, 0.6), plank, null, false, MeshKit.SIDING)
			for pz in [-0.6, 0.0, 0.4, 0.85]:
				for px in [-0.32, 0.32] if pz < 0.3 else [-0.6, 0.6]:
					mk.pole(Vector3(px, -lift, pz), 0.04, lift - 0.03, 5, Color(0.45, 0.34, 0.25))
			for s in [-1.0, 1.0]:
				mk.box(Vector3(s * 0.34, 0.16, -0.4), Vector3(0.02, 0.02, 1.2), Color(0.95, 0.95, 0.92))
				mk.box(Vector3(s * 0.64, 0.16, 0.62), Vector3(0.02, 0.02, 0.56), Color(0.95, 0.95, 0.92))
				for k in 4:
					mk.box(Vector3(s * 0.34, 0.08, -0.95 + k * 0.4), Vector3(0.02, 0.16, 0.02), Color(0.95, 0.95, 0.92))
			# a striped kiosk at the end, lamps, a bench and a rowing boat tied up
			mk.rbox(Vector3(0.2, 0.22, 0.7), Vector3(0.5, 0.38, 0.36), 0.03, Color(0.98, 0.96, 0.9), null, false, MeshKit.SIDING)
			mk.window(Vector3(0.2, 0.26, 0.885), Vector3.BACK, 0.34, 0.16, GLASS_LIGHT, Color(0, 0, 0, 0), true)
			mk.cone(Vector3(0.2, 0.41, 0.7), 0.42, 0.22, 8, Color("e85d5d"))
			mk.blob(Vector3(0.2, 0.65, 0.7), Vector3(0.03, 0.03, 0.03), Color.WHITE)
			_lamp(mk, Vector3(-0.3, 0.0, -0.2))
			_lamp(mk, Vector3(-0.55, 0.0, 0.85))
			ParkGen.bench(mk, Vector3(-0.3, 0.0, 0.45), PI * 0.5)
			mk.push_at(Vector3(0.62, sea_y - lift + 0.02, -0.3), 0.15)
			mk.rbox(Vector3(0, 0.03, 0), Vector3(0.24, 0.08, 0.55), 0.04, Color("3f7cc4"), Color(0.72, 0.56, 0.38))
			mk.pop()
			mk.pop()
		Game.LM.OBSERVATORY:
			mk.rbox(Vector3(0, 0.04, 0), Vector3(2.0, 0.08, 2.0), 0.03, Color(0.84, 0.8, 0.72), null, false, MeshKit.PAVING)
			var stone := Color(0.95, 0.94, 0.9)
			# drum and white dome, the telescope peering out of an open slit
			mk.cylinder(Vector3(0, 0.08, 0), 0.62, 0.62, 16, stone)
			mk.cylinder(Vector3(0, 0.7, 0), 0.66, 0.06, 16, Color(0.8, 0.78, 0.74))
			mk.blob(Vector3(0, 0.74, 0), Vector3(0.58, 0.58, 0.58), Color(0.88, 0.9, 0.93))
			mk.push(Transform3D(Basis(Vector3.RIGHT, 0.75), Vector3(0, 1.0, 0.05)))
			mk.cylinder(Vector3(0, 0, 0), 0.09, 0.62, 8, Color(0.3, 0.33, 0.38))
			mk.cylinder(Vector3(0, 0.62, 0), 0.11, 0.06, 8, Color(0.2, 0.22, 0.26))
			mk.pop()
			mk.window_row(Vector3(0, 0.38, 0.62), Vector3.BACK, 0.6, 2, 0.14, 0.22, GLASS)
			mk.rbox(Vector3(0, 0.27, 0.63), Vector3(0.22, 0.38, 0.04), 0.02, DOOR)
			# a small study wing and a sundial
			mk.rbox(Vector3(-0.68, 0.3, -0.25), Vector3(0.5, 0.46, 0.6), 0.03, stone)
			mk.window(Vector3(-0.68, 0.32, 0.055), Vector3.BACK, 0.22, 0.2, GLASS, FRAME, true)
			mk.hip_roof(Vector3(-0.68, 0.53, -0.25), 0.5, 0.6, 0.2, 0.05, Color("4b5262"))
			mk.cylinder(Vector3(0.7, 0.08, 0.6), 0.1, 0.24, 8, stone.darkened(0.05))
			mk.cone(Vector3(0.7, 0.32, 0.6), 0.08, 0.1, 3, Color("6f8f6a"))
			for k in 5:
				var a := TAU * k / 5.0
				mk.pebble(Vector3(cos(a) * 0.86, 0.1, sin(a) * 0.86), Vector3(0.09, 0.06, 0.08), Color(0.62, 0.6, 0.56))
		Game.LM.FERRIS:
			mk.rbox(Vector3(0, 0.04, 0), Vector3(2.0, 0.08, 2.0), 0.03, Color(0.9, 0.86, 0.8))
			var steel := Color(0.96, 0.96, 0.98)
			for s in [-1, 1]:
				mk.push(Transform3D(Basis(Vector3.BACK, s * 0.32), Vector3(s * 0.5, 0.08, 0.25)))
				mk.box(Vector3(0, 1.1, 0), Vector3(0.08, 2.3, 0.08), steel)
				mk.pop()
				mk.push(Transform3D(Basis(Vector3.BACK, s * 0.32), Vector3(s * 0.5, 0.08, -0.25)))
				mk.box(Vector3(0, 1.1, 0), Vector3(0.08, 2.3, 0.08), steel)
				mk.pop()
			mk.rbox(Vector3(0, 0.25, 0.75), Vector3(0.6, 0.36, 0.3), 0.06, Color("ef7fa8"))
			var wheel := MeshKit.new()
			var R := 1.5
			var spokes := 12
			for k in spokes:
				var a := TAU * k / spokes
				var p := Vector3(cos(a), sin(a), 0) * R
				for zz in [-0.18, 0.18]:
					wheel.push(Transform3D(Basis(Vector3.BACK, a), Vector3(0, 0, zz)))
					wheel.box(Vector3(R * 0.5, 0, 0), Vector3(R, 0.04, 0.04), steel)
					wheel.pop()
					var a2 := TAU * (k + 1) / spokes
					var p2 := Vector3(cos(a2), sin(a2), 0) * R
					var mid := (p + p2) * 0.5 + Vector3(0, 0, zz)
					wheel.push(Transform3D(Basis(Vector3.BACK, (a + a2) * 0.5 + PI * 0.5), mid))
					wheel.box(Vector3.ZERO, Vector3(p.distance_to(p2), 0.06, 0.05), steel)
					wheel.pop()
				wheel.blob(p, Vector3(0.05, 0.05, 0.05), Color(1, 0.85, 0.5), 0.0, 2.0)
				var cab: Color = AWNINGS[k % AWNINGS.size()]
				wheel.rbox(p + Vector3(0, -0.18, 0), Vector3(0.26, 0.24, 0.26), 0.07, cab)
				wheel.box(p + Vector3(0, -0.06, 0), Vector3(0.03, 0.12, 0.03), steel)
			wheel.cylinder(Vector3(0, -0.06, 0), 0.12, 0.12, 8, steel)
			var wn := _spinner(root, wheel.commit(mat), Vector3(0, 2.35, 0), Vector3.BACK, 0.18, wheel.commit_shadow(shadow_material()))
			(wn.get_parent() as Node3D).rotation.y = yaw_of(f)
			root.get_child(0).rotation.y = yaw_of(f)


static func _beam_mesh(mat: Material) -> ArrayMesh:
	# two cones out both sides of the lamp, angled down so they meet the sea about
	# 14 m out: a soft wide glow around a brighter narrow core
	var v := PackedVector3Array()
	var nrm := PackedVector3Array()
	var c := PackedColorArray()
	var sides := 10
	var warm := Color(1, 0.92, 0.66)
	for layer in [[1.7, 0.16], [0.7, 0.32]]:
		var rad: float = layer[0]
		var alpha: float = layer[1]
		for s in [-1.0, 1.0]:
			var axis := Vector3(s * 14.0, -4.6, 0.0)
			var fwd := axis.normalized()
			var up := fwd.cross(Vector3.BACK).normalized()
			var side := fwd.cross(up).normalized()
			for i in sides:
				var a0 := TAU * i / sides
				var a1 := TAU * (i + 1) / sides
				var d0 := up * cos(a0) + side * sin(a0)
				var d1 := up * cos(a1) + side * sin(a1)
				v.append_array([Vector3.ZERO, axis + d0 * rad, axis + d1 * rad])
				nrm.append_array([(d0 + d1).normalized(), d0, d1])
				c.append_array([Color(warm, alpha), Color(warm, 0.0), Color(warm, 0.0)])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = nrm
	arrays[Mesh.ARRAY_COLOR] = c
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	m.surface_set_material(0, mat)
	return m


static func _spinner(root: Node3D, mesh: ArrayMesh, pos: Vector3, axis: Vector3, speed: float, proxy: ArrayMesh = null) -> MeshInstance3D:
	var pivot := Node3D.new()
	pivot.position = pos
	root.add_child(pivot)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	if proxy:
		# spins along with the mesh, drawing only the cheap stand-in into the shadow map
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var sh := MeshInstance3D.new()
		sh.mesh = proxy
		sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		mi.add_child(sh)
	mi.set_meta("spin_axis", axis)
	mi.set_meta("spin_speed", speed)
	pivot.add_child(mi)
	return mi


# ------------------------------------------------------------------ entry point

## Builds the visual node for a tile, positioned at the tile's centre. Returns null for empty tiles.
static var _shadow_mat: Material


## Double-sided, so stand-in winding never matters in the shadow pass.
static func shadow_material() -> Material:
	if _shadow_mat == null:
		var m := StandardMaterial3D.new()
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_shadow_mat = m
	return _shadow_mat


static func build(x: int, z: int, mat: Material, beam_mat: Material) -> Node3D:
	var k := Game.knd(x, z)
	if k == Game.K.EMPTY:
		return null
	var root := Node3D.new()
	root.position = Game.tile_center(x, z)
	var mk := MeshKit.new(Game.hash2(x, z, 999))
	mk.quiet_sprites = true
	var body := MeshInstance3D.new()
	root.add_child(body)
	match k:
		Game.K.ROAD: _road(mk, x, z, root, mat)
		Game.K.HOUSE: HomeGen.build(mk, x, z)
		Game.K.SHOP: ShopGen.build(mk, x, z)
		Game.K.OFFICE: WorkGen.build(mk, x, z)
		Game.K.PARK: ParkGen.build(mk, x, z)
		Game.K.TREE: NatureGen.build(mk, x, z)
		Game.K.LANDMARK: _landmark(mk, x, z, root, mat, beam_mat)
	body.name = "Body"
	body.mesh = mk.commit(mat, false)
	# the shadow map gets cheap stand-in shapes instead of the detailed mesh
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sm := mk.commit_shadow(shadow_material())
	if sm:
		var sh := MeshInstance3D.new()
		sh.name = "Shadow"
		sh.mesh = sm
		sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		root.add_child(sh)
	var bm := mk.commit_blobs()
	if bm:
		var bl := MeshInstance3D.new()
		bl.name = "Blobs"
		bl.mesh = bm
		root.add_child(bl)
	var qm := mk.commit_quiet()
	if qm:
		var ql := MeshInstance3D.new()
		ql.name = "Sprites"
		ql.mesh = qm
		ql.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(ql)
	# raw arrays let the world merge settled tiles into big batched meshes
	body.set_meta("arrays", [mk.verts, mk.norms, mk.cols, mk.uvs, mk.dverts, mk.dnorms, mk.dcols, mk.duvs, mk.sverts, mk.snorms,
		mk.bverts, mk.bcols, mk.buvs, mk.bradius, mk.qverts, mk.qcols, mk.quvs, mk.qradius])
	return root
