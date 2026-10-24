class_name Streets
extends Node3D
## Streets on the new island. Each street is a smooth centre line with a graded
## height profile: it follows the land but evens out bumps and keeps slopes
## walkable, and the ground is cut and filled to meet it. Built as one mesh per
## street with asphalt, kerbs, paved pavements and centre dashes. Where streets
## meet, their asphalt stops short and one junction piece joins them, with
## rounded kerbs at the corners.

signal changed
signal added(s: Street)
signal removed(s: Street)

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
var _links := {}
var _links_dirty := true
var _junctions: Array = []
var _junctions_dirty := true
## this builder's mark on the streets it makes, so keys never clash in co-op
static var tag := ""
# streets being laid out along their length: id -> seconds since placed
var _laying := {}
const LAY_TIME := 0.8
# streets whose mesh needs remaking, a few per frame: id -> Street
var _pending := {}


class Street:
	var id := 0
	## stable across saves and between co-op builders (ids are only this session's)
	var key := ""
	var kind := "main"
	var pts := PackedVector2Array()
	var ys := PackedFloat32Array()
	var lo := Vector2.ZERO
	var hi := Vector2.ZERO
	# where junction corners take over the pavements: side -> (from, to) sample ranges
	var cuts := {}

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
	var s := _new_street()
	s.kind = kind
	s.pts = pts
	s.update_bounds()
	_grade(s)
	streets.append(s)
	_junctions_dirty = true
	land.conform(s.pts, s.ys, s.w() + PAVE + 0.15, 2.6)
	_reconform_near(s)
	_conform_junctions(s)
	_laying[s.id] = 0.0
	_build(s)
	for o in _touching(s):
		_build_later(o)
	added.emit(s)
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
			var ns := _new_street()
			ns.kind = s.kind
			ns.pts = pc[0]
			ns.ys = pc[1]
			ns.update_bounds()
			streets.append(ns)
			_junctions_dirty = true
			_build(ns)
			added.emit(ns)
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
	_junctions_dirty = true
	for s in moved:
		_reconform_near(s)
		_conform_junctions(s)
	for s in moved:
		_build(s)
		for o in _touching(s):
			if not o in moved:
				_build_later(o)


func _remove(s: Street) -> void:
	streets.erase(s)
	_junctions_dirty = true
	removed.emit(s)
	if _meshes.has(s.id):
		_meshes[s.id].queue_free()
		_meshes.erase(s.id)
	_laying.erase(s.id)
	_pending.erase(s.id)


func _init() -> void:
	changed.connect(func(): _links_dirty = true)
	removed.connect(func(_s): _links_dirty = true)
	added.connect(func(_s): _links_dirty = true)


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
		# a grid step past the pavement too, so the ground can't rise over its edge in between
		land.conform(o.pts, o.ys, o.w() + PAVE + 0.15 + Land.STEP * 0.75, 0.0, true)


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
				# the junctions it makes can now take over the other streets' ends
				for o in _touching(s):
					_build_later(o)
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


## Finishes laying and remaking every street now (tests, loading).
func flush() -> void:
	if not _laying.is_empty():
		for id in _laying:
			var s := by_id(id)
			if s:
				for o in _touching(s) + [s]:
					_pending[o.id] = o
		_laying.clear()
	for id in _pending.keys():
		_build(_pending[id])
	_pending.clear()
	for st in streets:
		if st.cuts.is_empty():
			_build(st)


## Whether the street is still being laid out or waiting for its mesh.
func is_settling(s: Street) -> bool:
	return _laying.has(s.id) or _pending.has(s.id)


func _build_later(s: Street) -> void:
	_pending[s.id] = s


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

	## `level` shades it as if flat, so a fan of slightly tilted pieces reads as one surface.
	func tri(a: Vector3, b: Vector3, c: Vector3, col: Color, e: float, level := false) -> void:
		var nrm := (b - a).cross(c - a)
		if nrm.length_squared() < 1e-10:
			return
		nrm = nrm.normalized()
		if nrm.y < 0.0:
			nrm = -nrm
		var face := nrm
		if level:
			nrm = Vector3.UP
		var base := verts.size()
		verts.append_array([a, b, c])
		for k in 3:
			norms.append(nrm)
			cols.append(col)
			uvs.append(Vector2(e, 0.0))
		if (b - a).cross(c - a).dot(face) > 0.0:
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
	var asphalt := Palette.ASPHALT.darkened(0.05) if s.kind == "main" else Palette.ASPHALT
	# where junction corners take over this street's pavements, per side,
	# and where a junction's own asphalt takes over from this street's
	var cuts := {-1.0: PackedVector2Array(), 1.0: PackedVector2Array()}
	var skip := PackedVector2Array()
	var last_i := int(upto)
	if not _laying.has(s.id):
		for jn in junctions():
			var mine := false
			var settled := true
			for arm in jn.arms:
				mine = mine or arm.st == s
				settled = settled and not _laying.has(arm.st.id)
			if not mine or not settled:
				continue
			for arm in jn.arms:
				if arm.st != s:
					continue
				skip.append(Vector2(minf(arm.f, arm.f_end), maxf(arm.f, arm.f_end)))
				for q in 2:
					if arm.cut[q] <= 0.0:
						continue
					var fc: float = arm.f + arm.sgn * arm.cut[q] / SAMPLE
					cuts[arm.sgn * (-1.0 if q == 0 else 1.0)].append(Vector2(minf(arm.f, fc), maxf(arm.f, fc)))
			if jn.owner == s.id:
				_build_junction(jn, buf)
	# which rows to keep: every bend, slope change and pavement gap; straight even runs collapse
	var rows := {0.0: true, upto: true}
	var last := 0
	for i in range(1, last_i):
		var d0 := (s.pts[i] - s.pts[last]).normalized()
		var d1 := (s.pts[i + 1] - s.pts[i]).normalized()
		var bend := absf(d0.angle_to(d1)) > 0.08
		var grade_change := absf((s.ys[i + 1] - s.ys[i]) - (s.ys[i] - s.ys[i - 1])) > 0.007
		if bend or grade_change or (i - last) * SAMPLE >= 3.0:
			rows[float(i)] = true
			last = i
	for list in [cuts[-1.0], cuts[1.0], skip]:
		for c in list:
			for f in [c.x, c.y]:
				if f > 0.0 and f < upto:
					rows[f] = true
	if upto >= n - 1:
		s.cuts = cuts
	var fs: Array = rows.keys()
	fs.sort()
	var pave := Palette.SIDEWALK
	var kerb := Palette.SIDEWALK.darkened(0.12)
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
		if not _in_cuts(skip, fm):
			_band(buf, p0, n0, y0, p1, n1, y1, -w, 0.0, w, 0.0, asphalt, MeshKit.ASPHALT, Vector3.UP)
		for side: float in [-1.0, 1.0]:
			if _in_cuts(cuts[side], fm):
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
			if fmod(along, 1.4) < SAMPLE and not _in_cuts(skip, i + 0.5) and not _in_cuts(skip, i - 0.5) and not _in_cuts(skip, i + 1.5):
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


## Every place where streets meet, worked out once after streets change. Each
## is one flat-topped piece: the arms' asphalt stops a little short of the
## middle and the junction fills in between, its corners rounded with kerbs
## and pavement, so streets meeting at any angle join without seams or holes.
## {at, y, arms: [{st, f, sgn, dir, back}], edge: [Vector3], corners: [[Vector3]], owner}
func junctions() -> Array:
	if _junctions_dirty:
		_junctions = _find_junctions()
		_junctions_dirty = false
	return _junctions


func _find_junctions() -> Array:
	var found: Array = []
	for i in streets.size():
		for k in range(i + 1, streets.size()):
			var a: Street = streets[i]
			var b: Street = streets[k]
			if not _boxes_overlap(a, b):
				continue
			for m in _meetings(a, b):
				var at := (_ptf(a, m.x) + _ptf(b, m.y)) * 0.5
				var jn: Dictionary = {}
				for q in found:
					if q.at.distance_to(at) < 3.0:
						jn = q
						break
				if jn.is_empty():
					jn = {"at": at, "meets": []}
					found.append(jn)
				jn.meets.append([a, m.x, b, m.y])
	for jn in found:
		_shape_junction(jn)
	return found.filter(func(q): return q.arms.size() >= 2)


## Arms, corners and the outline of one junction.
func _shape_junction(jn: Dictionary) -> void:
	# the same street meeting the junction twice close together counts once
	var spots := {}
	var at := Vector2.ZERO
	for m in jn.meets:
		at += (_ptf(m[0], m[1]) + _ptf(m[2], m[3])) * 0.5
		for e in [[m[0], m[1]], [m[2], m[3]]]:
			var st: Street = e[0]
			var list: Array = spots.get(st, [])
			var merged := false
			for qi in list.size():
				var q: Vector2 = list[qi]
				if not merged and absf(q.x - e[1]) < 8.0:
					list[qi] = Vector2((q.x * q.y + e[1]) / (q.y + 1.0), q.y + 1.0)
					merged = true
			if not merged:
				list.append(Vector2(e[1], 1.0))
			spots[st] = list
	at /= jn.meets.size()
	var arms: Array = []
	var y := 0.0
	var ny := 0
	var owner := 0
	for st: Street in spots:
		owner = maxi(owner, st.id)
		for q: Vector2 in spots[st]:
			y += _yf(st, q.x)
			ny += 1
			arms.append_array(_arms(st, q.x))
	arms.sort_custom(func(p, q): return p.dir.angle() < q.dir.angle())
	jn.at = at
	jn.y = y / maxf(ny, 1.0) + 0.03
	jn.arms = arms
	jn.owner = owner
	jn.edge = []
	jn.corners = []
	if arms.size() < 2:
		return
	for arm in arms:
		arm.cut = [0.0, 0.0]  # pavement taken over: toward the previous arm, toward the next
	# the curve between each arm and the next, going round
	var curves: Array = []
	for k in arms.size():
		var A: Dictionary = arms[k]
		var B: Dictionary = arms[(k + 1) % arms.size()]
		curves.append(_corner_curve(at, A, B))
	# each arm's asphalt stops where its farther corner begins
	for arm in arms:
		arm.back = maxf(maxf(arm.cut[0], arm.cut[1]), 0.3)
		arm.f_end = clampf(arm.f + arm.sgn * arm.back / SAMPLE, 0.0, arm.st.pts.size() - 1.0)
	# the outline, going round: each arm's end, then the way round to the next
	for k in arms.size():
		var A: Dictionary = arms[k]
		var B: Dictionary = arms[(k + 1) % arms.size()]
		var sa: float = A.sgn
		var sb: float = -B.sgn
		jn.edge.append(_kerb_pt(A.st, A.f_end, -sa))
		jn.edge.append(_kerb_pt(A.st, A.f_end, sa))
		var c: Dictionary = curves[k]
		if c.same:
			# one street running on through: follow its kerb
			_kerb_run(jn.edge, A.st, A.f_end, B.f_end, sa)
			continue
		_kerb_run(jn.edge, A.st, A.f_end, c.fa, sa)
		jn.edge.append_array(c.pts)
		jn.corners.append(c.pts)
		_kerb_run(jn.edge, B.st, c.fb, B.f_end, sb)


## The rounded kerb from arm A round to the next arm B, and how far along each
## arm it starts. Sharp corners get a tighter round, and where two arms are
## almost in line (or the gap is the outside of a bend) the kerb swings round
## the junction's middle instead.
func _corner_curve(j: Vector2, A: Dictionary, B: Dictionary) -> Dictionary:
	if A.st == B.st:
		return {"same": true}
	var a: Vector2 = A.dir
	var b: Vector2 = B.dir
	var th := wrapf(b.angle() - a.angle(), 0.0, TAU)
	var wa: float = A.st.w()
	var wb: float = B.st.w()
	var sa: float = A.sgn
	var sb: float = -B.sgn
	var na := a.rotated(PI * 0.5)
	var nb := b.rotated(-PI * 0.5)
	var pts: Array = []
	var ta := 0.0
	var tb := 0.0
	if th < PI - 0.12:
		var r := KERB_R * clampf(th / 1.2, 0.35, 1.0)
		var det := -a.cross(b)
		var d := nb * (wb + r) - na * (wa + r)
		ta = maxf(b.cross(d) / det, 0.0)
		tb = maxf(a.cross(d) / det, 0.0)
	var fa := clampf(A.f + A.sgn * ta / SAMPLE, 0.0, A.st.pts.size() - 1.0)
	var fb := clampf(B.f + B.sgn * tb / SAMPLE, 0.0, B.st.pts.size() - 1.0)
	A.cut[1] = absf(fa - A.f) * SAMPLE
	B.cut[0] = absf(fb - B.f) * SAMPLE
	var pa := _kerb_pt(A.st, fa, sa)
	var pb := _kerb_pt(B.st, fb, sb)
	var pa2 := Vector2(pa.x, pa.z)
	var pb2 := Vector2(pb.x, pb.z)
	if th < PI - 0.12:
		# a curve between the two kerbs, bending through where they would meet
		var det := -a.cross(b)
		var dc := nb * wb - na * wa
		var c := j + na * wa + a * (b.cross(dc) / det)
		var steps := 6 if th > 0.9 else 4
		for k in steps + 1:
			var t := float(k) / steps
			var p := pa2 * (1.0 - t) * (1.0 - t) + c * 2.0 * t * (1.0 - t) + pb2 * t * t
			pts.append(Vector3(p.x, lerpf(pa.y, pb.y, t), p.y))
	else:
		# round the outside of the junction's middle
		var r0 := pa2.distance_to(j)
		var r1 := pb2.distance_to(j)
		var a0 := (pa2 - j).angle()
		var sweep := wrapf((pb2 - j).angle() - a0, 0.0, TAU)
		var steps := clampi(ceili(sweep / 0.45), 1, 10)
		for k in steps + 1:
			var t := float(k) / steps
			var p := j + Vector2.from_angle(a0 + sweep * t) * lerpf(r0, r1, t)
			pts.append(Vector3(p.x, lerpf(pa.y, pb.y, t), p.y))
	return {"same": false, "pts": pts, "fa": fa, "fb": fb}


## A point on a street's kerb line (asphalt height) at index f on `side`.
func _kerb_pt(st: Street, f: float, side: float) -> Vector3:
	var p := _ptf(st, f) + _sidef(st, f) * side * st.w()
	return Vector3(p.x, _yf(st, f) + 0.03, p.y)


## Kerb points strictly between f0 and f1 (either order), added to `out` in that order.
func _kerb_run(out: Array, st: Street, f0: float, f1: float, side: float) -> void:
	var dirn := signf(f1 - f0)
	if dirn == 0.0:
		return
	var f := floorf(f0) + 1.0 if dirn > 0.0 else ceilf(f0) - 1.0
	while (f1 - f) * dirn > 0.05:
		out.append(_kerb_pt(st, f, side))
		f += dirn * 2.0


## Lowers the ground under the junctions a street is part of, so none shows
## through where the arms' slopes differ.
func _conform_junctions(s: Street) -> void:
	for jn in junctions():
		var mine := false
		for arm in jn.arms:
			mine = mine or arm.st == s
		if not mine:
			continue
		var j3 := Vector2(jn.at.x, jn.at.y)
		for arm in jn.arms:
			var e := _ptf(arm.st, arm.f_end)
			land.conform(PackedVector2Array([j3, e]), PackedFloat32Array([jn.y - 0.03, _yf(arm.st, arm.f_end)]), arm.st.w() + 0.2, 0.0, true)
		for c in jn.corners:
			var cp := PackedVector2Array()
			var cy := PackedFloat32Array()
			for p: Vector3 in c:
				cp.append(Vector2(p.x, p.z))
				cy.append(p.y - 0.03)
			land.conform(cp, cy, PAVE + 0.2 + Land.STEP * 0.75, 0.0, true)


## Builds a junction's asphalt and corner kerbs into a street's mesh.
func _build_junction(jn: Dictionary, buf: MeshBuf) -> void:
	var main := false
	for arm in jn.arms:
		main = main or arm.st.kind == "main"
	var asphalt := Palette.ASPHALT.darkened(0.05) if main else Palette.ASPHALT
	var c3 := Vector3(jn.at.x, jn.y, jn.at.y)
	var edge: Array = jn.edge
	for k in edge.size():
		buf.tri(c3, edge[k], edge[(k + 1) % edge.size()], asphalt, MeshKit.ASPHALT, true)
	var pave := Palette.SIDEWALK
	var kerb := Palette.SIDEWALK.darkened(0.12)
	for c: Array in jn.corners:
		var prev_p := Vector3.ZERO
		var prev_o := Vector3.ZERO
		var prev_n := Vector3.ZERO
		for k in c.size():
			var p3: Vector3 = c[k]
			var tan: Vector3 = c[mini(k + 1, c.size() - 1)] - c[maxi(k - 1, 0)]
			var n3 := Vector3(-tan.z, 0.0, tan.x).normalized()
			if n3.dot(p3 - c3) < 0.0:
				n3 = -n3
			var o3 := p3 + n3 * PAVE
			if k > 0:
				buf.quad(prev_p, p3, p3 + Vector3.UP * CURB, prev_p + Vector3.UP * CURB, kerb, 0.0, -(n3 + prev_n))
				buf.quad(prev_p + Vector3.UP * CURB, p3 + Vector3.UP * CURB, o3 + Vector3.UP * CURB, prev_o + Vector3.UP * CURB, pave, MeshKit.SLABS, Vector3.UP)
				buf.quad(prev_o + Vector3.UP * CURB, o3 + Vector3.UP * CURB, o3 + Vector3.DOWN * SKIRT, prev_o + Vector3.DOWN * SKIRT, kerb, 0.0, n3 + prev_n)
			prev_p = p3
			prev_o = o3
			prev_n = n3


# ------------------------------------------------------------------ sampling

## Where streets meet, for things that travel along them: street id to a list
## of [place along it, the other street, place along that one].
func links() -> Dictionary:
	if _links_dirty:
		_links.clear()
		for s in streets:
			_links[s.id] = []
		for i in streets.size():
			for j in range(i + 1, streets.size()):
				var a: Street = streets[i]
				var b: Street = streets[j]
				if not _boxes_overlap(a, b):
					continue
				for m in _meetings(a, b):
					_links[a.id].append([m.x, b, m.y])
					_links[b.id].append([m.y, a, m.x])
		_links_dirty = false
	return _links


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
		out.append(street_data(s))
	return out


func street_data(s: Street) -> Dictionary:
	var p := []
	for v in s.pts:
		p.append_array([snappedf(v.x, 0.01), snappedf(v.y, 0.01)])
	var y := []
	for v in s.ys:
		y.append(snappedf(v, 0.01))
	return {"id": s.key, "k": s.kind, "p": p, "y": y}


func from_data(data: Array) -> void:
	clear()
	for d in data:
		var s := _from_dict(d)
		if s:
			streets.append(s)
			_junctions_dirty = true
	for s in streets:
		_build(s)
	for s in streets:
		added.emit(s)


## Lays one street exactly as saved (from another builder, or an undo).
func add_data(d: Dictionary) -> Street:
	var s := _from_dict(d)
	if s == null:
		return null
	streets.append(s)
	_junctions_dirty = true
	_build(s)
	for o in _touching(s):
		_build_later(o)
	added.emit(s)
	changed.emit()
	return s


func remove_street(s: Street) -> void:
	var touching := _touching(s)
	_remove(s)
	for o in touching:
		if o in streets:
			_build_later(o)
	changed.emit()


func by_id(id: int) -> Street:
	for s: Street in streets:
		if s.id == id:
			return s
	return null


func by_key(k: String) -> Street:
	for s in streets:
		if s.key == k:
			return s
	return null


func _new_street() -> Street:
	var s := Street.new()
	s.id = _next_id
	_next_id += 1
	if tag == "":
		tag = "%04x" % (randi() % 65536)
	s.key = "%s%d_%d" % [tag, Time.get_ticks_msec() % 100000, s.id]
	return s


func _from_dict(d: Variant) -> Street:
	if not d is Dictionary:
		return null
	var s := _new_street()
	if str(d.get("id", "")) != "":
		s.key = str(d.id)
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
		return null
	s.update_bounds()
	return s
