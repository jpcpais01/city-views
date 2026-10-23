class_name Life
extends Node3D
## Ambient life around the island: sailboats and fishing boats wandering the
## open water, and seagulls gliding and flapping over the coast.
## Every kind is one MultiMesh, so the whole lot costs three draw calls.

const BOATS := 9
const GULLS := 16
const SAIL_COLORS := [Color("f7f3ea"), Color("ef7f6a"), Color("7fb8e6"), Color("f2c14e")]
const HULL_COLORS := [Color("f5f5f2"), Color("3d5f8f"), Color("c8553d"), Color("2f8f83")]

var material: Material
var rig: CameraRig
var _boat_mm: Array[MultiMesh] = []
# boxy stand-ins that draw the boats into the shadow map
var _boat_shadow_mm: Array[MultiMesh] = []
var _shadow_mesh: ArrayMesh
var _gull_mm: MultiMesh
var _boats: Array = []
var _gulls: Array = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	for i in 2:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = false
		mm.mesh = _sailboat() if i == 0 else _fishing_boat()
		mm.instance_count = BOATS
		mm.visible_instance_count = 0
		_add_mm(mm, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		_boat_mm.append(mm)
		var sm := MultiMesh.new()
		sm.transform_format = MultiMesh.TRANSFORM_3D
		sm.mesh = _shadow_mesh
		sm.instance_count = BOATS
		sm.visible_instance_count = 0
		_add_mm(sm, GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY)
		_boat_shadow_mm.append(sm)
	_gull_mm = MultiMesh.new()
	_gull_mm.transform_format = MultiMesh.TRANSFORM_3D
	_gull_mm.mesh = _gull()
	_gull_mm.instance_count = GULLS
	_gull_mm.visible_instance_count = 0
	_add_mm(_gull_mm, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)


func _add_mm(mm: MultiMesh, shadow: GeometryInstance3D.ShadowCastingSetting) -> void:
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = shadow
	# instances roam far from the node origin
	mmi.custom_aabb = AABB(Vector3(-200, -5, -200), Vector3(400, 40, 400))
	add_child(mmi)


# ------------------------------------------------------------------ meshes

func _sailboat() -> ArrayMesh:
	var mk := MeshKit.new(11)
	var hull: Color = HULL_COLORS[0]
	# hull along local +Z, pointed bow
	mk.rbox(Vector3(0, 0.08, -0.08), Vector3(0.42, 0.16, 0.9), 0.07, hull)
	mk.push(Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(0, 0.08, 0.36)))
	mk.rbox(Vector3.ZERO, Vector3(0.3, 0.16, 0.3), 0.06, hull)
	mk.pop()
	mk.box(Vector3(0, 0.165, -0.05), Vector3(0.34, 0.02, 0.7), Color("c99a6b"))
	mk.box(Vector3(0, 0.2, -0.26), Vector3(0.24, 0.08, 0.2), Color("e9e4d8"))
	mk.cylinder(Vector3(0, 0.16, 0.12), 0.018, 1.25, 5, Color("8a6a4a"))
	# mainsail and jib as thin double-sided wedges
	var sail: Color = SAIL_COLORS[0]
	var a := Vector3(0, 0.3, 0.1)
	var b := Vector3(0, 1.38, 0.12)
	var c := Vector3(0, 0.3, -0.42)
	mk.tri(a, b, c, sail, 0.0, 0.0, Vector3.RIGHT)
	mk.tri(a, b, c, sail, 0.0, 0.0, Vector3.LEFT)
	var d := Vector3(0, 0.26, 0.52)
	var e := Vector3(0, 1.2, 0.14)
	var f := Vector3(0, 0.3, 0.16)
	mk.tri(d, e, f, SAIL_COLORS[1], 0.0, 0.0, Vector3.RIGHT)
	mk.tri(d, e, f, SAIL_COLORS[1], 0.0, 0.0, Vector3.LEFT)
	# mast-top lantern for night sailing
	mk.box(Vector3(0, 1.42, 0.12), Vector3(0.05, 0.05, 0.05), Color(1, 0.9, 0.6), null, false, 2.0)
	_shadow_mesh = mk.commit_shadow(CityGen.shadow_material())
	return mk.commit(material)


func _fishing_boat() -> ArrayMesh:
	var mk := MeshKit.new(12)
	var hull: Color = HULL_COLORS[2]
	mk.rbox(Vector3(0, 0.1, 0), Vector3(0.5, 0.2, 1.1), 0.08, hull)
	mk.box(Vector3(0, 0.205, 0), Vector3(0.42, 0.02, 0.98), Color("f5f5f2"))
	mk.rbox(Vector3(0, 0.36, -0.2), Vector3(0.34, 0.3, 0.34), 0.05, Color("f5f5f2"), Color("3d5f8f"))
	mk.window(Vector3(0, 0.4, -0.03), Vector3.BACK, 0.22, 0.1, Color(0.25, 0.32, 0.4), Color(0, 0, 0, 0), true)
	mk.cylinder(Vector3(0, 0.5, -0.28), 0.03, 0.18, 6, Color("2b2b30"))
	mk.cylinder(Vector3(0, 0.2, 0.3), 0.015, 0.55, 5, Color("8a6a4a"))
	mk.box(Vector3(0, 0.62, 0.3), Vector3(0.06, 0.06, 0.06), Color(1, 0.9, 0.6), null, false, 2.0)
	_shadow_mesh = mk.commit_shadow(CityGen.shadow_material())
	return mk.commit(material)


func _gull() -> ArrayMesh:
	var mk := MeshKit.new(13)
	var white := Color("f7f7f4")
	var grey := Color("b9c0c8")
	mk.pebble(Vector3(0, 0, 0), Vector3(0.07, 0.06, 0.2), white)
	mk.pebble(Vector3(0, 0.035, 0.16), Vector3(0.05, 0.05, 0.06), white)
	mk.box(Vector3(0, 0.03, 0.23), Vector3(0.02, 0.02, 0.05), Color("f2b33d"))
	# wings in a gentle V; scaling the instance's Y flattens or deepens the V like a flap
	for s in [-1.0, 1.0]:
		var root_f := Vector3(0.05 * s, 0.01, 0.06)
		var root_b := Vector3(0.05 * s, 0.01, -0.08)
		var elbow_f := Vector3(0.26 * s, 0.07, 0.04)
		var elbow_b := Vector3(0.26 * s, 0.07, -0.09)
		var tip := Vector3(0.46 * s, 0.02, -0.08)
		mk.quad(root_f, elbow_f, elbow_b, root_b, Vector3.UP, white)
		mk.quad(root_f, elbow_f, elbow_b, root_b, Vector3.DOWN, white)
		mk.tri(elbow_f, tip, elbow_b, grey, 0.0, 0.0, Vector3.UP)
		mk.tri(elbow_f, tip, elbow_b, grey, 0.0, 0.0, Vector3.DOWN)
	mk.tri(Vector3(-0.05, 0.0, -0.16), Vector3(0.05, 0.0, -0.16), Vector3(0, 0.0, -0.3), white, 0.0, 0.0, Vector3.UP)
	mk.tri(Vector3(-0.05, 0.0, -0.16), Vector3(0.05, 0.0, -0.16), Vector3(0, 0.0, -0.3), white, 0.0, 0.0, Vector3.DOWN)
	return mk.commit(material)


# ------------------------------------------------------------------ spawning

func reset() -> void:
	_rng.seed = Game.seed_value
	_boats.clear()
	_gulls.clear()
	var sea: Array[Vector2i] = []
	var coast: Array[Vector2i] = []
	for z in Game.N:
		for x in Game.N:
			var s := Game.shore[Game.idx(x, z)] if Game.shore.size() == Game.N * Game.N else 8.0
			if Game.lvl(x, z) == 0 and s >= 3.0 and s <= 7.0:
				sea.append(Vector2i(x, z))
			elif Game.lvl(x, z) >= 1 and _near_water(x, z):
				coast.append(Vector2i(x, z))
	for i in BOATS:
		var p: Vector3
		if sea.is_empty():
			var a := _rng.randf() * TAU
			p = Vector3(cos(a), 0, sin(a)) * 80.0
		else:
			p = _centre(sea[_rng.randi() % sea.size()])
		_boats.append({"p": p, "h": _rng.randf() * TAU, "th": _rng.randf() * TAU, "kind": 0 if i % 3 != 2 else 1,
			"v": _rng.randf_range(0.9, 1.5), "ph": _rng.randf() * TAU, "turn": 0.0})
	for i in GULLS:
		var c := Vector3.ZERO
		if not coast.is_empty():
			c = _centre(coast[_rng.randi() % coast.size()])
		_gulls.append({"c": c, "r": _rng.randf_range(3.0, 9.0), "a": _rng.randf() * TAU,
			"w": _rng.randf_range(0.25, 0.45) * (1.0 if _rng.randf() < 0.5 else -1.0),
			"y": _rng.randf_range(4.5, 9.0), "ph": _rng.randf() * TAU, "move": _rng.randf_range(8.0, 30.0)})
	for mm in _boat_mm + _boat_shadow_mm:
		mm.visible_instance_count = 0


func _near_water(x: int, z: int) -> bool:
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if Game.inside(x + d.x, z + d.y) and Game.lvl(x + d.x, z + d.y) == 0:
			return true
	return false


func _centre(t: Vector2i) -> Vector3:
	return Vector3((t.x - Game.N * 0.5 + 0.5) * Game.TILE, 0.0, (t.y - Game.N * 0.5 + 0.5) * Game.TILE)


## Open water clearance at a world position, in tiles (8 = far out to sea).
func _clear(p: Vector3) -> float:
	var t := Game.world_to_tile(p)
	if not Game.inside(t.x, t.y):
		return 8.0
	if Game.lvl(t.x, t.y) > 0 or Game.shore.size() != Game.N * Game.N:
		return 0.0
	return Game.shore[Game.idx(t.x, t.y)]


# ------------------------------------------------------------------ motion

func _process(delta: float) -> void:
	if _boats.is_empty() and _gulls.is_empty():
		return
	var t := Time.get_ticks_msec() * 0.001
	var counts := [0, 0]
	for b in _boats:
		var fwd: Vector3 = Vector3(sin(b.h), 0, cos(b.h))
		# look ahead; steer away from the coast and back towards the island when too far out
		var ahead: float = _clear(b.p + fwd * 6.0)
		var dist: float = Vector2(b.p.x, b.p.z).length()
		if ahead < 2.5:
			var left: float = _clear(b.p + Vector3(sin(b.h + 0.8), 0, cos(b.h + 0.8)) * 6.0)
			var right: float = _clear(b.p + Vector3(sin(b.h - 0.8), 0, cos(b.h - 0.8)) * 6.0)
			b.th = b.h + (1.2 if left >= right else -1.2)
		elif dist > 95.0:
			b.th = atan2(-b.p.x, -b.p.z) + _rng.randf_range(-0.6, 0.6)
		elif _rng.randf() < delta * 0.05:
			b.th = b.h + _rng.randf_range(-1.0, 1.0)
		var dh: float = wrapf(b.th - b.h, -PI, PI)
		var turn: float = clampf(dh, -0.5 * delta, 0.5 * delta)
		b.h += turn
		b.turn = lerpf(b.turn, turn / maxf(delta, 0.001), minf(1.0, delta * 2.0))
		var slow: float = 0.35 if ahead < 1.5 else 1.0
		b.p += fwd * b.v * slow * delta
		if _clear(b.p) < 1.0:
			b.p -= fwd * b.v * slow * delta * 2.0
			b.th = b.h + PI
		# ride the swell
		var bob: float = sin(t * 1.3 + b.ph) * 0.035
		var roll: float = sin(t * 1.1 + b.ph * 1.7) * 0.06 - b.turn * 0.35
		var pitch: float = sin(t * 0.9 + b.ph) * 0.04
		var basis: Basis = Basis(Vector3.UP, b.h) * Basis(Vector3.FORWARD, roll) * Basis(Vector3.RIGHT, pitch)
		var k: int = b.kind
		var bx := Transform3D(basis * Basis.from_scale(Vector3.ONE * 1.5), b.p + Vector3(0, bob - 0.07, 0))
		_boat_mm[k].set_instance_transform(counts[k], bx)
		_boat_shadow_mm[k].set_instance_transform(counts[k], bx)
		counts[k] += 1
	for k in 2:
		_boat_mm[k].visible_instance_count = counts[k]
		_boat_shadow_mm[k].visible_instance_count = counts[k]

	var focus := rig.target if rig else Vector3.ZERO
	for i in _gulls.size():
		var g: Dictionary = _gulls[i]
		g.a += g.w * delta
		g.move -= delta
		if g.move <= 0.0:
			# wander off to circle somewhere else, often near where the player is looking
			g.move = _rng.randf_range(15.0, 40.0)
			var to: Vector3 = focus if _rng.randf() < 0.6 else g.c
			g.c = to + Vector3(_rng.randf_range(-14, 14), 0, _rng.randf_range(-14, 14))
			g.r = _rng.randf_range(3.0, 9.0)
		var pos: Vector3 = Vector3(cos(g.a), 0, sin(g.a)) * g.r
		g.cur = (g.get("cur", g.c) as Vector3).lerp(g.c, minf(1.0, delta * 0.15))
		var y: float = g.y + sin(t * 0.4 + g.ph) * 0.6
		var p: Vector3 = g.cur + pos + Vector3(0, y, 0)
		# tangent of the circle is the heading; bank into the turn
		var head: float = atan2(-sin(g.a) * signf(g.w), cos(g.a) * signf(g.w))
		var bank: float = -0.45 * signf(g.w)
		# glide most of the time, with short bursts of flapping
		var burst: float = smoothstep(0.55, 0.8, sin(t * 0.35 + g.ph * 3.0))
		var flap: float = maxf(0.25, 1.0 + sin(t * 11.0 + g.ph) * 1.6 * burst)
		var basis: Basis = Basis(Vector3.UP, head) * Basis(Vector3.BACK, bank)
		_gull_mm.set_instance_transform(i, Transform3D(basis * Basis.from_scale(Vector3(1.6, 1.6 * flap, 1.6)), p))
	_gull_mm.visible_instance_count = _gulls.size()
