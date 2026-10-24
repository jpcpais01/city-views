class_name Clouds
extends RefCounted
## Soft cumulus clouds drifting over the land. Each cloud is a handful of
## camera-facing puffs (2 triangles each) that shaders/cloud.gdshader turns
## into billowy, translucent vapour with a flat base; a shadow-only twin made
## of the same puffs (shaders/cloud_shadow.gdshader) lets a soft, half-dark
## patch drift across the town below. About 55 tris per cloud, both passes
## together: no more than the old round-blob clouds.

const COUNT := 18
## the wind wraps clouds round at this x (cloud shaders fade them out before it)
const WRAP := 300.0

static var _noise: NoiseTexture2D


## Builds the clouds as children of `parent`; returns the drifting nodes
## (each with a "speed" meta, moved along +x by the world).
static func make(parent: Node3D) -> Array[Node3D]:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/cloud.gdshader")
	mat.set_shader_parameter("noise_tex", noise())
	mat.set_shader_parameter("wrap", WRAP)
	# see-through like the sea (priority 1): draw after it, or the water paints
	# over the clouds above it; level with wakes and beams, which sort by depth,
	# and under the brush ring (3)
	mat.render_priority = 2
	var smat := ShaderMaterial.new()
	smat.shader = load("res://shaders/cloud_shadow.gdshader")
	smat.set_shader_parameter("noise_tex", noise())
	smat.set_shader_parameter("wrap", WRAP)
	var out: Array[Node3D] = []
	for i in COUNT:
		var meshes := _cloud_meshes(rng)
		var mi := MeshInstance3D.new()
		mi.mesh = meshes[0]
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# the puffs are sprites: give culling a box that holds every way they can turn
		mi.custom_aabb = AABB(Vector3(-40, -20, -40), Vector3(80, 50, 80))
		var sh := MeshInstance3D.new()
		sh.mesh = meshes[1]
		sh.material_override = smat
		sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		sh.custom_aabb = mi.custom_aabb
		mi.add_child(sh)
		# spread evenly over the wrap span so the sky never bunches up or empties
		var x := -WRAP + (i + rng.randf_range(0.1, 0.9)) * (2.0 * WRAP / COUNT)
		mi.position = Vector3(x, rng.randf_range(30, 42), rng.randf_range(-260, 260))
		mi.scale = Vector3.ONE * rng.randf_range(0.85, 1.25)
		mi.rotation.y = rng.randf_range(-0.5, 0.5)
		mi.set_meta("speed", rng.randf_range(0.9, 1.7))
		parent.add_child(mi)
		out.append(mi)
	return out


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


## One cumulus: a flat-bottomed row of base puffs, bigger domes piled on the
## middle, and a crown or two. Drawn bottom-up so the upper billows blend over
## the lower ones when seen from above. Returns the cloud and its shadow, which
## leaves out the small billows and crowns (they barely change its outline below).
static func _cloud_meshes(rng: RandomNumberGenerator) -> Array[ArrayMesh]:
	var length := rng.randf_range(22.0, 46.0)
	var width := rng.randf_range(10.0, 16.0)
	var puffs: Array = []  # [centre, radius, (true: no shadow)]
	# base: a staggered double row of flattened puffs
	var nb := int(length / 6.0) + 2
	for k in nb:
		var t := (k + 0.5) / nb - 0.5
		var taper := 1.0 - absf(t) * 1.1
		var r := width * rng.randf_range(0.3, 0.4) * (0.65 + 0.35 * taper)
		var z := rng.randf_range(-0.22, 0.22) * width
		puffs.append([Vector3(t * length, r * 0.55, z), r])
		# now and then a small billow tucked against its side breaks up the round outline
		if rng.randf() > 0.3:
			continue
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var rs := r * rng.randf_range(0.45, 0.6)
		puffs.append([Vector3(t * length + rng.randf_range(-0.4, 0.4) * r, rs * 0.6 + r * 0.25, z + side * r * 0.75), rs, true])
	# domes over the middle, highest near the centre
	var nd := rng.randi_range(2, 3) + int(length / 18.0)
	for k in nd:
		var t := (k + 0.5) / nd - 0.5 + rng.randf_range(-0.08, 0.08)
		var taper := 1.0 - absf(t) * 1.4
		var r := width * rng.randf_range(0.42, 0.55) * (0.7 + 0.3 * taper)
		puffs.append([Vector3(t * length * 0.7, r * 0.55 + width * 0.32 * taper, rng.randf_range(-0.1, 0.1) * width), r])
	# a crown or two on top
	for k in rng.randi_range(1, 2):
		var r := width * rng.randf_range(0.34, 0.44)
		puffs.append([Vector3(rng.randf_range(-0.15, 0.15) * length, r * 0.5 + width * 0.62, rng.randf_range(-0.1, 0.1) * width), r, true])
	puffs.sort_custom(func(a, b): return a[0].y < b[0].y)
	var top := 0.0
	for p in puffs:
		top = maxf(top, p[0].y)
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var sidx := PackedInt32Array()
	for p in puffs:
		var c: Vector3 = p[0]
		var seed := rng.randf()
		var b := verts.size()
		for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			verts.append(c)
			uvs.append(corner)
			uv2s.append(Vector2(p[1], c.y))
			cols.append(Color(c.y / maxf(top, 0.01), 0, 0, seed))
		idx.append_array([b, b + 1, b + 2, b, b + 2, b + 3])
		if p.size() < 3:
			sidx.append_array([b, b + 1, b + 2, b, b + 2, b + 3])
	var out: Array[ArrayMesh] = []
	for ix in [idx, sidx]:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_TEX_UV] = uvs
		arr[Mesh.ARRAY_TEX_UV2] = uv2s
		arr[Mesh.ARRAY_COLOR] = cols
		arr[Mesh.ARRAY_INDEX] = ix
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		out.append(m)
	return out
