class_name Traffic
extends Node3D
## Little toy cars that wander the road network, following lanes, ramps and bridges.

const DIRS := CityGen.DIRS
const LANE := 0.3
const CAR_COLORS := [Color("ef5b5b"), Color("4b86d6"), Color("f2c14e"), Color("f5f5f2"), Color("3fae8c"), Color("ef7fa8"), Color("6c7a89"), Color("ff9248")]

var material: Material
const MAX_CARS := 48
var _meshes: Array[ArrayMesh] = []
# one MultiMesh per car style: every car of a colour is a single draw call
var _multi: Array[MultiMesh] = []
var _cars: Array = []
var _road_tiles: Array[Vector2i] = []
var _dirty := true
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
		add_child(mmi)
		_multi.append(mm)


func mark_dirty() -> void:
	_dirty = true


func clear() -> void:
	_cars.clear()
	for mm in _multi:
		mm.visible_instance_count = 0
	_dirty = true


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
	for sx in [-0.17, 0.17]:
		for sz in [-len * 0.3, len * 0.3]:
			mk.push(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(sx, 0.07, sz)))
			mk.cylinder(Vector3(0, -0.035, 0), 0.07, 0.07, 8, Color(0.18, 0.18, 0.2))
			mk.pop()
	# headlights (lit at night) and tail lights
	for sx in [-0.11, 0.11]:
		mk.box(Vector3(sx, 0.14, len * 0.5 + 0.005), Vector3(0.07, 0.04, 0.02), Color(1, 0.97, 0.85), null, false, 2.0)
		mk.box(Vector3(sx, 0.14, -len * 0.5 - 0.005), Vector3(0.07, 0.04, 0.02), Color(0.9, 0.2, 0.2), null, false, 2.0)
	return mk.commit(material)


func _rebuild_tiles() -> void:
	_road_tiles.clear()
	for z in Game.N:
		for x in Game.N:
			if Game.knd(x, z) == Game.K.ROAD:
				_road_tiles.append(Vector2i(x, z))
	_dirty = false


func _links(t: Vector2i) -> Array:
	return CityGen.road_links(t.x, t.y)


func _choose_out(t: Vector2i, din: int) -> int:
	var links := _links(t)
	var opts: Array[int] = []
	for i in 4:
		if links[i] and i != (din + 2) % 4:
			opts.append(i)
	if opts.is_empty():
		if links[(din + 2) % 4]:
			return (din + 2) % 4
		return -1
	# prefer going straight a bit more often
	if opts.has(din) and randf() < 0.5:
		return din
	return opts[randi() % opts.size()]


func _process(delta: float) -> void:
	if _dirty:
		_rebuild_tiles()
	var wanted: int = mini(mini(_road_tiles.size() / 3, 4 + Game.population / 8), MAX_CARS - 8)
	_spawn_timer -= delta
	if _cars.size() < wanted and _spawn_timer <= 0.0:
		_spawn_timer = 0.4
		_spawn()
	elif _cars.size() > wanted + 2:
		_cars.pop_back()
	var i := 0
	while i < _cars.size():
		var c: Dictionary = _cars[i]
		if not _step(c, delta):
			_cars.remove_at(i)
			continue
		i += 1
	var counts: Array[int] = []
	counts.resize(_multi.size())
	for c in _cars:
		var v: int = c.v
		if counts[v] >= MAX_CARS:
			continue
		_multi[v].set_instance_transform(counts[v], c.xf)
		counts[v] += 1
	for v in _multi.size():
		_multi[v].visible_instance_count = counts[v]


func _spawn() -> void:
	if _road_tiles.is_empty():
		return
	var t := _road_tiles[randi() % _road_tiles.size()]
	var links := _links(t)
	var dirs: Array[int] = []
	for k in 4:
		if links[k]:
			dirs.append(k)
	if dirs.is_empty():
		return
	var din: int = dirs[randi() % dirs.size()]
	var dout := _choose_out(t, din)
	if dout < 0:
		return
	var car := {"v": randi() % _meshes.size(), "xf": Transform3D(), "tile": t, "din": din, "dout": dout, "t": randf() * 0.5, "speed": randf_range(1.3, 1.9), "grow": 0.0}
	_cars.append(car)


func _right(i: int) -> Vector3:
	var d := DIRS[i]
	return Vector3(-d.y, 0, d.x)


func _local_pos(din: int, dout: int, t: float) -> Array:
	var h := Game.TILE * 0.5
	var di := Vector3(DIRS[din].x, 0, DIRS[din].y)
	var dd := Vector3(DIRS[dout].x, 0, DIRS[dout].y)
	var a := -di * h + _right(din) * LANE
	var b := dd * h + _right(dout) * LANE
	var c: Vector3
	if din == dout:
		c = _right(din) * LANE
	elif dout == (din + 2) % 4:
		c = di * 0.35
	else:
		c = _right(din) * LANE + _right(dout) * LANE
	var u := 1.0 - t
	var p := a * u * u + c * 2.0 * u * t + b * t * t
	var tan := (c - a) * 2.0 * u + (b - c) * 2.0 * t
	return [p, tan]


func _step(c: Dictionary, delta: float) -> bool:
	var t: Vector2i = c.tile
	if Game.knd(t.x, t.y) != Game.K.ROAD:
		return false
	c.grow = min(1.0, c.grow + delta * 3.0)
	c.t += delta * c.speed / Game.TILE
	while c.t >= 1.0:
		c.t -= 1.0
		var d := DIRS[c.dout]
		var nt := Vector2i(t.x + d.x, t.y + d.y)
		if Game.knd(nt.x, nt.y) != Game.K.ROAD or not _links(t)[c.dout]:
			return false
		c.tile = nt
		t = nt
		c.din = c.dout
		var o := _choose_out(nt, c.din)
		if o < 0:
			return false
		c.dout = o
	var res := _local_pos(c.din, c.dout, c.t)
	var lp: Vector3 = res[0]
	var tan: Vector3 = res[1]
	var center := Game.tile_center(t.x, t.y)
	var y := center.y + CityGen.road_height(t.x, t.y, Vector2(lp.x, lp.z)) + 0.06
	var pos := Vector3(center.x + lp.x, y, center.z + lp.z)
	var rot: Basis = (c.xf as Transform3D).basis.orthonormalized()
	if tan.length() > 0.001:
		var ahead := Vector2(lp.x, lp.z) + Vector2(tan.x, tan.z).normalized() * 0.2
		var y2 := center.y + CityGen.road_height(t.x, t.y, ahead) + 0.06
		var fwd := Vector3(tan.x, 0, tan.z).normalized()
		var pitch := atan2(y2 - y, 0.2)
		rot = Basis(Vector3.UP, atan2(fwd.x, fwd.z)) * Basis(Vector3.RIGHT, -pitch)
	var s := Tween.interpolate_value(0.0, 1.0, c.grow, 1.0, Tween.TRANS_BACK, Tween.EASE_OUT) as float
	c.xf = Transform3D(rot.scaled(Vector3.ONE * max(s, 0.01)), pos)
	return true
