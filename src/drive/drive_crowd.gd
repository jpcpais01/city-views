class_name DriveCrowd
extends Node3D
## The busy streets round the player's car in Drive mode: dozens of detailed
## cars, vans, taxis, buses and lorries keeping to their lanes, easing off
## into corners and behind each other (and behind the player), and crowds on
## the pavements walking with swinging arms and legs, some stopping to chat.
## Cars stop at the lights of the bigger crossings and queue there. Only
## round the car while driving, or round the middle of the view when the
## camera is down close over the town; the everyday traffic and townsfolk
## step aside meanwhile. Each body is one MultiMesh (one draw call)
## that crowd.gdshader paints and animates per copy.

const CAR_R := 66.0
const PED_R := 36.0
const MAX_CARS := 170
const MAX_PEDS := 400
## a car every this many metres of lane, someone every this many of pavement
const CAR_EVERY := 4.0
const PED_EVERY := 1.0
## traffic lights: a whole cycle, and how long each way's green lasts of it
const CYCLE := 16.0
const GREEN := 7.0
## car bodies, in mesh order, with their length
const KINDS := ["hatch", "sedan", "suv", "van", "taxi", "pickup", "bus", "truck"]
const LENGTHS := [0.6, 0.68, 0.68, 0.72, 0.68, 0.74, 1.5, 1.15]
## how often each body turns up, out of 100
const ODDS := [24, 24, 16, 10, 8, 8, 4, 6]
const PAINTS := [Color("d8dadf"), Color("f4f4f2"), Color("1f2329"), Color("4b5563"), Color("a7adb6"), Color("b8232f"),
	Color("2c5aa0"), Color("1e3a5f"), Color("2f6b4f"), Color("e8c547"), Color("ef7d3a"), Color("6d2d4a"), Color("8fb8d8"),
	Color("c9b79c"), Color("3a3f4a"), Color("e15a5a"), Color("5fae9a"), Color("f2f0e6")]
const TAXI := Color("f6c228")
## the room a car leaves to the one ahead
const GAP := 0.3
## walkers: three builds (short hair, long hair and skirt, cap and backpack)
const BUILDS := 3
const STRIDE := 0.19

var island: IslandWorld
var material: ShaderMaterial
## where the player's car is, and which way it points
var player: DriveCar

var _rng := RandomNumberGenerator.new()
var _car_mm: Array[MultiMesh] = []
var _car_shadow_mm: Array[MultiMesh] = []
var _ped_mm: Array[MultiMesh] = []
# what each MultiMesh draws, written whole every frame (see _draw)
var _car_buf: Array[PackedFloat32Array] = []
var _car_shadow_buf: Array[PackedFloat32Array] = []
var _ped_buf: Array[PackedFloat32Array] = []
var _cars: Array = []
var _peds: Array = []
# street spots near the car: [street, sample index], for cars and for walkers
var _car_spots: Array = []
var _ped_spots: Array = []
var _spot_timer := 0.0
var _car_want := 0
var _ped_want := 0
var _frame := 0
var _clock := 0.0
# where the middle was last frame, to fill afresh after a jump
var _last_centre := Vector2.ZERO


func _ready() -> void:
	_rng.randomize()
	material = ShaderMaterial.new()
	material.shader = load("res://shaders/crowd.gdshader")
	for k in KINDS.size():
		var mk := MeshKit.new(70 + k)
		mk.impostors = false
		_car_body(mk, k)
		var mm := _multi(mk.commit(material), MAX_CARS, true, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		_car_mm.append(mm)
		_car_shadow_mm.append(_multi(mk.commit_shadow(Palette.shadow_material()), MAX_CARS, false, GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY))
		_car_buf.append(_blank(MAX_CARS, 16))
		_car_shadow_buf.append(_blank(MAX_CARS, 12))
	for b in BUILDS:
		_ped_mm.append(_multi(_walker(b), MAX_PEDS, true, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF))
		_ped_buf.append(_blank(MAX_PEDS, 16))
	visible = false
	set_process(false)


func _blank(n: int, stride: int) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(n * stride)
	return a


func _multi(mesh: Mesh, n: int, custom: bool, shadow: GeometryInstance3D.ShadowCastingSetting) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = custom
	mm.mesh = mesh
	mm.instance_count = n
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = shadow
	add_child(mmi)
	return mm


## Fills the streets round the car at once (the moment the player gets in)
## and keeps them busy until `stop()`.
func start() -> void:
	_cars.clear()
	_peds.clear()
	visible = true
	set_process(true)
	_find_spots()
	_last_centre = _centre()
	for i in _car_want * 2:
		if _cars.size() >= _car_want:
			break
		_spawn_car(true)
	for i in _ped_want * 2:
		if _peds.size() >= _ped_want:
			break
		_spawn_ped(true)
	# a few seconds of life, so nobody stands frozen where they spawned
	for i in 4:
		_step(0.25, true)
	_draw()


func stop() -> void:
	_cars.clear()
	_peds.clear()
	for mm in _car_mm + _car_shadow_mm + _ped_mm:
		mm.visible_instance_count = 0
	visible = false
	set_process(false)


func car_count() -> int:
	return _cars.size()


func ped_count() -> int:
	return _peds.size()


func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	_clock += delta
	material.set_shader_parameter("night", island.night)
	_spot_timer -= delta
	if _spot_timer <= 0.0:
		_spot_timer = 0.5
		_find_spots()
	# the view jumped across town: fill the streets there at once
	if _centre().distance_to(_last_centre) > 20.0:
		start()
		return
	_last_centre = _centre()
	# a few new arrivals a frame, out of the way of the view where possible
	for i in 3:
		if _cars.size() < _car_want:
			_spawn_car(false)
		if _peds.size() < _ped_want:
			_spawn_ped(false)
	_step(delta, false)
	_draw()


# ------------------------------------------------------------------ where they can be

func _find_spots() -> void:
	_car_spots.clear()
	_ped_spots.clear()
	# a street rebuilt or a city loaded: those on streets gone go too
	var now := {}
	for s: Streets.Street in island.streets.streets:
		now[s] = true
	_cars = _cars.filter(func(m: Dictionary) -> bool: return now.has(m.s))
	_peds = _peds.filter(func(m: Dictionary) -> bool: return now.has(m.s))
	var c := _centre()
	var car_m := 0.0
	var ped_m := 0.0
	for s: Streets.Street in island.streets.streets:
		if s.pts.size() < 4 or not s.near_box(c, CAR_R):
			continue
		var walk := s.kind == "walk"
		var verge: bool = Streets.KINDS.get(s.kind, {}).get("verge", false)
		var i := 1
		while i < s.pts.size() - 2:
			var d := s.pts[i].distance_to(c)
			if d < CAR_R and not walk:
				_car_spots.append([s, i])
				car_m += 2.0 * Traffic.lanes(s) * 2.0
			if d < PED_R and not verge:
				_ped_spots.append([s, i])
				ped_m += 2.0 * (1.0 if walk else 2.0)
			i += 4
	_car_want = mini(int(car_m / CAR_EVERY), MAX_CARS)
	_ped_want = mini(int(ped_m / PED_EVERY), MAX_PEDS)


func _centre() -> Vector2:
	if player:
		return Vector2(player.position.x, player.position.z)
	return Vector2(island.rig.target.x, island.rig.target.z)


## Whether a spot is in plain sight just ahead, where nobody should pop up.
func _in_view(p: Vector2) -> bool:
	var c := _centre()
	var d := p - c
	if d.length() > 32.0:
		return false
	var cam := island.rig.cam
	var f := -cam.global_transform.basis.z
	return Vector2(f.x, f.z).normalized().dot(d.normalized()) > 0.35


# ------------------------------------------------------------------ cars

## A street spot to put someone at, more likely the nearer it is and in
## front of the camera: the crowd is spent where it is seen.
func _pick(spots: Array) -> Array:
	var c := _centre()
	var cam := island.rig.cam
	var f := -cam.global_transform.basis.z
	var ahead := Vector2(f.x, f.z).normalized()
	var spot: Array = spots[_rng.randi() % spots.size()]
	for i in 6:
		var d: Vector2 = (spot[0] as Streets.Street).pts[spot[1]] - c
		var w := clampf(16.0 / (d.length() + 6.0), 0.12, 1.0) * (1.0 if ahead.dot(d) > 0.0 else 0.5)
		if _rng.randf() < w:
			break
		spot = spots[_rng.randi() % spots.size()]
	return spot


func _spawn_car(anywhere: bool) -> void:
	if _car_spots.is_empty():
		return
	var spot: Array = _pick(_car_spots)
	var s: Streets.Street = spot[0]
	var f: float = spot[1] + _rng.randf_range(0.0, 3.9)
	f = clampf(f, 1.0, s.pts.size() - 2.0)
	var at := island.streets._ptf(s, f)
	if not anywhere and _in_view(at):
		return
	if at.distance_to(_centre()) < 2.5:
		return
	var roll := _rng.randi() % 100
	var k := 0
	while roll >= ODDS[k]:
		roll -= ODDS[k]
		k += 1
	# buses and lorries keep to the main roads
	if k >= 6 and s.kind == "side":
		k = 0
	var dir := 1.0 if _rng.randf() < 0.5 else -1.0
	var lane := _rng.randi() % Traffic.lanes(s)
	if k >= 6:
		lane = Traffic.lanes(s) - 1 if k == 6 else 0
	var len: float = LENGTHS[k]
	for o in _cars:
		if o.s == s and o.dir == dir and o.lane == lane and absf(o.f - f) * Streets.SAMPLE < (o.len + len) * 0.5 + 0.8:
			return
	var paint: Color = TAXI if KINDS[k] == "taxi" else PAINTS[_rng.randi() % PAINTS.size()]
	if KINDS[k] == "bus":
		paint = [Color("d9483b"), Color("2f8f83"), Color("2b6cb0")][_rng.randi() % 3]
	_cars.append({"s": s, "f": f, "dir": dir, "since": 0.0, "k": k, "len": len, "lane": lane,
		"pace": _rng.randf_range(0.82, 1.12) * (0.82 if k >= 6 else 1.0), "speed": 0.0, "ahead": INF,
		"paint": paint, "brake": 0.0, "dyn": 0.0, "lean": 0.0, "xf": Transform3D(), "vel": Vector3.ZERO, "grow": 1.0 if anywhere else 0.0, "fresh": true})


## For each car, the room before the next one ahead in its lane.
func _queue() -> void:
	var runs := {}
	for c in _cars:
		var key: int = (c.s as Streets.Street).id * 16 + (8 if c.dir > 0.0 else 0) + int(c.lane)
		if not runs.has(key):
			runs[key] = []
		runs[key].append(c)
	for key in runs:
		var run: Array = runs[key]
		var dirn: float = run[0].dir
		if run.size() > 1:
			run.sort_custom(func(a, b) -> bool: return a.f * dirn > b.f * dirn)
		run[0].ahead = INF
		for k in range(1, run.size()):
			var front: Dictionary = run[k - 1]
			var me: Dictionary = run[k]
			me.ahead = absf(front.f - me.f) * Streets.SAMPLE - (front.len + me.len) * 0.5


func _drive(c: Dictionary, graph: Dictionary, delta: float, warm: bool) -> bool:
	var s: Streets.Street = c.s
	var want: float = Traffic.SPEEDS.get(s.kind, 1.5) * c.pace
	var room: float = c.ahead - GAP
	# easing off into the next junction, where it may turn, and stopping at
	# its lights on red
	if graph.has(s.id):
		var next := INF
		for l in graph[s.id]:
			var ahead: float = (l[0] - c.f) * c.dir
			if ahead > 0.0 and ahead < next:
				next = ahead
		if next < 6.0:
			want *= lerpf(0.5, 1.0, next / 6.0)
		if next < 10.0:
			for l in graph[s.id]:
				if absf((l[0] - c.f) * c.dir - next) > 1.0 or not _red(s, l):
					continue
				var line: float = next * Streets.SAMPLE - (l[1] as Streets.Street).w() - 0.2 - c.len * 0.5
				# already in the crossing, or too close to stop: on through it
				if line > -0.05 and line > c.speed * c.speed * 0.06:
					room = minf(room, line)
				break
	# and behind the player's car when it is in the lane ahead
	if player:
		var fwd: Vector3 = c.xf.basis.z.normalized()
		var co: Vector3 = c.xf.origin
		var d: Vector3 = player.position - co
		var along := d.x * fwd.x + d.z * fwd.z
		var lat := absf(d.x * fwd.z - d.z * fwd.x)
		if along > 0.0 and along < 4.0 and lat < 0.34:
			room = minf(room, along - c.len * 0.5 - DriveCar.HALF_L - GAP)
	if room < 1.6:
		want *= clampf(room / 1.6, 0.0, 1.0)
	var was: float = c.speed
	c.speed = move_toward(c.speed, want, delta * (1.4 if want > c.speed else 5.0))
	var accel: float = (c.speed - was) / maxf(delta, 0.001)
	c.brake = lerpf(c.brake, 1.0 if accel < -0.6 or (c.speed < 0.05 and want < 0.05) else 0.0, 1.0 - exp(-delta * 8.0))
	if not StreetWalk.advance(island.streets, graph, c, c.speed * delta, 0.45, _rng, true):
		return false
	if c.s != s:
		var ns: Streets.Street = c.s
		if ns.kind == "walk":
			return false
		c.lane = Traffic.lanes(ns) - 1 if c.k == 6 else 0 if c.k == 7 else _rng.randi() % Traffic.lanes(ns)
		s = ns
	var at := StreetWalk.place(island.streets, c, Traffic.lane_offset(s, c.lane) * c.dir)
	var pos: Vector3 = at[0]
	var fwd2: Vector3 = at[1]
	var slope: float = atan2(at[2] as float, Streets.SAMPLE) * c.dir
	var old: Transform3D = c.xf
	var yaw := atan2(fwd2.x, fwd2.z)
	# the body dips its nose under braking, squats pulling away, leans into turns
	c.dyn = lerpf(c.dyn, clampf(-accel * 0.025, -0.05, 0.06), 1.0 - exp(-delta * 6.0))
	var turn := 0.0
	if not c.fresh:
		var oz: Vector3 = old.basis.z
		turn = wrapf(yaw - atan2(oz.x, oz.z), -PI, PI) / maxf(delta, 0.001)
	c.lean = lerpf(c.lean, clampf(turn * c.speed * 0.04, -0.07, 0.07), 1.0 - exp(-delta * 5.0))
	var goal := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -slope + c.dyn) * Basis(Vector3.BACK, c.lean)
	if not warm:
		c.grow = minf(1.0, c.grow + delta * 3.0)
	var sc := 1.0 if c.grow >= 1.0 else Tween.interpolate_value(0.0, 1.0, c.grow, 1.0, Tween.TRANS_BACK, Tween.EASE_OUT) as float
	var k := 1.0 - exp(-delta * 9.0)
	if c.fresh or old.origin.distance_to(pos) > 2.0:
		k = 1.0
	c.fresh = false
	var q := old.basis.orthonormalized().get_rotation_quaternion().slerp(goal.get_rotation_quaternion(), k) if k < 1.0 else goal.get_rotation_quaternion()
	c.xf = Transform3D(Basis(q).scaled(Vector3.ONE * maxf(sc, 0.01)), old.origin.lerp(pos, k))
	c.vel = Vector3.ZERO if k >= 1.0 else (c.xf.origin - old.origin) / maxf(delta, 0.001)
	return true


## Whether a car on `s` coming up to where it meets another street (`l`, a
## link from Streets.links) has to stop there now. The crossings of main
## roads and avenues have lights, each crossing on its own time: one way
## green, a moment of red both ways, then the other way green.
func _red(s: Streets.Street, l: Array) -> bool:
	var o: Streets.Street = l[1]
	if o.kind == "walk" or Streets.KINDS[s.kind].verge or Streets.KINDS[o.kind].verge:
		return false
	if not (s.kind == "main" or s.kind == "avenue" or o.kind == "main" or o.kind == "avenue"):
		return false
	var jf: float = l[0]
	var of: float = l[2]
	# one street running on into the next is no crossing
	if (jf < 1.0 or jf > s.pts.size() - 2.0) and (of < 1.0 or of > o.pts.size() - 2.0):
		return false
	var p: Vector2 = s.pts[clampi(roundi(jf), 0, s.pts.size() - 1)]
	var t := fposmod(_clock + p.x * 0.37 + p.y * 0.61, CYCLE)
	if s.id < o.id:
		return t >= GREEN
	return t < CYCLE * 0.5 or t >= CYCLE * 0.5 + GREEN


## Whether the point `p` is inside one of the cars (for the player bumping into them).
func hits(p: Vector2) -> bool:
	for c in _cars:
		var o: Vector3 = c.xf.origin
		var d := Vector2(p.x - o.x, p.y - o.z)
		if d.length_squared() > 1.0:
			continue
		var z: Vector3 = c.xf.basis.z.normalized()
		var along := d.x * z.x + d.y * z.z
		var lat := d.x * z.z - d.y * z.x
		if absf(along) < c.len * 0.5 and absf(lat) < 0.17:
			return true
	return false


# ------------------------------------------------------------------ walkers

func _spawn_ped(anywhere: bool) -> void:
	if _ped_spots.is_empty():
		return
	var spot: Array = _pick(_ped_spots)
	var s: Streets.Street = spot[0]
	var f: float = clampf(spot[1] + _rng.randf_range(0.0, 3.9), 0.5, s.pts.size() - 1.5)
	var at := island.streets._ptf(s, f)
	if not anywhere and _in_view(at):
		return
	var walk := s.kind == "walk"
	var side := 1.0 if _rng.randf() < 0.5 else -1.0
	# somewhere across the pavement (or the path), so they don't walk in single file
	var off: float = (_rng.randf_range(-0.6, 0.6) * s.w()) if walk else (s.w() + Streets.PAVE * _rng.randf_range(0.22, 0.8)) * side
	var standing := _rng.randf() < 0.14
	var speed := _rng.randf_range(0.15, 0.26)
	var p := {"s": s, "f": f, "dir": 1.0 if _rng.randf() < 0.5 else -1.0, "since": 0.0, "off": off, "walk": walk,
		"b": _rng.randi() % BUILDS, "speed": speed, "ph": _rng.randf() * TAU, "pause": _rng.randf_range(8.0, 40.0) if standing else 0.0,
		"face": _rng.randf() * TAU, "dodge": 0.0, "q": Quaternion.IDENTITY, "xf": Transform3D(), "vel": Vector3.ZERO, "grow": 1.0 if anywhere else 0.0, "fresh": true,
		"look": _look(), "scale": _rng.randf_range(0.9, 1.08) * (0.72 if _rng.randf() < 0.08 else 1.0)}
	_peds.append(p)
	# friends and families walk together, side by side
	var more := 1 if _rng.randf() < 0.3 else 2 if _rng.randf() < 0.08 else 0
	for i in mini(more, _ped_want - _peds.size()):
		var q := p.duplicate()
		# alongside, on the roomier side of the pavement (or the path)
		var mid := 0.0 if walk else signf(off) * (s.w() + Streets.PAVE * 0.5)
		q.off = off + (0.075 + 0.07 * i) * (1.0 if mid >= off else -1.0)
		q.f = f + _rng.randf_range(-0.12, 0.12)
		q.b = _rng.randi() % BUILDS
		q.ph = p.ph + PI + _rng.randf_range(-0.6, 0.6)
		q.look = _look()
		q.scale = _rng.randf_range(0.9, 1.08) * (0.72 if _rng.randf() < 0.25 else 1.0)
		_peds.append(q)


## A walker's colours for crowd.gdshader: shirt, trousers + 8 * skin, hair.
func _look() -> Color:
	return Color(_rng.randi() % 12, (_rng.randi() % 8) + 8 * (_rng.randi() % 4), _rng.randi() % 6, 0.0)


func _walk(p: Dictionary, graph: Dictionary, delta: float, warm: bool) -> bool:
	var go := 0.0
	if p.pause > 0.0:
		p.pause -= delta
	else:
		if _rng.randf() < delta * 0.02:
			# stop to look in a window or check the phone
			p.pause = _rng.randf_range(1.5, 4.0)
			p.face = atan2(p.xf.basis.z.x, p.xf.basis.z.z) + PI * 0.5 * signf(p.off)
		go = p.speed * delta
	# out of the way of the player's car
	if player:
		var d := Vector2(p.xf.origin.x - player.position.x, p.xf.origin.z - player.position.z)
		if d.length() < 0.7 and absf(player.speed) > 0.05:
			p.dodge = minf(p.dodge + delta * 1.5, 0.35)
			go *= 0.3
		else:
			p.dodge = maxf(p.dodge - delta * 0.3, 0.0)
	var was: Streets.Street = p.s
	if not StreetWalk.advance(island.streets, graph, p, go, 0.3, _rng):
		return false
	var s: Streets.Street = p.s
	if s != was and Streets.KINDS.get(s.kind, {}).get("verge", false):
		return false
	var walk: bool = p.walk
	if s != was and (s.kind == "walk") != walk:
		walk = not walk
		p.walk = walk
		p.off = _rng.randf_range(-0.6, 0.6) * s.w() if walk else (s.w() + Streets.PAVE * _rng.randf_range(0.22, 0.8)) * (1.0 if _rng.randf() < 0.5 else -1.0)
	var off: float = p.off
	if not walk:
		# pavements of a street that changed width: back onto them
		off = signf(off) * clampf(absf(off), s.w() + 0.08, s.w() + Streets.PAVE - 0.06)
		off += signf(off) * p.dodge
	var at := StreetWalk.place(island.streets, p, off)
	var pos: Vector3 = at[0] + Vector3(0, 0.0 if walk else Streets.CURB, 0)
	var fwd: Vector3 = at[1]
	var walking: bool = go > 0.0
	if walking:
		p.ph = fmod(p.ph + go / STRIDE * TAU, TAU)
		pos.y += absf(sin(p.ph)) * 0.005
	else:
		# feet together when standing still
		p.ph = lerp_angle(p.ph, 0.0 if cos(p.ph) > 0.0 else PI, 1.0 - exp(-delta * 6.0))
	var yaw: float = atan2(fwd.x, fwd.z) if walking else p.face
	var goal := Basis(Vector3.UP, yaw)
	if not warm:
		p.grow = minf(1.0, p.grow + delta * 3.0)
	var sc := 1.0 if p.grow >= 1.0 else Tween.interpolate_value(0.0, 1.0, p.grow, 1.0, Tween.TRANS_BACK, Tween.EASE_OUT) as float
	var old: Transform3D = p.xf
	var k := 1.0 - exp(-delta * 10.0)
	if p.fresh or old.origin.distance_to(pos) > 1.2:
		k = 1.0
	p.fresh = false
	# turning to face the way, unless already facing it
	var gq := goal.get_rotation_quaternion()
	var oq: Quaternion = p.q
	var q := oq.slerp(gq, 1.0 - exp(-delta * 7.0)) if k < 1.0 and not oq.is_equal_approx(gq) else gq
	p.q = q
	p.xf = Transform3D(Basis(q).scaled(Vector3.ONE * maxf(sc * p.scale, 0.01)), old.origin.lerp(pos, k))
	p.vel = Vector3.ZERO if k >= 1.0 else (p.xf.origin - old.origin) / maxf(delta, 0.001)
	var look: Color = p.look
	look.a = p.ph
	p.look = look
	return true


# ------------------------------------------------------------------ each frame

func _step(delta: float, warm: bool) -> void:
	var graph := island.streets.links()
	var c := _centre()
	_queue()
	# those well away think every second, third or fourth frame, a longer
	# step at a time, and in between just glide on the way they were going:
	# at that distance it looks the same and costs a fraction
	_frame += 1
	var i := 0
	while i < _cars.size():
		var car: Dictionary = _cars[i]
		var o: Vector3 = car.xf.origin
		var d := Vector2(o.x, o.z).distance_to(c)
		var dt := delta
		if d > 18.0 and not warm and not car.fresh:
			var every := 4 if d > 52.0 else 3 if d > 36.0 else 2
			if (i + _frame) % every != 0:
				_glide(car, delta)
				i += 1
				continue
			dt = delta * every
		if not _drive(car, graph, dt, warm) or (not car.fresh and d > CAR_R + 8.0):
			_cars.remove_at(i)
			continue
		i += 1
	i = 0
	while i < _peds.size():
		var p: Dictionary = _peds[i]
		var o: Vector3 = p.xf.origin
		var d := Vector2(o.x, o.z).distance_to(c)
		var dt := delta
		if d > 7.0 and not warm and not p.fresh:
			var every := 4 if d > 26.0 else 3 if d > 16.0 else 2
			if (i + _frame) % every != 0:
				_glide(p, delta)
				i += 1
				continue
			dt = delta * every
		if not _walk(p, graph, dt, warm) or (not p.fresh and d > PED_R + 6.0):
			_peds.remove_at(i)
			continue
		i += 1


## A frame on between two steps: on at the speed it last went.
static func _glide(m: Dictionary, delta: float) -> void:
	var t: Transform3D = m.xf
	t.origin += (m.vel as Vector3) * delta
	m.xf = t


func _draw() -> void:
	# each MultiMesh's whole buffer is written at once: far quicker than an
	# engine call per copy
	var bufs: Array[PackedFloat32Array] = []
	var shadow_bufs: Array[PackedFloat32Array] = []
	var counts: Array[int] = []
	counts.resize(_car_mm.size())
	for k in _car_mm.size():
		bufs.append(_car_buf[k])
		shadow_bufs.append(_car_shadow_buf[k])
	for car in _cars:
		var k: int = car.k
		var n := counts[k]
		var paint: Color = car.paint
		paint.a = car.brake
		_put(bufs[k], n * 16, car.xf)
		_put_custom(bufs[k], n * 16 + 12, paint)
		_put(shadow_bufs[k], n * 12, car.xf)
		counts[k] = n + 1
	for k in _car_mm.size():
		_car_buf[k] = bufs[k]
		_car_shadow_buf[k] = shadow_bufs[k]
		_car_mm[k].buffer = bufs[k]
		_car_shadow_mm[k].buffer = shadow_bufs[k]
		_car_mm[k].visible_instance_count = counts[k]
		_car_shadow_mm[k].visible_instance_count = counts[k]
	var pc: Array[int] = []
	pc.resize(_ped_mm.size())
	var pbufs: Array[PackedFloat32Array] = []
	for b in _ped_mm.size():
		pbufs.append(_ped_buf[b])
	for p in _peds:
		var b: int = p.b
		_put(pbufs[b], pc[b] * 16, p.xf)
		_put_custom(pbufs[b], pc[b] * 16 + 12, p.look)
		pc[b] += 1
	for b in _ped_mm.size():
		_ped_buf[b] = pbufs[b]
		_ped_mm[b].buffer = pbufs[b]
		_ped_mm[b].visible_instance_count = pc[b]


static func _put(buf: PackedFloat32Array, i: int, t: Transform3D) -> void:
	var b := t.basis
	buf[i] = b.x.x
	buf[i + 1] = b.y.x
	buf[i + 2] = b.z.x
	buf[i + 3] = t.origin.x
	buf[i + 4] = b.x.y
	buf[i + 5] = b.y.y
	buf[i + 6] = b.z.y
	buf[i + 7] = t.origin.y
	buf[i + 8] = b.x.z
	buf[i + 9] = b.y.z
	buf[i + 10] = b.z.z
	buf[i + 11] = t.origin.z


static func _put_custom(buf: PackedFloat32Array, i: int, c: Color) -> void:
	buf[i] = c.r
	buf[i + 1] = c.g
	buf[i + 2] = c.b
	buf[i + 3] = c.a


# ------------------------------------------------------------------ the models

const TRIM := Color(0.16, 0.17, 0.19)
const GLASS := Color(0.12, 0.15, 0.2)
const TYRE := Color(0.1, 0.1, 0.11)
const HUB := Color(0.78, 0.8, 0.83)
const PAINT_TAG := 4.0


## A car body along +Z, standing on its wheels at y = 0.
func _car_body(mk: MeshKit, k: int) -> void:
	var kind: String = KINDS[k]
	var len: float = LENGTHS[k]
	var hl := len * 0.5
	var w := 0.34
	var wr := 0.058
	var clear := 0.045
	match kind:
		"hatch", "sedan", "taxi":
			var bh := 0.115
			mk.rbox(Vector3(0, clear + bh * 0.5, 0), Vector3(w, bh, len), 0.035, Color.WHITE, null, false, PAINT_TAG)
			var cl := len * (0.52 if kind == "hatch" else 0.46)
			var cz := -len * (0.08 if kind == "hatch" else 0.03)
			var ch := 0.1
			var cy := clear + bh + ch * 0.5
			mk.rbox(Vector3(0, cy, cz), Vector3(w - 0.035, ch, cl), 0.035, Color.WHITE, null, false, PAINT_TAG)
			_glasshouse(mk, cy, cz, w - 0.035, cl, ch, kind != "hatch")
			if kind == "taxi":
				mk.box(Vector3(0, cy + ch * 0.5 + 0.015, cz), Vector3(0.1, 0.03, 0.05), Color(1, 0.95, 0.75), null, false, 2.0)
			_lamps(mk, hl, clear + bh * 0.7, w)
		"suv":
			var bh := 0.13
			mk.rbox(Vector3(0, clear + 0.01 + bh * 0.5, 0), Vector3(w + 0.01, bh, len), 0.035, Color.WHITE, null, false, PAINT_TAG)
			var cl := len * 0.62
			var cz := -len * 0.07
			var ch := 0.115
			var cy := clear + 0.01 + bh + ch * 0.5
			mk.rbox(Vector3(0, cy, cz), Vector3(w - 0.025, ch, cl), 0.03, Color.WHITE, null, false, PAINT_TAG)
			_glasshouse(mk, cy, cz, w - 0.025, cl, ch, false)
			for sx in [-0.09, 0.09]:
				mk.box(Vector3(sx, cy + ch * 0.5 + 0.008, cz), Vector3(0.012, 0.012, cl * 0.8), TRIM)
			_lamps(mk, hl, clear + bh * 0.75, w)
			wr = 0.064
		"van":
			var bh := 0.27
			mk.rbox(Vector3(0, clear + bh * 0.5, -0.03), Vector3(w + 0.01, bh, len - 0.06), 0.04, Color.WHITE, null, false, PAINT_TAG)
			# short bonnet in front of the tall box
			mk.rbox(Vector3(0, clear + 0.06, hl - 0.06), Vector3(w + 0.01, 0.12, 0.12), 0.035, Color.WHITE, null, false, PAINT_TAG)
			mk.shadow = false
			var zf := hl - 0.12 + 0.004
			mk.quad(Vector3(-w * 0.43, clear + 0.14, zf), Vector3(w * 0.43, clear + 0.14, zf), Vector3(w * 0.43, clear + 0.235, zf), Vector3(-w * 0.43, clear + 0.235, zf), Vector3.BACK, GLASS, 1.0)
			for sx in [-1.0, 1.0]:
				var x: float = sx * (w * 0.5 + 0.009)
				mk.quad(Vector3(x, clear + 0.15, hl - 0.13), Vector3(x, clear + 0.15, hl - 0.26), Vector3(x, clear + 0.235, hl - 0.26), Vector3(x, clear + 0.235, hl - 0.13), Vector3(sx, 0, 0), GLASS, 1.0)
			mk.shadow = true
			_lamps(mk, hl, clear + 0.08, w)
		"pickup":
			var bh := 0.12
			mk.rbox(Vector3(0, clear + 0.01 + bh * 0.5, 0), Vector3(w + 0.01, bh, len), 0.035, Color.WHITE, null, false, PAINT_TAG)
			var cl := len * 0.36
			var cz := len * 0.08
			var ch := 0.11
			var cy := clear + 0.01 + bh + ch * 0.5
			mk.rbox(Vector3(0, cy, cz), Vector3(w - 0.02, ch, cl), 0.03, Color.WHITE, null, false, PAINT_TAG)
			_glasshouse(mk, cy, cz, w - 0.02, cl, ch, false)
			# the open bed behind
			mk.shadow = false
			var by := clear + 0.01 + bh
			mk.box(Vector3(0, by + 0.0015, -len * 0.25), Vector3(w - 0.03, 0.003, len * 0.42), TRIM)
			for sx in [-1.0, 1.0]:
				mk.box(Vector3(sx * (w * 0.5 - 0.005), by + 0.02, -len * 0.25), Vector3(0.012, 0.04, len * 0.44), Color.WHITE, null, false, PAINT_TAG)
			mk.box(Vector3(0, by + 0.02, -hl + 0.006), Vector3(w, 0.04, 0.012), Color.WHITE, null, false, PAINT_TAG)
			mk.shadow = true
			_lamps(mk, hl, clear + 0.1, w)
			wr = 0.064
		"bus":
			w = 0.4
			var bh := 0.4
			mk.rbox(Vector3(0, clear + bh * 0.5, 0), Vector3(w, bh, len), 0.05, Color.WHITE, Color(0.92, 0.93, 0.94), false, PAINT_TAG)
			mk.shadow = false
			# a window band down both sides and the big windscreen
			for sx in [-1.0, 1.0]:
				var x: float = sx * (w * 0.5 + 0.004)
				mk.quad(Vector3(x, clear + 0.2, -hl + 0.08), Vector3(x, clear + 0.2, hl - 0.12), Vector3(x, clear + 0.34, hl - 0.12), Vector3(x, clear + 0.34, -hl + 0.08), Vector3(sx, 0, 0), GLASS, 1.0)
				# a pale band under the windows
				mk.quad(Vector3(x, clear + 0.13, -hl + 0.06), Vector3(x, clear + 0.13, hl - 0.06), Vector3(x, clear + 0.17, hl - 0.06), Vector3(x, clear + 0.17, -hl + 0.06), Vector3(sx, 0, 0), Color(0.95, 0.95, 0.93))
			mk.quad(Vector3(-w * 0.44, clear + 0.14, hl + 0.004), Vector3(w * 0.44, clear + 0.14, hl + 0.004), Vector3(w * 0.44, clear + 0.34, hl + 0.004), Vector3(-w * 0.44, clear + 0.34, hl + 0.004), Vector3.BACK, GLASS, 1.0)
			mk.quad(Vector3(-0.12, clear + 0.355, hl + 0.004), Vector3(0.12, clear + 0.355, hl + 0.004), Vector3(0.12, clear + 0.385, hl + 0.004), Vector3(-0.12, clear + 0.385, hl + 0.004), Vector3.BACK, Color(1, 0.75, 0.25), 2.0)
			mk.shadow = true
			_lamps(mk, hl, clear + 0.07, w)
			wr = 0.07
		"truck":
			w = 0.38
			# a cab and a tall box behind it
			mk.rbox(Vector3(0, clear + 0.14, hl - 0.15), Vector3(0.36, 0.26, 0.28), 0.04, Color.WHITE, null, false, PAINT_TAG)
			mk.rbox(Vector3(0, clear + 0.25, -0.17), Vector3(w, 0.46, len - 0.33), 0.025, Color(0.95, 0.95, 0.93), Color(0.88, 0.88, 0.87))
			mk.shadow = false
			mk.quad(Vector3(-0.15, clear + 0.15, hl - 0.006), Vector3(0.15, clear + 0.15, hl - 0.006), Vector3(0.15, clear + 0.25, hl - 0.006), Vector3(-0.15, clear + 0.25, hl - 0.006), Vector3.BACK, GLASS, 1.0)
			# a coloured stripe along the box
			for sx in [-1.0, 1.0]:
				var x: float = sx * (w * 0.5 + 0.004)
				mk.quad(Vector3(x, clear + 0.2, -len * 0.5 + 0.05), Vector3(x, clear + 0.2, hl - 0.34), Vector3(x, clear + 0.25, hl - 0.34), Vector3(x, clear + 0.25, -len * 0.5 + 0.05), Vector3(sx, 0, 0), Color.WHITE, PAINT_TAG)
			mk.shadow = true
			_lamps(mk, hl, clear + 0.06, w)
			wr = 0.07
	# wheels with pale hubs, a pair at each end
	mk.shadow = false
	var axles := [hl * 0.62, -hl * 0.62]
	if kind == "bus":
		axles = [hl * 0.68, -hl * 0.6]
	elif kind == "truck":
		axles = [hl * 0.72, -hl * 0.45, -hl * 0.7]
	for z in axles:
		for sx in [-1.0, 1.0]:
			var x: float = sx * (w * 0.5 - 0.012)
			mk.push(Transform3D(Basis(Vector3.BACK, -PI * 0.5 * sx), Vector3(x, wr, z)))
			mk.cylinder(Vector3(0, -0.022, 0), wr, 0.044, 8, TYRE)
			mk.cylinder(Vector3(0, 0.022, 0), wr * 0.55, 0.003, 6, HUB)
			mk.pop()
	mk.shadow = true


## Windscreen, rear and side windows round a cabin.
func _glasshouse(mk: MeshKit, cy: float, cz: float, cw: float, cl: float, ch: float, pillar: bool) -> void:
	mk.shadow = false
	var hw := cw * 0.5
	var y0 := cy - ch * 0.32
	var y1 := cy + ch * 0.36
	var zf := cz + cl * 0.5 + 0.004
	var zb := cz - cl * 0.5 - 0.004
	mk.quad(Vector3(-hw + 0.025, y0, zf), Vector3(hw - 0.025, y0, zf), Vector3(hw - 0.03, y1, zf), Vector3(-hw + 0.03, y1, zf), Vector3.BACK, GLASS, 1.0)
	mk.quad(Vector3(-hw + 0.03, y0 + 0.008, zb), Vector3(hw - 0.03, y0 + 0.008, zb), Vector3(hw - 0.035, y1, zb), Vector3(-hw + 0.035, y1, zb), Vector3.FORWARD, GLASS, 1.0)
	for sx in [-1.0, 1.0]:
		var x: float = sx * (hw + 0.004)
		var segs := [[cz - cl * 0.5 + 0.03, cz - 0.012], [cz + 0.012, cz + cl * 0.5 - 0.03]] if pillar else [[cz - cl * 0.5 + 0.03, cz + cl * 0.5 - 0.03]]
		for sg in segs:
			mk.quad(Vector3(x, y0, sg[0]), Vector3(x, y0, sg[1]), Vector3(x, y1, sg[1] - 0.008), Vector3(x, y1, sg[0] + 0.008), Vector3(sx, 0, 0), GLASS, 1.0)
	mk.shadow = true


## Bumpers, headlamps, tail lamps and mirrors.
func _lamps(mk: MeshKit, hl: float, y: float, w: float) -> void:
	mk.shadow = false
	mk.box(Vector3(0, 0.07, hl + 0.006), Vector3(w + 0.006, 0.035, 0.026), TRIM)
	mk.box(Vector3(0, 0.07, -hl - 0.006), Vector3(w + 0.006, 0.035, 0.026), TRIM)
	var hx := w * 0.32
	for sx in [-hx, hx]:
		var f := hl + 0.004
		mk.quad(Vector3(sx - 0.032, y - 0.012, f), Vector3(sx + 0.032, y - 0.012, f), Vector3(sx + 0.03, y + 0.012, f), Vector3(sx - 0.03, y + 0.012, f), Vector3.BACK, Color(1, 0.97, 0.88), 2.0)
		mk.quad(Vector3(sx - 0.035, y - 0.01, -f), Vector3(sx + 0.035, y - 0.01, -f), Vector3(sx + 0.035, y + 0.012, -f), Vector3(sx - 0.035, y + 0.012, -f), Vector3.FORWARD, Color(0.85, 0.08, 0.08), 3.0)
	mk.shadow = true


## A walker facing +Z, about 0.3 m tall; arms and legs are tagged so the
## shader can swing them.
func _walker(b: int) -> ArrayMesh:
	var mk := MeshKit.new(90 + b)
	mk.impostors = false
	mk.shadow = false
	var white := Color.WHITE
	var shoe := Color(0.13, 0.12, 0.12)
	# legs (limbs 1 and 2) hanging from the hip, with shoes
	for leg in [1, 2]:
		var sx := -0.026 if leg == 1 else 0.026
		var v0 := mk.verts.size()
		if b == 1:
			# bare legs under a skirt
			mk.box(Vector3(sx, 0.06, 0), Vector3(0.026, 0.11, 0.028), white, null, false, 7.0)
		else:
			mk.box(Vector3(sx, 0.062, 0), Vector3(0.032, 0.116, 0.036), white, null, false, 6.0)
		mk.box_faces(Vector3(sx, 0.009, 0.008), Vector3(0.034, 0.018, 0.054), shoe, MeshKit.TOP | MeshKit.FRONT | MeshKit.LEFT | MeshKit.RIGHT)
		_limb(mk, v0, leg)
	if b == 1:
		# a flared skirt
		mk.cylinder(Vector3(0, 0.085, 0), 0.062, 0.05, 8, white, false, null, 0.046, 6.0)
	else:
		mk.box(Vector3(0, 0.124, 0), Vector3(0.088, 0.03, 0.056), white, null, false, 6.0)
	# body
	mk.rbox(Vector3(0, 0.168, 0), Vector3(0.1, 0.1, 0.06), 0.022, white, null, false, 5.0)
	# arms (limbs 3 and 4) from the shoulders, with hands
	for arm in [3, 4]:
		var sx := -0.063 if arm == 3 else 0.063
		var v0 := mk.verts.size()
		mk.box(Vector3(sx, 0.158, 0), Vector3(0.024, 0.094, 0.03), white, null, false, 5.0)
		_limb(mk, v0, arm)
	# head
	mk.blob(Vector3(0, 0.248, 0.002), Vector3(0.034, 0.04, 0.034), white, 0.0, 7.0)
	match b:
		0:
			mk.blob(Vector3(0, 0.264, -0.008), Vector3(0.036, 0.03, 0.035), white, 0.0, 8.0)
		1:
			mk.blob(Vector3(0, 0.262, -0.008), Vector3(0.037, 0.034, 0.036), white, 0.0, 8.0)
			# long hair down the back
			mk.box(Vector3(0, 0.226, -0.03), Vector3(0.06, 0.06, 0.016), white, null, false, 8.0)
		2:
			# a cap with a peak, and a backpack
			mk.cylinder(Vector3(0, 0.262, -0.002), 0.037, 0.022, 8, white, true, null, -1.0, 8.0)
			mk.box(Vector3(0, 0.272, 0.04), Vector3(0.05, 0.005, 0.03), white, null, false, 8.0)
			mk.rbox(Vector3(0, 0.17, -0.046), Vector3(0.075, 0.085, 0.034), 0.012, Color(0.25, 0.3, 0.38))
	return mk.commit(material)


## Tags the vertices added since `v0` with the limb they swing with.
func _limb(mk: MeshKit, v0: int, limb: int) -> void:
	for i in range(v0, mk.verts.size()):
		mk.uvs[i] = Vector2(mk.uvs[i].x, float(limb))
