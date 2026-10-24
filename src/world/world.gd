class_name World
extends Node3D
## The island's stage: materials, sky and day/night, sun, sea and clouds.

const DAY_LENGTH := 420.0
const SEA_FLOOR := -6.3

var time_of_day := 0.3
## the times of day the player can hold the clock at (Settings), or "auto"
const TIMES := {"sunrise": 0.28, "day": 0.45, "sunset": 0.775, "night": 0.95}
var night := 0.0

var city_mat: ShaderMaterial
var ground_mat: ShaderMaterial
var detail_mat: ShaderMaterial
var water_mat: ShaderMaterial
var beam_mat: ShaderMaterial
var sky_mat: ShaderMaterial
var env: Environment
var sun: DirectionalLight3D
var rig: CameraRig
var _clouds: Array[Node3D] = []


# ------------------------------------------------------------------ setup

func _make_materials() -> void:
	city_mat = ShaderMaterial.new()
	city_mat.shader = load("res://shaders/city.gdshader")
	detail_mat = ShaderMaterial.new()
	detail_mat.shader = load("res://shaders/city_detail.gdshader")
	ground_mat = ShaderMaterial.new()
	ground_mat.shader = load("res://shaders/ground.gdshader")
	MeshKit.detail_material = detail_mat
	water_mat = ShaderMaterial.new()
	water_mat.shader = load("res://shaders/water.gdshader")
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 1.0 / 32.0
	var ntex := NoiseTexture2D.new()
	ntex.width = 256
	ntex.height = 256
	ntex.seamless = true
	ntex.generate_mipmaps = true
	ntex.noise = noise
	water_mat.set_shader_parameter("noise_tex", ntex)
	water_mat.render_priority = 1
	beam_mat = ShaderMaterial.new()
	beam_mat.shader = load("res://shaders/beam.gdshader")
	beam_mat.set_shader_parameter("sea_y", 0.0)
	# after the sea, which reads the screen behind it and would hide the beam
	beam_mat.render_priority = 2


func _make_environment() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/sky.gdshader")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.6
	env.ambient_light_sky_contribution = 0.7
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	if OS.get_environment("CV_TONE") != "":
		env.tonemap_mode = int(OS.get_environment("CV_TONE"))
	if OS.get_environment("CV_NOGLOW") != "":
		env.glow_enabled = false
	if OS.get_environment("CV_NOFOG") != "":
		env.fog_enabled = false
	env.tonemap_exposure = 1.0
	env.tonemap_white = 5.0
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_strength = 0.9
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.fog_enabled = true
	# a soft haze that blues the far country, as from a plane over a big city
	env.fog_density = 0.0011
	env.fog_aerial_perspective = 0.35
	env.fog_sun_scatter = 0.06
	env.fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	env.adjustment_contrast = 1.08
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = Game.settings.get("shadows", true)
	# one orthogonal map: every caster is drawn into the shadow map once, not once per split
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 60.0
	sun.shadow_blur = 2.4
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	add_child(sun)


func _make_sea() -> void:
	var water := MeshInstance3D.new()
	water.mesh = _sea_mesh(48, 900.0)
	water.extra_cull_margin = 2.0
	water.material_override = water_mat
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)
	var floor_mi := MeshInstance3D.new()
	var fm := PlaneMesh.new()
	fm.size = Vector2(2000, 2000)
	floor_mi.mesh = fm
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.72, 0.7, 0.56)
	fmat.roughness = 1.0
	floor_mi.material_override = fmat
	floor_mi.position.y = SEA_FLOOR - 0.01
	add_child(floor_mi)


## A grid that is dense around the island (where waves are seen up close) and
## stretches out towards the horizon.
func _sea_mesh(cells: int, half: float) -> ArrayMesh:
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	var coord := PackedFloat32Array()
	for i in cells + 1:
		var u := float(i) / cells * 2.0 - 1.0
		coord.append(half * (0.28 * u + 0.72 * u * u * u))
	for z in cells + 1:
		for x in cells + 1:
			verts.append(Vector3(coord[x], 0.0, coord[z]))
	for z in cells:
		for x in cells:
			var a := z * (cells + 1) + x
			var b := a + 1
			var c := a + cells + 1
			var d := c + 1
			idx.append_array([a, b, c, b, d, c])
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.UP)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


func _make_clouds() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	# clouds still cast shadows on the town, but never on their own puffs
	var cloud_sh := Shader.new()
	cloud_sh.code = (load("res://shaders/blob.gdshader") as Shader).code.replace("cull_disabled;", "cull_disabled, shadows_disabled;")
	var cloud_mat := ShaderMaterial.new()
	cloud_mat.shader = cloud_sh
	for i in 18:
		var mk := MeshKit.new()
		var puffs := rng.randi_range(3, 6)
		for k in puffs:
			var p := Vector3(rng.randf_range(-3.5, 3.5), rng.randf_range(-0.4, 0.6), rng.randf_range(-1.6, 1.6))
			var r := rng.randf_range(1.4, 2.6)
			# each puff is a big round sprite flanked by two lower, smaller ones,
			# so the cloud keeps its flat-bottomed, spread-out shape
			mk.blob(p, Vector3.ONE * r * 0.8, Color(1, 1, 1))
			for sx in [-1.0, 1.0]:
				mk.blob(p + Vector3(sx * r * 0.62, -r * 0.18, rng.randf_range(-0.3, 0.3) * r), Vector3.ONE * r * 0.58, Color(1, 1, 1))
		var mi := MeshInstance3D.new()
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		m.albedo_color = Color(1, 1, 1)
		m.roughness = 1.0
		m.rim_enabled = true
		m.rim = 0.4
		mi.mesh = mk.commit(m)
		mi.material_override = cloud_mat
		mi.position = Vector3(rng.randf_range(-280, 280), rng.randf_range(24, 34), rng.randf_range(-280, 280))
		mi.scale = Vector3.ONE * rng.randf_range(0.8, 1.4)
		mi.set_meta("speed", rng.randf_range(0.8, 1.6))
		add_child(mi)
		_clouds.append(mi)


# ------------------------------------------------------------------ effects

## Tells every lit surface where the lighthouse beams point, so the sweep shows
## on the ground, the buildings and the sea, not just in the air.
func _update_beams(beams: PackedVector4Array) -> void:
	var on := smoothstep(0.15, 0.55, night)
	beam_mat.set_shader_parameter("strength", on)
	var n := beams.size() if on > 0.01 else 0
	while beams.size() < 4:
		beams.append(Vector4.ZERO)
	for m in [city_mat, detail_mat, ground_mat, water_mat]:
		m.set_shader_parameter("beam_count", n)
		if n > 0:
			m.set_shader_parameter("beams", beams)


# ------------------------------------------------------------------ frame

const SKY_KEYS := [
	# t, top, horizon, sun colour, sun energy, ambient
	[0.0, Color("0b1430"), Color("1f2d55"), Color("9fb6ff"), 0.22, 0.35],
	[0.2, Color("1a2550"), Color("4a4f7a"), Color("9fb6ff"), 0.15, 0.4],
	[0.26, Color("4f6fb0"), Color("ffb38a"), Color("ffb070"), 0.6, 0.6],
	[0.34, Color("5d9be0"), Color("bfe0f5"), Color("fff0d6"), 1.3, 0.65],
	[0.5, Color("4f8fe0"), Color("c6e4fa"), Color("fff6e6"), 1.45, 0.7],
	[0.68, Color("5a93db"), Color("d8e2ea"), Color("ffe6c2"), 1.3, 0.65],
	[0.76, Color("6a6fb8"), Color("ff9e6e"), Color("ff9a5a"), 0.75, 0.65],
	[0.81, Color("2e3570"), Color("b06a7a"), Color("ff8a6a"), 0.25, 0.45],
	[0.87, Color("111a3c"), Color("2a3360"), Color("9fb6ff"), 0.2, 0.35],
	[1.0, Color("0b1430"), Color("1f2d55"), Color("9fb6ff"), 0.22, 0.35],
]


func _eased_arc(t: float) -> float:
	var half := fposmod(t - 0.25, 1.0) * 2.0
	var base := floorf(half)
	var u := half - base - 0.5
	var eased := lerpf(u, 4.0 * u * u * u, 0.82)
	return (base + eased + 0.5) * 0.5


## Moves the clock on: round the day by itself on "auto", otherwise easing
## to the time the player picked, the short way round the clock.
func advance_time(delta: float) -> void:
	var pick: String = Game.settings.get("time", "auto")
	if not TIMES.has(pick):
		time_of_day = fmod(time_of_day + delta / DAY_LENGTH, 1.0)
		return
	var gap := fposmod(float(TIMES[pick]) - time_of_day + 0.5, 1.0) - 0.5
	time_of_day = fposmod(time_of_day + gap * minf(delta * 1.5, 1.0), 1.0)


func _update_sky() -> void:
	var t := time_of_day
	var a: Array = SKY_KEYS[0]
	var b: Array = SKY_KEYS[1]
	for i in SKY_KEYS.size() - 1:
		if t >= SKY_KEYS[i][0] and t <= SKY_KEYS[i + 1][0]:
			a = SKY_KEYS[i]
			b = SKY_KEYS[i + 1]
			break
	var k := smoothstep(0.0, 1.0, (t - a[0]) / maxf(b[0] - a[0], 0.0001))
	var top: Color = (a[1] as Color).lerp(b[1], k)
	var hor: Color = (a[2] as Color).lerp(b[2], k)
	var scol: Color = (a[3] as Color).lerp(b[3], k)
	var energy: float = lerpf(a[4], b[4], k)
	var amb: float = lerpf(a[5], b[5], k)
	# sun path; at night the same light becomes the moon
	# the sun barely moves around noon (and the moon around midnight) so shadows
	# stay still while you build; it only sweeps visibly at dawn and dusk
	var ang := _eased_arc(t) * TAU
	var sun_dir := Vector3(cos(ang), sin(ang), 0.35).normalized()
	var is_day := sun_dir.y > -0.02
	var light_dir := sun_dir if is_day else Vector3(-sun_dir.x, -sun_dir.y, 0.5).normalized()
	var horizon_fade := smoothstep(-0.02, 0.12, absf(sun_dir.y))
	night = 1.0 - smoothstep(-0.12, 0.15, sun_dir.y)
	sun.light_color = scol
	sun.light_energy = energy * max(horizon_fade, 0.15)
	sun.look_at_from_position(Vector3.ZERO, -light_dir.rotated(Vector3.UP, 0.6), Vector3.UP if absf(light_dir.y) < 0.99 else Vector3.BACK)
	env.ambient_light_energy = amb * float(OS.get_environment("CV_AMB")) if OS.get_environment("CV_AMB") != "" else amb
	env.fog_light_color = hor.lerp(top, 0.25)
	sky_mat.set_shader_parameter("top_col", top)
	sky_mat.set_shader_parameter("hor_col", hor)
	sky_mat.set_shader_parameter("bottom_col", hor.darkened(0.15))
	sky_mat.set_shader_parameter("sun_col", scol)
	sky_mat.set_shader_parameter("night", night)
	city_mat.set_shader_parameter("night", night)
	detail_mat.set_shader_parameter("night", night)
	# fewer windows stay lit as the night gets later
	var nt := fmod(t + 0.15, 1.0)
	var late := clampf(nt / 0.3, 0.0, 1.0) if nt < 0.4 else 0.0
	city_mat.set_shader_parameter("lit_ratio", lerpf(0.8, 0.35, late))
	detail_mat.set_shader_parameter("lit_ratio", lerpf(0.8, 0.35, late))
	water_mat.set_shader_parameter("night", night)
	# bloom only matters for lit windows and lamps, so skip its passes by day
	env.glow_enabled = night > 0.12 and OS.get_environment("CV_NOGLOW") == ""
	Sfx.night = night
