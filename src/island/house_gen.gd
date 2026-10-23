class_name HouseGen
extends RefCounted
## One house on one lot of the new island, in the town's painted-model style.
## Dense lots get tall terraced houses wall to wall, each its own colour; thin
## lots get detached houses with side windows, front hedges and a tree out back.
## On a slope the house stands on a stone plinth. Built in world space, as the
## raw arrays the town merges into one mesh per patch.

const FH := 0.62
const STONE := Color(0.74, 0.71, 0.66)
const TERRACE := [Color("f3c6a5"), Color("c9dbe9"), Color("f6dca7"), Color("cfe0c3"), Color("e7d3ec"), Color("fbf1df"), Color("f2b8a8"), Color("b9d4c8"), Color("fff1c4")]
const DOORS := [Color("8b5a44"), Color("4a7bb5"), Color("3d8a6a"), Color("b04a4a"), Color("2f3a48"), Color("e0b44a")]


static func build(l: Town.Lot, land: Land, street_y: float, seed_value: int) -> Array:
	var mk := MeshKit.new(seed_value)
	mk.quiet_sprites = true
	var rng := mk.rng
	var dense := l.dense > 0.6
	var right := Vector2(cos(l.yaw), -sin(l.yaw))
	var fwd := Vector2(sin(l.yaw), cos(l.yaw))
	var setback := lerpf(0.0, 0.12, rng.randf()) if dense else lerpf(0.3, 0.8, rng.randf())
	var hd := clampf(l.depth * (lerpf(0.5, 0.68, rng.randf()) if dense else lerpf(0.36, 0.52, rng.randf())), 1.3, 2.8)
	var gap := 0.0 if dense else lerpf(0.25, 0.5, rng.randf())
	var hw := maxf(l.width - gap * 2.0, 1.2)
	var cz := -setback - hd * 0.5
	# the ground under the house, from its four corners
	var lo := INF
	var hi := -INF
	for c in [Vector2(-hw * 0.5, -setback), Vector2(hw * 0.5, -setback), Vector2(hw * 0.5, -setback - hd), Vector2(-hw * 0.5, -setback - hd)]:
		var p: Vector2 = l.origin + right * c.x + fwd * c.y
		var g := land.height_at(p.x, p.y)
		lo = minf(lo, g)
		hi = maxf(hi, g)
	var y0 := maxf(street_y, (lo + hi) * 0.5 + 0.04)
	var floors: int
	if dense:
		floors = 2 + int(rng.randf() < l.dense - 0.35) + int(rng.randf() < l.dense - 0.75)
	else:
		floors = 1 + int(rng.randf() < 0.45)
	var hgt := floors * FH + 0.06
	var wall: Color = TERRACE[rng.randi() % TERRACE.size()] if dense else CityGen.WALLS[rng.randi() % CityGen.WALLS.size()]
	var roof: Color = CityGen.ROOFS[rng.randi() % CityGen.ROOFS.size()]
	var trim := wall.lightened(0.45)
	var we := 0.0
	var r := rng.randf()
	if r < 0.18:
		wall = CityGen.BRICK[rng.randi() % 3]
		we = MeshKit.BRICKS
		trim = Color(0.95, 0.93, 0.88)
	elif r < 0.3 and not dense:
		we = MeshKit.SIDING

	mk.push_at(Vector3(l.origin.x, y0, l.origin.y), l.yaw)
	# stone plinth where the ground falls away
	if y0 - lo > 0.04:
		var bottom := lo - y0 - 0.12
		mk.box(Vector3(0, bottom * 0.5 + 0.02, cz), Vector3(hw + 0.04, 0.04 - bottom, hd + 0.04), STONE.darkened(0.08 * rng.randf()))
	mk.push_at(Vector3(0, 0, cz))
	# the roof covers the top
	mk.box_faces(Vector3(0, hgt * 0.5, 0), Vector3(hw, hgt, hd), wall, MeshKit.FRONT | MeshKit.BACK | MeshKit.LEFT | MeshKit.RIGHT, we)
	mk.bands(FH + 0.03, hw, hd, FH, floors - 1, 0.035, trim)
	var count := maxi(1, int(hw / 0.55))
	var side_count := maxi(1, int(hd / 0.62))
	var door_x := (hw * 0.5 - 0.32) * (1.0 if rng.randf() < 0.5 else -1.0) if count > 1 else 0.0
	for fl in floors:
		var y := fl * FH + FH * 0.55
		if fl == 0:
			if count > 1:
				# the door takes one bay of the ground floor
				var len := hw - 0.6
				mk.window_row(Vector3(-signf(door_x) * 0.3, y, hd * 0.5), Vector3.BACK, len, count - 1, 0.24, 0.32, CityGen.GLASS, true)
		else:
			mk.window_row(Vector3(0, y, hd * 0.5), Vector3.BACK, hw, count, 0.24, 0.32, CityGen.GLASS, true)
		mk.window_row(Vector3(0, y, -hd * 0.5), Vector3.FORWARD, hw, count, 0.24, 0.32, CityGen.GLASS, true)
		if not dense and hd > 1.0:
			for sx: float in [-1.0, 1.0]:
				mk.window_row(Vector3(sx * hw * 0.5, y, 0), Vector3.RIGHT * sx, hd, side_count, 0.24, 0.32, CityGen.GLASS, true)
	# front door with a step, and on some a little canopy
	var door: Color = DOORS[rng.randi() % DOORS.size()]
	mk.box_faces(Vector3(door_x, 0.27, hd * 0.5 + 0.015), Vector3(0.3, 0.5, 0.03), door, MeshKit.FRONT | MeshKit.LEFT | MeshKit.RIGHT | MeshKit.TOP)
	mk.box_faces(Vector3(door_x, -0.02, hd * 0.5 + 0.1), Vector3(0.44, 0.07, 0.2), STONE, MeshKit.FRONT | MeshKit.TOP | MeshKit.LEFT | MeshKit.RIGHT)
	if rng.randf() < 0.4:
		mk.box_faces(Vector3(door_x, 0.58, hd * 0.5 + 0.1), Vector3(0.5, 0.04, 0.2), trim, MeshKit.FRONT | MeshKit.TOP | MeshKit.LEFT | MeshKit.RIGHT)
	_roof(mk, rng, hw, hd, hgt, roof, wall, dense)
	mk.pop()
	if not dense:
		_garden(mk, rng, l, hw, hd, setback, door_x, land, y0)
	elif l.depth - setback - hd > 1.4 and rng.randf() < 0.5:
		var tz := -setback - hd - (l.depth - setback - hd) * 0.5
		_tree(mk, rng, Vector3(lerpf(-0.4, 0.4, rng.randf()) * l.width, 0.0, tz), land, l, y0)
	mk.pop()
	return [mk.verts, mk.norms, mk.cols, mk.uvs, mk.dverts, mk.dnorms, mk.dcols, mk.duvs, mk.sverts, mk.snorms,
		mk.bverts, mk.bcols, mk.buvs, mk.bradius, mk.qverts, mk.qcols, mk.quvs, mk.qradius]


static func _roof(mk: MeshKit, rng: RandomNumberGenerator, hw: float, hd: float, hgt: float, roof: Color, wall: Color, dense: bool) -> void:
	var kind := rng.randf()
	var pitch := lerpf(0.55, 0.95, rng.randf())
	if dense and kind < 0.15:
		# flat roof behind a parapet
		mk.ledge(Vector3(0, hgt + 0.06, 0), Vector3(hw + 0.04, 0.12, hd + 0.04), 0.02, wall.lightened(0.35))
		mk.box_faces(Vector3(0, hgt + 0.1, 0), Vector3(hw - 0.1, 0.02, hd - 0.1), Color(0.55, 0.55, 0.57), MeshKit.TOP)
		return
	if kind < 0.7 or dense:
		# ridge along the street, eaves to the front
		mk.gable_roof(Vector3(0, hgt, 0), hw, hd, hd * 0.5 * pitch, 0.07, roof, wall)
	elif kind < 0.85:
		# gable end to the street
		mk.push_at(Vector3.ZERO, PI * 0.5)
		mk.gable_roof(Vector3(0, hgt, 0), hd, hw, hw * 0.5 * pitch, 0.07, roof, wall)
		mk.pop()
	else:
		mk.hip_roof(Vector3(0, hgt, 0), hw, hd, minf(hw, hd) * 0.5 * pitch, 0.08, roof)
	if rng.randf() < 0.6:
		var cx := hw * lerpf(0.2, 0.38, rng.randf()) * (1.0 if rng.randf() < 0.5 else -1.0)
		mk.box(Vector3(cx, hgt + hd * 0.5 * pitch * 0.6, -hd * 0.12), Vector3(0.16, hd * 0.5 * pitch + 0.2, 0.16), Color(0.62, 0.42, 0.36))


static func _garden(mk: MeshKit, rng: RandomNumberGenerator, l: Town.Lot, hw: float, hd: float, setback: float, door_x: float, land: Land, y0: float) -> void:
	# a low hedge or picket fence along the front, open at the path
	if setback > 0.35:
		var hedge := rng.randf() < 0.6
		var col: Color = CityGen.LEAF[rng.randi() % CityGen.LEAF.size()].darkened(0.15) if hedge else Color(0.97, 0.97, 0.95)
		var hh := 0.16 if hedge else 0.12
		var z := -0.08
		for sx: float in [-1.0, 1.0]:
			var x0 := door_x + sx * 0.25
			var x1 := sx * l.width * 0.5 - sx * 0.05
			if absf(x1 - x0) < 0.2 or signf(x1 - x0) != sx:
				continue
			# too low to throw a shadow worth drawing
			mk.shadow = false
			mk.box_faces(Vector3((x0 + x1) * 0.5, hh * 0.5, z), Vector3(absf(x1 - x0), hh, 0.1 if hedge else 0.04), col, MeshKit.TOP | MeshKit.FRONT | MeshKit.BACK)
			mk.shadow = true
		mk.box_faces(Vector3(door_x, 0.01, -setback * 0.5), Vector3(0.28, 0.02, setback), Color(0.84, 0.8, 0.74), MeshKit.TOP)
		for k in 2:
			mk.blob(Vector3(door_x + (0.5 + 0.3 * k) * (1.0 if k == 0 else -1.0), 0.1, -setback * 0.6), Vector3(0.1, 0.08, 0.1), CityGen.FLOWERS[rng.randi() % CityGen.FLOWERS.size()], 0.03)
	var back := l.depth - setback - hd
	if back > 1.0:
		_tree(mk, rng, Vector3(lerpf(-0.3, 0.3, rng.randf()) * l.width, 0.0, -setback - hd - back * 0.55), land, l, y0)


## A garden tree, standing on the real ground wherever the garden slopes to.
static func _tree(mk: MeshKit, rng: RandomNumberGenerator, at: Vector3, land: Land, l: Town.Lot, y0: float) -> void:
	var p := l.origin + Vector2(cos(l.yaw), -sin(l.yaw)) * at.x + Vector2(sin(l.yaw), cos(l.yaw)) * at.z
	at.y = land.height_at(p.x, p.y) - y0
	var s := lerpf(0.75, 1.15, rng.randf())
	mk.pole(at, 0.05 * s, 0.5 * s, 5, Color(0.45, 0.33, 0.24))
	var leaf: Color = CityGen.LEAF[rng.randi() % CityGen.LEAF.size()]
	mk.blob(at + Vector3(0, 0.75 * s, 0), Vector3(0.42, 0.4, 0.42) * s, leaf, 0.1)
	mk.blob(at + Vector3(0.18 * s, 0.98 * s, 0.05), Vector3(0.28, 0.26, 0.28) * s, leaf.lightened(0.08), 0.1)
