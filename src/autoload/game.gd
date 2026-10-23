extends Node
## Global game state: the island grid, economy, growth and unlocks.
## Everything visual listens to the signals here; networking writes through set_tile().

signal tile_changed(x: int, z: int)
signal growth_changed(x: int, z: int, grew: bool)
signal world_reset
signal stats_changed
signal coins_changed(delta: float)
signal tool_unlocked(tool_id: String)
signal title_changed(title: String)
signal toast(text: String, kind: String)
signal income_tick(amount: float)
signal seabed_changed
signal history_changed

const SAVE_VERSION := 1
const N := 64
const TILE := 2.0
const LEVEL_Y: Array[float] = [-0.5, 0.16, 0.42, 0.72, 1.02, 1.32, 1.62]
const SEA_FLOOR := -3.4
const MAX_LEVEL := 6

enum K { EMPTY, ROAD, HOUSE, SHOP, OFFICE, PARK, TREE, LANDMARK }

enum LM { NONE, FOUNTAIN, LIGHTHOUSE, WINDMILL, CLOCKTOWER, FERRIS }

const TOOLS := [
	{"id": "road", "name": "Road", "cost": 5, "unlock": 0, "desc": "Drag to pave streets. Buildings grow next to roads."},
	{"id": "house", "name": "Homes", "cost": 20, "unlock": 0, "desc": "Cozy homes that grow into townhouses and apartments."},
	{"id": "shop", "name": "Shops", "cost": 30, "unlock": 12, "desc": "Cafés and stores with awnings facing the street."},
	{"id": "park", "name": "Park", "cost": 15, "unlock": 12, "desc": "Green space. Nearby buildings grow faster and happier."},
	{"id": "tree", "name": "Trees", "cost": 2, "unlock": 0, "desc": "Paint forests. Palms by the sea, pines on the hills."},
	{"id": "office", "name": "Offices", "cost": 60, "unlock": 90, "desc": "Workplaces that rise into glassy towers downtown."},
	{"id": "fountain", "name": "Fountain", "cost": 150, "unlock": 50, "desc": "A sparkling plaza. Big happiness boost nearby."},
	{"id": "windmill", "name": "Windmill", "cost": 250, "unlock": 160, "desc": "Turns gently in the breeze. Loves hilltops."},
	{"id": "lighthouse", "name": "Lighthouse", "cost": 300, "unlock": 220, "desc": "Guides boats home at night. Must touch the shore."},
	{"id": "clocktower", "name": "Clocktower", "cost": 450, "unlock": 380, "desc": "The heart of a proper town square."},
	{"id": "ferris", "name": "Big Wheel", "cost": 800, "unlock": 650, "desc": "The pride of the city, glowing at night."},
	{"id": "raise", "name": "Raise", "cost": 8, "unlock": 0, "desc": "Lift the land. Raise sea tiles to make new beach."},
	{"id": "lower", "name": "Lower", "cost": 8, "unlock": 0, "desc": "Dig the land down, all the way to the sea."},
	{"id": "bulldoze", "name": "Clear", "cost": 0, "unlock": 0, "desc": "Remove anything. Refunds half the cost."},
]

const TITLES := [
	[0, "Hamlet"], [25, "Village"], [120, "Town"], [400, "City"], [1000, "Big City"], [2500, "Metropolis"]]

const HOUSE_POP := [0, 4, 12, 30]
const SHOP_JOBS := [0, 4, 10, 22]
const OFFICE_JOBS := [0, 12, 36, 90]

var seed_value := 1
var level := PackedByteArray()
var kind := PackedByteArray()
var param := PackedByteArray()
var growth := PackedByteArray()
var base_level := PackedByteArray()
var base_kind := PackedByteArray()
var base_param := PackedByteArray()
var seabed := PackedFloat32Array()
var shore := PackedFloat32Array() # tiles to the nearest land (0 on land)

var coins := 600.0
var population := 0
var jobs := 0
var happiness := 0.7
var city_name := "Bayview"
var player_name := "Mayor"
var title := "Hamlet"
var best_population := 0
var unlocked := {}
var settings := {"music": true, "sfx": true, "shadows": true}
var tutorial_step := 0
var play_time := 0.0

var _growth_timer := 0.0
var _income_timer := 0.0
var _autosave_timer := 0.0
var _rng := RandomNumberGenerator.new()

# undo/redo: each stroke is a list of [x, z, k0, l0, p0, g0, k1, l1, p1, cost]
const HISTORY_MAX := 60
var _undo: Array = []
var _redo: Array = []
var _stroke: Array = []


func _ready() -> void:
	_rng.randomize()
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not load_local():
		new_world(randi() % 1000000)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		save_local()


# ------------------------------------------------------------------ grid helpers

func idx(x: int, z: int) -> int:
	return z * N + x


func inside(x: int, z: int) -> bool:
	return x >= 0 and z >= 0 and x < N and z < N


func lvl(x: int, z: int) -> int:
	return level[idx(x, z)] if inside(x, z) else 0


func knd(x: int, z: int) -> int:
	return kind[idx(x, z)] if inside(x, z) else K.EMPTY


func prm(x: int, z: int) -> int:
	return param[idx(x, z)] if inside(x, z) else 0


func grw(x: int, z: int) -> int:
	return growth[idx(x, z)] if inside(x, z) else 0


func tile_y(x: int, z: int) -> float:
	if inside(x, z) and level[idx(x, z)] == 0 and seabed.size() == N * N:
		return seabed[idx(x, z)]
	return LEVEL_Y[lvl(x, z)] if inside(x, z) else SEA_FLOOR


## Sea floor deepens with distance from land (multi-source BFS from every land tile).
func compute_seabed() -> void:
	var dist := PackedInt32Array()
	dist.resize(N * N)
	dist.fill(999)
	var queue: Array[int] = []
	for i in N * N:
		if level[i] > 0:
			dist[i] = 0
			queue.append(i)
	var head := 0
	while head < queue.size():
		var i: int = queue[head]
		head += 1
		var x := i % N
		var z := i / N
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = x + d.x
			var nz: int = z + d.y
			if inside(nx, nz) and dist[idx(nx, nz)] > dist[i] + 1:
				dist[idx(nx, nz)] = dist[i] + 1
				queue.append(idx(nx, nz))
	seabed.resize(N * N)
	shore.resize(N * N)
	for i in N * N:
		shore[i] = minf(float(dist[i]), 8.0)
		var dd := dist[i]
		seabed[i] = LEVEL_Y[0] - minf(float(dd - 1), 8.0) * 0.36 if level[i] == 0 else LEVEL_Y[level[i]]
		if level[i] == 0:
			seabed[i] = maxf(seabed[i], SEA_FLOOR)


## Height a road surface sits at (bridges over water sit at beach height).
func road_level(x: int, z: int) -> int:
	return max(1, lvl(x, z))


func tile_center(x: int, z: int) -> Vector3:
	return Vector3((x - N * 0.5 + 0.5) * TILE, tile_y(x, z), (z - N * 0.5 + 0.5) * TILE)


func world_to_tile(p: Vector3) -> Vector2i:
	return Vector2i(int(floor(p.x / TILE + N * 0.5)), int(floor(p.z / TILE + N * 0.5)))


func is_water(x: int, z: int) -> bool:
	return lvl(x, z) == 0


func is_building(k: int) -> bool:
	return k == K.HOUSE or k == K.SHOP or k == K.OFFICE


func hash2(x: int, z: int, salt: int = 0) -> int:
	var h := (x * 73856093) ^ (z * 19349663) ^ (seed_value * 83492791) ^ (salt * 2654435761)
	h = (h ^ (h >> 13)) * 1274126177
	return absi(h ^ (h >> 16))


func hashf(x: int, z: int, salt: int = 0) -> float:
	return float(hash2(x, z, salt) % 10000) / 10000.0


# ------------------------------------------------------------------ world generation

func new_world(s: int) -> void:
	seed_value = s
	_generate_terrain()
	clear_history()
	coins = 600.0
	unlocked.clear()
	tutorial_step = 0
	best_population = 0
	city_name = _random_city_name()
	_recount()
	_check_unlocks(true)
	world_reset.emit()
	stats_changed.emit()


func _random_city_name() -> String:
	var a := ["Bay", "Sun", "Cove", "Maple", "Coral", "Willow", "Harbor", "Pebble", "Amber", "Lumen", "Juniper", "Seren"]
	var b := ["view", "ford", "haven", "port", "dale", "bridge", "wick", "shore", "field", "mere"]
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return a[r.randi() % a.size()] + b[r.randi() % b.size()]


func _generate_terrain() -> void:
	var count := N * N
	level = PackedByteArray(); level.resize(count)
	kind = PackedByteArray(); kind.resize(count)
	param = PackedByteArray(); param.resize(count)
	growth = PackedByteArray(); growth.resize(count)
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.035
	noise.fractal_octaves = 4
	var warp := FastNoiseLite.new()
	warp.seed = seed_value + 17
	warp.frequency = 0.03
	var forest := FastNoiseLite.new()
	forest.seed = seed_value + 99
	forest.frequency = 0.08
	var elev := PackedFloat32Array(); elev.resize(count)
	for z in N:
		for x in N:
			var u := (x + 0.5) / N * 2.0 - 1.0
			var v := (z + 0.5) / N * 2.0 - 1.0
			var d := sqrt(u * u + v * v) + warp.get_noise_2d(x, z) * 0.28
			var e := noise.get_noise_2d(x, z) * 0.42 + 0.6 - d * 0.62 - pow(maxf(d - 0.55, 0.0), 2.0) * 2.6
			elev[idx(x, z)] = e
	for z in N:
		for x in N:
			var e := elev[idx(x, z)]
			var l := 0
			if x < 2 or z < 2 or x >= N - 2 or z >= N - 2:
				l = 0
			elif e < 0.0:
				l = 0
			elif e < 0.05:
				l = 1
			elif e < 0.36:
				l = 2
			elif e < 0.5:
				l = 3
			elif e < 0.6:
				l = 4
			elif e < 0.7:
				l = 5
			else:
				l = 6
			level[idx(x, z)] = l
	# beaches: land touching the sea becomes sand, except where cliffs are steep
	var copy := level.duplicate()
	for z in N:
		for x in N:
			var l := copy[idx(x, z)]
			if l >= 2:
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					if inside(x + d.x, z + d.y) and copy[idx(x + d.x, z + d.y)] == 0:
						if l <= 2 or hashf(x, z, 5) < 0.6:
							level[idx(x, z)] = 1
						break
	# soften: no more than 2 terrace steps between neighbours
	for pass_i in 2:
		for z in range(1, N - 1):
			for x in range(1, N - 1):
				var l := level[idx(x, z)]
				var mn := 99
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					mn = min(mn, level[idx(x + d.x, z + d.y)])
				if l > mn + 2 and mn > 0:
					level[idx(x, z)] = mn + 2
	# natural forests
	for z in N:
		for x in N:
			var l := level[idx(x, z)]
			var f := forest.get_noise_2d(x, z)
			if l >= 2 and f > 0.18 + (0.0 if l >= 4 else 0.08):
				kind[idx(x, z)] = K.TREE
				param[idx(x, z)] = 1 + hash2(x, z, 3) % 3
			elif l == 1 and f > 0.45:
				kind[idx(x, z)] = K.TREE
				param[idx(x, z)] = 1
	compute_seabed()
	base_level = level.duplicate()
	base_kind = kind.duplicate()
	base_param = param.duplicate()


# ------------------------------------------------------------------ editing

func tool_def(id: String) -> Dictionary:
	for t in TOOLS:
		if t.id == id:
			return t
	return {}


func is_unlocked(id: String) -> bool:
	return unlocked.has(id)


func _landmark_for(id: String) -> int:
	match id:
		"fountain": return LM.FOUNTAIN
		"lighthouse": return LM.LIGHTHOUSE
		"windmill": return LM.WINDMILL
		"clocktower": return LM.CLOCKTOWER
		"ferris": return LM.FERRIS
	return LM.NONE


func _near_water(x: int, z: int, r: int) -> bool:
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if inside(x + dx, z + dz) and is_water(x + dx, z + dz):
				return true
	return false


## Returns "" if the tool can be used at (x, z), otherwise a short reason.
func check_tool(id: String, x: int, z: int) -> String:
	if not inside(x, z) or x < 1 or z < 1 or x >= N - 1 or z >= N - 1:
		return "Edge of the world"
	var def := tool_def(id)
	if def.is_empty():
		return "?"
	if not is_unlocked(id):
		return "Unlocks at %d citizens" % def.unlock
	var k := knd(x, z)
	var l := lvl(x, z)
	var cost: float = def.cost
	match id:
		"road":
			if k == K.ROAD:
				return "already"
			if k != K.EMPTY and k != K.TREE:
				return "Occupied"
			if l == 0:
				cost *= 4.0
				if not _bridge_ok(x, z):
					return "Bridges need a shore"
		"house", "shop", "office", "park", "tree":
			if l == 0:
				return "Can't build on water"
			var target := _kind_for(id)
			if k == target:
				return "already"
			if k != K.EMPTY and k != K.TREE:
				return "Occupied"
			if id == "tree" and k == K.TREE:
				return "already"
		"fountain", "windmill", "clocktower", "ferris":
			if l == 0:
				return "Can't build on water"
			if k != K.EMPTY and k != K.TREE:
				return "Occupied"
			if id == "windmill" and l < 3:
				return "Windmills need a hill"
		"lighthouse":
			if l == 0:
				return "Can't build on water"
			if k != K.EMPTY and k != K.TREE:
				return "Occupied"
			if not _near_water(x, z, 1):
				return "Must touch the sea"
		"raise":
			if l >= MAX_LEVEL:
				return "As high as it goes"
			if k != K.EMPTY and k != K.TREE:
				return "Clear it first"
		"lower":
			if l == 0:
				return "Already sea"
			if k != K.EMPTY and k != K.TREE:
				return "Clear it first"
		"bulldoze":
			if k == K.EMPTY:
				return "already"
	if coins < cost:
		return "Not enough coins"
	return ""


func _bridge_ok(x: int, z: int) -> bool:
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nx: int = x + d.x
		var nz: int = z + d.y
		if knd(nx, nz) == K.ROAD or (inside(nx, nz) and lvl(nx, nz) >= 1):
			return true
	return false


func _kind_for(id: String) -> int:
	match id:
		"road": return K.ROAD
		"house": return K.HOUSE
		"shop": return K.SHOP
		"office": return K.OFFICE
		"park": return K.PARK
		"tree": return K.TREE
	return K.LANDMARK


func tool_cost(id: String, x: int, z: int) -> float:
	var def := tool_def(id)
	var cost: float = def.get("cost", 0)
	if id == "road" and lvl(x, z) == 0:
		cost *= 4.0
	return cost


## Applies a tool locally. Returns true when something changed.
func apply_tool(id: String, x: int, z: int) -> bool:
	if check_tool(id, x, z) != "":
		return false
	var cost := tool_cost(id, x, z)
	var k := knd(x, z)
	var l := lvl(x, z)
	var before := [k, l, prm(x, z), grw(x, z)]
	match id:
		"raise":
			set_tile(x, z, K.EMPTY, l + 1, 0)
		"lower":
			set_tile(x, z, K.EMPTY, l - 1, 0)
		"bulldoze":
			var refund := 0.0
			for t in TOOLS:
				if _kind_for(t.id) == k and (k != K.LANDMARK or _landmark_for(t.id) == prm(x, z)):
					refund = t.cost * 0.5
					break
			set_tile(x, z, K.EMPTY, l, 0)
			cost = -refund
		"tree":
			set_tile(x, z, K.TREE, l, 1 + hash2(x, z, 11) % 3)
		_:
			var nk := _kind_for(id)
			var p := _landmark_for(id) if nk == K.LANDMARK else hash2(x, z, 7) % 250
			set_tile(x, z, nk, l, p)
	add_coins(-cost)
	_stroke.append([x, z, before[0], before[1], before[2], before[3], knd(x, z), lvl(x, z), prm(x, z), cost])
	if tutorial_step < 3:
		_advance_tutorial(id)
	return true


# ------------------------------------------------------------------ undo / redo

## Closes the current drag so it undoes as one step.
func end_stroke() -> void:
	if _stroke.is_empty():
		return
	_undo.append(_stroke)
	_stroke = []
	if _undo.size() > HISTORY_MAX:
		_undo.pop_front()
	_redo.clear()
	history_changed.emit()


func can_undo() -> bool:
	return not _undo.is_empty() or not _stroke.is_empty()


func can_redo() -> bool:
	return not _redo.is_empty()


func clear_history() -> void:
	_undo.clear()
	_redo.clear()
	_stroke.clear()
	history_changed.emit()


func _matches(e: Array, off: int) -> bool:
	return knd(e[0], e[1]) == e[off] and lvl(e[0], e[1]) == e[off + 1] and prm(e[0], e[1]) == e[off + 2]


## Reverts the last stroke and gives back exactly what it cost.
func undo() -> bool:
	end_stroke()
	if _undo.is_empty():
		return false
	var stroke: Array = _undo.pop_back()
	var refund := 0.0
	for i in range(stroke.size() - 1, -1, -1):
		var e: Array = stroke[i]
		# skip tiles someone else changed since (co-op), so nothing gets clobbered
		if not _matches(e, 6):
			continue
		set_tile(e[0], e[1], e[2], e[3], e[4])
		growth[idx(e[0], e[1])] = e[5]
		growth_changed.emit(e[0], e[1], false)
		refund += e[9]
	if refund != 0.0:
		add_coins(refund)
	_redo.append(stroke)
	_recount()
	history_changed.emit()
	return true


## Re-applies an undone stroke for the same price it had the first time.
func redo() -> bool:
	if _redo.is_empty():
		return false
	var stroke: Array = _redo.back()
	var cost := 0.0
	for e in stroke:
		if _matches(e, 2):
			cost += e[9]
	if cost > coins + 0.001:
		toast.emit("Not enough coins to redo", "warn")
		return false
	_redo.pop_back()
	for e in stroke:
		if _matches(e, 2):
			set_tile(e[0], e[1], e[6], e[7], e[8])
	add_coins(-cost)
	_undo.append(stroke)
	history_changed.emit()
	return true


## Writes a tile. Called for local edits and for edits arriving from other players.
func set_tile(x: int, z: int, k: int, l: int, p: int, remote := false) -> void:
	if not inside(x, z):
		return
	var i := idx(x, z)
	if kind[i] == k and level[i] == l and param[i] == p:
		return
	var was := kind[i]
	var old_level := level[i]
	kind[i] = k
	level[i] = clampi(l, 0, MAX_LEVEL)
	param[i] = p
	if k != was:
		growth[i] = 0
	if k == K.ROAD or k == K.PARK or k == K.TREE or k == K.LANDMARK:
		growth[i] = 1
	if level[i] != old_level and (level[i] == 0 or old_level == 0):
		compute_seabed()
		seabed_changed.emit()
	tile_changed.emit(x, z)
	if not remote:
		Net.push_tile(x, z)
	_recount()


func add_coins(amount: float) -> void:
	coins = max(0.0, coins + amount)
	coins_changed.emit(amount)


# ------------------------------------------------------------------ simulation

func _process(delta: float) -> void:
	play_time += delta
	_growth_timer += delta
	_income_timer += delta
	_autosave_timer += delta
	if _growth_timer > 0.9:
		_growth_timer = 0.0
		_grow_step()
	if _income_timer > 3.0:
		_income_timer = 0.0
		var income := (population * 0.16 + mini(jobs, population) * 0.22 + 1.0) * (0.6 + happiness * 0.8)
		add_coins(income)
		income_tick.emit(income)
	if _autosave_timer > 25.0:
		_autosave_timer = 0.0
		save_local()
		if Firebase.signed_in and not Net.in_room():
			Firebase.save_city(to_dict())


func target_growth(x: int, z: int) -> int:
	var k := knd(x, z)
	if not is_building(k):
		return growth[idx(x, z)]
	var road := false
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			if knd(x + dx, z + dz) == K.ROAD:
				road = true
	if not road:
		return 0
	var score := 1.0
	var houses := 0
	var shops := 0
	var dense := 0
	for dz in range(-4, 5):
		for dx in range(-4, 5):
			if dx == 0 and dz == 0:
				continue
			var nk := knd(x + dx, z + dz)
			var dist: int = max(absi(dx), absi(dz))
			match nk:
				K.PARK:
					if dist <= 3: score += 0.35
				K.TREE:
					if dist <= 1: score += 0.08
				K.LANDMARK:
					score += 0.7
				K.HOUSE:
					houses += 1
					if dist <= 2: dense += 1
				K.SHOP:
					shops += 1
					if dist <= 2: dense += 1
				K.OFFICE:
					if dist <= 2: dense += 2
	score += min(dense, 16) * 0.07
	if k == K.HOUSE:
		if shops > 0: score += 0.45
		if _near_water(x, z, 2): score += 0.3
	elif k == K.SHOP:
		if houses == 0: return 1
		score += min(houses, 10) * 0.06
	elif k == K.OFFICE:
		if houses + shops < 4: return 1
	var t := 1
	if score >= 1.9: t = 2
	if score >= 2.9: t = 3
	# the whole city has to be big enough for taller buildings
	if t >= 2 and population < 30: t = 1
	if t >= 3 and population < (220 if k != K.OFFICE else 400): t = 2
	return t


func _grow_step() -> void:
	# a few random building tiles per step move one notch toward their target: staggered, lively growth
	var changed := 0
	for attempt in 60:
		var x := _rng.randi_range(1, N - 2)
		var z := _rng.randi_range(1, N - 2)
		var i := idx(x, z)
		if not is_building(kind[i]):
			continue
		var t := target_growth(x, z)
		var g := growth[i]
		if g < t:
			growth[i] = g + 1
			growth_changed.emit(x, z, true)
			changed += 1
		elif g > t:
			growth[i] = g - 1
			growth_changed.emit(x, z, false)
			changed += 1
		if changed >= 2:
			break
	if changed > 0:
		_recount()


func _recount() -> void:
	var pop := 0
	var jb := 0
	var green := 0.0
	for i in kind.size():
		var g := growth[i]
		match kind[i]:
			K.HOUSE: pop += HOUSE_POP[g]
			K.SHOP: jb += SHOP_JOBS[g]
			K.OFFICE: jb += OFFICE_JOBS[g]
			K.PARK: green += 6.0
			K.TREE: green += 0.6
			K.LANDMARK: green += 30.0
	population = pop
	jobs = jb
	var need := pop * 0.18 + 1.0
	var h := 0.45 + 0.45 * minf(1.0, green / need)
	if pop > 20:
		h += 0.1 * min(1.0, float(jb) / pop) - 0.05
	happiness = clampf(h, 0.0, 1.0)
	best_population = max(best_population, population)
	_check_unlocks(false)
	stats_changed.emit()


func _check_unlocks(silent: bool) -> void:
	for t in TOOLS:
		if not unlocked.has(t.id) and best_population >= t.unlock:
			unlocked[t.id] = true
			if not silent:
				tool_unlocked.emit(t.id)
	var new_title := "Hamlet"
	for tt in TITLES:
		if best_population >= tt[0]:
			new_title = tt[1]
	if new_title != title:
		title = new_title
		if not silent:
			title_changed.emit(title)


func next_title_progress() -> Array:
	# returns [next title name, progress 0..1]
	var prev := 0
	for tt in TITLES:
		if best_population < tt[0]:
			return [tt[1], clampf(float(population - prev) / float(tt[0] - prev), 0.0, 1.0)]
		prev = tt[0]
	return ["", 1.0]


func _advance_tutorial(tool_id: String) -> void:
	if tutorial_step == 0 and tool_id == "road":
		tutorial_step = 1
	elif tutorial_step == 1 and tool_id == "house":
		tutorial_step = 2
	elif tutorial_step == 2 and population > 0:
		tutorial_step = 3


# ------------------------------------------------------------------ saving

func edits_dict() -> Dictionary:
	var out := {}
	for i in kind.size():
		if kind[i] != base_kind[i] or level[i] != base_level[i] or param[i] != base_param[i]:
			out["%d" % i] = [kind[i], level[i], param[i], growth[i]]
	return out


func to_dict() -> Dictionary:
	return {
		"v": SAVE_VERSION, "seed": seed_value, "name": city_name, "coins": coins,
		"best": best_population, "tut": tutorial_step, "edits": edits_dict(),
		"time": Time.get_unix_time_from_system(), "play": play_time,
	}


func from_dict(d: Dictionary, keep_economy := false) -> void:
	seed_value = int(d.get("seed", 1))
	_generate_terrain()
	clear_history()
	var edits: Dictionary = d.get("edits", {})
	for key in edits:
		var i := int(key)
		var e: Array = edits[key]
		if i < 0 or i >= kind.size() or e.size() < 3:
			continue
		kind[i] = int(e[0])
		level[i] = int(e[1])
		param[i] = int(e[2])
		growth[i] = int(e[3]) if e.size() > 3 else 0
	compute_seabed()
	city_name = str(d.get("name", city_name))
	if not keep_economy:
		coins = float(d.get("coins", 600.0))
		best_population = int(d.get("best", 0))
		tutorial_step = int(d.get("tut", 3))
		play_time = float(d.get("play", 0.0))
	unlocked.clear()
	_recount()
	_check_unlocks(true)
	world_reset.emit()


func save_local() -> void:
	if level.is_empty() or Net.in_room():
		return
	var f := FileAccess.open("user://city.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(to_dict()))
	var s := FileAccess.open("user://settings.json", FileAccess.WRITE)
	if s:
		s.store_string(JSON.stringify({"settings": settings, "player": player_name}))


func load_local() -> bool:
	if FileAccess.file_exists("user://settings.json"):
		var s = JSON.parse_string(FileAccess.get_file_as_string("user://settings.json"))
		if s is Dictionary:
			settings.merge(s.get("settings", {}), true)
			player_name = str(s.get("player", player_name))
	if not FileAccess.file_exists("user://city.json"):
		return false
	var d = JSON.parse_string(FileAccess.get_file_as_string("user://city.json"))
	if not d is Dictionary:
		return false
	from_dict(d)
	return true
