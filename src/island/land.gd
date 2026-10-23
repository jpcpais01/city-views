class_name Land
extends Node3D
## The new island's ground: one continuous height field (no tiles), grown from
## noise into hills, ridges, coves, beaches and the odd cliff, and reshaped by
## the player's brushes. Built in chunks so a brush stroke only remakes the
## ground it touched.

const SIZE := 128.0
const HALF := SIZE * 0.5
const CELLS := 128
const STEP := SIZE / CELLS
const SIDE := CELLS + 1
const CHUNK := 16
const LOW := -4.6
const HIGH := 11.0
# sea floor deeper than this is drawn coarser (it is barely seen through the water)
const DEEP := -1.4
# heights in the shader's ground map run from -MAP_BIAS to MAP_SCALE - MAP_BIAS
const MAP_SCALE := 16.0
const MAP_BIAS := 1.0

signal changed

var material: Material
var heights := PackedFloat32Array()
var _base := PackedFloat32Array()
# where the player has asked the town to grow, 0..1 per ground sample
var zone := PackedFloat32Array()
# where the player has asked for green (parks and gardens instead of houses), 0..1
var green := PackedFloat32Array()
# tint the painted area strongly (while the Grow brush is in hand)
var show_zone := false:
	set(v):
		if v != show_zone:
			show_zone = v
			for c in _chunks.keys():
				_dirty[c] = true
var _chunks := {}
# a coarser copy of the ground drawn only into the shadow map, so hills cast
# shadows across the valleys for a quarter of the triangles
var _shadow: MeshInstance3D
var _shadow_dirty := true
var _dirty := {}
var _noise := FastNoiseLite.new()
var _warp := FastNoiseLite.new()
var _detail := FastNoiseLite.new()


## Fresh island for a seed.
func generate(seed_value: int) -> void:
	_noise.seed = seed_value
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise.fractal_octaves = 3
	_noise.fractal_gain = 0.36
	_noise.frequency = 1.0 / 64.0
	_warp.seed = seed_value + 17
	_warp.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_warp.fractal_octaves = 3
	_warp.frequency = 1.0 / 40.0
	_detail.seed = seed_value + 31
	_detail.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_detail.fractal_octaves = 2
	_detail.frequency = 1.0 / 9.0
	heights.resize(SIDE * SIDE)
	for j in SIDE:
		for i in SIDE:
			heights[j * SIDE + i] = _natural(_pos(i, j))
	_base = heights.duplicate()
	zone.resize(SIDE * SIDE)
	zone.fill(0.0)
	green.resize(SIDE * SIDE)
	green.fill(0.0)
	for c in _chunks.values():
		c.queue_free()
	_chunks.clear()
	for cz in CELLS / CHUNK:
		for cx in CELLS / CHUNK:
			_dirty[Vector2i(cx, cz)] = true
	rebuild_dirty(1 << 20)
	rebuild_shadow()
	changed.emit()


func _pos(i: int, j: int) -> Vector2:
	return Vector2(i * STEP - HALF, j * STEP - HALF)


## The untouched landscape at a point: a warped, roughly round island whose
## coast wanders, inland hills and ridges, broad beaches and a few cliffs.
func _natural(p: Vector2) -> float:
	var w := Vector2(_warp.get_noise_2d(p.x, p.y), _warp.get_noise_2d(p.x + 91.0, p.y - 37.0)) * 20.0
	w += Vector2(_detail.get_noise_2d(p.x * 0.5, p.y * 0.5), _detail.get_noise_2d(p.x * 0.5 + 50.0, p.y * 0.5)) * 2.0
	var q := p + w
	var r := q.length() / HALF
	# where the coast is cliffy the land rises sharply out of the sea
	var cliff := smoothstep(0.3, 0.55, _warp.get_noise_2d(q.x * 0.6 - 200.0, q.y * 0.6))
	var mask := 1.0 - smoothstep(lerpf(0.42, 0.62, cliff), lerpf(0.86, 0.72, cliff), r)
	var hills := (_noise.get_noise_2d(q.x, q.y) * 0.5 + 0.5)
	# mostly broad, gentle land that a town can spread over, with a few real hills
	hills = pow(hills, 2.7) * 17.0
	# a ridge line here and there
	var ridge := 1.0 - absf(_noise.get_noise_2d(q.x * 0.7 + 400.0, q.y * 0.7))
	hills += pow(ridge, 6.0) * 3.0 * smoothstep(0.0, 0.4, _warp.get_noise_2d(q.x * 0.5 + 300.0, q.y * 0.5))
	var inland := smoothstep(0.2, 0.9, mask)
	inland *= inland
	var land := 0.8 + hills * inland + _detail.get_noise_2d(p.x, p.y) * 0.12 + cliff * 1.6 * smoothstep(0.0, 0.3, mask)
	var h := lerpf(LOW, land, mask)
	return _beach(h)


## Flattens the ground just above and below the waterline into wide beaches.
func _beach(h: float) -> float:
	if h > 0.0:
		return h * smoothstep(-0.2, 1.6, h)
	return h * smoothstep(-0.4, -2.0, h) + h * 0.35


func index(i: int, j: int) -> int:
	return clampi(j, 0, CELLS) * SIDE + clampi(i, 0, CELLS)


## Ground height at a world point (bilinear between samples; sea floor outside).
func height_at(x: float, z: float) -> float:
	var fx := (x + HALF) / STEP
	var fz := (z + HALF) / STEP
	if fx < 0.0 or fz < 0.0 or fx > CELLS or fz > CELLS:
		return LOW
	var i := mini(int(fx), CELLS - 1)
	var j := mini(int(fz), CELLS - 1)
	var u := fx - i
	var v := fz - j
	var a := heights[j * SIDE + i]
	var b := heights[j * SIDE + i + 1]
	var c := heights[(j + 1) * SIDE + i]
	var d := heights[(j + 1) * SIDE + i + 1]
	return lerpf(lerpf(a, b, u), lerpf(c, d, u), v)


func normal_at(x: float, z: float) -> Vector3:
	var e := STEP
	return Vector3(height_at(x - e, z) - height_at(x + e, z), 2.0 * e, height_at(x, z - e) - height_at(x, z + e)).normalized()


## Where a screen ray first meets the ground (or the sea surface); null if it misses.
func raycast(origin: Vector3, dir: Vector3) -> Variant:
	var t := 0.0
	var prev := origin
	while t < 600.0:
		var p := origin + dir * t
		var g := maxf(height_at(p.x, p.z), 0.0)
		if p.y <= g:
			# refine between the last point above ground and this one
			var lo := prev
			var hi := p
			for k in 8:
				var m := (lo + hi) * 0.5
				if m.y <= maxf(height_at(m.x, m.z), 0.0):
					hi = m
				else:
					lo = m
			return hi
		prev = p
		t += clampf((p.y - g) * 0.5, 0.15, 3.0)
	return null


# ------------------------------------------------------------------ brushes

## Raise (amount > 0) or lower the ground in a soft circle.
func sculpt(centre: Vector3, radius: float, amount: float) -> void:
	_each_in(centre, radius, func(k: int, w: float) -> void:
		heights[k] = clampf(heights[k] + amount * w, LOW, HIGH))


## Relax bumps and pits towards their neighbours' average.
func smooth(centre: Vector3, radius: float, amount: float) -> void:
	var src := heights.duplicate()
	_each_in(centre, radius, func(k: int, w: float) -> void:
		var i := k % SIDE
		var j := k / SIDE
		var avg := (src[index(i - 1, j)] + src[index(i + 1, j)] + src[index(i, j - 1)] + src[index(i, j + 1)]) * 0.25
		heights[k] = lerpf(src[k], avg, clampf(amount * w, 0.0, 1.0)))


## Paint (amount > 0) or wipe where the town should grow.
func paint_zone(centre: Vector3, radius: float, amount: float) -> void:
	_each_in(centre, radius, func(k: int, w: float) -> void:
		zone[k] = clampf(zone[k] + amount * minf(w * 2.0, 1.0), 0.0, 1.0))


func zone_at(x: float, z: float) -> float:
	return _sample(zone, x, z)


## Paint (amount > 0) or wipe green: parks where houses would go.
func paint_green(centre: Vector3, radius: float, amount: float) -> void:
	_each_in(centre, radius, func(k: int, w: float) -> void:
		green[k] = clampf(green[k] + amount * minf(w * 2.0, 1.0), 0.0, 1.0))


func green_at(x: float, z: float) -> float:
	return _sample(green, x, z)


func _sample(a: PackedFloat32Array, x: float, z: float) -> float:
	var fx := (x + HALF) / STEP
	var fz := (z + HALF) / STEP
	if fx < 0.0 or fz < 0.0 or fx > CELLS or fz > CELLS:
		return 0.0
	var i := mini(int(fx), CELLS - 1)
	var j := mini(int(fz), CELLS - 1)
	var u := fx - i
	var v := fz - j
	return lerpf(lerpf(a[j * SIDE + i], a[j * SIDE + i + 1], u), lerpf(a[(j + 1) * SIDE + i], a[(j + 1) * SIDE + i + 1], u), v)


## Ease the ground towards a level (the height where the stroke started).
func flatten(centre: Vector3, radius: float, level: float, amount: float) -> void:
	_each_in(centre, radius, func(k: int, w: float) -> void:
		heights[k] = lerpf(heights[k], level, clampf(amount * w, 0.0, 1.0)))


func _each_in(centre: Vector3, radius: float, f: Callable) -> void:
	var i0 := maxi(0, int(floor((centre.x - radius + HALF) / STEP)))
	var i1 := mini(CELLS, int(ceil((centre.x + radius + HALF) / STEP)))
	var j0 := maxi(0, int(floor((centre.z - radius + HALF) / STEP)))
	var j1 := mini(CELLS, int(ceil((centre.z + radius + HALF) / STEP)))
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var p := _pos(i, j)
			var d := p.distance_to(Vector2(centre.x, centre.z)) / radius
			if d >= 1.0:
				continue
			var w := (1.0 - d * d)
			f.call(j * SIDE + i, w * w)
	# the island's rim stays under the sea so it never shows a cut edge
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			if i <= 1 or j <= 1 or i >= CELLS - 1 or j >= CELLS - 1:
				heights[j * SIDE + i] = minf(heights[j * SIDE + i], LOW)
	_mark(i0, j0, i1, j1)


## The ground samples changed since take_touched() was last called, as a box.
var touched_lo := Vector2i(1 << 20, 1 << 20)
var touched_hi := Vector2i(-1, -1)


func take_touched() -> Rect2i:
	var r := Rect2i(touched_lo, touched_hi - touched_lo + Vector2i.ONE) if touched_hi.x >= 0 else Rect2i()
	touched_lo = Vector2i(1 << 20, 1 << 20)
	touched_hi = Vector2i(-1, -1)
	return r


func _mark(i0: int, j0: int, i1: int, j1: int) -> void:
	touched_lo = touched_lo.min(Vector2i(maxi(i0, 0), maxi(j0, 0)))
	touched_hi = touched_hi.max(Vector2i(mini(i1, CELLS), mini(j1, CELLS)))
	for cz in range(maxi(0, (j0 - 1) / CHUNK), mini(CELLS / CHUNK - 1, (j1 + 1) / CHUNK) + 1):
		for cx in range(maxi(0, (i0 - 1) / CHUNK), mini(CELLS / CHUNK - 1, (i1 + 1) / CHUNK) + 1):
			_dirty[Vector2i(cx, cz)] = true


## Cut and fill the ground to meet a street: flat at the street's height within
## `core` of its centre line, easing back into the natural slope over `blend`.
## With `lower_only`, ground is only ever cut down to the street (where streets
## meet, so neither street's ground pokes up through the other's asphalt).
func conform(pts: PackedVector2Array, ys: PackedFloat32Array, core: float, blend: float, lower_only := false) -> void:
	if pts.size() < 2:
		return
	var reach := core + blend
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in pts:
		lo = lo.min(p)
		hi = hi.max(p)
	var i0 := maxi(2, int(floor((lo.x - reach + HALF) / STEP)))
	var i1 := mini(CELLS - 2, int(ceil((hi.x + reach + HALF) / STEP)))
	var j0 := maxi(2, int(floor((lo.y - reach + HALF) / STEP)))
	var j1 := mini(CELLS - 2, int(ceil((hi.y + reach + HALF) / STEP)))
	if i0 > i1 or j0 > j1:
		return
	var w := i1 - i0 + 1
	var best := PackedFloat32Array()
	var by := PackedFloat32Array()
	best.resize(w * (j1 - j0 + 1))
	best.fill(INF)
	by.resize(best.size())
	for s in pts.size() - 1:
		var a := pts[s]
		var b := pts[s + 1]
		var ab := b - a
		var l2 := maxf(ab.length_squared(), 1e-6)
		var si0 := maxi(i0, int(floor((minf(a.x, b.x) - reach + HALF) / STEP)))
		var si1 := mini(i1, int(ceil((maxf(a.x, b.x) + reach + HALF) / STEP)))
		var sj0 := maxi(j0, int(floor((minf(a.y, b.y) - reach + HALF) / STEP)))
		var sj1 := mini(j1, int(ceil((maxf(a.y, b.y) + reach + HALF) / STEP)))
		for j in range(sj0, sj1 + 1):
			for i in range(si0, si1 + 1):
				var p := _pos(i, j)
				var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
				var d := p.distance_to(a + ab * t)
				var k := (j - j0) * w + (i - i0)
				if d < best[k]:
					best[k] = d
					by[k] = lerpf(ys[s], ys[s + 1], t)
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var k := (j - j0) * w + (i - i0)
			var d := best[k]
			if d >= reach:
				continue
			var wt := 1.0 if d <= core else 1.0 - smoothstep(0.0, 1.0, (d - core) / maxf(blend, 0.01))
			var g := j * SIDE + i
			var target := lerpf(heights[g], by[k] - 0.03, wt)
			heights[g] = minf(heights[g], target) if lower_only else target
	_mark(i0, j0, i1, j1)


## Level a building plot: flat at `level` inside the outline, easing back to
## the natural ground over `blend` around it (a terrace cut into a hillside).
func pad(outline: PackedVector2Array, level: float, blend: float, keep_off := Callable()) -> void:
	var lo := outline[0]
	var hi := outline[0]
	for p in outline:
		lo = lo.min(p)
		hi = hi.max(p)
	var i0 := maxi(2, int(floor((lo.x - blend + HALF) / STEP)))
	var i1 := mini(CELLS - 2, int(ceil((hi.x + blend + HALF) / STEP)))
	var j0 := maxi(2, int(floor((lo.y - blend + HALF) / STEP)))
	var j1 := mini(CELLS - 2, int(ceil((hi.y + blend + HALF) / STEP)))
	if i0 > i1 or j0 > j1:
		return
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var p := _pos(i, j)
			var d := 0.0
			if not Geometry2D.is_point_in_polygon(p, outline):
				d = INF
				for k in outline.size():
					d = minf(d, Geometry2D.get_closest_point_to_segment(p, outline[k], outline[(k + 1) % outline.size()]).distance_to(p))
			if d >= blend or (keep_off.is_valid() and keep_off.call(p)):
				continue
			var g := j * SIDE + i
			heights[g] = lerpf(heights[g], level, 1.0 - smoothstep(0.0, 1.0, d / blend))
	_mark(i0, j0, i1, j1)


## Remake changed chunks, spending at most `budget_us` microseconds.
func rebuild_dirty(budget_us := 4000) -> void:
	var start := Time.get_ticks_usec()
	for c in _dirty.keys():
		_build_chunk(c)
		_dirty.erase(c)
		if Time.get_ticks_usec() - start > budget_us:
			break


func is_settled() -> bool:
	return _dirty.is_empty()


## Remake the shadow stand-in (call once a stroke has finished).
func rebuild_shadow() -> void:
	const S := 2
	var n := CELLS / S + 1
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	verts.resize(n * n)
	for j in n:
		for i in n:
			var p := _pos(i * S, j * S)
			# sunk a little so the real ground never shadows itself in stripes
			# and never above the real ground around it, so cuttings and streets stay lit
			var gi := i * S
			var gj := j * S
			var h := heights[gj * SIDE + gi]
			if h > -0.6:
				if gi > 0 and gj > 0 and gi < CELLS and gj < CELLS:
					var k := gj * SIDE + gi
					h = minf(minf(minf(h, heights[k - 1]), minf(heights[k + 1], heights[k - SIDE])), minf(minf(heights[k + SIDE], heights[k - SIDE - 1]), minf(minf(heights[k - SIDE + 1], heights[k + SIDE - 1]), heights[k + SIDE + 1])))
				else:
					for dj in range(-1, 2):
						for di in range(-1, 2):
							h = minf(h, heights[index(gi + di, gj + dj)])
			verts[j * n + i] = Vector3(p.x, maxf(h, -0.6) - 0.12, p.y)
	for j in n - 1:
		for i in n - 1:
			var a := j * n + i
			# nothing on the sea floor needs shading by the ground
			if maxf(maxf(verts[a].y, verts[a + 1].y), maxf(verts[a + n].y, verts[a + n + 1].y)) < -0.65:
				continue
			idx.append_array([a, a + 1, a + n, a + 1, a + n + 1, a + n])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	if _shadow == null:
		_shadow = MeshInstance3D.new()
		_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		add_child(_shadow)
	m.surface_set_material(0, CityGen.shadow_material())
	_shadow.mesh = m


# ------------------------------------------------------------------ mesh

func _build_chunk(c: Vector2i) -> void:
	var n := CHUNK + 1
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	verts.resize(n * n)
	norms.resize(n * n)
	cols.resize(n * n)
	for j in n:
		for i in n:
			var gi := c.x * CHUNK + i
			var gj := c.y * CHUNK + j
			var h := heights[gj * SIDE + gi]
			var p := _pos(gi, gj)
			var hx := heights[index(gi + 1, gj)] - heights[index(gi - 1, gj)]
			var hz := heights[index(gi, gj + 1)] - heights[index(gi, gj - 1)]
			var nrm := Vector3(-hx, 2.0 * STEP, -hz).normalized()
			var k := j * n + i
			verts[k] = Vector3(p.x, h, p.y)
			norms[k] = nrm
			# hollows a touch darker, crests a touch lighter: the land's shape reads from any angle
			var lap := (heights[index(gi - 2, gj)] + heights[index(gi + 2, gj)] + heights[index(gi, gj - 2)] + heights[index(gi, gj + 2)] - 4.0 * h) / (4.0 * STEP * STEP)
			var col := _colour(p, h, nrm.y)
			var zn := zone[gj * SIDE + gi]
			if zn > 0.0 and h > 0.0:
				col = col.lerp(Color("f4e3b0"), zn * 0.45) if show_zone else col.lerp(Color("b5c97a"), zn * 0.18)
			var gn := green[gj * SIDE + gi]
			if gn > 0.0 and h > 0.0:
				# park lawns, a lusher green
				col = col.lerp(Color("74bf5e"), gn * (0.5 if show_zone else 0.3))
			if h > -0.3:
				col = col.darkened(clampf(lap * 0.9, 0.0, 0.14)) if lap > 0.0 else col.lightened(clampf(-lap * 0.5, 0.0, 0.08))
			cols[k] = col
	const B := 8
	for bj in CHUNK / B:
		for bi in CHUNK / B:
			var deep := true
			for j in range(bj * B, bj * B + B + 1):
				for i in range(bi * B, bi * B + B + 1):
					if verts[j * n + i].y > DEEP:
						deep = false
			if deep:
				# deep sea floor, seen only faintly through the water: a fan from the
				# middle out to every edge vertex, so it still meets its neighbours exactly
				var ring := PackedInt32Array()
				for i in range(bi * B, bi * B + B):
					ring.append(bj * B * n + i)
				for j in range(bj * B, bj * B + B):
					ring.append(j * n + bi * B + B)
				for i in range(bi * B + B, bi * B, -1):
					ring.append((bj * B + B) * n + i)
				for j in range(bj * B + B, bj * B, -1):
					ring.append(j * n + bi * B)
				var mid := (bj * B + B / 2) * n + bi * B + B / 2
				for k in ring.size():
					idx.append_array([mid, ring[k], ring[(k + 1) % ring.size()]])
				continue
			for j in range(bj * B, bj * B + B):
				for i in range(bi * B, bi * B + B):
					var a := j * n + i
					var b := a + 1
					var cc := a + n
					var d := cc + 1
					# split each square along the diagonal that follows the land best
					if absf(verts[a].y - verts[d].y) < absf(verts[b].y - verts[cc].y):
						idx.append_array([a, b, d, a, d, cc])
					else:
						idx.append_array([a, b, cc, b, d, cc])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	m.surface_set_material(0, material)
	var mi: MeshInstance3D = _chunks.get(c)
	if mi == null:
		mi = MeshInstance3D.new()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_chunks[c] = mi
	mi.mesh = m


## Ground colour from height, steepness and a little noise: wet and dry sand,
## meadow grass that is lusher low down and drier up high, rock on steep slopes.
func _colour(p: Vector2, h: float, up: float) -> Color:
	var n := _detail.get_noise_2d(p.x * 1.7, p.y * 1.7)
	var slope := 1.0 - up
	var sand_line := 0.32 + n * 0.12
	var col: Color
	if h < -0.05:
		col = Color("d9c9a0").darkened(clampf(-h * 0.06, 0.0, 0.25))
	elif h < sand_line:
		col = Color("efe0b4").lerp(Color("e2cf9c"), clampf(0.5 - h * 2.0, 0.0, 1.0))
	else:
		var lush := Color("7fbf5f")
		var dry := Color("a9c46a")
		col = lush.lerp(dry, clampf(h / 8.0 + n * 0.3, 0.0, 1.0))
		col = col.lerp(Color("efe0b4"), 1.0 - smoothstep(sand_line, sand_line + 0.18, h))
	var rock := Color("a49d90").lerp(Color("8a847a"), clampf(n + 0.5, 0.0, 1.0))
	col = col.lerp(rock, smoothstep(0.3, 0.45, slope + n * 0.06))
	return col


# ------------------------------------------------------------------ maps for shaders

## Distance from every sea point to the nearest land, in world units (capped),
## for the water shader's foam and calm shallows.
func shore_image(cap: float) -> Image:
	var big := 1e6
	var d := PackedFloat32Array()
	d.resize(SIDE * SIDE)
	for k in SIDE * SIDE:
		d[k] = 0.0 if heights[k] > 0.0 else big
	# two-pass chamfer distance (3-4 weights), good to a few percent
	var a := STEP
	var b := STEP * 1.4142
	for j in SIDE:
		for i in SIDE:
			var k := j * SIDE + i
			var v := d[k]
			if i > 0: v = minf(v, d[k - 1] + a)
			if j > 0:
				v = minf(v, d[k - SIDE] + a)
				if i > 0: v = minf(v, d[k - SIDE - 1] + b)
				if i < CELLS: v = minf(v, d[k - SIDE + 1] + b)
			d[k] = v
	for j in range(CELLS, -1, -1):
		for i in range(CELLS, -1, -1):
			var k := j * SIDE + i
			var v := d[k]
			if i < CELLS: v = minf(v, d[k + 1] + a)
			if j < CELLS:
				v = minf(v, d[k + SIDE] + a)
				if i < CELLS: v = minf(v, d[k + SIDE + 1] + b)
				if i > 0: v = minf(v, d[k + SIDE - 1] + b)
			d[k] = v
	var bytes := PackedByteArray()
	bytes.resize(SIDE * SIDE)
	for k in SIDE * SIDE:
		bytes[k] = int(clampf(d[k] / cap, 0.0, 1.0) * 255.0)
	return Image.create_from_data(SIDE, SIDE, false, Image.FORMAT_L8, bytes)


## Ground height map for the city shader's contact shading.
func height_image() -> Image:
	var bytes := PackedByteArray()
	bytes.resize(SIDE * SIDE)
	for k in SIDE * SIDE:
		bytes[k] = int(clampf((heights[k] + MAP_BIAS) / MAP_SCALE, 0.0, 1.0) * 255.0)
	return Image.create_from_data(SIDE, SIDE, false, Image.FORMAT_L8, bytes)


## The little edits the player has made, as (index, delta) pairs, for saving.
func edits() -> Dictionary:
	var out := {}
	for k in heights.size():
		var dlt := heights[k] - _base[k]
		if absf(dlt) > 0.01:
			out[k] = snappedf(dlt, 0.01)
	return out


func zone_edits() -> Dictionary:
	var out := {}
	for k in zone.size():
		if zone[k] > 0.01:
			out[k] = snappedf(zone[k], 0.01)
	return out


func green_edits() -> Dictionary:
	var out := {}
	for k in green.size():
		if green[k] > 0.01:
			out[k] = snappedf(green[k], 0.01)
	return out


func apply_green(e: Dictionary) -> void:
	for k in e:
		var i := int(k)
		if i >= 0 and i < green.size():
			green[i] = clampf(float(e[k]), 0.0, 1.0)
	for c in _chunks.keys():
		_dirty[c] = true


func apply_zone(e: Dictionary) -> void:
	for k in e:
		var i := int(k)
		if i >= 0 and i < zone.size():
			zone[i] = clampf(float(e[k]), 0.0, 1.0)
	for c in _chunks.keys():
		_dirty[c] = true


## Heights, growing area and green all at once, as snapshot() took them.
func snapshot() -> Array:
	return [heights.duplicate(), zone.duplicate(), green.duplicate()]


func restore(snap: Array) -> void:
	heights = snap[0].duplicate()
	zone = snap[1].duplicate()
	green = snap[2].duplicate()
	_mark(0, 0, CELLS, CELLS)
	for c in _chunks.keys():
		_dirty[c] = true
	changed.emit()


## The natural ground height at sample k, before anyone reshaped it.
func base_height(k: int) -> float:
	return _base[k]


## Sets single samples (from another builder), redrawing only where they are.
## `layer` is heights (as offsets from the natural ground), zone or green.
func set_samples(layer: String, values: Dictionary) -> void:
	for k in values:
		var i: int = k
		if i < 0 or i >= heights.size():
			continue
		var v: float = values[k]
		match layer:
			"land":
				heights[i] = _base[i] + v
			"zone":
				zone[i] = clampf(v, 0.0, 1.0)
			"green":
				green[i] = clampf(v, 0.0, 1.0)
		var x := i % SIDE
		var z := i / SIDE
		_mark(x, z, x, z)


func apply_edits(e: Dictionary) -> void:
	for k in e:
		var i := int(k)
		if i >= 0 and i < heights.size():
			heights[i] = _base[i] + float(e[k])
	for c in _chunks.keys():
		_dirty[c] = true
	rebuild_dirty(1 << 20)
	rebuild_shadow()
	changed.emit()
