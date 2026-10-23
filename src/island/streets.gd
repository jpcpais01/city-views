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
# radius of the rounded kerb at street corners
const KERB_R := 1.1
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
# streets whose mesh needs remaking, a few per frame: id -> Street
var _pending := {}


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
		_build_later(o)
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
				_build_later(o)
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
		_reconform_near(s)
	for s in moved:
		_build(s)
		for o in _touching(s):
			if not o in moved:
				_build_later(o)


func _remove(s: Street) -> void:
	streets.erase(s)
	if _meshes.has(s.id):
		_meshes[s.id].queue_free()
		_meshes.erase(s.id)
	_laying.erase(s.id)
	_pending.erase(s.id)


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
		land.conform(o.pts, o.ys, o.w() + PAVE + 0.15, 0.0, true)


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
	var start := Time.get_ticks_usec()
	for id in _laying.keys():
		var before: float = _laying[id]
		_laying[id] += delta
		var s: Street = null
		for o in streets:
			if o.id == id:
				s = o
		if s == null or _laying[id] >= LAY_TIME:
			_laying.erase(id)
			if s:
				_build(s)
		# lay it out in a few steps rather than remaking it every frame
		elif int(before / 0.1) != int(_laying[id] / 0.1):
			_build(s)
	for id in _pending.keys():
		if Time.get_ticks_usec() - start > 3000:
			break
		var s: Street = _pending[id]
		_pending.erase(id)
		if s in streets:
			_build(s)


func _build_later(s: Street) -> void:
	_pending[s.id] = s


## Whether a point lies on another street's asphalt or pavement.
func _covered(p: Vector2, s: Street, margin: float, among: Array = streets) -> bool:
	for o in among:
		if o == s or not o.near_box(p, o.reach()):
			continue
		if o.closest(p).x < o.w() + margin:
			return true
	return false


class MeshBuf:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()

	## A flat four-sided piece facing the side of `hint`.
	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, e: float, hint: Vector3) -> void:
		var nrm := (c - a).cross(d - b)
		if nrm.length_squared() < 1e-10:
			return
		nrm = nrm.normalized()
		if nrm.dot(hint) < 0.0:
			nrm = -nrm
		var base := verts.size()
		verts.append_array([a, b, c, d])
		for k in 4:
			norms.append(nrm)
			cols.append(col)
			uvs.append(Vector2(e, 0.0))
		# Godot's front faces wind clockwise seen from the front
		if (b - a).cross(c - a).dot(nrm) > 0.0:
			idx.append_array([base, base + 2, base + 1, base, base + 3, base + 2])
		else:
			idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])

	func tri(a: Vector3, b: Vector3, c: Vector3, col: Color, e: float) -> void:
		var nrm := (b - a).cross(c - a)
		if nrm.length_squared() < 1e-10:
			return
		nrm = nrm.normalized()
		if nrm.y < 0.0:
			nrm = -nrm
		var base := verts.size()
		verts.append_array([a, b, c])
		for k in 3:
			norms.append(nrm)
			cols.append(col)
			uvs.append(Vector2(e, 0.0))
		if (b - a).cross(c - a).dot(nrm) > 0.0:
			idx.append_array([base, base + 2, base + 1])
		else:
			idx.append_array([base, base + 1, base + 2])


func _build(s: Street) -> void:
	var n := s.pts.size()
	var upto := float(n - 1)
	if _laying.has(s.id):
		var t: float = clampf(_laying[s.id] / LAY_TIME, 0.0, 1.0)
		upto = clampf((n - 1) * (1.0 - pow(1.0 - t, 3.0)), 1.0, n - 1)
	var w := s.w()
	var buf := MeshBuf.new()
	var asphalt := CityGen.ASPHALT.darkened(0.05) if s.kind == "main" else CityGen.ASPHALT
	# where junction corners take over this street's pavements, per side
	var cuts := {-1.0: PackedVector2Array(), 1.0: PackedVector2Array()}
	var near := _touching(s)
	var last_i := int(upto)
	# only samples close to a junction can run into another street: sample -> those streets
	var close := {}
	for o in near:
		for m in _meetings(s, o):
			_junction(s, m.x, o, m.y, cuts, buf, upto, asphalt)
			for i in range(maxi(0, int(m.x) - 12), mini(last_i, int(m.x) + 13) + 1):
				if not close.has(i):
					close[i] = []
				if not o in close[i]:
					close[i].append(o)
	var gaps := []
	for i in last_i + 1:
		if not close.has(i):
			gaps.append([false, false])
			continue
		var nrm := _side(s, i)
		gaps.append([_covered(s.pts[i] - nrm * (w + PAVE * 0.5), s, PAVE * 0.8, close[i]), _covered(s.pts[i] + nrm * (w + PAVE * 0.5), s, PAVE * 0.8, close[i])])
	# which rows to keep: every bend, slope change and pavement gap; straight even runs collapse
	var rows := {0.0: true, upto: true}
	var last := 0
	for i in range(1, last_i):
		var d0 := (s.pts[i] - s.pts[last]).normalized()
		var d1 := (s.pts[i + 1] - s.pts[i]).normalized()
		var bend := absf(d0.angle_to(d1)) > 0.03
		var grade_change := absf((s.ys[i + 1] - s.ys[i]) - (s.ys[i] - s.ys[i - 1])) > 0.004
		var gap_change: bool = gaps[i] != gaps[i - 1] or gaps[i] != gaps[i + 1]
		if bend or grade_change or gap_change or (i - last) * SAMPLE >= 3.0:
			rows[float(i)] = true
			last = i
	for side in cuts:
		for c in cuts[side]:
			for f in [c.x, c.y]:
				if f > 0.0 and f < upto:
					rows[f] = true
	var fs: Array = rows.keys()
	fs.sort()
	var pave := CityGen.SIDEWALK
	var kerb := CityGen.SIDEWALK.darkened(0.12)
	# each row's centre, sideways direction and height, worked out once
	var rp := PackedVector2Array()
	var rn := PackedVector2Array()
	var ry := PackedFloat32Array()
	for f in fs:
		rp.append(_ptf(s, f))
		rn.append(_sidef(s, f))
		ry.append(_yf(s, f) + 0.03)
	for r in fs.size() - 1:
		var f0: float = fs[r]
		var f1: float = fs[r + 1]
		if f1 - f0 < 0.01:
			continue
		var fm := (f0 + f1) * 0.5
		var p0 := rp[r]
		var p1 := rp[r + 1]
		var n0 := rn[r]
		var n1 := rn[r + 1]
		var y0 := ry[r]
		var y1 := ry[r + 1]
		# where a corner takes over, the asphalt reaches a little under it so no seam shows
		var wl := w + (0.2 if _in_cuts(cuts[-1.0], fm) else 0.0)
		var wr := w + (0.2 if _in_cuts(cuts[1.0], fm) else 0.0)
		_band(buf, p0, n0, y0, p1, n1, y1, -wl, 0.0, wr, 0.0, asphalt, MeshKit.ASPHALT, Vector3.UP)
		for side: float in [-1.0, 1.0]:
			if _in_cuts(cuts[side], fm):
				continue
			var gi := clampi(int(round(fm)), 0, last_i)
			if gaps[gi][0 if side < 0.0 else 1] and gaps[clampi(int(f0), 0, last_i)][0 if side < 0.0 else 1]:
				continue
			var out_dir := (n0 + n1) * 0.5 * side
			var out3 := Vector3(out_dir.x, 0.0, out_dir.y)
			# kerb face, pavement, and the pavement's outer edge down into the ground
			_band(buf, p0, n0, y0, p1, n1, y1, side * w, 0.0, side * w, CURB, kerb, 0.0, -out3)
			_band(buf, p0, n0, y0, p1, n1, y1, side * w, CURB, side * (w + PAVE), CURB, pave, MeshKit.SLABS, Vector3.UP)
			_band(buf, p0, n0, y0, p1, n1, y1, side * (w + PAVE), CURB, side * (w + PAVE), -SKIRT, kerb, 0.0, out3)
	if KINDS[s.kind].dash:
		var paint := Color(1.0, 0.97, 0.9)
		var along := 0.0
		for i in last_i:
			along += SAMPLE
			if fmod(along, 1.4) < SAMPLE and not (close.has(i) and (_covered(s.pts[i], s, 0.3, close[i]) or _covered(s.pts[i + 1], s, 0.3, close[i]))):
				_dash(buf, s, i, paint)
	var mi: MeshInstance3D = _meshes.get(s.id)
	if mi == null:
		mi = MeshInstance3D.new()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_meshes[s.id] = mi
	if buf.idx.is_empty():
		mi.mesh = null
		return
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = buf.verts
	arr[Mesh.ARRAY_NORMAL] = buf.norms
	arr[Mesh.ARRAY_COLOR] = buf.cols
	arr[Mesh.ARRAY_TEX_UV] = buf.uvs
	arr[Mesh.ARRAY_INDEX] = buf.idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	m.surface_set_material(0, material)
	mi.mesh = m


static func _in_cuts(list: PackedVector2Array, f: float) -> bool:
	for c in list:
		if f > c.x and f < c.y:
			return true
	return false


# ------------------------------------------------------------------ junctions

## Where two streets meet, as (index on s, index on o) pairs (fractional
## sample indices): ends that stop on the other street, and crossings.
func _meetings(s: Street, o: Street) -> PackedVector2Array:
	var out := PackedVector2Array()
	var spots := PackedVector2Array()
	var ns := s.pts.size()
	var no := o.pts.size()
	for e in [0, ns - 1]:
		var c: Vector3 = o.closest(s.pts[e])
		if c.x < o.w() + 0.3:
			out.append(Vector2(e, c.z))
			spots.append(s.pts[e])
	for e in [0, no - 1]:
		var c: Vector3 = s.closest(o.pts[e])
		if c.x < s.w() + 0.3 and not _near_any(spots, o.pts[e], 1.5):
			out.append(Vector2(c.z, e))
			spots.append(o.pts[e])
	for i in ns - 1:
		var a := s.pts[i]
		var b := s.pts[i + 1]
		if not o.near_box(a, 0.6) and not o.near_box(b, 0.6):
			continue
		for j in no - 1:
			var hit: Variant = Geometry2D.segment_intersects_segment(a, b, o.pts[j], o.pts[j + 1])
			if hit == null or _near_any(spots, hit, 1.5):
				continue
			var fs := i + a.distance_to(hit) / maxf(a.distance_to(b), 1e-6)
			var fo := j + o.pts[j].distance_to(hit) / maxf(o.pts[j].distance_to(o.pts[j + 1]), 1e-6)
			out.append(Vector2(fs, fo))
			spots.append(hit)
	return out


static func _near_any(list: PackedVector2Array, p: Vector2, r: float) -> bool:
	for q in list:
		if q.distance_to(p) < r:
			return true
	return false


## The directions a street leaves a junction at index f: [dir, +1 forward / -1 back].
func _arms(st: Street, f: float) -> Array:
	var out: Array = []
	var n := st.pts.size()
	var here := _ptf(st, f)
	if f < n - 2.0:
		out.append({"st": st, "f": f, "sgn": 1.0, "dir": (_ptf(st, minf(f + 3.0, n - 1)) - here).normalized()})
	if f > 1.0:
		out.append({"st": st, "f": f, "sgn": -1.0, "dir": (_ptf(st, maxf(f - 3.0, 0.0)) - here).normalized()})
	return out


## Rounded kerbs for the corners between the streets meeting at one junction.
## Each street leaves its pavement off where a corner takes over; the newer of
## the two streets builds the corner itself: the asphalt swept round into the
## corner, a curved kerb, pavement and its edge.
func _junction(s: Street, fs: float, o: Street, fo: float, cuts: Dictionary, buf: MeshBuf, upto: float, asphalt: Color) -> void:
	var arms := _arms(s, fs) + _arms(o, fo)
	if arms.size() < 2:
		return
	arms.sort_custom(func(p, q): return p.dir.angle() < q.dir.angle())
	var j := (_ptf(s, fs) + _ptf(o, fo)) * 0.5
	for k in arms.size():
		var A: Dictionary = arms[k]
		var B: Dictionary = arms[(k + 1) % arms.size()]
		if A.st == B.st:
			continue
		var a: Vector2 = A.dir
		var b: Vector2 = B.dir
		var th := wrapf(b.angle() - a.angle(), 0.0, TAU)
		if th < 0.45 or th > PI - 0.25:
			continue
		var wa: float = A.st.w()
		var wb: float = B.st.w()
		var na := a.rotated(PI * 0.5)
		var nb := b.rotated(-PI * 0.5)
		var det := -a.cross(b)
		if absf(det) < 1e-3:
			continue
		# how far along each arm the curve starts
		var d := nb * (wb + KERB_R) - na * (wa + KERB_R)
		var ta := b.cross(d) / det
		var tb := a.cross(d) / det
		if ta <= 0.0 or tb <= 0.0:
			continue
		var fa: float = A.f + A.sgn * ta / SAMPLE
		var fb: float = B.f + B.sgn * tb / SAMPLE
		var side_a: float = A.sgn
		var side_b: float = -B.sgn
		if A.st == s:
			cuts[side_a].append(Vector2(minf(A.f, fa), maxf(A.f, fa)))
		if B.st == s:
			cuts[side_b].append(Vector2(minf(B.f, fb), maxf(B.f, fb)))
		var other: Street = B.st if A.st == s else A.st
		if s.id < other.id:
			continue
		var na_st: Street = A.st
		var nb_st: Street = B.st
		if fa < 0.0 or fb < 0.0 or fa > na_st.pts.size() - 1 or fb > nb_st.pts.size() - 1:
			continue
		if (na_st == s and fa > upto) or (nb_st == s and fb > upto):
			continue
		var pa := _ptf(na_st, fa) + _sidef(na_st, fa) * side_a * wa
		var pb := _ptf(nb_st, fb) + _sidef(nb_st, fb) * side_b * wb
		var dc := nb * wb - na * wa
		var c := j + na * wa + a * (b.cross(dc) / det)
		var ya := _yf(na_st, fa) + 0.03
		var yb := _yf(nb_st, fb) + 0.03
		_corner(buf, pa, c, pb, ya, yb, asphalt)


func _corner(buf: MeshBuf, pa: Vector2, c: Vector2, pb: Vector2, ya: float, yb: float, asphalt: Color) -> void:
	const K := 6
	var pave := CityGen.SIDEWALK
	var kerb := CityGen.SIDEWALK.darkened(0.12)
	var cy := (ya + yb) * 0.5
	var c3 := Vector3(c.x, cy, c.y)
	var prev_p := Vector3.ZERO
	var prev_o := Vector3.ZERO
	var prev_n := Vector3.ZERO
	for k in K + 1:
		var t := float(k) / K
		var p := pa * (1.0 - t) * (1.0 - t) + c * 2.0 * t * (1.0 - t) + pb * t * t
		var tan := (c - pa) * 2.0 * (1.0 - t) + (pb - c) * 2.0 * t
		var nrm := tan.normalized().rotated(-PI * 0.5)
		var y := lerpf(ya, yb, t)
		var p3 := Vector3(p.x, y, p.y)
		var o := p + nrm * PAVE
		var o3 := Vector3(o.x, y, o.y)
		var n3 := Vector3(nrm.x, 0.0, nrm.y)
		if k > 0:
			buf.tri(c3, prev_p, p3, asphalt, MeshKit.ASPHALT)
			buf.quad(prev_p, p3, p3 + Vector3.UP * CURB, prev_p + Vector3.UP * CURB, kerb, 0.0, -(n3 + prev_n))
			buf.quad(prev_p + Vector3.UP * CURB, p3 + Vector3.UP * CURB, o3 + Vector3.UP * CURB, prev_o + Vector3.UP * CURB, pave, MeshKit.SLABS, Vector3.UP)
			buf.quad(prev_o + Vector3.UP * CURB, o3 + Vector3.UP * CURB, o3 + Vector3.DOWN * SKIRT, prev_o + Vector3.DOWN * SKIRT, kerb, 0.0, n3 + prev_n)
		prev_p = p3
		prev_o = o3
		prev_n = n3


# ------------------------------------------------------------------ sampling

func _ptf(s: Street, f: float) -> Vector2:
	var i := clampi(int(f), 0, s.pts.size() - 2)
	return s.pts[i].lerp(s.pts[i + 1], clampf(f - i, 0.0, 1.0))


func _yf(s: Street, f: float) -> float:
	var i := clampi(int(f), 0, s.pts.size() - 2)
	return lerpf(s.ys[i], s.ys[i + 1], clampf(f - i, 0.0, 1.0))


## Unit vector to the street's right at sample i.
func _side(s: Street, i: int) -> Vector2:
	var a := s.pts[maxi(i - 1, 0)]
	var b := s.pts[mini(i + 1, s.pts.size() - 1)]
	var t := (b - a).normalized()
	return Vector2(-t.y, t.x)


func _sidef(s: Street, f: float) -> Vector2:
	var i := clampi(int(f), 0, s.pts.size() - 2)
	return _side(s, i).lerp(_side(s, i + 1), clampf(f - i, 0.0, 1.0)).normalized()


func _atf(s: Street, f: float, off: float, dy: float) -> Vector3:
	var p := _ptf(s, f) + _sidef(s, f) * off
	return Vector3(p.x, _yf(s, f) + 0.03 + dy, p.y)


## One band of the cross-section between two rows, from (o0, dy0) to (o1, dy1).
static func _band(buf: MeshBuf, p0: Vector2, n0: Vector2, y0: float, p1: Vector2, n1: Vector2, y1: float,
		o0: float, dy0: float, o1: float, dy1: float, col: Color, e: float, hint: Vector3) -> void:
	var a := p0 + n0 * o0
	var b := p0 + n0 * o1
	var c := p1 + n1 * o1
	var d := p1 + n1 * o0
	buf.quad(Vector3(a.x, y0 + dy0, a.y), Vector3(b.x, y0 + dy1, b.y), Vector3(c.x, y1 + dy1, c.y), Vector3(d.x, y1 + dy0, d.y), col, e, hint)


func _dash(buf: MeshBuf, s: Street, i: int, col: Color) -> void:
	var hw := 0.035
	buf.quad(_atf(s, i, -hw, 0.006), _atf(s, i, hw, 0.006), _atf(s, i + 1, hw, 0.006), _atf(s, i + 1, -hw, 0.006), col, 0.0, Vector3.UP)


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
