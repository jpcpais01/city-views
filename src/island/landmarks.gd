class_name Landmarks
extends Node3D
## The island's landmarks, which come up as the town grows: a windmill on the
## highest hill once a village has formed, a wooden pier where the harbour
## quarter meets deep water, and a lighthouse on the headland that reaches
## furthest into the sea once it is a proper town, its beam sweeping the
## water at night. Where the windmill and lighthouse stand follows from the
## land itself; once standing, the town leaves room around each one.
## A big shopping district at the top levels brings its own attractions: a
## Ferris wheel turning beside the stores, and a stadium under floodlights.
## A city of a few thousand gets an airport out in open country: a runway
## with lights, a taxiway, a terminal with airliners at its gates, a control
## tower and a hangar. Airliners take off from it and land on it (see Planes).

const NEED := {"windmill": 150, "pier": 275, "lighthouse": 450, "wheel": 0, "stadium": 0, "airport": 4000}
const NAMES := {"windmill": "A windmill now turns on the hilltop", "pier": "A pier now reaches out from the harbour", "lighthouse": "A lighthouse now guards the headland",
	"wheel": "A Ferris wheel now turns by the shops", "stadium": "A stadium now stands by the shopping district",
	"airport": "The city's airport is open: watch for planes taking off"}
const ROOM := {"windmill": 1.6, "pier": 1.2, "lighthouse": 2.0, "wheel": 2.4, "stadium": 6.6, "airport": 24.0}
## the airport's ground, half its width and half its length (the runway runs
## along its length), and where on it the runway lies across
const AIRPORT := Vector2(8.5, 24.0)
const RUNWAY_X := -5.5
const RUNWAY_HALF := 23.0
const TARMAC := Color(0.32, 0.33, 0.35)
const APRON := Color(0.68, 0.68, 0.66)
const FIELD := Color(0.56, 0.69, 0.38)
## how many stores, malls, cinemas and venues a shopping or entertainment
## district needs for each attraction
const RETAIL := {"wheel": 3, "stadium": 6}
const TEAM := [[Color("2f5f9f"), Color("e9e6df")], [Color("c8553d"), Color("f2f1ec")], [Color("2f8f83"), Color("e3a33b")], [Color("6a4c9c"), Color("e9e6df")]]
const WHITE := Color(0.97, 0.96, 0.93)
const RED := Color("d9534f")
const STONE := Color(0.72, 0.7, 0.66)
const TIMBER := Color(0.45, 0.33, 0.24)
const PLANK := Color(0.72, 0.56, 0.38)
const PIER_LEN := 7.0
# how far beyond the town's streets a landmark may stand
const SEARCH := 60.0

var world: IslandWorld
var beam_mat: Material
## kind -> Vector2 where it stands
var spots := {}
var _nodes := {}
var _spin: Array[MeshInstance3D] = []
var _beam: MeshInstance3D
var _check := 1.0
# what the town was like when each missing landmark was last looked for
var _looked := {}
var _next_look := {}
var _searches: Array[Dictionary] = []
## which way the airport's runway points (its local +Z), once it stands
var airport_yaw := 0.0


func _process(delta: float) -> void:
	for mi in _spin:
		if is_instance_valid(mi):
			mi.rotate_object_local(mi.get_meta("axis"), float(mi.get_meta("speed")) * delta)
	if _beam:
		_beam.visible = world.night > 0.15
	_check -= delta
	if _check > 0.0 or world.town.is_busy() or not _searches.is_empty():
		if not _searches.is_empty():
			_step_searches()
		return
	_check = 2.0
	for kind in NEED:
		var want := _wants(kind)
		if spots.has(kind) and (not want or not (_airport_fits(spots[kind], airport_yaw, true) if kind == "airport" else _fits(kind, spots[kind], true))):
			_remove(kind)
		if want and not spots.has(kind):
			# look again only once the town has changed since the last look
			var sig := hash([world.town.lots.size(), world.streets.streets.size(), world.land.revision])
			if _looked.get(kind, 0) == sig:
				continue
			# a long search: while the town is still growing, not too often
			var now := Time.get_ticks_msec()
			if _looked.has(kind) and now < int(_next_look.get(kind, 0)):
				continue
			_next_look[kind] = now + 12000
			_looked[kind] = sig
			var search := _search_start(kind)
			if not search.is_empty():
				_searches.append(search)
	_step_searches()


## The searches under way go on a slice at a time, so none stalls a frame.
func _step_searches() -> void:
	if not _searches.is_empty() and _search_step(_searches[0], FrameBudget.cap(2000)):
		var done: Dictionary = _searches.pop_front()
		var kind: String = done.kind
		if done.at != null and not spots.has(kind) and _wants(kind):
			if kind == "airport":
				airport_yaw = done.yaw
			_place(kind, done.at)
			if world.progress._hush <= 0.0:
				world.note.emit(NAMES[kind], "title")
				Sfx.play("unlock", 0.9)


## Runs every search under way to the end (loads and tests).
func settle() -> void:
	_check = 0.0
	_next_look.clear()
	_process(0.0)
	while not _searches.is_empty():
		_process(0.0)


## Whether the town is big enough for `kind`: the old landmarks go by
## residents, the attractions by how much the shopping and entertainment
## districts have grown.
func _wants(kind: String) -> bool:
	if RETAIL.has(kind):
		return _retail().size() >= int(RETAIL[kind])
	return world.progress.residents >= int(NEED[kind])


## Where the stores, malls, cinemas and the bigger venues stand.
func _retail() -> PackedVector2Array:
	var out := PackedVector2Array()
	for l: Town.Lot in world.town.lots.values():
		if (l.use == "retail" or (l.use == "fun" and l.stage >= 4)) and l.host == 0:
			out.append(l.origin)
	return out


## Where the lighthouse beams point, for the lit surfaces.
func beams() -> PackedVector4Array:
	var out := PackedVector4Array()
	if _beam and _beam.visible:
		var bx := _beam.global_transform.basis.x
		var o := _beam.global_position
		out.append(Vector4(o.x, o.y, o.z, atan2(bx.z, bx.x)))
	return out


func reset() -> void:
	_looked.clear()
	for kind in spots.keys():
		_remove(kind)


func to_dict() -> Dictionary:
	var out := {}
	for kind in spots:
		var p: Vector2 = spots[kind]
		out[kind] = [snappedf(p.x, 0.01), snappedf(p.y, 0.01)]
		if kind == "airport":
			out[kind].append(snappedf(airport_yaw, 0.0001))
	return out


## Puts back the landmarks of a saved island, before its town fills in again.
func from_dict(d: Dictionary) -> void:
	reset()
	for kind in d:
		var v: Variant = d[kind]
		if NEED.has(kind) and v is Array and v.size() >= 2:
			if kind == "airport":
				if v.size() < 3:
					continue
				airport_yaw = float(v[2])
			_place(kind, Vector2(float(v[0]), float(v[1])))


# ------------------------------------------------------------------ where

## Whether `kind` can stand at `p`: the right ground, and clear of streets and
## (unless it already stands there) houses.
func _fits(kind: String, p: Vector2, standing := false) -> bool:
	var land := world.land
	var h := land.height_at(p.x, p.y)
	if kind == "pier":
		return _pier_fits(p, standing)
	if kind == "lighthouse" and (h < 0.3 or h > 6.0):
		return false
	if kind == "windmill" and h < 1.2:
		return false
	if RETAIL.has(kind) and h < 0.3:
		return false
	var r: float = ROOM[kind]
	if RETAIL.has(kind):
		# a wide one: every ring of ground under it clear (the quick test,
		# first), then dry and level
		if not standing:
			for ring in [0.0, 0.5, 1.0, 0.75, 0.25]:
				for k in (16 if ring > 0.0 else 1):
					if world.town.is_built(p + Vector2.from_angle(k * TAU / 16.0) * r * ring):
						return false
		for ring in [0.35, 0.7, 1.0]:
			for k in 16:
				var q: Vector2 = p + Vector2.from_angle(k * TAU / 16.0) * r * ring
				var g: float = land.height_at(q.x, q.y)
				if absf(g - h) > 0.7 or g < 0.2:
					return false
	for k in 8:
		var q := p + Vector2.from_angle(k * TAU / 8.0) * r
		var g := p + Vector2.from_angle(k * TAU / 8.0) * r * 0.6
		if absf(land.height_at(g.x, g.y) - h) > 0.9 or land.height_at(g.x, g.y) < 0.05:
			return false
		if not standing and world.town.is_built(q):
			return false
	if not standing and world.town.is_built(p):
		return false
	for s: Streets.Street in world.streets.streets:
		if s.near_box(p, r + 2.0) and s.closest(p).x < r + s.reach() + 0.4:
			return false
	return true


## Whether the airport fits at p with its runway along yaw: dry, nearly
## level ground all over it, nothing built on it, no street across it.
func _airport_fits(p: Vector2, yaw: float, standing: bool) -> bool:
	var land := world.land
	var right := Vector2(cos(yaw), -sin(yaw))
	var fwd := Vector2(sin(yaw), cos(yaw))
	var lo := INF
	var hi := -INF
	# the corners and the middle first, then the whole of it
	for pass_i in 2:
		var step := Vector2(AIRPORT.x, AIRPORT.y) if pass_i == 0 else Vector2(AIRPORT.x / 3.0, AIRPORT.y / 8.0)
		var gx := -AIRPORT.x
		while gx <= AIRPORT.x + 0.01:
			var gz := -AIRPORT.y
			while gz <= AIRPORT.y + 0.01:
				var q := p + right * gx + fwd * gz
				if absf(q.x) > Land.HALF - 2.0 or absf(q.y) > Land.HALF - 2.0:
					return false
				var g := land.height_at(q.x, q.y)
				lo = minf(lo, g)
				hi = maxf(hi, g)
				if lo < 0.25 or hi - lo > 1.6:
					return false
				if not standing and world.town.is_built(q):
					return false
				gz += step.y
			gx += step.x
	# no street through it (or along its edge)
	for s: Streets.Street in world.streets.streets:
		if not s.near_box(p, AIRPORT.y + 2.0):
			continue
		var reach := s.reach() + 1.0
		for k in range(0, s.pts.size(), 2):
			var d := s.pts[k] - p
			if absf(d.dot(right)) < AIRPORT.x + reach and absf(d.dot(fwd)) < AIRPORT.y + reach:
				return false
	return true


## The two ends of the runway, on the ground (for the airliners), or an
## empty array when there is no airport.
func runway() -> PackedVector3Array:
	var out := PackedVector3Array()
	if not spots.has("airport") or not _nodes.has("airport"):
		return out
	var p: Vector2 = spots.airport
	var y: float = _nodes.airport.position.y
	var right := Vector2(cos(airport_yaw), -sin(airport_yaw))
	var fwd := Vector2(sin(airport_yaw), cos(airport_yaw))
	for e: float in [-1.0, 1.0]:
		var q := p + right * RUNWAY_X + fwd * e * (RUNWAY_HALF - 1.5)
		out.append(Vector3(q.x, y, q.y))
	return out


## Which way is out to sea from a spot on the shore (zero if none is).
func _seaward(p: Vector2) -> Vector2:
	var d := Vector2.ZERO
	for k in 16:
		var dir := Vector2.from_angle(k * TAU / 16.0)
		var q := p + dir * 4.0
		if world.land.height_at(q.x, q.y) < -0.3:
			d += dir
	return d.normalized()


## A pier starts on the shore just above the water and runs out into water
## deep enough for boats, clear of houses and streets.
func _pier_fits(p: Vector2, standing: bool) -> bool:
	var land := world.land
	var h := land.height_at(p.x, p.y)
	if h < 0.02 or h > 1.0:
		return false
	var d := _seaward(p)
	if d == Vector2.ZERO:
		return false
	for t in [2.5, 4.5, PIER_LEN]:
		var q: Vector2 = p + d * t
		if land.height_at(q.x, q.y) > (-0.2 if t < 3.0 else -0.7):
			return false
	var back := p - d * 1.0
	if land.height_at(back.x, back.y) < h - 0.05:
		return false
	if not standing and (world.town.is_built(p) or world.town.is_built(back)):
		return false
	# clear of streets all the way out (a bridge may cross the water here)
	for s: Streets.Street in world.streets.streets:
		if not s.near_box(p, PIER_LEN + 3.0):
			continue
		var t := 0.0
		while t <= PIER_LEN:
			if s.closest(p + d * t).x < s.reach() + 0.8:
				return false
			t += 1.5
	return true


## The middle of the harbour quarter (or of the whole town), where the pier should be near.
func _harbour_centre() -> Variant:
	for pass_i in 2:
		var sum := Vector2.ZERO
		var n := 0
		for l: Town.Lot in world.town.lots.values():
			if l.type == "house" and (pass_i == 1 or l.kit == HouseGen.HARBOUR):
				sum += l.origin
				n += 1
		if n > 0:
			return sum / n
	return null


## Where `kind` should stand, looked for all at once (loads and tests).
func _find(kind: String) -> Variant:
	var search := _search_start(kind)
	if search.is_empty():
		return null
	_search_step(search, -1)
	return search.at


## A search for where `kind` should stand: the spots to try and how to rate
## each. _search_step() works through them a slice of time at a time.
func _search_start(kind: String) -> Dictionary:
	var pts := PackedVector2Array()
	var origin := Vector2.ZERO
	if kind == "pier":
		var c: Variant = _harbour_centre()
		if c == null:
			return {}
		origin = c
		for gx in range(-30, 31):
			for gz in range(-30, 31):
				pts.append(origin + Vector2(gx, gz))
	elif RETAIL.has(kind):
		var shops := _retail()
		if shops.is_empty():
			return {}
		for q in shops:
			origin += q
		origin /= shops.size()
		for gx in range(-20, 21):
			for gz in range(-20, 21):
				pts.append(origin + Vector2(gx, gz) * 2.0)
	elif kind == "airport":
		# out in the country round the town, on a coarser grid
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		var n := 0
		for l: Town.Lot in world.town.lots.values():
			lo = lo.min(l.origin)
			hi = hi.max(l.origin)
			origin += l.origin
			n += 1
		if n == 0:
			return {}
		origin /= n
		lo = (lo - Vector2(70, 70)).max(Vector2(-Land.HALF + 26.0, -Land.HALF + 26.0))
		hi = (hi + Vector2(70, 70)).min(Vector2(Land.HALF - 26.0, Land.HALF - 26.0))
		var x := snappedf(lo.x, 4.0)
		while x < hi.x:
			var z := snappedf(lo.y, 4.0)
			while z < hi.y:
				pts.append(Vector2(x, z))
				z += 4.0
			x += 4.0
	else:
		# only round the town: the map is far bigger than anyone would walk
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for st: Streets.Street in world.streets.streets:
			lo = lo.min(st.lo)
			hi = hi.max(st.hi)
		if lo.x > hi.x:
			return {}
		lo = (lo - Vector2(SEARCH, SEARCH)).max(Vector2(-Land.HALF + 6.0, -Land.HALF + 6.0))
		hi = (hi + Vector2(SEARCH, SEARCH)).min(Vector2(Land.HALF - 6.0, Land.HALF - 6.0))
		var x := snappedf(lo.x, 2.0)
		while x < hi.x:
			var z := snappedf(lo.y, 2.0)
			while z < hi.y:
				pts.append(Vector2(x, z))
				z += 2.0
			x += 2.0
	return {"kind": kind, "pts": pts, "i": 0, "origin": origin, "best": -INF, "at": null, "yaw": 0.0}


## Tries the search's next spots for up to `budget_us` (all of them if < 0).
## Returns whether it has tried them all.
func _search_step(search: Dictionary, budget_us: int) -> bool:
	var start := Time.get_ticks_usec()
	var pts: PackedVector2Array = search.pts
	var kind: String = search.kind
	while search.i < pts.size():
		var p := pts[search.i]
		search.i += 1
		var score := _score(kind, p, search.origin)
		if kind == "airport":
			# the runway may point four ways
			if score > search.best:
				for k in 4:
					var yaw: float = (search.origin as Vector2).angle_to_point(p) + k * PI * 0.25
					if _airport_fits(p, yaw, false):
						search.best = score
						search.at = p
						search.yaw = yaw
						break
		elif score > search.best and (_pier_fits(p, false) if kind == "pier" else _fits(kind, p)):
			search.best = score
			search.at = p
		if budget_us >= 0 and Time.get_ticks_usec() - start > budget_us:
			return false
	return true


## How good a spot is for `kind` before the closer look (-INF: no good):
## the pier and the attractions as near the middle of their quarter as can
## be, the lighthouse looking out over the most sea, the windmill up high.
func _score(kind: String, p: Vector2, origin: Vector2) -> float:
	var land := world.land
	if kind == "pier":
		if absf(p.x) > Land.HALF - 8.0 or absf(p.y) > Land.HALF - 8.0:
			return -INF
		return -p.distance_to(origin)
	if RETAIL.has(kind):
		if absf(p.x) > Land.HALF - 10.0 or absf(p.y) > Land.HALF - 10.0:
			return -INF
		for other in spots:
			if p.distance_to(spots[other]) < float(ROOM[kind]) + float(ROOM[other]) + 2.0:
				return -INF
		return -p.distance_to(origin)
	if kind == "airport":
		# out of town, but not too far out: about 45 m from its middle
		for other in spots:
			if other != "airport" and p.distance_to(spots[other]) < float(ROOM[other]) + 26.0:
				return -INF
		return -absf(p.distance_to(origin) - 45.0)
	var h := land.height_at(p.x, p.y)
	if kind == "lighthouse" and h > 0.3 and h < 6.0:
		# how much of the view all round is open sea
		var sea := 0
		for k in 16:
			var q := p + Vector2.from_angle(k * TAU / 16.0) * 7.0
			sea += int(land.height_at(q.x, q.y) < -0.3)
		return sea * 10.0 + h if sea >= 6 else -INF
	if kind == "windmill" and h > 1.2:
		if spots.has("lighthouse") and p.distance_to(spots.lighthouse) < 12.0:
			return -INF
		return h
	return -INF


# ------------------------------------------------------------------ building

func _remove(kind: String) -> void:
	var n: Node3D = _nodes.get(kind)
	if n:
		for mi in n.find_children("*", "MeshInstance3D", true, false):
			_spin.erase(mi)
			if mi == _beam:
				_beam = null
		n.queue_free()
	_nodes.erase(kind)
	spots.erase(kind)
	world.town.unreserve(kind)


func _place(kind: String, p: Vector2) -> void:
	spots[kind] = p
	var land := world.land
	if kind == "airport":
		world.town.reserve_box(kind, p, AIRPORT + Vector2(0.6, 0.6), airport_yaw)
		_place_airport(p)
		return
	world.town.reserve(kind, p, float(ROOM[kind]) + 0.6)
	if kind == "pier":
		_place_pier(p)
		return
	# stand on the lowest ground under it, the plinth hides the rest of the slope
	var y := land.height_at(p.x, p.y)
	for k in 8:
		var q := p + Vector2.from_angle(k * TAU / 8.0) * float(ROOM[kind]) * 0.6
		y = minf(y, land.height_at(q.x, q.y))
	var root := Node3D.new()
	root.position = Vector3(p.x, y, p.y)
	add_child(root)
	_nodes[kind] = root
	# face the middle of the island (the windmill's sails, the keeper's cottage)
	var yaw := atan2(-p.x, -p.y)
	var mk := MeshKit.new(hash(kind))
	mk.push_at(Vector3.ZERO, yaw)
	match kind:
		"lighthouse": _lighthouse(mk, root)
		"stadium": _stadium(mk, hash(p))
		"wheel": _wheel(mk, root, yaw)
		_: _windmill(mk, root, yaw)
	mk.pop()
	var body := MeshInstance3D.new()
	body.mesh = mk.commit(world.city_mat)
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(body)
	var sm := mk.commit_shadow(Palette.shadow_material())
	if sm:
		var sh := MeshInstance3D.new()
		sh.mesh = sm
		sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		root.add_child(sh)


## The airport, stood on a level field raised over the highest ground under
## it (its sides hide the slope), runway along local +Z.
func _place_airport(p: Vector2) -> void:
	var land := world.land
	var right := Vector2(cos(airport_yaw), -sin(airport_yaw))
	var fwd := Vector2(sin(airport_yaw), cos(airport_yaw))
	var lo := INF
	var hi := -INF
	var gx := -AIRPORT.x
	while gx <= AIRPORT.x + 0.01:
		var gz := -AIRPORT.y
		while gz <= AIRPORT.y + 0.01:
			var q := p + right * gx + fwd * gz
			lo = minf(lo, land.height_at(q.x, q.y))
			hi = maxf(hi, land.height_at(q.x, q.y))
			gz += 2.0
		gx += 2.0
	var root := Node3D.new()
	root.position = Vector3(p.x, hi + 0.05, p.y)
	root.rotation.y = airport_yaw
	add_child(root)
	_nodes["airport"] = root
	var mk := MeshKit.new(hash("airport"))
	_airport(mk, lo - hi - 0.15, hash(p))
	var body := MeshInstance3D.new()
	body.mesh = mk.commit(world.city_mat)
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(body)
	var sm := mk.commit_shadow(Palette.shadow_material())
	if sm:
		var sh := MeshInstance3D.new()
		sh.mesh = sm
		sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		root.add_child(sh)
	# an airliner at one of the gates, nose to the terminal (one: the view
	# from all the way out is near its triangle budget)
	var planes: Planes = world.planes
	if planes and not planes._kinds.is_empty():
		for k in 1:
			var mi := MeshInstance3D.new()
			mi.mesh = planes._kinds[(hash(p) + k) % planes._kinds.size()]
			# like the ones in the air, they cast no shadow (the airliner is
			# fine and costly to shadow)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.position = Vector3(1.6, Planes.GROUND, -5.0 + (hash(p) % 2) * 10.0)
			mi.rotation.y = PI * 0.5
			root.add_child(mi)


## The airport's buildings and paving, in its own frame: the field, the
## runway with its markings and lights, the taxiway, the apron, the terminal
## with its jet bridges, the control tower and a hangar. `drop` is how far
## down the field's sides reach.
func _airport(mk: MeshKit, drop: float, seed_value: int) -> void:
	var hx := AIRPORT.x
	var hz := AIRPORT.y
	# the field itself, its sides down to the ground
	mk.shadow = false
	mk.box(Vector3(0, drop * 0.5, 0), Vector3(hx * 2.0, -drop, hz * 2.0), FIELD.darkened(0.3), FIELD)
	var top := 0.0
	# the runway, its centre line, thresholds and numbers, and edge lights
	var rx := RUNWAY_X
	_flat(mk, rx, 0.0, 1.3, RUNWAY_HALF, top + 0.02, TARMAC)
	var z := -RUNWAY_HALF + 4.0
	while z < RUNWAY_HALF - 4.0:
		_flat(mk, rx, z + 0.6, 0.05, 0.6, top + 0.03, WHITE)
		z += 2.4
	for e: float in [-1.0, 1.0]:
		for k in 6:
			var x := rx - 1.0 + k * 0.4 + (0.2 if k >= 3 else 0.0)
			_flat(mk, x, e * (RUNWAY_HALF - 1.0), 0.1, 0.7, top + 0.03, WHITE)
		# the touchdown zone
		for sx: float in [-0.6, 0.6]:
			_flat(mk, rx + sx, e * (RUNWAY_HALF - 6.0), 0.12, 0.9, top + 0.03, WHITE)
	# the lights: flush with the tarmac, a lit square each, edges white,
	# ends green and red
	z = -RUNWAY_HALF + 0.5
	while z <= RUNWAY_HALF - 0.4:
		for sx: float in [-1.4, 1.4]:
			mk.box_faces(Vector3(rx + sx, top + 0.04, z), Vector3(0.09, 0.02, 0.09), Color(1.0, 0.95, 0.75), MeshKit.TOP, 2.0)
		z += 3.0
	for e: float in [-1.0, 1.0]:
		for sx in 5:
			mk.box_faces(Vector3(rx - 1.0 + sx * 0.5, top + 0.04, e * (RUNWAY_HALF - 0.15)), Vector3(0.09, 0.02, 0.09), Color(0.35, 1.0, 0.45) if e < 0.0 else Color(1.0, 0.25, 0.2), MeshKit.TOP, 2.0)
	# the taxiway beside it, joined to each end, and the apron
	_flat(mk, -1.6, 0.0, 0.6, RUNWAY_HALF - 3.0, top + 0.02, TARMAC)
	for e: float in [-1.0, 1.0]:
		_flat(mk, (rx + 1.3 - 1.0) * 0.5, e * (RUNWAY_HALF - 3.6), (-1.0 - rx - 1.3) * 0.5 + 0.1, 0.6, top + 0.021, TARMAC)
	for e: float in [-1.0, 1.0]:
		_flat(mk, -0.6, e * 5.0, 0.5, 0.5, top + 0.021, TARMAC)
	_flat(mk, 2.5, 0.0, 2.6, 11.0, top + 0.02, APRON)
	# a yellow line out to each gate
	for k in 2:
		_flat(mk, 1.8, -5.0 + k * 10.0, 2.0, 0.04, top + 0.03, Color("e3b53a"))
	mk.shadow = true
	# the terminal: a long low hall, glass along the airside, a wavy roof
	var tw := 2.8
	var tx := 5.1 + tw * 0.5
	var th := 1.5
	mk.box(Vector3(tx, top + th * 0.5, 0), Vector3(tw, th, 20.0), Color(0.88, 0.89, 0.9), Color(0.75, 0.78, 0.8))
	mk.box_faces(Vector3(tx - tw * 0.5 - 0.006, top + th * 0.55, 0), Vector3(0.012, th * 0.7, 19.4), Color(0.36, 0.5, 0.6), MeshKit.LEFT, 1.0)
	mk.box_faces(Vector3(tx + tw * 0.5 + 0.006, top + th * 0.4, 0), Vector3(0.012, th * 0.5, 19.0), Color(0.42, 0.55, 0.62), MeshKit.RIGHT, 2.0)
	mk.box(Vector3(tx, top + th + 0.08, 0), Vector3(tw + 0.5, 0.12, 20.6), Color(0.95, 0.95, 0.94))
	# a canopy over the kerb on the landside
	mk.box(Vector3(tx + tw * 0.5 + 0.35, top + 0.62, 0), Vector3(0.7, 0.05, 14.0), Color(0.95, 0.95, 0.94))
	# the jet bridges out to the gates
	for k in 2:
		var gz := -5.0 + k * 10.0
		mk.box(Vector3(4.1, top + 0.55, gz), Vector3(2.0, 0.28, 0.32), Color(0.8, 0.82, 0.84))
		mk.pole(Vector3(3.3, top, gz), 0.04, 0.42, 4, Color(0.4, 0.42, 0.45))
	# the name along the roof, lit at night
	mk.box(Vector3(tx + tw * 0.5 + 0.04, top + th - 0.25, 0), Vector3(0.06, 0.28, 5.0), Color(0.25, 0.5, 0.9), null, false, 2.7)
	# the control tower beyond the terminal's end
	var c := Vector3(5.6, top, 13.5)
	mk.cylinder(c, 0.38, 4.6, 8, Color(0.9, 0.9, 0.88), false)
	mk.cylinder(c + Vector3(0, 4.6, 0), 0.75, 0.12, 8, Color(0.85, 0.86, 0.87), true)
	mk.cylinder(c + Vector3(0, 4.72, 0), 0.68, 0.55, 8, Color(0.3, 0.42, 0.5), false, null, 0.74, 1.0)
	mk.cylinder(c + Vector3(0, 5.27, 0), 0.8, 0.12, 8, Color(0.85, 0.86, 0.87), true, Color(0.7, 0.72, 0.74))
	mk.pole(c + Vector3(0, 5.39, 0), 0.03, 0.7, 4, Color(0.8, 0.8, 0.8))
	mk.box(c + Vector3(0, 6.1, 0), Vector3(0.1, 0.1, 0.1), Color(1.0, 0.15, 0.1), null, false, 2.7)
	# a hangar with its doors open to the apron, a plane's tail inside
	var hz0 := -15.5
	mk.box(Vector3(3.2, top + 1.0, hz0), Vector3(4.6, 2.0, 5.0), Color(0.72, 0.74, 0.76), null, false, MeshKit.SIDING)
	mk.gable_roof(Vector3(3.2, top + 2.0, hz0), 5.0, 4.6, 0.6, 0.1, Color(0.52, 0.56, 0.6), Color(0.72, 0.74, 0.76), 0.06)
	mk.box_faces(Vector3(0.89, top + 0.85, hz0), Vector3(0.02, 1.6, 4.0), Color(0.15, 0.17, 0.2), MeshKit.LEFT)
	# a windsock by the runway
	var wsx := rx + 2.6
	mk.pole(Vector3(wsx, top, 6.0), 0.025, 0.9, 4, Color(0.8, 0.8, 0.8))
	mk.cone(Vector3(wsx, top + 0.85, 6.15), 0.08, 0.35, 6, Color("f07a2e"))


## A flat rectangle on the field, `w` and `d` half its width and length.
func _flat(mk: MeshKit, x: float, z: float, w: float, d: float, y: float, col: Color) -> void:
	mk.quad(Vector3(x - w, y, z + d), Vector3(x + w, y, z + d), Vector3(x + w, y, z - d), Vector3(x - w, y, z - d), Vector3.UP, col)


func _place_pier(p: Vector2) -> void:
	var land := world.land
	var d := _seaward(p)
	var root := Node3D.new()
	root.position = Vector3(p.x, 0.0, p.y)
	add_child(root)
	_nodes["pier"] = root
	var yaw := atan2(d.x, d.y)
	var deck := maxf(land.height_at(p.x, p.y), 0.0) + 0.22
	var side := Vector2(d.y, -d.x)
	var mk := MeshKit.new(hash("pier"))
	# local +Z runs out to sea
	mk.push_at(Vector3.ZERO, yaw)
	mk.box(Vector3(0, deck - 0.04, PIER_LEN * 0.5 - 0.6), Vector3(0.9, 0.08, PIER_LEN + 1.2), PLANK, null, false, MeshKit.SIDING)
	mk.box(Vector3(0, deck - 0.04, PIER_LEN + 0.4), Vector3(2.6, 0.08, 1.4), PLANK, null, false, MeshKit.SIDING)
	# posts down to the sea bed, a pair every metre and a half
	var z := 0.6
	while z <= PIER_LEN + 1.0:
		var wide := z > PIER_LEN - 0.3
		for sx: float in ([-1.2, 1.2] if wide else [-0.4, 0.4]):
			var w: Vector2 = p + d * z - side * sx
			var bed := minf(land.height_at(w.x, w.y), -0.1)
			mk.pole(Vector3(sx, bed, z), 0.05, deck - 0.06 - bed, 5, Color(0.42, 0.32, 0.24))
		z += 1.5
	# rails, and lamps and a bench out at the end
	for sx: float in [-1.0, 1.0]:
		mk.box(Vector3(sx * 0.43, deck + 0.22, PIER_LEN * 0.5 - 0.2), Vector3(0.03, 0.03, PIER_LEN - 0.6), WHITE)
		mk.box(Vector3(sx * 1.28, deck + 0.22, PIER_LEN + 0.4), Vector3(0.03, 0.03, 1.3), WHITE)
		var k := 0.4
		while k < PIER_LEN - 0.4:
			mk.box(Vector3(sx * 0.43, deck + 0.11, k), Vector3(0.03, 0.22, 0.03), WHITE)
			k += 1.0
		CivicGen._lamp(mk, Vector3(sx * 1.15, deck, PIER_LEN + 0.95))
	mk.box(Vector3(0, deck + 0.22, PIER_LEN + 1.08), Vector3(2.56, 0.03, 0.03), WHITE)
	CivicGen._bench(mk, Vector3(0.6, deck, PIER_LEN + 0.7), PI)
	# two anglers sit on the edge of the end, rods out over the water
	for a in [[-0.75, Color("3fae8c")], [0.45, Color("f2c14e")]]:
		_angler(mk, Vector3(a[0], deck, PIER_LEN + 1.08), a[1])
	# a striped kiosk where the pier meets the shore
	mk.rbox(Vector3(-0.75, deck + 0.22, 0.2), Vector3(0.5, 0.44, 0.44), 0.03, WHITE, null, false, MeshKit.SIDING)
	mk.window(Vector3(-0.75, deck + 0.28, 0.43), Vector3.BACK, 0.34, 0.16, Palette.GLASS_LIGHT, Color(0, 0, 0, 0), true)
	mk.cone(Vector3(-0.75, deck + 0.44, 0.2), 0.42, 0.24, 8, Color("e85d5d"))
	# rowing boats tied up alongside
	for b in [[1.1, 2.6, 0.2, Color("3d5f8f")], [-1.05, 4.6, -0.15, Color("c8553d")]]:
		mk.push_at(Vector3(b[0], 0.04, b[1]), b[2])
		mk.rbox(Vector3(0, 0.06, 0), Vector3(0.4, 0.14, 1.0), 0.07, b[3])
		mk.box(Vector3(0, 0.11, 0), Vector3(0.32, 0.03, 0.86), Color(0.86, 0.74, 0.55))
		mk.box(Vector3(0, 0.15, 0.05), Vector3(0.34, 0.03, 0.1), PLANK)
		mk.pop()
	mk.pop()
	var body := MeshInstance3D.new()
	body.mesh = mk.commit(world.city_mat)
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(body)
	var sm := mk.commit_shadow(Palette.shadow_material())
	if sm:
		var sh := MeshInstance3D.new()
		sh.mesh = sm
		sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		root.add_child(sh)


## A little figure sitting on the deck edge at `at`, legs over the water
## (local +Z), holding a rod whose line drops into the sea.
func _angler(mk: MeshKit, at: Vector3, shirt: Color) -> void:
	var pants := Color("3d4a5c")
	for sx: float in [-0.028, 0.028]:
		mk.box(at + Vector3(sx, 0.012, 0.05), Vector3(0.045, 0.045, 0.11), pants)
		mk.box(at + Vector3(sx, -0.05, 0.1), Vector3(0.04, 0.1, 0.04), pants)
	mk.rbox(at + Vector3(0, 0.09, -0.01), Vector3(0.11, 0.11, 0.07), 0.025, shirt)
	mk.blob(at + Vector3(0, 0.19, 0), Vector3(0.043, 0.045, 0.043), Color("d9a77c"))
	mk.cone(at + Vector3(0, 0.216, 0), 0.06, 0.014, 7, Color("e9d8a6"))
	mk.cylinder(at + Vector3(0, 0.229, 0), 0.035, 0.03, 6, Color("e9d8a6"))
	# the rod angles up and out; the line hangs from its tip to the water
	var butt := at + Vector3(0.05, 0.08, 0.06)
	var rod := Vector3(0.05, 0.26, 0.46)
	var up := rod.normalized()
	var x := up.cross(Vector3.BACK).normalized()
	mk.push(Transform3D(Basis(x, up, x.cross(up)), butt))
	# a real cylinder: a pole would be drawn as an upright sprite
	mk.cylinder(Vector3.ZERO, 0.008, rod.length(), 4, Color(0.2, 0.18, 0.16), false)
	mk.pop()
	var tip := butt + rod
	mk.box(Vector3(tip.x, tip.y * 0.5, tip.z), Vector3(0.006, tip.y, 0.006), Color(0.92, 0.92, 0.92))
	mk.blob(Vector3(tip.x, 0.03, tip.z), Vector3(0.025, 0.025, 0.025), Color("e85d5d"))


func _lighthouse(mk: MeshKit, root: Node3D) -> void:
	mk.rbox(Vector3(0, -0.2, 0), Vector3(1.6, 0.6, 1.6), 0.1, STONE)
	var hgt := 3.4
	var seg := 5
	for k in seg:
		var r0 := 0.5 - k * 0.05
		var r1 := 0.5 - (k + 1) * 0.05
		mk.cylinder(Vector3(0, 0.1 + k * hgt / seg, 0), r0, hgt / seg, 16, WHITE if k % 2 == 0 else RED, false, null, r1)
	var top := 0.1 + hgt
	mk.cylinder(Vector3(0, top, 0), 0.42, 0.08, 16, Color(0.25, 0.27, 0.3))
	# the gallery rail round the lantern
	for k in 12:
		var a := TAU * k / 12.0
		mk.box(Vector3(cos(a) * 0.4, top + 0.16, sin(a) * 0.4), Vector3(0.02, 0.16, 0.02), Color(0.25, 0.27, 0.3))
	mk.cylinder(Vector3(0, top + 0.08, 0), 0.24, 0.42, 12, Color(1, 0.9, 0.6), false, null, -1.0, 2.0)
	mk.cone(Vector3(0, top + 0.5, 0), 0.34, 0.36, 12, RED)
	mk.blob(Vector3(0, top + 0.9, 0), Vector3(0.06, 0.06, 0.06), Color(0.25, 0.27, 0.3))
	for k in 2:
		mk.window(Vector3(0, 1.0 + k * 1.2, 0.46 - k * 0.06), Vector3.BACK, 0.14, 0.22, Palette.GLASS, WHITE)
	mk.rbox(Vector3(0, 0.3, 0.42), Vector3(0.22, 0.4, 0.1), 0.03, Color(0.35, 0.42, 0.5))
	# the keeper's cottage on the landward side
	mk.rbox(Vector3(0, 0.35, 1.05), Vector3(0.9, 0.7, 0.7), 0.05, WHITE)
	mk.push_at(Vector3(0, 0.7, 1.05), PI * 0.5)
	mk.gable_roof(Vector3.ZERO, 0.7, 0.9, 0.34, 0.06, RED, WHITE)
	mk.pop()
	mk.window(Vector3(0.22, 0.4, 1.41), Vector3.BACK, 0.18, 0.2, Palette.GLASS, WHITE, true)
	mk.rbox(Vector3(-0.2, 0.25, 1.41), Vector3(0.18, 0.36, 0.04), 0.02, Color(0.35, 0.42, 0.5))
	mk.cylinder(Vector3(0.3, 0.9, 1.15), 0.06, 0.24, 6, Color(0.8, 0.5, 0.4))
	# the turning beam, out both sides of the lamp, only lit at night
	_beam = _spinner(root, _beam_mesh(), Vector3(0, top + 0.28, 0), Vector3.UP, 0.9)
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## A stadium: an oval bowl of stands in the team's colours round a striped
## pitch, a white roof over the upper tier and four floodlight masts.
func _stadium(mk: MeshKit, seed_value: int) -> void:
	var team: Array = TEAM[posmod(seed_value, TEAM.size())]
	var n := 24
	var rx := 6.2
	var rz := 4.7
	var ring := func(k: int, s: float, y: float) -> Vector3:
		var a := TAU * k / n
		return Vector3(cos(a) * rx * s, y, sin(a) * rz * s)
	var concrete := Color(0.86, 0.85, 0.82)
	for k in n:
		# down into the ground, so a slope never shows under it
		var a0: Vector3 = ring.call(k, 1.0, -0.6)
		var b0: Vector3 = ring.call(k + 1, 1.0, -0.6)
		var a1: Vector3 = ring.call(k, 1.0, 1.35)
		var b1: Vector3 = ring.call(k + 1, 1.0, 1.35)
		var out := ((a0 + b0) * 0.5).normalized()
		# the outer wall, with a band of the team's colour round the top
		mk.quad(a0, b0, b1, a1, out, concrete)
		mk.quad(a1, b1, ring.call(k + 1, 1.0, 1.6), ring.call(k, 1.0, 1.6), out, team[0])
		# two tiers of seats stepping down to the pitch, in stripes
		var seat: Color = team[k % 2] if k % 6 < 3 else team[(k + 1) % 2]
		mk.quad(ring.call(k, 0.97, 1.5), ring.call(k + 1, 0.97, 1.5), ring.call(k + 1, 0.8, 0.85), ring.call(k, 0.8, 0.85), Vector3.UP, seat.darkened(0.05))
		mk.quad(ring.call(k, 0.8, 0.8), ring.call(k + 1, 0.8, 0.8), ring.call(k + 1, 0.64, 0.25), ring.call(k, 0.64, 0.25), Vector3.UP, seat)
		# the roof over the upper tier
		mk.quad(ring.call(k, 1.02, 1.85), ring.call(k + 1, 1.02, 1.85), ring.call(k + 1, 0.84, 1.75), ring.call(k, 0.84, 1.75), Vector3.UP, Color(0.95, 0.95, 0.94))
		mk.shadow = false
		mk.quad(ring.call(k, 1.02, 1.84), ring.call(k + 1, 1.02, 1.84), ring.call(k + 1, 0.84, 1.74), ring.call(k, 0.84, 1.74), Vector3.DOWN, Color(0.7, 0.7, 0.72))
		mk.shadow = true
	# the pitch, mown in stripes, with its lines, on a level floor
	mk.shadow = false
	for k in n:
		mk.tri(Vector3(0, 0.24, 0), ring.call(k, 0.65, 0.24), ring.call(k + 1, 0.65, 0.24), Color("4a8f42"), 0.0, 0.0, Vector3.UP)
	var px := rx * 0.5
	var pz := rz * 0.48
	for k in 6:
		var x0 := -px + 2.0 * px * k / 6.0
		var x1 := -px + 2.0 * px * (k + 1) / 6.0
		var g := Color("4f9a45") if k % 2 == 0 else Color("5ba851")
		mk.quad(Vector3(x0, 0.26, -pz), Vector3(x1, 0.26, -pz), Vector3(x1, 0.26, pz), Vector3(x0, 0.26, pz), Vector3.UP, g)
	var white := Color(0.97, 0.97, 0.95)
	for side in [[Vector3(-px, 0.27, -pz), Vector3(px, 0.27, -pz)], [Vector3(-px, 0.27, pz), Vector3(px, 0.27, pz)], [Vector3(0, 0.27, -pz), Vector3(0, 0.27, pz)]]:
		var a: Vector3 = side[0]
		var b: Vector3 = side[1]
		var w := (b - a).normalized().cross(Vector3.UP) * 0.03
		mk.quad(a - w, b - w, b + w, a + w, Vector3.UP, white)
	for sx in [-1.0, 1.0]:
		mk.quad(Vector3(sx * px - 0.03, 0.27, -pz), Vector3(sx * px + 0.03, 0.27, -pz), Vector3(sx * px + 0.03, 0.27, pz), Vector3(sx * px - 0.03, 0.27, pz), Vector3.UP, white)
	mk.shadow = true
	# floodlights on the four corners, bright at night
	for k in 4:
		var a := PI * 0.25 + PI * 0.5 * k
		var foot := Vector3(cos(a) * rx * 1.04, 0.0, sin(a) * rz * 1.04)
		mk.cylinder(foot, 0.07, 3.2, 4, Color(0.7, 0.72, 0.75), false, null, 0.045)
		var face := -Vector3(foot.x, 0, foot.z).normalized()
		mk.push(Transform3D(Basis(Vector3.UP, atan2(face.x, face.z)), foot + Vector3(0, 3.25, 0)))
		mk.box(Vector3.ZERO, Vector3(0.6, 0.35, 0.06), Color(0.95, 0.97, 1.0), null, false, 2.7)
		mk.pop()


## A Ferris wheel: two white A-frames holding a turning wheel of coloured
## gondolas, its rim lit up at night, and a ticket kiosk at its foot.
func _wheel(mk: MeshKit, root: Node3D, yaw: float) -> void:
	var white := Color(0.95, 0.95, 0.94)
	var r := 2.1
	var hub := r + 0.5
	mk.rbox(Vector3(0, -0.15, 0), Vector3(2.0, 0.4, 1.6), 0.1, STONE)
	for sz in [-0.45, 0.45]:
		for sx in [-1.0, 1.0]:
			# legs leaning in to the axle
			var foot := Vector3(sx * 1.1, 0.0, sz)
			var top := Vector3(0, hub, sz)
			var up := (top - foot).normalized()
			var x := up.cross(Vector3.BACK).normalized()
			mk.push(Transform3D(Basis(x, up, x.cross(up)), foot))
			mk.box(Vector3(0, (top - foot).length() * 0.5, 0), Vector3(0.1, (top - foot).length(), 0.1), white)
			mk.pop()
	mk.rbox(Vector3(0.9, 0.3, 0.75), Vector3(0.5, 0.5, 0.4), 0.05, Color("e3a33b"))
	var wheel := MeshKit.new(7)
	var cabins := [Color("c8553d"), Color("3f8cff"), Color("e3a33b"), Color("2f8f83"), Color("ff6fae"), Color("8ad14a")]
	var n := 16
	for k in n:
		var a0 := TAU * k / n
		var a1 := TAU * (k + 1) / n
		var p0 := Vector3(cos(a0), sin(a0), 0) * r
		var p1 := Vector3(cos(a1), sin(a1), 0) * r
		var m := (p0 + p1) * 0.5
		# the rim, two rings of lights tied together
		wheel.push(Transform3D(Basis(Vector3.BACK, (a0 + a1) * 0.5 + PI * 0.5), m))
		for sz in [-0.3, 0.3]:
			wheel.box(Vector3(0, 0, sz), Vector3(p0.distance_to(p1), 0.07, 0.07), Color(1.0, 0.85, 0.55), null, false, 2.7)
		wheel.pop()
		if k % 2 == 0:
			# a spoke to each side of the rim, and a gondola hanging from it
			wheel.push(Transform3D(Basis(Vector3.BACK, a0 - PI * 0.5), Vector3.ZERO))
			wheel.box(Vector3(0, r * 0.5, 0), Vector3(0.04, r, 0.6), white)
			wheel.pop()
			wheel.box(p0 * 1.04 + Vector3(0, -0.2, 0), Vector3(0.3, 0.3, 0.4), cabins[(k / 2) % cabins.size()])
	wheel.cylinder(Vector3(0, 0, -0.4), 0.16, 0.8, 8, white)
	var turn := _spinner(root, wheel.commit(world.city_mat), Vector3(0, hub, 0).rotated(Vector3.UP, yaw), Vector3.BACK, 0.12)
	turn.get_parent().rotation.y = yaw
	var sh := MeshInstance3D.new()
	sh.mesh = wheel.commit_shadow(Palette.shadow_material())
	sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	turn.add_child(sh)
	turn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _windmill(mk: MeshKit, root: Node3D, yaw: float) -> void:
	mk.cylinder(Vector3(0, -0.4, 0), 0.72, 0.5, 14, STONE)
	mk.cylinder(Vector3(0, 0.1, 0), 0.62, 2.2, 14, Color(0.93, 0.9, 0.84), false, null, 0.42)
	mk.cone(Vector3(0, 2.3, 0), 0.52, 0.6, 14, Color("8b5a44"))
	mk.rbox(Vector3(0, 0.38, 0.58), Vector3(0.3, 0.56, 0.1), 0.04, Color(0.45, 0.3, 0.22))
	mk.window(Vector3(0, 1.4, 0.52), Vector3.BACK, 0.18, 0.24, Palette.GLASS, WHITE, true)
	mk.rbox(Vector3(0, 2.1, 0.5), Vector3(0.16, 0.16, 0.3), 0.04, Color(0.4, 0.3, 0.22))
	# a little railed balcony half way up, and sacks by the door
	mk.cylinder(Vector3(0, 1.05, 0), 0.66, 0.05, 14, TIMBER)
	for k in 3:
		mk.blob(Vector3(0.45 + k * 0.12, 0.08, 0.6 - k * 0.08), Vector3(0.08, 0.1, 0.08), Color(0.86, 0.78, 0.6))
	var blades := MeshKit.new()
	for k in 4:
		blades.push(Transform3D(Basis(Vector3.BACK, TAU * k / 4.0), Vector3.ZERO))
		blades.box(Vector3(0, 0.8, 0), Vector3(0.06, 1.6, 0.04), TIMBER)
		blades.box(Vector3(0.14, 0.95, 0.0), Vector3(0.24, 1.15, 0.02), Color(0.97, 0.95, 0.9))
		blades.pop()
	blades.blob(Vector3.ZERO, Vector3(0.1, 0.1, 0.1), Color(0.35, 0.27, 0.2))
	var out := Vector3(sin(yaw), 0, cos(yaw))
	var sail := _spinner(root, blades.commit(world.city_mat), out * 0.68 + Vector3(0, 2.1, 0), Vector3.BACK, 0.7)
	sail.get_parent().rotation.y = yaw
	var sh := MeshInstance3D.new()
	sh.mesh = blades.commit_shadow(Palette.shadow_material())
	sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	sail.add_child(sh)
	sail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _spinner(root: Node3D, mesh: ArrayMesh, pos: Vector3, axis: Vector3, speed: float) -> MeshInstance3D:
	var pivot := Node3D.new()
	pivot.position = pos
	root.add_child(pivot)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.set_meta("axis", axis)
	mi.set_meta("speed", speed)
	pivot.add_child(mi)
	_spin.append(mi)
	return mi


## Two soft cones out both sides of the lamp, angled down to meet the sea
## about 14 m out: a wide glow around a brighter narrow core.
func _beam_mesh() -> ArrayMesh:
	var v := PackedVector3Array()
	var nrm := PackedVector3Array()
	var c := PackedColorArray()
	var sides := 10
	var warm := Color(1, 0.92, 0.66)
	for layer in [[1.7, 0.16], [0.7, 0.32]]:
		var rad: float = layer[0]
		var alpha: float = layer[1]
		for s in [-1.0, 1.0]:
			var axis := Vector3(s * 14.0, -4.6, 0.0)
			var fwd := axis.normalized()
			var up := fwd.cross(Vector3.BACK).normalized()
			var side := fwd.cross(up).normalized()
			for i in sides:
				var a0 := TAU * i / sides
				var a1 := TAU * (i + 1) / sides
				var d0 := up * cos(a0) + side * sin(a0)
				var d1 := up * cos(a1) + side * sin(a1)
				v.append_array([Vector3.ZERO, axis + d0 * rad, axis + d1 * rad])
				nrm.append_array([(d0 + d1).normalized(), d0, d1])
				c.append_array([Color(warm, alpha), Color(warm, 0.0), Color(warm, 0.0)])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = nrm
	arrays[Mesh.ARRAY_COLOR] = c
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	m.surface_set_material(0, beam_mat)
	return m
