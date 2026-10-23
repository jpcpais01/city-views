class_name World
extends Node3D
## The 3D island: environment, day/night, terrain, buildings, traffic, clouds, input and effects.

signal hover_changed(tile: Vector2i, reason: String)
signal tool_failed(reason: String)
signal tile_tapped(tile: Vector2i)

const DAY_LENGTH := 420.0

var tool := ""
var time_of_day := 0.3
var night := 0.0

var city_mat: ShaderMaterial
var detail_mat: ShaderMaterial
var water_mat: ShaderMaterial
var beam_mat: StandardMaterial3D
var sky_mat: ShaderMaterial
var env: Environment
var sun: DirectionalLight3D
var rig: CameraRig
var terrain: Terrain
var traffic: Traffic
var life: Life
var people: People
var _tiles := {}
# settled tiles are merged into one mesh per BATCH x BATCH block (a handful of
# draw calls instead of one per tile, which matters a lot for shadows on phones)
const BATCH := 8
var _baked := {}
var _batches := {}
var _batch_dirty := {}
var _batch_urgent := {}
var _spinners: Array = []
var _build_queue: Array[Vector2i] = []
var _queued := {}
var _clouds: Array[Node3D] = []
var _cursor: MeshInstance3D
var _cursor_mat: StandardMaterial3D
var _remote_cursors := {}
var _hover := Vector2i(-1, -1)

# input state
var _touches := {}
var _gesture_prev := {}
var _paint_last := Vector2i(-1, -1)
var _painting := false
var _press_pos := Vector2.ZERO
var _moved := false
var _mouse_buttons := 0
var _last_fail_time := 0.0
var _painted_this_stroke := 0


func _ready() -> void:
	_make_materials()
	_make_environment()
	terrain = Terrain.new()
	terrain.material = city_mat
	add_child(terrain)
	_make_sea()
	traffic = Traffic.new()
	traffic.material = city_mat
	add_child(traffic)
	people = People.new()
	people.material = city_mat
	add_child(people)
	rig = CameraRig.new()
	add_child(rig)
	life = Life.new()
	life.material = city_mat
	life.rig = rig
	add_child(life)
	_make_cursor()
	_make_clouds()
	Game.world_reset.connect(_on_world_reset)
	Game.tile_changed.connect(_on_tile_changed)
	Game.growth_changed.connect(_on_growth_changed)
	Game.income_tick.connect(_on_income)
	Game.seabed_changed.connect(func():
		terrain.build_all()
		_update_shore_tex())
	Net.players_changed.connect(_update_remote_cursors)
	_on_world_reset()


# ------------------------------------------------------------------ setup

func _make_materials() -> void:
	city_mat = ShaderMaterial.new()
	city_mat.shader = load("res://shaders/city.gdshader")
	detail_mat = ShaderMaterial.new()
	detail_mat.shader = load("res://shaders/city_detail.gdshader")
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
	beam_mat = StandardMaterial3D.new()
	beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_mat.vertex_color_use_as_albedo = true
	beam_mat.vertex_color_is_srgb = true
	beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	beam_mat.no_depth_test = false


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
	env.fog_density = 0.0012
	env.fog_aerial_perspective = 0.15
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
	water.mesh = _sea_mesh(40, 350.0)
	water.extra_cull_margin = 2.0
	water.material_override = water_mat
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)
	var floor_mi := MeshInstance3D.new()
	var fm := PlaneMesh.new()
	fm.size = Vector2(700, 700)
	floor_mi.mesh = fm
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.72, 0.7, 0.56)
	fmat.roughness = 1.0
	floor_mi.material_override = fmat
	floor_mi.position.y = Game.SEA_FLOOR - 0.01
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


func _make_cursor() -> void:
	var mk := MeshKit.new()
	var t := 0.1
	for s in [-1.0, 1.0]:
		mk.rbox(Vector3(s * (1.0 - t * 0.5), 0.05, 0), Vector3(t, 0.1, 2.0), 0.04, Color.WHITE)
		mk.rbox(Vector3(0, 0.05, s * (1.0 - t * 0.5)), Vector3(2.0 - t * 2.0, 0.1, t), 0.04, Color.WHITE)
	_cursor_mat = StandardMaterial3D.new()
	_cursor_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_cursor_mat.albedo_color = Color(1, 1, 1, 0.85)
	_cursor_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_cursor_mat.no_depth_test = true
	_cursor_mat.render_priority = 2
	_cursor = MeshInstance3D.new()
	_cursor.mesh = mk.commit()
	_cursor.material_override = _cursor_mat
	_cursor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cursor.visible = false
	add_child(_cursor)


func _make_clouds() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in 9:
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
		mi.position = Vector3(rng.randf_range(-120, 120), rng.randf_range(22, 30), rng.randf_range(-120, 120))
		mi.scale = Vector3.ONE * rng.randf_range(0.8, 1.4)
		mi.set_meta("speed", rng.randf_range(0.8, 1.6))
		add_child(mi)
		_clouds.append(mi)


# ------------------------------------------------------------------ tiles

## Distance-to-land map the water shader uses for shore foam and calmer shallows.
func _update_shore_tex() -> void:
	if Game.shore.size() != Game.N * Game.N:
		return
	var img := Image.create_empty(Game.N, Game.N, false, Image.FORMAT_L8)
	for z in Game.N:
		for x in Game.N:
			var v := Game.shore[Game.idx(x, z)] / 8.0
			img.set_pixel(x, z, Color(v, v, v))
	water_mat.set_shader_parameter("shore_tex", ImageTexture.create_from_image(img))
	water_mat.set_shader_parameter("grid_size", Game.N * Game.TILE)


func _on_world_reset() -> void:
	_update_shore_tex()
	for n in _tiles.values():
		n.queue_free()
	_tiles.clear()
	for pair in _batches.values():
		for mi in pair:
			mi.queue_free()
	_batches.clear()
	_baked.clear()
	_batch_dirty.clear()
	_batch_urgent.clear()
	_spinners.clear()
	_build_queue.clear()
	_queued.clear()
	terrain.build_all()
	traffic.clear()
	people.clear()
	life.reset()
	# populate from the centre outwards so the island "blooms" into view
	var order: Array[Vector2i] = []
	for z in Game.N:
		for x in Game.N:
			if Game.knd(x, z) != Game.K.EMPTY:
				order.append(Vector2i(x, z))
	var c := Vector2(Game.N * 0.5, Game.N * 0.5)
	order.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return Vector2(a).distance_squared_to(c) < Vector2(b).distance_squared_to(c))
	for t in order:
		_queue(t)
	rig.focus(_city_centre())


func _city_centre() -> Vector3:
	var sum := Vector3.ZERO
	var n := 0
	for z in Game.N:
		for x in Game.N:
			var k := Game.knd(x, z)
			if k != Game.K.EMPTY and k != Game.K.TREE:
				sum += Game.tile_center(x, z)
				n += 1
	return sum / n if n > 0 else Vector3.ZERO


func _queue(t: Vector2i) -> void:
	if not _queued.has(t):
		_queued[t] = true
		_build_queue.append(t)


func _rebuild(t: Vector2i, anim := "") -> void:
	if _tiles.has(t):
		var old: Node3D = _tiles[t]
		_remove_spinners(old)
		old.queue_free()
		_tiles.erase(t)
	if _baked.erase(t):
		# re-merge this frame so the old version never shows next to the new one
		_batch_urgent[_batch_of(t)] = true
	var node := CityGen.build(t.x, t.y, city_mat, beam_mat)
	if node == null:
		return
	add_child(node)
	_tiles[t] = node
	_collect_spinners(node)
	if anim == "":
		_bake(t, node)
		return
	var tw: Tween
	match anim:
		"pop":
			node.scale = Vector3(0.7, 0.05, 0.7)
			tw = create_tween()
			tw.tween_property(node, "scale", Vector3.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		"grow":
			node.scale = Vector3(1.0, 0.3, 1.0)
			tw = create_tween()
			tw.tween_property(node, "scale", Vector3(1.04, 1.08, 1.04), 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			tw.tween_property(node, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_SINE)
		"fade":
			node.scale = Vector3.ONE * 0.6
			tw = create_tween()
			tw.tween_property(node, "scale", Vector3.ONE, 0.5).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	if tw:
		tw.finished.connect(func(): _bake(t, node))
	else:
		_bake(t, node)


func _batch_of(t: Vector2i) -> Vector2i:
	return Vector2i(t.x / BATCH, t.y / BATCH)


## Hands a settled tile's static mesh to its block; the block re-merges soon.
func _bake(t: Vector2i, node: Node3D) -> void:
	if not is_instance_valid(node) or _tiles.get(t) != node:
		return
	node.scale = Vector3.ONE
	var body := node.get_node_or_null("Body") as MeshInstance3D
	if body == null or not body.has_meta("arrays"):
		return
	var arr: Array = body.get_meta("arrays")
	if (arr[0] as PackedVector3Array).is_empty() and (arr[4] as PackedVector3Array).is_empty() and (arr.size() < 11 or (arr[10] as PackedVector3Array).is_empty()):
		return
	_baked[t] = arr
	_batch_dirty[_batch_of(t)] = true


func _rebuild_batch(b: Vector2i) -> void:
	_batch_dirty.erase(b)
	_batch_urgent.erase(b)
	# slot 0: solid geometry (casts shadows); slot 1: flush details (no shadow pass)
	var sets := [[PackedVector3Array(), PackedVector3Array(), PackedColorArray(), PackedVector2Array()],
		[PackedVector3Array(), PackedVector3Array(), PackedColorArray(), PackedVector2Array()],
		[PackedVector3Array(), PackedVector3Array()],
		[PackedVector3Array(), PackedColorArray(), PackedVector2Array(), PackedVector2Array()]]
	var merged: Array[Vector2i] = []
	for z in range(b.y * BATCH, (b.y + 1) * BATCH):
		for x in range(b.x * BATCH, (b.x + 1) * BATCH):
			var t := Vector2i(x, z)
			if not _baked.has(t):
				continue
			var arr: Array = _baked[t]
			var xf := Transform3D(Basis.IDENTITY, (_tiles[t] as Node3D).position)
			for k in 2:
				var o := k * 4
				sets[k][0].append_array(xf * (arr[o] as PackedVector3Array))
				sets[k][1].append_array(arr[o + 1])
				sets[k][2].append_array(arr[o + 2])
				sets[k][3].append_array(arr[o + 3])
			if arr.size() > 8:
				sets[2][0].append_array(xf * (arr[8] as PackedVector3Array))
				sets[2][1].append_array(arr[9])
			if arr.size() > 10:
				sets[3][0].append_array(xf * (arr[10] as PackedVector3Array))
				sets[3][1].append_array(arr[11])
				sets[3][2].append_array(arr[12])
				sets[3][3].append_array(arr[13])
			merged.append(t)
	var quad: Array = _batches.get(b, [])
	if quad.is_empty():
		# 0: solid geometry, 1: flush details, 2: shadow stand-ins (shadow map only),
		# 3: sphere sprites (draw and cast their own round shadows)
		for k in 4:
			var nmi := MeshInstance3D.new()
			nmi.set_meta("batch", k)
			nmi.cast_shadow = [GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
				GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY, GeometryInstance3D.SHADOW_CASTING_SETTING_ON][k]
			add_child(nmi)
			quad.append(nmi)
		_batches[b] = quad
	for k in 4:
		var mi: MeshInstance3D = quad[k]
		var v: PackedVector3Array = sets[k][0]
		if v.is_empty():
			mi.mesh = null
			continue
		if k == 3:
			var bm := ArrayMesh.new()
			bm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, MeshKit.blob_arrays(v, sets[3][1], sets[3][2], sets[3][3]))
			bm.surface_set_material(0, MeshKit.blob_material())
			bm.custom_aabb = MeshKit._blob_aabb(v, sets[3][3])
			mi.mesh = bm
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = v
		arrays[Mesh.ARRAY_NORMAL] = sets[k][1]
		if k < 2:
			arrays[Mesh.ARRAY_COLOR] = sets[k][2]
			arrays[Mesh.ARRAY_TEX_UV] = sets[k][3]
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, [city_mat, detail_mat, CityGen.shadow_material()][k])
		mi.mesh = mesh
	# the merged copy is drawn now, so the per-tile bodies can go
	for t in merged:
		for part in ["Body", "Shadow", "Blobs"]:
			var n := (_tiles[t] as Node3D).get_node_or_null(part)
			if n:
				n.queue_free()


func _collect_spinners(node: Node) -> void:
	for c in node.get_children():
		if c.has_meta("spin_axis"):
			_spinners.append(c)
		_collect_spinners(c)


func _remove_spinners(node: Node) -> void:
	for c in node.get_children():
		if c.has_meta("spin_axis"):
			_spinners.erase(c)
		_remove_spinners(c)


func _on_tile_changed(x: int, z: int) -> void:
	var t := Vector2i(x, z)
	terrain.tile_changed(x, z)
	traffic.mark_dirty()
	people.mark_dirty()
	_rebuild(t, "pop")
	_dust(t)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dz == 0:
				continue
			var n := Vector2i(x + dx, z + dz)
			if Game.inside(n.x, n.y) and Game.knd(n.x, n.y) != Game.K.EMPTY:
				_rebuild(n)


func _on_growth_changed(x: int, z: int, grew: bool) -> void:
	var t := Vector2i(x, z)
	_rebuild(t, "grow" if grew else "fade")
	if grew:
		_sparkle(t)
		if _on_screen(Game.tile_center(x, z)):
			Sfx.play("grow", 1.0 + Game.grw(x, z) * 0.12, -6.0)
	for d in CityGen.DIRS:
		var n := t + d
		if Game.inside(n.x, n.y) and Game.is_building(Game.knd(n.x, n.y)):
			_rebuild(n)


func _on_screen(p: Vector3) -> bool:
	var cam := rig.cam
	if cam.is_position_behind(p):
		return false
	var s := cam.unproject_position(p)
	return get_viewport().get_visible_rect().has_point(s)


# ------------------------------------------------------------------ effects

func _dust(t: Vector2i) -> void:
	var p := CPUParticles3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.12
	sm.height = 0.24
	sm.radial_segments = 8
	sm.rings = 4
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.98, 0.95, 0.88)
	m.roughness = 1.0
	sm.material = m
	p.mesh = sm
	p.amount = 14
	p.one_shot = true
	p.explosiveness = 0.95
	p.lifetime = 0.7
	p.direction = Vector3.UP
	p.spread = 80.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 2.4
	p.gravity = Vector3(0, -3.0, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	p.scale_amount_curve = curve
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(0.8, 0.05, 0.8)
	p.position = Game.tile_center(t.x, t.y) + Vector3(0, 0.15, 0)
	add_child(p)
	p.emitting = true
	get_tree().create_timer(1.2).timeout.connect(p.queue_free)


func _sparkle(t: Vector2i) -> void:
	var p := CPUParticles3D.new()
	var qm := SphereMesh.new()
	qm.radius = 0.06
	qm.height = 0.12
	qm.radial_segments = 6
	qm.rings = 3
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.9, 0.45)
	qm.material = m
	p.mesh = qm
	p.amount = 16
	p.one_shot = true
	p.explosiveness = 0.8
	p.lifetime = 1.1
	p.direction = Vector3.UP
	p.spread = 35.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 3.0
	p.gravity = Vector3(0, -1.0, 0)
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	p.scale_amount_curve = curve
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(0.7, 0.3, 0.7)
	p.position = Game.tile_center(t.x, t.y) + Vector3(0, 0.8, 0)
	add_child(p)
	p.emitting = true
	get_tree().create_timer(1.6).timeout.connect(p.queue_free)


func _on_income(amount: float) -> void:
	# float a little "+coins" over a random visible building
	var tries := 20
	while tries > 0:
		tries -= 1
		var x := randi_range(1, Game.N - 2)
		var z := randi_range(1, Game.N - 2)
		if Game.is_building(Game.knd(x, z)) and Game.grw(x, z) > 0:
			var p := Game.tile_center(x, z) + Vector3(0, 1.6 + Game.grw(x, z) * 0.8, 0)
			if not _on_screen(p):
				continue
			var l := Label3D.new()
			l.text = "+%d" % int(round(amount))
			l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			l.no_depth_test = true
			l.font_size = 64
			l.pixel_size = 0.006
			l.outline_size = 14
			l.modulate = Color(1.0, 0.86, 0.3)
			l.outline_modulate = Color(0.45, 0.3, 0.1)
			l.position = p
			add_child(l)
			var tw := create_tween()
			tw.set_parallel(true)
			tw.tween_property(l, "position", p + Vector3(0, 1.4, 0), 1.6).set_ease(Tween.EASE_OUT)
			tw.tween_property(l, "modulate:a", 0.0, 1.6).set_delay(0.5)
			tw.chain().tween_callback(l.queue_free)
			return


# ------------------------------------------------------------------ frame

func _process(delta: float) -> void:
	# build queued tiles within a small time budget per frame
	var start := Time.get_ticks_usec()
	while not _build_queue.is_empty() and Time.get_ticks_usec() - start < 5000:
		var t: Vector2i = _build_queue.pop_front()
		_queued.erase(t)
		_rebuild(t, "fade" if _build_queue.size() < 400 else "")
	for b in _batch_urgent.keys():
		_rebuild_batch(b)
	var n := 0
	for b in _batch_dirty.keys():
		_rebuild_batch(b)
		n += 1
		if n >= 2:
			break
	time_of_day = fmod(time_of_day + delta / DAY_LENGTH, 1.0)
	_update_sky()
	for s in _spinners:
		if not is_instance_valid(s):
			continue
		var mi: MeshInstance3D = s
		mi.rotate_object_local(mi.get_meta("spin_axis"), mi.get_meta("spin_speed") * delta)
		if mi.has_meta("night_only"):
			mi.visible = night > 0.3
	for c in _clouds:
		c.position.x += c.get_meta("speed") * delta
		if c.position.x > 160.0:
			c.position.x = -160.0
	sun.directional_shadow_max_distance = clampf(rig.dist * 1.4, 28.0, 80.0)
	if _cursor.visible:
		var pulse := 0.7 + 0.3 * sin(Time.get_ticks_msec() * 0.008)
		_cursor_mat.albedo_color.a = 0.55 + 0.35 * pulse
	_animate_remote_cursors(delta)


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


# ------------------------------------------------------------------ cursor & multiplayer

func _set_hover(t: Vector2i) -> void:
	if t == _hover:
		return
	_hover = t
	Net.set_cursor(t)
	if not Game.inside(t.x, t.y) or tool == "":
		_cursor.visible = false
		hover_changed.emit(t, "")
		return
	_cursor.visible = true
	var top := Game.tile_y(t.x, t.y)
	if Game.knd(t.x, t.y) == Game.K.ROAD or Game.lvl(t.x, t.y) == 0:
		top = max(top, Game.LEVEL_Y[Game.road_level(t.x, t.y)])
	var c := Game.tile_center(t.x, t.y)
	_cursor.position = Vector3(c.x, top + 0.02, c.z)
	var reason := Game.check_tool(tool, t.x, t.y)
	var ok := reason == "" or reason == "already"
	_cursor_mat.albedo_color = Color(0.55, 1.0, 0.7, 0.8) if ok else Color(1.0, 0.45, 0.4, 0.8)
	if tool == "bulldoze" and ok:
		_cursor_mat.albedo_color = Color(1.0, 0.75, 0.35, 0.8)
	hover_changed.emit(t, reason)


func _update_remote_cursors() -> void:
	var seen := {}
	for p in Net.active_players():
		var id: String = p.id
		if id == Firebase.uid:
			continue
		seen[id] = true
		if not _remote_cursors.has(id):
			var root := Node3D.new()
			var mi := MeshInstance3D.new()
			mi.mesh = _cursor.mesh
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.albedo_color = Color(str(p.get("color", "ffffff")))
			mi.material_override = m
			root.add_child(mi)
			var l := Label3D.new()
			l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			l.no_depth_test = true
			l.font_size = 48
			l.pixel_size = 0.008
			l.outline_size = 12
			l.position = Vector3(0, 1.6, 0)
			root.add_child(l)
			var pin := MeshInstance3D.new()
			var pk := MeshKit.new()
			pk.blob(Vector3(0, 1.05, 0), Vector3(0.22, 0.22, 0.22), Color(str(p.get("color", "ffffff"))))
			pk.cone(Vector3(0, 0.45, 0), 0.12, 0.5, 8, Color(str(p.get("color", "ffffff"))))
			pin.mesh = pk.commit(city_mat)
			root.add_child(pin)
			add_child(root)
			_remote_cursors[id] = root
		var node: Node3D = _remote_cursors[id]
		(node.get_child(1) as Label3D).text = str(p.get("name", "Builder"))
		var cx := int(p.get("cx", -1))
		var cz := int(p.get("cz", -1))
		node.visible = Game.inside(cx, cz)
		if node.visible:
			node.set_meta("goal", Game.tile_center(cx, cz) + Vector3(0, 0.05, 0))
	for id in _remote_cursors.keys():
		if not seen.has(id):
			_remote_cursors[id].queue_free()
			_remote_cursors.erase(id)


func _animate_remote_cursors(delta: float) -> void:
	for node in _remote_cursors.values():
		if node.has_meta("goal"):
			node.position = node.position.lerp(node.get_meta("goal"), 1.0 - exp(-delta * 8.0))
			node.get_child(2).position.y = sin(Time.get_ticks_msec() * 0.004) * 0.1


# ------------------------------------------------------------------ input

func set_tool(id: String) -> void:
	tool = id
	var h := _hover
	_hover = Vector2i(-99, -99)
	_set_hover(h)


func _paint_at(t: Vector2i) -> void:
	if not Game.inside(t.x, t.y):
		return
	if _paint_last.x >= 0 and t != _paint_last:
		# walk a 4-connected line so dragged roads always link up
		var cur := _paint_last
		var guard := 0
		while cur != t and guard < 200:
			guard += 1
			var dx := t.x - cur.x
			var dz := t.y - cur.y
			if absi(dx) >= absi(dz):
				cur.x += signi(dx)
			else:
				cur.y += signi(dz)
			_apply_one(cur)
	elif _paint_last.x < 0:
		_apply_one(t)
	_paint_last = t


func _apply_one(t: Vector2i) -> void:
	var reason := Game.check_tool(tool, t.x, t.y)
	if reason == "already":
		return
	if reason != "":
		if Time.get_ticks_msec() - _last_fail_time > 1200:
			_last_fail_time = Time.get_ticks_msec()
			tool_failed.emit(reason)
			Sfx.play("click", 0.6, -4.0)
		return
	var lvl_before := Game.lvl(t.x, t.y)
	if Game.apply_tool(tool, t.x, t.y):
		_painted_this_stroke += 1
		var pitch := 1.0 + mini(_painted_this_stroke, 12) * 0.03
		match tool:
			"road": Sfx.play("road", pitch, -2.0)
			"bulldoze": Sfx.play("bulldoze", 1.0, -3.0)
			"raise", "lower": Sfx.play("place", 0.8 if tool == "lower" else 1.1, -2.0)
			"tree": Sfx.play("pop", 1.3 * pitch, -5.0)
			_: Sfx.play("place", pitch, 0.0)
		if Game.lvl(t.x, t.y) != lvl_before:
			_hover = Vector2i(-99, -99)
	_set_hover(t)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_on_touch(event)
	elif event is InputEventScreenDrag:
		_on_drag(event)
	elif event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION:
		_on_mouse_button(event)
	elif event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION:
		_on_mouse_motion(event)
	elif event is InputEventMagnifyGesture:
		rig.zoom(1.0 / event.factor)
	elif event is InputEventPanGesture:
		rig.pan_screen(event.delta * 8.0)


func _on_touch(e: InputEventScreenTouch) -> void:
	if e.pressed:
		_touches[e.index] = e.position
		if _touches.size() == 1:
			_press_pos = e.position
			_moved = false
			_painted_this_stroke = 0
			if tool != "":
				_painting = true
				_paint_last = Vector2i(-1, -1)
				var t := rig.pick_tile(e.position)
				_set_hover(t)
				_paint_at(t)
		else:
			_painting = false
			Game.end_stroke()
			_gesture_prev = {}
	else:
		_touches.erase(e.index)
		if _touches.is_empty():
			if not _moved and tool == "":
				tile_tapped.emit(rig.pick_tile(e.position))
			_painting = false
			_paint_last = Vector2i(-1, -1)
			Game.end_stroke()
		_gesture_prev = {}


func _on_drag(e: InputEventScreenDrag) -> void:
	_touches[e.index] = e.position
	if _touches.size() == 1:
		if e.position.distance_to(_press_pos) > 10.0:
			_moved = true
		if _painting:
			var t := rig.pick_tile(e.position)
			_set_hover(t)
			_paint_at(t)
		elif _moved:
			rig.pan_screen(e.relative)
	elif _touches.size() >= 2:
		var keys := _touches.keys()
		var p0: Vector2 = _touches[keys[0]]
		var p1: Vector2 = _touches[keys[1]]
		var mid := (p0 + p1) * 0.5
		var dist := p0.distance_to(p1)
		var ang := (p1 - p0).angle()
		if not _gesture_prev.is_empty():
			rig.pan_screen(mid - _gesture_prev.mid)
			if dist > 1.0 and _gesture_prev.dist > 1.0:
				rig.zoom(_gesture_prev.dist / dist)
			rig.rotate_by(wrapf(ang - _gesture_prev.ang, -PI, PI))
		_gesture_prev = {"mid": mid, "dist": dist, "ang": ang}


func _on_mouse_button(e: InputEventMouseButton) -> void:
	match e.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			rig.zoom(0.9)
		MOUSE_BUTTON_WHEEL_DOWN:
			rig.zoom(1.1)
		MOUSE_BUTTON_LEFT:
			if e.pressed:
				_press_pos = e.position
				_moved = false
				_painted_this_stroke = 0
				if tool != "":
					_painting = true
					_paint_last = Vector2i(-1, -1)
					_paint_at(rig.pick_tile(e.position))
			else:
				if not _moved and tool == "":
					tile_tapped.emit(rig.pick_tile(e.position))
				_painting = false
				_paint_last = Vector2i(-1, -1)
				Game.end_stroke()
	if e.pressed:
		_mouse_buttons |= 1 << e.button_index
	else:
		_mouse_buttons &= ~(1 << e.button_index)


func _on_mouse_motion(e: InputEventMouseMotion) -> void:
	var t := rig.pick_tile(e.position)
	_set_hover(t)
	if _mouse_buttons & (1 << MOUSE_BUTTON_RIGHT):
		rig.rotate_by(-e.relative.x * 0.008)
	elif _mouse_buttons & (1 << MOUSE_BUTTON_MIDDLE):
		rig.pan_screen(e.relative)
	elif _mouse_buttons & (1 << MOUSE_BUTTON_LEFT):
		if e.position.distance_to(_press_pos) > 6.0:
			_moved = true
		if _painting:
			_paint_at(t)
		elif _moved:
			rig.pan_screen(e.relative)
