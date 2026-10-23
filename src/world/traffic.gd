class_name Traffic
extends Node3D
## The toy cars on the island's streets: keeping to the right, turning where
## streets meet, round again at a dead end, more of them as the town grows.
## One MultiMesh per colour keeps every car of a colour to a single draw call.

const CAR_COLORS := [Color("ef5b5b"), Color("4b86d6"), Color("f2c14e"), Color("f5f5f2"), Color("3fae8c"), Color("ef7fa8"), Color("6c7a89"), Color("ff9248")]

var material: Material
var streets: Streets
var town: Town
var _rng := RandomNumberGenerator.new()
const MAX_CARS := 48
var _meshes: Array[ArrayMesh] = []
var _shadow_meshes: Array[ArrayMesh] = []
# one MultiMesh per car style: every car of a colour is a single draw call
var _multi: Array[MultiMesh] = []
# a box or two per car for the shadow map instead of the whole car
var _shadow_multi: Array[MultiMesh] = []
var _cars: Array = []
var _spawn_timer := 0.0


func _ready() -> void:
	for i in CAR_COLORS.size():
		_meshes.append(_car_mesh(CAR_COLORS[i], i))
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


func _car_mesh(col: Color, variant: int) -> ArrayMesh:
	var mk := MeshKit.new(variant)
	var van := variant % 4 == 3
	var len := 0.62 if not van else 0.7
	# body along local +Z
	mk.rbox(Vector3(0, 0.13, 0), Vector3(0.34, 0.16, len), 0.06, col)
	if van:
		mk.rbox(Vector3(0, 0.3, -0.04), Vector3(0.32, 0.22, len * 0.82), 0.06, col.lightened(0.1))
		mk.window(Vector3(0, 0.32, len * 0.5 - 0.15), Vector3.BACK, 0.26, 0.12, Color(0.25, 0.32, 0.4))
	else:
		mk.rbox(Vector3(0, 0.27, -0.03), Vector3(0.3, 0.14, len * 0.55), 0.06, Color(0.95, 0.96, 0.98))
		mk.window(Vector3(0, 0.27, len * 0.25 - 0.02), Vector3.BACK, 0.24, 0.09, Color(0.25, 0.32, 0.4))
		mk.window(Vector3(0, 0.27, -len * 0.31), Vector3.FORWARD, 0.24, 0.09, Color(0.25, 0.32, 0.4))
	mk.shadow = false
	for sx in [-0.17, 0.17]:
		for sz in [-len * 0.3, len * 0.3]:
			# hub cap on the outside only; the inner face is hidden under the car
			mk.push(Transform3D(Basis(Vector3.BACK, PI * 0.5 * signf(-sx)), Vector3(sx, 0.07, sz)))
			mk.cylinder(Vector3(0, -0.035, 0), 0.07, 0.07, 7, Color(0.18, 0.18, 0.2))
			mk.pop()
	# headlights (lit at night) and tail lights, flush with the body
	for sx in [-0.11, 0.11]:
		var f := len * 0.5 + 0.015
		mk.quad(Vector3(sx - 0.035, 0.12, f), Vector3(sx + 0.035, 0.12, f), Vector3(sx + 0.035, 0.16, f), Vector3(sx - 0.035, 0.16, f), Vector3.BACK, Color(1, 0.97, 0.85), 2.0)
		mk.quad(Vector3(sx - 0.035, 0.12, -f), Vector3(sx + 0.035, 0.12, -f), Vector3(sx + 0.035, 0.16, -f), Vector3(sx - 0.035, 0.16, -f), Vector3.FORWARD, Color(0.9, 0.2, 0.2), 2.0)
	_shadow_meshes.append(mk.commit_shadow(Palette.shadow_material()))
	return mk.commit(material)


func _process(delta: float) -> void:
	var graph := streets.links()
	var total := 0.0
	for s: Streets.Street in streets.streets:
		total += s.pts.size() * Streets.SAMPLE
	var wanted := mini(int(total / 16.0) + town.lots.size() / 10, MAX_CARS - 8)
	_spawn_timer -= delta
	if _cars.size() < wanted and _spawn_timer <= 0.0:
		_spawn_timer = 0.4
		var m := StreetWalk.spawn(streets, _rng)
		if not m.is_empty():
			m.merge({"v": _rng.randi() % _meshes.size(), "xf": Transform3D(), "speed": _rng.randf_range(1.3, 1.9), "grow": 0.0})
			_cars.append(m)
	elif _cars.size() > wanted + 2:
		_cars.pop_back()
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


func _drive(c: Dictionary, graph: Dictionary, delta: float) -> bool:
	if not StreetWalk.advance(streets, graph, c, c.speed * delta, 0.4, _rng):
		return false
	var s: Streets.Street = c.s
	var at := StreetWalk.place(streets, c, s.w() * 0.42 * c.dir)
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
