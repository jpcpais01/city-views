class_name Traffic
extends Node3D
## The traffic on the streets: cars and vans keeping to their lane, buses
## stopping now and then along the main roads, lorries coming and going from
## the works, faster on avenues and fastest on highways, queueing behind the
## car ahead. More of it as the city grows. One MultiMesh per vehicle style
## keeps every vehicle of a style to a single draw call.

const CAR_COLORS := [Color("ef5b5b"), Color("4b86d6"), Color("f2c14e"), Color("f5f5f2"), Color("3fae8c"), Color("ef7fa8"), Color("6c7a89"), Color("ff9248")]
const BUS_COLORS := [Color("d9483b"), Color("2f8f83")]
const TRUCK_COLORS := [Color("f2f0ea"), Color("e0a43a"), Color("4b6fa8")]
## vehicle styles, in mesh order: [kind, colour]
var STYLES: Array = []
## how fast each kind of street is driven (m/s at toy scale)
const SPEEDS := {"side": 1.15, "main": 1.6, "avenue": 2.1, "highway": 3.1}
## how often a street of each kind is picked for a new vehicle, per metre
const BUSY := {"side": 0.6, "main": 1.0, "avenue": 2.0, "highway": 2.6}
const LENGTHS := {"car": 0.62, "van": 0.7, "bus": 1.5, "truck": 1.15}
const MAX_CARS := 150
const MAX_BUSES := 8
## the room a vehicle leaves to the one ahead, in metres
const GAP := 0.35

var material: Material
var streets: Streets
var town: Town
var _rng := RandomNumberGenerator.new()
var _meshes: Array[ArrayMesh] = []
var _shadow_meshes: Array[ArrayMesh] = []
# one MultiMesh per style: every vehicle of a style is a single draw call
var _multi: Array[MultiMesh] = []
# a box or two per vehicle for the shadow map instead of the whole vehicle
var _shadow_multi: Array[MultiMesh] = []
var _cars: Array = []
var _spawn_timer := 0.0
# the streets the works stand on, looked up now and then
var _works_streets := {}
var _works_timer := 0.0


func _ready() -> void:
	for c in CAR_COLORS.size():
		STYLES.append(["van" if c % 4 == 3 else "car", CAR_COLORS[c]])
	for c in BUS_COLORS:
		STYLES.append(["bus", c])
	for c in TRUCK_COLORS:
		STYLES.append(["truck", c])
	for i in STYLES.size():
		_meshes.append(_vehicle_mesh(STYLES[i][0], STYLES[i][1], i))
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _meshes[i]
		mm.instance_count = MAX_CARS
		mm.visible_instance_count = 0
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
		_multi.append(mm)
		var sm := MultiMesh.new()
		sm.transform_format = MultiMesh.TRANSFORM_3D
		sm.mesh = _shadow_meshes[i]
		sm.instance_count = MAX_CARS
		sm.visible_instance_count = 0
		var smi := MultiMeshInstance3D.new()
		smi.multimesh = sm
		smi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		add_child(smi)
		_shadow_multi.append(sm)


func clear() -> void:
	_cars.clear()
	for mm in _multi + _shadow_multi:
		mm.visible_instance_count = 0


const GLASS := Color(0.25, 0.32, 0.4)
const TYRE := Color(0.16, 0.16, 0.18)


## A vehicle along local +Z, kept to a few dozen triangles: flat boxes with
## glass, lights and wheels painted on as quads.
func _vehicle_mesh(kind: String, col: Color, variant: int) -> ArrayMesh:
	var mk := MeshKit.new(variant)
	var len: float = LENGTHS[kind]
	var hl := len * 0.5
	var wd := 0.34
	match kind:
		"car":
			mk.box(Vector3(0, 0.14, 0), Vector3(wd, 0.16, len), col)
			mk.box(Vector3(0, 0.28, -0.03), Vector3(0.3, 0.12, len * 0.55), Color(0.95, 0.96, 0.98))
			_glass(mk, 0.28, len * 0.55 * 0.5 - 0.03, 0.24, 0.08)
			_glass(mk, 0.28, -len * 0.55 * 0.5 - 0.03, 0.24, 0.08)
			_side_glass(mk, Vector3(0, 0.28, -0.03), 0.3, len * 0.5, 0.08)
		"van":
			mk.box(Vector3(0, 0.14, 0), Vector3(wd, 0.16, len), col)
			mk.box(Vector3(0, 0.31, -0.04), Vector3(0.32, 0.2, len * 0.82), col.lightened(0.1))
			_glass(mk, 0.33, len * 0.82 * 0.5 - 0.04, 0.26, 0.1)
		"bus":
			wd = 0.4
			mk.box(Vector3(0, 0.26, 0), Vector3(wd, 0.4, len), col, col.lightened(0.35))
			_glass(mk, 0.3, hl, 0.32, 0.14)
			_side_glass(mk, Vector3(0, 0.33, 0), wd, len - 0.2, 0.11)
		"truck":
			wd = 0.38
			# a cab and a box behind it
			mk.box(Vector3(0, 0.2, hl - 0.15), Vector3(0.36, 0.28, 0.3), Color("d24a3a") if variant % 2 == 0 else Color("3d6fb6"))
			_glass(mk, 0.28, hl, 0.28, 0.09)
			mk.box(Vector3(0, 0.3, -0.16), Vector3(wd, 0.46, len - 0.32), col, col.darkened(0.08))
	mk.shadow = false
	# wheels: dark patches on each side
	var axles := [-hl * 0.6, hl * 0.6] if kind != "bus" else [-hl * 0.7, hl * 0.62]
	for sz: float in axles:
		for sx in [-1.0, 1.0]:
			var x: float = sx * (wd * 0.5 + 0.004)
			mk.quad(Vector3(x, 0.0, sz - 0.07), Vector3(x, 0.0, sz + 0.07), Vector3(x, 0.12, sz + 0.07), Vector3(x, 0.12, sz - 0.07), Vector3(sx, 0, 0), TYRE)
	# headlights (lit at night) and tail lights
	for sx in [-0.11, 0.11]:
		var f := hl + 0.004
		mk.quad(Vector3(sx - 0.035, 0.12, f), Vector3(sx + 0.035, 0.12, f), Vector3(sx + 0.035, 0.16, f), Vector3(sx - 0.035, 0.16, f), Vector3.BACK, Color(1, 0.97, 0.85), 2.0)
		mk.quad(Vector3(sx - 0.035, 0.12, -f), Vector3(sx + 0.035, 0.12, -f), Vector3(sx + 0.035, 0.16, -f), Vector3(sx - 0.035, 0.16, -f), Vector3.FORWARD, Color(0.9, 0.2, 0.2), 2.0)
	if kind == "bus":
		# its route sign, lit at night
		mk.quad(Vector3(-0.12, 0.42, hl + 0.004), Vector3(0.12, 0.42, hl + 0.004), Vector3(0.12, 0.45, hl + 0.004), Vector3(-0.12, 0.45, hl + 0.004), Vector3.BACK, Color(1, 0.8, 0.3), 2.0)
	_shadow_meshes.append(mk.commit_shadow(Palette.shadow_material()))
	return mk.commit(material)


## A windscreen (or rear window) across the front (z > 0) or back.
func _glass(mk: MeshKit, y: float, z: float, w: float, h: float) -> void:
	var f := z + 0.004 * signf(z)
	var out := Vector3.BACK if z > 0.0 else Vector3.FORWARD
	mk.quad(Vector3(-w * 0.5, y - h * 0.5, f), Vector3(w * 0.5, y - h * 0.5, f), Vector3(w * 0.5, y + h * 0.5, f), Vector3(-w * 0.5, y + h * 0.5, f), out, GLASS)


## A band of side windows down both flanks.
func _side_glass(mk: MeshKit, c: Vector3, wd: float, len: float, h: float) -> void:
	for sx in [-1.0, 1.0]:
		var x: float = c.x + sx * (wd * 0.5 + 0.004)
		mk.quad(Vector3(x, c.y - h * 0.5, c.z - len * 0.5), Vector3(x, c.y - h * 0.5, c.z + len * 0.5), Vector3(x, c.y + h * 0.5, c.z + len * 0.5), Vector3(x, c.y + h * 0.5, c.z - len * 0.5), Vector3(sx, 0, 0), GLASS)


## How many lanes each way a street has.
static func lanes(s: Streets.Street) -> int:
	return 2 if Streets.KINDS[s.kind].median > 0.0 else 1


## How far right of the centre line a lane runs.
static func lane_offset(s: Streets.Street, lane: int) -> float:
	var med: float = Streets.KINDS[s.kind].median
	if med <= 0.0:
		return s.w() * 0.42
	return med + (s.w() - med) * (0.27 + 0.46 * lane)


func _process(delta: float) -> void:
	var graph := streets.links()
	_works_timer -= delta
	if _works_timer <= 0.0:
		_works_timer = 5.0
		_works_streets.clear()
		for l: Town.Lot in town.lots.values():
			if l.use == "industry":
				_works_streets[l.street] = true
	var total := 0.0
	for s: Streets.Street in streets.streets:
		total += s.pts.size() * Streets.SAMPLE * BUSY.get(s.kind, 1.0)
	var wanted := mini(int(total / 14.0) + town.lots.size() / 9, MAX_CARS - 10)
	_spawn_timer -= delta
	if _cars.size() < wanted and _spawn_timer <= 0.0:
		_spawn_timer = 0.25 if _cars.size() < wanted / 2 else 0.5
		var m := _spawn(total)
		if not m.is_empty():
			_cars.append(m)
	elif _cars.size() > wanted + 2:
		_cars.pop_back()
	_queue()
	var i := 0
	while i < _cars.size():
		if not _drive(_cars[i], graph, delta):
			_cars.remove_at(i)
			continue
		i += 1
	var counts: Array[int] = []
	counts.resize(_multi.size())
	for c in _cars:
		var v: int = c.v
		_multi[v].set_instance_transform(counts[v], c.xf)
		_shadow_multi[v].set_instance_transform(counts[v], c.xf)
		counts[v] += 1
	for v in _multi.size():
		_multi[v].visible_instance_count = counts[v]
		_shadow_multi[v].visible_instance_count = counts[v]


## A new vehicle on a street picked by how busy its kind is: buses on the main
## roads, lorries by the works and on highways, cars and vans everywhere.
func _spawn(total: float) -> Dictionary:
	var pick := _rng.randf() * total
	var s: Streets.Street = null
	for o: Streets.Street in streets.streets:
		pick -= o.pts.size() * Streets.SAMPLE * BUSY.get(o.kind, 1.0)
		if pick <= 0.0:
			s = o
			break
	if s == null or s.pts.size() < 4:
		return {}
	var buses := 0
	for c in _cars:
		buses += int(STYLES[c.v][0] == "bus")
	var roll := _rng.randf()
	var v := _rng.randi() % CAR_COLORS.size()
	if (s.kind == "main" or s.kind == "avenue") and buses < MAX_BUSES and roll < 0.1:
		v = CAR_COLORS.size() + _rng.randi() % BUS_COLORS.size()
	elif roll < (0.4 if _works_streets.has(s.id) else 0.16 if s.kind == "highway" else 0.03):
		v = CAR_COLORS.size() + BUS_COLORS.size() + _rng.randi() % TRUCK_COLORS.size()
	var kind: String = STYLES[v][0]
	var m := {"s": s, "f": _rng.randf_range(1.0, s.pts.size() - 2.0), "dir": 1.0 if _rng.randf() < 0.5 else -1.0, "since": 0.0,
		"v": v, "xf": Transform3D(), "grow": 0.0, "lane": _rng.randi() % lanes(s), "len": LENGTHS[kind],
		"pace": _rng.randf_range(0.85, 1.12) * (0.8 if kind == "bus" or kind == "truck" else 1.0), "speed": 0.0,
		"ahead": INF, "wait": 0.0, "stop": _rng.randf_range(12.0, 30.0) if kind == "bus" else INF}
	if kind != "car" and kind != "van":
		# the big ones keep to the inside lane
		m.lane = 0
	# not on top of one already there
	for c in _cars:
		if c.s == s and c.lane == m.lane and c.dir == m.dir and absf(c.f - m.f) * Streets.SAMPLE < (c.len + m.len) * 0.5 + 1.0:
			return {}
	return m


## For each vehicle, how much room it has before the one ahead in its lane.
func _queue() -> void:
	var runs := {}
	for c in _cars:
		var s: Streets.Street = c.s
		var key := "%d:%d:%d" % [s.id, int(c.dir), c.lane]
		if not runs.has(key):
			runs[key] = []
		runs[key].append(c)
	for key in runs:
		var run: Array = runs[key]
		if run.size() < 2:
			run[0].ahead = INF
			continue
		var dirn: float = run[0].dir
		run.sort_custom(func(a, b) -> bool: return a.f * dirn > b.f * dirn)
		run[0].ahead = INF
		for k in range(1, run.size()):
			var front: Dictionary = run[k - 1]
			var me: Dictionary = run[k]
			me.ahead = absf(front.f - me.f) * Streets.SAMPLE - (front.len + me.len) * 0.5


func _drive(c: Dictionary, graph: Dictionary, delta: float) -> bool:
	var s: Streets.Street = c.s
	var want: float = SPEEDS.get(s.kind, 1.5) * c.pace
	# ease off behind the one ahead, and stop short of it
	var room: float = c.ahead - GAP
	if room < 1.2:
		want *= clampf(room / 1.2, 0.0, 1.0)
	if c.wait > 0.0:
		# a bus at its stop
		c.wait -= delta
		want = 0.0
	c.speed = move_toward(c.speed, want, delta * (2.5 if want > c.speed else 6.0))
	var step: float = c.speed * delta
	if c.stop != INF:
		c.stop -= step
		if c.stop <= 0.0:
			c.stop = _rng.randf_range(18.0, 34.0)
			c.wait = 2.2
	if not StreetWalk.advance(streets, graph, c, step, 0.4, _rng):
		return false
	if c.s != s:
		# into a new street: pick a lane there
		var ns: Streets.Street = c.s
		c.lane = 0 if c.len > 0.8 else _rng.randi() % lanes(ns)
		s = ns
	var at := StreetWalk.place(streets, c, lane_offset(s, c.lane) * c.dir)
	var pos: Vector3 = at[0]
	var fwd: Vector3 = at[1]
	var pitch: float = atan2(at[2] as float, Streets.SAMPLE) * c.dir
	var goal := Basis(Vector3.UP, atan2(fwd.x, fwd.z)) * Basis(Vector3.RIGHT, -pitch)
	c.grow = minf(1.0, c.grow + delta * 3.0)
	var sc := Tween.interpolate_value(0.0, 1.0, c.grow, 1.0, Tween.TRANS_BACK, Tween.EASE_OUT) as float
	var old: Transform3D = c.xf
	# ease round corners and across junctions rather than jumping lanes
	var k := 1.0 - exp(-delta * 10.0)
	if c.grow < 1.0 or old.origin.distance_to(pos) > 1.5:
		k = 1.0
	var rot := old.basis.orthonormalized().get_rotation_quaternion().slerp(goal.get_rotation_quaternion(), k) if k < 1.0 else goal.get_rotation_quaternion()
	c.xf = Transform3D(Basis(rot).scaled(Vector3.ONE * maxf(sc, 0.01)), old.origin.lerp(pos, k))
	return true
