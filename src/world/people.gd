class_name People
extends Node3D
## Townsfolk strolling the pavements of the island's streets, more of them as
## the town fills with houses; now and then one stops to look around. One
## MultiMesh per outfit keeps them to a few draw calls.

const MAX_PEOPLE := 72
const SHIRTS := [Color("ef5b5b"), Color("4b86d6"), Color("f2c14e"), Color("3fae8c"), Color("ef7fa8"), Color("f5f5f2")]
const PANTS := [Color("3d4a5c"), Color("5b4a42"), Color("2f3a48"), Color("c9b48f")]
const SKIN := [Color("f3d2b5"), Color("d9a77c"), Color("a8714f"), Color("7a4e34")]

var material: Material
var streets: Streets
var town: Town
var _rng := RandomNumberGenerator.new()
var _multi: Array[MultiMesh] = []
var _people: Array = []
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


func clear() -> void:
	_people.clear()
	for mm in _multi:
		mm.visible_instance_count = 0


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


func _process(delta: float) -> void:
	var graph := streets.links()
	var wanted := mini(6 + town.lots.size() / 4, MAX_PEOPLE - 4) if not town.lots.is_empty() else 0
	_spawn_timer -= delta
	if _people.size() < wanted and _spawn_timer <= 0.0:
		_spawn_timer = 0.25
		var m := StreetWalk.spawn(streets, _rng)
		# (no pavements along a highway)
		if not m.is_empty() and m.s.kind != "highway":
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
