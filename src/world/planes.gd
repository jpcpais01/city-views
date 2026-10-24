class_name Planes
extends Node3D
## An airliner crossing high over the city now and then: white with a
## coloured tail, swept wings with an engine under each, a row of cabin
## windows that glow at night and nav lights on the wingtips, red on the
## left blinking and green on the right.

const WAIT := Vector2(40.0, 90.0)
const SPEED := 16.0
const HEIGHT := 40.0
const TAILS := [Color("c8553d"), Color("2f5f9f"), Color("2f8f83"), Color("e3a33b")]

var material: Material
var world: Node3D
var _kinds: Array[Mesh] = []
var _plane: Node3D
var _from := Vector2.ZERO
var _dir := Vector2.ZERO
var _run := 0.0
var _d := 0.0
var _wait := 12.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	for tail: Color in TAILS:
		_kinds.append(airliner(tail))


## An airliner about four units long, nose towards +Z.
func airliner(tail: Color) -> Mesh:
	var mk := MeshKit.new(0)
	mk.shadow = false
	var white := Color(0.95, 0.95, 0.94)
	var belly := Color(0.78, 0.8, 0.83)
	var wing := Color(0.82, 0.84, 0.86)
	mk.box(Vector3(0, 0, 0), Vector3(0.42, 0.44, 3.4), white, white, true)
	mk.box(Vector3(0, -0.04, 1.9), Vector3(0.32, 0.32, 0.4), white, white, true)
	mk.quad(Vector3(-0.2, -0.225, -1.65), Vector3(0.2, -0.225, -1.65), Vector3(0.2, -0.225, 1.65), Vector3(-0.2, -0.225, 1.65), Vector3.DOWN, belly)
	# cabin windows down both sides, warm at night
	for sx in [-1.0, 1.0]:
		var x: float = sx * 0.212
		mk.quad(Vector3(x, 0.06, -1.3), Vector3(x, 0.06, 1.5), Vector3(x, 0.12, 1.5), Vector3(x, 0.12, -1.3), Vector3(sx, 0, 0), Color(0.15, 0.18, 0.22), 2.0)
	# swept wings, seen from above and below
	for sx in [-1.0, 1.0]:
		var root_a := Vector3(sx * 0.2, -0.08, 0.5)
		var root_b := Vector3(sx * 0.2, -0.08, -0.4)
		var tip_a := Vector3(sx * 2.1, 0.02, -0.55)
		var tip_b := Vector3(sx * 2.1, 0.02, -0.85)
		mk.quad(root_a, root_b, tip_b, tip_a, Vector3.UP, wing)
		mk.quad(root_a, root_b, tip_b, tip_a, Vector3.DOWN, belly)
		# an engine slung under each wing
		mk.box(Vector3(sx * 0.85, -0.22, 0.25), Vector3(0.2, 0.2, 0.55), Color(0.7, 0.72, 0.75))
		# the nav light on the tip
		mk.box(Vector3(sx * 2.12, 0.02, -0.7), Vector3(0.14, 0.1, 0.14), Color(0.1, 0.9, 0.3) if sx > 0 else Color(1.0, 0.12, 0.08), null, false, 2.7)
		# the tailplane
		var ta := Vector3(sx * 0.15, 0.1, -1.4)
		var tb := Vector3(sx * 0.15, 0.1, -1.8)
		var tc := Vector3(sx * 0.85, 0.12, -1.95)
		var td := Vector3(sx * 0.85, 0.12, -1.75)
		mk.quad(ta, tb, tc, td, Vector3.UP, white)
		mk.quad(ta, tb, tc, td, Vector3.DOWN, belly)
	# the fin, in the airline's colour, with a white light on top
	var fa := Vector3(0, 0.2, -1.1)
	var fb := Vector3(0, 0.2, -1.7)
	var fc := Vector3(0, 1.0, -1.9)
	var fd := Vector3(0, 1.0, -1.6)
	mk.quad(fa, fb, fc, fd, Vector3.RIGHT, tail)
	mk.quad(fa, fb, fc, fd, Vector3.LEFT, tail)
	mk.box(Vector3(0, 1.02, -1.75), Vector3(0.1, 0.1, 0.12), Color(1, 1, 1), null, false, 2.7)
	return mk.commit(material)


func _process(delta: float) -> void:
	if _plane == null:
		_wait -= delta
		if _wait <= 0.0:
			_wait = _rng.randf_range(WAIT.x, WAIT.y)
			spawn()
		return
	_d += SPEED * delta
	if _d > _run:
		_plane.queue_free()
		_plane = null
		return
	var p := _from + _dir * _d
	_plane.position = Vector3(p.x, HEIGHT + _d * 0.01, p.y)


## Sends an airliner across the sky on a fresh course.
func spawn(halfway := false) -> void:
	var land: Land = world.get("land") if world else null
	var r := maxf(land.reach if land else Land.HALF, 120.0) * 1.6
	var side := _rng.randf() * TAU
	# a course that passes somewhere over the town, not always dead centre
	var aim := Vector2.from_angle(_rng.randf() * TAU) * _rng.randf() * r * 0.3
	_from = Vector2.from_angle(side) * r
	_dir = (aim - _from).normalized()
	_run = _from.distance_to(aim) * 2.0
	_d = _run * 0.5 if halfway else 0.0
	var mi := MeshInstance3D.new()
	mi.mesh = _kinds[_rng.randi() % _kinds.size()]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_plane = Node3D.new()
	_plane.add_child(mi)
	_plane.basis = Basis(Vector3.UP, atan2(_dir.x, _dir.y))
	add_child(_plane)
	var p := _from + _dir * _d
	_plane.position = Vector3(p.x, HEIGHT, p.y)


## How many triangles one airliner draws.
func tris() -> int:
	var n := 0
	for s in _kinds[0].get_surface_count():
		var a := _kinds[0].surface_get_arrays(s)
		n += (a[Mesh.ARRAY_INDEX].size() if a[Mesh.ARRAY_INDEX] else a[Mesh.ARRAY_VERTEX].size()) / 3
	return n
