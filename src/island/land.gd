class_name Land
extends Node3D
## The map's ground: one continuous height field (no tiles), grown from
## noise into hills, ridges, coves, beaches and the odd cliff, and reshaped by
## the player's brushes. Built in chunks so a brush stroke only remakes the
## ground it touched. Each chunk is drawn as blocks that are as coarse as the
## ground allows (flat land and deep sea take a handful of triangles, hills
## keep every sample), stitched so neighbouring blocks always meet exactly.

const SIZE := 384.0
const HALF := SIZE * 0.5
const CELLS := 384
const STEP := SIZE / CELLS
const SIDE := CELLS + 1
const CHUNK := 32
# blocks inside a chunk, each drawn every 1, 2, 4 or 8 samples
const BLOCK := 8
const BLOCKS := CELLS / BLOCK
# how far a coarser block may stray from the ground it stands for: closely
# where anyone has built, shaped or painted, more loosely over wild country
const TOL := 0.05
const TOL_WILD := 0.08
const TOL_DEEP := 0.5
const TOL_COL := 0.07
# the size of the first islands (version 1 saves), which sit in the middle of the map
const LEGACY_SIZE := 128.0
# the kinds of map a new game can start on
const KINDS := ["island"]
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
# how far the town may grow up in each place, as painted with the Grow brush:
# 1 village .. 4 centre (0 where never painted, which counts as a town, 2)
var level := PackedFloat32Array()
const LEVEL_DEFAULT := 2.0
const LEVEL_TINTS := [Color("ffd23f"), Color("ffd23f"), Color("ff9a1f"), Color("ff5a3c"), Color("e0328c")]
# tint the painted area strongly (while the Grow brush is in hand)
var show_zone := false:
	set(v):
		if v != show_zone:
			show_zone = v
			for c in _chunks.keys():
				_dirty[c] = true
var _chunks := {}
## counts up whenever the ground or its painting changes
var revision := 0
# a coarser copy of the ground drawn only into the shadow map, so hills cast
# shadows across the valleys for a quarter of the triangles
var _shadow := {}
var _dirty := {}
## how far from the middle the land reaches (ships pass beyond it)
var reach := 0.0
## what kind of map this is ("legacy": the first, small islands)
var kind := "island"
# each sample's colour, and how coarsely each block is drawn
var _col := PackedColorArray()
var _steps := PackedByteArray()
var _ready_chunks := {}
var _pending_build := false
var _noise := FastNoiseLite.new()
var _warp := FastNoiseLite.new()
var _detail := FastNoiseLite.new()


## Fresh ground for a seed and a kind of map.
## With `build` off the ground is only worked out, not drawn, until finish()
## (so a save's edits go in first and every chunk is drawn once).
func generate(seed_value: int, map_kind := "island", build := true) -> void:
	kind = map_kind
	_noise.seed = seed_value
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise.fractal_octaves = 3
	_noise.fractal_gain = 0.3
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
	if kind == "legacy":
		for j in SIDE:
			for i in SIDE:
				heights[j * SIDE + i] = _natural(_pos(i, j))
	else:
		# worked out every other sample and filled in between: the land is
		# smoothed after anyway, and it takes a quarter of the time
		var half := CELLS / 2 + 1
		var coarse := PackedFloat32Array()
		coarse.resize(half * half)
		for j in half:
			for i in half:
				coarse[j * half + i] = _natural(_pos(i * 2, j * 2))
		for j in SIDE:
			var cj := mini(j / 2, half - 2)
			var v := (j - cj * 2) * 0.5
			for i in SIDE:
				var ci := mini(i / 2, half - 2)
				var u := (i - ci * 2) * 0.5
				var a := cj * half + ci
				heights[j * SIDE + i] = lerpf(lerpf(coarse[a], coarse[a + 1], u), lerpf(coarse[a + half], coarse[a + half + 1], u), v)
	if kind != "legacy":
		# rounded, rolling land: the big maps are seen from far out, where
		# crisp little creases only cost triangles
		for pass_i in 8:
			_blur(heights)
	_base = heights.duplicate()
	reach = 0.0
	for j in range(0, SIDE, 4):
		for i in range(0, SIDE, 4):
			if heights[j * SIDE + i] > -1.0:
				reach = maxf(reach, _pos(i, j).length())
	_col.resize(SIDE * SIDE)
	_steps.resize(BLOCKS * BLOCKS)
	_steps.fill(0)
	zone.resize(SIDE * SIDE)
	zone.fill(0.0)
	green.resize(SIDE * SIDE)
	green.fill(0.0)
	level.resize(SIDE * SIDE)
	level.fill(0.0)
	_mark(0, 0, CELLS, CELLS)
	for c in _chunks.values():
		c.queue_free()
	_chunks.clear()
	_pending_build = true
	if build:
		finish()


## Draws freshly generated ground (see generate()).
func finish() -> void:
	if not _pending_build:
		return
	_pending_build = false
	# how coarse every block can be first, so each chunk meets its neighbours
	for cz in CELLS / CHUNK:
		for cx in CELLS / CHUNK:
			_prepare(Vector2i(cx, cz))
	_dirty.clear()
	for cz in CELLS / CHUNK:
		for cx in CELLS / CHUNK:
			_dirty[Vector2i(cx, cz)] = true
			_ready_chunks[Vector2i(cx, cz)] = true
	rebuild_dirty(1 << 20)
	rebuild_shadow()
	changed.emit()


func _pos(i: int, j: int) -> Vector2:
	return Vector2(i * STEP - HALF, j * STEP - HALF)


## The untouched landscape at a point.
func _natural(p: Vector2) -> float:
	if kind == "legacy":
		return _legacy(p)
	return _island(p)


## A big island: a warped, roughly round coast with bays and headlands, broad
## lowlands for a city, inland hills and ridges, beaches and a few cliffs.
func _island(p: Vector2) -> float:
	var s := HALF / (LEGACY_SIZE * 0.5)
	var w := Vector2(_warp.get_noise_2d(p.x / s, p.y / s), _warp.get_noise_2d(p.x / s + 91.0, p.y / s - 37.0)) * 20.0 * s
	w += Vector2(_detail.get_noise_2d(p.x * 0.5, p.y * 0.5), _detail.get_noise_2d(p.x * 0.5 + 50.0, p.y * 0.5)) * 2.0
	var q := p + w
	var r := q.length() / HALF
	var cliff := smoothstep(0.3, 0.55, _warp.get_noise_2d(q.x * 0.6 - 200.0, q.y * 0.6))
	var mask := 1.0 - smoothstep(lerpf(0.5, 0.66, cliff), lerpf(0.9, 0.78, cliff), r)
	var hills := (_noise.get_noise_2d(q.x * 0.8, q.y * 0.8) * 0.5 + 0.5)
	hills = pow(hills, 2.7) * 8.5
	var ridge := 1.0 - absf(_noise.get_noise_2d(q.x * 0.5 + 400.0, q.y * 0.5))
	hills += pow(ridge, 6.0) * 1.5 * smoothstep(0.0, 0.4, _warp.get_noise_2d(q.x * 0.3 + 300.0, q.y * 0.3))
	var inland := smoothstep(0.1, 0.7, mask)
	inland *= inland
	var land := 0.8 + hills * inland + cliff * 1.2 * smoothstep(0.0, 0.3, mask)
	var h := lerpf(LOW, land, mask)
	return _beach(h)


## The first, small islands (kept so version 1 saves come back as they were),
## in the middle of the map with open sea all round.
func _legacy(p: Vector2) -> float:
	# (the warp moves the coast by 22 m at most)
	if p.length() > LEGACY_SIZE * 0.6 + 24.0:
		return _beach(LOW)
	var w := Vector2(_warp.get_noise_2d(p.x, p.y), _warp.get_noise_2d(p.x + 91.0, p.y - 37.0)) * 20.0
	w += Vector2(_detail.get_noise_2d(p.x * 0.5, p.y * 0.5), _detail.get_noise_2d(p.x * 0.5 + 50.0, p.y * 0.5)) * 2.0
	var q := p + w
	var r := q.length() / (LEGACY_SIZE * 0.5)
	if r > 1.2:
		return _beach(LOW)
	# where the coast is cliffy the land rises sharply out of the sea
	var cliff := smoothstep(0.3, 0.55, _warp.get_noise_2d(q.x * 0.6 - 200.0, q.y * 0.6))
	var mask := 1.0 - smoothstep(lerpf(0.42, 0.62, cliff), lerpf(0.86, 0.72, cliff), r)
	var hills := (_noise.get_noise_2d(q.x, q.y) * 0.5 + 0.5)
	# mostly broad, gentle land that a town can spread over, with a few real hills
	hills = pow(hills, 2.7) * 8.5
	# a ridge line here and there
	var ridge := 1.0 - absf(_noise.get_noise_2d(q.x * 0.7 + 400.0, q.y * 0.7))
	hills += pow(ridge, 6.0) * 1.5 * smoothstep(0.0, 0.4, _warp.get_noise_2d(q.x * 0.5 + 300.0, q.y * 0.5))
	var inland := smoothstep(0.2, 0.9, mask)
	inland *= inland
	var land := 0.8 + hills * inland + _detail.get_noise_2d(p.x, p.y) * 0.06 + cliff * 1.2 * smoothstep(0.0, 0.3, mask)
	var h := lerpf(LOW, land, mask)
	return _beach(h)


## One pass of a 3x3 blur over a whole layer (its rim left as it is).
static func _blur(a: PackedFloat32Array) -> void:
	var src := a.duplicate()
	for j in range(1, CELLS):
		var r := j * SIDE
		for i in range(1, CELLS):
			var k := r + i
			a[k] = (src[k] * 4.0 + src[k - 1] + src[k + 1] + src[k - SIDE] + src[k + SIDE]) * 0.125
	return


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


## Paint the growing level `lv` (1..4): unpainted ground takes it at once,
## painted ground moves towards it, so strokes blend at their edges.
func paint_level(centre: Vector3, radius: float, lv: float, amount: float) -> void:
	_each_in(centre, radius, func(k: int, w: float) -> void:
		if w < 0.02:
			return
		if level[k] < 0.5:
			level[k] = lv
		else:
			level[k] = move_toward(level[k], lv, amount * minf(w * 3.0, 1.0)))


## The level the town may grow to here, 1..4 (from the nearest sample).
func level_at(x: float, z: float) -> float:
	var fx := (x + HALF) / STEP
	var fz := (z + HALF) / STEP
	var i := clampi(int(round(fx)), 0, CELLS)
	var j := clampi(int(round(fz)), 0, CELLS)
	var lv := level[j * SIDE + i]
	return lv if lv >= 0.5 else LEVEL_DEFAULT


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
func flatten(centre: Vector3, radius: float, to: float, amount: float) -> void:
	_each_in(centre, radius, func(k: int, w: float) -> void:
		heights[k] = lerpf(heights[k], to, clampf(amount * w, 0.0, 1.0)))


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


## A revision count per TILE x TILE metres, bumped whenever anything there
## changes, so the woods and yards know which of their pieces to redo.
const TILE := 16
const TILES := CELLS / TILE
var tile_rev := PackedInt32Array()


func tile_sig(t: Vector2i) -> int:
	if tile_rev.is_empty():
		return 0
	return tile_rev[clampi(t.y, 0, TILES - 1) * TILES + clampi(t.x, 0, TILES - 1)]


func _mark(i0: int, j0: int, i1: int, j1: int) -> void:
	if tile_rev.size() != TILES * TILES:
		tile_rev.resize(TILES * TILES)
	for tz in range(maxi(0, (j0 - 2) / TILE), mini(TILES - 1, (j1 + 2) / TILE) + 1):
		for tx in range(maxi(0, (i0 - 2) / TILE), mini(TILES - 1, (i1 + 2) / TILE) + 1):
			tile_rev[tz * TILES + tx] += 1
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


## Level a building plot: flat at height `y` inside the outline, easing back to
## the natural ground over `blend` around it (a terrace cut into a hillside).
func pad(outline: PackedVector2Array, y: float, blend: float, keep_off := Callable()) -> void:
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
			heights[g] = lerpf(heights[g], y, 1.0 - smoothstep(0.0, 1.0, d / blend))
	_mark(i0, j0, i1, j1)


## Remake changed chunks, spending at most `budget_us` microseconds.
func rebuild_dirty(budget_us := 4000) -> void:
	if not _dirty.is_empty():
		revision += 1
		_shadow_dirty = true
	var start := Time.get_ticks_usec()
	for c in _dirty.keys():
		# (unless generate() has just worked it out)
		if not _ready_chunks.erase(c):
			_prepare(c)
		_build_chunk(c)
		_dirty.erase(c)
		if Time.get_ticks_usec() - start > budget_us:
			break


func is_settled() -> bool:
	return _dirty.is_empty()


var _shadow_dirty := true
# the shadow stand-in is cut into tiles this many samples across
const SHADOW_TILE := 96


## Remake the shadow stand-in (call once a stroke has finished): the ground
## every 4 samples, sunk a little, only where it is hilly enough to shade
## anything, in tiles so only what is in view is drawn.
func rebuild_shadow() -> void:
	if not _shadow_dirty and not _shadow.is_empty():
		return
	_shadow_dirty = false
	const S := 4
	var n := CELLS / S + 1
	var hs := PackedFloat32Array()
	hs.resize(n * n)
	for j in n:
		for i in n:
			# never above the real ground around it, so cuttings and streets stay lit
			var gi := i * S
			var gj := j * S
			var h := heights[gj * SIDE + gi]
			for dj in range(-2, 3):
				for di in range(-2, 3):
					h = minf(h, heights[index(gi + di, gj + dj)])
			hs[j * n + i] = maxf(h, -0.6) - 0.12
	var per := SHADOW_TILE / S
	for tj in CELLS / SHADOW_TILE:
		for ti in CELLS / SHADOW_TILE:
			var verts := PackedVector3Array()
			var idx := PackedInt32Array()
			var at := {}
			for j in range(tj * per, tj * per + per):
				for i in range(ti * per, ti * per + per):
					var ks := [j * n + i, j * n + i + 1, (j + 1) * n + i, (j + 1) * n + i + 1]
					var lo := INF
					var hi := -INF
					for k in ks:
						lo = minf(lo, hs[k])
						hi = maxf(hi, hs[k])
					# flat ground and the sea floor shade nothing
					if hi < -0.65 or hi - lo < 0.12:
						continue
					var vi := PackedInt32Array()
					for k in ks:
						if not at.has(k):
							at[k] = verts.size()
							var p := _pos((k % n) * S, (k / n) * S)
							verts.append(Vector3(p.x, hs[k], p.y))
						vi.append(at[k])
					idx.append_array([vi[0], vi[1], vi[2], vi[1], vi[3], vi[2]])
			var key := Vector2i(ti, tj)
			var mi: MeshInstance3D = _shadow.get(key)
			if idx.is_empty():
				if mi:
					mi.mesh = null
				continue
			var arr := []
			arr.resize(Mesh.ARRAY_MAX)
			arr[Mesh.ARRAY_VERTEX] = verts
			arr[Mesh.ARRAY_INDEX] = idx
			var m := ArrayMesh.new()
			m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			m.surface_set_material(0, Palette.shadow_material())
			if mi == null:
				mi = MeshInstance3D.new()
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
				add_child(mi)
				_shadow[key] = mi
			mi.mesh = m


# ------------------------------------------------------------------ mesh

## Colours every sample of a chunk and works out how coarsely each of its
## blocks can be drawn. A border block that changes how coarse it is makes
## the chunk next to it redraw too, so their seam stays closed.
func _prepare(c: Vector2i) -> void:
	for j in CHUNK + 1:
		for i in CHUNK + 1:
			var gi := c.x * CHUNK + i
			var gj := c.y * CHUNK + j
			_col[gj * SIDE + gi] = _sample_colour(gi, gj)
	var per := CHUNK / BLOCK
	for bj in per:
		for bi in per:
			var gb := Vector2i(c.x * per + bi, c.y * per + bj)
			var s := _block_step(gb.x * BLOCK, gb.y * BLOCK)
			var k := gb.y * BLOCKS + gb.x
			if s == _steps[k]:
				continue
			_steps[k] = s
			for d: Vector2i in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
				if (bi == 0 and d.x < 0) or (bi == per - 1 and d.x > 0) or (bj == 0 and d.y < 0) or (bj == per - 1 and d.y > 0):
					var nc := c + d
					if nc.x >= 0 and nc.y >= 0 and nc.x < CELLS / CHUNK and nc.y < CELLS / CHUNK:
						_dirty[nc] = true


## The coarsest step (8, 4, 2 or 1 samples) a block can be drawn at while
## staying within TOL of the ground and TOL_COL of its colours.
func _block_step(i0: int, j0: int) -> int:
	var deep := true
	var wild := true
	for j in range(j0, j0 + BLOCK + 1):
		for i in range(i0, i0 + BLOCK + 1):
			var k := j * SIDE + i
			if heights[k] > DEEP:
				deep = false
			if zone[k] > 0.0 or green[k] > 0.0 or absf(heights[k] - _base[k]) > 0.005:
				wild = false
	var tol := TOL_DEEP if deep else (TOL_WILD if wild else TOL)
	for s: int in [8, 4, 2]:
		var ok := true
		for j in range(j0, j0 + BLOCK + 1):
			var cj := j0 + ((j - j0) / s) * s
			var cj1 := mini(cj + s, j0 + BLOCK)
			var v := float(j - cj) / s if cj1 > cj else 0.0
			for i in range(i0, i0 + BLOCK + 1):
				if (i - i0) % s == 0 and (j - j0) % s == 0:
					continue
				var ci := i0 + ((i - i0) / s) * s
				var ci1 := mini(ci + s, i0 + BLOCK)
				var u := float(i - ci) / s if ci1 > ci else 0.0
				var a := cj * SIDE
				var b := cj1 * SIDE
				var h := lerpf(lerpf(heights[a + ci], heights[a + ci1], u), lerpf(heights[b + ci], heights[b + ci1], u), v)
				if absf(h - heights[j * SIDE + i]) > tol:
					ok = false
					break
				if not deep:
					var col := _col[a + ci].lerp(_col[a + ci1], u).lerp(_col[b + ci].lerp(_col[b + ci1], u), v)
					var o := _col[j * SIDE + i]
					if absf(col.r - o.r) > TOL_COL or absf(col.g - o.g) > TOL_COL or absf(col.b - o.b) > TOL_COL:
						ok = false
						break
			if not ok:
				break
		if ok:
			return s
	return 1


## How far apart the samples along a block's edge are: the finer of the block
## and its neighbour that way (the map's rim keeps the block's own).
func _edge(bx: int, bz: int, d: Vector2i, own: int) -> int:
	var nx := bx + d.x
	var nz := bz + d.y
	if nx < 0 or nz < 0 or nx >= BLOCKS or nz >= BLOCKS:
		return own
	var o := _steps[nz * BLOCKS + nx]
	return mini(own, o) if o > 0 else 1


func _sample_colour(gi: int, gj: int) -> Color:
	var h := heights[gj * SIDE + gi]
	var p := _pos(gi, gj)
	var hx := heights[index(gi + 1, gj)] - heights[index(gi - 1, gj)]
	var hz := heights[index(gi, gj + 1)] - heights[index(gi, gj - 1)]
	var up := 2.0 * STEP / Vector3(-hx, 2.0 * STEP, -hz).length()
	# hollows a touch darker, crests a touch lighter: the land's shape reads from any angle
	var lap := (heights[index(gi - 2, gj)] + heights[index(gi + 2, gj)] + heights[index(gi, gj - 2)] + heights[index(gi, gj + 2)] - 4.0 * h) / (4.0 * STEP * STEP)
	var col := _colour(p, h, up)
	var zn := zone[gj * SIDE + gi]
	if zn > 0.0 and h > 0.0:
		if show_zone:
			# while growing, the painted ground shows its level: warmer is taller
			var lv := level[gj * SIDE + gi]
			var t: Color = LEVEL_TINTS[clampi(int(round(lv if lv >= 0.5 else LEVEL_DEFAULT)), 1, LEVEL_TINTS.size() - 1)]
			col = col.lerp(t, minf(zn * 1.4, 1.0) * 0.82)
		else:
			col = col.lerp(Color("b5c97a"), zn * 0.18)
	var gn := green[gj * SIDE + gi]
	if gn > 0.0 and h > 0.0:
		# park lawns, a lusher green
		col = col.lerp(Color("2fd35a") if show_zone else Color("74bf5e"), minf(gn * 1.4, 1.0) * 0.82 if show_zone else gn * 0.3)
	if h > -0.3:
		col = col.darkened(clampf(lap * 0.9, 0.0, 0.14)) if lap > 0.0 else col.lightened(clampf(-lap * 0.5, 0.0, 0.08))
	return col


func _build_chunk(c: Vector2i) -> void:
	var n := CHUNK + 1
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var at := PackedInt32Array()
	at.resize(n * n)
	at.fill(-1)
	var per := CHUNK / BLOCK
	var ring := PackedInt32Array()
	for bj in per:
		for bi in per:
			var bx := c.x * per + bi
			var bz := c.y * per + bj
			var s := maxi(_steps[bz * BLOCKS + bx], 1)
			# samples along each edge: north (-z), south, west (-x), east
			var en := _edge(bx, bz, Vector2i(0, -1), s)
			var es := _edge(bx, bz, Vector2i(0, 1), s)
			var ew := _edge(bx, bz, Vector2i(-1, 0), s)
			var ee := _edge(bx, bz, Vector2i(1, 0), s)
			var li0 := bi * BLOCK
			var lj0 := bj * BLOCK
			for cj in range(lj0, lj0 + BLOCK, s):
				for ci in range(li0, li0 + BLOCK, s):
					var top := cj == lj0 and en < s
					var bottom := cj + s == lj0 + BLOCK and es < s
					var left := ci == li0 and ew < s
					var right := ci + s == li0 + BLOCK and ee < s
					if not (top or bottom or left or right):
						var a := _vert(c, ci, cj, at, verts, norms, cols)
						var b := _vert(c, ci + s, cj, at, verts, norms, cols)
						var cc := _vert(c, ci, cj + s, at, verts, norms, cols)
						var d := _vert(c, ci + s, cj + s, at, verts, norms, cols)
						# split along the diagonal that follows the land best
						if absf(verts[a].y - verts[d].y) < absf(verts[b].y - verts[cc].y):
							idx.append_array([a, b, d, a, d, cc])
						else:
							idx.append_array([a, b, cc, b, d, cc])
						continue
					# a finer neighbour: fan from the middle out to every sample on the edge
					ring.clear()
					var e := en if top else s
					for i in range(ci, ci + s, e):
						ring.append(_vert(c, i, cj, at, verts, norms, cols))
					e = ee if right else s
					for j in range(cj, cj + s, e):
						ring.append(_vert(c, ci + s, j, at, verts, norms, cols))
					e = es if bottom else s
					for i in range(ci + s, ci, -e):
						ring.append(_vert(c, i, cj + s, at, verts, norms, cols))
					e = ew if left else s
					for j in range(cj + s, cj, -e):
						ring.append(_vert(c, ci, j, at, verts, norms, cols))
					var mid := _vert(c, ci + s / 2, cj + s / 2, at, verts, norms, cols)
					for k in ring.size():
						idx.append_array([mid, ring[k], ring[(k + 1) % ring.size()]])
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


## The vertex for chunk-local sample (i, j), made the first time it is needed.
func _vert(c: Vector2i, i: int, j: int, at: PackedInt32Array, verts: PackedVector3Array, norms: PackedVector3Array, cols: PackedColorArray) -> int:
	var k := j * (CHUNK + 1) + i
	if at[k] >= 0:
		return at[k]
	var gi := c.x * CHUNK + i
	var gj := c.y * CHUNK + j
	var p := _pos(gi, gj)
	var hx := heights[index(gi + 1, gj)] - heights[index(gi - 1, gj)]
	var hz := heights[index(gi, gj + 1)] - heights[index(gi, gj - 1)]
	at[k] = verts.size()
	verts.append(Vector3(p.x, heights[gj * SIDE + gi], p.y))
	norms.append(Vector3(-hx, 2.0 * STEP, -hz).normalized())
	cols.append(_col[gj * SIDE + gi])
	return at[k]


## Ground colour from height, steepness and a little noise: wet and dry sand,
## meadow grass that is lusher low down and drier up high, rock on steep slopes.
func _colour(p: Vector2, h: float, up: float) -> Color:
	var n := _detail.get_noise_2d(p.x * 0.45, p.y * 0.45)
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


func level_edits() -> Dictionary:
	var out := {}
	for k in level.size():
		if level[k] >= 0.5:
			out[k] = snappedf(level[k], 0.01)
	return out


func apply_level(e: Dictionary) -> void:
	for k in e:
		var i := int(k)
		if i >= 0 and i < level.size():
			level[i] = clampf(float(e[k]), 0.0, 4.0)
	_mark_keys(e)


func apply_green(e: Dictionary) -> void:
	for k in e:
		var i := int(k)
		if i >= 0 and i < green.size():
			green[i] = clampf(float(e[k]), 0.0, 1.0)
	_mark_keys(e)


func apply_zone(e: Dictionary) -> void:
	for k in e:
		var i := int(k)
		if i >= 0 and i < zone.size():
			zone[i] = clampf(float(e[k]), 0.0, 1.0)
	_mark_keys(e)


## Heights, growing area and green all at once, as snapshot() took them.
func snapshot() -> Array:
	return [heights.duplicate(), zone.duplicate(), green.duplicate(), level.duplicate()]


func restore(snap: Array) -> void:
	heights = snap[0].duplicate()
	zone = snap[1].duplicate()
	green = snap[2].duplicate()
	if snap.size() > 3:
		level = snap[3].duplicate()
	_mark(0, 0, CELLS, CELLS)
	for c in _chunks.keys():
		_dirty[c] = true
	changed.emit()


## Where sample k of a version 1 (128 m) island lies on this map.
static func legacy_index(k: int) -> int:
	var old := int(LEGACY_SIZE) + 1
	var off := (CELLS - int(LEGACY_SIZE)) / 2
	return (k / old + off) * SIDE + k % old + off


## A version 1 save's samples, moved to where they lie on this map.
static func legacy_cells(e: Dictionary) -> Dictionary:
	var out := {}
	for k in e:
		out[str(legacy_index(int(k)))] = e[k]
	return out


## The natural ground height at sample k, before anyone reshaped it.
func base_height(k: int) -> float:
	return _base[k]


## Sets single samples (from another builder), redrawing only where they are.
## `layer` is heights (as offsets from the natural ground), zone, green or level.
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
			"level":
				level[i] = clampf(v, 0.0, 4.0)
		var x := i % SIDE
		var z := i / SIDE
		_mark(x, z, x, z)


## Marks the box round a set of sample keys as changed.
func _mark_keys(e: Dictionary) -> void:
	if e.is_empty():
		return
	var lo := Vector2i(SIDE, SIDE)
	var hi := Vector2i(-1, -1)
	for k in e:
		var i := int(k)
		if i < 0 or i >= SIDE * SIDE:
			continue
		var c := Vector2i(i % SIDE, i / SIDE)
		lo = lo.min(c)
		hi = hi.max(c)
	if hi.x >= 0:
		_mark(lo.x, lo.y, hi.x, hi.y)


func apply_edits(e: Dictionary) -> void:
	for k in e:
		var i := int(k)
		if i >= 0 and i < heights.size():
			heights[i] = _base[i] + float(e[k])
	_mark_keys(e)
	if not _pending_build:
		rebuild_dirty(1 << 20)
		rebuild_shadow()
	changed.emit()
