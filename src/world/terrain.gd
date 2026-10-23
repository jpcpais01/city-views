class_name Terrain
extends Node3D
## Terraced island terrain built in 16x16 tile chunks with soft rounded lips.

const CHUNK := 16
const LIP := 0.1
# how far a terrace edge may wander out over the lower ground, and how finely
const WAVE := 0.42
const WAVE_SEG := 5
const OUT := [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]
const ALONG := [Vector3(0, 0, 1), Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(1, 0, 0)]
# rounded-corner index (see `rc`) at the start / end of each edge
const EDGE_ENDS := [[1, 0], [3, 2], [3, 1], [2, 0]]

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
		3: c = Color(0.46, 0.71, 0.35)
		4: c = Color(0.39, 0.63, 0.33)
		5: c = Color(0.52, 0.58, 0.44)
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
				if nl < l or (l == 0 and nl == 0 and Game.inside(x + d.x, z + d.y) and Game.tile_y(x + d.x, z + d.y) < c.y - 0.01):
					drops[i] = true
					low[i] = Game.tile_y(x + d.x, z + d.y) if Game.inside(x + d.x, z + d.y) else Game.SEA_FLOOR
			var bx1 := LIP if drops[0] else 0.0
			var bx0 := LIP if drops[1] else 0.0
			var bz1 := LIP if drops[2] else 0.0
			var bz0 := LIP if drops[3] else 0.0
			var x0 := c.x - h
			var x1 := c.x + h
			var z0 := c.z - h
			var z1 := c.z + h
			var top := _top_color(x, z, l)
			# corner colours are averaged with the neighbours on the same terrace,
			# so the grid melts into soft gradients instead of hard squares
			mk.quad_c(Vector3(x0 + bx0, y, z0 + bz0), Vector3(x1 - bx1, y, z0 + bz0), Vector3(x1 - bx1, y, z1 - bz1), Vector3(x0 + bx0, y, z1 - bz1),
				_corner(x, z, l, x, z), _corner(x, z, l, x + 1, z), _corner(x, z, l, x + 1, z + 1), _corner(x, z, l, x, z + 1))
			var lip := top.lightened(0.06)
			# convex corners (both sides drop) get a rounded fillet instead of a square notch
			var rc := [drops[0] and drops[2], drops[0] and drops[3], drops[1] and drops[2], drops[1] and drops[3]]
			var ins := [bz0, bz1, bz0, bz1, bx0, bx1, bx0, bx1]
			for i in 4:
				if drops[i]:
					_edge(mk, x, z, i, c, y, ins[i * 2], ins[i * 2 + 1], rc[EDGE_ENDS[i][0]], rc[EDGE_ENDS[i][1]], low[i], top, lip, l)
			var corners := [[1.0, 1.0, 0, 2], [1.0, -1.0, 0, 3], [-1.0, 1.0, 1, 2], [-1.0, -1.0, 1, 3]]
			for k in 4:
				if rc[k]:
					var cr: Array = corners[k]
					_fillet(mk, Vector3(c.x + cr[0] * (h - LIP), y, c.z + cr[1] * (h - LIP)), cr[0], cr[1], minf(low[cr[2]], low[cr[3]]), lip, l)
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
	# the ground only receives shadows; drawing it into the shadow map is wasted work
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_chunks[key] = mi


## Smooth 2D value noise in world space (same value for both tiles sharing an edge point).
func _noise(px: float, pz: float) -> float:
	var v := 0.0
	var amp := 0.65
	var f := 0.7
	for o in 2:
		var gx := px * f
		var gz := pz * f
		var ix := floori(gx)
		var iz := floori(gz)
		var fx := gx - ix
		var fz := gz - iz
		fx = fx * fx * (3.0 - 2.0 * fx)
		fz = fz * fz * (3.0 - 2.0 * fz)
		var a := Game.hashf(ix, iz, 300 + o)
		var b := Game.hashf(ix + 1, iz, 300 + o)
		var c := Game.hashf(ix, iz + 1, 300 + o)
		var d := Game.hashf(ix + 1, iz + 1, 300 + o)
		v += lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fz) * amp
		amp = 0.35
		f *= 2.3
	return v


## Whether the edge on side `i` of a tile may wander: only natural ground drops
## (not under roads, ramps or buildings below) and never under water.
func _wavy(x: int, z: int, i: int) -> bool:
	if not Game.inside(x, z):
		return false
	var l := Game.lvl(x, z)
	if l < 1 or Game.knd(x, z) == Game.K.ROAD:
		return false
	var d := Vector2i(int(OUT[i].x), int(OUT[i].z))
	var nx := x + d.x
	var nz := z + d.y
	if not Game.inside(nx, nz):
		return true
	if Game.lvl(nx, nz) >= l:
		return false
	var nk := Game.knd(nx, nz)
	return nk == Game.K.EMPTY or nk == Game.K.TREE


## One dropping edge: rounded lip and cliff, with an irregular outline that bulges
## out over the lower ground so terraces and beaches read as natural terrain.
func _edge(mk: MeshKit, x: int, z: int, i: int, c: Vector3, y: float, b0: float, b1: float, round0: bool, round1: bool, low: float, top: Color, lip: Color, l: int) -> void:
	var h := Game.TILE * 0.5
	var o: Vector3 = OUT[i]
	var t: Vector3 = ALONG[i]
	var e0 := LIP if round0 else 0.0
	var e1 := LIP if round1 else 0.0
	var yl := y - LIP
	var up := Vector3.UP
	var n_top := (up + o * 0.4).normalized()
	var n_bot := (o + up * 0.3).normalized()
	var wavy := _wavy(x, z, i)
	var seg := WAVE_SEG if wavy else 1
	# keep the outline continuous with the neighbour along the edge, else ease to zero
	var step := Vector2i(int(t.x), int(t.z))
	var keep0 := wavy and not round0 and Game.lvl(x - step.x, z - step.y) == Game.lvl(x, z) and _wavy(x - step.x, z - step.y, i)
	var keep1 := wavy and not round1 and Game.lvl(x + step.x, z + step.y) == Game.lvl(x, z) and _wavy(x + step.x, z + step.y, i)
	var pt := []
	for k in seg + 1:
		var u := float(k) / seg
		var tt := lerpf(-h + b0, h - b1, u)
		var tb := lerpf(-h + e0, h - e1, u)
		var off := 0.0
		if wavy:
			var edge_p := c + o * h + t * tb
			var taper := (1.0 if keep0 else smoothstep(0.0, 0.45, u)) * (1.0 if keep1 else smoothstep(0.0, 0.45, 1.0 - u))
			off = WAVE * _noise(edge_p.x, edge_p.z) * taper
		var base_top := Vector3(c.x, y, c.z) + t * tt + o * (h - LIP)
		pt.append([base_top, base_top + o * off, Vector3(c.x, yl, c.z) + t * tb + o * (h + off)])
	# inner (concave) corners: close the small wedge between this lip and the tile line
	for end in 2:
		if (b0 if end == 0 else b1) > 0.0 or (round0 if end == 0 else round1):
			continue
		var sgn := -1.0 if end == 0 else 1.0
		var ax := x + step.x * int(sgn)
		var az := z + step.y * int(sgn)
		if not Game.inside(ax, az) or Game.lvl(ax, az) != Game.lvl(x, z):
			continue
		var bx := ax + int(o.x)
		var bz := az + int(o.z)
		if Game.inside(bx, bz) and Game.lvl(bx, bz) < Game.lvl(ax, az):
			continue
		var p: Array = pt[0 if end == 0 else seg]
		var line := Vector3(c.x, y, c.z) + t * (h * sgn) + o * h
		mk.tri_n(p[1], line, p[2], n_top, up, n_bot, -t * sgn, lip)
	for k in seg:
		var a: Array = pt[k]
		var b: Array = pt[k + 1]
		if wavy:
			# ground that spills past the straight line
			mk.quad(a[0], b[0], b[1], a[1], up, top)
		mk.quad_n(a[1], b[1], b[2], a[2], n_top, n_top, n_bot, n_bot, lip)
		_wall(mk, a[2], b[2], low, o, l)


## Average of the top colours of the (up to four) same-level tiles around a grid corner.
func _corner(x: int, z: int, l: int, gx: int, gz: int) -> Color:
	var sum := Color(0, 0, 0, 0)
	var n := 0
	for oz in [gz - 1, gz]:
		for ox in [gx - 1, gx]:
			if Game.inside(ox, oz) and Game.lvl(ox, oz) == l:
				sum += _top_color(ox, oz, l)
				n += 1
	if n == 0:
		return _top_color(x, z, l)
	return Color(sum.r / n, sum.g / n, sum.b / n)


## Quarter-round lip and cliff for a convex terrace corner centred on `cc` (top level).
func _fillet(mk: MeshKit, cc: Vector3, sx: float, sz: float, bottom: float, lip: Color, l: int) -> void:
	const SEG := 4
	var yl := cc.y - LIP
	var top := cc
	var prev := Vector3.ZERO
	var prev_n := Vector3.ZERO
	for i in SEG + 1:
		var a := PI * 0.5 * float(i) / SEG
		var dir := Vector3(cos(a) * sx, 0, sin(a) * sz)
		var p := Vector3(cc.x, yl, cc.z) + dir * LIP
		if i > 0:
			mk.tri_n(top, prev, p, (Vector3.UP + (prev_n + dir) * 0.2).normalized(), (prev_n + Vector3.UP * 0.3).normalized(), (dir + Vector3.UP * 0.3).normalized(), (Vector3.UP + dir).normalized(), lip)
			if yl - bottom > 0.01:
				var col := _wall_color(l, cc.y)
				mk.quad_n(prev, p, Vector3(p.x, bottom, p.z), Vector3(prev.x, bottom, prev.z), prev_n, dir, dir, prev_n, col)
		prev = p
		prev_n = dir


func _wall(mk: MeshKit, a: Vector3, b: Vector3, bottom: float, out: Vector3, l: int) -> void:
	var top_y := a.y
	if top_y - bottom < 0.01:
		return
	# two bands so cliffs read as layered strata
	var mid := lerpf(top_y, bottom, 0.45)
	mk.quad(a, b, Vector3(b.x, mid, b.z), Vector3(a.x, mid, a.z), out, _wall_color(l, top_y))
	mk.quad(Vector3(a.x, mid, a.z), Vector3(b.x, mid, b.z), Vector3(b.x, bottom, b.z), Vector3(a.x, bottom, a.z), out, _wall_color(l, top_y).darkened(0.1))
