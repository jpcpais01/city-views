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
		mk.box(Vector3(0, 0.03, 0), Vector3(w * 2, 0.06, w * 2), ASPHALT)
	else:
		_flat(mk, -w, -w, w, w, 0.06, ASPHALT)
	for i in 4:
		if links[i]:
			var d := DIRS[i]
			var c := Vector3(d.x, 0, d.y) * (w + (H - w) * 0.5)
			var sz := Vector3(H - w if d.x != 0 else w * 2, 0.06, H - w if d.y != 0 else w * 2)
			if water:
				mk.box(c + Vector3(0, 0.03, 0), sz, ASPHALT)
			else:
				_flat(mk, c.x - sz.x * 0.5, c.z - sz.z * 0.5, c.x + sz.x * 0.5, c.z + sz.z * 0.5, 0.06, ASPHALT)
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
	if count == 2 and ((links[0] and links[2]) or (links[1] and links[3])):
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
	# street lamps on some corners
	if not water and Game.hash2(x, z, 77) % 3 == 0:
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
static func _flat(mk: MeshKit, x0: float, z0: float, x1: float, z1: float, y: float, col: Color) -> void:
	var was := mk.shadow
	mk.shadow = false
	mk.quad(Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z1), Vector3.UP, col)
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


static func _round_tree(mk: MeshKit, p: Vector3, s: float, col: Color) -> void:
	mk.pole(p, 0.05 * s / 0.6, 0.35 * s / 0.6, 4, Color(0.5, 0.36, 0.25))
	mk.blob(p + Vector3(0, 0.55 * s / 0.6, 0), Vector3(0.32, 0.36, 0.32) * s / 0.6, col, 0.06)


static func _pine(mk: MeshKit, p: Vector3, s: float, col: Color) -> void:
	mk.pole(p, 0.05 * s, 0.25 * s, 6, Color(0.45, 0.32, 0.22))
	for k in 3:
		mk.cone(p + Vector3(0, (0.2 + k * 0.28) * s, 0), (0.42 - k * 0.1) * s, 0.5 * s, 9, col.lightened(k * 0.05))


static func _palm(mk: MeshKit, p: Vector3, s: float, seed_i: int) -> void:
	var lean := Vector3(sin(seed_i * 1.7), 0, cos(seed_i * 1.7)) * 0.07
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


# ------------------------------------------------------------------ houses

static func _house(mk: MeshKit, x: int, z: int) -> void:
	var g := Game.grw(x, z)
	if g == 0:
		_lot(mk, x, z)
		return
	var f := facing(x, z)
	var sea := coastal(x, z)
	var hill := Game.lvl(x, z) >= 4
	var wall := pick(SEA_WALLS if sea else (HILL_WALLS if hill else WALLS), x, z, 10)
	var roof := pick(SEA_ROOFS if sea else (HILL_ROOFS if hill else ROOFS), x, z, 11)
	if roof.is_equal_approx(Color("ffffff")) and wall.v > 0.95:
		roof = Color("3f7cc4")
	var right := (f + 1) % 4
	var left := (f + 3) % 4
	var jr := joined(x, z, right, Game.K.HOUSE) or joined(x, z, right, Game.K.SHOP)
	var jl := joined(x, z, left, Game.K.HOUSE) or joined(x, z, left, Game.K.SHOP)
	mk.push_at(Vector3.ZERO, yaw_of(f))
	_plot(mk, Color(0.6, 0.8, 0.45) if g < 3 else SIDEWALK)
	# local frame: +Z = street. +X toward 'left' index? yaw maps local +X to world dir (f+3)%4
	# (rotating +Z onto DIRS[f] sends +X onto DIRS[(f+3)%4]), so swap the joins accordingly.
	var join_px := jl
	var join_nx := jr
	var w := 1.25 + 0.2 * Game.hashf(x, z, 12)
	var d := 1.05 + 0.2 * Game.hashf(x, z, 13)
	if g == 2:
		w = 1.5; d = 1.3
	elif g == 3:
		w = 1.72; d = 1.6
	var x0 := -w * 0.5
	var x1 := w * 0.5
	if join_nx: x0 = -H
	if join_px: x1 = H
	w = x1 - x0
	var cx := (x0 + x1) * 0.5
	var cz := -0.1 if g < 3 else 0.0
	var fh := 0.62  # floor height
	var floors := 1 + int(Game.hashf(x, z, 14) > 0.6)
	if g == 2:
		floors = 2 + int(Game.hashf(x, z, 14) > 0.5)
	elif g == 3:
		floors = 4 + Game.hash2(x, z, 14) % 2 + min(3, density(x, z) / 6)
	var hgt := floors * fh + 0.1
	var sides := [true, not join_px, true, not join_nx]
	mk.push_at(Vector3(cx, 0, cz))
	# foundation
	mk.rbox(Vector3(0, 0.08, 0), Vector3(w + 0.06, 0.16, d + 0.06), 0.04, wall.darkened(0.25))
	var flat_roof := g == 3 or (sea and Game.hashf(x, z, 15) > 0.55)
	if g == 3:
		var brick := pick(BRICK, x, z, 16)
		mk.rbox(Vector3(0, 0.1 + hgt * 0.5, 0), Vector3(w, hgt, d), 0.06, brick)
		# floor bands
		mk.bands(0.1 + fh, w, d, fh, floors - 1, 0.04, brick.lightened(0.25))
		for fl in floors:
			var yy := 0.1 + fl * fh + fh * 0.5
			if fl == 0:
				_windows_row(mk, yy, w, d, 2, 2, GLASS, FRAME, [false, sides[1], true, sides[3]], 0.24, 0.32)
				# entrance with canopy
				mk.rbox(Vector3(0, 0.38, d * 0.5 + 0.01), Vector3(0.36, 0.56, 0.06), 0.03, DOOR)
				mk.rbox(Vector3(0, 0.72, d * 0.5 + 0.14), Vector3(0.6, 0.05, 0.3), 0.02, brick.darkened(0.3))
			else:
				_windows_row(mk, yy, w, d, 3, 3, GLASS, FRAME, sides, 0.24, 0.32)
				if fl % 2 == 1 and Game.hashf(x, z, 17) > 0.4:
					# balconies
					for i in [-1, 1]:
						mk.box_faces(Vector3(i * w * 0.25, yy - fh * 0.32, d * 0.5 + 0.12), Vector3(0.42, 0.04, 0.24), FRAME, MeshKit.TOP | MeshKit.FRONT | MeshKit.LEFT | MeshKit.RIGHT)
						mk.box_faces(Vector3(i * w * 0.25, yy - fh * 0.2, d * 0.5 + 0.235), Vector3(0.42, 0.2, 0.015), Color(1, 1, 1, 1).darkened(0.1), MeshKit.FRONT | MeshKit.BACK)
		# roof: parapet + rooftop details
		var top := 0.1 + hgt
		mk.rbox(Vector3(0, top + 0.06, 0), Vector3(w + 0.06, 0.12, d + 0.06), 0.03, brick.lightened(0.3))
		mk.box_faces(Vector3(0, top + 0.1, 0), Vector3(w - 0.12, 0.02, d - 0.12), Color(0.55, 0.55, 0.57), MeshKit.TOP)
		var r := Game.hash2(x, z, 18) % 3
		if r == 0:
			mk.cylinder(Vector3(w * 0.22, top + 0.1, -d * 0.2), 0.18, 0.32, 8, Color(0.55, 0.42, 0.32), false, null, 0.16)
			mk.cone(Vector3(w * 0.22, top + 0.42, -d * 0.2), 0.2, 0.14, 8, Color(0.45, 0.35, 0.28))
			for k in 4:
				var a := TAU * k / 4.0 + 0.6
				mk.box(Vector3(w * 0.22 + cos(a) * 0.12, top + 0.15, -d * 0.2 + sin(a) * 0.12), Vector3(0.03, 0.12, 0.03), Color(0.3, 0.3, 0.3))
		elif r == 1:
			# roof garden
			for k in 3:
				mk.blob(Vector3(-w * 0.3 + k * w * 0.3, top + 0.2, -d * 0.15), Vector3(0.16, 0.13, 0.16), LEAF[(k + x) % LEAF.size()])
		else:
			mk.rbox(Vector3(-w * 0.2, top + 0.2, 0), Vector3(0.3, 0.2, 0.25), 0.04, Color(0.8, 0.82, 0.85))
			mk.rbox(Vector3(w * 0.15, top + 0.18, -d * 0.2), Vector3(0.2, 0.16, 0.2), 0.04, Color(0.8, 0.82, 0.85))
	else:
		mk.rbox(Vector3(0, 0.1 + hgt * 0.5, 0), Vector3(w, hgt, d), 0.05, wall)
		var glass := GLASS
		for fl in floors:
			var yy := 0.1 + fl * fh + fh * 0.52
			var nf := 2 if w < 1.7 else 3
			if fl == 0:
				# door + two windows
				mk.rbox(Vector3(0, 0.37, d * 0.5 + 0.005), Vector3(0.26, 0.48, 0.05), 0.03, pick([DOOR, Color("4a7bb5"), Color("3d8a6a"), Color("b04a4a")], x, z, 19))
				mk.box(Vector3(0.08, 0.37, d * 0.5 + 0.035), Vector3(0.03, 0.03, 0.02), Color(1, 0.85, 0.4))
				for s in [-1, 1]:
					mk.window(Vector3(s * w * 0.3, yy, d * 0.5), Vector3.BACK, 0.24, 0.28, glass, FRAME)
				_windows_row(mk, yy, w, d, 0, 1, glass, FRAME, [false, sides[1], false, sides[3]])
				_windows_row(mk, yy, w, d, nf, 0, glass, FRAME, [false, false, true, false])
			else:
				_windows_row(mk, yy, w, d, nf, 1, glass, FRAME, sides)
				if g == 2 and fl == 1 and Game.hashf(x, z, 20) > 0.4:
					mk.box_faces(Vector3(0, yy - 0.2, d * 0.5 + 0.13), Vector3(0.7, 0.04, 0.26), FRAME, MeshKit.TOP | MeshKit.FRONT | MeshKit.LEFT | MeshKit.RIGHT)
					mk.box_faces(Vector3(0, yy - 0.1, d * 0.5 + 0.255), Vector3(0.7, 0.18, 0.015), Color(0.95, 0.95, 0.95), MeshKit.FRONT | MeshKit.BACK)
					for k in 3:
						mk.blob(Vector3(-0.25 + k * 0.25, yy - 0.13, d * 0.5 + 0.2), Vector3(0.06, 0.05, 0.06), AWNINGS[(k + x) % AWNINGS.size()])
		var top := 0.1 + hgt
		if flat_roof:
			mk.rbox(Vector3(0, top + 0.05, 0), Vector3(w + 0.05, 0.1, d + 0.05), 0.03, wall.lightened(0.1))
			mk.box_faces(Vector3(0, top + 0.08, 0), Vector3(w - 0.12, 0.02, d - 0.12), wall.darkened(0.12), MeshKit.TOP)
			if Game.hashf(x, z, 21) > 0.5:
				# blue-domed seaside cupola
				mk.cylinder(Vector3(w * 0.2, top + 0.08, -d * 0.15), 0.18, 0.22, 10, wall)
				mk.blob(Vector3(w * 0.2, top + 0.3, -d * 0.15), Vector3(0.18, 0.16, 0.18), roof if roof.b > roof.r else Color("3f7cc4"))
			else:
				# canvas sunshade
				mk.box(Vector3(-w * 0.15, top + 0.38, 0), Vector3(0.6, 0.03, 0.5), AWNINGS[Game.hash2(x, z, 22) % AWNINGS.size()])
				for px in [-1, 1]:
					for pz in [-1, 1]:
						mk.box(Vector3(-w * 0.15 + px * 0.27, top + 0.22, pz * 0.22), Vector3(0.025, 0.3, 0.025), FRAME)
		else:
			var pitch := 0.5 if not hill else 0.75
			# ridge runs along local X (parallel to the street)
			mk.gable_roof(Vector3(0, top, 0), w, d, pitch * (0.8 + g * 0.15), 0.12, roof, wall)
			if Game.hashf(x, z, 23) > 0.45:
				mk.rbox(Vector3(w * 0.28, top + pitch * 0.6, -d * 0.2), Vector3(0.16, 0.5, 0.16), 0.03, wall.darkened(0.2))
				mk.box(Vector3(w * 0.28, top + pitch * 0.6 + 0.26, -d * 0.2), Vector3(0.2, 0.04, 0.2), wall.darkened(0.35))
			if g == 2 and Game.hashf(x, z, 24) > 0.5:
				# dormer
				mk.rbox(Vector3(0, top + 0.16, d * 0.18), Vector3(0.34, 0.3, 0.3), 0.03, wall)
				mk.window(Vector3(0, top + 0.17, d * 0.18 + 0.15), Vector3.BACK, 0.16, 0.16, glass, FRAME)
				mk.push_at(Vector3(0, top + 0.3, d * 0.18), PI * 0.5)
				mk.gable_roof(Vector3.ZERO, 0.32, 0.36, 0.16, 0.04, roof, wall, 0.04)
				mk.pop()
	mk.pop()
	# front garden decoration
	if g < 3:
		var gz := cz + d * 0.5 + 0.12
		var room := H - gz
		if room > 0.3:
			if Game.hashf(x, z, 25) > 0.5:
				# picket fence
				var fx0 := x0 + 0.05
				var fx1 := x1 - 0.05
				var n := int((fx1 - fx0) / 0.2)
				for k in n + 1:
					mk.box(Vector3(fx0 + k * (fx1 - fx0) / max(n, 1), 0.15, H - 0.08), Vector3(0.035, 0.18, 0.03), FRAME)
				mk.box(Vector3((fx0 + fx1) * 0.5, 0.17, H - 0.08), Vector3(fx1 - fx0, 0.03, 0.02), FRAME)
			else:
				mk.rbox(Vector3((x0 + x1) * 0.5, 0.14, H - 0.12), Vector3(x1 - x0 - 0.1, 0.18, 0.16), 0.07, Color("5c9e4e"))
			mk.blob(Vector3(x0 + 0.2, 0.15, gz + 0.12), Vector3(0.13, 0.11, 0.13), pick(AWNINGS, x, z, 26))
			mk.rbox(Vector3(0, 0.065, gz + room * 0.5), Vector3(0.22, 0.01, room), 0.004, Color(0.86, 0.8, 0.7))
	if not join_px and not join_nx and g == 1 and Game.hashf(x, z, 27) > 0.4:
		_round_tree(mk, Vector3(0.7, 0.06, -0.72), 0.45, pick(LEAF, x, z, 28))
	mk.pop()


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
	mk.rbox(Vector3(0, 0.06 + hgt * 0.5, 0), Vector3(w, hgt, d), 0.05, wall)
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
	mk.box(Vector3(0, 0.74, sf + 0.38), Vector3(aw, 0.08, 0.02), awn)
	# sign board
	mk.rbox(Vector3(0, 1.08, sf + 0.04), Vector3(w * 0.6, 0.2, 0.06), 0.04, Color(0.98, 0.95, 0.86))
	mk.box(Vector3(0, 1.08, sf + 0.075), Vector3(w * 0.45, 0.07, 0.01), awn.darkened(0.2), null, false, 2.0)
	# upper floors
	for fl in range(1, floors):
		var yy := 0.2 + fl * fh + fh * 0.5
		_windows_row(mk, yy, w, d, 3, 2, GLASS, FRAME, [true, not jl, true, not jr])
		if g == 2 and fl == 1:
			for s in [-1, 0, 1]:
				mk.blob(Vector3(s * w * 0.32, yy - 0.2, sf + 0.06), Vector3(0.1, 0.06, 0.06), Color("e86a6a").lerp(Color("6fb35a"), 0.6))
	var top := 0.06 + hgt
	mk.rbox(Vector3(0, top + 0.05, 0), Vector3(w + 0.05, 0.1, d + 0.05), 0.03, wall.lightened(0.15))
	if g == 3:
		# rooftop billboard
		mk.box(Vector3(0, top + 0.3, -0.2), Vector3(0.04, 0.5, 0.04), Color(0.3, 0.3, 0.32))
		mk.rbox(Vector3(0, top + 0.6, -0.2), Vector3(w * 0.7, 0.36, 0.06), 0.03, awn)
		mk.box(Vector3(0, top + 0.6, -0.165), Vector3(w * 0.5, 0.12, 0.01), Color(1, 1, 1), null, false, 2.0)
	else:
		mk.rbox(Vector3(w * 0.25, top + 0.16, -0.25), Vector3(0.3, 0.2, 0.3), 0.04, Color(0.82, 0.84, 0.86))
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
		mk.rbox(Vector3(0, y + hh * 0.5, 0), Vector3(w, hh, d), corner, tone)
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
		mk.rbox(Vector3(0, y + 0.04, 0), Vector3(w + 0.06, 0.08, d + 0.06), 0.03, tone.lightened(0.25))
		y += 0.08
		w *= 0.78
		d *= 0.78
	if g == 3:
		mk.cylinder(Vector3(0, y, 0), 0.06, 0.9, 6, Color(0.8, 0.82, 0.85), true, null, 0.02)
		mk.blob(Vector3(0, y + 0.92, 0), Vector3(0.06, 0.06, 0.06), Color(1, 0.25, 0.2), 0.0, 2.0)
	else:
		mk.rbox(Vector3(-0.2, y + 0.14, 0.1), Vector3(0.4, 0.2, 0.3), 0.04, Color(0.75, 0.77, 0.8))
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
	var count := 1 + Game.prm(x, z) % 3 + (1 if l >= 2 else 0)
	for k in count:
		var p := Vector3(Game.hashf(x, z, 60 + k) * 1.3 - 0.65, 0.0, Game.hashf(x, z, 70 + k) * 1.3 - 0.65)
		var s := 0.5 + Game.hashf(x, z, 80 + k) * 0.35
		if l == 1:
			_palm(mk, p, s * 1.1, Game.hash2(x, z, 90 + k) % 100)
		elif l >= 4 or (l == 3 and Game.hashf(x, z, 95 + k) > 0.5):
			_pine(mk, p, s * 1.3, pick([Color("3f7f4f"), Color("4b8b55"), Color("36704a")], x, z, 100 + k))
		else:
			var col := pick(LEAF, x, z, 110 + k)
			if Game.hashf(x, z, 120 + k) > 0.86:
				col = pick(AUTUMN, x, z, 130 + k)
			_round_tree(mk, p, s, col)
	if l >= 2 and Game.hashf(x, z, 140) > 0.6:
		mk.blob(Vector3(Game.hashf(x, z, 141) - 0.5, 0.06, Game.hashf(x, z, 142) - 0.5), Vector3(0.18, 0.12, 0.16), Color("5c9e4e"))


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
	var v := PackedVector3Array()
	var c := PackedColorArray()
	var sides := 10
	for s in [-1.0, 1.0]:
		for i in sides:
			var a0 := TAU * i / sides
			var a1 := TAU * (i + 1) / sides
			var p0 := Vector3(s * 10.0, cos(a0) * 1.4 - 0.6, sin(a0) * 1.4)
			var p1 := Vector3(s * 10.0, cos(a1) * 1.4 - 0.6, sin(a1) * 1.4)
			v.append_array([Vector3.ZERO, p0, p1])
			c.append_array([Color(1, 0.93, 0.65, 0.28), Color(1, 0.93, 0.65, 0.0), Color(1, 0.93, 0.65, 0.0)])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
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
	var body := MeshInstance3D.new()
	root.add_child(body)
	match k:
		Game.K.ROAD: _road(mk, x, z, root, mat)
		Game.K.HOUSE: _house(mk, x, z)
		Game.K.SHOP: _shop(mk, x, z)
		Game.K.OFFICE: _office(mk, x, z)
		Game.K.PARK: _park(mk, x, z)
		Game.K.TREE: _trees(mk, x, z)
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
	# raw arrays let the world merge settled tiles into big batched meshes
	body.set_meta("arrays", [mk.verts, mk.norms, mk.cols, mk.uvs, mk.dverts, mk.dnorms, mk.dcols, mk.duvs, mk.sverts, mk.snorms,
		mk.bverts, mk.bcols, mk.buvs, mk.bradius])
	return root
