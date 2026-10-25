class_name Land
extends Node3D
## The map's ground: one continuous height field (no tiles), grown from
## noise into hills, ridges, coves, beaches and the odd cliff, and reshaped by
## the player's brushes. Built in chunks so a brush stroke only remakes the
## ground it touched. Each chunk is drawn as blocks that are as coarse as the
## ground allows (flat land and deep sea take a handful of triangles, hills
## keep every sample), stitched so neighbouring blocks always meet exactly.

# how big the map is: most maps are 384 m across, the coast 672 m (see use_size);
# always a whole number of chunks, shadow tiles and horizon tiles
const NORMAL_SIZE := 384
const COAST_SIZE := 672
static var SIZE := 384.0
static var HALF := SIZE * 0.5
static var CELLS := 384
const STEP := 1.0
static var SIDE := CELLS + 1
const CHUNK := 32
# blocks inside a chunk, each drawn every 1, 2, 4 or 8 samples
const BLOCK := 8
static var BLOCKS := CELLS / BLOCK
# how far a coarser block may stray from the ground it stands for: closely
# where anyone has built, shaped or painted, more loosely over wild country
const TOL := 0.05
const TOL_WILD := 0.08
const TOL_DEEP := 0.5
const TOL_COL := 0.07
# the big coast's untouched country is seen in far greater sweeps, so it is
# drawn a little more loosely (the same everywhere on it, near or far)
const TOL_WILD_BIG := 0.14
const TOL_COL_WILD_BIG := 0.11
# the size of the first islands (version 1 saves), which sit in the middle of the map
const LEGACY_SIZE := 128.0
# the kinds of map a new game can start on
const KINDS := ["river", "coast", "lakes", "island"]
const KIND_NAMES := {"river": "River valley", "coast": "Coast", "lakes": "Lake country", "island": "Island", "legacy": "Island"}
# maps whose land runs on past the edge, drawn out to the horizon
const OPEN_KINDS := ["river", "coast", "lakes"]
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
## what each district grows, painted with the Grow brush along with its level:
## the level layer holds district * USE_STRIDE + level (so saves and co-op
## carry both in one number)
const USES := ["homes", "shops", "offices", "industry", "entertainment"]
const USE_STRIDE := 10.0
const LEVEL_MAX := 7.0
## the light stone of downtown plazas and the ground between its buildings
const PAVED := Color(0.77, 0.74, 0.69)
## the painted ground's tint while growing, by district (homes green, shops
## blue, offices teal, industry amber, entertainment pink, as city builders
## colour their zones)
const USE_TINTS := [Color("59d24a"), Color("3f8cff"), Color("22c7c7"), Color("ffb51f"), Color("e35fd2")]
# tint the painted area strongly (while the Grow brush is in hand): the ground
# shader lays the tint map over the land, so it shows the instant it is painted
# and switching it on or off redraws nothing
var show_zone := false:
	set(v):
		show_zone = v
		if material:
			material.set_shader_parameter("show_zone", v)
## the painted town's tint as the Grow brush shows it, one pixel per ground
## sample: RGB the colour, A how strongly it covers the ground
var tint_img: Image
var _tint_bytes := PackedByteArray()
var _tint_lo := Vector2i(0, 0)
var _tint_hi := Vector2i(CELLS, CELLS)
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
# chunks changed again while being redrawn: redrawn once more when done
var _again := {}
# chunks part way through being worked out: the next row of colours to do,
# and the mesh being put together
var _prep_row := {}
var _jobs := {}
var _pending_build := false
var _noise := FastNoiseLite.new()
var _warp := FastNoiseLite.new()
var _detail := FastNoiseLite.new()


## How big a map of this kind is, in metres: a save that says nothing is from
## before the coast grew, and keeps its old size.
static func size_for(map_kind: String, saved := 0) -> int:
	if saved > 0:
		return saved
	return COAST_SIZE if map_kind == "coast" else NORMAL_SIZE


## Sets the map's size for everything that works in map samples. Call it
## before a map of another size is cleared and generated.
static func use_size(metres: int) -> void:
	SIZE = float(metres)
	HALF = SIZE * 0.5
	CELLS = metres
	SIDE = CELLS + 1
	BLOCKS = CELLS / BLOCK
	FARM_SIDE = int(SIZE / FARM_CELL) + 1
	TILES = CELLS / TILE
	# the country runs on to the horizon: on the big coast only a rim of it,
	# since nearly all the land is the map itself
	FAR = 320.0 if metres == NORMAL_SIZE else 112.0


## Moves painted or reshaped samples saved on a map `from` samples across to
## where the same ground lies on one `to` across (both centred on the middle).
static func recentre_cells(e: Dictionary, from: int, to: int) -> Dictionary:
	var out := {}
	var off := (to - from) / 2
	for k in e:
		var i := int(k) % (from + 1) + off
		var j := int(k) / (from + 1) + off
		if i >= 0 and j >= 0 and i <= to and j <= to:
			out[str(j * (to + 1) + i)] = e[k]
	return out


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
	farm_rev += 1
	_farm_noise.seed = seed_value + 53
	_farm_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_farm_noise.fractal_octaves = 2
	_farm_noise.frequency = 1.0 / 90.0
	farm_angle = fposmod(seed_value * 0.618, 1.0) * 0.9 - 0.45
	# a new map works its farmland out afresh
	_farm_raw.clear()
	_farm_land.clear()
	_plan_water(seed_value)
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
		for pass_i in (8 if kind == "island" else (6 if SIZE > NORMAL_SIZE else 4)):
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
	for mi in _shadow.values():
		mi.queue_free()
	_shadow.clear()
	_shadow_tiles.clear()
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
	_jobs.clear()
	_prep_row.clear()
	_shadow_all = true
	for cz in CELLS / CHUNK:
		for cx in CELLS / CHUNK:
			_dirty[Vector2i(cx, cz)] = true
			_ready_chunks[Vector2i(cx, cz)] = true
	rebuild_dirty(1 << 20)
	rebuild_shadow()
	_build_horizon()
	changed.emit()


func _pos(i: int, j: int) -> Vector2:
	return Vector2(i * STEP - HALF, j * STEP - HALF)


## The untouched landscape at a point (anywhere, on the map or beyond it).
func _natural(p: Vector2) -> float:
	match kind:
		"legacy":
			return _legacy(p)
		"island":
			return _island(p)
	return _country(p)


## The untouched land at p, on the map or anywhere past its edge.
func natural_at(p: Vector2) -> float:
	return _natural(p)


# ------------------------------------------------------------------ open country

# the river: its centre line (well past the map at both ends), how wide it is
# along the way, and its stretches filed by area for quick lookups
var _river := PackedVector2Array()
var _river_w := PackedFloat32Array()
var _river_cells := {}
const RIVER_CELL := 64.0
# where the sea is, for a coast: land rises away from the shore along _coast_dir
var _coast_dir := Vector2.ZERO
var _coast_at := 0.0


## Lays out the big water of an open map: where its river runs and which way
## the sea lies.
func _plan_water(seed_value: int) -> void:
	_river = PackedVector2Array()
	_river_w = PackedFloat32Array()
	_river_cells = {}
	_coast_dir = Vector2.ZERO
	if not kind in OPEN_KINDS:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 7 + 3
	# the river runs roughly across the map, at a slant
	var along := Vector2.from_angle(rng.randf() * TAU)
	var side := along.orthogonal()
	if kind == "coast":
		# the sea lies on one side, the river comes down to it from inland
		_coast_dir = -along
		# (where it lay on the first, smaller coast maps, so their towns still fit)
		_coast_at = -NORMAL_SIZE * 0.5 * 0.42 + rng.randf_range(-12.0, 12.0)
	var off := rng.randf_range(-40.0, 40.0)
	var ph := [rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU]
	var wide := rng.randf_range(4.5, 6.0) if kind != "lakes" else rng.randf_range(3.2, 4.2)
	var t := -HALF - 420.0
	while t <= HALF + 420.0:
		# broad sweeps with tighter meanders on them
		var lat := off + sin(t / 170.0 + ph[0]) * 46.0 + sin(t / 61.0 + ph[1]) * 16.0 + sin(t / 23.0 + ph[2]) * 3.0
		_river.append(along * t + side * lat)
		var w := wide * (1.0 + 0.18 * sin(t / 90.0 + ph[2]))
		if kind == "coast":
			# an estuary: wider as it nears the sea
			w *= 1.0 + 1.6 * smoothstep(0.0, 1.0, (-t - (-_coast_at) + 90.0) / 140.0)
		_river_w.append(w)
		t += 6.0
	for k in _river.size() - 1:
		var a := _river[k]
		var b := _river[k + 1]
		var c0 := Vector2i(floor(minf(a.x, b.x) / RIVER_CELL), floor(minf(a.y, b.y) / RIVER_CELL))
		var c1 := Vector2i(floor(maxf(a.x, b.x) / RIVER_CELL), floor(maxf(a.y, b.y) / RIVER_CELL))
		for cy in range(c0.y, c1.y + 1):
			for cx in range(c0.x, c1.x + 1):
				var key := Vector2i(cx, cy)
				if not _river_cells.has(key):
					_river_cells[key] = PackedInt32Array()
				_river_cells[key].append(k)


## (distance to the river's centre line, its half width there), or a far
## distance where no river runs within about RIVER_CELL.
func _river_at(p: Vector2) -> Vector2:
	if _river.is_empty():
		return Vector2(1e6, 1.0)
	var c := Vector2i(floor(p.x / RIVER_CELL), floor(p.y / RIVER_CELL))
	var best := 1e6
	var bw := 1.0
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var segs: Variant = _river_cells.get(c + Vector2i(dx, dy))
			if segs == null:
				continue
			for k: int in segs:
				var a := _river[k]
				var ab := _river[k + 1] - a
				var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
				var d := p.distance_to(a + ab * t)
				if d < best:
					best = d
					bw = lerpf(_river_w[k], _river_w[k + 1], t)
	return Vector2(best, bw)


## Open country: broad, gentle land a city can spread over, low and level by
## the river (its flood plain), rising to wooded hills further out; a river
## winding through, lakes in the hollows, and for a coast, the sea along one
## side with beaches and the river's estuary.
func _country(p: Vector2) -> float:
	var broad := _noise.get_noise_2d(p.x * 0.22, p.y * 0.22)
	var h := 1.5 + broad * 2.0
	# hills, only in some parts of the map
	var hilly := smoothstep(0.05, 0.45, _warp.get_noise_2d(p.x * 0.18 + 300.0, p.y * 0.18))
	var bump := _noise.get_noise_2d(p.x * 0.7 + 100.0, p.y * 0.7) * 0.5 + 0.5
	h += pow(bump, 2.2) * 9.0 * hilly
	h = maxf(h, 0.75)
	# the river and its flood plain
	var rv := _river_at(p)
	var plain := 0.55 + _detail.get_noise_2d(p.x * 0.08, p.y * 0.08) * 0.12
	h = lerpf(plain, h, smoothstep(rv.y + 2.0, rv.y + 75.0, rv.x))
	if rv.x < rv.y + 3.0:
		var bank := clampf((rv.x - rv.y) / 3.0, 0.0, 1.0)
		var bed := -1.7 * (1.0 - pow(clampf(rv.x / rv.y, 0.0, 1.0), 2.0)) - 0.35
		h = minf(h, lerpf(bed, plain, smoothstep(0.0, 1.0, bank)) if rv.x > rv.y else bed)
	# lakes in the hollows
	if kind == "lakes" or kind == "river":
		var ln := _warp.get_noise_2d(p.x * 0.11 - 500.0, p.y * 0.11 + 200.0)
		var need := 0.38 if kind == "lakes" else 0.52
		if ln > need - 0.08:
			var lt := smoothstep(need - 0.08, need + 0.02, ln)
			h = lerpf(h, minf(h, plain), lt)
			if ln > need:
				h = minf(h, -smoothstep(need, need + 0.12, ln) * 2.4 - 0.2)
	# the sea
	if _coast_dir != Vector2.ZERO:
		var s := p.dot(_coast_dir) + _warp.get_noise_2d(p.x * 0.12, p.y * 0.12) * 38.0 + _detail.get_noise_2d(p.x * 0.05, p.y * 0.05) * 10.0
		var inland := s - _coast_at
		if inland < 26.0:
			# a broad sandy shore
			h = lerpf(0.35, h, smoothstep(4.0, 26.0, inland))
		if inland < 0.0:
			h = lerpf(0.3, LOW, smoothstep(0.0, 45.0, -inland))
	if SIZE > NORMAL_SIZE:
		# the big coast is nearly all map: just past its edge the land ends in
		# a ragged shore with rounded corners, the sea all round
		var inland := -_outline(p)
		if inland < 26.0:
			h = lerpf(minf(h, 0.35), h, smoothstep(4.0, 26.0, inland))
		if inland < 0.0:
			h = lerpf(minf(h, 0.3), LOW, smoothstep(0.0, 70.0, -inland))
	return h if h > 0.0 else _beach(h)


## How far p lies outside the big coast's land (negative inside): a rounded
## square about the size of the map, its sides warped into bays and points.
func _outline(p: Vector2) -> float:
	const ROUND := 150.0
	# broad bays and headlands, with smaller coves on them
	var w := Vector2(_warp.get_noise_2d(p.x * 0.3 + 400.0, p.y * 0.3), _warp.get_noise_2d(p.x * 0.3, p.y * 0.3 - 400.0)) * 50.0
	w += Vector2(_warp.get_noise_2d(p.x * 0.8 - 250.0, p.y * 0.8), _warp.get_noise_2d(p.x * 0.8, p.y * 0.8 + 250.0)) * 7.0
	var q := (p + w).abs() - Vector2.ONE * (HALF - 8.0 - ROUND)
	return q.max(Vector2.ZERO).length() + minf(maxf(q.x, q.y), 0.0) - ROUND


## Whether ships can sail past: the sea all round an island, or along a coast.
func has_sea() -> bool:
	return not kind in OPEN_KINDS or _coast_dir != Vector2.ZERO


## For a coast: the way inland (x, y) and how far inland the shore lies (z).
func coast() -> Vector3:
	return Vector3(_coast_dir.x, _coast_dir.y, _coast_at)


## A good first view of a fresh map: level, dry ground near the middle, and
## on an open map near the river (where a town would start).
func start_point() -> Vector2:
	var best := Vector2.ZERO
	var score := INF
	for j in range(SIDE / 4, SIDE * 3 / 4, 6):
		for i in range(SIDE / 4, SIDE * 3 / 4, 6):
			var h := heights[j * SIDE + i]
			if h < 0.4:
				continue
			var p := _pos(i, j)
			var sl := absf(heights[j * SIDE + mini(i + 4, CELLS)] - h) + absf(heights[mini(j + 4, CELLS) * SIDE + i] - h)
			var sc := p.length() * 0.4 + sl * 30.0 + h * 2.0
			if not _river.is_empty():
				var rv := _river_at(p)
				sc += absf(rv.x - rv.y - 18.0)
			if sc < score:
				score = sc
				best = p
	return best


# ------------------------------------------------------------------ the horizon

# the land beyond the map, out to the horizon
static var FAR := 320.0
const FAR_STEP := 8.0
const FAR_TILE := 16
var _horizon: Array[MeshInstance3D] = []


## On an open map the country carries on past the edge of the map: drawn
## coarser (nobody builds there), meeting the map's rim sample for sample.
func _build_horizon() -> void:
	for mi in _horizon:
		mi.queue_free()
	_horizon.clear()
	if not kind in OPEN_KINDS:
		return
	var n := int((SIZE + FAR * 2.0) / FAR_STEP)
	var inner0 := int(FAR / FAR_STEP)
	var inner1 := inner0 + int(SIZE / FAR_STEP)
	var per := int(FAR_STEP / STEP)
	var hs := PackedFloat32Array()
	hs.resize((n + 1) * (n + 1))
	for j in n + 1:
		for i in n + 1:
			if i >= inner0 and i <= inner1 and j >= inner0 and j <= inner1:
				# on the rim (or inside): the map's own ground
				hs[j * (n + 1) + i] = heights[index((i - inner0) * per, (j - inner0) * per)]
			else:
				hs[j * (n + 1) + i] = _natural(_far_pos(i, j))
	# a normal and colour per grid point, shared by the cells round it
	var gn := PackedVector3Array()
	var gc := PackedColorArray()
	gn.resize((n + 1) * (n + 1))
	gc.resize((n + 1) * (n + 1))
	for j in n + 1:
		for i in n + 1:
			var a := j * (n + 1) + i
			var hx := hs[a + 1 if i < n else a] - hs[a - 1 if i > 0 else a]
			var hz := hs[a + n + 1 if j < n else a] - hs[a - n - 1 if j > 0 else a]
			var nrm := Vector3(-hx, 2.0 * FAR_STEP, -hz).normalized()
			gn[a] = nrm
			gc[a] = _colour(_far_pos(i, j), hs[a], nrm.y)
	for tj in n / FAR_TILE:
		for ti in n / FAR_TILE:
			var verts := PackedVector3Array()
			var norms := PackedVector3Array()
			var cols := PackedColorArray()
			var idx := PackedInt32Array()
			var shared := {}
			for j in range(tj * FAR_TILE, (tj + 1) * FAR_TILE):
				for i in range(ti * FAR_TILE, (ti + 1) * FAR_TILE):
					if i >= inner0 and i < inner1 and j >= inner0 and j < inner1:
						continue
					# the ring of points round this cell: corners, plus every
					# map sample along an edge it shares with the map
					var ring: Array[Vector3] = []
					var corners := [Vector2i(i, j), Vector2i(i + 1, j), Vector2i(i + 1, j + 1), Vector2i(i, j + 1)]
					for e in 4:
						var a: Vector2i = corners[e]
						var b: Vector2i = corners[(e + 1) % 4]
						ring.append(_far_vert(a, hs, n))
						if _on_rim(a, inner0, inner1) and _on_rim(b, inner0, inner1) and (a.x == b.x) != (a.y == b.y) and _rim_edge(a, b, inner0, inner1):
							for k in range(1, per):
								var t := float(k) / per
								var g := Vector2(a).lerp(Vector2(b), t)
								var gi := int(round((g.x - inner0) * per))
								var gj := int(round((g.y - inner0) * per))
								var p := _pos(gi, gj)
								ring.append(Vector3(p.x, heights[index(gi, gj)], p.y))
					if ring.size() == 4:
						var q := PackedInt32Array()
						for c: Vector2i in corners:
							var g := c.y * (n + 1) + c.x
							if not shared.has(g):
								shared[g] = verts.size()
								verts.append(ring[q.size()])
								norms.append(gn[g])
								cols.append(gc[g])
							q.append(shared[g])
						if absf(ring[0].y - ring[2].y) < absf(ring[1].y - ring[3].y):
							idx.append_array([q[0], q[1], q[2], q[0], q[2], q[3]])
						else:
							idx.append_array([q[0], q[1], q[3], q[1], q[2], q[3]])
						continue
					var base := verts.size()
					var mid := (Vector2(i, j) + Vector2(0.5, 0.5))
					var mp := Vector2(mid.x * FAR_STEP - HALF - FAR, mid.y * FAR_STEP - HALF - FAR)
					_far_push(Vector3(mp.x, _natural(mp), mp.y), verts, norms, cols)
					for v in ring:
						_far_push(v, verts, norms, cols)
					var m := ring.size()
					for k in m:
						idx.append_array([base, base + 1 + k, base + 1 + (k + 1) % m])
			if idx.is_empty():
				continue
			var arr := []
			arr.resize(Mesh.ARRAY_MAX)
			arr[Mesh.ARRAY_VERTEX] = verts
			arr[Mesh.ARRAY_NORMAL] = norms
			arr[Mesh.ARRAY_COLOR] = cols
			arr[Mesh.ARRAY_INDEX] = idx
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			mesh.surface_set_material(0, material)
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			_horizon.append(mi)


func _far_pos(i: int, j: int) -> Vector2:
	return Vector2(i * FAR_STEP - HALF - FAR, j * FAR_STEP - HALF - FAR)


func _far_vert(g: Vector2i, hs: PackedFloat32Array, n: int) -> Vector3:
	var p := _far_pos(g.x, g.y)
	return Vector3(p.x, hs[g.y * (n + 1) + g.x], p.y)


static func _on_rim(g: Vector2i, i0: int, i1: int) -> bool:
	return g.x >= i0 and g.x <= i1 and g.y >= i0 and g.y <= i1 and (g.x == i0 or g.x == i1 or g.y == i0 or g.y == i1)


## Whether a to b runs along the map's edge (not across a corner of it).
static func _rim_edge(a: Vector2i, b: Vector2i, i0: int, i1: int) -> bool:
	if a.x == b.x:
		return a.x == i0 or a.x == i1
	return a.y == i0 or a.y == i1


## A horizon vertex: the ground's normal and colour worked out from the
## natural land around it (painting never reaches out here).
func _far_push(v: Vector3, verts: PackedVector3Array, norms: PackedVector3Array, cols: PackedColorArray) -> void:
	var p := Vector2(v.x, v.z)
	var e := FAR_STEP * 0.5
	var hx := _natural(p + Vector2(e, 0)) - _natural(p - Vector2(e, 0))
	var hz := _natural(p + Vector2(0, e)) - _natural(p - Vector2(0, e))
	var nrm := Vector3(-hx, 2.0 * e, -hz).normalized()
	verts.append(v)
	norms.append(nrm)
	cols.append(_colour(p, v.y, nrm.y))


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
func paint_level(centre: Vector3, radius: float, lv: float, amount: float, use := 0) -> void:
	var base := use * USE_STRIDE
	_each_in(centre, radius, func(k: int, w: float) -> void:
		if w < 0.02:
			return
		var cur := level[k]
		if cur < 0.5 or (_use_of(cur) != use and w > 0.25):
			level[k] = base + lv
		elif _use_of(cur) == use:
			level[k] = base + move_toward(cur - base, lv, amount * minf(w * 3.0, 1.0)))


## The district (Land.USES) a level layer value is painted for.
static func _use_of(v: float) -> int:
	return clampi(int(floor((v + 0.5) / USE_STRIDE)), 0, USES.size() - 1)


## How much of the ground at sample (gi, gj) is paved, 0..1: none up to the
## third level, all of it from the fifth (a level sooner for shops, offices
## and entertainment).
func paved(gi: int, gj: int) -> float:
	var raw := level[gj * SIDE + gi]
	var u := _use_of(raw) if raw >= 0.5 else 0
	var lv := raw - u * USE_STRIDE if raw >= 0.5 else LEVEL_DEFAULT
	if u == 1 or u == 2 or u == 4:
		lv += 1.0
	return smoothstep(2.6, 4.6, lv) * minf(zone[gj * SIDE + gi] * 1.6, 1.0)


## The level the town may grow to here, 1..7 (from the nearest sample).
func level_at(x: float, z: float) -> float:
	var fx := (x + HALF) / STEP
	var fz := (z + HALF) / STEP
	var i := clampi(int(round(fx)), 0, CELLS)
	var j := clampi(int(round(fz)), 0, CELLS)
	var lv := level[j * SIDE + i]
	return lv - _use_of(lv) * USE_STRIDE if lv >= 0.5 else LEVEL_DEFAULT


## The district painted here (an index into USES; homes where nothing was).
func use_at(x: float, z: float) -> int:
	var i := clampi(int(round((x + HALF) / STEP)), 0, CELLS)
	var j := clampi(int(round((z + HALF) / STEP)), 0, CELLS)
	var lv := level[j * SIDE + i]
	return _use_of(lv) if lv >= 0.5 else 0


## Paint (amount > 0) or wipe green: parks where houses would go.
func paint_green(centre: Vector3, radius: float, amount: float) -> void:
	_each_in(centre, radius, func(k: int, w: float) -> void:
		green[k] = clampf(green[k] + amount * minf(w * 2.0, 1.0), 0.0, 1.0))


func green_at(x: float, z: float) -> float:
	return _sample(green, x, z)


## Tells the ground, its tint and everything built on it that the painting
## changed in samples (i0, j0)..(i1, j1) (see BrushMask).
func mark_painted(i0: int, j0: int, i1: int, j1: int) -> void:
	farm_rev += 1
	_mark(i0, j0, i1, j1)


# ------------------------------------------------------------------ farmland

## Fields out in the country: a patchwork of crops in a grid turned by
## farm_angle, each field FIELD metres, drawn by the ground shader. The farm
## map says which fields are farmed (sampled at each field's middle), kept
## clear of the town, the parks, the water and the hills.
const FIELD := Vector2(15.0, 10.0)
const FARM_CELL := 4.0
static var FARM_SIDE := int(SIZE / FARM_CELL) + 1
## how far fields keep from ground painted for the town (in farm cells)
const FARM_CLEAR := 5
var farm_angle := 0.0
## bumped whenever the farm map may need working out again
var farm_rev := 0
var _farm := PackedFloat32Array()
# the town at each farm cell, spread along its row, then down its column too
var _farm_raw := PackedFloat32Array()
var _farm_row := PackedFloat32Array()
var _farm_town := PackedFloat32Array()
# how fit the ground alone is for fields, before the town clears it
var _farm_land := PackedFloat32Array()
var _farm_noise := FastNoiseLite.new()


## Works out the farm map (after the land, the town or the parks changed):
## all of it, or only round `box` (in samples), as far as a change there
## can reach.
func update_farm(box := Rect2i(0, 0, -1, -1)) -> void:
	var n := FARM_SIDE
	var full := box.size.x < 0 or _farm_raw.size() != n * n or _farm_land.size() != n * n
	var lo := Vector2i.ZERO
	var hi := Vector2i(n - 1, n - 1)
	if full:
		_farm_raw.resize(n * n)
		_farm_row.resize(n * n)
		_farm_town.resize(n * n)
		_farm_land.resize(n * n)
		_farm.resize(n * n)
	else:
		var k := STEP / FARM_CELL
		lo = Vector2i(int(floor(box.position.x * k)) - 1, int(floor(box.position.y * k)) - 1).max(Vector2i.ZERO)
		hi = Vector2i(int(ceil(box.end.x * k)) + 1, int(ceil(box.end.y * k)) + 1).min(Vector2i(n - 1, n - 1))
	# how much town there is at each farm cell
	for j in range(lo.y, hi.y + 1):
		for i in range(lo.x, hi.x + 1):
			var x := -HALF + i * FARM_CELL
			var z := -HALF + j * FARM_CELL
			var t := 0.0
			for o: Vector2 in [Vector2.ZERO, Vector2(2, 0), Vector2(0, 2), Vector2(2, 2), Vector2(-2, -2)]:
				t = maxf(t, maxf(zone_at(x + o.x, z + o.y), green_at(x + o.x, z + o.y)))
			_farm_raw[j * n + i] = t
	# spread the town out, a row and then a column at a time
	var c := Vector2i(FARM_CLEAR, FARM_CLEAR)
	var wide_lo := (lo - c).max(Vector2i.ZERO)
	var wide_hi := (hi + c).min(Vector2i(n - 1, n - 1))
	for j in range(lo.y, hi.y + 1):
		for i in range(wide_lo.x, wide_hi.x + 1):
			var t := 0.0
			for a in range(maxi(i - FARM_CLEAR, 0), mini(i + FARM_CLEAR, n - 1) + 1):
				t = maxf(t, _farm_raw[j * n + a])
			_farm_row[j * n + i] = t
	for j in range(wide_lo.y, wide_hi.y + 1):
		for i in range(wide_lo.x, wide_hi.x + 1):
			var t := 0.0
			for b in range(maxi(j - FARM_CLEAR, 0), mini(j + FARM_CLEAR, n - 1) + 1):
				t = maxf(t, _farm_row[b * n + i])
			_farm_town[j * n + i] = t
	# how fit the ground itself is for fields only changes where the ground did
	for j in range(lo.y, hi.y + 1):
		for i in range(lo.x, hi.x + 1):
			var x := -HALF + i * FARM_CELL
			var z := -HALF + j * FARM_CELL
			var h := height_at(x, z)
			var f := smoothstep(-0.12, 0.08, _farm_noise.get_noise_2d(x, z))
			f *= smoothstep(0.7, 1.1, h) * (1.0 - smoothstep(6.5, 8.0, h))
			f *= smoothstep(0.965, 0.985, normal_at(x, z).y)
			_farm_land[j * n + i] = f
	for j in range(wide_lo.y, wide_hi.y + 1):
		for i in range(wide_lo.x, wide_hi.x + 1):
			_farm[j * n + i] = _farm_land[j * n + i] * (1.0 - smoothstep(0.05, 0.2, _farm_town[j * n + i]))


func farm_image() -> Image:
	var bytes := PackedByteArray()
	bytes.resize(FARM_SIDE * FARM_SIDE)
	for k in bytes.size():
		bytes[k] = int(clampf(_farm[k] if k < _farm.size() else 0.0, 0.0, 1.0) * 255.0)
	return Image.create_from_data(FARM_SIDE, FARM_SIDE, false, Image.FORMAT_L8, bytes)


## The middle of the field a point lies in.
func field_centre(x: float, z: float) -> Vector2:
	var q := Vector2(x, z).rotated(-farm_angle) / FIELD
	return ((q.floor() + Vector2(0.5, 0.5)) * FIELD).rotated(farm_angle)


## How far a point is from the edge of its field, in metres.
func field_edge(x: float, z: float) -> float:
	var f := (Vector2(x, z).rotated(-farm_angle) / FIELD)
	f -= f.floor()
	return minf(minf(f.x, 1.0 - f.x) * FIELD.x, minf(f.y, 1.0 - f.y) * FIELD.y)


## Whether the field a point lies in is farmed.
func farm_at(x: float, z: float) -> bool:
	if _farm.is_empty():
		return false
	var c := field_centre(x, z)
	var fx := (c.x + HALF) / FARM_CELL
	var fz := (c.y + HALF) / FARM_CELL
	if fx < 0.0 or fz < 0.0 or fx > FARM_SIDE - 1 or fz > FARM_SIDE - 1:
		return false
	var i := mini(int(fx), FARM_SIDE - 2)
	var j := mini(int(fz), FARM_SIDE - 2)
	var u := fx - i
	var v := fz - j
	var n := FARM_SIDE
	return lerpf(lerpf(_farm[j * n + i], _farm[j * n + i + 1], u), lerpf(_farm[(j + 1) * n + i], _farm[(j + 1) * n + i + 1], u), v) > 0.5


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
	farm_rev += 1
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
	# an island's rim stays under the sea so it never shows a cut edge
	for j in (range(j0, j1 + 1) if not kind in OPEN_KINDS else []):
		for i in range(i0, i1 + 1):
			if i <= 1 or j <= 1 or i >= CELLS - 1 or j >= CELLS - 1:
				heights[j * SIDE + i] = minf(heights[j * SIDE + i], LOW)
	_mark(i0, j0, i1, j1)


## The ground samples changed since take_touched() was last called, as a box.
var touched_lo := Vector2i(1 << 20, 1 << 20)
var touched_hi := Vector2i(-1, -1)


## The same for the ground maps the shaders read (heights, farmland), kept
## apart so the co-op sync and the maps each take their own.
var _map_lo := Vector2i(1 << 20, 1 << 20)
var _map_hi := Vector2i(-1, -1)


func take_map_box() -> Rect2i:
	var r := Rect2i(_map_lo, _map_hi - _map_lo + Vector2i.ONE) if _map_hi.x >= 0 else Rect2i()
	_map_lo = Vector2i(1 << 20, 1 << 20)
	_map_hi = Vector2i(-1, -1)
	return r


func take_touched() -> Rect2i:
	var r := Rect2i(touched_lo, touched_hi - touched_lo + Vector2i.ONE) if touched_hi.x >= 0 else Rect2i()
	touched_lo = Vector2i(1 << 20, 1 << 20)
	touched_hi = Vector2i(-1, -1)
	return r


## A revision count per TILE x TILE metres, bumped whenever anything there
## changes, so the woods and yards know which of their pieces to redo.
const TILE := 16
static var TILES := CELLS / TILE
var tile_rev := PackedInt32Array()


func tile_sig(t: Vector2i) -> int:
	if tile_rev.is_empty():
		return 0
	return tile_rev[clampi(t.y, 0, TILES - 1) * TILES + clampi(t.x, 0, TILES - 1)]


func _mark(i0: int, j0: int, i1: int, j1: int, tint := true) -> void:
	# (the town and its streets levelling ground leave the paint as it was)
	if tint:
		_tint_lo = _tint_lo.min(Vector2i(maxi(i0, 0), maxi(j0, 0)))
		_tint_hi = _tint_hi.max(Vector2i(mini(i1, CELLS), mini(j1, CELLS)))
	if tile_rev.size() != TILES * TILES:
		tile_rev.resize(TILES * TILES)
	for tz in range(maxi(0, (j0 - 2) / TILE), mini(TILES - 1, (j1 + 2) / TILE) + 1):
		for tx in range(maxi(0, (i0 - 2) / TILE), mini(TILES - 1, (i1 + 2) / TILE) + 1):
			tile_rev[tz * TILES + tx] += 1
	touched_lo = touched_lo.min(Vector2i(maxi(i0, 0), maxi(j0, 0)))
	touched_hi = touched_hi.max(Vector2i(mini(i1, CELLS), mini(j1, CELLS)))
	_map_lo = _map_lo.min(Vector2i(maxi(i0, 0), maxi(j0, 0)))
	_map_hi = _map_hi.max(Vector2i(mini(i1, CELLS), mini(j1, CELLS)))
	# the shadow stand-in reads the ground a few samples round each of its points
	for tz in range(maxi(0, (j0 - 3) / SHADOW_TILE), mini(CELLS / SHADOW_TILE - 1, (j1 + 3) / SHADOW_TILE) + 1):
		for tx in range(maxi(0, (i0 - 3) / SHADOW_TILE), mini(CELLS / SHADOW_TILE - 1, (i1 + 3) / SHADOW_TILE) + 1):
			_shadow_tiles[Vector2i(tx, tz)] = true
	for cz in range(maxi(0, (j0 - 1) / CHUNK), mini(CELLS / CHUNK - 1, (j1 + 1) / CHUNK) + 1):
		for cx in range(maxi(0, (i0 - 1) / CHUNK), mini(CELLS / CHUNK - 1, (i1 + 1) / CHUNK) + 1):
			# changed since it was last worked out: work it out again
			_dirty_chunk(Vector2i(cx, cz), true)


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
	_mark(i0, j0, i1, j1, false)


## Eases the ground within `r` of a line back to the natural lie of the land
## (where a highway was taken up), fading out over the last few metres.
func renature(pts: PackedVector2Array, r: float) -> void:
	if pts.size() < 2:
		return
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in pts:
		lo = lo.min(p)
		hi = hi.max(p)
	var i0 := maxi(2, int(floor((lo.x - r + HALF) / STEP)))
	var i1 := mini(CELLS - 2, int(ceil((hi.x + r + HALF) / STEP)))
	var j0 := maxi(2, int(floor((lo.y - r + HALF) / STEP)))
	var j1 := mini(CELLS - 2, int(ceil((hi.y + r + HALF) / STEP)))
	if i0 > i1 or j0 > j1:
		return
	var w := i1 - i0 + 1
	var best := PackedFloat32Array()
	best.resize(w * (j1 - j0 + 1))
	best.fill(INF)
	for s in pts.size() - 1:
		var a := pts[s]
		var b := pts[s + 1]
		var si0 := maxi(i0, int(floor((minf(a.x, b.x) - r + HALF) / STEP)))
		var si1 := mini(i1, int(ceil((maxf(a.x, b.x) + r + HALF) / STEP)))
		var sj0 := maxi(j0, int(floor((minf(a.y, b.y) - r + HALF) / STEP)))
		var sj1 := mini(j1, int(ceil((maxf(a.y, b.y) + r + HALF) / STEP)))
		for j in range(sj0, sj1 + 1):
			for i in range(si0, si1 + 1):
				var k := (j - j0) * w + (i - i0)
				best[k] = minf(best[k], Geometry2D.get_closest_point_to_segment(_pos(i, j), a, b).distance_to(_pos(i, j)))
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var d := best[(j - j0) * w + (i - i0)]
			if d >= r:
				continue
			var g := j * SIDE + i
			heights[g] = lerpf(heights[g], _base[g], 1.0 - smoothstep(r - 3.0, r, d))
	_mark(i0, j0, i1, j1, false)


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
	_mark(i0, j0, i1, j1, false)


## Remake changed chunks, spending at most `budget_us` microseconds.
func rebuild_dirty(budget_us := 3000) -> void:
	if not _dirty.is_empty():
		revision += 1
		_shadow_dirty = true
	var start := Time.get_ticks_usec()
	for c in _dirty.keys():
		# colours and coarseness first (unless generate() has just worked them
		# out), the mesh after, each in a few pieces so none stalls a frame
		while _dirty.has(c):
			_advance(c)
			if Time.get_ticks_usec() - start > budget_us:
				return


## Marks a chunk to be redrawn; `reprepare` when its ground or paint changed,
## so its colours and coarseness are worked out again too.
func _dirty_chunk(c: Vector2i, reprepare := false) -> void:
	if _dirty.has(c) and (_jobs.has(c) or _prep_row.has(c) or _ready_chunks.has(c)):
		# half redrawn: let it finish and show, then redraw it again from the
		# latest ground (starting over every frame of a brush stroke would
		# never show anything until the finger lifts)
		_again[c] = _again.get(c, false) or reprepare
		return
	_dirty[c] = true
	_jobs.erase(c)
	if reprepare:
		_ready_chunks.erase(c)
		_prep_row.erase(c)


## Does the next piece of redrawing a dirty chunk.
func _advance(c: Vector2i) -> void:
	if not _ready_chunks.has(c):
		var row: int = _prep_row.get(c, 0)
		if row <= CHUNK:
			var to := mini(row + 4, CHUNK + 1)
			_prepare_colours(c, row, to)
			_prep_row[c] = to
		else:
			_prep_row.erase(c)
			_ready_chunks[c] = true
			_prepare_steps(c)
		return
	if not _jobs.has(c):
		_jobs[c] = {"bj": 0, "verts": PackedVector3Array(), "norms": PackedVector3Array(), "cols": PackedColorArray(), "idx": PackedInt32Array(), "at": PackedInt32Array()}
		_jobs[c].at.resize((CHUNK + 1) * (CHUNK + 1))
		_jobs[c].at.fill(-1)
	var job: Dictionary = _jobs[c]
	if job.bj < CHUNK / BLOCK:
		_build_rows(c, job, job.bj, job.bj + 1)
		job.bj += 1
		return
	_jobs.erase(c)
	_dirty.erase(c)
	_ready_chunks.erase(c)
	_commit_chunk(c, job)
	if _again.has(c):
		var re: bool = _again[c]
		_again.erase(c)
		_dirty_chunk(c, re)


func is_settled() -> bool:
	return _dirty.is_empty()


var _shadow_dirty := true
# the shadow stand-in's heights, and the tiles of it to redo
var _shadow_hs := PackedFloat32Array()
var _shadow_tiles := {}
var _shadow_all := true
# the shadow stand-in is cut into tiles this many samples across
const SHADOW_TILE := 48


## Remake the shadow stand-in (call once a stroke has finished): the ground
## every 4 samples, sunk a little, only where it is hilly enough to shade
## anything, in tiles so only what is in view is drawn.
func rebuild_shadow(budget_us := -1) -> void:
	const S := 4
	var n := CELLS / S + 1
	var per := SHADOW_TILE / S
	var tiles: Array = []
	if _shadow.is_empty() or _shadow_hs.size() != n * n or _shadow_all:
		# all of it (a new map)
		_shadow_hs.resize(n * n)
		for tj in CELLS / SHADOW_TILE:
			for ti in CELLS / SHADOW_TILE:
				tiles.append(Vector2i(ti, tj))
	elif _shadow_tiles.is_empty():
		return
	else:
		# only the tiles whose ground changed, one at a time when time is short
		tiles = _shadow_tiles.keys()
		if budget_us >= 0:
			tiles = tiles.slice(0, 1)
	_shadow_all = false
	for t in tiles:
		_shadow_tiles.erase(t)
	_shadow_dirty = false
	for t: Vector2i in tiles:
		for j in range(t.y * per, mini(t.y * per + per, n - 1) + 1):
			for i in range(t.x * per, mini(t.x * per + per, n - 1) + 1):
				# never above the real ground around it, so cuttings and streets stay lit
				var gi := i * S
				var gj := j * S
				var h := heights[gj * SIDE + gi]
				var i0 := maxi(gi - 2, 0)
				var i1 := mini(gi + 2, CELLS)
				for jj in range(maxi(gj - 2, 0), mini(gj + 2, CELLS) + 1):
					var row := jj * SIDE
					for ii in range(i0, i1 + 1):
						h = minf(h, heights[row + ii])
				_shadow_hs[j * n + i] = maxf(h, -0.6) - 0.12
	var hs := _shadow_hs
	for t: Vector2i in tiles:
		var ti := t.x
		var tj := t.y
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
	_prepare_colours(c, 0, CHUNK + 1)
	_prepare_steps(c)


func _prepare_colours(c: Vector2i, j0: int, j1: int) -> void:
	for j in range(j0, j1):
		for i in CHUNK + 1:
			var gi := c.x * CHUNK + i
			var gj := c.y * CHUNK + j
			_col[gj * SIDE + gi] = _sample_colour(gi, gj)


func _prepare_steps(c: Vector2i) -> void:
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
						_dirty_chunk(nc)


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
	var tol_col := TOL_COL
	if wild and not deep and SIZE > NORMAL_SIZE:
		tol = TOL_WILD_BIG
		tol_col = TOL_COL_WILD_BIG
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
					if absf(col.r - o.r) > tol_col or absf(col.g - o.g) > tol_col or absf(col.b - o.b) > tol_col or absf(col.a - o.a) > tol_col:
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
		col = col.lerp(Color("b5c97a"), zn * 0.18)
	var gn := green[gj * SIDE + gi]
	if gn > 0.0 and h > 0.0:
		# park lawns, a lusher green
		col = col.lerp(Color("74bf5e"), gn * 0.3)
	if zn > 0.0 and h > 0.45:
		# the denser the town, the more of the ground between its streets and
		# buildings is paved: lawns in the suburbs, stone plazas downtown.
		# The shader reads alpha below 1 as paving and lays slabs over it.
		# (beaches and river banks stay sand and grass)
		var pv := paved(gi, gj) * (1.0 - minf(gn * 1.6, 1.0)) * smoothstep(0.55, 0.85, up) * smoothstep(0.45, 0.95, h)
		if pv > 0.0:
			col = col.lerp(PAVED, pv)
			col.a = 1.0 - pv
	if h > -0.3:
		col = col.darkened(clampf(lap * 0.9, 0.0, 0.14)) if lap > 0.0 else col.lightened(clampf(-lap * 0.5, 0.0, 0.08))
	return col


## parks' tint while painting
const PARK_TINT := Color("2fd35a")


## Brings the tint map up to date where the painting changed; false when
## nothing did. While growing, the painted ground shows its district and
## level: its district's colour, deeper where it may grow taller, and parks
## a lusher green.
func update_tint() -> bool:
	if tint_img == null or tint_img.get_width() != SIDE:
		tint_img = Image.create(SIDE, SIDE, false, Image.FORMAT_RGBA8)
		_tint_bytes = PackedByteArray()
		_tint_bytes.resize(SIDE * SIDE * 4)
		_tint_lo = Vector2i(0, 0)
		_tint_hi = Vector2i(CELLS, CELLS)
	if _tint_hi.x < _tint_lo.x:
		return false
	# written as bytes and handed over in one go (much quicker than pixel by pixel)
	var bytes := _tint_bytes
	for j in range(_tint_lo.y, _tint_hi.y + 1):
		for i in range(_tint_lo.x, _tint_hi.x + 1):
			var k := j * SIDE + i
			var zn := zone[k]
			var gn := green[k]
			if (zn <= 0.0 and gn <= 0.0) or heights[k] <= 0.0:
				bytes[k * 4] = 0
				bytes[k * 4 + 1] = 0
				bytes[k * 4 + 2] = 0
				bytes[k * 4 + 3] = 0
				continue
			var col := Color(0, 0, 0, 0)
			if zn > 0.0:
				var raw := level[k]
				var u := _use_of(raw) if raw >= 0.5 else 0
				var lv := raw - u * USE_STRIDE if raw >= 0.5 else LEVEL_DEFAULT
				col = USE_TINTS[u].lerp(USE_TINTS[u].darkened(0.45), clampf((lv - 1.0) / (LEVEL_MAX - 1.0), 0.0, 1.0))
				# A is how much of the sample is painted: the shader draws the
				# painted area's edge where it crosses a half, crisp
				col.a = zn
			if gn > 0.0:
				col = Color(PARK_TINT, maxf(col.a, gn)) if gn >= 0.5 or col.a <= 0.0 else col
			# premultiplied, so the shader can take the blend at an edge apart
			var a := clampf(col.a, 0.0, 1.0)
			bytes[k * 4] = int(clampf(col.r * a, 0.0, 1.0) * 255.0)
			bytes[k * 4 + 1] = int(clampf(col.g * a, 0.0, 1.0) * 255.0)
			bytes[k * 4 + 2] = int(clampf(col.b * a, 0.0, 1.0) * 255.0)
			bytes[k * 4 + 3] = int(a * 255.0)
	tint_img.set_data(SIDE, SIDE, false, Image.FORMAT_RGBA8, bytes)
	_tint_lo = Vector2i(1 << 20, 1 << 20)
	_tint_hi = Vector2i(-1, -1)
	return true


## Adds rows bj0..bj1 of a chunk's blocks to its mesh being put together.
func _build_rows(c: Vector2i, job: Dictionary, bj0: int, bj1: int) -> void:
	var verts: PackedVector3Array = job.verts
	var norms: PackedVector3Array = job.norms
	var cols: PackedColorArray = job.cols
	var idx: PackedInt32Array = job.idx
	var at: PackedInt32Array = job.at
	var per := CHUNK / BLOCK
	var ring := PackedInt32Array()
	for bj in range(bj0, mini(bj1, per)):
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
	job.verts = verts
	job.norms = norms
	job.cols = cols
	job.idx = idx
	job.at = at


func _commit_chunk(c: Vector2i, job: Dictionary) -> void:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = job.verts
	arr[Mesh.ARRAY_NORMAL] = job.norms
	arr[Mesh.ARRAY_COLOR] = job.cols
	arr[Mesh.ARRAY_INDEX] = job.idx
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
	var fresh := _fresh(p)
	if fresh > 0.0 and h < sand_line + 0.3:
		# rivers and lakes: grassy banks down to a strip of mud and pebbles,
		# and a dark, weedy bed (no sandy beaches inland)
		var bank: Color
		if h < -0.05:
			bank = Color("7d7a5c").darkened(clampf(-h * 0.08, 0.0, 0.3))
		else:
			bank = Color("9a9068").lerp(Color("7fbf5f"), smoothstep(0.0, sand_line + 0.3, h + n * 0.08))
		col = col.lerp(bank, fresh)
	var rock := Color("a49d90").lerp(Color("8a847a"), clampf(n + 0.5, 0.0, 1.0))
	col = col.lerp(rock, smoothstep(0.3, 0.45, slope + n * 0.06))
	return col


## 1 by fresh water (rivers, lakes), 0 by the sea.
func _fresh(p: Vector2) -> float:
	if not kind in OPEN_KINDS:
		return 0.0
	if _coast_dir == Vector2.ZERO:
		return 1.0
	var f := smoothstep(45.0, 90.0, p.dot(_coast_dir) - _coast_at)
	if SIZE > NORMAL_SIZE and f > 0.0:
		# the big coast's other shores are sea too, with sandy beaches
		f *= smoothstep(30.0, 70.0, -_outline(p))
	return f


# ------------------------------------------------------------------ maps for shaders

## Distance from every sea point to the nearest land, in world units (capped),
## for the water shader's foam and calm shallows.
func shore_image(cap: float, box := Rect2i(0, 0, -1, -1)) -> Image:
	var whole := box.size.x <= 0 or _shore_bytes.size() != SIDE * SIDE * 2 or _shore_cap != cap
	_shore_cap = cap
	# what can change: the box and as far round it as the distances go; worked
	# out from the ground that far round that again
	var reach := int(ceil(cap / STEP)) + 1
	var out := Rect2i(0, 0, SIDE, SIDE)
	var win := out
	if whole:
		_shore_bytes.resize(SIDE * SIDE * 2)
	else:
		out = box.grow(reach).intersection(out)
		win = out.grow(reach).intersection(Rect2i(0, 0, SIDE, SIDE))
	var w := win.size.x
	var h := win.size.y
	var big := 1e6
	var d := PackedFloat32Array()
	d.resize(w * h)
	for y in h:
		var row := (win.position.y + y) * SIDE + win.position.x
		for x in w:
			d[y * w + x] = 0.0 if heights[row + x] > 0.0 else big
	# two-pass chamfer distance (3-4 weights), good to a few percent
	var a := STEP
	var b := STEP * 1.4142
	for y in h:
		for x in w:
			var k := y * w + x
			var v := d[k]
			if x > 0: v = minf(v, d[k - 1] + a)
			if y > 0:
				v = minf(v, d[k - w] + a)
				if x > 0: v = minf(v, d[k - w - 1] + b)
				if x < w - 1: v = minf(v, d[k - w + 1] + b)
			d[k] = v
	for y in range(h - 1, -1, -1):
		for x in range(w - 1, -1, -1):
			var k := y * w + x
			var v := d[k]
			if x < w - 1: v = minf(v, d[k + 1] + a)
			if y < h - 1:
				v = minf(v, d[k + w] + a)
				if x < w - 1: v = minf(v, d[k + w + 1] + b)
				if x > 0: v = minf(v, d[k + w - 1] + b)
			d[k] = v
	# alpha: fresh water (rivers, lakes: calm, little foam) rather than sea
	var bytes := _shore_bytes
	for j in range(out.position.y, out.end.y):
		for i in range(out.position.x, out.end.x):
			var k := j * SIDE + i
			bytes[k * 2] = int(clampf(d[(j - win.position.y) * w + i - win.position.x] / cap, 0.0, 1.0) * 255.0)
			bytes[k * 2 + 1] = int(_fresh(_pos(i, j)) * 255.0)
	return Image.create_from_data(SIDE, SIDE, false, Image.FORMAT_LA8, bytes)


var _shore_bytes := PackedByteArray()
var _shore_cap := 0.0


## Ground height map for the city shader's contact shading.
func height_image() -> Image:
	var bytes := PackedByteArray()
	bytes.resize(SIDE * SIDE)
	for k in SIDE * SIDE:
		bytes[k] = int(clampf((heights[k] + MAP_BIAS) / MAP_SCALE, 0.0, 1.0) * 255.0)
	return Image.create_from_data(SIDE, SIDE, false, Image.FORMAT_L8, bytes)


## Writes the heights inside `box` (in samples) into a height_image().
func paint_heights(img: Image, box: Rect2i) -> void:
	for j in range(maxi(box.position.y, 0), mini(box.end.y, SIDE)):
		for i in range(maxi(box.position.x, 0), mini(box.end.x, SIDE)):
			var v := float(int(clampf((heights[j * SIDE + i] + MAP_BIAS) / MAP_SCALE, 0.0, 1.0) * 255.0)) / 255.0
			img.set_pixel(i, j, Color(v, v, v))


## The little edits the player has made, as (index, delta) pairs, for saving.
func edits() -> Dictionary:
	return edits_of(heights, _base)


func zone_edits() -> Dictionary:
	return painted_of(zone, 0.01)


func green_edits() -> Dictionary:
	return painted_of(green, 0.01)


func level_edits() -> Dictionary:
	return painted_of(level, 0.5)


## The same from copies of the layers, so a save can work them out off the
## main thread: (index, offset) where the ground was reshaped...
static func edits_of(h: PackedFloat32Array, base: PackedFloat32Array) -> Dictionary:
	var out := {}
	for k in h.size():
		var dlt := h[k] - base[k]
		if absf(dlt) > 0.01:
			out[k] = snappedf(dlt, 0.01)
	return out


## ...and (index, value) wherever a painted layer is above `least`.
static func painted_of(layer: PackedFloat32Array, least: float) -> Dictionary:
	var out := {}
	for k in layer.size():
		if layer[k] > least or (least >= 0.5 and layer[k] >= least):
			out[k] = snappedf(layer[k], 0.01)
	return out


func apply_level(e: Dictionary) -> void:
	farm_rev += 1
	for k in e:
		var i := int(k)
		if i >= 0 and i < level.size():
			level[i] = clampf(float(e[k]), 0.0, USE_STRIDE * USES.size())
	_mark_keys(e)


func apply_green(e: Dictionary) -> void:
	farm_rev += 1
	for k in e:
		var i := int(k)
		if i >= 0 and i < green.size():
			green[i] = clampf(float(e[k]), 0.0, 1.0)
	_mark_keys(e)


func apply_zone(e: Dictionary) -> void:
	farm_rev += 1
	for k in e:
		var i := int(k)
		if i >= 0 and i < zone.size():
			zone[i] = clampf(float(e[k]), 0.0, 1.0)
	_mark_keys(e)


## Heights, growing area and green all at once, as snapshot() took them.
func snapshot() -> Array:
	return [heights.duplicate(), zone.duplicate(), green.duplicate(), level.duplicate()]


## Puts the ground back as snapshot() took it, redrawing only the rows and
## columns that differ. Returns the box of samples that changed as
## [lo, hi, heights_changed], or an empty array if nothing did.
func restore(snap: Array) -> Array:
	var layers := [heights, zone, green, level]
	var lo := Vector2i(SIDE, SIDE)
	var hi := Vector2i(-1, -1)
	var shaped := false
	for n in mini(snap.size(), layers.size()):
		var now: PackedFloat32Array = layers[n]
		var was: PackedFloat32Array = snap[n]
		if now == was:
			continue
		for j in SIDE:
			var a := j * SIDE
			if now.slice(a, a + SIDE) == was.slice(a, a + SIDE):
				continue
			# the first and last samples along the row that differ
			var i0 := 0
			while now[a + i0] == was[a + i0]:
				i0 += 1
			var i1 := SIDE - 1
			while now[a + i1] == was[a + i1]:
				i1 -= 1
			lo = lo.min(Vector2i(i0, j))
			hi = hi.max(Vector2i(i1, j))
		shaped = shaped or n == 0
	if hi.x < 0:
		return []
	farm_rev += 1
	heights = snap[0].duplicate()
	zone = snap[1].duplicate()
	green = snap[2].duplicate()
	if snap.size() > 3:
		level = snap[3].duplicate()
	_mark(lo.x, lo.y, hi.x, hi.y)
	changed.emit()
	return [lo, hi, shaped]


## The middle of sample (i, j) on the ground.
func sample_pos(i: int, j: int) -> Vector2:
	return _pos(i, j)


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
	farm_rev += 1
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
				level[i] = clampf(v, 0.0, USE_STRIDE * USES.size())
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
	farm_rev += 1
	for k in e:
		var i := int(k)
		if i >= 0 and i < heights.size():
			heights[i] = _base[i] + float(e[k])
	_mark_keys(e)
	if not _pending_build:
		rebuild_dirty(1 << 20)
		rebuild_shadow()
	changed.emit()
