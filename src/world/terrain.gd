class_name Terrain
extends Node3D
## Island ground built in 16x16 tile chunks from one continuous height field.
## Terraces don't end in walls: each lower tile bites into the higher ground
## beside it with an eroded, noise-wandering slope (gentle at the foot, steeper
## and rocky in the middle, rounded into a grass lip at the top). Under houses
## and roads the slope is kept narrow so nothing floats. Flat tiles are a single
## quad and only tiles beside lower ground are subdivided, so it stays light.

const CHUNK := 16
# where extra rows go, measured in from a tile edge that has lower ground beyond it
const NEAR := [0.2, 0.55]
# rows along an edge so the slope can wander
const ALONG := [0.0]
# rounding of the lip where a slope meets the terrace above
const LIP_K := 0.12
# rounding of convex corners
const CORNER_K := 0.7
# natural ground vs ground carrying roads and buildings (slope squeezed this much)
const BUILT_STEEP := 3.5
const BITE := 0.45

class Hood:
	var uniq := PackedFloat32Array()
	var lvl := PackedInt32Array()
	var rx0 := PackedFloat32Array()
	var rz0 := PackedFloat32Array()
	var steep := PackedFloat32Array()
	var x0 := 0.0
	var z0 := 0.0


var material: Material
var _chunks := {}
# finished geometry per tile, so an edit only remakes the tiles it touches
var _cache := {}
# per-tile lookups refreshed before building: height, top colour, carries buildings
var _ys := PackedFloat32Array()
var _tops := PackedColorArray()
var _builts := PackedByteArray()


func _prep() -> void:
	var n := Game.N * Game.N
	_ys.resize(n)
	_tops.resize(n)
	_builts.resize(n)
	for z in Game.N:
		for x in Game.N:
			var i := Game.idx(x, z)
			_ys[i] = Game.tile_y(x, z)
			_tops[i] = _make_top(x, z, Game.lvl(x, z))
			var k := Game.knd(x, z)
			_builts[i] = 1 if k != Game.K.EMPTY and k != Game.K.TREE else 0


func build_all() -> void:
	for c in _chunks.values():
		c.queue_free()
	_chunks.clear()
	_cache.clear()
	_prep()
	var n := Game.N / CHUNK
	for cz in n:
		for cx in n:
			_build_chunk(cx, cz)


func tile_changed(x: int, z: int) -> void:
	# every tile's ground depends on its eight neighbours; only those are remade
	_prep()
	var touched := {}
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var tx: int = x + dx
			var tz: int = z + dz
			if Game.inside(tx, tz):
				_cache.erase(Vector2i(tx, tz))
				touched[Vector2i(tx / CHUNK, tz / CHUNK)] = true
	for c in touched:
		_build_chunk(c.x, c.y)


func _top_color(x: int, z: int, l: int) -> Color:
	if _tops.size() == Game.N * Game.N and Game.inside(x, z) and Game.lvl(x, z) == l:
		return _tops[Game.idx(x, z)]
	return _make_top(x, z, l)


func _make_top(x: int, z: int, l: int) -> Color:
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


# ------------------------------------------------------------------ height field

func _ty(x: int, z: int) -> float:
	if x < 0 or z < 0 or x >= Game.N or z >= Game.N:
		return Game.SEA_FLOOR
	return _ys[z * Game.N + x]


func _built(x: int, z: int) -> bool:
	if x < 0 or z < 0 or x >= Game.N or z >= Game.N:
		return false
	return _builts[z * Game.N + x] == 1


## Slope squeeze at a grid corner: built ground anywhere around it keeps slopes tight.
func _corner_steep(gx: int, gz: int) -> float:
	if _built(gx - 1, gz - 1) or _built(gx, gz - 1) or _built(gx - 1, gz) or _built(gx, gz):
		return BUILT_STEEP
	return 1.0


## Smooth 2D value noise in world space, 0..1.
func _noise(px: float, pz: float, salt: int, f: float) -> float:
	var gx := px * f
	var gz := pz * f
	var ix := floori(gx)
	var iz := floori(gz)
	var fx := gx - ix
	var fz := gz - iz
	fx = fx * fx * (3.0 - 2.0 * fx)
	fz = fz * fz * (3.0 - 2.0 * fz)
	var a := Game.hashf(ix, iz, salt)
	var b := Game.hashf(ix + 1, iz, salt)
	var c := Game.hashf(ix, iz + 1, salt)
	var d := Game.hashf(ix + 1, iz + 1, salt)
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fz)


## Eroded slope profile: rise above the lower ground at (scaled) distance u.
static func _rise(u: float) -> float:
	return 0.13 * u + 1.9 * u * u * u


static func _smin(a: float, b: float, k: float) -> float:
	var h := maxf(k - absf(a - b), 0.0) / k
	return minf(a, b) - h * h * k * 0.25


## Everything the field needs about the 3x3 tiles around (tx, tz).
func _hood(tx: int, tz: int) -> Hood:
	var hd := Hood.new()
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var x := tx + dx
			var z := tz + dz
			var y := _ty(x, z)
			var k := -1
			for u in hd.uniq.size():
				if absf(hd.uniq[u] - y) < 0.001:
					k = u
			if k < 0:
				hd.uniq.append(y)
				k = hd.uniq.size() - 1
			hd.lvl.append(k)
			hd.rx0.append((x - Game.N * 0.5) * Game.TILE)
			hd.rz0.append((z - Game.N * 0.5) * Game.TILE)
	hd.steep.append(_corner_steep(tx, tz))
	hd.steep.append(_corner_steep(tx + 1, tz))
	hd.steep.append(_corner_steep(tx, tz + 1))
	hd.steep.append(_corner_steep(tx + 1, tz + 1))
	hd.x0 = (tx - Game.N * 0.5) * Game.TILE
	hd.z0 = (tz - Game.N * 0.5) * Game.TILE
	return hd


## Ground height at world (px, pz); also reports which tile's level wins there.
func _field(hd: Hood, px: float, pz: float) -> Vector2:
	const T := Game.TILE
	# slope squeeze, bilinear across the tile so neighbours agree on shared edges
	var st := hd.steep
	var u := clampf((px - hd.x0) / T, 0.0, 1.0)
	var v := clampf((pz - hd.z0) / T, 0.0, 1.0)
	var s := lerpf(lerpf(st[0], st[1], u), lerpf(st[2], st[3], u), v)
	var natural := clampf((BUILT_STEEP - s) / (BUILT_STEEP - 1.0), 0.0, 1.0)
	var bite := 0.0
	if natural > 0.0:
		bite = _noise(px, pz, 300, 0.75) * BITE * natural
	# per level: smooth-min distance to its tiles (rounds convex corners)
	var n := hd.uniq.size()
	var dist := PackedFloat32Array()
	dist.resize(n)
	dist.fill(1e9)
	var rx0 := hd.rx0
	var rz0 := hd.rz0
	var lvl := hd.lvl
	for i in 9:
		var dx := maxf(maxf(rx0[i] - px, px - rx0[i] - T), 0.0)
		var dz := maxf(maxf(rz0[i] - pz, pz - rz0[i] - T), 0.0)
		var d := sqrt(dx * dx + dz * dz)
		var k := lvl[i]
		var a := dist[k]
		if a > 1e8:
			dist[k] = d
		else:
			var hh := maxf(CORNER_K - absf(a - d), 0.0) / CORNER_K
			dist[k] = minf(a, d) - hh * hh * CORNER_K * 0.25
	var h := INF
	var win := 0.0
	var best := INF
	for k in n:
		var w := maxf(dist[k] * s - bite, 0.0)
		var val: float = hd.uniq[k] + 0.13 * w + 1.9 * w * w * w
		if val < best:
			best = val
			win = hd.uniq[k]
		if h == INF:
			h = val
		else:
			var hh := maxf(LIP_K - absf(h - val), 0.0) / LIP_K
			h = minf(h, val) - hh * hh * LIP_K * 0.25
	return Vector2(h, win)


# ------------------------------------------------------------------ meshing

func _build_chunk(cx: int, cz: int) -> void:
	var key := Vector2i(cx, cz)
	if _chunks.has(key):
		_chunks[key].queue_free()
	var mk := MeshKit.new()
	# open sea at full depth is one flat floor: merged into a few big quads
	var deep := PackedByteArray()
	deep.resize(CHUNK * CHUNK)
	for z in range(cz * CHUNK, (cz + 1) * CHUNK):
		for x in range(cx * CHUNK, (cx + 1) * CHUNK):
			var t := Vector2i(x, z)
			if not _cache.has(t):
				var tk := MeshKit.new()
				tk.shadow = false
				var d := _deep(x, z)
				if not d:
					_tile(tk, x, z)
				_cache[t] = [tk.verts, tk.norms, tk.cols, tk.uvs, tk.bverts, tk.bcols, tk.buvs, tk.bradius, d]
			var a: Array = _cache[t]
			if a[8]:
				deep[(z - cz * CHUNK) * CHUNK + x - cx * CHUNK] = 1
				continue
			mk.verts.append_array(a[0])
			mk.norms.append_array(a[1])
			mk.cols.append_array(a[2])
			mk.uvs.append_array(a[3])
			mk.bverts.append_array(a[4])
			mk.bcols.append_array(a[5])
			mk.buvs.append_array(a[6])
			mk.bradius.append_array(a[7])
	_merge_deep(mk, cx, cz, deep)
	var mi := MeshInstance3D.new()
	mi.mesh = mk.commit(material)
	# the ground only receives shadows; drawing it into the shadow map is wasted work
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_chunks[key] = mi


## Sea tile at the deepest floor with only deepest floor around it.
func _deep(x: int, z: int) -> bool:
	if Game.lvl(x, z) != 0:
		return false
	var y := _ty(x, z)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			if absf(_ty(x + dx, z + dz) - y) > 0.0001:
				return false
	return true


## Greedy rectangles over the chunk's deep tiles. Under that much water the
## per-tile colour jitter can't be seen, so they share the plain sea floor colour.
func _merge_deep(mk: MeshKit, cx: int, cz: int, deep: PackedByteArray) -> void:
	var col := Color(0.78, 0.74, 0.58)
	var h := Game.TILE * 0.5
	for j in CHUNK:
		for i in CHUNK:
			if deep[j * CHUNK + i] == 0:
				continue
			var y := _ty(cx * CHUNK + i, cz * CHUNK + j)
			var i1 := i
			while i1 + 1 < CHUNK and deep[j * CHUNK + i1 + 1] == 1 and absf(_ty(cx * CHUNK + i1 + 1, cz * CHUNK + j) - y) < 0.0001:
				i1 += 1
			var j1 := j
			var grow := true
			while grow and j1 + 1 < CHUNK:
				for k in range(i, i1 + 1):
					if deep[(j1 + 1) * CHUNK + k] == 0 or absf(_ty(cx * CHUNK + k, cz * CHUNK + j1 + 1) - y) > 0.0001:
						grow = false
						break
				if grow:
					j1 += 1
			for jj in range(j, j1 + 1):
				for k in range(i, i1 + 1):
					deep[jj * CHUNK + k] = 0
			var a := Game.tile_center(cx * CHUNK + i, cz * CHUNK + j)
			var b := Game.tile_center(cx * CHUNK + i1, cz * CHUNK + j1)
			var x0 := a.x - h
			var x1 := b.x + h
			var z0 := a.z - h
			var z1 := b.z + h
			mk.quad_c(Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z1), col, col, col, col)


func _tile(mk: MeshKit, x: int, z: int) -> void:
	var l := Game.lvl(x, z)
	var y := _ty(x, z)
	# which sides (including diagonals) have lower ground
	var lo_px := false
	var lo_nx := false
	var lo_pz := false
	var lo_nz := false
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			if _ty(x + dx, z + dz) < y - 0.001:
				if dx > 0: lo_px = true
				if dx < 0: lo_nx = true
				if dz > 0: lo_pz = true
				if dz < 0: lo_nz = true
	var flat := not (lo_px or lo_nx or lo_pz or lo_nz)
	if flat or l == 0:
		_flat_tile(mk, x, z, l, flat)
	else:
		_slope_tile(mk, x, z, l, [lo_px, lo_nx, lo_pz, lo_nz])
	_dress(mk, x, z, l)


## One quad: flat terrace top, or (under the sea) a smooth seabed ramp.
func _flat_tile(mk: MeshKit, x: int, z: int, l: int, flat: bool) -> void:
	var c := Game.tile_center(x, z)
	var h := Game.TILE * 0.5
	var pts: Array[Vector3] = []
	var cols: Array[Color] = []
	var hd: Hood = null if flat else _hood(x, z)
	for k in 4:
		var gx: int = [x, x + 1, x + 1, x][k]
		var gz: int = [z, z, z + 1, z + 1][k]
		var p := Vector3(c.x + (h if gx > x else -h), c.y, c.z + (h if gz > z else -h))
		if not flat:
			p.y = _field(hd, p.x, p.z).x
		pts.append(p)
		cols.append(_corner(x, z, l, gx, gz))
	mk.quad_c(pts[0], pts[1], pts[2], pts[3], cols[0], cols[1], cols[2], cols[3])


func _axis(lo_neg: bool, lo_pos: bool, wavy: bool) -> PackedFloat32Array:
	var h := Game.TILE * 0.5
	var out := {-h: true, h: true}
	if wavy:
		for a in ALONG:
			out[a * h] = true
	for n in NEAR:
		if lo_neg:
			out[-h + n] = true
		if lo_pos:
			out[h - n] = true
	var keys := out.keys()
	keys.sort()
	return PackedFloat32Array(keys)


func _slope_tile(mk: MeshKit, x: int, z: int, l: int, lo: Array) -> void:
	var c := Game.tile_center(x, z)
	var hd := _hood(x, z)
	# rows across a drop, plus rows along it so the slope can wander
	var xs := _axis(lo[1], lo[0], lo[2] or lo[3])
	var zs := _axis(lo[3], lo[2], lo[0] or lo[1])
	var nx := xs.size()
	var nz := zs.size()
	var corners := [_corner(x, z, l, x, z), _corner(x, z, l, x + 1, z), _corner(x, z, l, x, z + 1), _corner(x, z, l, x + 1, z + 1)]
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	var col := PackedColorArray()
	for j in nz:
		for i in nx:
			var px := c.x + xs[i]
			var pz := c.z + zs[j]
			var f := _field(hd, px, pz)
			var e := 0.05
			var gx := (_field(hd, px + e, pz).x - f.x) / e
			var gz := (_field(hd, px, pz + e).x - f.x) / e
			var n := Vector3(-gx, 1.0, -gz).normalized()
			var steep := clampf((Vector2(gx, gz).length() - 0.3) / 0.9, 0.0, 1.0)
			if steep > 0.0:
				# rough rock: break up the normal a little
				var r := Vector3(_noise(px, pz, 310, 3.1) - 0.5, 0.0, _noise(px, pz, 311, 3.1) - 0.5)
				n = (n + r * 0.6 * steep).normalized()
			pos.append(Vector3(px, f.x, pz))
			nrm.append(n)
			col.append(_ground_color(x, z, l, f, px, pz, steep, corners))
	# cells lying flat on the terrace top are merged into larger rectangles
	# (collinear edges, so no cracks); only the slope itself keeps the fine grid
	var cw := nx - 1
	var level := PackedByteArray()
	level.resize(cw * (nz - 1))
	for j in nz - 1:
		for i in cw:
			var a := j * nx + i
			level[j * cw + i] = 1 if _flat_v(pos, nrm, a, pos[a].y) and _flat_v(pos, nrm, a + 1, pos[a].y) \
				and _flat_v(pos, nrm, a + nx, pos[a].y) and _flat_v(pos, nrm, a + nx + 1, pos[a].y) else 0
	for j in nz - 1:
		for i in cw:
			var a := j * nx + i
			if level[j * cw + i] == 1:
				var y := pos[a].y
				var i1 := i
				while i1 + 1 < cw and level[j * cw + i1 + 1] == 1 and absf(pos[a + i1 + 1 - i].y - y) < 1e-5:
					i1 += 1
				var j1 := j
				var grow := true
				while grow and j1 + 1 < nz - 1:
					for k in range(i, i1 + 1):
						if level[(j1 + 1) * cw + k] != 1 or absf(pos[(j1 + 1) * nx + k].y - y) > 1e-5:
							grow = false
							break
					if grow:
						j1 += 1
				for jj in range(j, j1 + 1):
					for k in range(i, i1 + 1):
						level[jj * cw + k] = 2
				var b := j * nx + i1 + 1
				var cc := (j1 + 1) * nx + i1 + 1
				var d := (j1 + 1) * nx + i
				_tri(mk, pos, nrm, col, a, b, cc)
				_tri(mk, pos, nrm, col, a, cc, d)
				continue
			if level[j * cw + i] == 2:
				continue
			var b := a + 1
			var cc := a + nx + 1
			var d := a + nx
			# split along the diagonal that follows the slope best
			if absf(pos[a].y - pos[cc].y) <= absf(pos[b].y - pos[d].y):
				_tri(mk, pos, nrm, col, a, b, cc)
				_tri(mk, pos, nrm, col, a, cc, d)
			else:
				_tri(mk, pos, nrm, col, a, b, d)
				_tri(mk, pos, nrm, col, b, cc, d)


func _flat_v(pos: PackedVector3Array, nrm: PackedVector3Array, i: int, y: float) -> bool:
	return absf(pos[i].y - y) < 1e-5 and nrm[i].y > 0.99999


func _tri(mk: MeshKit, pos: PackedVector3Array, nrm: PackedVector3Array, col: PackedColorArray, a: int, b: int, c: int) -> void:
	var p0 := pos[a]
	var p1 := pos[b]
	var p2 := pos[c]
	var n0 := nrm[a]
	var n1 := nrm[b]
	var n2 := nrm[c]
	var c0 := col[a]
	var c1 := col[b]
	var c2 := col[c]
	# clockwise seen from above is front-facing in Godot
	if (p1 - p0).cross(p2 - p0).y > 0.0:
		var tp := p1; p1 = p2; p2 = tp
		var tn := n1; n1 = n2; n2 = tn
		var tc := c1; c1 = c2; c2 = tc
	mk._v(p0, n0, c0, 0.0, 0.0)
	mk._v(p1, n1, c1, 0.0, 0.0)
	mk._v(p2, n2, c2, 0.0, 0.0)


## Colour of the ground: the winning level's own top colour, turning to banded
## earth or stone (sand by the sea) where it is steep.
func _ground_color(x: int, z: int, l: int, f: Vector2, px: float, pz: float, steep: float, corners: Array) -> Color:
	var base: Color
	if absf(f.y - _ty(x, z)) < 0.002:
		# this tile's own terrace: blend its corner colours like the flat tiles do
		var c := Game.tile_center(x, z)
		var u := clampf((px - c.x) / Game.TILE + 0.5, 0.0, 1.0)
		var v := clampf((pz - c.z) / Game.TILE + 0.5, 0.0, 1.0)
		base = (corners[0] as Color).lerp(corners[1], u).lerp((corners[2] as Color).lerp(corners[3], u), v)
	else:
		base = _level_color(x, z, f.y)
	if steep <= 0.0:
		return base
	var hgt := f.x
	var band := 0.045 * sin(hgt * 21.0 + _noise(px, pz, 320, 1.3) * 5.0)
	var rock: Color
	if hgt < 0.12:
		rock = Color(0.8, 0.71, 0.54)
	elif l >= 5:
		rock = Color(0.6 + band, 0.58 + band, 0.55 + band)
	else:
		rock = Color(0.68 + band, 0.55 + band, 0.41 + band)
	return base.lerp(rock, steep)


## Top colour of the neighbouring tile that sits at height y (nearest one).
func _level_color(x: int, z: int, y: float) -> Color:
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			if Game.inside(x + dx, z + dz) and absf(_ty(x + dx, z + dz) - y) < 0.002:
				return _top_color(x + dx, z + dz, Game.lvl(x + dx, z + dz))
	return _top_color(x, z, maxi(0, Game.lvl(x, z) - 1))


## Flowers, pebbles and scree. Round bits are sphere sprites (2 triangles each).
func _dress(mk: MeshKit, x: int, z: int, l: int) -> void:
	if Game.knd(x, z) != Game.K.EMPTY or l < 1:
		return
	var c := Game.tile_center(x, z)
	var r := Game.hashf(x, z, 21)
	if l >= 5 and r < 0.7:
		mk.blob(c + Vector3(Game.hashf(x, z, 22) - 0.5, 0.05, Game.hashf(x, z, 23) - 0.5), Vector3(0.24, 0.16, 0.2), Color(0.66, 0.64, 0.6))
		mk.blob(c + Vector3(Game.hashf(x, z, 24) - 0.5, 0.03, Game.hashf(x, z, 25) - 0.5), Vector3(0.13, 0.1, 0.12), Color(0.6, 0.58, 0.55))
	elif l >= 2 and r < 0.35:
		var fc: Color = [Color(1, 0.85, 0.35), Color(1, 0.6, 0.7), Color(0.95, 0.95, 1), Color(0.75, 0.6, 1)][Game.hash2(x, z, 24) % 4]
		var cc := c + Vector3(Game.hashf(x, z, 30) * 1.0 - 0.5, 0.0, Game.hashf(x, z, 40) * 1.0 - 0.5)
		mk.blob(cc + Vector3(0, 0.02, 0), Vector3(0.08, 0.08, 0.08), Color(0.42, 0.68, 0.33))
		for k in 2:
			var p := cc + Vector3(Game.hashf(x, z, 31 + k) * 0.14 - 0.07, 0.085, Game.hashf(x, z, 41 + k) * 0.14 - 0.07)
			mk.blob(p, Vector3(0.042, 0.042, 0.042), fc)
	elif l == 1 and r < 0.12:
		mk.blob(c + Vector3(Game.hashf(x, z, 22) - 0.5, 0.03, Game.hashf(x, z, 23) - 0.5), Vector3(0.14, 0.06, 0.1), Color(0.98, 0.95, 0.9))
	# scree: loose rocks at the foot of a bigger slope from natural ground above
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for i in 4:
		var d: Vector2i = dirs[i]
		var nx := x + d.x
		var nz := z + d.y
		if not Game.inside(nx, nz) or _built(nx, nz) or _ty(nx, nz) - c.y < 0.25:
			continue
		for k in 2:
			if Game.hashf(x, z, 50 + i * 2 + k) > 0.55:
				continue
			var along := Game.hashf(x, z, 60 + i * 2 + k) * 1.6 - 0.8
			var into := 0.2 + Game.hashf(x, z, 70 + i * 2 + k) * 0.35
			var side := Vector3(absf(d.y), 0, absf(d.x))
			var p := c + Vector3(d.x, 0, d.y) * (Game.TILE * 0.5 - into) + side * along
			var rr := 0.06 + Game.hashf(x, z, 80 + i * 2 + k) * 0.07
			var g := 0.55 + Game.hashf(x, z, 90 + i) * 0.1
			mk.blob(p + Vector3(0, rr * 0.35, 0), Vector3(rr, rr, rr), Color(g + 0.05, g, g - 0.04))
