class_name Planes
extends Node3D
## An airliner crossing high over the city now and then: white with a
## coloured tail, swept wings with an engine under each, a row of cabin
## windows that glow at night and nav lights on the wingtips, red on the
## left blinking and green on the right. Once the city has its airport,
## about half of them take off from its runway or come in to land on it.

const WAIT := Vector2(40.0, 90.0)
const SPEED := 16.0
const HEIGHT := 40.0
const TAILS := [Color("c8553d"), Color("2f5f9f"), Color("2f8f83"), Color("e3a33b")]
## how high an airliner's middle rides over the tarmac, on its wheels
const GROUND := 0.42
## how steeply they climb away and come down, and how far out they go
const CLIMB := 0.14
const GLIDE := 0.09
const OUT := 320.0

var material: Material
var world: Node3D
var _kinds: Array[Mesh] = []
var _plane: Node3D
var _from := Vector2.ZERO
var _dir := Vector2.ZERO
var _run := 0.0
var _d := 0.0
var _wait := 12.0
# "" crossing high over the city, "up" taking off, "down" coming in to land
var _mode := ""
var _ground := 0.0
var _speed := SPEED
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	for tail: Color in TAILS:
		_kinds.append(airliner(tail))


## An airliner about four units long, nose towards +Z: a round fuselage
## tapering to the nose and up into the tail, swept wings with thickness,
## winglets and two engines on pylons, the fin and tailplane, cockpit and
## cabin windows, the airline's cheatline, and its lights.
func airliner(tail: Color) -> Mesh:
	var mk := MeshKit.new(0)
	mk.shadow = false
	var white := Color(0.95, 0.95, 0.94)
	var belly := Color(0.78, 0.8, 0.83)
	var wing := Color(0.8, 0.82, 0.85)
	var dark := Color(0.14, 0.17, 0.21)
	var r := 0.22
	# the fuselage: a tube, a rounded nose and a tail cone sweeping up
	BoatKit.tube(mk, Vector3(0, 0, -1.45), Vector3.BACK, 2.9, r, r, 12, white, false)
	BoatKit.tube(mk, Vector3(0, 0, 1.45), Vector3(0, -0.12, 1).normalized(), 0.32, r, r * 0.72, 12, white, false)
	BoatKit.tube(mk, Vector3(0, -0.035, 1.765), Vector3(0, -0.25, 1).normalized(), 0.2, r * 0.72, r * 0.25, 12, white, true)
	BoatKit.tube(mk, Vector3(0, 0, -1.45), Vector3(0, 0.3, -1).normalized(), 0.8, r, r * 0.3, 12, white, true)
	# the airline's cheatline down each side, with the cabin windows above it
	for sx: float in [-1.0, 1.0]:
		var x := sx * (r + 0.003)
		mk.quad(Vector3(x, -0.04, -1.4), Vector3(x, -0.04, 1.5), Vector3(x, 0.0, 1.5), Vector3(x, 0.0, -1.4), Vector3(sx, 0, 0), tail)
		mk.quad(Vector3(x, 0.05, -1.25), Vector3(x, 0.05, 1.35), Vector3(x, 0.095, 1.35), Vector3(x, 0.095, -1.25), Vector3(sx, 0, 0), dark, 2.0)
		# the doors at each end of the cabin
		for z: float in [1.3, -1.2]:
			mk.quad(Vector3(x * 1.001, -0.05, z), Vector3(x * 1.001, -0.05, z + 0.12), Vector3(x * 1.001, 0.13, z + 0.12), Vector3(x * 1.001, 0.13, z), Vector3(sx, 0, 0), belly)
		# the cockpit windows, wrapping round the nose
		mk.quad(Vector3(sx * 0.07, 0.11, 1.74), Vector3(sx * 0.15, 0.08, 1.66), Vector3(sx * 0.16, 0.12, 1.6), Vector3(sx * 0.07, 0.15, 1.68), Vector3(sx * 0.4, 0.6, 1).normalized(), dark)
	# the grey belly fairing where the wings join
	mk.box(Vector3(0, -0.2, 0.05), Vector3(0.36, 0.08, 1.0), belly, null, true)
	for sx: float in [-1.0, 1.0]:
		# swept wings with a thick root thinning to the tip
		var ra := Vector3(sx * 0.18, -0.1, 0.55)
		var rb := Vector3(sx * 0.18, -0.1, -0.35)
		var ta := Vector3(sx * 2.05, 0.04, -0.62)
		var tb := Vector3(sx * 2.05, 0.04, -0.88)
		var up := Vector3(0, 0.05, 0)
		var tup := Vector3(0, 0.015, 0)
		mk.quad(ra + up, rb + up, tb + tup, ta + tup, Vector3.UP, wing)
		mk.quad(ra, rb, tb, ta, Vector3.DOWN, belly)
		mk.quad(ra, ra + up, ta + tup, ta, Vector3(0, 0, 1), wing.darkened(0.08))
		mk.quad(rb, rb + up, tb + tup, tb, Vector3(0, 0, -1), belly)
		# flaps picked out along the trailing edge
		mk.quad(rb.lerp(tb, 0.1) + up * 0.95 + Vector3(0, 0, 0.12), rb.lerp(tb, 0.55) + up * 0.6 + Vector3(0, 0, 0.1), rb.lerp(tb, 0.55) + up * 0.6, rb.lerp(tb, 0.1) + up * 0.95, Vector3.UP, wing.darkened(0.12))
		# a winglet in the airline's colour
		mk.quad(ta + tup, tb + tup, tb + Vector3(sx * 0.06, 0.32, -0.12), ta + Vector3(sx * 0.06, 0.32, -0.25), Vector3(sx, 0, 0), tail)
		mk.quad(ta + tup, tb + tup, tb + Vector3(sx * 0.06, 0.32, -0.12), ta + Vector3(sx * 0.06, 0.32, -0.25), Vector3(-sx, 0, 0), tail)
		# an engine on a pylon under each wing: nacelle, dark intake, exhaust cone
		var ec := Vector3(sx * 0.78, -0.27, 0.42)
		BoatKit.tube(mk, ec + Vector3(0, 0, -0.32), Vector3.BACK, 0.58, 0.12, 0.125, 10, Color(0.86, 0.87, 0.89), true, Color(0.1, 0.1, 0.12))
		BoatKit.tube(mk, ec + Vector3(0, 0, -0.32), Vector3.FORWARD, 0.14, 0.09, 0.03, 8, Color(0.45, 0.45, 0.48), true)
		mk.box(ec + Vector3(0, 0.15, -0.05), Vector3(0.04, 0.12, 0.42), wing)
		# the tailplane
		var pa := Vector3(sx * 0.1, 0.12, -1.55)
		var pb := Vector3(sx * 0.1, 0.12, -1.95)
		var pc := Vector3(sx * 0.82, 0.16, -2.08)
		var pd := Vector3(sx * 0.82, 0.16, -1.9)
		mk.quad(pa, pb, pc, pd, Vector3.UP, white)
		mk.quad(pa, pb, pc, pd, Vector3.DOWN, belly)
		# nav lights on the wingtips: red left, green right
		mk.box(ta.lerp(tb, 0.5) + Vector3(sx * 0.03, 0.03, 0), Vector3(0.08, 0.06, 0.1), Color(0.1, 0.9, 0.3) if sx > 0 else Color(1.0, 0.12, 0.08), null, false, 2.75)
	# the fin in the airline's colour, swept back, with a white light on top
	var fa := Vector3(0, 0.18, -1.15)
	var fb := Vector3(0, 0.18, -1.85)
	var fc := Vector3(0, 1.0, -2.05)
	var fd := Vector3(0, 1.0, -1.7)
	for sx: float in [-1.0, 1.0]:
		var o := Vector3(sx * 0.025, 0, 0)
		mk.quad(fa + o, fb + o, fc + o * 0.4, fd + o * 0.4, Vector3(sx, 0, 0), tail)
	mk.quad(fa + Vector3(0.025, 0, 0), fd + Vector3(0.01, 0, 0), fd - Vector3(0.01, 0, 0), fa - Vector3(0.025, 0, 0), Vector3(0, 0.3, 1), tail.lightened(0.1))
	mk.box(Vector3(0, 1.02, -1.88), Vector3(0.08, 0.08, 0.1), Color(1, 1, 1), null, false, 2.75)
	# a red beacon blinking on the belly
	mk.box(Vector3(0, -0.25, 0.5), Vector3(0.07, 0.05, 0.07), Color(1.0, 0.1, 0.06), null, false, 2.7)
	return mk.commit(material)


func _process(delta: float) -> void:
	if _plane == null:
		_wait -= delta
		if _wait <= 0.0:
			_wait = _rng.randf_range(WAIT.x, WAIT.y)
			spawn()
		return
	if _mode == "up":
		# rolls down the runway gathering speed, lifts off and climbs away
		_speed = minf(_speed + 3.0 * delta, SPEED)
	elif _mode == "down" and _d > 0.0:
		# touched down: brakes along the runway
		_speed = maxf(_speed - 3.2 * delta, 1.5)
	_d += _speed * delta
	if _d > _run:
		_plane.queue_free()
		_plane = null
		return
	_fly()


## Puts the airliner where it is along its course, nose up as it climbs
## and a little down as it comes in.
func _fly() -> void:
	var p := _from + _dir * _d
	var y := HEIGHT + _d * 0.01
	var pitch := 0.0
	if _mode == "up":
		# off the ground after the first stretch of runway
		var air := maxf(_d - 14.0, 0.0)
		y = minf(_ground + GROUND + air * CLIMB, HEIGHT)
		pitch = -0.16 if air > 0.0 and y < HEIGHT else 0.0
	elif _mode == "down":
		# down the glide path to the threshold, then rolling on the runway
		y = minf(_ground + GROUND + maxf(-_d, 0.0) * GLIDE, HEIGHT)
		pitch = 0.05 if _d < 0.0 else 0.0
	_plane.position = Vector3(p.x, y, p.y)
	_plane.basis = Basis(Vector3.UP, atan2(_dir.x, _dir.y)) * Basis(Vector3.RIGHT, pitch)


## Sends an airliner across the sky on a fresh course (or, with an airport,
## often up from it or down onto it).
## `force` ("up" or "down") picks a flight from the airport (shots, tests).
func spawn(halfway := false, force := "") -> void:
	var marks: Landmarks = world.get("landmarks") if world else null
	var rw := marks.runway() if marks else PackedVector3Array()
	if not halfway and rw.size() == 2 and (force != "" or _rng.randf() < 0.6):
		_mode = force if force != "" else "up" if _rng.randf() < 0.5 else "down"
		var a := Vector2(rw[0].x, rw[0].z)
		var b := Vector2(rw[1].x, rw[1].z)
		if _rng.randf() < 0.5:
			var t := a
			a = b
			b = t
		_ground = rw[0].y
		_dir = (b - a).normalized()
		_from = a
		if _mode == "up":
			_speed = 0.5
			_run = OUT
			_d = 0.0
		else:
			# from far out on the approach to the far end of the runway
			_speed = SPEED * 0.75
			_d = -(HEIGHT - GROUND) / GLIDE
			_run = a.distance_to(b)
		_launch()
		return
	_mode = ""
	_speed = SPEED
	var land: Land = world.get("land") if world else null
	var r := maxf(land.reach if land else Land.HALF, 120.0) * 1.6
	var side := _rng.randf() * TAU
	# a course that passes somewhere over the town, not always dead centre
	var aim := Vector2.from_angle(_rng.randf() * TAU) * _rng.randf() * r * 0.3
	_from = Vector2.from_angle(side) * r
	_dir = (aim - _from).normalized()
	_run = _from.distance_to(aim) * 2.0
	_d = _run * 0.5 if halfway else 0.0
	_launch()


func _launch() -> void:
	if _plane:
		_plane.queue_free()
	var mi := MeshInstance3D.new()
	mi.mesh = _kinds[_rng.randi() % _kinds.size()]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_plane = Node3D.new()
	_plane.add_child(mi)
	add_child(_plane)
	_fly()


## How many triangles one airliner draws.
func tris() -> int:
	var n := 0
	for s in _kinds[0].get_surface_count():
		var a := _kinds[0].surface_get_arrays(s)
		n += (a[Mesh.ARRAY_INDEX].size() if a[Mesh.ARRAY_INDEX] else a[Mesh.ARRAY_VERTEX].size()) / 3
	return n
