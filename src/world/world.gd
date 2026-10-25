class_name World
extends Node3D
## The island's stage: materials, sky and day/night, sun, sea and clouds.

const DAY_LENGTH := 420.0
## the haze: how much of the far country it takes at most, and how far out
## it has taken all it will (the first stretch in front of the view stays
## clear, so the town never washes out at any zoom)
const HAZE := 0.95
const HAZE_END := 5500.0
const HAZE_CURVE := 0.45
## how far the sea runs (it meets the haze long before)
const SEA_REACH := 16000.0
## shadow softness and lift, in shadow-map texels at the closest zoom
const SHADOW_BLUR := 2.4
const SHADOW_NORMAL_BIAS := 1.2
## how far the shadow map reaches when the view is at its tightest (in metres);
## the texel is this over the map's size, and the blur is kept in metres from it
const SHADOW_NEAR_REACH := 92.0
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
## Hyper graphics: photo mode's stills get every bit of quality the device can give
var hyper := false
var _ao: MeshInstance3D
var _everyday := {}


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
	sky_mat.set_shader_parameter("cloud_tex", Clouds.noise())
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.6
	# the shade is lit by the sky itself: cool blue under a clear noon, warm
	# when a low sun fires up its side of the sky
	env.ambient_light_sky_contribution = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	# AgX rolls bright skies and lamps off softly, like film, instead of clipping them
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	if OS.get_environment("CV_TONE") != "":
		env.tonemap_mode = int(OS.get_environment("CV_TONE"))
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_strength = 0.9
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.fog_enabled = OS.get_environment("CV_NOFOG") == ""
	# aerial perspective: the air between the eye and the far country blues and
	# pales it into the sky behind, so hills a few kilometres off read as a
	# soft blue range and the land and sea melt into the horizon with no edge.
	# It deepens with distance from the eye, starting a little in front of
	# what the view looks at (frame_view), so the town itself stays clear
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_density = HAZE
	env.fog_depth_curve = HAZE_CURVE
	env.fog_depth_begin = 30.0
	env.fog_depth_end = HAZE_END
	env.fog_aerial_perspective = 0.3
	if OS.get_environment("CV_HAZE") != "":
		var hz := OS.get_environment("CV_HAZE").split(",")
		env.fog_density = float(hz[0])
		env.fog_depth_curve = float(hz[1])
		env.fog_depth_end = float(hz[2])
		env.fog_aerial_perspective = float(hz[3])
	env.fog_sun_scatter = 0.12
	env.fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.06
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = Game.settings.get("shadows", true)
	# one orthogonal map: every caster is drawn into the shadow map once, not once per split
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 60.0
	# never let shadows thin out towards the edge of what they cover
	sun.directional_shadow_fade_start = 1.0
	sun.shadow_blur = SHADOW_BLUR
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = SHADOW_NORMAL_BIAS
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
	# the open sea beyond, flat (the swell has died away long before) out to
	# where the haze takes it
	var outer := MeshInstance3D.new()
	outer.mesh = _sea_ring(900.0, SEA_REACH)
	outer.material_override = water_mat
	outer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(outer)
	var deep := MeshInstance3D.new()
	deep.mesh = _sea_ring(1000.0, SEA_REACH, SEA_FLOOR - 0.01)
	deep.material_override = fmat
	deep.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(deep)


## A flat square ring between `a` and `b` out from the middle, at height y.
func _sea_ring(a: float, b: float, y := 0.0) -> ArrayMesh:
	var verts := PackedVector3Array()
	for p: Vector2 in [Vector2(-a, -a), Vector2(a, -a), Vector2(a, a), Vector2(-a, a), Vector2(-b, -b), Vector2(b, -b), Vector2(b, b), Vector2(-b, b)]:
		verts.append(Vector3(p.x, y, p.y))
	var idx := PackedInt32Array()
	for k in 4:
		var i0 := k
		var i1 := (k + 1) % 4
		idx.append_array([i0 + 4, i1 + 4, i1, i0 + 4, i1, i0])
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
	_clouds = Clouds.make(self)


# ------------------------------------------------------------------ view

## Fits the shadow map and the haze to what the camera at distance `d`,
## looking down at `pitch`, can see: the shadows reach the far edge of the
## view (all the way to the horizon when tilted up), and stay as crisp and as
## dark there as up close; the haze thins as the camera pulls back so the town
## never washes out, while the far country still fades into the sky.
func frame_view(d: float, pitch: float) -> void:
	var h := d * sin(pitch)
	var top := pitch - deg_to_rad(rig.cam.fov * 0.5 if rig else 20.0)
	var reach := h / sin(top) if top > deg_to_rad(4.0) else 1e9
	var far := clampf(maxf(reach, d) * 1.3, 32.0, 1100.0)
	sun.directional_shadow_max_distance = far
	# the map's texels grow with its reach: keep the blur and lift the same in metres
	var k := clampf(SHADOW_NEAR_REACH / far, 0.3, 1.0)
	sun.shadow_blur = SHADOW_BLUR * k
	sun.shadow_normal_bias = SHADOW_NORMAL_BIAS * maxf(k, 0.5)
	env.fog_depth_begin = d * 0.55
	if hyper:
		# four nested maps: the nearest a few metres across, every caster still
		# reaching the horizon, so close-ups get pin-sharp contact shadows
		sun.shadow_blur = SHADOW_BLUR * 0.6
		sun.shadow_normal_bias = SHADOW_NORMAL_BIAS * 0.7
		sun.directional_shadow_split_1 = 0.05
		sun.directional_shadow_split_2 = 0.15
		sun.directional_shadow_split_3 = 0.4


## Hyper graphics, for photo mode only (it is far too heavy to play in):
## supersampled, a shadow map four times the size split in
## four, the softest shadow filter, ambient occlusion from the depth buffer,
## a finer sky reflection and a gentle bloom by day. Off again restores the
## everyday settings exactly.
func set_hyper(on: bool) -> void:
	if on == hyper:
		return
	hyper = on
	var vp := get_viewport()
	if on:
		_everyday = {"scale": vp.scaling_3d_scale, "aa": vp.screen_space_aa, "lod": vp.mesh_lod_threshold}
		# twice the pixels each way, averaged down: smoother than MSAA, and the sea
		# and the occlusion still read the depth buffer (MSAA would break both here)
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = 2.0
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		vp.mesh_lod_threshold = 0.0
		RenderingServer.directional_shadow_atlas_set_size(8192, true)
		RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_ULTRA)
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		sun.directional_shadow_blend_splits = true
		env.sky.radiance_size = Sky.RADIANCE_SIZE_256
		if _ao == null:
			_ao = MeshInstance3D.new()
			var q := QuadMesh.new()
			q.size = Vector2.ONE
			var m := ShaderMaterial.new()
			m.shader = load("res://shaders/ao.gdshader")
			# over the town, under the sea (which draws the seabed itself)
			m.render_priority = -1
			q.material = m
			_ao.mesh = q
			_ao.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_ao.extra_cull_margin = 16384.0
			_ao.ignore_occlusion_culling = true
		if rig and _ao.get_parent() == null:
			rig.cam.add_child(_ao)
		_ao.visible = true
	else:
		vp.scaling_3d_scale = _everyday.scale
		vp.screen_space_aa = _everyday.aa
		vp.mesh_lod_threshold = _everyday.lod
		RenderingServer.directional_shadow_atlas_set_size(ProjectSettings.get_setting_with_override("rendering/lights_and_shadows/directional_shadow/size"), true)
		RenderingServer.directional_soft_shadow_filter_set_quality(ProjectSettings.get_setting_with_override("rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality"))
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
		env.sky.radiance_size = Sky.RADIANCE_SIZE_64
		if _ao:
			_ao.visible = false
	if rig:
		frame_view(rig.dist, rig.view_pitch())
	_update_sky()


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
	[0.0, Color("070d24"), Color("16224a"), Color("8fa8ff"), 0.3, 0.22],
	[0.2, Color("121c45"), Color("3a4272"), Color("8fa8ff"), 0.22, 0.26],
	[0.26, Color("41609f"), Color("ffae80"), Color("ffa868"), 0.85, 0.42],
	[0.31, Color("4f8ad4"), Color("f6d6b8"), Color("ffd9a8"), 1.45, 0.5],
	[0.38, Color("3d82dc"), Color("b9dcf6"), Color("fff1dc"), 1.75, 0.52],
	[0.5, Color("3a7fdc"), Color("bfe0f8"), Color("fff6ea"), 1.85, 0.52],
	[0.66, Color("4383d6"), Color("cfe0ee"), Color("ffeccc"), 1.7, 0.52],
	[0.73, Color("4f74c0"), Color("ffc890"), Color("ffc27a"), 1.4, 0.48],
	[0.775, Color("4b5aa6"), Color("ff9a68"), Color("ffa860"), 1.2, 0.4],
	[0.81, Color("272f68"), Color("c0687a"), Color("ff7f5e"), 0.3, 0.32],
	[0.87, Color("0e1636"), Color("24305e"), Color("8fa8ff"), 0.26, 0.24],
	[1.0, Color("070d24"), Color("16224a"), Color("8fa8ff"), 0.3, 0.22],
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
	# (a little less than before the sky lit the shade by itself, so the sun
	# reads stronger against it)
	var amb: float = lerpf(a[5], b[5], k) * 0.9
	# sun path; at night the same light becomes the moon
	# the sun barely moves around noon (and the moon around midnight) so shadows
	# stay still while you build; it only sweeps visibly at dawn and dusk
	var ang := _eased_arc(t) * TAU
	# (tipped towards the south, so even at noon it stands about 55° up and
	# every building throws a shadow you can read)
	var sun_dir := Vector3(cos(ang), sin(ang), 0.7).normalized()
	var is_day := sun_dir.y > -0.02
	var light_dir := sun_dir if is_day else Vector3(-sun_dir.x, -sun_dir.y, 0.5).normalized()
	var horizon_fade := smoothstep(-0.02, 0.12, absf(sun_dir.y))
	night = 1.0 - smoothstep(-0.12, 0.15, sun_dir.y)
	sun.light_color = scol
	sun.light_energy = energy * max(horizon_fade, 0.15)
	# the player can swing the whole arc round the compass (Settings > Sun direction)
	var turn := 0.6 + deg_to_rad(float(Game.settings.get("sun_angle", 0.0)))
	sun.look_at_from_position(Vector3.ZERO, -light_dir.rotated(Vector3.UP, turn), Vector3.UP if absf(light_dir.y) < 0.99 else Vector3.BACK)
	env.ambient_light_energy = amb * float(OS.get_environment("CV_AMB")) if OS.get_environment("CV_AMB") != "" else amb
	env.fog_light_color = hor.lerp(top, 0.1)
	# the haze glows towards the sun when it is low
	env.fog_sun_scatter = lerpf(0.1, 0.45, 1.0 - smoothstep(0.05, 0.5, absf(sun_dir.y))) * (1.0 - night)
	# colours drain away in the dark, as they do to the eye
	env.adjustment_saturation = lerpf(1.12, 0.78, night)
	sky_mat.set_shader_parameter("top_col", top)
	sky_mat.set_shader_parameter("hor_col", hor)
	sky_mat.set_shader_parameter("bottom_col", hor.darkened(0.15))
	sky_mat.set_shader_parameter("sun_col", scol)
	sky_mat.set_shader_parameter("night", night)
	city_mat.set_shader_parameter("night", night)
	for m: ShaderMaterial in [city_mat, detail_mat]:
		m.set_shader_parameter("refl_amount", 0.0 if OS.get_environment("CV_NOREFL") != "" else 1.0)
		m.set_shader_parameter("refl_top", top)
		m.set_shader_parameter("refl_hor", hor)
		m.set_shader_parameter("refl_sun_col", scol)
		m.set_shader_parameter("refl_sun_dir", sun.global_transform.basis.z if is_day else Vector3(0, -1, 0))
	detail_mat.set_shader_parameter("night", night)
	if Clouds.material:
		Clouds.material.set_shader_parameter("sun_dir", sun.global_transform.basis.z)
		Clouds.material.set_shader_parameter("sun_light", Vector3(scol.srgb_to_linear().r, scol.srgb_to_linear().g, scol.srgb_to_linear().b) * sun.light_energy)
		Clouds.material.set_shader_parameter("sky_top", top)
		Clouds.material.set_shader_parameter("sky_hor", hor)
		Clouds.material.set_shader_parameter("night", night)
	# fewer windows stay lit as the night gets later
	var nt := fmod(t + 0.15, 1.0)
	var late := clampf(nt / 0.3, 0.0, 1.0) if nt < 0.4 else 0.0
	city_mat.set_shader_parameter("lit_ratio", lerpf(0.8, 0.35, late))
	detail_mat.set_shader_parameter("lit_ratio", lerpf(0.8, 0.35, late))
	water_mat.set_shader_parameter("night", night)
	Wake.material().set_shader_parameter("night", night)
	# bloom only matters for lit windows and lamps, so skip its passes by day
	env.glow_enabled = (night > 0.12 or hyper) and OS.get_environment("CV_NOGLOW") == ""
	if _ao:
		(_ao.mesh.material as ShaderMaterial).set_shader_parameter("night", night)
	Sfx.night = night
