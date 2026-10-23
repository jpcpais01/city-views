class_name IslandTraffic
extends Traffic
## The classic town's toy cars, driving the new island's streets: keeping to
## the right, turning where streets meet, round again at a dead end. More cars
## as the town grows.

var streets: Streets
var town: Town
var _rng := RandomNumberGenerator.new()


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
