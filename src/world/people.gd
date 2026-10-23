class_name People
extends Node3D
## Tiny townsfolk strolling the sidewalks, crossing at junctions, more of them
## as the town grows. One MultiMesh per outfit keeps them to a few draw calls.

const DIRS := CityGen.DIRS
const WALK := 0.81  # sidewalk centre line from the road axis
const MAX_PEOPLE := 72
const SHIRTS := [Color("ef5b5b"), Color("4b86d6"), Color("f2c14e"), Color("3fae8c"), Color("ef7fa8"), Color("f5f5f2")]
const PANTS := [Color("3d4a5c"), Color("5b4a42"), Color("2f3a48"), Color("c9b48f")]
const SKIN := [Color("f3d2b5"), Color("d9a77c"), Color("a8714f"), Color("7a4e34")]

var material: Material
var _multi: Array[MultiMesh] = []
var _people: Array = []
var _roads: Array[Vector2i] = []
var _dirty := true
var _spawn_timer := 0.0


func _ready() -> void:
	for i in SHIRTS.size():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _person(i)
		mm.instance_count = MAX_PEOPLE
		mm.visible_instance_count = 0
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		# far too small to read in the shadow map
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
		_multi.append(mm)


func mark_dirty() -> void:
	_dirty = true


func clear() -> void:
	_people.clear()
	for mm in _multi:
		mm.visible_instance_count = 0
	_dirty = true


func _person(v: int) -> ArrayMesh:
	var mk := MeshKit.new(40 + v)
	var shirt: Color = SHIRTS[v]
	var pants: Color = PANTS[v % PANTS.size()]
	var skin: Color = SKIN[v % SKIN.size()]
	# legs, body, arms and a round head; faces local +Z
	for sx in [-0.028, 0.028]:
		mk.pole(Vector3(sx, 0.0, 0), 0.023, 0.11, 6, pants)
	mk.rbox(Vector3(0, 0.16, 0), Vector3(0.11, 0.11, 0.07), 0.025, shirt)
	for sx in [-0.068, 0.068]:
		mk.box(Vector3(sx, 0.15, 0), Vector3(0.026, 0.09, 0.034), shirt.darkened(0.08))
	mk.blob(Vector3(0, 0.255, 0), Vector3(0.043, 0.045, 0.043), skin)
	if v % 3 == 0:
		# a little sun hat
		mk.cone(Vector3(0, 0.282, 0), 0.06, 0.014, 7, Color("e9d8a6"))
		mk.cylinder(Vector3(0, 0.295, 0), 0.035, 0.03, 6, Color("e9d8a6"))
	else:
		# hair: a slightly bigger ball set up and back, leaving the face showing
		mk.blob(Vector3(0, 0.266, -0.012), Vector3(0.042, 0.042, 0.042), [Color("3a2a20"), Color("6b4a2e"), Color("d8b46a"), Color("1f1f24")][v % 4])
	return mk.commit(material)


func _rebuild_roads() -> void:
	_roads.clear()
	for z in Game.N:
		for x in Game.N:
			# bridges have no sidewalk worth strolling
			if Game.knd(x, z) == Game.K.ROAD and Game.lvl(x, z) > 0 and _near_buildings(x, z):
				_roads.append(Vector2i(x, z))
	_dirty = false


func _near_buildings(x: int, z: int) -> bool:
	for d in DIRS:
		var k := Game.knd(x + d.x, z + d.y)
		if Game.is_building(k) or k == Game.K.PARK or k == Game.K.LANDMARK:
			return true
	return false


func _links(t: Vector2i) -> Array:
	return CityGen.road_links(t.x, t.y)


func _choose_out(t: Vector2i, din: int) -> int:
	var links := _links(t)
	var opts: Array[int] = []
	for i in 4:
		if links[i] and i != (din + 2) % 4:
			opts.append(i)
	if opts.is_empty():
		# dead end: turn around along the other sidewalk
		return (din + 2) % 4 if links[(din + 2) % 4] else -1
	if opts.has(din) and randf() < 0.6:
		return din
	return opts[randi() % opts.size()]


func _process(delta: float) -> void:
	if _dirty:
		_rebuild_roads()
	var wanted: int = mini(mini(_roads.size(), 6 + Game.population / 14), MAX_PEOPLE - 4)
	_spawn_timer -= delta
	if _people.size() < wanted and _spawn_timer <= 0.0:
		_spawn_timer = 0.25
		_spawn()
	elif _people.size() > wanted + 3:
		_people.pop_back()
	var t := Time.get_ticks_msec() * 0.001
	var counts: Array[int] = []
	counts.resize(_multi.size())
	var i := 0
	while i < _people.size():
		var p: Dictionary = _people[i]
		if not _step(p, delta, t):
			_people.remove_at(i)
			continue
		var v: int = p.v
		_multi[v].set_instance_transform(counts[v], p.xf)
		counts[v] += 1
		i += 1
	for v in _multi.size():
		_multi[v].visible_instance_count = counts[v]


func _spawn() -> void:
	if _roads.is_empty():
		return
	var tile := _roads[randi() % _roads.size()]
	var links := _links(tile)
	var dirs: Array[int] = []
	for k in 4:
		if links[k]:
			dirs.append(k)
	if dirs.is_empty():
		return
	var din: int = dirs[randi() % dirs.size()]
	var dout := _choose_out(tile, din)
	if dout < 0:
		return
	_people.append({"v": randi() % SHIRTS.size(), "xf": Transform3D(), "tile": tile, "din": din, "dout": dout,
		"t": randf(), "speed": randf_range(0.32, 0.5), "side": 1.0 if randf() < 0.5 else -1.0,
		"ph": randf() * TAU, "grow": 0.0, "pause": 0.0})


func _side(i: int, s: float) -> Vector3:
	var d := DIRS[i]
	return Vector3(-d.y, 0, d.x) * WALK * s


func _local_pos(p: Dictionary) -> Array:
	var h := Game.TILE * 0.5
	var din: int = p.din
	var dout: int = p.dout
	var s: float = p.side
	var di := Vector3(DIRS[din].x, 0, DIRS[din].y)
	var dd := Vector3(DIRS[dout].x, 0, DIRS[dout].y)
	var a := -di * h + _side(din, s)
	var b := dd * h + _side(dout, s)
	var c: Vector3
	if din == dout:
		c = (a + b) * 0.5
	elif dout == (din + 2) % 4:
		# U-turn at a dead end: swap to the other sidewalk at the far end
		c = di * h * 0.9
	else:
		c = _side(din, s) + _side(dout, s)
	var u := 1.0 - float(p.t)
	var tt: float = p.t
	var pos := a * u * u + c * 2.0 * u * tt + b * tt * tt
	var tan := (c - a) * 2.0 * u + (b - c) * 2.0 * tt
	return [pos, tan]


func _step(p: Dictionary, delta: float, time: float) -> bool:
	var tile: Vector2i = p.tile
	if Game.knd(tile.x, tile.y) != Game.K.ROAD:
		return false
	p.grow = minf(1.0, p.grow + delta * 3.0)
	# now and then someone stops to look around
	if p.pause > 0.0:
		p.pause -= delta
	else:
		if randf() < delta * 0.04:
			p.pause = randf_range(1.0, 3.0)
		p.t += delta * p.speed / Game.TILE
	while p.t >= 1.0:
		p.t -= 1.0
		var d := DIRS[p.dout]
		var nt := Vector2i(tile.x + d.x, tile.y + d.y)
		if Game.knd(nt.x, nt.y) != Game.K.ROAD or not _links(tile)[p.dout]:
			return false
		if p.dout == (p.din + 2) % 4:
			p.side = -p.side
		p.tile = nt
		tile = nt
		p.din = p.dout
		var o := _choose_out(nt, p.din)
		if o < 0:
			return false
		p.dout = o
	var res := _local_pos(p)
	var lp: Vector3 = res[0]
	var tan: Vector3 = res[1]
	var centre := Game.tile_center(tile.x, tile.y)
	var walking: bool = p.pause <= 0.0
	var bob := absf(sin(time * 9.0 + p.ph)) * 0.012 if walking else 0.0
	var y := centre.y + CityGen.road_height(tile.x, tile.y, Vector2(lp.x, lp.z)) + 0.1 + bob
	var rot := Basis(Vector3.UP, atan2(tan.x, tan.z)) if tan.length() > 0.001 else (p.xf as Transform3D).basis.orthonormalized()
	if walking:
		rot = rot * Basis(Vector3.BACK, sin(time * 9.0 + p.ph) * 0.06)
	var s := Tween.interpolate_value(0.0, 1.0, p.grow, 1.0, Tween.TRANS_BACK, Tween.EASE_OUT) as float
	p.xf = Transform3D(rot.scaled(Vector3.ONE * maxf(s, 0.01)), Vector3(centre.x + lp.x, y, centre.z + lp.z))
	return true
