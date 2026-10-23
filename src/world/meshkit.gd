class_name MeshKit
extends RefCounted
## Tiny procedural mesh builder. Every primitive is written with vertex colours
## and a UV channel used as flags by the city shader:
##   UV.x = 0 plain surface, 1 = window (lit randomly at night), 2 = lamp (always lit at night),
##   3 = water/glass highlight.  UV.y = random value per window.

var verts := PackedVector3Array()
var norms := PackedVector3Array()
var cols := PackedColorArray()
var uvs := PackedVector2Array()
var xf := Transform3D.IDENTITY
var _stack: Array[Transform3D] = []
var rng := RandomNumberGenerator.new()

static var _ico_v: PackedVector3Array
static var _ico_i: PackedInt32Array


func _init(seed_value: int = 0) -> void:
	rng.seed = seed_value


func push(t: Transform3D) -> void:
	_stack.push_back(xf)
	xf = xf * t


func push_at(pos: Vector3, yaw: float = 0.0, scl: Vector3 = Vector3.ONE) -> void:
	push(Transform3D(Basis(Vector3.UP, yaw).scaled(scl), pos))


func pop() -> void:
	xf = _stack.pop_back()


func is_empty() -> bool:
	return verts.is_empty()


func _v(p: Vector3, nn: Vector3, col: Color, e: float, r: float) -> void:
	verts.push_back(xf * p)
	norms.push_back((xf.basis * nn).normalized())
	cols.push_back(col)
	uvs.push_back(Vector2(e, r))


## Triangle with per-vertex normals. `face` is the outward direction used to fix winding.
func tri_n(a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, face: Vector3, col: Color, e := 0.0, r := 0.0) -> void:
	# Godot treats clockwise triangles as front faces: cross(b-a, c-a) must point away from `face`.
	if (b - a).cross(c - a).dot(face) > 0.0:
		var t := b; b = c; c = t
		var tn := nb; nb = nc; nc = tn
	_v(a, na, col, e, r)
	_v(b, nb, col, e, r)
	_v(c, nc, col, e, r)


func tri(a: Vector3, b: Vector3, c: Vector3, col: Color, e := 0.0, r := 0.0, face := Vector3.ZERO) -> void:
	var nrm := (b - a).cross(c - a).normalized()
	if face != Vector3.ZERO and nrm.dot(face) < 0.0:
		nrm = -nrm
	elif face == Vector3.ZERO:
		nrm = -nrm  # assume caller listed vertices counter-clockwise seen from outside
	tri_n(a, b, c, nrm, nrm, nrm, nrm, col, e, r)


## Quad a-b-c-d (any consistent order around the perimeter) facing `face`.
func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, face: Vector3, col: Color, e := 0.0, r := 0.0) -> void:
	var nrm := face.normalized()
	tri_n(a, b, c, nrm, nrm, nrm, nrm, col, e, r)
	tri_n(a, c, d, nrm, nrm, nrm, nrm, col, e, r)


## Quad with explicit, interpolated normals (soft shading).
func quad_n(a: Vector3, b: Vector3, c: Vector3, d: Vector3, na: Vector3, nb: Vector3, nc: Vector3, nd: Vector3, col: Color, e := 0.0, r := 0.0) -> void:
	var face := (na + nb + nc + nd).normalized()
	tri_n(a, b, c, na, nb, nc, face, col, e, r)
	tri_n(a, c, d, na, nc, nd, face, col, e, r)


## Axis-aligned flat box (no bottom by default).
func box(center: Vector3, size: Vector3, col: Color, top_col: Variant = null, bottom := false, e := 0.0) -> void:
	var h := size * 0.5
	var tc: Color = top_col if top_col != null else col
	var c := center
	var p000 := c + Vector3(-h.x, -h.y, -h.z)
	var p100 := c + Vector3(h.x, -h.y, -h.z)
	var p010 := c + Vector3(-h.x, h.y, -h.z)
	var p110 := c + Vector3(h.x, h.y, -h.z)
	var p001 := c + Vector3(-h.x, -h.y, h.z)
	var p101 := c + Vector3(h.x, -h.y, h.z)
	var p011 := c + Vector3(-h.x, h.y, h.z)
	var p111 := c + Vector3(h.x, h.y, h.z)
	quad(p010, p110, p111, p011, Vector3.UP, tc, e)
	quad(p001, p101, p111, p011, Vector3.BACK, col, e)
	quad(p000, p100, p110, p010, Vector3.FORWARD, col, e)
	quad(p100, p101, p111, p110, Vector3.RIGHT, col, e)
	quad(p000, p001, p011, p010, Vector3.LEFT, col, e)
	if bottom:
		quad(p000, p100, p101, p001, Vector3.DOWN, col, e)


## Rounded (chamfered, smooth-shaded) box: the signature toy look.
func rbox(center: Vector3, size: Vector3, radius: float, col: Color, top_col: Variant = null, bottom := false, e := 0.0) -> void:
	var h := size * 0.5
	var r: float = min(radius, min(h.x, min(h.y, h.z)) * 0.98)
	if r <= 0.001:
		box(center, size, col, top_col, bottom, e)
		return
	var inner := h - Vector3(r, r, r)
	var tc: Color = top_col if top_col != null else col
	for axis in 3:
		for s in [-1.0, 1.0]:
			if axis == 1 and s < 0.0 and not bottom:
				continue
			var b := (axis + 1) % 3
			var cax := (axis + 2) % 3
			var cb := [-h[b], -inner[b], inner[b], h[b]]
			var cc := [-h[cax], -inner[cax], inner[cax], h[cax]]
			var face := Vector3.ZERO
			face[axis] = s
			var fcol: Color = tc if (axis == 1 and s > 0.0) else col
			for i in 3:
				for j in 3:
					var pts: Array[Vector3] = []
					var nrs: Array[Vector3] = []
					for k in 4:
						var ii: int = i + (1 if k == 1 or k == 2 else 0)
						var jj: int = j + (1 if k >= 2 else 0)
						var p := Vector3.ZERO
						p[axis] = s * h[axis]
						p[b] = cb[ii]
						p[cax] = cc[jj]
						var q := p.clamp(-inner, inner)
						var nn := (p - q).normalized()
						pts.append(center + q + nn * r)
						nrs.append(nn)
					var nf := (nrs[0] + nrs[1] + nrs[2] + nrs[3]).normalized()
					tri_n(pts[0], pts[1], pts[2], nrs[0], nrs[1], nrs[2], nf, fcol, e)
					tri_n(pts[0], pts[2], pts[3], nrs[0], nrs[2], nrs[3], nf, fcol, e)


## Vertical cylinder standing on `base`.
func cylinder(base: Vector3, radius: float, height: float, sides: int, col: Color, cap := true, top_col: Variant = null, r_top := -1.0, e := 0.0) -> void:
	var rt: float = radius if r_top < 0.0 else r_top
	var tc: Color = top_col if top_col != null else col
	var slope := (radius - rt) / maxf(height, 0.001)
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var n0 := (d0 + Vector3(0, slope, 0)).normalized()
		var n1 := (d1 + Vector3(0, slope, 0)).normalized()
		quad_n(base + d0 * radius, base + d1 * radius, base + d1 * rt + Vector3(0, height, 0), base + d0 * rt + Vector3(0, height, 0), n0, n1, n1, n0, col, e)
		if cap and rt > 0.001:
			var top := base + Vector3(0, height, 0)
			tri_n(top, top + d0 * rt, top + d1 * rt, Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP, tc, e)


func cone(base: Vector3, radius: float, height: float, sides: int, col: Color, e := 0.0) -> void:
	var tip := base + Vector3(0, height, 0)
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var k := radius / height
		var n0 := (d0 + Vector3(0, k, 0)).normalized()
		var n1 := (d1 + Vector3(0, k, 0)).normalized()
		var nt := (n0 + n1).normalized()
		tri_n(base + d0 * radius, base + d1 * radius, tip, n0, n1, nt, nt, col, e)


static func _build_ico() -> void:
	var t := (1.0 + sqrt(5.0)) / 2.0
	var base_v: Array[Vector3] = [
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	var faces := [0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11, 1, 5, 9, 5, 11, 4, 11, 10, 2, 10, 7, 6, 7, 1, 8,
		3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9, 4, 9, 5, 2, 4, 11, 6, 2, 10, 8, 6, 7, 9, 8, 1]
	var vs: Array[Vector3] = []
	for p in base_v:
		vs.append(p.normalized())
	var cache := {}
	var out := PackedInt32Array()
	var mid := func(a: int, b: int) -> int:
		var key := Vector2i(mini(a, b), maxi(a, b))
		if cache.has(key):
			return cache[key]
		vs.append(((vs[a] + vs[b]) * 0.5).normalized())
		cache[key] = vs.size() - 1
		return vs.size() - 1
	for f in range(0, faces.size(), 3):
		var a: int = faces[f]
		var b: int = faces[f + 1]
		var c: int = faces[f + 2]
		var ab: int = mid.call(a, b)
		var bc: int = mid.call(b, c)
		var ca: int = mid.call(c, a)
		out.append_array([a, ab, ca, b, bc, ab, c, ca, bc, ab, bc, ca])
	_ico_v = PackedVector3Array(vs)
	_ico_i = out


## Soft round blob (tree canopies, bushes, clouds).
func blob(center: Vector3, radius: Vector3, col: Color, jitter := 0.0, e := 0.0) -> void:
	if _ico_v.is_empty():
		_build_ico()
	var pts := PackedVector3Array()
	pts.resize(_ico_v.size())
	for i in _ico_v.size():
		var u := _ico_v[i]
		var k := 1.0
		if jitter > 0.0:
			k += sin(u.x * 7.1 + u.z * 5.3 + center.x) * jitter + cos(u.y * 6.7 + center.z) * jitter * 0.5
		pts[i] = center + u * radius * k
	for f in range(0, _ico_i.size(), 3):
		var ia := _ico_i[f]
		var ib := _ico_i[f + 1]
		var ic := _ico_i[f + 2]
		var na := (_ico_v[ia] / radius).normalized()
		var nb := (_ico_v[ib] / radius).normalized()
		var nc := (_ico_v[ic] / radius).normalized()
		var shade := 0.88 + 0.12 * clampf((_ico_v[ia].y + 1.0) * 0.5, 0.0, 1.0)
		var cc := Color(col.r * shade, col.g * shade, col.b * shade)
		tri_n(pts[ia], pts[ib], pts[ic], na, nb, nc, (na + nb + nc), cc, e)


## Cheap 20-triangle blob for tiny details (flowers, pebbles).
func pebble(center: Vector3, radius: Vector3, col: Color, e := 0.0) -> void:
	var t := (1.0 + sqrt(5.0)) / 2.0
	var pv: Array[Vector3] = [
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	var faces := [0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11, 1, 5, 9, 5, 11, 4, 11, 10, 2, 10, 7, 6, 7, 1, 8,
		3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9, 4, 9, 5, 2, 4, 11, 6, 2, 10, 8, 6, 7, 9, 8, 1]
	for f in range(0, faces.size(), 3):
		var a := pv[faces[f]].normalized()
		var b := pv[faces[f + 1]].normalized()
		var c := pv[faces[f + 2]].normalized()
		tri_n(center + a * radius, center + b * radius, center + c * radius, a, b, c, a + b + c, col, e)


## Gable roof whose ridge runs along local X. Sits on top of walls at height y0.
func gable_roof(c: Vector3, w: float, d: float, h: float, over: float, col: Color, gable_col: Color, thick := 0.08) -> void:
	var x0 := c.x - w * 0.5 - over
	var x1 := c.x + w * 0.5 + over
	var zf := c.z + d * 0.5 + over
	var zb := c.z - d * 0.5 - over
	var y0 := c.y - over * (h / (d * 0.5))
	var yr := c.y + h
	var ridge0 := Vector3(x0, yr, c.z)
	var ridge1 := Vector3(x1, yr, c.z)
	var nf := Vector3(0, d * 0.5, h).normalized()
	var nb := Vector3(0, d * 0.5, -h).normalized()
	# top slopes
	quad(Vector3(x0, y0, zf), Vector3(x1, y0, zf), ridge1, ridge0, nf, col)
	quad(Vector3(x0, y0, zb), Vector3(x1, y0, zb), ridge1, ridge0, nb, col)
	# slab thickness at the eaves and rakes
	var dt := Vector3(0, -thick, 0)
	var under := col.darkened(0.25)
	quad(Vector3(x0, y0, zf), Vector3(x1, y0, zf), Vector3(x1, y0, zf) + dt, Vector3(x0, y0, zf) + dt, Vector3.BACK, under)
	quad(Vector3(x0, y0, zb), Vector3(x1, y0, zb), Vector3(x1, y0, zb) + dt, Vector3(x0, y0, zb) + dt, Vector3.FORWARD, under)
	for xs in [x0, x1]:
		var side := Vector3.LEFT if xs == x0 else Vector3.RIGHT
		quad(Vector3(xs, y0, zf), Vector3(xs, yr, c.z), Vector3(xs, yr, c.z) + dt, Vector3(xs, y0, zf) + dt, side, under)
		quad(Vector3(xs, y0, zb), Vector3(xs, yr, c.z), Vector3(xs, yr, c.z) + dt, Vector3(xs, y0, zb) + dt, side, under)
	# soffit
	quad(Vector3(x0, y0, zf) + dt, Vector3(x1, y0, zf) + dt, ridge1 + dt, ridge0 + dt, -nf, under)
	quad(Vector3(x0, y0, zb) + dt, Vector3(x1, y0, zb) + dt, ridge1 + dt, ridge0 + dt, -nb, under)
	# gable triangles on the wall plane
	var gx0 := c.x - w * 0.5
	var gx1 := c.x + w * 0.5
	for gx in [gx0, gx1]:
		var side := Vector3.LEFT if gx == gx0 else Vector3.RIGHT
		tri(Vector3(gx, c.y, c.z + d * 0.5), Vector3(gx, c.y, c.z - d * 0.5), Vector3(gx, yr - 0.02, c.z), gable_col, 0.0, 0.0, side)
	# ridge cap
	rbox(Vector3(c.x, yr + 0.01, c.z), Vector3(x1 - x0 + 0.04, 0.07, 0.12), 0.03, col.darkened(0.15))


## Hip / pyramid roof on a w x d footprint at height y.
func hip_roof(c: Vector3, w: float, d: float, h: float, over: float, col: Color) -> void:
	var hw := w * 0.5 + over
	var hd := d * 0.5 + over
	var y0 := c.y - 0.04
	var ridge_half: float = max(0.0, hw - hd) * 0.9
	var r0 := Vector3(c.x - ridge_half, c.y + h, c.z)
	var r1 := Vector3(c.x + ridge_half, c.y + h, c.z)
	var a := Vector3(c.x - hw, y0, c.z + hd)
	var b := Vector3(c.x + hw, y0, c.z + hd)
	var cc := Vector3(c.x + hw, y0, c.z - hd)
	var dd := Vector3(c.x - hw, y0, c.z - hd)
	quad(a, b, r1, r0, Vector3(0, hd, h).normalized(), col)
	quad(dd, cc, r1, r0, Vector3(0, hd, -h).normalized(), col)
	tri(b, cc, r1, col, 0, 0, Vector3(1, 0.5, 0))
	tri(a, dd, r0, col, 0, 0, Vector3(-1, 0.5, 0))
	var under := col.darkened(0.3)
	var dt := Vector3(0, -0.07, 0)
	quad(a, b, b + dt, a + dt, Vector3.BACK, under)
	quad(dd, cc, cc + dt, dd + dt, Vector3.FORWARD, under)
	quad(b, cc, cc + dt, b + dt, Vector3.RIGHT, under)
	quad(a, dd, dd + dt, a + dt, Vector3.LEFT, under)


## Window pane on a wall. `out` is the wall's outward normal (axis aligned in local space).
func window(center: Vector3, out: Vector3, w: float, h: float, glass: Color, frame: Color = Color(0, 0, 0, 0), lamp := false) -> void:
	var side := Vector3.UP.cross(out).normalized() * w * 0.5
	var up := Vector3(0, h * 0.5, 0)
	var p := center + out * 0.012
	if frame.a > 0.0:
		var fp := center + out * 0.006
		var fs := side * (1.0 + 0.09 / maxf(w, 0.01))
		var fu := up + Vector3(0, 0.045, 0)
		quad(fp - fs - fu, fp + fs - fu, fp + fs + fu, fp - fs + fu, out, frame)
		# sill
		var sill_c := center - up - Vector3(0, 0.03, 0) + out * 0.03
		push(Transform3D(Basis.looking_at(-out, Vector3.UP), sill_c))
		box(Vector3.ZERO, Vector3(w + 0.08, 0.04, 0.06), frame)
		pop()
	quad(p - side - up, p + side - up, p + side + up, p - side + up, out, glass, 2.0 if lamp else 1.0, rng.randf())


func commit(material: Material = null) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if verts.is_empty():
		return mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if material:
		mesh.surface_set_material(0, material)
	return mesh
