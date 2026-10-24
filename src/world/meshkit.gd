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
# geometry written while `detail` is on (windows, paint, lamps) goes to a second
# set of arrays that is drawn without casting shadows
var detail := false
var dverts := PackedVector3Array()
var dnorms := PackedVector3Array()
var dcols := PackedColorArray()
var duvs := PackedVector2Array()
# cheap stand-in shapes drawn only into the shadow map (a box per rounded box,
# a diamond per canopy...): soft shadows look the same at a fraction of the cost
var shadow := true
var sverts := PackedVector3Array()
var snorms := PackedVector3Array()
var _depth := 0
# round blobs become sphere sprites (2 triangles, see blob.gdshader) unless this is off
var impostors := true
var bverts := PackedVector3Array()
var bcols := PackedColorArray()
var buvs := PackedVector2Array()
var bradius := PackedVector2Array()
# sprites too thin to cast a visible shadow (the same rule _small applies to
# boxes): drawn from their own mesh that stays out of the shadow pass
var quiet_sprites := false
var qverts := PackedVector3Array()
var qcols := PackedColorArray()
var quvs := PackedVector2Array()
var qradius := PackedVector2Array()
static var _blob_mat: Material
# material for the flush-detail surface (window rows need its shader)
static var detail_material: Material
var xf := Transform3D.IDENTITY
var _stack: Array[Transform3D] = []
var rng := RandomNumberGenerator.new()

static var _ico_v: PackedVector3Array
static var _ico_i: PackedInt32Array
static var _octa_v: PackedVector3Array
static var _octa_i: PackedInt32Array


func _init(seed_value: int = 0) -> void:
	rng.seed = seed_value


func push(t: Transform3D) -> void:
	_stack.push_back(xf)
	xf = xf * t


func push_at(pos: Vector3, yaw: float = 0.0, scl: Vector3 = Vector3.ONE) -> void:
	push(Transform3D(Basis(Vector3.UP, yaw).scaled(scl), pos))


func pop() -> void:
	xf = _stack.pop_back()


## Whether a primitive called now should write its own shadow stand-in.
func _casts() -> bool:
	return shadow and not detail and _depth == 0


func _st(a: Vector3, b: Vector3, c: Vector3) -> void:
	var pa := xf * a
	var pb := xf * b
	var pc := xf * c
	var n := (pb - pa).cross(pc - pa).normalized()
	sverts.append(pa)
	sverts.append(pb)
	sverts.append(pc)
	snorms.append(n)
	snorms.append(n)
	snorms.append(n)


## Shadow stand-in: box without a bottom (10 triangles).
func _sbox(c: Vector3, h: Vector3) -> void:
	var p := [c + Vector3(-h.x, -h.y, -h.z), c + Vector3(h.x, -h.y, -h.z), c + Vector3(h.x, -h.y, h.z), c + Vector3(-h.x, -h.y, h.z),
		c + Vector3(-h.x, h.y, -h.z), c + Vector3(h.x, h.y, -h.z), c + Vector3(h.x, h.y, h.z), c + Vector3(-h.x, h.y, h.z)]
	for f in [[4, 5, 6, 7], [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]]:
		_st(p[f[0]], p[f[1]], p[f[2]])
		_st(p[f[0]], p[f[2]], p[f[3]])


## Shadow stand-in: octahedron (8 triangles) for round shapes.
func _socta(c: Vector3, r: Vector3) -> void:
	var t := c + Vector3(0, r.y, 0)
	var b := c - Vector3(0, r.y, 0)
	var ring := [c + Vector3(r.x, 0, 0), c + Vector3(0, 0, r.z), c - Vector3(r.x, 0, 0), c - Vector3(0, 0, r.z)]
	for i in 4:
		_st(ring[i], ring[(i + 1) % 4], t)
		_st(ring[(i + 1) % 4], ring[i], b)


## Thin sticks, plates and tiny bits cast shadows too faint to see once softened.
static func _small(size: Vector3) -> bool:
	var a := [size.x, size.y, size.z]
	a.sort()
	# thin plates (floor bands, doors, awnings) hug a bigger body whose shadow covers them
	return a[0] < 0.06 or a[1] < 0.07 or a[2] < 0.12


## Plates lying on the ground (lots, paths, plinths) have no shadow worth drawing.
func _ground_slab(center: Vector3, size: Vector3) -> bool:
	return size.y <= 0.17 and (xf * (center + Vector3(0, size.y * 0.5, 0))).y < 0.25


func is_empty() -> bool:
	return verts.is_empty() and dverts.is_empty() and bverts.is_empty()


func _v(p: Vector3, nn: Vector3, col: Color, e: float, r: float) -> void:
	if detail:
		dverts.push_back(xf * p)
		dnorms.push_back((xf.basis * nn).normalized())
		dcols.push_back(col)
		duvs.push_back(Vector2(e, r))
		return
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
	if _casts():
		_st(a, b, c)
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


## Upward-facing quad with a colour per corner, so colours blend smoothly across it.
func quad_c(a: Vector3, b: Vector3, c: Vector3, d: Vector3, ca: Color, cb: Color, cc: Color, cd: Color) -> void:
	var n := Vector3.UP
	for t in [[a, b, c, ca, cb, cc], [a, c, d, ca, cc, cd]]:
		var p0: Vector3 = t[0]
		var p1: Vector3 = t[1]
		var p2: Vector3 = t[2]
		var c0: Color = t[3]
		var c1: Color = t[4]
		var c2: Color = t[5]
		if (p1 - p0).cross(p2 - p0).dot(n) > 0.0:
			var tp := p1; p1 = p2; p2 = tp
			var tc := c1; c1 = c2; c2 = tc
		_v(p0, n, c0, 0.0, 0.0)
		_v(p1, n, c1, 0.0, 0.0)
		_v(p2, n, c2, 0.0, 0.0)


## Quad with explicit, interpolated normals (soft shading).
func quad_n(a: Vector3, b: Vector3, c: Vector3, d: Vector3, na: Vector3, nb: Vector3, nc: Vector3, nd: Vector3, col: Color, e := 0.0, r := 0.0) -> void:
	var face := (na + nb + nc + nd).normalized()
	tri_n(a, b, c, na, nb, nc, face, col, e, r)
	tri_n(a, c, d, na, nc, nd, face, col, e, r)


## Axis-aligned flat box (no bottom by default).
func box(center: Vector3, size: Vector3, col: Color, top_col: Variant = null, bottom := false, e := 0.0) -> void:
	# posts and pickets this thin read the same as a round pole: 2 triangles
	var thick := maxf(size.x, size.z)
	if impostors and not detail and e == 0.0 and _depth == 0 and top_col == null and thick <= 0.06 \
			and size.y >= thick * 2.5 and xf.basis.y.normalized().y > 0.999:
		pole(center - Vector3(0, size.y * 0.5, 0), (size.x + size.z) * 0.28, size.y, 4, col)
		return
	if _casts() and not _small(size) and not _ground_slab(center, size):
		_sbox(center, size * 0.5)
	_depth += 1
	_box_impl(center, size, col, top_col, bottom, e)
	_depth -= 1


# emission codes the city shader paints as surface patterns (no extra triangles)
const ASPHALT := 0.1
const SLABS := 0.16
const ROOF_TILES := 0.25
const COBBLE := 0.33
const PAVING := 0.37
const SIDING := 0.41
const BRICKS := 0.45
const MOWN_X := 0.48
const MOWN_Z := 0.49

const TOP := 1
const FRONT := 2  # +Z
const BACK := 4  # -Z
const RIGHT := 8  # +X
const LEFT := 16  # -X


## A box drawing only the faces in `mask` (the rest are against a wall, under a
## neighbour or too thin to ever cover a pixel). Casts the same shadow as box().
func box_faces(center: Vector3, size: Vector3, col: Color, mask: int, e := 0.0) -> void:
	if _casts() and not _small(size) and not _ground_slab(center, size):
		_sbox(center, size * 0.5)
	_depth += 1
	var h := size * 0.5
	var c := center
	if mask & TOP:
		quad(c + Vector3(-h.x, h.y, -h.z), c + Vector3(h.x, h.y, -h.z), c + Vector3(h.x, h.y, h.z), c + Vector3(-h.x, h.y, h.z), Vector3.UP, col, e)
	if mask & FRONT:
		quad(c + Vector3(-h.x, -h.y, h.z), c + Vector3(h.x, -h.y, h.z), c + Vector3(h.x, h.y, h.z), c + Vector3(-h.x, h.y, h.z), Vector3.BACK, col, e)
	if mask & BACK:
		quad(c + Vector3(-h.x, -h.y, -h.z), c + Vector3(h.x, -h.y, -h.z), c + Vector3(h.x, h.y, -h.z), c + Vector3(-h.x, h.y, -h.z), Vector3.FORWARD, col, e)
	if mask & RIGHT:
		quad(c + Vector3(h.x, -h.y, -h.z), c + Vector3(h.x, -h.y, h.z), c + Vector3(h.x, h.y, h.z), c + Vector3(h.x, h.y, -h.z), Vector3.RIGHT, col, e)
	if mask & LEFT:
		quad(c + Vector3(-h.x, -h.y, -h.z), c + Vector3(-h.x, -h.y, h.z), c + Vector3(-h.x, h.y, h.z), c + Vector3(-h.x, h.y, -h.z), Vector3.LEFT, col, e)
	_depth -= 1


## Shadow stand-in for just the walls in `mask` (a lean-to whose roof and back
## wall already cast): two triangles per face instead of a ten-triangle box.
func shadow_faces(center: Vector3, size: Vector3, mask: int) -> void:
	if not _casts():
		return
	var h := size * 0.5
	var c := center
	for f in [[FRONT, Vector3(0, 0, h.z), Vector3(h.x, 0, 0)], [BACK, Vector3(0, 0, -h.z), Vector3(h.x, 0, 0)],
			[RIGHT, Vector3(h.x, 0, 0), Vector3(0, 0, h.z)], [LEFT, Vector3(-h.x, 0, 0), Vector3(0, 0, h.z)]]:
		if mask & int(f[0]):
			var o: Vector3 = c + f[1]
			var t: Vector3 = f[2]
			var u := Vector3(0, h.y, 0)
			_st(o - t - u, o + t - u, o + t + u)
			_st(o - t - u, o + t + u, o - t + u)


func _box_impl(center: Vector3, size: Vector3, col: Color, top_col: Variant = null, bottom := false, e := 0.0) -> void:
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


## Rounded (chamfered, smooth-shaded) box: the signature toy look. One bevel per
## edge with normals blended across it reads as rounded at a third of the triangles.
func rbox(center: Vector3, size: Vector3, radius: float, col: Color, top_col: Variant = null, bottom := false, e := 0.0) -> void:
	if _casts() and not _small(size) and not _ground_slab(center, size):
		_sbox(center, size * 0.5)
	_depth += 1
	_rbox_impl(center, size, radius, col, top_col, bottom, e)
	_depth -= 1


## The walls of a rounded box whose top is hidden under a roof, cornice or
## parapet: sides and vertical bevels only, so 16 triangles instead of 30.
## Casts the same shadow as rbox().
func rbox_walls(center: Vector3, size: Vector3, radius: float, col: Color, e := 0.0) -> void:
	if _casts() and not _small(size) and not _ground_slab(center, size):
		_sbox(center, size * 0.5)
	var h := size * 0.5
	var r: float = min(radius, min(h.x, min(h.y, h.z)) * 0.98)
	var i := h - Vector3(r, r, r)
	var c := center
	_depth += 1
	for s in [-1.0, 1.0]:
		quad(c + Vector3(s * h.x, -h.y, -i.z), c + Vector3(s * h.x, -h.y, i.z), c + Vector3(s * h.x, h.y, i.z), c + Vector3(s * h.x, h.y, -i.z), Vector3(s, 0, 0), col, e)
		quad(c + Vector3(-i.x, -h.y, s * h.z), c + Vector3(i.x, -h.y, s * h.z), c + Vector3(i.x, h.y, s * h.z), c + Vector3(-i.x, h.y, s * h.z), Vector3(0, 0, s), col, e)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var nx := Vector3(sx, 0, 0)
			var nz := Vector3(0, 0, sz)
			quad_n(c + Vector3(sx * h.x, -h.y, sz * i.z), c + Vector3(sx * h.x, h.y, sz * i.z), c + Vector3(sx * i.x, h.y, sz * h.z), c + Vector3(sx * i.x, -h.y, sz * h.z), nx, nx, nz, nz, col, e)
	_depth -= 1


## A cornice or parapet capping a body that already casts: the same rounded
## box, with no shadow stand-in of its own.
func ledge(center: Vector3, size: Vector3, radius: float, col: Color, e := 0.0) -> void:
	_depth += 1
	_rbox_impl(center, size, radius, col, null, false, e)
	_depth -= 1


func _rbox_impl(center: Vector3, size: Vector3, radius: float, col: Color, top_col: Variant = null, bottom := false, e := 0.0) -> void:
	# a bevel on a small or thin part is under a pixel wide: draw it as a plain box
	if minf(size.x, minf(size.y, size.z)) < 0.2 and radius < 0.05:
		_box_impl(center, size, col, top_col, bottom, e)
		return
	var h := size * 0.5
	var r: float = min(radius, min(h.x, min(h.y, h.z)) * 0.98)
	if r <= 0.001:
		box(center, size, col, top_col, bottom, e)
		return
	var i := h - Vector3(r, r, r)
	var tc: Color = top_col if top_col != null else col
	var c := center
	var lo := -i.y if bottom else -h.y
	var U := Vector3.UP
	# flat faces
	quad(c + Vector3(-i.x, h.y, -i.z), c + Vector3(i.x, h.y, -i.z), c + Vector3(i.x, h.y, i.z), c + Vector3(-i.x, h.y, i.z), U, tc, e)
	if bottom:
		quad(c + Vector3(-i.x, -h.y, -i.z), c + Vector3(i.x, -h.y, -i.z), c + Vector3(i.x, -h.y, i.z), c + Vector3(-i.x, -h.y, i.z), Vector3.DOWN, col, e)
	for s in [-1.0, 1.0]:
		var nx := Vector3(s, 0, 0)
		var nz := Vector3(0, 0, s)
		quad(c + Vector3(s * h.x, lo, -i.z), c + Vector3(s * h.x, lo, i.z), c + Vector3(s * h.x, i.y, i.z), c + Vector3(s * h.x, i.y, -i.z), nx, col, e)
		quad(c + Vector3(-i.x, lo, s * h.z), c + Vector3(i.x, lo, s * h.z), c + Vector3(i.x, i.y, s * h.z), c + Vector3(-i.x, i.y, s * h.z), nz, col, e)
		# top bevels
		quad_n(c + Vector3(s * i.x, h.y, -i.z), c + Vector3(s * i.x, h.y, i.z), c + Vector3(s * h.x, i.y, i.z), c + Vector3(s * h.x, i.y, -i.z), U, U, nx, nx, tc, e)
		quad_n(c + Vector3(-i.x, h.y, s * i.z), c + Vector3(i.x, h.y, s * i.z), c + Vector3(i.x, i.y, s * h.z), c + Vector3(-i.x, i.y, s * h.z), U, U, nz, nz, tc, e)
		if bottom:
			var D := Vector3.DOWN
			quad_n(c + Vector3(s * i.x, -h.y, -i.z), c + Vector3(s * i.x, -h.y, i.z), c + Vector3(s * h.x, -i.y, i.z), c + Vector3(s * h.x, -i.y, -i.z), D, D, nx, nx, col, e)
			quad_n(c + Vector3(-i.x, -h.y, s * i.z), c + Vector3(i.x, -h.y, s * i.z), c + Vector3(i.x, -i.y, s * h.z), c + Vector3(-i.x, -i.y, s * h.z), D, D, nz, nz, col, e)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var nx := Vector3(sx, 0, 0)
			var nz := Vector3(0, 0, sz)
			# vertical bevel
			quad_n(c + Vector3(sx * h.x, lo, sz * i.z), c + Vector3(sx * h.x, i.y, sz * i.z), c + Vector3(sx * i.x, i.y, sz * h.z), c + Vector3(sx * i.x, lo, sz * h.z), nx, nx, nz, nz, col, e)
			# corner
			var a := c + Vector3(sx * i.x, h.y, sz * i.z)
			var b2 := c + Vector3(sx * h.x, i.y, sz * i.z)
			var d := c + Vector3(sx * i.x, i.y, sz * h.z)
			tri_n(a, b2, d, U, nx, nz, (U + nx + nz).normalized(), tc, e)
			if bottom:
				var D := Vector3.DOWN
				var a2 := c + Vector3(sx * i.x, -h.y, sz * i.z)
				var b3 := c + Vector3(sx * h.x, -i.y, sz * i.z)
				var d2 := c + Vector3(sx * i.x, -i.y, sz * h.z)
				tri_n(a2, b3, d2, D, nx, nz, (D + nx + nz).normalized(), col, e)
				quad_n(c + Vector3(sx * h.x, -i.y, sz * i.z), c + Vector3(sx * h.x, lo, sz * i.z), c + Vector3(sx * i.x, lo, sz * h.z), c + Vector3(sx * i.x, -i.y, sz * h.z), nx, nx, nz, nz, col, e)


## Vertical cylinder standing on `base`.
func cylinder(base: Vector3, radius: float, height: float, sides: int, col: Color, cap := true, top_col: Variant = null, r_top := -1.0, e := 0.0) -> void:
	if _casts() and not _small(Vector3(radius * 2.0, height, radius * 2.0)):
		var rr := maxf(radius, r_top) * 0.9
		_sbox(base + Vector3(0, height * 0.5, 0), Vector3(rr, height * 0.5, rr))
	_depth += 1
	_cylinder_impl(base, radius, height, sides, col, cap, top_col, r_top, e)
	_depth -= 1


func _cylinder_impl(base: Vector3, radius: float, height: float, sides: int, col: Color, cap := true, top_col: Variant = null, r_top := -1.0, e := 0.0) -> void:
	var rt: float = radius if r_top < 0.0 else r_top
	var tc: Color = top_col if top_col != null else col
	var slope := (radius - rt) / maxf(height, 0.001)
	# a disc this thin (water in a basin, soil in a planter) has no wall worth a pixel
	var walls := height > 0.012
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var n0 := (d0 + Vector3(0, slope, 0)).normalized()
		var n1 := (d1 + Vector3(0, slope, 0)).normalized()
		if walls:
			quad_n(base + d0 * radius, base + d1 * radius, base + d1 * rt + Vector3(0, height, 0), base + d0 * rt + Vector3(0, height, 0), n0, n1, n1, n0, col, e)
		if cap and rt > 0.001:
			var top := base + Vector3(0, height, 0)
			tri_n(top, top + d0 * rt, top + d1 * rt, Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP, tc, e)


func cone(base: Vector3, radius: float, height: float, sides: int, col: Color, e := 0.0) -> void:
	if _casts() and not _small(Vector3(radius * 2.0, height, radius * 2.0)):
		var tip := base + Vector3(0, height, 0)
		var ring := [base + Vector3(radius, 0, 0), base + Vector3(0, 0, radius), base - Vector3(radius, 0, 0), base - Vector3(0, 0, radius)]
		for i in 4:
			_st(ring[i], ring[(i + 1) % 4], tip)
	_depth += 1
	_cone_impl(base, radius, height, sides, col, e)
	_depth -= 1


func _cone_impl(base: Vector3, radius: float, height: float, sides: int, col: Color, e := 0.0) -> void:
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
	# once-subdivided octahedron, rotated 22.5 degrees so its outline is a level octagon
	var ov: Array[Vector3] = [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]
	var of := [2, 4, 0, 2, 0, 5, 2, 5, 1, 2, 1, 4, 3, 0, 4, 3, 5, 0, 3, 1, 5, 3, 4, 1]
	var ocache := {}
	var omid := func(a: int, b: int) -> int:
		var key := Vector2i(mini(a, b), maxi(a, b))
		if ocache.has(key):
			return ocache[key]
		ov.append(((ov[a] + ov[b]) * 0.5).normalized())
		ocache[key] = ov.size() - 1
		return ov.size() - 1
	var oi := PackedInt32Array()
	for f in range(0, of.size(), 3):
		var a: int = of[f]
		var b: int = of[f + 1]
		var c: int = of[f + 2]
		var ab: int = omid.call(a, b)
		var bc: int = omid.call(b, c)
		var ca: int = omid.call(c, a)
		oi.append_array([a, ab, ca, b, bc, ab, c, ca, bc, ab, bc, ca])
	var rot := Basis(Vector3.UP, PI / 8.0)
	_octa_v = PackedVector3Array()
	for p in ov:
		_octa_v.append(rot * p)
	_octa_i = oi


## Soft round blob (tree canopies, bushes, clouds).
func blob(center: Vector3, radius: Vector3, col: Color, jitter := 0.0, e := 0.0) -> void:
	if impostors and e == 0.0 and not detail:
		# one camera-facing quad that the shader turns into a shaded sphere
		var c := xf * center
		var r := (radius.x + radius.y + radius.z) / 3.0 * xf.basis.get_scale().x
		# a jittered blob is foliage: the shader gives it a leafy outline (y = -1)
		_sprite(c, col, [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, -1), Vector2(1, 1), Vector2(-1, 1)],
			Vector2(r, -1.0 if jitter > 0.0 else 0.0), r * 2.0 < 0.12)
		return
	if _casts() and not _small(radius * 2.0):
		_socta(center, radius)
	_depth += 1
	_blob_impl(center, radius, col, jitter, e)
	_depth -= 1


## Upright round pole (trunks, lamp posts, piles): one quad turned to the
## camera that the blob shader shades as a cylinder. Falls back to a mesh.
func pole(base: Vector3, radius: float, height: float, sides: int, col: Color, e := 0.0) -> void:
	if impostors and e == 0.0 and not detail:
		var c := xf * base
		var sc := xf.basis.get_scale().x
		_sprite(c, col, [Vector2(-1, 0), Vector2(1, 0), Vector2(1, 1), Vector2(-1, 0), Vector2(1, 1), Vector2(-1, 1)],
			Vector2(radius * sc, height * sc), radius * sc * 2.0 < 0.06)
		return
	cylinder(base, radius, height, sides, col, false, null, -1.0, e)


func _sprite(c: Vector3, col: Color, corners: Array, rad: Vector2, thin: bool) -> void:
	var q := quiet_sprites and thin
	for k in corners:
		(qverts if q else bverts).append(c)
		(qcols if q else bcols).append(col)
		(quvs if q else buvs).append(k)
		(qradius if q else bradius).append(rad)


func _blob_impl(center: Vector3, radius: Vector3, col: Color, jitter := 0.0, e := 0.0) -> void:
	if maxf(radius.x, maxf(radius.y, radius.z)) < 0.1:
		# flower and bush sized: 20 faces are already round at this size
		_pebble_impl(center, radius, col, e)
		return
	if _ico_v.is_empty():
		_build_ico()
	# smooth normals make 32 faces (an octagon in outline) read as round
	var sv := _octa_v
	var si := _octa_i
	var pts := PackedVector3Array()
	pts.resize(sv.size())
	for i in sv.size():
		var u := sv[i]
		var k := 1.0
		if jitter > 0.0:
			k += sin(u.x * 7.1 + u.z * 5.3 + center.x) * jitter + cos(u.y * 6.7 + center.z) * jitter * 0.5
		pts[i] = center + u * radius * k
	for f in range(0, si.size(), 3):
		var ia := si[f]
		var ib := si[f + 1]
		var ic := si[f + 2]
		var na := (sv[ia] / radius).normalized()
		var nb := (sv[ib] / radius).normalized()
		var nc := (sv[ic] / radius).normalized()
		var shade := 0.88 + 0.12 * clampf((sv[ia].y + 1.0) * 0.5, 0.0, 1.0)
		var cc := Color(col.r * shade, col.g * shade, col.b * shade)
		tri_n(pts[ia], pts[ib], pts[ic], na, nb, nc, (na + nb + nc), cc, e)


## Cheap 20-triangle blob for tiny details (flowers, pebbles).
func pebble(center: Vector3, radius: Vector3, col: Color, e := 0.0) -> void:
	if _casts() and not _small(radius * 2.0):
		_socta(center, radius)
	_depth += 1
	_pebble_impl(center, radius, col, e)
	_depth -= 1


func _pebble_impl(center: Vector3, radius: Vector3, col: Color, e := 0.0) -> void:
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
	if _casts():
		var hx := w * 0.5 + over
		var hz := d * 0.5 + over
		var y0 := c.y - over * (h / (d * 0.5))
		var r0 := Vector3(c.x - hx, c.y + h, c.z)
		var r1 := Vector3(c.x + hx, c.y + h, c.z)
		for zs in [hz, -hz]:
			_st(Vector3(c.x - hx, y0, c.z + zs), Vector3(c.x + hx, y0, c.z + zs), r1)
			_st(Vector3(c.x - hx, y0, c.z + zs), r1, r0)
	_depth += 1
	_gable_roof_impl(c, w, d, h, over, col, gable_col, thick)
	_depth -= 1


func _gable_roof_impl(c: Vector3, w: float, d: float, h: float, over: float, col: Color, gable_col: Color, thick := 0.08) -> void:
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
	quad(Vector3(x0, y0, zf), Vector3(x1, y0, zf), ridge1, ridge0, nf, col, ROOF_TILES)
	quad(Vector3(x0, y0, zb), Vector3(x1, y0, zb), ridge1, ridge0, nb, col, ROOF_TILES)
	# slab thickness at the eaves and rakes
	var dt := Vector3(0, -thick, 0)
	var under := col.darkened(0.25)
	quad(Vector3(x0, y0, zf), Vector3(x1, y0, zf), Vector3(x1, y0, zf) + dt, Vector3(x0, y0, zf) + dt, Vector3.BACK, under)
	quad(Vector3(x0, y0, zb), Vector3(x1, y0, zb), Vector3(x1, y0, zb) + dt, Vector3(x0, y0, zb) + dt, Vector3.FORWARD, under)
	# dormers, porches and sheds: rakes, soffit and ridge cap are under a pixel at any zoom
	var small := w * d < 0.4
	for xs in ([] if small else [x0, x1]):
		var side := Vector3.LEFT if xs == x0 else Vector3.RIGHT
		quad(Vector3(xs, y0, zf), Vector3(xs, yr, c.z), Vector3(xs, yr, c.z) + dt, Vector3(xs, y0, zf) + dt, side, under)
		quad(Vector3(xs, y0, zb), Vector3(xs, yr, c.z), Vector3(xs, yr, c.z) + dt, Vector3(xs, y0, zb) + dt, side, under)
	if not small:
		# soffit
		quad(Vector3(x0, y0, zf) + dt, Vector3(x1, y0, zf) + dt, ridge1 + dt, ridge0 + dt, -nf, under)
		quad(Vector3(x0, y0, zb) + dt, Vector3(x1, y0, zb) + dt, ridge1 + dt, ridge0 + dt, -nb, under)
	# gable triangles on the wall plane
	var gx0 := c.x - w * 0.5
	var gx1 := c.x + w * 0.5
	for gx in [gx0, gx1]:
		var side := Vector3.LEFT if gx == gx0 else Vector3.RIGHT
		tri(Vector3(gx, c.y, c.z + d * 0.5), Vector3(gx, c.y, c.z - d * 0.5), Vector3(gx, yr - 0.02, c.z), gable_col, 0.0, 0.0, side)
	if not small:
		# ridge cap (its ends are a few pixels at most, left open)
		box_faces(Vector3(c.x, yr + 0.01, c.z), Vector3(x1 - x0 + 0.04, 0.07, 0.12), col.darkened(0.15), TOP | FRONT | BACK)


## Hip / pyramid roof on a w x d footprint at height y.
func hip_roof(c: Vector3, w: float, d: float, h: float, over: float, col: Color) -> void:
	if _casts():
		var hw := w * 0.5 + over
		var hd := d * 0.5 + over
		var top := Vector3(c.x, c.y + h, c.z)
		var ring := [Vector3(c.x - hw, c.y, c.z + hd), Vector3(c.x + hw, c.y, c.z + hd), Vector3(c.x + hw, c.y, c.z - hd), Vector3(c.x - hw, c.y, c.z - hd)]
		for i in 4:
			_st(ring[i], ring[(i + 1) % 4], top)
	_depth += 1
	_hip_roof_impl(c, w, d, h, over, col)
	_depth -= 1


func _hip_roof_impl(c: Vector3, w: float, d: float, h: float, over: float, col: Color) -> void:
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
	quad(a, b, r1, r0, Vector3(0, hd, h).normalized(), col, ROOF_TILES)
	quad(dd, cc, r1, r0, Vector3(0, hd, -h).normalized(), col, ROOF_TILES)
	tri(b, cc, r1, col, ROOF_TILES, 0, Vector3(1, 0.5, 0))
	tri(a, dd, r0, col, ROOF_TILES, 0, Vector3(-1, 0.5, 0))
	var under := col.darkened(0.3)
	var dt := Vector3(0, -0.07, 0)
	quad(a, b, b + dt, a + dt, Vector3.BACK, under)
	quad(dd, cc, cc + dt, dd + dt, Vector3.FORWARD, under)
	quad(b, cc, cc + dt, b + dt, Vector3.RIGHT, under)
	quad(a, dd, dd + dt, a + dt, Vector3.LEFT, under)


## Window pane on a wall. `out` is the wall's outward normal (axis aligned in local space).
func window(center: Vector3, out: Vector3, w: float, h: float, glass: Color, frame: Color = Color(0, 0, 0, 0), lamp := false) -> void:
	var was := detail
	detail = true
	var side := Vector3.UP.cross(out).normalized() * w * 0.5
	var up := Vector3(0, h * 0.5, 0)
	if frame.a > 0.0:
		# frame, glass and sill are painted by the city shader on one quad
		var p := center + out * 0.01
		var fs := side + side.normalized() * 0.045
		var top := up + Vector3(0, 0.045, 0)
		var bot := -up - Vector3(0, 0.095, 0)
		var rr := floorf(rng.randf() * 100.0)
		quad_uv(p - fs + bot, p + fs + bot, p + fs + top, p - fs + top, out, glass,
			Vector2(4.0, rr), Vector2(4.98, rr), Vector2(4.98, rr + 0.98), Vector2(4.0, rr + 0.98))
	elif lamp:
		var p := center + out * 0.012
		quad(p - side - up, p + side - up, p + side + up, p - side + up, out, glass, 2.0, rng.randf())
	else:
		# a frameless pane is a one-window row, so the shader knows where on the glass it is
		var p := center + out * 0.012
		var seed := floorf(rng.randf() * 100.0)
		quad_uv(p - side - up, p + side - up, p + side + up, p - side + up, out, Color(glass.r, glass.g, glass.b, 1.0),
			Vector2(121.0, seed), Vector2(121.98, seed), Vector2(121.98, seed + 0.98), Vector2(121.0, seed + 0.98))
	detail = was


## A row of `count` evenly spaced windows along a wall, as one quad that the
## detail shader cuts into windows. `center` is the row's centre on the wall.
func window_row(center: Vector3, out: Vector3, length: float, count: int, w: float, h: float, glass: Color, framed := true) -> void:
	if count <= 0:
		return
	if count == 1:
		window(center, out, w, h, glass, Color(1, 1, 1, 1) if framed else Color(0, 0, 0, 0))
		return
	var was := detail
	detail = true
	var side := Vector3.UP.cross(out).normalized() * length * 0.5
	var p := center + out * (0.01 if framed else 0.012)
	var top := Vector3(0, h * 0.5 + (0.045 if framed else 0.0), 0)
	var bot := -Vector3(0, h * 0.5 + (0.095 if framed else 0.0), 0)
	var cell := length / count
	var fill := ((w + 0.09) if framed else w) / cell
	var code := 20.0 + count + (0.0 if framed else 100.0)
	var seed := floorf(rng.randf() * 100.0)
	var col := Color(glass.r, glass.g, glass.b, clampf(fill, 0.02, 1.0))
	quad_uv(p - side + bot, p + side + bot, p + side + top, p - side + top, out, col,
		Vector2(code, seed), Vector2(code + 0.98, seed), Vector2(code + 0.98, seed + 0.98), Vector2(code, seed + 0.98))
	detail = was


## Framed windows on `floors` storeys of a wall, all on one quad: from `foot`
## (the wall's foot, centred) up `floors` storeys of 0.62, `count` across,
## each window placed in its storey as window_row places a row of 0.32 tall
## ones. The shader cuts out the gaps.
func window_grid(foot: Vector3, out: Vector3, length: float, count: int, floors: int, w: float, glass: Color) -> void:
	if count <= 0 or floors <= 0:
		return
	var was := detail
	detail = true
	var side := Vector3.UP.cross(out).normalized() * length * 0.5
	var p := foot + out * 0.01
	var top := Vector3(0, floors * 0.62, 0)
	var cell := length / count
	var code := 200.0 + mini(count, 90)
	var seed := floorf(rng.randf() * 100.0)
	var y := floors * 100.0 + seed
	var col := Color(glass.r, glass.g, glass.b, clampf((w + 0.09) / cell, 0.02, 1.0))
	quad_uv(p - side, p + side, p + side + top, p - side + top, out, col,
		Vector2(code, y), Vector2(code + 0.98, y), Vector2(code + 0.98, y + 0.98), Vector2(code, y + 0.98))
	detail = was


## Thin trim lines running round a w x d block every `spacing` up from y0
## (floor bands, mullions): one quad per wall, the gaps cut out by the shader.
func bands(y0: float, w: float, d: float, spacing: float, count: int, thick: float, col: Color) -> void:
	if count <= 0:
		return
	var was := detail
	detail = true
	var ht := thick * 0.5
	var s0 := -ht / spacing
	var s1 := count - 1 + ht / spacing
	var c := Color(col.r, col.g, col.b, ht / spacing)
	var lo := y0 - ht
	var hi := y0 + (count - 1) * spacing + ht
	for side in 4:
		var out: Vector3 = [Vector3.BACK, Vector3.RIGHT, Vector3.FORWARD, Vector3.LEFT][side]
		var half := (w if side % 2 == 0 else d) * 0.5 + 0.012
		var dist := (d if side % 2 == 0 else w) * 0.5 + 0.012
		var along := Vector3.UP.cross(out).normalized() * half
		var p := out * dist
		quad_uv(p - along + Vector3(0, lo, 0), p + along + Vector3(0, lo, 0), p + along + Vector3(0, hi, 0), p - along + Vector3(0, hi, 0), out, c,
			Vector2(300, s0), Vector2(300.98, s0), Vector2(300.98, s1), Vector2(300, s1))
	detail = was


## Flat quad with its own UV per corner (a-b-c-d around the perimeter).
func quad_uv(a: Vector3, b: Vector3, c: Vector3, d: Vector3, face: Vector3, col: Color, ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2) -> void:
	var n := face.normalized()
	for t in [[a, b, c, ua, ub, uc], [a, c, d, ua, uc, ud]]:
		var p0: Vector3 = t[0]
		var p1: Vector3 = t[1]
		var p2: Vector3 = t[2]
		var u0: Vector2 = t[3]
		var u1: Vector2 = t[4]
		var u2: Vector2 = t[5]
		if (p1 - p0).cross(p2 - p0).dot(n) > 0.0:
			var tp := p1; p1 = p2; p2 = tp
			var tu := u1; u1 = u2; u2 = tu
		_v(p0, n, col, u0.x, u0.y)
		_v(p1, n, col, u1.x, u1.y)
		_v(p2, n, col, u2.x, u2.y)


static func blob_material() -> Material:
	if _blob_mat == null:
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/blob.gdshader")
		_blob_mat = m
	return _blob_mat


## The sphere sprites as their own mesh (null when there are none).
func commit_blobs() -> ArrayMesh:
	if bverts.is_empty():
		return null
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, blob_arrays(bverts, bcols, buvs, bradius))
	mesh.surface_set_material(0, blob_material())
	# sprites grow past their centres; keep them from being culled early
	mesh.custom_aabb = _blob_aabb(bverts, bradius)
	return mesh


static func blob_arrays(v: PackedVector3Array, c: PackedColorArray, uv: PackedVector2Array, r: PackedVector2Array) -> Array:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	var n := PackedVector3Array()
	n.resize(v.size())
	n.fill(Vector3.UP)
	arrays[Mesh.ARRAY_NORMAL] = n
	arrays[Mesh.ARRAY_COLOR] = c
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_TEX_UV2] = r
	return arrays


static func _blob_aabb(v: PackedVector3Array, r: PackedVector2Array) -> AABB:
	var box := AABB(v[0], Vector3.ZERO)
	var big := 0.0
	for i in v.size():
		box = box.expand(v[i])
		big = maxf(big, maxf(r[i].x, r[i].y))
	return box.grow(big * 1.2)


## The shadowless thin sprites as their own mesh (null when there are none).
func commit_quiet() -> ArrayMesh:
	if qverts.is_empty():
		return null
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, blob_arrays(qverts, qcols, quvs, qradius))
	mesh.surface_set_material(0, blob_material())
	mesh.custom_aabb = _blob_aabb(qverts, qradius)
	return mesh


## The shadow stand-ins as their own mesh (null when there are none).
func commit_shadow(material: Material = null) -> ArrayMesh:
	if sverts.is_empty():
		return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = sverts
	arrays[Mesh.ARRAY_NORMAL] = snorms
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if material:
		mesh.surface_set_material(0, material)
	return mesh


func commit(material: Material = null, with_blobs := true) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for set in [[verts, norms, cols, uvs], [dverts, dnorms, dcols, duvs]]:
		if (set[0] as PackedVector3Array).is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = set[0]
		arrays[Mesh.ARRAY_NORMAL] = set[1]
		arrays[Mesh.ARRAY_COLOR] = set[2]
		arrays[Mesh.ARRAY_TEX_UV] = set[3]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		if material:
			var m := material
			if set[0] == dverts and detail_material:
				m = detail_material
			mesh.surface_set_material(mesh.get_surface_count() - 1, m)
	if with_blobs and not bverts.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, blob_arrays(bverts, bcols, buvs, bradius))
		mesh.surface_set_material(mesh.get_surface_count() - 1, blob_material())
		mesh.custom_aabb = mesh.get_aabb().merge(_blob_aabb(bverts, bradius))
	return mesh
