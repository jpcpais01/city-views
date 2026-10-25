class_name FarLand
extends Node3D
## The country past the horizon ring, out to where the haze swallows it: the
## valley's own land carrying on, rising into hills and then a blue range of
## mountains (snow on the highest peaks) round an inland map, with the river
## still winding through; the far shores of a mainland and other islands
## across the sea from an island or a coast. Drawn as square rings, each twice
## as far out and twice as coarse as the one inside it, stitched so they meet
## exactly (no seams, no cracks), the first one meeting Land's horizon ring
## sample for sample. Nobody builds out here, it is the same at every zoom and
## casts no shadows (the sun's shadow map never reaches it), and cells that lie
## wholly under the sea are left out (the seabed and the water cover them).

## the first ring's cells, in metres (each ring further out doubles it)
const STEP0 := 64.0
## how many rings: out to about 8 km, where the haze has taken everything
const RINGS := 4
## below this a cell is under the sea for good (the seabed plane shows instead)
const UNDER := -2.6
## where the mountains rise to their full height, past the horizon ring's edge
const RISE := 1700.0
const PEAK := 330.0

var land: Land
var material: Material
var _ridge := FastNoiseLite.new()
var _range := FastNoiseLite.new()
var _shore := FastNoiseLite.new()
var _tint := FastNoiseLite.new()
var _meshes: Array[MeshInstance3D] = []
# where the far country starts (the outer edge of what Land draws itself)
var _a0 := 0.0
# heights already worked out, by position in metres (so rings share their edges)
var _h := {}
var tris := 0


## Throws away what was drawn and draws the far country for the land's map as it is now.
func rebuild() -> void:
	for mi in _meshes:
		mi.queue_free()
	_meshes.clear()
	_h.clear()
	tris = 0
	var s: int = land._noise.seed
	_ridge.seed = s + 101
	_ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_ridge.fractal_octaves = 5
	_ridge.fractal_lacunarity = 2.1
	_ridge.fractal_gain = 0.48
	_ridge.frequency = 1.0 / 1500.0
	_range.seed = s + 131
	_range.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_range.fractal_octaves = 2
	_range.frequency = 1.0 / 3200.0
	_shore.seed = s + 151
	_shore.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_shore.fractal_octaves = 4
	_shore.frequency = 1.0 / 2600.0
	_tint.seed = s + 171
	_tint.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_tint.fractal_octaves = 2
	_tint.frequency = 1.0 / 260.0
	var open: bool = land.kind in Land.OPEN_KINDS
	_a0 = Land.HALF + (Land.FAR if open else 0.0)
	var a := _a0
	var step := STEP0
	# the first ring meets Land's horizon ring, a vertex every FAR_STEP along
	# its inner edge; an island has none (open sea round the map's edge)
	var inner := Land.FAR_STEP if open else STEP0
	for ring in RINGS:
		var next := step * 2.0
		var b := ceilf(a * 2.0 / next) * next
		_build_ring(a, b, step, inner)
		inner = step
		a = b
		step = next


## Height of the far country at p (metres; the map's middle is 0, 0).
func height(p: Vector2) -> float:
	var key := Vector2i(roundi(p.x * 4.0), roundi(p.y * 4.0))
	if _h.has(key):
		return _h[key]
	var h := _height(p)
	_h[key] = h
	return h


func _height(p: Vector2) -> float:
	var h: float = land.natural_at(p)
	# how far past the edge of what Land draws: nothing changes until well clear of it
	var out := maxf(absf(p.x), absf(p.y)) - _a0
	if out <= 16.0:
		return h
	var r := p.length()
	var ramp := smoothstep(60.0, RISE, out + _range.get_noise_2d(p.x + 900.0, p.y) * 260.0)
	var mtn := _mountains(p) * ramp
	match land.kind:
		"river", "lakes":
			# the river keeps its valley through the hills
			var rv: Vector2 = land._river_at(p)
			mtn *= smoothstep(rv.y + 30.0, rv.y + 420.0, rv.x)
			h += mtn
			if rv.x < rv.y + 30.0:
				h = minf(h, -1.2)
		"coast":
			var c: Vector3 = land.coast()
			var inland := p.dot(Vector2(c.x, c.y)) - c.z
			if Land.SIZE <= Land.NORMAL_SIZE:
				# the valley runs back into mountains; the sea side stays sea,
				# with far shores across it
				var rv: Vector2 = land._river_at(p)
				mtn *= smoothstep(rv.y + 30.0, rv.y + 420.0, rv.x) * smoothstep(80.0, 700.0, inland)
				h += mtn
				if rv.x < rv.y + 30.0 and inland > 0.0:
					h = minf(h, -1.2)
				if inland < 0.0:
					h = maxf(h, _far_shore(p, r, 1300.0))
			else:
				# the big coast is an island of its own: other shores far off
				h = maxf(h, _far_shore(p, r, 1500.0))
		_:
			h = maxf(h, _far_shore(p, r, 1500.0))
	return h


## The bare mountains (0 at the foot), before they are faded in with distance.
func _mountains(p: Vector2) -> float:
	var ridge := _ridge.get_noise_2d(p.x, p.y) * 0.5 + 0.5
	# whole ranges and the gaps between them
	var big := smoothstep(-0.45, 0.5, _range.get_noise_2d(p.x, p.y))
	return (pow(ridge, 2.2) * PEAK + 8.0) * (0.25 + 0.75 * big)


## The far shores across the sea: a mainland or islands, rising into hills and
## mountains of their own, starting `from` metres out; the seabed between.
func _far_shore(p: Vector2, r: float, from: float) -> float:
	var c := _shore.get_noise_2d(p.x, p.y) + smoothstep(from, from + 3000.0, r) * 0.25 - 0.1
	var mask := smoothstep(0.0, 0.18, c) * smoothstep(from, from + 600.0, r)
	if mask <= 0.0:
		return -20.0
	var hills := _mountains(p) * smoothstep(0.05, 0.5, c) * 0.85
	return lerpf(-8.0, 1.2 + hills, mask)


## One square ring of cells `step` across, between `a` and `b` out from the
## middle; edges on its inner rim are split every `inner` metres to meet the
## ring inside.
func _build_ring(a: float, b: float, step: float, inner: float) -> void:
	var n := int(b * 2.0 / step)
	var per := int(step / inner)
	# split into tiles so each is culled on its own
	var tile := 8
	for tj in range(0, n, tile):
		for ti in range(0, n, tile):
			var verts := PackedVector3Array()
			var norms := PackedVector3Array()
			var cols := PackedColorArray()
			var idx := PackedInt32Array()
			var shared := {}
			for j in range(tj, mini(tj + tile, n)):
				for i in range(ti, mini(ti + tile, n)):
					var x0 := -b + i * step
					var z0 := -b + j * step
					var mid := Vector2(x0 + step * 0.5, z0 + step * 0.5)
					if maxf(absf(mid.x), absf(mid.y)) < a:
						continue
					var corners: Array[Vector2] = [Vector2(x0, z0), Vector2(x0 + step, z0), Vector2(x0 + step, z0 + step), Vector2(x0, z0 + step)]
					var ring: Array[Vector2] = []
					for e in 4:
						var c0: Vector2 = corners[e]
						var c1: Vector2 = corners[(e + 1) % 4]
						ring.append(c0)
						if per > 1 and _on_inner(c0, c1, a):
							for k in range(1, per):
								ring.append(c0.lerp(c1, float(k) / per))
					var top := height(mid)
					for q in ring:
						top = maxf(top, height(q))
					if top < UNDER:
						continue
					if ring.size() == 4:
						var q4 := PackedInt32Array()
						for c in corners:
							q4.append(_vert(c, step, shared, verts, norms, cols))
						if absf(height(corners[0]) - height(corners[2])) < absf(height(corners[1]) - height(corners[3])):
							idx.append_array([q4[0], q4[1], q4[2], q4[0], q4[2], q4[3]])
						else:
							idx.append_array([q4[0], q4[1], q4[3], q4[1], q4[2], q4[3]])
						continue
					var m := _vert(mid, step, shared, verts, norms, cols)
					var ids := PackedInt32Array()
					for q in ring:
						ids.append(_vert(q, step, shared, verts, norms, cols))
					for k in ids.size():
						idx.append_array([m, ids[k], ids[(k + 1) % ids.size()]])
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
			_meshes.append(mi)
			tris += idx.size() / 3


## Whether c0..c1 runs along the ring's inner rim.
static func _on_inner(c0: Vector2, c1: Vector2, a: float) -> bool:
	if c0.x == c1.x:
		return absf(c0.x) == a and maxf(absf(c0.y), absf(c1.y)) <= a
	return absf(c0.y) == a and maxf(absf(c0.x), absf(c1.x)) <= a


func _vert(p: Vector2, step: float, shared: Dictionary, verts: PackedVector3Array, norms: PackedVector3Array, cols: PackedColorArray) -> int:
	var key := Vector2i(roundi(p.x * 4.0), roundi(p.y * 4.0))
	if shared.has(key):
		return shared[key]
	var h := height(p)
	# the normal from the land round about, as coarse as the cells it shades
	var e := step * 0.5
	var hx := _height(p + Vector2(e, 0)) - _height(p - Vector2(e, 0))
	var hz := _height(p + Vector2(0, e)) - _height(p - Vector2(0, e))
	var nrm := Vector3(-hx, 2.0 * e, -hz).normalized()
	shared[key] = verts.size()
	verts.append(Vector3(p.x, h, p.y))
	norms.append(nrm)
	cols.append(_colour(p, h, nrm.y))
	return shared[key]


## Meadows and farmland low down, then dark forest up the slopes, bare rock
## above the tree line and snow on the highest peaks.
func _colour(p: Vector2, h: float, up: float) -> Color:
	var col: Color = land._colour(p, minf(h, 10.0), up if h < 12.0 else 1.0)
	if h <= 10.0:
		return col
	var n := _tint.get_noise_2d(p.x, p.y)
	var forest := Color("4f7a43").lerp(Color("3c6439"), clampf(n + 0.5, 0.0, 1.0))
	col = col.lerp(forest, smoothstep(10.0, 40.0, h))
	var rock := Color("8d8679").lerp(Color("a39b8c"), clampf(n * 0.8 + 0.5, 0.0, 1.0))
	var tree_line := 150.0 + n * 40.0
	col = col.lerp(rock, smoothstep(tree_line - 20.0, tree_line + 25.0, h + (1.0 - up) * 160.0))
	var snow_line := 235.0 + n * 30.0
	col = col.lerp(Color("f2f4f7"), smoothstep(snow_line, snow_line + 25.0, h + (up - 0.8) * 60.0))
	return col
