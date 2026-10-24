class_name IslandWorld
extends World
## The island: one continuous landscape the player reshapes with soft brushes,
## the streets drawn over it and the town that grows along them, under the
## sky, sea and light of World.

signal brush_changed
signal history_changed
## something the player should hear about, such as a brush they can't use yet
signal note(text: String, kind: String)
## the island was renamed (here or by a co-op builder)
signal name_changed
## a building was tapped with no brush in hand (null: open ground)
signal inspected(lot: Variant)

const SAVE_PATH := "user://island.json"
## 2: the big maps (version 1 islands were 128 m across, and come back as an
## island in the middle of one)
const SAVE_VERSION := 2
const BRUSHES := ["street", "grow", "green", "clear", "raise", "lower", "smooth", "flatten"]
const SHAPE := ["raise", "lower", "smooth", "flatten"]
const HISTORY := 25

var land: Land
var streets: Streets
var growth: Growth
var town: Town
var cars: Traffic
var folk: People
var wildlife: Life
var ships: Ships
var brush := ""
var brush_radius := 5.0
## how far the Grow brush lets the town grow up: 1 village .. 4 centre
var grow_level := 2
## what the Street brush lays: "main", "avenue" or "highway" (Streets.DRAWN)
var street_kind := "main"
var island_seed := 0
## what the player calls this island (empty: the default name)
var island_name := ""
const NAME_MAX := 24
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
var progress: IslandProgress
var landmarks: Landmarks
var bunting: Bunting
var wilds: Wilds
var yards: Yards
var _broke := false
# the line being drawn with the street brush, and the box a shaping stroke touched
var _path := PackedVector2Array()
var _stroke_lo := Vector2.ZERO
var _stroke_hi := Vector2.ZERO
# the island as it was before each stroke, for undo, and as it was before each undo
# input state
var _touches := {}
var _gesture_prev := {}
var _press_pos := Vector2.ZERO
var _moved := false
var _mouse_buttons := 0
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
	cars = Traffic.new()
	cars.material = city_mat
	cars.streets = streets
	cars.town = town
	add_child(cars)
	folk = People.new()
	folk.material = city_mat
	folk.streets = streets
	folk.town = town
	add_child(folk)
	wildlife = Life.new()
	wildlife.material = city_mat
	wildlife.rig = rig
	wildlife.land = land
	wildlife.town = town
	add_child(wildlife)
	ships = Ships.new()
	ships.material = city_mat
	ships.world = self
	add_child(ships)
	_make_clouds()
	_make_ring()
	sync = IslandSync.new()
	sync.world = self
	add_child(sync)
	progress = IslandProgress.new()
	progress.world = self
	add_child(progress)
	landmarks = Landmarks.new()
	landmarks.world = self
	landmarks.beam_mat = beam_mat
	add_child(landmarks)
	bunting = Bunting.new()
	bunting.world = self
	add_child(bunting)
	wilds = Wilds.new()
	wilds.world = self
	add_child(wilds)
	yards = Yards.new()
	yards.world = self
	add_child(yards)
	progress.coins_changed.connect(func():
		if _save_timer <= 0.0:
			_save_timer = 15.0)
	_load()
	rig.limit = Land.HALF - 8.0
	rig.focus(_home())
	rig._t_dist = 70.0
	rig.dist = 70.0


func _exit_tree() -> void:
	if Net.island == self:
		Net.island = null
		# a shared island stays in its room
		if Net.in_room():
			Net.leave_room()


func new_island(s: int, map_kind := "river") -> void:
	island_seed = s
	island_name = ""
	name_changed.emit()
	_undo.clear()
	_redo.clear()
	history_changed.emit()
	streets.clear()
	landmarks.reset()
	town.clear()
	town.keep_stages({})
	land.generate(s, map_kind)
	_update_maps()
	cars.clear()
	folk.clear()
	wildlife.reset()
	rig.focus(_home())
	_save()


func _load() -> void:
	var data: Variant = null
	if FileAccess.file_exists(SAVE_PATH):
		data = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if data is Dictionary and data.has("seed"):
		_apply_save(data)
	else:
		new_island(randi() % 1000000)


## Where the camera starts: the middle of the town, or of the map.
func _home() -> Vector3:
	if streets.streets.is_empty():
		var sp := land.start_point()
		return Vector3(sp.x, 0, sp.y)
	var c := Vector2.ZERO
	for st: Streets.Street in streets.streets:
		c += (st.lo + st.hi) * 0.5
	c /= streets.streets.size()
	return Vector3(c.x, 0, c.y)


## Your own island again (after leaving a co-op room).
func load_own() -> void:
	sync.end()
	_load()


func to_dict() -> Dictionary:
	return {"v": SAVE_VERSION, "map": land.kind, "t": Time.get_unix_time_from_system(), "seed": island_seed, "land": land.edits(),
		"streets": streets.to_data(), "zone": land.zone_edits(), "green": land.green_edits(), "level": land.level_edits(),
		"progress": progress.to_dict(), "marks": landmarks.to_dict(), "stages": town.stages(), "name": island_name}


func _apply_save(data: Dictionary) -> void:
	_undo.clear()
	_redo.clear()
	history_changed.emit()
	growth.stop()
	town.clear()
	var sg: Variant = data.get("stages", {})
	town.keep_stages(sg if sg is Dictionary else {})
	island_seed = int(data.seed)
	island_name = str(data.get("name", "")).left(NAME_MAX)
	name_changed.emit()
	var old := int(data.get("v", 1)) < 2
	var map_kind := "legacy" if old else str(data.get("map", "island"))
	if not map_kind in Land.KINDS and map_kind != "legacy":
		map_kind = "island"
	land.generate(island_seed, map_kind, false)
	if old:
		# the ground samples of a 128 m island, moved to where they lie now
		for layer in ["land", "zone", "green", "level"]:
			if data.get(layer) is Dictionary:
				data[layer] = Land.legacy_cells(data[layer])
	var ed: Variant = data.get("land", {})
	land.apply_edits(ed if ed is Dictionary else {})
	var st: Variant = data.get("streets", [])
	streets.from_data(st if st is Array else [])
	var zn: Variant = data.get("zone", {})
	land.apply_zone(zn if zn is Dictionary else {})
	var gn: Variant = data.get("green", {})
	land.apply_green(gn if gn is Dictionary else {})
	var lv: Variant = data.get("level", {})
	land.apply_level(lv if lv is Dictionary else {})
	land.finish()
	var mk: Variant = data.get("marks", {})
	landmarks.from_dict(mk if mk is Dictionary else {})
	var pr: Variant = data.get("progress")
	if pr is Dictionary:
		progress.from_dict(pr)
	progress.hush()
	_update_maps()
	cars.clear()
	folk.clear()
	wildlife.reset()
	if rig:
		rig.focus(_home())


## Opens a co-op room's island: its seed, with everything the builders made on it.
func load_room(seed_value: int, state: Variant, map_kind := "island") -> void:
	var d := {"seed": seed_value, "v": SAVE_VERSION, "map": map_kind}
	if state is Dictionary:
		for layer in ["land", "zone", "green", "level"]:
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
		d["name"] = str(state.get("name", ""))
	_apply_save(d)
	sync.begin()


## Renames the island: saved with it, and shared with everyone in a co-op room.
func set_island_name(text: String) -> void:
	text = text.strip_edges().left(NAME_MAX)
	if text == island_name:
		return
	island_name = text
	name_changed.emit()
	if Net.in_room():
		Firebase.db_put("rooms/%s/island/name" % Net.room_code, text)
	else:
		_save()


func display_name() -> String:
	return island_name if island_name != "" else "Your city"


func _save() -> void:
	# a shared island lives in its room; your own stays as you left it, with
	# the coins and goals you earned while away
	var data := to_dict()
	if Net.in_room():
		var own: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH)) if FileAccess.file_exists(SAVE_PATH) else null
		if not own is Dictionary:
			return
		own["progress"] = progress.to_dict()
		data = own
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
		pull_cloud(false)
		return
	_cloud_timer -= delta
	if _cloud_timer <= 0.0:
		_cloud_timer = 60.0
		save_cloud()


## Brings in your account's island if it is newer than this one (or whenever, if `force`).
func pull_cloud(force: bool) -> void:
	if not Firebase.signed_in or Net.in_room():
		return
	var r: Dictionary = await Firebase.db_get("users/%s/island" % Firebase.uid)
	if r.ok and r.data is Dictionary and r.data.has("seed") and (force or float(r.data.get("t", 0.0)) > _local_time() + 5.0):
		_apply_save(r.data)
		var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify(r.data))
		note.emit("Your city was brought in from your account", "info")


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
	if id != brush and not progress.can_use(id):
		note.emit(progress.unlock_text(id), "warn")
		Sfx.play("error", 1.0, -6.0)
		return
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
	# the lighthouse beam shines in the air only: no light patches swept over the ground and sea
	_update_beams(PackedVector4Array())
	for c in _clouds:
		c.position.x += c.get_meta("speed") * delta
		if c.position.x > 300.0:
			c.position.x = -300.0
	sun.directional_shadow_max_distance = clampf(rig.dist * 2.4, 32.0, 380.0)
	_draw_ring()


func _apply_brush(at: Vector3, delta: float) -> void:
	var r := brush_radius
	var c := Vector2(at.x, at.z)
	_stroke_did = true
	_stroke_lo = _stroke_lo.min(c - Vector2(r, r))
	_stroke_hi = _stroke_hi.max(c + Vector2(r, r))
	if brush in SHAPE and not progress.spend(IslandProgress.SHAPE_COST * delta):
		if not _broke:
			_broke = true
			note.emit("Not enough coins to reshape the land: the town pays as it grows", "warn")
			Sfx.play("error", 1.0, -6.0)
		return
	match brush:
		"raise":
			land.sculpt(at, r, 2.2 * delta)
		"lower":
			land.sculpt(at, r, -2.2 * delta)
		"smooth":
			land.smooth(at, r, 6.0 * delta)
		"flatten":
			land.flatten(at, r, _stroke_level, 5.0 * delta)
		"grow", "green":
			_paint_town(at, 4.0 * delta)
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


## The Grow and Green brushes cover more ground than the shaping ones: enough
## to reach past a street's pavements to where its houses and side streets go.
func _zone_radius() -> float:
	return brush_radius * 1.4 + 1.5


## Paint where the town should grow (Green: as parks and gardens, which are
## still town, its streets running through them).
func _paint_town(at: Vector3, amount: float) -> void:
	var r := _zone_radius()
	var c := Vector2(at.x, at.z)
	land.paint_zone(at, r, amount)
	land.paint_green(at, r, amount if brush == "green" else -amount)
	if brush == "grow":
		land.paint_level(at, r, grow_level, amount * 2.0)
	# keep the town growing towards the brush without restarting its search
	growth.nudge(c)
	town.zone_changed(c, r)
	_save_timer = 1.0


## Whether the town has a street to grow from within reach of the brush at
## `c`: it only ever grows outwards from streets already there.
func can_grow_at(c: Vector2) -> bool:
	var r := _zone_radius() + 2.0
	for st: Streets.Street in streets.streets:
		if st.near_box(c, r) and st.closest(c).x < r:
			return true
	return false


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
		var hw: float = Streets.KINDS[street_kind].w
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
	# Grow and Green show green where the town can spread, amber where no
	# street is near enough to grow from
	var tint := Color(1, 1, 1, 0.8)
	if brush == "grow" or brush == "green":
		tint = Color(0.55, 1.0, 0.6, 0.9) if can_grow_at(Vector2(at.x, at.z)) else Color(1.0, 0.72, 0.35, 0.9)
	(_ring.material_override as StandardMaterial3D).albedo_color = tint
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
		"grow", "green":
			return _zone_radius()
	return brush_radius


func _hover_at(screen: Vector2) -> void:
	_ring_at = land.raycast(rig.cam.project_ray_origin(screen), rig.cam.project_ray_normal(screen))


# ------------------------------------------------------------------ input

## A tap with no brush in hand asks what stands there.
func _tap(screen: Vector2) -> void:
	if brush != "":
		return
	inspected.emit(town.lot_on_ray(rig.cam.project_ray_origin(screen), rig.cam.project_ray_normal(screen)))


func _begin_stroke(screen: Vector2) -> void:
	_hover_at(screen)
	if brush == "" or _ring_at == null:
		return
	_stroke = true
	_stroke_did = false
	_broke = false
	_undo.append(snapshot())
	_stroke_level = land.height_at(_ring_at.x, _ring_at.z)
	_stroke_lo = Vector2(INF, INF)
	_stroke_hi = Vector2(-INF, -INF)
	_path = PackedVector2Array()
	if brush == "street":
		_extend_path(_ring_at)
	elif brush == "grow" or brush == "green":
		# a single tap already marks the spot clearly enough to build on
		_stroke_did = true
		_stroke_lo = Vector2(_ring_at.x, _ring_at.z)
		_stroke_hi = _stroke_lo
		_paint_town(_ring_at, 0.55)


func _end_stroke() -> void:
	if not _stroke:
		return
	_stroke = false
	if brush == "street":
		var cost := _path_length(_path) * IslandProgress.STREET_COST * float(Streets.DRAWN[street_kind])
		if progress.coins < cost:
			note.emit("Not enough coins for that %s (%d)" % ["street" if street_kind == "main" else street_kind, ceili(cost)], "warn")
			Sfx.play("error", 1.0, -6.0)
		elif streets.add_stroke(_path, street_kind) != null:
			progress.spend(cost)
			Sfx.play("road", 1.0, -4.0)
			_stroke_did = true
		_path = PackedVector2Array()
	elif brush in SHAPE and _stroke_lo.x < _stroke_hi.x:
		streets.regrade_in(_stroke_lo, _stroke_hi)
	elif (brush == "grow" or brush == "green") and _stroke_lo.x <= _stroke_hi.x:
		var c := (_stroke_lo + _stroke_hi) * 0.5
		if _ring_at != null:
			c = Vector2(_ring_at.x, _ring_at.z)
		if not can_grow_at(c):
			note.emit("The town grows out from streets: draw one through here with the Street brush", "warn")
		# a fresh look over every street near where the stroke ended
		growth.wake(c)
	# a stroke that changed nothing leaves nothing to undo
	if not _stroke_did:
		_undo.pop_back()
	else:
		if _undo.size() > HISTORY:
			_undo.pop_front()
		_redo.clear()
		history_changed.emit()


static func _path_length(p: PackedVector2Array) -> float:
	var m := 0.0
	for i in range(1, p.size()):
		m += p[i].distance_to(p[i - 1])
	return m


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
				_moved = true
				_path = PackedVector2Array()
				_end_stroke()
				_gesture_prev = {}
		else:
			_touches.erase(event.index)
			if _touches.is_empty():
				_end_stroke()
				if not _moved:
					_tap(event.position)
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
					if not _moved:
						_tap(event.position)
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
