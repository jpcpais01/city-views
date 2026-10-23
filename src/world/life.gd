class_name Life
extends Node3D
## Ambient life around the island: sailboats and fishing boats wandering the
## open water, and seagulls that soar on the breeze, flap, dive for fish, and
## come down to stand on the beach or bob on the water before taking off again.
## Every kind is one MultiMesh, so the whole lot costs three draw calls.

const BOATS := 9
const GULLS := 16
enum { SOAR, TRAVEL, LAND, PERCH, TAKEOFF, DIVE }
# the gull mesh's feet sit this far below its origin (instances are scaled 1.6)
const FEET := 0.2
const SAIL_COLORS := [Color("f7f3ea"), Color("ef7f6a"), Color("7fb8e6"), Color("f2c14e")]
const HULL_COLORS := [Color("f5f5f2"), Color("3d5f8f"), Color("c8553d"), Color("2f8f83")]

var material: Material
var rig: CameraRig
var _boat_mm: Array[MultiMesh] = []
# boxy stand-ins that draw the boats into the shadow map
var _boat_shadow_mm: Array[MultiMesh] = []
var _shadow_mesh: ArrayMesh
var gull_mat: ShaderMaterial
var _gull_mm: MultiMesh
var _boats: Array = []
var _gulls: Array = []
# where a gull may come down: empty coast tiles and calm water near the shore
var _perches: Array[Vector2i] = []
var _shallows: Array[Vector2i] = []
var _call_timer := 5.0
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
	gull_mat = ShaderMaterial.new()
	gull_mat.shader = load("res://shaders/gull.gdshader")
	_gull_mm = MultiMesh.new()
	_gull_mm.transform_format = MultiMesh.TRANSFORM_3D
	_gull_mm.use_custom_data = true
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
	# Wings, head and legs are tagged in UV.x so gull.gdshader can bend, fold and tuck them.
	var mk := MeshKit.new(13)
	var white := Color("f7f7f4")
	var grey := Color("aab3bd")
	mk.pebble(Vector3(0, 0, -0.01), Vector3(0.065, 0.058, 0.19), white)
	mk.pebble(Vector3(0, 0.04, 0.165), Vector3(0.047, 0.047, 0.056), white, 2.0)
	# hooked yellow beak as two crossed sheets
	var beak := Color("f2b33d")
	mk.tri(Vector3(-0.013, 0.03, 0.205), Vector3(0.013, 0.03, 0.205), Vector3(0, 0.024, 0.27), beak, 0.0, 0.0, Vector3.UP)
	mk.tri(Vector3(0, 0.044, 0.205), Vector3(0, 0.017, 0.205), Vector3(0, 0.022, 0.272), beak, 0.0, 0.0, Vector3.RIGHT)
	for s in [-1.0, 1.0]:
		var root_f := Vector3(0.05 * s, 0.012, 0.07)
		var root_b := Vector3(0.05 * s, 0.012, -0.09)
		var elbow_f := Vector3(0.26 * s, 0.012, 0.055)
		var elbow_b := Vector3(0.26 * s, 0.012, -0.1)
		var hand_f := Vector3(0.37 * s, 0.012, 0.035)
		var hand_b := Vector3(0.37 * s, 0.012, -0.095)
		mk.quad(root_f, elbow_f, elbow_b, root_b, Vector3.UP, grey, 1.0)
		mk.quad(elbow_f, hand_f, hand_b, elbow_b, Vector3.UP, grey, 1.0)
		mk.tri(hand_f, Vector3(0.5 * s, 0.012, -0.075), hand_b, grey, 1.0, 1.0, Vector3.UP)
		# pink legs and webbed feet, folded away in flight
		var leg := Color("e39a8c")
		mk.tri(Vector3(0.024 * s, -0.03, 0.01), Vector3(0.024 * s, -0.03, -0.025), Vector3(0.024 * s, -0.125, -0.005), leg, 3.0, 0.0, Vector3.RIGHT * s)
		mk.tri(Vector3(0.024 * s - 0.018, -0.125, 0.03), Vector3(0.024 * s + 0.018, -0.125, 0.03), Vector3(0.024 * s, -0.125, -0.012), leg, 3.0, 0.0, Vector3.UP)
	mk.quad(Vector3(-0.042, 0.008, -0.17), Vector3(0.042, 0.008, -0.17), Vector3(0.05, 0.012, -0.28), Vector3(-0.05, 0.012, -0.28), Vector3.UP, white)
	return mk.commit(gull_mat)


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
	_perches.clear()
	_shallows.clear()
	for t in coast:
		if Game.knd(t.x, t.y) == Game.K.EMPTY:
			_perches.append(t)
	for t in sea:
		if Game.shore[Game.idx(t.x, t.y)] <= 4.0:
			_shallows.append(t)
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
		_gull_step(_gulls[i], delta, t, focus)
		var g: Dictionary = _gulls[i]
		var basis: Basis = Basis(Vector3.UP, g.h) * Basis(Vector3.RIGHT, g.pitch) * Basis(Vector3.BACK, g.bank)
		# wingbeat: a slow, shallow M-shaped glide up to deep full strokes
		var fl: float = g.fl
		var beat: float = sin(g.ph)
		var shoulder: float = lerpf(0.17, 0.05, fl) + beat * lerpf(0.035, 0.9, fl)
		var outer: float = lerpf(-0.34, -0.05, fl) + fl * 0.55 * sin(g.ph - 1.1)
		var bob: float = -beat * fl * 0.035
		_gull_mm.set_instance_transform(i, Transform3D(basis.scaled_local(Vector3.ONE * 1.6), g.p + Vector3(0, bob, 0)))
		_gull_mm.set_instance_custom_data(i, Color(shoulder, g.fold, outer, g.legs))
	_gull_mm.visible_instance_count = _gulls.size()
	_gull_calls(delta, focus)


func _gull_step(g: Dictionary, delta: float, t: float, focus: Vector3) -> void:
	var p: Vector3 = g.p
	var want_h: float = g.h
	var want_y: float = g.alt
	var want_v := 2.4
	var want_fl := 0.0
	var want_fold := 0.0
	var want_legs := 0.0
	var turn_rate := 1.3
	g.time -= delta
	var to: Vector3 = g.c - p
	to.y = 0.0
	var d := to.length()
	match g.st:
		SOAR, TRAVEL:
			if g.st == TRAVEL:
				want_h = atan2(to.x, to.z)
				want_fl = 0.45 * smoothstep(0.2, 0.7, sin(t * 0.9 + g.seed))
				if d < g.r:
					g.st = SOAR
			else:
				# ride a thermal: hold the circle, drifting in from wherever we are
				var inward := to / maxf(d, 0.01)
				var tangent := Vector3(-inward.z, 0, inward.x) * float(g.dir)
				var steer := tangent + inward * clampf((d - g.r) / g.r * 1.6, -1.0, 1.0)
				want_h = atan2(steer.x, steer.z)
				want_fl = 0.4 * smoothstep(0.6, 0.85, sin(t * 0.3 + g.seed * 3.0))
			want_y = g.alt + sin(t * 0.4 + g.seed) * 0.6
			if p.y < want_y - 0.8:
				want_fl = maxf(want_fl, 0.6)
			if g.time <= 0.0:
				_gull_decide(g, focus)
		LAND, DIVE:
			var spot: Vector3 = g.spot
			to = spot - p
			to.y = 0.0
			d = to.length()
			want_h = atan2(to.x, to.z)
			turn_rate = 1.3 + 3.0 * (1.0 - smoothstep(0.5, 4.0, d))
			if g.st == LAND:
				want_y = spot.y + clampf((d - 0.3) * 0.6, 0.0, g.alt)
				want_v = lerpf(0.5, 2.4, smoothstep(0.3, 4.0, d))
				# braking wingbeats and dropped legs for the touchdown
				want_fl = 0.75 * (1.0 - smoothstep(0.6, 3.0, d))
				want_legs = 1.0 - smoothstep(1.0, 2.5, d)
				if d < 0.3 and p.y < spot.y + 0.35:
					g.st = PERCH
					g.time = _rng.randf_range(6.0, 16.0)
			else:
				want_y = g.alt
				if d < 2.0 or g.plunge:
					# plunge: wings half swept back, nose down, straight into the sea
					g.plunge = true
					want_v = 1.6
					want_fold = 0.45
					p.y -= 5.0 * delta
					want_y = p.y
					if p.y < 0.12:
						g.plunge = false
						g.st = TAKEOFF
						g.spot = Vector3(p.x, 0.06, p.z)
						g.wet = true
			if g.time <= 0.0 and g.st != PERCH:
				# gave up on the approach
				g.st = SOAR
				g.c = p
				g.time = _rng.randf_range(6.0, 14.0)
		PERCH:
			p = g.spot
			if g.wet:
				p.y += sin(t * 1.3 + g.seed) * 0.025
			if g.v > 0.4:
				g.look = g.h
			want_v = 0.0
			want_fold = 1.0
			want_legs = 1.0
			# look about now and then
			if _rng.randf() < delta * 0.4:
				g.look = g.h + _rng.randf_range(-1.2, 1.2)
			want_h = g.look
			turn_rate = 2.5
			var tile := Game.world_to_tile(p)
			var taken: bool = not g.wet and Game.knd(tile.x, tile.y) != Game.K.EMPTY
			if g.time <= 0.0 or taken:
				g.st = TAKEOFF
				if _rng.randf() < 0.4:
					g.call = true
		TAKEOFF:
			want_fl = 1.0
			want_legs = 0.3
			want_v = 2.0
			want_y = g.spot.y + 3.0
			if p.y > g.spot.y + 2.5:
				g.st = SOAR
				g.c = p + Vector3(sin(g.h), 0, cos(g.h)) * g.r
				g.time = _rng.randf_range(10.0, 30.0)
	# steer, bank into the turn, climb or sink towards the wanted height
	var dh := wrapf(want_h - g.h, -PI, PI)
	var turn := clampf(dh, -turn_rate * delta, turn_rate * delta)
	g.h += turn
	var rate := turn / maxf(delta, 0.001)
	var in_air: bool = g.st != PERCH
	g.bank = lerpf(g.bank, -clampf(rate * 0.42, -0.75, 0.75) if in_air else 0.0, minf(1.0, delta * 3.0))
	g.v = lerpf(g.v, want_v, minf(1.0, delta * (4.0 if g.st == LAND else 1.2)))
	var vy := 0.0
	if in_air:
		p += Vector3(sin(g.h), 0, cos(g.h)) * g.v * delta
		if g.st == DIVE and g.plunge:
			vy = -5.0
		else:
			vy = clampf((want_y - p.y) * 1.1, -1.6, 1.4 if g.st == TAKEOFF else 1.0)
			p.y += vy * delta
	var want_pitch := clampf(-vy * 0.22, -0.4, 0.3)
	if vy < -3.0:
		want_pitch = 1.0
	elif g.st == LAND:
		want_pitch -= 0.25 * want_legs
	elif not in_air:
		want_pitch = 0.0
	g.pitch = lerpf(g.pitch, want_pitch, minf(1.0, delta * 4.0))
	g.p = p
	g.fl = lerpf(g.fl, want_fl, minf(1.0, delta * 3.0))
	g.fold = lerpf(g.fold, want_fold, minf(1.0, delta * 3.5))
	g.legs = lerpf(g.legs, want_legs, minf(1.0, delta * 3.0))
	g.ph += delta * lerpf(4.0, 15.0, g.fl)


## Pick what a soaring gull does next: wander, come down, or go fishing.
func _gull_decide(g: Dictionary, focus: Vector3) -> void:
	var roll := _rng.randf()
	var tired: float = 0.3 + 0.4 * Sfx.night
	if roll < tired and not (_perches.is_empty() and _shallows.is_empty()):
		# come down near where the player is looking, if there is room there
		var spot := Vector3.ZERO
		var best := INF
		var on_water := _perches.is_empty() or (not _shallows.is_empty() and _rng.randf() < 0.35)
		var pool: Array[Vector2i] = _shallows if on_water else _perches
		for k in 6:
			var tile: Vector2i = pool[_rng.randi() % pool.size()]
			if not on_water and Game.knd(tile.x, tile.y) != Game.K.EMPTY:
				continue
			var c := _centre(tile)
			var score := c.distance_to(Vector3(focus.x, 0, focus.z)) + _rng.randf() * 12.0
			if score < best:
				best = score
				spot = c
		if best < INF:
			spot += Vector3(_rng.randf_range(-0.6, 0.6), 0, _rng.randf_range(-0.6, 0.6))
			var tile := Game.world_to_tile(spot)
			spot.y = 0.06 if on_water else Game.tile_y(tile.x, tile.y) + FEET
			g.st = LAND
			g.spot = spot
			g.wet = on_water
			g.time = 25.0
			return
	if roll > 0.8 and not _shallows.is_empty():
		g.st = DIVE
		var c := _centre(_shallows[_rng.randi() % _shallows.size()])
		g.spot = c + Vector3(_rng.randf_range(-0.8, 0.8), 0, _rng.randf_range(-0.8, 0.8))
		g.time = 25.0
		return
	# wander off to circle somewhere else, often near where the player is looking
	var to: Vector3 = focus if _rng.randf() < 0.6 else g.c
	g.c = Vector3(to.x, 0, to.z) + Vector3(_rng.randf_range(-14, 14), 0, _rng.randf_range(-14, 14))
	g.r = _rng.randf_range(3.0, 9.0)
	g.alt = _rng.randf_range(4.5, 9.0)
	g.st = TRAVEL
	g.time = _rng.randf_range(15.0, 40.0)


## Now and then a gull near the camera calls out; louder the closer it is.
func _gull_calls(delta: float, focus: Vector3) -> void:
	_call_timer -= delta
	var reach: float = (rig.dist if rig else 38.0) * 0.9
	for g in _gulls:
		if g.call:
			g.call = false
			var d: float = (g.p as Vector3).distance_to(focus)
			if d < reach:
				Sfx.gull(1.0 - d / reach)
	if _call_timer > 0.0:
		return
	_call_timer = _rng.randf_range(4.0, 11.0) * (1.0 + Sfx.night * 2.0)
	var best: Dictionary = {}
	var best_d := reach
	for g in _gulls:
		var d: float = (g.p as Vector3).distance_to(focus)
		if d < best_d and _rng.randf() < 0.5:
			best_d = d
			best = g
	if not best.is_empty():
		Sfx.gull(1.0 - best_d / reach)
