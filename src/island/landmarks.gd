class_name Landmarks
extends Node3D
## The island's landmarks, which come up as the town grows: a windmill on the
## highest hill once a village has formed, a wooden pier where the harbour
## quarter meets deep water, and a lighthouse on the headland that reaches
## furthest into the sea once it is a proper town, its beam sweeping the
## water at night. Where the windmill and lighthouse stand follows from the
## land itself; once standing, the town leaves room around each one.

const NEED := {"windmill": 30, "pier": 55, "lighthouse": 90}
const NAMES := {"windmill": "A windmill now turns on the hilltop", "pier": "A pier now reaches out from the harbour", "lighthouse": "A lighthouse now guards the headland"}
const ROOM := {"windmill": 1.6, "pier": 1.2, "lighthouse": 2.0}
const WHITE := Color(0.97, 0.96, 0.93)
const RED := Color("d9534f")
const STONE := Color(0.72, 0.7, 0.66)
const TIMBER := Color(0.45, 0.33, 0.24)
const PLANK := Color(0.72, 0.56, 0.38)
const PIER_LEN := 7.0

var world: IslandWorld
var beam_mat: Material
## kind -> Vector2 where it stands
var spots := {}
var _nodes := {}
var _spin: Array[MeshInstance3D] = []
var _beam: MeshInstance3D
var _check := 1.0


func _process(delta: float) -> void:
	for mi in _spin:
		if is_instance_valid(mi):
			mi.rotate_object_local(mi.get_meta("axis"), float(mi.get_meta("speed")) * delta)
	if _beam:
		_beam.visible = world.night > 0.15
	_check -= delta
	if _check > 0.0 or world.town.is_busy():
		return
	_check = 2.0
	for kind in NEED:
		var want: bool = world.progress.residents >= int(NEED[kind])
		if spots.has(kind) and (not want or not _fits(kind, spots[kind], true)):
			_remove(kind)
		if want and not spots.has(kind):
			var at: Variant = _find(kind)
			if at != null:
				_place(kind, at)
				if world.progress._hush <= 0.0:
					world.note.emit(NAMES[kind], "title")
					Sfx.play("unlock", 0.9)


## Where the lighthouse beams point, for the lit surfaces.
func beams() -> PackedVector4Array:
	var out := PackedVector4Array()
	if _beam and _beam.visible:
		var bx := _beam.global_transform.basis.x
		var o := _beam.global_position
		out.append(Vector4(o.x, o.y, o.z, atan2(bx.z, bx.x)))
	return out


func reset() -> void:
	for kind in spots.keys():
		_remove(kind)


func to_dict() -> Dictionary:
	var out := {}
	for kind in spots:
		var p: Vector2 = spots[kind]
		out[kind] = [snappedf(p.x, 0.01), snappedf(p.y, 0.01)]
	return out


## Puts back the landmarks of a saved island, before its town fills in again.
func from_dict(d: Dictionary) -> void:
	reset()
	for kind in d:
		var v: Variant = d[kind]
		if NEED.has(kind) and v is Array and v.size() == 2:
			_place(kind, Vector2(float(v[0]), float(v[1])))


# ------------------------------------------------------------------ where

## Whether `kind` can stand at `p`: the right ground, and clear of streets and
## (unless it already stands there) houses.
func _fits(kind: String, p: Vector2, standing := false) -> bool:
	var land := world.land
	var h := land.height_at(p.x, p.y)
	if kind == "pier":
		return _pier_fits(p, standing)
	if kind == "lighthouse" and (h < 0.3 or h > 6.0):
		return false
	if kind == "windmill" and h < 1.2:
		return false
	var r: float = ROOM[kind]
	for k in 8:
		var q := p + Vector2.from_angle(k * TAU / 8.0) * r
		var g := p + Vector2.from_angle(k * TAU / 8.0) * r * 0.6
		if absf(land.height_at(g.x, g.y) - h) > 0.9 or land.height_at(g.x, g.y) < 0.05:
			return false
		if not standing and world.town.is_built(q):
			return false
	if not standing and world.town.is_built(p):
		return false
	for s: Streets.Street in world.streets.streets:
		if s.near_box(p, r + 2.0) and s.closest(p).x < r + s.reach() + 0.4:
			return false
	return true


## Which way is out to sea from a spot on the shore (zero if none is).
func _seaward(p: Vector2) -> Vector2:
	var d := Vector2.ZERO
	for k in 16:
		var dir := Vector2.from_angle(k * TAU / 16.0)
		var q := p + dir * 4.0
		if world.land.height_at(q.x, q.y) < -0.3:
			d += dir
	return d.normalized()


## A pier starts on the shore just above the water and runs out into water
## deep enough for boats, clear of houses and streets.
func _pier_fits(p: Vector2, standing: bool) -> bool:
	var land := world.land
	var h := land.height_at(p.x, p.y)
	if h < 0.02 or h > 1.0:
		return false
	var d := _seaward(p)
	if d == Vector2.ZERO:
		return false
	for t in [2.5, 4.5, PIER_LEN]:
		var q: Vector2 = p + d * t
		if land.height_at(q.x, q.y) > (-0.2 if t < 3.0 else -0.7):
			return false
	var back := p - d * 1.0
	if land.height_at(back.x, back.y) < h - 0.05:
		return false
	if not standing and (world.town.is_built(p) or world.town.is_built(back)):
		return false
	for s: Streets.Street in world.streets.streets:
		if s.near_box(p, 3.0) and s.closest(p).x < s.reach() + 0.6:
			return false
	return true


## The middle of the harbour quarter (or of the whole town), where the pier should be near.
func _harbour_centre() -> Variant:
	for pass_i in 2:
		var sum := Vector2.ZERO
		var n := 0
		for l: Town.Lot in world.town.lots.values():
			if l.type == "house" and (pass_i == 1 or l.kit == HouseGen.HARBOUR):
				sum += l.origin
				n += 1
		if n > 0:
			return sum / n
	return null


func _find(kind: String) -> Variant:
	var land := world.land
	if kind == "pier":
		var c: Variant = _harbour_centre()
		if c == null:
			return null
		var best_d := INF
		var found: Variant = null
		var gx := -30.0
		while gx <= 30.0:
			var gz := -30.0
			while gz <= 30.0:
				var p: Vector2 = c + Vector2(gx, gz)
				var dd := Vector2(gx, gz).length()
				if dd < best_d and absf(p.x) < Land.HALF - 8.0 and absf(p.y) < Land.HALF - 8.0 and _pier_fits(p, false):
					best_d = dd
					found = p
				gz += 1.0
			gx += 1.0
		return found

	var best := -INF
	var at: Variant = null
	var x := -Land.HALF + 6.0
	while x < Land.HALF - 6.0:
		var z := -Land.HALF + 6.0
		while z < Land.HALF - 6.0:
			var p := Vector2(x, z)
			var h := land.height_at(x, z)
			var score := -INF
			if kind == "lighthouse" and h > 0.3 and h < 6.0:
				# how much of the view all round is open sea
				var sea := 0
				for k in 16:
					var q := p + Vector2.from_angle(k * TAU / 16.0) * 7.0
					sea += int(land.height_at(q.x, q.y) < -0.3)
				if sea >= 6:
					score = sea * 10.0 + h
			elif kind == "windmill" and h > 1.2:
				score = h
			if spots.has("lighthouse") and kind == "windmill" and p.distance_to(spots.lighthouse) < 12.0:
				score = -INF
			if score > best and _fits(kind, p):
				best = score
				at = p
			z += 2.0
		x += 2.0
	return at


# ------------------------------------------------------------------ building

func _remove(kind: String) -> void:
	var n: Node3D = _nodes.get(kind)
	if n:
		for mi in n.find_children("*", "MeshInstance3D", true, false):
			_spin.erase(mi)
			if mi == _beam:
				_beam = null
		n.queue_free()
	_nodes.erase(kind)
	spots.erase(kind)
	world.town.unreserve(kind)


func _place(kind: String, p: Vector2) -> void:
	spots[kind] = p
	world.town.reserve(kind, p, float(ROOM[kind]) + 0.6)
	var land := world.land
	if kind == "pier":
		_place_pier(p)
		return
	# stand on the lowest ground under it, the plinth hides the rest of the slope
	var y := land.height_at(p.x, p.y)
	for k in 8:
		var q := p + Vector2.from_angle(k * TAU / 8.0) * float(ROOM[kind]) * 0.6
		y = minf(y, land.height_at(q.x, q.y))
	var root := Node3D.new()
	root.position = Vector3(p.x, y, p.y)
	add_child(root)
	_nodes[kind] = root
	# face the middle of the island (the windmill's sails, the keeper's cottage)
	var yaw := atan2(-p.x, -p.y)
	var mk := MeshKit.new(hash(kind))
	mk.push_at(Vector3.ZERO, yaw)
	if kind == "lighthouse":
		_lighthouse(mk, root)
	else:
		_windmill(mk, root, yaw)
	mk.pop()
	var body := MeshInstance3D.new()
	body.mesh = mk.commit(world.city_mat)
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(body)
	var sm := mk.commit_shadow(Palette.shadow_material())
	if sm:
		var sh := MeshInstance3D.new()
		sh.mesh = sm
		sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		root.add_child(sh)


func _place_pier(p: Vector2) -> void:
	var land := world.land
	var d := _seaward(p)
	var root := Node3D.new()
	root.position = Vector3(p.x, 0.0, p.y)
	add_child(root)
	_nodes["pier"] = root
	var yaw := atan2(d.x, d.y)
	var deck := maxf(land.height_at(p.x, p.y), 0.0) + 0.22
	var side := Vector2(d.y, -d.x)
	var mk := MeshKit.new(hash("pier"))
	# local +Z runs out to sea
	mk.push_at(Vector3.ZERO, yaw)
	mk.box(Vector3(0, deck - 0.04, PIER_LEN * 0.5 - 0.6), Vector3(0.9, 0.08, PIER_LEN + 1.2), PLANK, null, false, MeshKit.SIDING)
	mk.box(Vector3(0, deck - 0.04, PIER_LEN + 0.4), Vector3(2.6, 0.08, 1.4), PLANK, null, false, MeshKit.SIDING)
	# posts down to the sea bed, a pair every metre and a half
	var z := 0.6
	while z <= PIER_LEN + 1.0:
		var wide := z > PIER_LEN - 0.3
		for sx: float in ([-1.2, 1.2] if wide else [-0.4, 0.4]):
			var w: Vector2 = p + d * z - side * sx
			var bed := minf(land.height_at(w.x, w.y), -0.1)
			mk.pole(Vector3(sx, bed, z), 0.05, deck - 0.06 - bed, 5, Color(0.42, 0.32, 0.24))
		z += 1.5
	# rails, and lamps and a bench out at the end
	for sx: float in [-1.0, 1.0]:
		mk.box(Vector3(sx * 0.43, deck + 0.22, PIER_LEN * 0.5 - 0.2), Vector3(0.03, 0.03, PIER_LEN - 0.6), WHITE)
		mk.box(Vector3(sx * 1.28, deck + 0.22, PIER_LEN + 0.4), Vector3(0.03, 0.03, 1.3), WHITE)
		var k := 0.4
		while k < PIER_LEN - 0.4:
			mk.box(Vector3(sx * 0.43, deck + 0.11, k), Vector3(0.03, 0.22, 0.03), WHITE)
			k += 1.0
		CivicGen._lamp(mk, Vector3(sx * 1.15, deck, PIER_LEN + 0.95))
	mk.box(Vector3(0, deck + 0.22, PIER_LEN + 1.08), Vector3(2.56, 0.03, 0.03), WHITE)
	CivicGen._bench(mk, Vector3(0.6, deck, PIER_LEN + 0.7), PI)
	# two anglers sit on the edge of the end, rods out over the water
	for a in [[-0.75, Color("3fae8c")], [0.45, Color("f2c14e")]]:
		_angler(mk, Vector3(a[0], deck, PIER_LEN + 1.08), a[1])
	# a striped kiosk where the pier meets the shore
	mk.rbox(Vector3(-0.75, deck + 0.22, 0.2), Vector3(0.5, 0.44, 0.44), 0.03, WHITE, null, false, MeshKit.SIDING)
	mk.window(Vector3(-0.75, deck + 0.28, 0.43), Vector3.BACK, 0.34, 0.16, Palette.GLASS_LIGHT, Color(0, 0, 0, 0), true)
	mk.cone(Vector3(-0.75, deck + 0.44, 0.2), 0.42, 0.24, 8, Color("e85d5d"))
	# rowing boats tied up alongside
	for b in [[1.1, 2.6, 0.2, Color("3d5f8f")], [-1.05, 4.6, -0.15, Color("c8553d")]]:
		mk.push_at(Vector3(b[0], 0.04, b[1]), b[2])
		mk.rbox(Vector3(0, 0.06, 0), Vector3(0.4, 0.14, 1.0), 0.07, b[3])
		mk.box(Vector3(0, 0.11, 0), Vector3(0.32, 0.03, 0.86), Color(0.86, 0.74, 0.55))
		mk.box(Vector3(0, 0.15, 0.05), Vector3(0.34, 0.03, 0.1), PLANK)
		mk.pop()
	mk.pop()
	var body := MeshInstance3D.new()
	body.mesh = mk.commit(world.city_mat)
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(body)
	var sm := mk.commit_shadow(Palette.shadow_material())
	if sm:
		var sh := MeshInstance3D.new()
		sh.mesh = sm
		sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		root.add_child(sh)


## A little figure sitting on the deck edge at `at`, legs over the water
## (local +Z), holding a rod whose line drops into the sea.
func _angler(mk: MeshKit, at: Vector3, shirt: Color) -> void:
	var pants := Color("3d4a5c")
	for sx: float in [-0.028, 0.028]:
		mk.box(at + Vector3(sx, 0.012, 0.05), Vector3(0.045, 0.045, 0.11), pants)
		mk.box(at + Vector3(sx, -0.05, 0.1), Vector3(0.04, 0.1, 0.04), pants)
	mk.rbox(at + Vector3(0, 0.09, -0.01), Vector3(0.11, 0.11, 0.07), 0.025, shirt)
	mk.blob(at + Vector3(0, 0.19, 0), Vector3(0.043, 0.045, 0.043), Color("d9a77c"))
	mk.cone(at + Vector3(0, 0.216, 0), 0.06, 0.014, 7, Color("e9d8a6"))
	mk.cylinder(at + Vector3(0, 0.229, 0), 0.035, 0.03, 6, Color("e9d8a6"))
	# the rod angles up and out; the line hangs from its tip to the water
	var butt := at + Vector3(0.05, 0.08, 0.06)
	var rod := Vector3(0.05, 0.26, 0.46)
	var up := rod.normalized()
	var x := up.cross(Vector3.BACK).normalized()
	mk.push(Transform3D(Basis(x, up, x.cross(up)), butt))
	# a real cylinder: a pole would be drawn as an upright sprite
	mk.cylinder(Vector3.ZERO, 0.008, rod.length(), 4, Color(0.2, 0.18, 0.16), false)
	mk.pop()
	var tip := butt + rod
	mk.box(Vector3(tip.x, tip.y * 0.5, tip.z), Vector3(0.006, tip.y, 0.006), Color(0.92, 0.92, 0.92))
	mk.blob(Vector3(tip.x, 0.03, tip.z), Vector3(0.025, 0.025, 0.025), Color("e85d5d"))


func _lighthouse(mk: MeshKit, root: Node3D) -> void:
	mk.rbox(Vector3(0, -0.2, 0), Vector3(1.6, 0.6, 1.6), 0.1, STONE)
	var hgt := 3.4
	var seg := 5
	for k in seg:
		var r0 := 0.5 - k * 0.05
		var r1 := 0.5 - (k + 1) * 0.05
		mk.cylinder(Vector3(0, 0.1 + k * hgt / seg, 0), r0, hgt / seg, 16, WHITE if k % 2 == 0 else RED, false, null, r1)
	var top := 0.1 + hgt
	mk.cylinder(Vector3(0, top, 0), 0.42, 0.08, 16, Color(0.25, 0.27, 0.3))
	# the gallery rail round the lantern
	for k in 12:
		var a := TAU * k / 12.0
		mk.box(Vector3(cos(a) * 0.4, top + 0.16, sin(a) * 0.4), Vector3(0.02, 0.16, 0.02), Color(0.25, 0.27, 0.3))
	mk.cylinder(Vector3(0, top + 0.08, 0), 0.24, 0.42, 12, Color(1, 0.9, 0.6), false, null, -1.0, 2.0)
	mk.cone(Vector3(0, top + 0.5, 0), 0.34, 0.36, 12, RED)
	mk.blob(Vector3(0, top + 0.9, 0), Vector3(0.06, 0.06, 0.06), Color(0.25, 0.27, 0.3))
	for k in 2:
		mk.window(Vector3(0, 1.0 + k * 1.2, 0.46 - k * 0.06), Vector3.BACK, 0.14, 0.22, Palette.GLASS, WHITE)
	mk.rbox(Vector3(0, 0.3, 0.42), Vector3(0.22, 0.4, 0.1), 0.03, Color(0.35, 0.42, 0.5))
	# the keeper's cottage on the landward side
	mk.rbox(Vector3(0, 0.35, 1.05), Vector3(0.9, 0.7, 0.7), 0.05, WHITE)
	mk.push_at(Vector3(0, 0.7, 1.05), PI * 0.5)
	mk.gable_roof(Vector3.ZERO, 0.7, 0.9, 0.34, 0.06, RED, WHITE)
	mk.pop()
	mk.window(Vector3(0.22, 0.4, 1.41), Vector3.BACK, 0.18, 0.2, Palette.GLASS, WHITE, true)
	mk.rbox(Vector3(-0.2, 0.25, 1.41), Vector3(0.18, 0.36, 0.04), 0.02, Color(0.35, 0.42, 0.5))
	mk.cylinder(Vector3(0.3, 0.9, 1.15), 0.06, 0.24, 6, Color(0.8, 0.5, 0.4))
	# the turning beam, out both sides of the lamp, only lit at night
	_beam = _spinner(root, _beam_mesh(), Vector3(0, top + 0.28, 0), Vector3.UP, 0.9)
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _windmill(mk: MeshKit, root: Node3D, yaw: float) -> void:
	mk.cylinder(Vector3(0, -0.4, 0), 0.72, 0.5, 14, STONE)
	mk.cylinder(Vector3(0, 0.1, 0), 0.62, 2.2, 14, Color(0.93, 0.9, 0.84), false, null, 0.42)
	mk.cone(Vector3(0, 2.3, 0), 0.52, 0.6, 14, Color("8b5a44"))
	mk.rbox(Vector3(0, 0.38, 0.58), Vector3(0.3, 0.56, 0.1), 0.04, Color(0.45, 0.3, 0.22))
	mk.window(Vector3(0, 1.4, 0.52), Vector3.BACK, 0.18, 0.24, Palette.GLASS, WHITE, true)
	mk.rbox(Vector3(0, 2.1, 0.5), Vector3(0.16, 0.16, 0.3), 0.04, Color(0.4, 0.3, 0.22))
	# a little railed balcony half way up, and sacks by the door
	mk.cylinder(Vector3(0, 1.05, 0), 0.66, 0.05, 14, TIMBER)
	for k in 3:
		mk.blob(Vector3(0.45 + k * 0.12, 0.08, 0.6 - k * 0.08), Vector3(0.08, 0.1, 0.08), Color(0.86, 0.78, 0.6))
	var blades := MeshKit.new()
	for k in 4:
		blades.push(Transform3D(Basis(Vector3.BACK, TAU * k / 4.0), Vector3.ZERO))
		blades.box(Vector3(0, 0.8, 0), Vector3(0.06, 1.6, 0.04), TIMBER)
		blades.box(Vector3(0.14, 0.95, 0.0), Vector3(0.24, 1.15, 0.02), Color(0.97, 0.95, 0.9))
		blades.pop()
	blades.blob(Vector3.ZERO, Vector3(0.1, 0.1, 0.1), Color(0.35, 0.27, 0.2))
	var out := Vector3(sin(yaw), 0, cos(yaw))
	var sail := _spinner(root, blades.commit(world.city_mat), out * 0.68 + Vector3(0, 2.1, 0), Vector3.BACK, 0.7)
	sail.get_parent().rotation.y = yaw
	var sh := MeshInstance3D.new()
	sh.mesh = blades.commit_shadow(Palette.shadow_material())
	sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	sail.add_child(sh)
	sail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _spinner(root: Node3D, mesh: ArrayMesh, pos: Vector3, axis: Vector3, speed: float) -> MeshInstance3D:
	var pivot := Node3D.new()
	pivot.position = pos
	root.add_child(pivot)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.set_meta("axis", axis)
	mi.set_meta("speed", speed)
	pivot.add_child(mi)
	_spin.append(mi)
	return mi


## Two soft cones out both sides of the lamp, angled down to meet the sea
## about 14 m out: a wide glow around a brighter narrow core.
func _beam_mesh() -> ArrayMesh:
	var v := PackedVector3Array()
	var nrm := PackedVector3Array()
	var c := PackedColorArray()
	var sides := 10
	var warm := Color(1, 0.92, 0.66)
	for layer in [[1.7, 0.16], [0.7, 0.32]]:
		var rad: float = layer[0]
		var alpha: float = layer[1]
		for s in [-1.0, 1.0]:
			var axis := Vector3(s * 14.0, -4.6, 0.0)
			var fwd := axis.normalized()
			var up := fwd.cross(Vector3.BACK).normalized()
			var side := fwd.cross(up).normalized()
			for i in sides:
				var a0 := TAU * i / sides
				var a1 := TAU * (i + 1) / sides
				var d0 := up * cos(a0) + side * sin(a0)
				var d1 := up * cos(a1) + side * sin(a1)
				v.append_array([Vector3.ZERO, axis + d0 * rad, axis + d1 * rad])
				nrm.append_array([(d0 + d1).normalized(), d0, d1])
				c.append_array([Color(warm, alpha), Color(warm, 0.0), Color(warm, 0.0)])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = nrm
	arrays[Mesh.ARRAY_COLOR] = c
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	m.surface_set_material(0, beam_mat)
	return m
