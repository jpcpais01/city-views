class_name Wake
extends RefCounted
## The foam a boat leaves behind it: a churned trail straight back from the
## stern and the two arms of the V spreading out from it, added to the boat's
## own mesh as one more surface (so it costs no extra draw call per boat).

## the half angle of the V a boat's wake opens to, as on real water
const ARMS := deg_to_rad(19.5)
const SEGMENTS := 6

static var _mat: ShaderMaterial


static func material() -> ShaderMaterial:
	if _mat == null:
		_mat = ShaderMaterial.new()
		_mat.shader = load("res://shaders/wake.gdshader")
		# after the sea, which is drawn see-through on top of the seabed
		_mat.render_priority = 2
	return _mat


## Adds a wake to `mesh`: from `stern` (mesh-local, at the waterline) back
## along `back` for `length`, the boat `beam` wide; `side` is the boat's right.
static func add(mesh: ArrayMesh, stern: Vector3, back: Vector3, side: Vector3, length: float, beam: float) -> void:
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	# the churn straight behind, then each arm of the V
	var spread := tan(ARMS)
	_strip(verts, cols, uvs, idx, func(s: float) -> Vector3: return stern + back * s * length * 0.75,
		func(s: float) -> float: return beam * (0.3 + 0.35 * s), side, 0.6)
	for sx: float in [-1.0, 1.0]:
		_strip(verts, cols, uvs, idx, func(s: float) -> Vector3: return stern + back * s * length + side * sx * (beam * 0.4 + s * length * spread),
			func(s: float) -> float: return beam * (0.05 + 0.12 * s), side, 0.45)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var norms := PackedVector3Array()
	norms.resize(verts.size())
	norms.fill(Vector3.UP)
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(mesh.get_surface_count() - 1, material())
	if mesh.custom_aabb.size != Vector3.ZERO:
		mesh.custom_aabb = mesh.custom_aabb.merge(mesh.get_aabb())


static func _strip(verts: PackedVector3Array, cols: PackedColorArray, uvs: PackedVector2Array, idx: PackedInt32Array,
		at: Callable, half: Callable, side: Vector3, strength: float) -> void:
	var first := verts.size()
	for k in SEGMENTS + 1:
		var s := float(k) / SEGMENTS
		var c: Vector3 = at.call(s)
		var h: float = half.call(s)
		verts.append(c - side * h)
		verts.append(c + side * h)
		cols.append(Color(1, 1, 1, strength))
		cols.append(Color(1, 1, 1, strength))
		uvs.append(Vector2(0.0, s))
		uvs.append(Vector2(1.0, s))
	for k in SEGMENTS:
		var a := first + k * 2
		idx.append_array([a, a + 2, a + 1, a + 1, a + 2, a + 3])
