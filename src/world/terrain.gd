class_name Terrain
extends Node3D
## Terraced island terrain built in 16x16 tile chunks with soft rounded lips.

const CHUNK := 16
const LIP := 0.1

var material: Material
var _chunks := {}


func build_all() -> void:
	for c in _chunks.values():
		c.queue_free()
	_chunks.clear()
	var n := Game.N / CHUNK
	for cz in n:
		for cx in n:
			_build_chunk(cx, cz)


func tile_changed(x: int, z: int) -> void:
	var touched := {}
	for d in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var tx: int = x + d.x
		var tz: int = z + d.y
		if Game.inside(tx, tz):
			touched[Vector2i(tx / CHUNK, tz / CHUNK)] = true
	for c in touched:
		_build_chunk(c.x, c.y)


func _top_color(x: int, z: int, l: int) -> Color:
	var j := Game.hashf(x, z, 1) * 0.06 - 0.03
	var c: Color
	match l:
		0: c = Color(0.78, 0.74, 0.58)
		1: c = Color(0.96, 0.87, 0.66)
		2: c = Color(0.56, 0.79, 0.4)
		3: c = Color(0.5, 0.75, 0.37)
		4: c = Color(0.45, 0.69, 0.36)
		5: c = Color(0.58, 0.64, 0.48)
		_: c = Color(0.62, 0.66, 0.52)
	if Game.knd(x, z) == Game.K.TREE and l >= 2:
		c = c.darkened(0.08)
	return Color(c.r + j, c.g + j, c.b + j * 0.5)


func _wall_color(l: int, y: float) -> Color:
	if l <= 1:
		return Color(0.9, 0.8, 0.6)
	var band := 0.04 * sin(y * 9.0)
	return Color(0.74 + band, 0.62 + band, 0.48 + band)


func _build_chunk(cx: int, cz: int) -> void:
	var key := Vector2i(cx, cz)
	if _chunks.has(key):
		_chunks[key].queue_free()
	var mk := MeshKit.new()
	var h := Game.TILE * 0.5
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for z in range(cz * CHUNK, (cz + 1) * CHUNK):
		for x in range(cx * CHUNK, (cx + 1) * CHUNK):
			var l := Game.lvl(x, z)
			var c := Game.tile_center(x, z)
			var y := c.y
			var drops := [false, false, false, false]
			var low := [0.0, 0.0, 0.0, 0.0]
			for i in 4:
				var d: Vector2i = dirs[i]
				var nl := Game.lvl(x + d.x, z + d.y) if Game.inside(x + d.x, z + d.y) else 0
				if nl < l:
					drops[i] = true
					low[i] = Game.LEVEL_Y[nl]
			var bx1 := LIP if drops[0] else 0.0
			var bx0 := LIP if drops[1] else 0.0
			var bz1 := LIP if drops[2] else 0.0
			var bz0 := LIP if drops[3] else 0.0
			var x0 := c.x - h
			var x1 := c.x + h
			var z0 := c.z - h
			var z1 := c.z + h
			var top := _top_color(x, z, l)
			mk.quad(Vector3(x0 + bx0, y, z0 + bz0), Vector3(x1 - bx1, y, z0 + bz0), Vector3(x1 - bx1, y, z1 - bz1), Vector3(x0 + bx0, y, z1 - bz1), Vector3.UP, top)
			var lip := top.lightened(0.06)
			var yl := y - LIP
			var up := Vector3.UP
			# rounded lips + cliff walls on every edge that drops
			if drops[0]:
				var o := Vector3.RIGHT
				mk.quad_n(Vector3(x1 - LIP, y, z0 + bz0), Vector3(x1 - LIP, y, z1 - bz1), Vector3(x1, yl, z1), Vector3(x1, yl, z0),
					(up + o * 0.4).normalized(), (up + o * 0.4).normalized(), (o + up * 0.3).normalized(), (o + up * 0.3).normalized(), lip)
				_wall(mk, Vector3(x1, yl, z0), Vector3(x1, yl, z1), low[0], o, l)
			if drops[1]:
				var o := Vector3.LEFT
				mk.quad_n(Vector3(x0 + LIP, y, z0 + bz0), Vector3(x0 + LIP, y, z1 - bz1), Vector3(x0, yl, z1), Vector3(x0, yl, z0),
					(up + o * 0.4).normalized(), (up + o * 0.4).normalized(), (o + up * 0.3).normalized(), (o + up * 0.3).normalized(), lip)
				_wall(mk, Vector3(x0, yl, z0), Vector3(x0, yl, z1), low[1], o, l)
			if drops[2]:
				var o := Vector3.BACK
				mk.quad_n(Vector3(x0 + bx0, y, z1 - LIP), Vector3(x1 - bx1, y, z1 - LIP), Vector3(x1, yl, z1), Vector3(x0, yl, z1),
					(up + o * 0.4).normalized(), (up + o * 0.4).normalized(), (o + up * 0.3).normalized(), (o + up * 0.3).normalized(), lip)
				_wall(mk, Vector3(x0, yl, z1), Vector3(x1, yl, z1), low[2], o, l)
			if drops[3]:
				var o := Vector3.FORWARD
				mk.quad_n(Vector3(x0 + bx0, y, z0 + LIP), Vector3(x1 - bx1, y, z0 + LIP), Vector3(x1, yl, z0), Vector3(x0, yl, z0),
					(up + o * 0.4).normalized(), (up + o * 0.4).normalized(), (o + up * 0.3).normalized(), (o + up * 0.3).normalized(), lip)
				_wall(mk, Vector3(x0, yl, z0), Vector3(x1, yl, z0), low[3], o, l)
			# pebbles and grass tufts on empty land for extra richness
			if Game.knd(x, z) == Game.K.EMPTY and l >= 1:
				var r := Game.hashf(x, z, 21)
				if l >= 5 and r < 0.7:
					mk.pebble(c + Vector3(Game.hashf(x, z, 22) - 0.5, 0.05, Game.hashf(x, z, 23) - 0.5), Vector3(0.26, 0.16, 0.2), Color(0.66, 0.64, 0.6))
					mk.pebble(c + Vector3(Game.hashf(x, z, 24) - 0.5, 0.03, Game.hashf(x, z, 25) - 0.5), Vector3(0.14, 0.1, 0.12), Color(0.6, 0.58, 0.55))
				elif l >= 2 and r < 0.35:
					var fc: Color = [Color(1, 0.85, 0.35), Color(1, 0.6, 0.7), Color(0.95, 0.95, 1), Color(0.75, 0.6, 1)][Game.hash2(x, z, 24) % 4]
					var cc := c + Vector3(Game.hashf(x, z, 30) * 1.2 - 0.6, 0.0, Game.hashf(x, z, 40) * 1.2 - 0.6)
					mk.pebble(cc + Vector3(0, 0.02, 0), Vector3(0.2, 0.07, 0.18), Color(0.42, 0.68, 0.33))
					for k in 4:
						var p := cc + Vector3(Game.hashf(x, z, 31 + k) * 0.3 - 0.15, 0.09, Game.hashf(x, z, 41 + k) * 0.3 - 0.15)
						mk.pebble(p, Vector3(0.045, 0.035, 0.045), fc)
				elif l == 1 and r < 0.12:
					mk.rbox(c + Vector3(Game.hashf(x, z, 22) - 0.5, 0.02, Game.hashf(x, z, 23) - 0.5), Vector3(0.18, 0.06, 0.12), 0.03, Color(0.98, 0.95, 0.9))
	var mi := MeshInstance3D.new()
	mi.mesh = mk.commit(material)
	add_child(mi)
	_chunks[key] = mi


func _wall(mk: MeshKit, a: Vector3, b: Vector3, bottom: float, out: Vector3, l: int) -> void:
	var top_y := a.y
	if top_y - bottom < 0.01:
		return
	# two bands so cliffs read as layered strata
	var mid := lerpf(top_y, bottom, 0.45)
	mk.quad(a, b, Vector3(b.x, mid, b.z), Vector3(a.x, mid, a.z), out, _wall_color(l, top_y))
	mk.quad(Vector3(a.x, mid, a.z), Vector3(b.x, mid, b.z), Vector3(b.x, bottom, b.z), Vector3(a.x, bottom, a.z), out, _wall_color(l, top_y).darkened(0.1))
