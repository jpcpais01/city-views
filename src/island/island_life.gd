class_name IslandLife
extends Life
## The classic town's sailboats, fishing boats and seagulls, around the new
## island: boats keep to open water off its real coastline, and gulls come
## down on its beaches and empty ground, or bob on the shallows.

var land: Land
var town: Town


## Places are kept on a half-metre grid: a cell is Vector2i(round(x * 2), round(z * 2)).
func _centre(t: Vector2i) -> Vector3:
	return Vector3(t.x * 0.5, 0.0, t.y * 0.5)


func reset() -> void:
	_rng.seed = land._noise.seed
	_boats.clear()
	_gulls.clear()
	_perches.clear()
	_shallows.clear()
	var sea: Array[Vector2i] = []
	var coast: Array[Vector2i] = []
	var x := -Land.HALF + 2.0
	while x < Land.HALF - 2.0:
		var z := -Land.HALF + 2.0
		while z < Land.HALF - 2.0:
			var h := land.height_at(x, z)
			var cell := Vector2i(roundi(x * 2.0), roundi(z * 2.0))
			if h < -2.2:
				sea.append(cell)
			elif h < -0.3 and h > -0.9:
				_shallows.append(cell)
			elif h > 0.1 and h < 1.0 and _by_water(x, z):
				coast.append(cell)
			z += 2.0
		x += 2.0
	for i in BOATS:
		var p: Vector3
		if sea.is_empty():
			var a := _rng.randf() * TAU
			p = Vector3(cos(a), 0, sin(a)) * 70.0
		else:
			p = _centre(sea[_rng.randi() % sea.size()])
		_boats.append({"p": p, "h": _rng.randf() * TAU, "th": _rng.randf() * TAU, "kind": 0 if i % 3 != 2 else 1,
			"v": _rng.randf_range(0.9, 1.5), "ph": _rng.randf() * TAU, "turn": 0.0})
	_perches = coast
	for i in GULLS:
		var c := Vector3.ZERO
		if not coast.is_empty():
			c = _centre(coast[_rng.randi() % coast.size()])
		var alt := _rng.randf_range(4.5, 9.0)
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(3.0, 9.0)
		_gulls.append({"p": c + Vector3(cos(a) * r, alt, sin(a) * r), "h": _rng.randf() * TAU, "v": 2.4,
			"c": c, "r": r, "dir": 1.0 if _rng.randf() < 0.5 else -1.0, "alt": alt,
			"st": SOAR, "time": _rng.randf_range(8.0, 30.0), "spot": Vector3.ZERO, "wet": false,
			"ph": _rng.randf() * TAU, "fl": 0.0, "fold": 0.0, "legs": 0.0, "bank": 0.0, "pitch": 0.0,
			"seed": _rng.randf() * TAU, "plunge": false, "look": 0.0, "call": false})
	for mm in _boat_mm + _boat_shadow_mm:
		mm.visible_instance_count = 0


func _by_water(x: float, z: float) -> bool:
	for k in 6:
		var d := Vector2.from_angle(k * TAU / 6.0) * 3.0
		if land.height_at(x + d.x, z + d.y) < 0.0:
			return true
	return false


func _taken(p: Vector3) -> bool:
	return town.is_built(Vector2(p.x, p.z))


func _ground_y(p: Vector3) -> float:
	return land.height_at(p.x, p.z)


## Open water ahead, in the classic town's tiles: 0 on land, 8 far out to sea.
func _clear(p: Vector3) -> float:
	if absf(p.x) > Land.HALF or absf(p.z) > Land.HALF:
		return 8.0
	return clampf(-land.height_at(p.x, p.z) * 2.0, 0.0, 8.0)
