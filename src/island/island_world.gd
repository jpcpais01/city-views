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
const BRUSHES := ["street", "grow", "green", "magic", "clear", "raise", "lower", "smooth", "flatten"]
const SHAPE := ["raise", "lower", "smooth", "flatten"]
const HISTORY := 25

var land: Land
var streets: Streets
var growth: Growth
var town: Town
var cars: Traffic
var lights: StreetLights
var smoke: Smoke
var planes: Planes
var folk: People
var wildlife: Life
var ships: Ships
var brush := ""
var brush_radius := 5.0
## how far the Grow brush lets the town grow up: 1 village .. 4 centre
var grow_level := 2
## the district the Grow brush paints (Land.USES): homes, shops, offices or industry
var grow_use := 0
## what the Street brush lays: "main" or "avenue" (highways come with the
## map, see plan_highways)
var street_kind := "main"
## the Street brush changes roads already there to street_kind instead of
## laying new ones: drag along them (or tap one) to raise or lower them
var street_change := false
var island_seed := 0
## the seed the map's highway network was planned from (see HighwayPlan); 0
## where it wasn't (islands saved with highways the player drew themselves)
var highway_seed := 0
## whether a new map comes with its highways (tests that lay their own turn it off)
static var auto_highways := true
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
# where the shaping brushes moved the coast since it was last worked out (in
# samples; empty: anywhere, so all of it)
var _coast_box := Rect2i()
var _coast_any := false
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
# the Grow and Green brushes: what the stroke began on (it may paint over
# that colour), where it last dabbed, how much it newly painted, and the dab
# under the finger as the ring shows it
var _stroke_over := BrushMask.EMPTY
var _last_dab: Variant = null
var _stroke_claimed := 0
var _mask: BrushMask
var _mask_key := 0
## Change mode: the roads the finger went along, street id -> [Street, from, to]
## samples, and what changing them would do: [[Street, a, b]], net coins
var _change_hits := {}
var change_plan: Array = []
var change_cost := 0.0
var _change_hover := Vector2(INF, INF)
## a glow over the building last tapped, while its card shows
var _picked: MeshInstance3D
var _picked_tw: Tween


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
	town.magicked.connect(_sparkle)
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
	lights = StreetLights.new()
	lights.material = city_mat
	lights.streets = streets
	add_child(lights)
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
	smoke = Smoke.new()
	smoke.town = town
	add_child(smoke)
	planes = Planes.new()
	planes.material = city_mat
	planes.world = self
	add_child(planes)
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
	rig.focus(_home())
	rig._t_dist = 70.0
	rig.dist = 70.0


func _exit_tree() -> void:
	if _save_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_save_task)
		_save_task = -1
	for t in _cloud_tasks:
		WorkerThreadPool.wait_for_task_completion(t)
	_cloud_tasks.clear()
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
	_use_size(Land.size_for(map_kind))
	town.clear()
	town.keep_stages({})
	land.generate(s, map_kind, false)
	if auto_highways:
		plan_highways(default_highway_seed())
	else:
		highway_seed = 0
	land.finish()
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


## Sizes everything that works in map samples for a map `metres` across.
func _use_size(metres: int) -> void:
	Land.use_size(metres)
	if rig:
		rig.limit = Land.HALF - 8.0


## The map's own highway network, the first one it comes with: the same for
## everyone on the same map (co-op builders work out the same one).
func default_highway_seed() -> int:
	return posmod(island_seed * 7919 + 104729, 999983) + 1


## Plans the map's highway network from a seed and lays it, in place of the
## highways there were. Returns how many highways it has.
func plan_highways(seed_value: int) -> int:
	streets.clear_highways()
	highway_seed = seed_value
	var keep: Array = []
	for st: Streets.Street in streets.streets:
		if not st.auto and st.kind != "highway":
			keep.append(st.pts)
	var lines := HighwayPlan.make(land, seed_value, keep)
	for k in lines.size():
		streets.lay_highway(lines[k], "hw%d_%d" % [seed_value, k])
	_shore_dirty = true
	_coast_dirty = true
	_coast_any = true
	return lines.size()


## Rolls a new highway network for the map (the Road tool's Reroll key), as
## many times as the player likes; undo brings the last one back.
func reroll_highways() -> int:
	if _stroke:
		return 0
	_undo.append(snapshot())
	if _undo.size() > HISTORY:
		_undo.pop_front()
	_redo.clear()
	var seed_value := highway_seed
	while seed_value == highway_seed:
		seed_value = randi() % 999983 + 1
	var count := plan_highways(seed_value)
	history_changed.emit()
	_save_timer = 1.0
	return count


## Your own island again (after leaving a co-op room).
func load_own() -> void:
	sync.end()
	_load()


func to_dict() -> Dictionary:
	return {"v": SAVE_VERSION, "map": land.kind, "size": int(Land.SIZE), "t": Time.get_unix_time_from_system(), "seed": island_seed, "land": land.edits(),
		"streets": streets.to_data(), "zone": land.zone_edits(), "green": land.green_edits(), "level": land.level_edits(),
		"progress": progress.to_dict(), "marks": landmarks.to_dict(), "stages": town.stages(), "name": island_name, "hw": highway_seed}


func _apply_save(data: Dictionary) -> void:
	_undo.clear()
	_redo.clear()
	history_changed.emit()
	growth.stop()
	var old := int(data.get("v", 1)) < 2
	var map_kind := "legacy" if old else str(data.get("map", "island"))
	if not map_kind in Land.KINDS and map_kind != "legacy":
		map_kind = "island"
	# saves from before a map grew keep their ground where it was, in the middle
	var was := int(data.get("size", Land.NORMAL_SIZE))
	var size := Land.size_for(map_kind)
	if was != size and was > 0:
		for layer in ["land", "zone", "green", "level"]:
			if data.get(layer) is Dictionary:
				data[layer] = Land.recentre_cells(data[layer], was, size)
	_use_size(size)
	town.clear()
	var sg: Variant = data.get("stages", {})
	town.keep_stages(sg if sg is Dictionary else {})
	island_seed = int(data.seed)
	island_name = str(data.get("name", "")).left(NAME_MAX)
	name_changed.emit()
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
	highway_seed = int(data.get("hw", -1))
	if highway_seed < 0:
		# saved before highways came with the map (or a co-op room's island):
		# its network, unless it has highways of its own already
		highway_seed = 0
		if auto_highways and not streets.streets.any(func(o): return o.kind == "highway"):
			plan_highways(default_highway_seed())
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
func load_room(seed_value: int, state: Variant, map_kind := "island", size: int = Land.NORMAL_SIZE) -> void:
	var d := {"seed": seed_value, "v": SAVE_VERSION, "map": map_kind, "size": size}
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


var _save_task := -1
var _cloud_tasks: Array[int] = []


## Saves the island. In the `background` the ground's edits are worked out
## and the file written on another thread, so autosaving never stalls a frame.
func _save(background := false) -> void:
	if _save_task >= 0:
		if background and not WorkerThreadPool.is_task_completed(_save_task):
			# still writing the last one: try again shortly
			_save_timer = 0.5
			return
		WorkerThreadPool.wait_for_task_completion(_save_task)
		_save_task = -1
	_cloud_timer = minf(_cloud_timer, 20.0)
	# a shared island lives in its room; your own stays as you left it, with
	# the coins and goals you earned while away
	if Net.in_room():
		var own: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH)) if FileAccess.file_exists(SAVE_PATH) else null
		if not own is Dictionary:
			return
		own["progress"] = progress.to_dict()
		_write_save(own)
		return
	if not background:
		_write_save(to_dict())
		return
	_save_task = _dict_off_thread(_write_save)


## Works out to_dict() with the ground's edits done on another thread, then
## hands it to `done` (on that thread). Returns the task.
func _dict_off_thread(done: Callable) -> int:
	var data := {"v": SAVE_VERSION, "map": land.kind, "size": int(Land.SIZE), "t": Time.get_unix_time_from_system(), "seed": island_seed,
		"progress": progress.to_dict(), "marks": landmarks.to_dict(), "stages": town.stages(), "name": island_name, "hw": highway_seed}
	var layers := [land.heights.duplicate(), land._base, land.zone.duplicate(), land.green.duplicate(), land.level.duplicate()]
	# the streets copied out here, turned into data over there
	var raw := streets.to_raw()
	return WorkerThreadPool.add_task(func():
		var st := []
		for r: Array in raw:
			st.append(Streets.data_of(r))
		data["streets"] = st
		data["land"] = Land.edits_of(layers[0], layers[1])
		data["zone"] = Land.painted_of(layers[2], 0.01)
		data["green"] = Land.painted_of(layers[3], 0.01)
		data["level"] = Land.painted_of(layers[4], 0.5)
		done.call(data))


static func _write_save(data: Dictionary) -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))


## Keeps a copy of your island in your account, and brings back a newer one
## from another device when you sign in.
func _cloud(delta: float) -> void:
	for t in _cloud_tasks.duplicate():
		if WorkerThreadPool.is_task_completed(t):
			WorkerThreadPool.wait_for_task_completion(t)
			_cloud_tasks.erase(t)
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
		# worked out off the main thread, sent from it
		_cloud_tasks.append(_dict_off_thread(func(data: Dictionary): (func(): Firebase.db_put("users/%s/island" % Firebase.uid, data)).call_deferred()))


func _local_time() -> float:
	if not FileAccess.file_exists(SAVE_PATH):
		return 0.0
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	return float(d.get("t", 0.0)) if d is Dictionary else 0.0


var _farm_rev := -1
# the next row of the map box the farm map is being redone from (-1: not under way)
var _farm_y := -1


var _height_img: Image
var _maps_box := Rect2i()
var _maps_stage := 0
var _maps_coast := false
var _maps_shore := Rect2i(0, 0, -1, -1)
var _height_tex: ImageTexture
var _shore_tex: ImageTexture


## Ground maps for the shaders; the shoreline one only when the coast may have
## moved. With a `box` (in samples) only that part of them is worked out again.
func _update_maps(coast := true, box := Rect2i(0, 0, -1, -1)) -> void:
	var full := box.size.x < 0 or _height_tex == null
	if full:
		land.take_map_box()
		box = Rect2i(0, 0, -1, -1)
		if coast:
			# all of the shoreline is worked out here: nothing left owing
			_coast_dirty = false
			_coast_any = false
			_coast_box = Rect2i()
	_maps_farm(box)
	_maps_ground(coast, box)


## Redoes the farm map a band of rows a frame; true once it is done.
func _maps_farm_step(box: Rect2i) -> bool:
	if box.size.x <= 0 or (_farm_y < 0 and land.farm_rev == _farm_rev):
		_maps_farm(box)
		return true
	if _farm_y < 0:
		_farm_y = box.position.y
		_farm_rev = land.farm_rev
	land.update_farm(Rect2i(box.position.x, _farm_y, box.size.x, mini(FARM_BAND, box.end.y - _farm_y)))
	_farm_y += FARM_BAND
	if _farm_y < box.end.y:
		return false
	_farm_y = -1
	_upload_farm()
	return true


const FARM_BAND := 12


## The farm map, where the land or the painted town may have changed it.
func _maps_farm(box: Rect2i) -> void:
	if land.farm_rev == _farm_rev:
		return
	_farm_rev = land.farm_rev
	land.update_farm(box)
	_upload_farm()


func _upload_farm() -> void:
	ground_mat.set_shader_parameter("farm_tex", ImageTexture.create_from_image(land.farm_image()))
	ground_mat.set_shader_parameter("farm_angle", land.farm_angle)
	ground_mat.set_shader_parameter("grid_size", Land.SIZE)


## The height map the buildings and streets read, and the shoreline.
func _maps_ground(coast: bool, box: Rect2i, shore := Rect2i(0, 0, -1, -1)) -> void:
	if coast:
		# (only round what changed, when the rest is as it was)
		var img := land.shore_image(16.0, shore if shore.size.x > 0 and _shore_tex != null else Rect2i(0, 0, -1, -1))
		if _shore_tex != null and Vector2i(_shore_tex.get_size()) == img.get_size():
			_shore_tex.update(img)
		else:
			_shore_tex = ImageTexture.create_from_image(img)
			water_mat.set_shader_parameter("shore_tex", _shore_tex)
		water_mat.set_shader_parameter("grid_size", Land.SIZE)
	if box.size.x < 0 or _height_tex == null:
		_height_img = land.height_image()
		_height_tex = ImageTexture.create_from_image(_height_img)
		for m in [city_mat, detail_mat]:
			m.set_shader_parameter("height_tex", _height_tex)
			m.set_shader_parameter("height_range", Vector2(Land.MAP_SCALE, Land.MAP_BIAS))
			m.set_shader_parameter("grid_size", Land.SIZE)
	elif box.size.x > 0:
		land.paint_heights(_height_img, box)
		_height_tex.update(_height_img)


var _tint_tex: ImageTexture


## The Grow brush's tint over the painted ground, as it is painted.
func _update_tint() -> void:
	if not land.update_tint():
		return
	if _tint_tex == null or _tint_tex.get_size() != Vector2(land.tint_img.get_size()):
		_tint_tex = ImageTexture.create_from_image(land.tint_img)
		ground_mat.set_shader_parameter("tint_tex", _tint_tex)
	else:
		_tint_tex.update(land.tint_img)


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
	_update_tint()
	land.rebuild_dirty(FrameBudget.cap(3000))
	_shore_wait -= delta
	# while the town grows, the shadows and maps catch up about once a second
	if _shore_dirty and not _stroke and land.is_settled() and (_shore_wait <= 0.0 or not town.is_busy()):
		_shore_dirty = false
		_shore_wait = 1.0
		# the maps catch up over the next two frames, a part in each
		var box := land.take_map_box()
		if box.size.x > 0:
			_maps_box = _maps_box.merge(box) if _maps_box.size.x > 0 else box
		if _coast_dirty:
			var whole := _coast_any or _coast_box.size.x <= 0 or (_maps_coast and _maps_shore.size.x <= 0)
			_maps_shore = Rect2i(0, 0, -1, -1) if whole else (_maps_shore.merge(_coast_box) if _maps_coast else _coast_box)
			_maps_coast = true
		_maps_stage = 1
		_farm_y = -1
		_coast_dirty = false
		_coast_any = false
		_coast_box = Rect2i()
		_save_timer = maxf(_save_timer, 1.0)
	elif _maps_stage == 1:
		if _maps_farm_step(_maps_box):
			_maps_stage = 2
	elif _maps_stage == 2:
		_maps_stage = 0
		_maps_ground(_maps_coast, _maps_box, _maps_shore)
		_maps_box = Rect2i()
		_maps_coast = false
	# the ground's shadow stand-in, a tile a frame where it changed
	if not _stroke:
		land.rebuild_shadow(0)
	if _save_timer > 0.0:
		_save_timer -= delta
		if _save_timer <= 0.0:
			_save(true)
	_cloud(delta)
	if _stroke and _ring_at != null:
		if brush == "street":
			_extend_path(_ring_at)
		else:
			_apply_brush(_ring_at, delta)
	elif brush == "street" and street_change and not _stroke:
		_hover_change()
	advance_time(delta)
	_update_sky()
	# the lighthouse beam shines in the air only: no light patches swept over the ground and sea
	_update_beams(PackedVector4Array())
	for c in _clouds:
		c.position.x += c.get_meta("speed") * delta
		if c.position.x > 300.0:
			c.position.x = -300.0
	frame_view(rig.dist, rig.view_pitch())
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
			# _apply_brush grew the box by the shaping radius; the dabs reach further
			var zr := _zone_radius()
			_stroke_lo = _stroke_lo.min(c - Vector2(zr, zr))
			_stroke_hi = _stroke_hi.max(c + Vector2(zr, zr))
			return
		"magic":
			_magic_at(c)
			return
		"clear":
			BrushMask.clear(land, c, r * 0.6)
			town.zone_changed(c, r * 0.6)
			# (the map's highways stay: the Road tool's Reroll plans new ones)
			if streets.erase_at(c, r * 0.6, true):
				Sfx.play("bulldoze", 1.0, -8.0, 0.1)
			_save_timer = 1.0
			return
	_shore_dirty = true
	_coast_dirty = true
	var lo := Vector2i(((c - Vector2(r, r) + Vector2.ONE * Land.HALF) / Land.STEP).floor()) - Vector2i.ONE
	var cb := Rect2i(lo, Vector2i.ONE * (int(ceil(r * 2.0 / Land.STEP)) + 3))
	_coast_box = _coast_box.merge(cb) if _coast_box.size.x > 0 else cb
	_sculpt_sound -= delta
	if _sculpt_sound <= 0.0:
		_sculpt_sound = 0.16
		Sfx.play("road" if brush == "smooth" or brush == "flatten" else "place", 0.7 if brush == "lower" else 1.0, -12.0, 0.15)


## The Grow and Green brushes cover more ground than the shaping ones: enough
## to reach past a street's pavements to where its houses and side streets go.
func _zone_radius() -> float:
	return brush_radius * 1.4 + 1.5


## Paint where the town should grow (Green: as parks and gardens, which are
## still town, its streets running through them). Each dab paints at full
## strength at once, in a crisp disc that keeps to its side of the streets
## and stops at other colours (see BrushMask); a quick drag lays dabs all
## along the way so the stroke has no gaps.
func _paint_town(at: Vector3, _amount: float) -> void:
	var r := _zone_radius()
	var c := Vector2(at.x, at.z)
	var from: Vector2 = _last_dab if _last_dab != null else c
	var gap := from.distance_to(c)
	if _last_dab != null and gap < 0.5:
		return
	_last_dab = c
	var n := clampi(ceili(gap / maxf(r * 0.35, 0.5)), 1, 4)
	for k in n:
		var p := from.lerp(c, float(k + 1) / n)
		_stroke_claimed += _dab_mask(p, _stroke_over).apply(land, brush, grow_use, float(grow_level))
	# keep the town growing towards the brush without restarting its search
	growth.nudge(c)
	town.zone_changed(from.lerp(c, 0.5), r + gap * 0.5)
	_save_timer = 1.0


## What the brush in hand paints as (BrushMask classes).
func _own_class() -> int:
	return BrushMask.PARK if brush == "green" else grow_use


## The dab at c, kept while the brush hovers in the same place.
func _dab_mask(c: Vector2, over: int) -> BrushMask:
	var r := _zone_radius()
	# (the paint and the streets, not the ground's shape: land.revision moves
	# on every frame the town is growing, which would redo it every frame)
	var key := hash([Vector2i((c * 4.0).round()), r, _own_class(), over, streets.streets.size(), streets._next_id, land.farm_rev])
	if _mask == null or key != _mask_key:
		_mask = BrushMask.new()
		_mask.compute(land, streets, c, r, _own_class(), over)
		_mask_key = key
	return _mask


## The rest of the blocks a stroke mostly painted fill in.
func _fill_blocks() -> void:
	var b := BrushMask.fill_blocks(land, streets, _stroke_lo, _stroke_hi, _own_class(), _stroke_over, brush, grow_use, float(grow_level), _stroke_claimed)
	_mask = null
	if b.count <= 0:
		return
	var mid := Vector2(b.i0 + b.w * 0.5, b.j0 + b.h * 0.5) * Land.STEP - Vector2.ONE * Land.HALF
	town.zone_changed(mid, Vector2(b.w, b.h).length() * 0.5)
	Sfx.play("place", 1.25, -8.0)


## coins per stage the Magic brush skips
const MAGIC_COST := 2.0


## The Magic brush: every house under it shoots up to the top level its
## plot allows (the painted Grow level), for a few coins a stage.
func _magic_at(c: Vector2) -> void:
	var r := _zone_radius()
	var stages := town.magic(c, r, true)
	if stages == 0:
		return
	if not progress.spend(stages * MAGIC_COST):
		if not _broke:
			_broke = true
			note.emit("Not enough coins for magic here: %d needed" % int(stages * MAGIC_COST), "warn")
			Sfx.play("error", 1.0, -6.0)
		return
	town.magic(c, r)
	Sfx.play("unlock", 1.3, -8.0, 0.1)
	_save_timer = 1.0


## Golden sparkles rising round a building the Magic brush just grew.
func _sparkle(at: Vector3, size: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 40
	p.lifetime = 1.4
	p.explosiveness = 0.75
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(size.x * 0.55, size.y * 0.5, size.z * 0.55)
	p.position = at + Vector3(0, size.y * 0.5, 0)
	p.direction = Vector3.UP
	p.spread = 25.0
	p.gravity = Vector3(0, 1.2, 0)
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 2.2
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.2))
	curve.add_point(Vector2(0.2, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = curve
	p.mesh = _sparkle_mesh()
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	p.emitting = true
	get_tree().create_timer(p.lifetime + 0.3).timeout.connect(p.queue_free)


var _sparkle_quad: QuadMesh


func _sparkle_mesh() -> QuadMesh:
	if _sparkle_quad == null:
		_sparkle_quad = QuadMesh.new()
		_sparkle_quad.size = Vector2(0.9, 0.9)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.albedo_color = Color(1.0, 0.82, 0.35)
		m.albedo_texture = _sparkle_tex()
		_sparkle_quad.material = m
	return _sparkle_quad


## A soft four-pointed star.
static func _sparkle_tex() -> ImageTexture:
	const N := 32
	var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
	for y in N:
		for x in N:
			var u := absf((x + 0.5) / N * 2.0 - 1.0)
			var v := absf((y + 0.5) / N * 2.0 - 1.0)
			var star := maxf(1.0 - u * 6.0 - v * 1.1, 1.0 - v * 6.0 - u * 1.1)
			var glow := maxf(1.0 - sqrt(u * u + v * v) * 1.6, 0.0)
			var a := clampf(maxf(star, 0.0) + glow * glow * 0.8, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


## Whether the town has a street to grow from within reach of the brush at
## `c`: it only ever grows outwards from streets already there.
func can_grow_at(c: Vector2) -> bool:
	var r := _zone_radius() + 2.0
	for st: Streets.Street in streets.streets:
		if st.near_box(c, r) and st.within(c, r):
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
	m.vertex_color_use_as_albedo = true
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
	if brush == "street" and street_change:
		_draw_change()
	elif brush == "street" and _path.size() >= 2:
		# the line being drawn, as a soft ribbon the width of the street
		var hw: float = Streets.KINDS[street_kind].w
		_ring_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		_ring_mesh.surface_set_color(Color(1, 1, 1, 0.8))
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
	if brush == "street" and street_change and _stroke:
		return
	var at: Vector3 = _ring_at
	# Grow and Green show green where the town can spread, amber where no
	# street is near enough to grow from
	var tint := Color(1, 1, 1, 0.8)
	if brush == "grow" or brush == "green":
		_draw_dab(at, w)
		return
	elif brush == "magic":
		tint = Color(1.0, 0.85, 0.4, 0.95)
	elif brush == "street" and street_change:
		tint = _change_tint()
	var segs := 48
	var radius := _ring_radius()
	_ring_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	_ring_mesh.surface_set_color(tint)
	for k in segs + 1:
		var a := TAU * k / segs
		var dir := Vector3(cos(a), 0, sin(a))
		for rr in [radius - w, radius + w]:
			var p: Vector3 = at + dir * rr
			p.y = maxf(land.height_at(p.x, p.z), 0.0) + 0.06
			_ring_mesh.surface_add_vertex(p)
	_ring_mesh.surface_end()


## The Grow and Green brushes show exactly what the dab will paint: its
## ground washed in the colour it paints, inside a crisp outline that follows
## the streets and the other colours it stops at. The outline turns amber where
## there is no street near enough to grow from, and a faint grey circle means
## the ground under the finger is another colour this stroke leaves alone.
func _draw_dab(at: Vector3, w: float) -> void:
	var c := Vector2(at.x, at.z)
	var over := _stroke_over if _stroke else BrushMask.class_at(land, c)
	var mask := _dab_mask(c, over)
	var radius := _zone_radius()
	var col: Color = Land.PARK_TINT if brush == "green" else Land.USE_TINTS[clampi(grow_use, 0, Land.USE_TINTS.size() - 1)]
	var edge := col.lightened(0.35) if can_grow_at(c) else Color(1.0, 0.72, 0.35)
	var segs := 64
	# how far the dab reaches each way, worked out once for each dab
	if mask.outline.size() != segs:
		mask.outline.resize(segs)
		# (mask.covers() written out, as this runs a thousand times or more)
		var cov := mask.cov
		var mw := mask.w
		var mh := mask.h
		var o := Vector2(Land.HALF - mask.i0 * Land.STEP, Land.HALF - mask.j0 * Land.STEP)
		for k in segs:
			var dir := Vector2.from_angle(TAU * k / segs)
			var t := 0.0
			while t < radius + 0.5:
				var q := (c + dir * (t + 0.5) + o) / Land.STEP
				var ii := int(round(q.x))
				var jj := int(round(q.y))
				if ii < 0 or jj < 0 or ii >= mw or jj >= mh or cov[jj * mw + ii] < 0.5:
					break
				t += 0.5
			mask.outline[k] = minf(t + 0.25, radius) if t > 0.0 else 0.0
	var reach := mask.outline
	var none := true
	for k in segs:
		none = none and reach[k] <= 0.0
	if none:
		_ring_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		_ring_mesh.surface_set_color(Color(0.8, 0.8, 0.8, 0.45))
		for k in segs + 1:
			var dir := Vector3(cos(TAU * k / segs), 0, sin(TAU * k / segs))
			for rr in [radius - w * 0.5, radius + w * 0.5]:
				var p: Vector3 = at + dir * rr
				p.y = maxf(land.height_at(p.x, p.z), 0.0) + 0.06
				_ring_mesh.surface_add_vertex(p)
		_ring_mesh.surface_end()
		return
	var pts: Array[Vector3] = []
	pts.resize(segs * 3)
	for k in segs:
		var dir := Vector3(cos(TAU * k / segs), 0, sin(TAU * k / segs))
		for s in 3:
			var p: Vector3 = at + dir * reach[k] * (s + 1) / 3.0
			p.y = maxf(land.height_at(p.x, p.z), 0.0) + 0.06
			pts[k * 3 + s] = p
	var mid := Vector3(at.x, maxf(land.height_at(at.x, at.z), 0.0) + 0.06, at.z)
	# the wash, in three rings so it lies along the hills
	_ring_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	_ring_mesh.surface_set_color(Color(col, 0.22))
	for k in segs:
		var n := (k + 1) % segs
		_ring_mesh.surface_add_vertex(mid)
		_ring_mesh.surface_add_vertex(pts[k * 3])
		_ring_mesh.surface_add_vertex(pts[n * 3])
		for s in 2:
			var a: Vector3 = pts[k * 3 + s]
			var b: Vector3 = pts[n * 3 + s]
			var a2: Vector3 = pts[k * 3 + s + 1]
			var b2: Vector3 = pts[n * 3 + s + 1]
			for v in [a, a2, b2, a, b2, b]:
				_ring_mesh.surface_add_vertex(v)
	_ring_mesh.surface_end()
	# the outline, crisp and bright
	_ring_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	_ring_mesh.surface_set_color(Color(edge, 0.95))
	for k in segs + 1:
		var q: Vector3 = pts[(k % segs) * 3 + 2]
		var out := Vector3(q.x - at.x, 0, q.z - at.z).normalized() * w * 0.5
		for o in [-out, out]:
			_ring_mesh.surface_add_vertex(q + o)
	_ring_mesh.surface_end()


func _ring_radius() -> float:
	match brush:
		"street":
			return Streets.KINDS.main.w + Streets.PAVE
		"clear":
			return brush_radius * 0.6
		"grow", "green", "magic":
			return _zone_radius()
	return brush_radius


func _hover_at(screen: Vector2) -> void:
	_ring_at = land.raycast(rig.cam.project_ray_origin(screen), rig.cam.project_ray_normal(screen))


# ------------------------------------------------------------------ input

## A tap with no brush in hand asks what stands there.
func _tap(screen: Vector2) -> void:
	if brush != "":
		return
	var lot: Town.Lot = town.lot_on_ray(rig.cam.project_ray_origin(screen), rig.cam.project_ray_normal(screen))
	_highlight(lot)
	inspected.emit(lot)


## Lights up the tapped building for as long as its info card stays up, so
## it is plain which one the card is about.
func _highlight(lot: Town.Lot) -> void:
	if _picked_tw:
		_picked_tw.kill()
	if _picked:
		_picked.queue_free()
		_picked = null
	if lot == null or lot.arrays.is_empty():
		return
	var mesh := ArrayMesh.new()
	for k in [0, 4]:
		var v: PackedVector3Array = lot.arrays[k]
		if v.is_empty():
			continue
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = lot.arrays[k + 1]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	if mesh.get_surface_count() == 0:
		return
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.78, 0.3, 0.0)
	# just proud of the walls, so it never flickers against them
	mat.grow = true
	mat.grow_amount = 0.025
	_picked = MeshInstance3D.new()
	_picked.mesh = mesh
	_picked.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_picked.material_override = mat
	add_child(_picked)
	var node := _picked
	_picked_tw = create_tween()
	_picked_tw.tween_property(mat, "albedo_color:a", 0.6, 0.12)
	_picked_tw.tween_property(mat, "albedo_color:a", 0.38, 0.35)
	_picked_tw.tween_interval(4.5)
	_picked_tw.tween_property(mat, "albedo_color:a", 0.0, 0.4)
	_picked_tw.tween_callback(func():
		node.queue_free()
		if _picked == node:
			_picked = null)


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
	_change_hits.clear()
	if brush == "street":
		_extend_path(_ring_at)
	elif brush == "grow" or brush == "green":
		# a single tap already marks the spot clearly enough to build on
		_stroke_did = true
		var c := Vector2(_ring_at.x, _ring_at.z)
		var zr := _zone_radius()
		_stroke_lo = c - Vector2(zr, zr)
		_stroke_hi = c + Vector2(zr, zr)
		_stroke_over = BrushMask.class_at(land, c)
		_last_dab = null
		_stroke_claimed = 0
		_paint_town(_ring_at, 0.55)


func _end_stroke() -> void:
	if not _stroke:
		return
	_stroke = false
	if brush == "street" and street_change:
		_stroke_did = _apply_change()
		_path = PackedVector2Array()
		_change_hits.clear()
		_change_hover = Vector2(INF, INF)
	elif brush == "street":
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
		_fill_blocks()
		_last_dab = null
		_stroke_over = BrushMask.EMPTY
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


## Puts the island back as a snapshot had it, redrawing only what differs:
## streets that changed are taken up or laid again, and houses re-grow only
## where the ground or the painted town changed.
func restore(snap: Dictionary) -> void:
	growth.stop()
	var box := land.restore(snap.land)
	if streets.restore_data(snap.streets):
		cars.clear()
		folk.clear()
	if not box.is_empty():
		var lo := land.sample_pos(box[0].x, box[0].y)
		var hi := land.sample_pos(box[1].x, box[1].y)
		var c := (lo + hi) * 0.5
		var r := (hi - lo).length() * 0.5 + Land.STEP
		if box[2]:
			# houses on reshaped ground are laid out again at its new height
			town.reground(lo, hi)
		town.zone_changed(c, r)
	_shore_dirty = true
	_coast_dirty = true
	_coast_any = true
	_save_timer = 0.5


## Another builder reshaped the ground: shadows and the sea's shore follow.
func ground_changed() -> void:
	_shore_dirty = true
	_coast_dirty = true
	_coast_any = true


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
		if street_change:
			_touch_change(_path.size() - 1)
			_plan_change()


# ------------------------------------------------------------------ changing roads

## what a metre of each kind costs, compared with a street (Streets.DRAWN);
## lowering a road gives back half of what raising it cost
const GRADE_COST := {"side": 0.6, "main": 1.0, "avenue": 2.5, "highway": 4.0}
const REFUND := 0.5


## Marks the road under path point i. Dragging, only a road running the way
## the finger goes counts, so crossing a junction leaves the cross street be.
func _touch_change(i: int) -> void:
	var p := _path[i]
	var dir := Vector2.ZERO
	if i > 0:
		dir = (p - _path[maxi(i - 3, 0)]).normalized()
	var best: Streets.Street = null
	var bd := INF
	var bf := 0.0
	for st: Streets.Street in streets.streets:
		# (the map's highways stay as they were planned)
		if not Streets.gradable(st) or st.kind == "highway" or not st.near_box(p, st.reach() + 0.8):
			continue
		var c: Vector3 = st.closest(p)
		if c.x > st.reach() + 0.8 or c.x >= bd:
			continue
		if dir != Vector2.ZERO:
			var k := clampi(int(c.z), 0, st.pts.size() - 2)
			if absf((st.pts[k + 1] - st.pts[k]).normalized().dot(dir)) < 0.6:
				continue
		bd = c.x
		best = st
		bf = c.z
	if best == null:
		return
	var h: Array = _change_hits.get(best.id, [best, bf, bf])
	h[1] = minf(h[1], bf)
	h[2] = maxf(h[2], bf)
	_change_hits[best.id] = h


## What changing the marked roads to street_kind would do, and cost.
func _plan_change() -> void:
	change_plan = []
	change_cost = 0.0
	for id in _change_hits:
		var h: Array = _change_hits[id]
		var st: Streets.Street = h[0]
		if not st in streets.streets or st.kind == street_kind:
			continue
		var r := streets.stretch(st, h[1], h[2])
		change_plan.append([st, r.x, r.y])
		var d: float = GRADE_COST[street_kind] - GRADE_COST[st.kind]
		var cost := (r.y - r.x) * Streets.SAMPLE * IslandProgress.STREET_COST * d
		change_cost += cost if d > 0.0 else cost * REFUND


## With a mouse, the road under the pointer shows what a click would change.
func _hover_change() -> void:
	if _ring_at == null:
		if not change_plan.is_empty():
			change_plan = []
			change_cost = 0.0
		return
	var p := Vector2(_ring_at.x, _ring_at.z)
	if p.distance_to(_change_hover) < 0.3:
		return
	_change_hover = p
	_change_hits.clear()
	_path = PackedVector2Array([p])
	_touch_change(0)
	_plan_change()
	_path = PackedVector2Array()
	_change_hits.clear()


## Green where a road goes up, amber where it comes down, red if the coins
## don't stretch to it.
func _change_tint() -> Color:
	if change_cost > progress.coins:
		return Color(1.0, 0.45, 0.4, 0.9)
	return Color(0.55, 1.0, 0.6, 0.9) if change_raises() else Color(1.0, 0.75, 0.4, 0.9)


## Whether the planned change raises some road (rather than only lowering).
func change_raises() -> bool:
	for c: Array in change_plan:
		if Streets.GRADES.find(street_kind) > Streets.GRADES.find(c[0].kind):
			return true
	return change_plan.is_empty()


## The stretches about to change, as ribbons the width of the new road.
func _draw_change() -> void:
	if change_plan.is_empty():
		return
	var tint := _change_tint()
	var hw: float = Streets.KINDS[street_kind].w + Streets.PAVE * 0.5
	for c: Array in change_plan:
		var st: Streets.Street = c[0]
		var a := int(c[1])
		var b := mini(int(ceil(c[2])), st.pts.size() - 1)
		if b - a < 1:
			continue
		_ring_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		_ring_mesh.surface_set_color(tint)
		for i in range(a, b + 1):
			var t := (st.pts[mini(i + 1, b)] - st.pts[maxi(i - 1, a)]).normalized()
			var side := Vector2(-t.y, t.x) * hw
			for q in [st.pts[i] - side, st.pts[i] + side]:
				_ring_mesh.surface_add_vertex(Vector3(q.x, st.ys[i] + 0.14, q.y))
		_ring_mesh.surface_end()


## Changes the roads the stroke went along. Whether any changed.
func _apply_change() -> bool:
	if _path.is_empty():
		return false
	_plan_change()
	if change_plan.is_empty():
		return false
	var name := _kind_name(street_kind)
	if change_cost > progress.coins:
		note.emit("Not enough coins to make that a %s (%d)" % [name, ceili(change_cost)], "warn")
		Sfx.play("error", 1.0, -6.0)
		return false
	var done := false
	var up := change_raises()
	for c: Array in change_plan:
		var st: Streets.Street = c[0]
		# (a road changed before it may have taken this one's end off)
		if not st in streets.streets:
			continue
		if not streets.rekind(st, street_kind, c[1], c[2]).is_empty():
			done = true
	if not done:
		return false
	if change_cost >= 0.0:
		progress.spend(change_cost)
	else:
		progress.add_coins(-change_cost)
	Sfx.play("unlock" if up else "road", 1.2 if up else 0.85, -6.0, 0.05)
	Sfx.play("road", 1.0, -4.0)
	change_plan = []
	change_cost = 0.0
	_save_timer = 1.0
	return true


static func _kind_name(kind: String) -> String:
	return {"side": "lane", "main": "street"}.get(kind, kind)


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
			# sliding up tilts the view out towards the horizon, down looks straight down
			rig.tilt_by(event.relative.y * 0.006)
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
