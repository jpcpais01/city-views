class_name IslandWorld
extends World
## The new, tile-free island (preview while it grows into the full game): the
## same sky, sea, light and camera as the classic town, over one continuous
## landscape the player reshapes with soft brushes.

signal brush_changed
signal history_changed

const SAVE_PATH := "user://island.json"
const BRUSHES := ["street", "grow", "green", "clear", "raise", "lower", "smooth", "flatten"]
const SHAPE := ["raise", "lower", "smooth", "flatten"]
const HISTORY := 25

var land: Land
var streets: Streets
var growth: Growth
var town: Town
var cars: IslandTraffic
var folk: IslandPeople
var wildlife: IslandLife
var brush := ""
var brush_radius := 5.0
var island_seed := 0
var _stroke := false
var _stroke_level := 0.0
var _stroke_screen := Vector2.ZERO
var _ring: MeshInstance3D
var _ring_mesh: ImmediateMesh
var _ring_at: Variant = null
var _shore_dirty := false
var _coast_dirty := false
var _shore_wait := 0.0
var _save_timer := 0.0
var _sculpt_sound := 0.0
var _cloud_timer := 60.0
var _cloud_checked := false
var sync: IslandSync
# the line being drawn with the street brush, and the box a shaping stroke touched
var _path := PackedVector2Array()
var _stroke_lo := Vector2.ZERO
var _stroke_hi := Vector2.ZERO
# the island as it was before each stroke, for undo, and as it was before each undo
var _undo: Array = []
var _redo: Array = []
var _stroke_did := false


func _ready() -> void:
	Net.island = self
	_make_materials()
	_make_environment()
	land = Land.new()
	land.material = ground_mat
	add_child(land)
	streets = Streets.new()
	streets.land = land
	streets.material = city_mat
	streets.changed.connect(func(): _shore_dirty = true)
	add_child(streets)
	growth = Growth.new()
	growth.land = land
	growth.streets = streets
	add_child(growth)
	town = Town.new()
	town.setup(land, streets, city_mat)
	town.reshaped.connect(func(): _shore_dirty = true)
	add_child(town)
	_make_sea()
	rig = CameraRig.new()
	rig.ground_fn = land.height_at
	add_child(rig)
	cars = IslandTraffic.new()
	cars.material = city_mat
	cars.streets = streets
	cars.town = town
	add_child(cars)
	folk = IslandPeople.new()
	folk.material = city_mat
	folk.streets = streets
	folk.town = town
	add_child(folk)
	wildlife = IslandLife.new()
	wildlife.material = city_mat
	wildlife.rig = rig
	wildlife.land = land
	wildlife.town = town
	add_child(wildlife)
	_make_clouds()
	_make_ring()
	sync = IslandSync.new()
	sync.world = self
	add_child(sync)
	_load()
	rig.focus(Vector3.ZERO)
	rig._t_dist = 70.0
	rig.dist = 70.0


func _exit_tree() -> void:
	if Net.island == self:
		Net.island = null
		# off to the classic town: a shared island stays in its room
		if Net.in_room():
			Net.leave_room()


func new_island(s: int) -> void:
	island_seed = s
	_undo.clear()
	_redo.clear()
	history_changed.emit()
	streets.clear()
	town.clear()
	land.generate(s)
	_update_maps()
	cars.clear()
	folk.clear()
	wildlife.reset()
	_save()


func _load() -> void:
	var data: Variant = null
	if FileAccess.file_exists(SAVE_PATH):
		data = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if data is Dictionary and data.has("seed"):
		_apply_save(data)
	else:
		new_island(randi() % 1000000)


## Your own island again (after leaving a co-op room).
func load_own() -> void:
	sync.end()
	_load()


func to_dict() -> Dictionary:
	return {"v": 1, "t": Time.get_unix_time_from_system(), "seed": island_seed, "land": land.edits(),
		"streets": streets.to_data(), "zone": land.zone_edits(), "green": land.green_edits()}


func _apply_save(data: Dictionary) -> void:
	_undo.clear()
	_redo.clear()
	history_changed.emit()
	growth.stop()
	town.clear()
	island_seed = int(data.seed)
	land.generate(island_seed)
	var ed: Variant = data.get("land", {})
	land.apply_edits(ed if ed is Dictionary else {})
	var st: Variant = data.get("streets", [])
	streets.from_data(st if st is Array else [])
	var zn: Variant = data.get("zone", {})
	land.apply_zone(zn if zn is Dictionary else {})
	var gn: Variant = data.get("green", {})
	land.apply_green(gn if gn is Dictionary else {})
	_update_maps()
	cars.clear()
	folk.clear()
	wildlife.reset()


## Opens a co-op room's island: its seed, with everything the builders made on it.
func load_room(seed_value: int, state: Variant) -> void:
	var d := {"seed": seed_value}
	if state is Dictionary:
		for layer in ["land", "zone", "green"]:
			var cells := {}
			var src: Variant = state.get(layer, {})
			if src is Dictionary:
				for key in src:
					if str(key).begins_with("c"):
						cells[str(key).substr(1)] = src[key]
			d[layer] = cells
		var list := []
		var sts: Variant = state.get("streets", {})
		if sts is Dictionary:
			for key in sts:
				if sts[key] is Dictionary:
					var sd: Dictionary = sts[key]
					sd["id"] = str(key)
					list.append(sd)
		d["streets"] = list
	_apply_save(d)
	sync.begin()


func _save() -> void:
	# a shared island lives in its room; your own stays as you left it
	if Net.in_room():
		return
	var data := to_dict()
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))
	_cloud_timer = minf(_cloud_timer, 20.0)


## Keeps a copy of your island in your account, and brings back a newer one
## from another device when you sign in.
func _cloud(delta: float) -> void:
	if not Firebase.signed_in or Net.in_room():
		return
	if not _cloud_checked:
		_cloud_checked = true
		var r: Dictionary = await Firebase.db_get("users/%s/island" % Firebase.uid)
		if r.ok and r.data is Dictionary and r.data.has("seed") and float(r.data.get("t", 0.0)) > _local_time() + 5.0:
			_apply_save(r.data)
			var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
			if f:
				f.store_string(JSON.stringify(r.data))
		return
	_cloud_timer -= delta
	if _cloud_timer <= 0.0:
		_cloud_timer = 60.0
		save_cloud()


func save_cloud() -> void:
	if Firebase.signed_in and not Net.in_room():
		Firebase.db_put("users/%s/island" % Firebase.uid, to_dict())


func _local_time() -> float:
	if not FileAccess.file_exists(SAVE_PATH):
		return 0.0
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	return float(d.get("t", 0.0)) if d is Dictionary else 0.0


## Ground maps for the shaders; the shoreline one only when the coast may have moved.
func _update_maps(coast := true) -> void:
	if coast:
		water_mat.set_shader_parameter("shore_tex", ImageTexture.create_from_image(land.shore_image(16.0)))
		water_mat.set_shader_parameter("grid_size", Land.SIZE)
	var ht := ImageTexture.create_from_image(land.height_image())
	for m in [city_mat, detail_mat]:
		m.set_shader_parameter("height_tex", ht)
		m.set_shader_parameter("height_range", Vector2(Land.MAP_SCALE, Land.MAP_BIAS))
		m.set_shader_parameter("grid_size", Land.SIZE)


func set_brush(id: String) -> void:
	brush = id if id != brush else ""
	land.show_zone = brush == "grow" or brush == "green"
	brush_changed.emit()


# ------------------------------------------------------------------ frame

func _process(delta: float) -> void:
	land.rebuild_dirty()
	_shore_wait -= delta
	# while the town grows, the shadows and maps catch up about once a second
	if _shore_dirty and not _stroke and land.is_settled() and (_shore_wait <= 0.0 or not town.is_busy()):
		_shore_dirty = false
		_shore_wait = 1.0
		land.rebuild_shadow()
		_update_maps(_coast_dirty)
		_coast_dirty = false
		_save_timer = 1.0
	if _save_timer > 0.0:
		_save_timer -= delta
		if _save_timer <= 0.0:
			_save()
	_cloud(delta)
	if _stroke and _ring_at != null:
		if brush == "street":
			_extend_path(_ring_at)
		else:
			_apply_brush(_ring_at, delta)
	time_of_day = fmod(time_of_day + delta / DAY_LENGTH, 1.0)
	_update_sky()
	_update_beams(PackedVector4Array())
	for c in _clouds:
		c.position.x += c.get_meta("speed") * delta
		if c.position.x > 160.0:
			c.position.x = -160.0
	sun.directional_shadow_max_distance = clampf(rig.dist * 2.4, 32.0, 240.0)
	_draw_ring()


func _apply_brush(at: Vector3, delta: float) -> void:
	var r := brush_radius
	var c := Vector2(at.x, at.z)
	_stroke_did = true
	_stroke_lo = _stroke_lo.min(c - Vector2(r, r))
	_stroke_hi = _stroke_hi.max(c + Vector2(r, r))
	match brush:
		"raise":
			land.sculpt(at, r, 2.2 * delta)
		"lower":
			land.sculpt(at, r, -2.2 * delta)
		"smooth":
			land.smooth(at, r, 6.0 * delta)
		"flatten":
			land.flatten(at, r, _stroke_level, 5.0 * delta)
		"grow":
			land.paint_zone(at, r, 2.5 * delta)
			land.paint_green(at, r, -2.5 * delta)
			growth.wake(c)
			town.zone_changed(c, r)
			_save_timer = 1.0
			return
		"green":
			# parks and gardens: still part of the town, its streets run through
			land.paint_zone(at, r, 2.5 * delta)
			land.paint_green(at, r, 2.5 * delta)
			growth.wake(c)
			town.zone_changed(c, r)
			_save_timer = 1.0
			return
		"clear":
			land.paint_zone(at, r * 0.6, -4.0 * delta)
			land.paint_green(at, r * 0.6, -4.0 * delta)
			town.zone_changed(c, r * 0.6)
			if streets.erase_at(c, r * 0.6):
				Sfx.play("bulldoze", 1.0, -8.0, 0.1)
			_save_timer = 1.0
			return
	_shore_dirty = true
	_coast_dirty = true
	_sculpt_sound -= delta
	if _sculpt_sound <= 0.0:
		_sculpt_sound = 0.16
		Sfx.play("road" if brush == "smooth" or brush == "flatten" else "place", 0.7 if brush == "lower" else 1.0, -12.0, 0.15)


# ------------------------------------------------------------------ brush ring

func _make_ring() -> void:
	_ring_mesh = ImmediateMesh.new()
	_ring = MeshInstance3D.new()
	_ring.mesh = _ring_mesh
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1, 1, 1, 0.8)
	m.no_depth_test = true
	m.render_priority = 3
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ring.material_override = m
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)


## A soft white circle lying on the ground under the brush.
func _draw_ring() -> void:
	_ring_mesh.clear_surfaces()
	var w := 0.12 + rig.dist * 0.004
	if brush == "street" and _path.size() >= 2:
		# the line being drawn, as a soft ribbon the width of the street
		var hw: float = Streets.KINDS.main.w
		_ring_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		for i in _path.size():
			var a := _path[maxi(i - 1, 0)]
			var b := _path[mini(i + 1, _path.size() - 1)]
			var t := (b - a).normalized()
			var side := Vector2(-t.y, t.x) * hw
			for p in [_path[i] - side, _path[i] + side]:
				_ring_mesh.surface_add_vertex(Vector3(p.x, maxf(land.height_at(p.x, p.y), 0.0) + 0.1, p.y))
		_ring_mesh.surface_end()
	if brush == "" or _ring_at == null:
		return
	var at: Vector3 = _ring_at
	var segs := 48
	var radius := _ring_radius()
	_ring_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for k in segs + 1:
		var a := TAU * k / segs
		var dir := Vector3(cos(a), 0, sin(a))
		for rr in [radius - w, radius + w]:
			var p: Vector3 = at + dir * rr
			p.y = maxf(land.height_at(p.x, p.z), 0.0) + 0.06
			_ring_mesh.surface_add_vertex(p)
	_ring_mesh.surface_end()


func _ring_radius() -> float:
	match brush:
		"street":
			return Streets.KINDS.main.w + Streets.PAVE
		"clear":
			return brush_radius * 0.6
	return brush_radius


func _hover_at(screen: Vector2) -> void:
	_ring_at = land.raycast(rig.cam.project_ray_origin(screen), rig.cam.project_ray_normal(screen))


# ------------------------------------------------------------------ input

func _begin_stroke(screen: Vector2) -> void:
	_hover_at(screen)
	if brush == "" or _ring_at == null:
		return
	_stroke = true
	_stroke_did = false
	_undo.append(snapshot())
	_stroke_level = land.height_at(_ring_at.x, _ring_at.z)
	_stroke_lo = Vector2(INF, INF)
	_stroke_hi = Vector2(-INF, -INF)
	_path = PackedVector2Array()
	if brush == "street":
		_extend_path(_ring_at)


func _end_stroke() -> void:
	if not _stroke:
		return
	_stroke = false
	if brush == "street":
		if streets.add_stroke(_path) != null:
			Sfx.play("road", 1.0, -4.0)
			_stroke_did = true
		_path = PackedVector2Array()
	elif brush in SHAPE and _stroke_lo.x < _stroke_hi.x:
		streets.regrade_in(_stroke_lo, _stroke_hi)
	# a stroke that changed nothing leaves nothing to undo
	if not _stroke_did:
		_undo.pop_back()
	else:
		if _undo.size() > HISTORY:
			_undo.pop_front()
		_redo.clear()
		history_changed.emit()


# ------------------------------------------------------------------ undo

func snapshot() -> Dictionary:
	return {"land": land.snapshot(), "streets": streets.to_data()}


## Puts the island back as a snapshot had it; the town re-grows its houses.
func restore(snap: Dictionary) -> void:
	growth.stop()
	town.clear()
	land.restore(snap.land)
	streets.from_data(snap.streets)
	cars.clear()
	folk.clear()
	_shore_dirty = true
	_coast_dirty = true
	_save_timer = 0.5


## Another builder reshaped the ground: shadows and the sea's shore follow.
func ground_changed() -> void:
	_shore_dirty = true
	_coast_dirty = true


func can_undo() -> bool:
	return not _undo.is_empty() and not _stroke


func can_redo() -> bool:
	return not _redo.is_empty() and not _stroke


func undo() -> bool:
	if not can_undo():
		return false
	_redo.append(snapshot())
	restore(_undo.pop_back())
	history_changed.emit()
	return true


func redo() -> bool:
	if not can_redo():
		return false
	_undo.append(snapshot())
	restore(_redo.pop_back())
	history_changed.emit()
	return true


func _extend_path(at: Vector3) -> void:
	var p := Vector2(at.x, at.z)
	if _path.is_empty() or _path[_path.size() - 1].distance_to(p) > 0.4:
		_path.append(p)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
			if _touches.size() == 1:
				_press_pos = event.position
				_moved = false
				_begin_stroke(event.position)
			else:
				# a second finger means the camera, not a street
				_path = PackedVector2Array()
				_end_stroke()
				_gesture_prev = {}
		else:
			_touches.erase(event.index)
			if _touches.is_empty():
				_end_stroke()
			_gesture_prev = {}
	elif event is InputEventScreenDrag:
		_touches[event.index] = event.position
		if _touches.size() == 1:
			if event.position.distance_to(_press_pos) > 10.0:
				_moved = true
			if _stroke:
				_hover_at(event.position)
			elif _moved:
				rig.pan_screen(event.relative)
		elif _touches.size() >= 2:
			_two_finger()
	elif event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				rig.zoom(0.9)
			MOUSE_BUTTON_WHEEL_DOWN:
				rig.zoom(1.1)
			MOUSE_BUTTON_LEFT:
				if event.pressed:
					_press_pos = event.position
					_moved = false
					_begin_stroke(event.position)
				else:
					_end_stroke()
		if event.pressed:
			_mouse_buttons |= 1 << event.button_index
		else:
			_mouse_buttons &= ~(1 << event.button_index)
	elif event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION:
		_hover_at(event.position)
		if _mouse_buttons & (1 << MOUSE_BUTTON_RIGHT):
			rig.rotate_by(-event.relative.x * 0.008)
		elif _mouse_buttons & (1 << MOUSE_BUTTON_MIDDLE):
			rig.pan_screen(event.relative)
		elif _mouse_buttons & (1 << MOUSE_BUTTON_LEFT) and not _stroke:
			if event.position.distance_to(_press_pos) > 6.0:
				_moved = true
			if _moved:
				rig.pan_screen(event.relative)
	elif event is InputEventMagnifyGesture:
		rig.zoom(1.0 / event.factor)
	elif event is InputEventPanGesture:
		rig.pan_screen(event.delta * 8.0)


func _two_finger() -> void:
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
