class_name Streets
extends Node3D
## Streets on the new island. Each street is a smooth centre line with a graded
## height profile: it follows the land but evens out bumps and keeps slopes
## walkable, and the ground is cut and filled to meet it. Built as one mesh per
## street with asphalt, kerbs, paved pavements and centre dashes. Where streets
## meet, each one leaves a gap in the other's pavement, so junctions open up.

signal changed

const SAMPLE := 0.5
const MAX_GRADE := 0.16
const CURB := 0.06
const PAVE := 0.42
const SKIRT := 0.2
const KINDS := {
	"main": {"w": 0.78, "dash": true},
	"side": {"w": 0.56, "dash": false},
}

var land: Land
var material: Material
var streets: Array = []
var _meshes := {}
var _next_id := 1
# streets being laid out along their length: id -> seconds since placed
var _laying := {}
const LAY_TIME := 0.8


class Street:
	var id := 0
	var kind := "main"
	var pts := PackedVector2Array()
	var ys := PackedFloat32Array()
	var lo := Vector2.ZERO
	var hi := Vector2.ZERO

	func w() -> float:
		return Streets.KINDS[kind].w

	func reach() -> float:
		return w() + Streets.PAVE

	func update_bounds() -> void:
		lo = Vector2(INF, INF)
		hi = Vector2(-INF, -INF)
		for p in pts:
			lo = lo.min(p)
			hi = hi.max(p)

	func near_box(p: Vector2, r: float) -> bool:
		return p.x > lo.x - r and p.y > lo.y - r and p.x < hi.x + r and p.y < hi.y + r

	## Distance from p to the centre line, with the street height there.
	func closest(p: Vector2) -> Vector3:
		var best := INF
		var by := 0.0
		var bs := 0.0
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var ab := b - a
			var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
			var d := p.distance_to(a + ab * t)
			if d < best:
				best = d
				by = lerpf(ys[i], ys[i + 1], t)
				bs = i + t
		return Vector3(best, by, bs)


# ------------------------------------------------------------------ building streets

## Turns a finger stroke into a street. Returns it, or null if too short.
func add_stroke(raw: PackedVector2Array, kind := "main") -> Street:
	var pts := _resample(raw, 1.2)
	if pts.size() < 2 or _length(pts) < 2.5:
		return null
	pts = _chaikin(_chaikin(pts))
	# ends that stop just short of another street join it
	pts = _snap_ends(pts)
	pts = _resample(pts, SAMPLE)
	if pts.size() < 3:
		return null
	var s := Street.new()
	s.id = _next_id
	_next_id += 1
	s.kind = kind
	s.pts = pts
	s.update_bounds()
	_grade(s)
	streets.append(s)
	land.conform(s.pts, s.ys, s.w() + PAVE + 0.15, 2.6)
	_reconform_near(s)
	_laying[s.id] = 0.0
	_build(s)
	for o in _touching(s):
		_build(o)
	changed.emit()
	return s


## Removes street within `radius` of p, splitting streets that pass through.
func erase_at(p: Vector2, radius: float) -> bool:
	var hit := false
	for s in streets.duplicate():
		if not s.near_box(p, radius + s.reach()):
			continue
		var pieces: Array = []
		var cur := PackedVector2Array()
		var cy := PackedFloat32Array()
		var cut := false
		for i in s.pts.size():
			if s.pts[i].distance_to(p) < radius:
				cut = true
				if cur.size() >= 3:
					pieces.append([cur, cy])
				cur = PackedVector2Array()
				cy = PackedFloat32Array()
			else:
				cur.append(s.pts[i])
				cy.append(s.ys[i])
		if not cut:
			continue
		hit = true
		if cur.size() >= 3:
			pieces.append([cur, cy])
		var touching := _touching(s)
		_remove(s)
		for pc in pieces:
			var ns := Street.new()
			ns.id = _next_id
			_next_id += 1
			ns.kind = s.kind
			ns.pts = pc[0]
			ns.ys = pc[1]
			ns.update_bounds()
			streets.append(ns)
			_build(ns)
		for o in touching:
			if o in streets:
				_build(o)
	if hit:
		changed.emit()
	return hit


## After the ground was reshaped under some streets, re-grade and re-lay them.
func regrade_in(lo: Vector2, hi: Vector2) -> void:
	var moved: Array = []
	for s in streets:
		if s.hi.x < lo.x or s.hi.y < lo.y or s.lo.x > hi.x or s.lo.y > hi.y:
			continue
		_grade(s)
		land.conform(s.pts, s.ys, s.w() + PAVE + 0.15, 2.6)
		moved.append(s)
	for s in moved:
		_build(s)
		for o in _touching(s):
			if not o in moved:
				_build(o)


func _remove(s: Street) -> void:
	streets.erase(s)
	if _meshes.has(s.id):
		_meshes[s.id].queue_free()
		_meshes.erase(s.id)
	_laying.erase(s.id)


func clear() -> void:
	for s in streets.duplicate():
		_remove(s)
	_next_id = 1


## Height profile: the land's, smoothed, kept off the sea, never steeper than
## MAX_GRADE, and pinned to other streets' heights where it crosses or joins them.
func _grade(s: Street) -> void:
	var n := s.pts.size()
	var ys := PackedFloat32Array()
	ys.resize(n)
	for i in n:
		ys[i] = maxf(land.height_at(s.pts[i].x, s.pts[i].y), 0.14)
	for pass_i in 8:
		var src := ys.duplicate()
		for i in range(1, n - 1):
			ys[i] = src[i - 1] * 0.25 + src[i] * 0.5 + src[i + 1] * 0.25
	_limit(s.pts, ys, {})
	# meet other streets at their height, easing the change in over a few metres
	var pins := {}
	for o in streets:
		if o == s or not _boxes_overlap(s, o):
			continue
		var best := Vector3(INF, 0, 0)
		var bi := -1
		for i in n:
			var c: Vector3 = o.closest(s.pts[i])
			if c.x < best.x:
				best = c
				bi = i
		if bi < 0 or best.x > o.w() + 0.2:
			continue
		var shift: float = best.y - ys[bi]
		for i in n:
			var d := absf(i - bi) * SAMPLE
			ys[i] += shift * clampf(1.0 - d / 9.0, 0.0, 1.0)
		pins[bi] = best.y
	if not pins.is_empty():
		_limit(s.pts, ys, pins)
	s.ys = ys


## Keeps every step within MAX_GRADE, holding pinned samples at their height.
static func _limit(pts: PackedVector2Array, ys: PackedFloat32Array, pins: Dictionary) -> void:
	var n := pts.size()
	for it in 4:
		for i in pins:
			ys[i] = pins[i]
		for i in range(1, n):
			if pins.has(i):
				continue
			var step := MAX_GRADE * pts[i].distance_to(pts[i - 1])
			ys[i] = clampf(ys[i], ys[i - 1] - step, ys[i - 1] + step)
		for i in range(n - 2, -1, -1):
			if pins.has(i):
				continue
			var step := MAX_GRADE * pts[i].distance_to(pts[i + 1])
			ys[i] = clampf(ys[i], ys[i + 1] - step, ys[i + 1] + step)


func _boxes_overlap(a: Street, b: Street) -> bool:
	var r := a.reach() + b.reach()
	return not (a.hi.x + r < b.lo.x or b.hi.x + r < a.lo.x or a.hi.y + r < b.lo.y or b.hi.y + r < a.lo.y)


func _touching(s: Street) -> Array:
	var out: Array = []
	for o in streets:
		if o != s and _boxes_overlap(s, o):
			out.append(o)
	return out


func _reconform_near(s: Street) -> void:
	for o in _touching(s):
		land.conform(o.pts, o.ys, o.w() + PAVE + 0.15, 0.0)


func _snap_ends(pts: PackedVector2Array) -> PackedVector2Array:
	for end in [0, pts.size() - 1]:
		var p := pts[end]
		var best: Street = null
		var bd := 2.8
		for o in streets:
			if not o.near_box(p, bd):
				continue
			var c: Vector3 = o.closest(p)
			if c.x < bd:
				bd = c.x
				best = o
		if best == null or bd < 0.3:
			continue
		var c2: Vector3 = best.closest(p)
		var i := int(c2.z)
		var a := best.pts[mini(i, best.pts.size() - 1)]
		var b := best.pts[mini(i + 1, best.pts.size() - 1)]
		var on := a.lerp(b, c2.z - i)
		if end == 0:
			pts.insert(0, on)
		else:
			pts.append(on)
	return pts


# ------------------------------------------------------------------ polyline helpers

static func _length(pts: PackedVector2Array) -> float:
	var l := 0.0
	for i in pts.size() - 1:
		l += pts[i].distance_to(pts[i + 1])
	return l


## Evenly spaced points along the line.
static func _resample(pts: PackedVector2Array, step: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if pts.size() < 2:
		return pts
	out.append(pts[0])
	var carry := 0.0
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var seg := a.distance_to(b)
		var t := step - carry
		while t <= seg:
			out.append(a.lerp(b, t / seg))
			t += step
		carry = seg - (t - step)
	if out[out.size() - 1].distance_to(pts[pts.size() - 1]) > step * 0.3:
		out.append(pts[pts.size() - 1])
	else:
		out[out.size() - 1] = pts[pts.size() - 1]
	return out


## Corner cutting: rounds the drawn line into gentle curves, ends kept.
static func _chaikin(pts: PackedVector2Array) -> PackedVector2Array:
	if pts.size() < 3:
		return pts
	var out := PackedVector2Array([pts[0]])
	for i in pts.size() - 1:
		out.append(pts[i].lerp(pts[i + 1], 0.25))
		out.append(pts[i].lerp(pts[i + 1], 0.75))
	out.append(pts[pts.size() - 1])
	return out


# ------------------------------------------------------------------ mesh

func _process(delta: float) -> void:
	for id in _laying.keys():
		_laying[id] += delta
		var s: Street = null
		for o in streets:
			if o.id == id:
				s = o
		if s == null or _laying[id] >= LAY_TIME:
			_laying.erase(id)
		if s:
			_build(s)


## Whether a point lies on another street's asphalt or pavement.
func _covered(p: Vector2, s: Street, margin: float) -> bool:
	for o in streets:
		if o == s or not o.near_box(p, o.reach()):
			continue
		if o.closest(p).x < o.w() + margin:
			return true
	return false


func _build(s: Street) -> void:
	var n := s.pts.size()
	var upto := n
	if _laying.has(s.id):
		var t: float = clampf(_laying[s.id] / LAY_TIME, 0.0, 1.0)
		upto = clampi(int(ceil(n * (1.0 - pow(1.0 - t, 3.0)))), 2, n)
	var w := s.w()
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	# which rows to keep: every bend, slope change and pavement gap; straight even runs collapse
	var keep := PackedByteArray()
	keep.resize(upto)
	var gaps := []
	for i in upto:
		var nrm := _side(s, i)
		gaps.append([_covered(s.pts[i] - nrm * (w + PAVE * 0.5), s, PAVE * 0.8), _covered(s.pts[i] + nrm * (w + PAVE * 0.5), s, PAVE * 0.8)])
	var last := 0
	keep[0] = 1
	for i in range(1, upto):
		if i == upto - 1:
			keep[i] = 1
			continue
		var d0 := (s.pts[i] - s.pts[last]).normalized()
		var d1 := (s.pts[i + 1] - s.pts[i]).normalized()
		var bend := absf(d0.angle_to(d1)) > 0.03
		var grade_change := absf((s.ys[i + 1] - s.ys[i]) - (s.ys[i] - s.ys[i - 1])) > 0.004
		var gap_change: bool = gaps[i] != gaps[i - 1] or gaps[i] != gaps[i + 1]
		if bend or grade_change or gap_change or (i - last) * SAMPLE >= 3.0:
			keep[i] = 1
			last = i
	var rows: Array[int] = []
	for i in upto:
		if keep[i]:
			rows.append(i)
	var asphalt := CityGen.ASPHALT.darkened(0.05) if s.kind == "main" else CityGen.ASPHALT
	var pave := CityGen.SIDEWALK
	var kerb := CityGen.SIDEWALK.darkened(0.12)
	for r in rows.size() - 1:
		var i0 := rows[r]
		var i1 := rows[r + 1]
		var left_gap: bool = gaps[i0][0] and gaps[i1][0]
		var right_gap: bool = gaps[i0][1] and gaps[i1][1]
		# asphalt
		_strip(verts, norms, cols, uvs, idx, s, i0, i1, -w, 0.0, w, 0.0, asphalt, MeshKit.ASPHALT)
		for side in [-1.0, 1.0]:
			if (side < 0.0 and left_gap) or (side > 0.0 and right_gap):
				continue
			# kerb face, pavement, and the pavement's outer edge down into the ground
			_strip(verts, norms, cols, uvs, idx, s, i0, i1, side * w, 0.0, side * w, CURB, kerb, 0.0)
			_strip(verts, norms, cols, uvs, idx, s, i0, i1, side * w, CURB, side * (w + PAVE), CURB, pave, MeshKit.SLABS)
			_strip(verts, norms, cols, uvs, idx, s, i0, i1, side * (w + PAVE), CURB, side * (w + PAVE), -SKIRT, kerb, 0.0)
	if KINDS[s.kind].dash:
		var paint := Color(1.0, 0.97, 0.9)
		var along := 0.0
		for i in upto - 1:
			along += SAMPLE
			if fmod(along, 1.4) < SAMPLE and not _covered(s.pts[i], s, 0.3) and not _covered(s.pts[i + 1], s, 0.3):
				_dash(verts, norms, cols, uvs, idx, s, i, paint)
	var mi: MeshInstance3D = _meshes.get(s.id)
	if mi == null:
		mi = MeshInstance3D.new()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_meshes[s.id] = mi
	if idx.is_empty():
		mi.mesh = null
		return
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	m.surface_set_material(0, material)
	mi.mesh = m


## Unit vector to the street's right at sample i.
func _side(s: Street, i: int) -> Vector2:
	var a := s.pts[maxi(i - 1, 0)]
	var b := s.pts[mini(i + 1, s.pts.size() - 1)]
	var t := (b - a).normalized()
	return Vector2(-t.y, t.x)


func _at(s: Street, i: int, off: float, dy: float) -> Vector3:
	var p := s.pts[i] + _side(s, i) * off
	return Vector3(p.x, s.ys[i] + 0.03 + dy, p.y)


## One band of the cross-section between rows i0 and i1, from (o0, dy0) to (o1, dy1).
func _strip(verts: PackedVector3Array, norms: PackedVector3Array, cols: PackedColorArray, uvs: PackedVector2Array, idx: PackedInt32Array,
		s: Street, i0: int, i1: int, o0: float, dy0: float, o1: float, dy1: float, col: Color, e: float) -> void:
	var a := _at(s, i0, o0, dy0)
	var b := _at(s, i0, o1, dy1)
	var c := _at(s, i1, o1, dy1)
	var d := _at(s, i1, o0, dy0)
	var nrm := (c - a).cross(b - d).normalized()
	if nrm.y < -0.01 or (absf(nrm.y) < 0.01 and false):
		nrm = -nrm
	var base := verts.size()
	verts.append_array([a, b, c, d])
	for k in 4:
		norms.append(nrm)
		cols.append(col)
		uvs.append(Vector2(e, 0.0))
	# wind so the face looks along its normal (Godot's front faces are clockwise)
	if (b - a).cross(c - a).dot(nrm) > 0.0:
		idx.append_array([base, base + 2, base + 1, base, base + 3, base + 2])
	else:
		idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])


func _dash(verts: PackedVector3Array, norms: PackedVector3Array, cols: PackedColorArray, uvs: PackedVector2Array, idx: PackedInt32Array,
		s: Street, i: int, col: Color) -> void:
	var hw := 0.035
	var a := _at(s, i, -hw, 0.006)
	var b := _at(s, i, hw, 0.006)
	var c := _at(s, i + 1, hw, 0.006)
	var d := _at(s, i + 1, -hw, 0.006)
	var nrm := Vector3.UP
	var base := verts.size()
	verts.append_array([a, b, c, d])
	for k in 4:
		norms.append(nrm)
		cols.append(col)
		uvs.append(Vector2.ZERO)
	if (b - a).cross(c - a).y > 0.0:
		idx.append_array([base, base + 2, base + 1, base, base + 3, base + 2])
	else:
		idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])


# ------------------------------------------------------------------ saving

func to_data() -> Array:
	var out := []
	for s in streets:
		var p := []
		for v in s.pts:
			p.append_array([snappedf(v.x, 0.01), snappedf(v.y, 0.01)])
		var y := []
		for v in s.ys:
			y.append(snappedf(v, 0.01))
		out.append({"k": s.kind, "p": p, "y": y})
	return out


func from_data(data: Array) -> void:
	clear()
	for d in data:
		if not d is Dictionary:
			continue
		var s := Street.new()
		s.id = _next_id
		_next_id += 1
		s.kind = str(d.get("k", "main"))
		if not KINDS.has(s.kind):
			s.kind = "main"
		var p: Array = d.get("p", [])
		var y: Array = d.get("y", [])
		for i in range(0, p.size() - 1, 2):
			s.pts.append(Vector2(float(p[i]), float(p[i + 1])))
		for v in y:
			s.ys.append(float(v))
		if s.pts.size() < 2 or s.ys.size() != s.pts.size():
			continue
		s.update_bounds()
		streets.append(s)
	for s in streets:
		_build(s)
