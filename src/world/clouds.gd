class_name Clouds
extends RefCounted
## Volumetric cumulus drifting over the land. Each cloud is a box that
## shaders/cloud.gdshader marches rays through, gathering vapour shaped by
## drifting 3D noise and lit by the sun through it, the sky above and the
## ground below; a shadow-only twin of the box (shaders/cloud_shadow.gdshader)
## lets a soft patch of shade drift across the town under it. 12 triangles per
## cloud and pass, so far fewer than the old puffs.

const COUNT := 30
## the wind wraps clouds round at this x (cloud shaders fade them out before it)
const WRAP := 560.0

static var _noise: NoiseTexture2D
static var _noise3: NoiseTexture3D
## the clouds' material, lit by World each frame
static var material: ShaderMaterial


## Builds the clouds as children of `parent`; returns the drifting nodes
## (each with a "speed" meta, moved along +x by the world).
static func make(parent: Node3D) -> Array[Node3D]:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/cloud.gdshader")
	mat.set_shader_parameter("noise3", noise3())
	mat.set_shader_parameter("wrap", WRAP)
	# see-through like the sea (priority 1): draw after it, or the water paints
	# over the clouds above it; level with wakes and beams, which sort by depth,
	# and under the brush ring (3)
	mat.render_priority = 2
	material = mat
	var smat := ShaderMaterial.new()
	smat.shader = load("res://shaders/cloud_shadow.gdshader")
	smat.set_shader_parameter("noise3", noise3())
	smat.set_shader_parameter("wrap", WRAP)
	var out: Array[Node3D] = []
	for i in COUNT:
		var mesh := _box(rng.randf())
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var sh := MeshInstance3D.new()
		sh.mesh = mesh
		sh.material_override = smat
		sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		mi.add_child(sh)
		# spread evenly over the wrap span so the sky never bunches up or empties
		var x := -WRAP + (i + rng.randf_range(0.1, 0.9)) * (2.0 * WRAP / COUNT)
		mi.position = Vector3(x, rng.randf_range(34, 50), rng.randf_range(-520, 520))
		# long and low, or round and towering
		var big := rng.randf_range(0.8, 1.35)
		mi.scale = Vector3(rng.randf_range(17.0, 38.0), rng.randf_range(15.0, 26.0), rng.randf_range(12.0, 22.0)) * big
		mi.rotation.y = rng.randf_range(-0.6, 0.6)
		mi.set_meta("speed", rng.randf_range(0.9, 1.7))
		parent.add_child(mi)
		out.append(mi)
	return out


## The box a cloud fills: x and z -1..1, y 0..1 (its flat base at the bottom),
## its seed in the colour's alpha.
static func _box(seed: float) -> ArrayMesh:
	var bm := BoxMesh.new()
	bm.size = Vector3(2, 1, 2)
	var arr := bm.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var cols := PackedColorArray()
	for k in verts.size():
		verts[k].y += 0.5
		cols.append(Color(0, 0, 0, seed))
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = cols
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


## Seamless 3D vapour noise the clouds are carved from.
static func noise3() -> NoiseTexture3D:
	if _noise3 == null:
		var n := FastNoiseLite.new()
		n.noise_type = FastNoiseLite.TYPE_PERLIN
		n.fractal_type = FastNoiseLite.FRACTAL_FBM
		n.fractal_octaves = 4
		n.frequency = 1.0 / 14.0
		_noise3 = NoiseTexture3D.new()
		_noise3.width = 64
		_noise3.height = 64
		_noise3.depth = 64
		_noise3.seamless = true
		_noise3.normalize = true
		_noise3.noise = n
	return _noise3


## Shared drifting-vapour noise (seamless, so it tiles over the whole sky).
static func noise() -> NoiseTexture2D:
	if _noise == null:
		var n := FastNoiseLite.new()
		n.noise_type = FastNoiseLite.TYPE_PERLIN
		n.fractal_type = FastNoiseLite.FRACTAL_FBM
		n.fractal_octaves = 4
		n.frequency = 1.0 / 48.0
		_noise = NoiseTexture2D.new()
		_noise.width = 256
		_noise.height = 256
		_noise.seamless = true
		_noise.normalize = true
		_noise.generate_mipmaps = true
		_noise.noise = n
	return _noise
