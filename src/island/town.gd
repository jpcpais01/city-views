class_name Town
extends Node3D
## The town's buildings. Along both sides of every street in the painted area
## the frontage is divided into lots: narrow and terraced where the town is
## dense, wider with gaps and gardens where it thins out. Lots are as deep as
## the block allows, meeting the lots of the street behind back to back, and
## stop short of junction corners and of other streets. Each lot gets a house
## that fits it and its slope. Houses are merged into one mesh per patch of
## land, remade a few at a time as the town grows.

const CELL := 0.5
const RES := 256
const PATCH := 16.0
const FRONT_GAP := 0.06
# how deep the strip along a street is that only its own lots may use
const FRONTAGE := 2.6
const MAX_DEPTH := 6.0
const MIN_DEPTH := 2.4
const FH := 0.62

## The ground was levelled for new houses.
signal reshaped

var land: Land
var streets: Streets
var material: Material
var lots := {}
var _next_id := 1
# what fills each cell of the town map: 0 nothing, > 0 a lot, < 0 a street (-id)
var _occ := PackedInt32Array()
# the strip of land along each street that its own lots front onto: the
# nearest street's id per cell (0 none), and how far that street is
var _front := PackedInt32Array()
var _front_d := PackedFloat32Array()
# streets whose sides still need lots: id -> Street
var _todo := {}
# the street being laid out now: {s, side, f}
var _job := {}
# streets just laid, still to be marked on the town map
var _new_streets: Array = []
var _patches := {}
var _dirty_patches := {}


class Lot:
	var id := 0
	var street := 0
	var side := 1.0
	var quad := PackedVector2Array()
	var origin := Vector2.ZERO
	var yaw := 0.0
	var width := 0.0
	var depth := 0.0
	var dense := 0.0
	## the style kit of its quarter (HouseGen.KITS)
	var kit := 0
	## house, park, square or church
	var type := "house"
	## floors and a shop on the ground floor, for houses
	var floors := 0
	var shop := false
	var patch := Vector2i.ZERO
	var arrays: Array = []
	var cells := PackedInt32Array()


func setup(l: Land, st: Streets, mat: Material) -> void:
	land = l
	streets = st
	material = mat
	_occ.resize(RES * RES)
	_front.resize(RES * RES)
	_front_d.resize(RES * RES)
	_front_d.fill(INF)
	streets.added.connect(_on_added)
	streets.removed.connect(_on_removed)


func clear() -> void:
	for id in lots.keys():
		_drop(lots[id])
	_occ.fill(0)
	_front.fill(0)
	_front_d.fill(INF)
	_todo.clear()
	_job = {}
	_new_streets.clear()


## The player painted or wiped the growing area around `c`.
func zone_changed(c: Vector2, r: float) -> void:
	for id in lots.keys():
		var l: Lot = lots[id]
		if l.origin.distance_to(c) < r + 4.0 and (_zone(l) < 0.25 or (_green(l) > 0.5) != (l.type == "park")):
			_drop(l)
	for s: Streets.Street in streets.streets:
		if s.near_box(c, r + 4.0):
			_todo[s.id] = s


## Whether anything stands at p: a lot, a street or its pavement.
func is_built(p: Vector2) -> bool:
	var c := _cell(p)
	if c.x < 0 or c.y < 0 or c.x >= RES or c.y >= RES:
		return false
	return _occ[c.y * RES + c.x] != 0


func house_count() -> int:
	return lots.size()


func _on_added(s: Streets.Street) -> void:
	# done on a later frame, so laying a street stays quick
	_new_streets.append(s)


func _place_street(s: Streets.Street) -> void:
	if not s in streets.streets:
		return
	_mark_street(s)
	# lots the new street runs through make way for it
	for id in lots.keys():
		var l: Lot = lots[id]
		if s.near_box(l.origin, MAX_DEPTH + 3.0) and _hits(s, l):
			_drop(l)
	_todo[s.id] = s
	for o in streets._touching(s):
		_todo[o.id] = o


func _on_removed(s: Streets.Street) -> void:
	for id in lots.keys():
		if lots[id].street == s.id:
			_drop(lots[id])
	for k in _occ.size():
		if _occ[k] == -s.id:
			_occ[k] = 0
		if _front[k] == s.id:
			_front[k] = 0
			_front_d[k] = INF
	# streets that crossed it may have lost cells they share with it, and gain room
	for o in streets._touching(s):
		_mark_street(o)
		_todo[o.id] = o


func _hits(s: Streets.Street, l: Lot) -> bool:
	for p in l.quad:
		if s.closest(p).x < s.reach() + FRONT_GAP:
			return true
	for p in s.pts:
		if Geometry2D.is_point_in_polygon(p, l.quad):
			return true
	return false


func _drop(l: Lot) -> void:
	for k in l.cells:
		if _occ[k] == l.id:
			_occ[k] = 0
	lots.erase(l.id)
	_dirty_patches[l.patch] = true


# ------------------------------------------------------------------ town map

static func _cell(p: Vector2) -> Vector2i:
	return Vector2i(int(floor((p.x + Land.HALF) / CELL)), int(floor((p.y + Land.HALF) / CELL)))


## Marks the street's carriageway and pavements on the town map, and the
## strip beside them its houses front onto.
func _mark_street(s: Streets.Street) -> void:
	var r := s.reach() + FRONT_GAP - 0.02
	var rf := s.reach() + FRONTAGE
	const STEP := CELL * 0.7
	const RUN := 4
	var n := s.pts.size()
	var i := 0
	while i < n - 1:
		# the band of cells beside a short run of the street, a little past each
		# end so bends leave no gaps; distances are to the street itself
		var j := mini(i + RUN, n - 1)
		var a := s.pts[i]
		var t := (s.pts[j] - a).normalized()
		var nrm := Vector2(-t.y, t.x)
		var len := a.distance_to(s.pts[j])
		var u := -CELL
		while u <= len + CELL:
			var v := -rf
			while v <= rf:
				var c := _cell(a + t * u + nrm * v)
				v += STEP
				if c.x < 0 or c.y < 0 or c.x >= RES or c.y >= RES:
					continue
				var k := c.y * RES + c.x
				var p := Vector2((c.x + 0.5) * CELL - Land.HALF, (c.y + 0.5) * CELL - Land.HALF)
				var d := INF
				for m in range(i, j):
					d = minf(d, Geometry2D.get_closest_point_to_segment(p, s.pts[m], s.pts[m + 1]).distance_squared_to(p))
				d = sqrt(d)
				if d < rf and d - s.reach() < _front_d[k]:
					_front[k] = s.id
					_front_d[k] = d - s.reach()
				if d < r and _occ[k] >= 0:
					_occ[k] = -s.id
			u += STEP
		i = j


## The cells inside a lot's outline, or empty if any of them is taken.
func _free_cells(quad: PackedVector2Array, owner: int, inward: Vector2) -> PackedInt32Array:
	var lo := quad[0]
	var hi := quad[0]
	for p in quad:
		lo = lo.min(p)
		hi = hi.max(p)
	var c0 := _cell(lo)
	var c1 := _cell(hi)
	var out := PackedInt32Array()
	if c0.x < 0 or c0.y < 0 or c1.x >= RES or c1.y >= RES:
		return out
	for cz in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			var p := Vector2((cx + 0.5) * CELL - Land.HALF, (cz + 0.5) * CELL - Land.HALF)
			if not Geometry2D.is_point_in_polygon(p, quad):
				continue
			var k := cz * RES + cx
			# a lot may not reach into another street's frontage
			# a lot may reach into another street's frontage only within its own (on a corner)
			if _occ[k] != 0 or (_front[k] != 0 and _front[k] != owner and (p - quad[0]).dot(inward) > FRONTAGE):
				return PackedInt32Array()
			out.append(k)
	return out


# ------------------------------------------------------------------ laying out lots

func _process(_delta: float) -> void:
	var start := Time.get_ticks_usec()
	if not _new_streets.is_empty():
		_place_street(_new_streets.pop_front())
		return
	# a street's lots are laid a few at a time, so a long street never stalls a frame
	while Time.get_ticks_usec() - start < 2500:
		if _job.is_empty():
			_job = _next_job()
			if _job.is_empty():
				break
		if _step(_job, start + 2500):
			_job = {}
	for c in _dirty_patches.keys():
		if Time.get_ticks_usec() - start > 3000:
			break
		_dirty_patches.erase(c)
		_commit_patch(c)


func _next_job() -> Dictionary:
	for id in _todo.keys():
		var s: Streets.Street = _todo[id]
		if not s in streets.streets:
			_todo.erase(id)
			continue
		# wait until the street has its final shape (junction corners and all)
		if streets.is_settling(s):
			continue
		_todo.erase(id)
		return {"s": s, "side": 0, "f": 1.0}
	return {}


## Still laying out lots or building houses.
func is_busy() -> bool:
	return not _new_streets.is_empty() or not _job.is_empty() or not _todo.is_empty() or not _dirty_patches.is_empty()


## Lays lots down both sides of a street wherever there is room.
func fill_all() -> void:
	for s: Streets.Street in _new_streets:
		_place_street(s)
	_new_streets.clear()
	for s: Streets.Street in streets.streets:
		_fill(s)
	_todo.clear()
	_job = {}
	for c in _dirty_patches.keys():
		_commit_patch(c)
	_dirty_patches.clear()


func _fill(s: Streets.Street) -> void:
	var job := {"s": s, "side": 0, "f": 1.0}
	while not _step(job, -1):
		pass


## Lays lots along a street from where the job left off; true once both sides are done.
## Stops early (false) when the clock passes `until` (in usec; -1 runs to the end).
func _step(job: Dictionary, until: int) -> bool:
	var s: Streets.Street = job.s
	if not s in streets.streets:
		return true
	var n := s.pts.size()
	var off := s.reach() + FRONT_GAP
	while job.side < 2:
		var side := -1.0 if job.side == 0 else 1.0
		var cuts: PackedVector2Array = s.cuts.get(side, PackedVector2Array())
		var f: float = job.f
		while f < n - 2.0:
			if until >= 0 and Time.get_ticks_usec() > until:
				job.f = f
				return false
			var p := streets._ptf(s, f)
			var dense := _density(s, p)
			if land.zone_at(p.x, p.y) < 0.3:
				f += 1.0
				continue
			var h := _hash(s.id, f, side)
			var kind := _kind_at(s, f, p, side, dense)
			var lot: Lot = null
			var f1 := f
			for attempt in 2:
				# terraced rows are narrow; detached houses take wider plots
				var width := lerpf(1.7, 2.4, h) if dense > 0.6 else lerpf(2.2, 3.2, h)
				if kind == "square":
					width = 6.0
				elif kind == "church":
					width = 4.4
				f1 = f + width / Streets.SAMPLE
				var blocked := f1 > n - 1.5
				for c in cuts:
					if f1 > c.x - 0.6 and f < c.y + 0.6:
						blocked = true
				if not blocked:
					lot = _try_lot(s, f, f1, side, off, dense, kind)
				# no room for something grand here: a plain lot instead
				if lot or kind == "house" or kind == "park":
					break
				kind = "house"
			if f1 > n - 1.5 and not lot:
				break
			var cut_end := -1.0
			for c in cuts:
				if f1 > c.x - 0.6 and f < c.y + 0.6:
					cut_end = c.y + 0.6
			if not lot and cut_end > 0.0:
				f = maxf(cut_end, f + 1.0)
				continue
			if lot:
				f = f1 + (0.0 if dense > 0.6 or kind == "park" else lerpf(0.4, 1.2, _hash(s.id, f, side * 3.0)))
			else:
				f += 1.0
		job.side += 1
		job.f = 1.0
	return true


## What a new lot here should hold: green where the player painted parks, now
## and then a square on a busy main street or a church, spaced well apart.
func _kind_at(s: Streets.Street, f: float, p: Vector2, side: float, dense: float) -> String:
	var q := p + streets._sidef(s, f) * side * (s.reach() + 2.5)
	if land.green_at(q.x, q.y) > 0.5:
		return "park"
	var h := _hash(s.id, f, side * 7.0)
	if s.kind == "main" and dense > 0.7 and h < 0.25 and _civic_near(q, "square", 48.0) == null:
		return "square"
	if dense > 0.5 and h > 0.88 and _civic_near(q, "church", 60.0) == null and _civic_near(q, "square", 14.0) == null:
		return "church"
	return "house"


func _civic_near(p: Vector2, type: String, r: float) -> Variant:
	for l: Lot in lots.values():
		if l.type == type and l.origin.distance_to(p) < r:
			return l
	return null


func _try_lot(s: Streets.Street, f0: float, f1: float, side: float, off: float, dense: float, kind := "house") -> Lot:
	var a := streets._ptf(s, f0) + streets._sidef(s, f0) * side * off
	var b := streets._ptf(s, f1) + streets._sidef(s, f1) * side * off
	var fm := (f0 + f1) * 0.5
	var inward := streets._sidef(s, fm) * side
	# side lines square to the street, so neighbouring lots share them exactly
	var na := streets._sidef(s, f0) * side
	var nb := streets._sidef(s, f1) * side
	var depth := MAX_DEPTH if s.kind == "main" else MAX_DEPTH - 0.8
	# share the block with the street behind: lots meet back to back halfway
	var front_mid := (a + b) * 0.5
	var t := 0.5
	while t < depth * 2.0 + 0.5:
		var c := _cell(front_mid + inward * t)
		if c.x < 0 or c.y < 0 or c.x >= RES or c.y >= RES or _occ[c.y * RES + c.x] < 0:
			depth = minf(depth, snappedf(t * 0.5 - 0.1, 0.5))
			break
		t += 0.25
	var least := MIN_DEPTH
	if kind == "church":
		least = 4.5
	elif kind == "square":
		least = 3.5
	while depth >= least:
		var quad := PackedVector2Array([a, b, b + nb * depth, a + na * depth])
		var cells := _free_cells(quad, s.id, inward)
		if not cells.is_empty() and _ground_ok(quad):
			var l := Lot.new()
			l.id = _next_id
			_next_id += 1
			l.street = s.id
			l.side = side
			l.quad = quad
			l.origin = (a + b) * 0.5
			# local +Z faces the street
			l.yaw = atan2(-inward.x, -inward.y)
			l.width = minf(a.distance_to(b), quad[2].distance_to(quad[3]) * 0.5 + a.distance_to(b) * 0.5)
			l.depth = depth
			l.dense = dense
			l.cells = cells
			for k in cells:
				_occ[k] = l.id
			l.patch = Vector2i(int(floor((l.origin.x + Land.HALF) / PATCH)), int(floor((l.origin.y + Land.HALF) / PATCH)))
			lots[l.id] = l
			var street_y := streets._yf(s, fm) + 0.03 + Streets.CURB
			# terrace the front of the plot, where the house stands, near the street's level
			var mid := (a + b) * 0.5 + inward * minf(depth * 0.35, 2.0)
			var level := clampf(land.height_at(mid.x, mid.y), street_y - 0.02, street_y + 0.45)
			l.type = kind
			# squares and churches stand on a level plot all the way back; parks keep their slopes
			var front := depth if kind == "square" or kind == "church" else minf(depth * 0.72, 4.2)
			if kind != "park":
				land.pad(PackedVector2Array([a, b, b + nb * front, a + na * front]), level, 1.4, _near_street)
			l.kit = HouseGen.kit_at(land, l.origin)
			# seeded by place, so the same lot always grows the same house
			var sd := int(floor(l.origin.x * 8.0)) * 73856093 ^ int(floor(l.origin.y * 8.0)) * 19349663
			if kind == "house":
				l.arrays = HouseGen.build(l, land, street_y, sd, s.kind == "main")
			else:
				l.arrays = CivicGen.build(l, land, street_y, sd)
			reshaped.emit()
			_dirty_patches[l.patch] = true
			return l
		depth -= 0.5
	return null


## Whether a ground point is on or right beside a street (levelling keeps off it).
func _near_street(p: Vector2) -> bool:
	var c := _cell(p)
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			var x := c.x + dx
			var z := c.y + dz
			if x >= 0 and z >= 0 and x < RES and z < RES and _occ[z * RES + x] < 0:
				return true
	return false


func _ground_ok(quad: PackedVector2Array) -> bool:
	var lo := INF
	var hi := -INF
	for p in quad:
		var h := land.height_at(p.x, p.y)
		lo = minf(lo, h)
		hi = maxf(hi, h)
	return lo > 0.2 and hi - lo < 3.2


func _green(l: Lot) -> float:
	var c := (l.quad[0] + l.quad[1]) * 0.5 + (l.quad[3] - l.quad[0]).normalized() * 2.5
	return land.green_at(c.x, c.y)


func _zone(l: Lot) -> float:
	var c := (l.quad[0] + l.quad[2]) * 0.5
	return land.zone_at(c.x, c.y)


## How built-up the town wants to be here: along main streets and where the
## player has painted thickly, rows of tall terraces; elsewhere, houses apart.
func _density(s: Streets.Street, p: Vector2) -> float:
	var d := clampf((land.zone_at(p.x, p.y) - 0.3) / 0.7, 0.0, 1.0) * 0.6
	if s.kind == "main":
		d += 0.35
	d += (_wobble(p) - 0.5) * 0.3
	return clampf(d, 0.0, 1.0)


static func _wobble(p: Vector2) -> float:
	return 0.5 + 0.5 * sin(p.x * 0.13 + 1.7) * sin(p.y * 0.11 - 0.6)


static func _hash(a: int, f: float, b: float) -> float:
	return fposmod(sin(a * 12.9898 + f * 78.233 + b * 37.719) * 43758.5453, 1.0)


# ------------------------------------------------------------------ meshes

func _commit_patch(c: Vector2i) -> void:
	var sets: Array = []
	for i in 18:
		sets.append(null)
	for id in lots:
		var l: Lot = lots[id]
		if l.patch != c or l.arrays.is_empty():
			continue
		for i in 18:
			if sets[i] == null:
				sets[i] = l.arrays[i].duplicate()
			else:
				sets[i].append_array(l.arrays[i])
	var node: Node3D = _patches.get(c)
	if node:
		node.queue_free()
		_patches.erase(c)
	if sets[0] == null:
		return
	node = Node3D.new()
	add_child(node)
	_patches[c] = node
	var mesh := ArrayMesh.new()
	for k in [0, 4]:
		var v: PackedVector3Array = sets[k]
		if v.is_empty():
			continue
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = sets[k + 1]
		arr[Mesh.ARRAY_COLOR] = sets[k + 2]
		arr[Mesh.ARRAY_TEX_UV] = sets[k + 3]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		mesh.surface_set_material(mesh.get_surface_count() - 1, material if k == 0 else MeshKit.detail_material)
	var body := MeshInstance3D.new()
	body.mesh = mesh
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(body)
	if not (sets[8] as PackedVector3Array).is_empty():
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = sets[8]
		arr[Mesh.ARRAY_NORMAL] = sets[9]
		var sm := ArrayMesh.new()
		sm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		sm.surface_set_material(0, CityGen.shadow_material())
		var sh := MeshInstance3D.new()
		sh.mesh = sm
		sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		node.add_child(sh)
	for k in [10, 14]:
		var v: PackedVector3Array = sets[k]
		if v.is_empty():
			continue
		var bm := ArrayMesh.new()
		bm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, MeshKit.blob_arrays(v, sets[k + 1], sets[k + 2], sets[k + 3]))
		bm.surface_set_material(0, MeshKit.blob_material())
		bm.custom_aabb = MeshKit._blob_aabb(v, sets[k + 3])
		var bl := MeshInstance3D.new()
		bl.mesh = bm
		if k == 14:
			bl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(bl)
