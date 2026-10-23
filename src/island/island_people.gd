class_name IslandPeople
extends People
## Townsfolk strolling the pavements of the new island's streets, more of them
## as the town fills with houses; now and then one stops to look around.

var streets: Streets
var town: Town
var _rng := RandomNumberGenerator.new()


func _process(delta: float) -> void:
	var graph := streets.links()
	var wanted := mini(6 + town.lots.size() / 4, MAX_PEOPLE - 4) if not town.lots.is_empty() else 0
	_spawn_timer -= delta
	if _people.size() < wanted and _spawn_timer <= 0.0:
		_spawn_timer = 0.25
		var m := StreetWalk.spawn(streets, _rng)
		if not m.is_empty():
			m.merge({"v": _rng.randi() % SHIRTS.size(), "xf": Transform3D(), "speed": _rng.randf_range(0.32, 0.5),
				"side": 1.0 if _rng.randf() < 0.5 else -1.0, "ph": _rng.randf() * TAU, "grow": 0.0, "pause": 0.0})
			_people.append(m)
	elif _people.size() > wanted + 3:
		_people.pop_back()
	var time := Time.get_ticks_msec() * 0.001
	var counts: Array[int] = []
	counts.resize(_multi.size())
	var i := 0
	while i < _people.size():
		var p: Dictionary = _people[i]
		if not _walk(p, graph, delta, time):
			_people.remove_at(i)
			continue
		var v: int = p.v
		_multi[v].set_instance_transform(counts[v], p.xf)
		counts[v] += 1
		i += 1
	for v in _multi.size():
		_multi[v].visible_instance_count = counts[v]


func _walk(p: Dictionary, graph: Dictionary, delta: float, time: float) -> bool:
	var go := 0.0
	if p.pause > 0.0:
		p.pause -= delta
	else:
		if _rng.randf() < delta * 0.04:
			p.pause = _rng.randf_range(1.0, 3.0)
		go = p.speed * delta
	if not StreetWalk.advance(streets, graph, p, go, 0.35, _rng):
		return false
	var s: Streets.Street = p.s
	var at := StreetWalk.place(streets, p, (s.w() + Streets.PAVE * 0.5) * p.side)
	var pos: Vector3 = at[0] + Vector3(0, Streets.CURB, 0)
	var fwd: Vector3 = at[1]
	var walking: bool = p.pause <= 0.0
	pos.y += absf(sin(time * 9.0 + p.ph)) * 0.012 if walking else 0.0
	var rot := Basis(Vector3.UP, atan2(fwd.x, fwd.z))
	if walking:
		rot = rot * Basis(Vector3.BACK, sin(time * 9.0 + p.ph) * 0.06)
	p.grow = minf(1.0, p.grow + delta * 3.0)
	var sc := Tween.interpolate_value(0.0, 1.0, p.grow, 1.0, Tween.TRANS_BACK, Tween.EASE_OUT) as float
	var old: Transform3D = p.xf
	var k := 1.0 - exp(-delta * 8.0)
	if p.grow < 1.0 or old.origin.distance_to(pos) > 1.2:
		k = 1.0
	p.xf = Transform3D(rot.scaled(Vector3.ONE * maxf(sc, 0.01)), old.origin.lerp(pos, k))
	return true
