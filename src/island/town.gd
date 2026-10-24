class_name Town
extends Node3D
## The town's buildings. Along both sides of every street in the painted area
## the frontage is divided into lots: narrow and terraced where the town is
## dense, wider with gaps and gardens where it thins out. Lots are as deep as
## the block allows, meeting the lots of the street behind back to back, and
## stop short of junction corners and of other streets. Each lot gets a house
## that fits it and its slope. Houses are merged into one mesh per patch of
## land, remade a few at a time as the town grows.
##
## Houses evolve. Each plot has a cap, the stage it may grow to: about the
## level painted there with the Grow brush, give or take a little, a touch
## higher on main streets. Every house starts as a cottage and, every so
## often, climbs a stage (a two-floor house, a terrace, a taller terrace with
## shops below, a tall town house) until it reaches its cap. A house only
## outgrows its neighbours by a little, so the town grows up from its busy
## streets outwards, and a cottage left behind among tall houses catches up.
##
## In a city or a centre, neighbouring plots that have grown tall join up:
## two to four of them become one wider, taller building over all their
## plots, shaped by them, the way a town's old plots fill with blocks.

const CELL := 0.5
const RES := 256
const PATCH := 16.0
const FRONT_GAP := 0.06
# how deep the strip along a street is that only its own lots may use
const FRONTAGE := 2.6
const MAX_DEPTH := 6.0
## how deep a plot must be across the middle of its frontage; its ends may taper
const MIN_DEPTH := 1.8
const FH := 0.62
## how built-up each stage is (terraced from stage 2 up)
const STAGE_DENSE := [0.3, 0.45, 0.72, 0.86, 1.0]
const STAGE_NAMES := ["cottage", "house", "townhouse", "terrace", "tall terrace"]
# seconds between a house's stages, before its own variation
const EVOLVE_TIME := 14.0
const NEIGHBOURS := 10.0

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
# ground kept for landmarks: key -> [centre, radius]; marked RESERVED on the map
var _reserved := {}
const RESERVED := -(1 << 30)
var _dirty_patches := {}
# the town's own clock, for when houses next grow
var _clock := 0.0
var _evolve_wait := 0.0
# stages that houses already had (from a save, or before an undo rebuilt the
# town), by plot position: they come back at that stage
var _kept_stages := {}


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
	## the stage the house may grow to, and the stage it has reached (0 cottage .. 4)
	var cap := 0
	## where the cap was read (from the painted level)
	var capq := Vector2.ZERO
	var stage := 0
	var next_up := 0.0
	var street_y := 0.0
	var main := false
	var sd := 0
	var patch := Vector2i.ZERO
	var arrays: Array = []
	var cells := PackedInt32Array()
	## a taller building spanning this plot and its neighbours: the first
	## plot's id on the others, and on the first the plots it spans, in order
	var host := 0
	var group: Array = []
	## set back inside the block, near a street but not on it
	var inner := false
	## which side of the plot (-1 left, +1 right in its own frame) runs along
	## another street, on a corner; 0 if neither
	var corner := 0.0
	## the back of the plot in its own frame, left to right: (x along the
	## street, z going in from it, negative), as deep as the block allows
	var back := PackedVector2Array()

	## How deep the plot is at x across the frontage.
	func depth_at(x: float) -> float:
		if back.size() < 2:
			return depth
		if x <= back[0].x:
			return -back[0].y
		for k in back.size() - 1:
			if x <= back[k + 1].x:
				if back[k + 1].x - back[k].x < 0.001:
					return -back[k + 1].y
				return -lerpf(back[k].y, back[k + 1].y, inverse_lerp(back[k].x, back[k + 1].x, x))
		return -back[back.size() - 1].y

	## The plot's shallowest depth anywhere between x0 and x1.
	func room(x0: float, x1: float) -> float:
		var d := minf(depth_at(x0), depth_at(x1))
		for p in back:
			if p.x > x0 and p.x < x1:
				d = minf(d, -p.y)
		return d


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
	# a town rebuilt from the same streets (after an undo) keeps how far its houses had grown
	_kept_stages.merge(stages(), true)
	for l: Lot in lots.values():
		l.host = 0
		l.group = []
	for id in lots.keys():
		_drop(lots[id])
	_occ.fill(0)
	_front.fill(0)
	_front_d.fill(INF)
	for key in _reserved:
		_mark_reserved(_reserved[key][0], _reserved[key][1], true)
	_todo.clear()
	_job = {}
	_new_streets.clear()


## Keeps the ground within `r` of `p` free of houses, for a landmark.
func reserve(key: String, p: Vector2, r: float) -> void:
	_reserved[key] = [p, r]
	_mark_reserved(p, r, true)


func unreserve(key: String) -> void:
	if not _reserved.has(key):
		return
	var e: Array = _reserved[key]
	_reserved.erase(key)
	_mark_reserved(e[0], e[1], false)
	for k in _reserved:
		_mark_reserved(_reserved[k][0], _reserved[k][1], true)


func _mark_reserved(p: Vector2, r: float, on: bool) -> void:
	var c0 := _cell(p - Vector2(r, r))
	var c1 := _cell(p + Vector2(r, r))
	for cz in range(maxi(c0.y, 0), mini(c1.y + 1, RES)):
		for cx in range(maxi(c0.x, 0), mini(c1.x + 1, RES)):
			var q := Vector2((cx + 0.5) * CELL - Land.HALF, (cz + 0.5) * CELL - Land.HALF)
			if q.distance_to(p) > r:
				continue
			var k := cz * RES + cx
			if on and _occ[k] == 0:
				_occ[k] = RESERVED
			elif not on and _occ[k] == RESERVED:
				_occ[k] = 0


## The player painted or wiped the growing area around `c`.
func zone_changed(c: Vector2, r: float) -> void:
	for id in lots.keys():
		var l: Lot = lots[id]
		if l.origin.distance_to(c) < r + 4.0 and (_zone(l) < 0.25 or (_green(l) > 0.5) != (l.type == "park")):
			_drop(l)
	for s: Streets.Street in streets.streets:
		if s.near_box(c, r + 4.0):
			_todo[s.id] = s
	# a repainted level moves the caps of the houses under the brush
	for l: Lot in lots.values():
		if l.type == "house" and l.origin.distance_to(c) < r + 2.0:
			var s: Streets.Street = streets.by_id(l.street)
			if s:
				var cap := _cap_at(s, l.capq, l.side)
				if cap != l.cap:
					l.cap = cap
					if l.stage > cap:
						_set_stage(l, cap)


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
	_split(l)


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

func _process(delta: float) -> void:
	_clock += delta
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
	_evolve_wait -= delta
	if _evolve_wait <= 0.0 and _job.is_empty() and _new_streets.is_empty() and _dirty_patches.is_empty():
		_evolve_wait = 0.2
		_evolve_one()


# ------------------------------------------------------------------ evolving

## Grows the one house most overdue to climb a stage, if any is ready.
func _evolve_one() -> void:
	var best: Lot = null
	for l: Lot in lots.values():
		if l.type == "house" and l.stage < l.cap and l.next_up <= _clock and (best == null or l.next_up < best.next_up):
			best = l
	if best == null:
		return
	var around := _neighbours(best)
	# never more than a little taller than the houses around it
	if around.y >= 3.0 and best.stage > around.x + 0.75:
		best.next_up = _clock + _delay(best, around)
		return
	_set_stage(best, best.stage + 1)
	best.next_up = _clock + _delay(best, around)


## The average stage of the houses near a lot (x) and how many there are (y).
func _neighbours(l: Lot) -> Vector2:
	var sum := 0.0
	var n := 0
	for o: Lot in lots.values():
		if o != l and o.type == "house" and o.origin.distance_squared_to(l.origin) < NEIGHBOURS * NEIGHBOURS:
			sum += o.stage
			n += 1
	return Vector2(sum / n if n > 0 else 0.0, n)


## How long a house waits before its next stage: longer as it gets bigger,
## shorter on main streets and where it has fallen behind its neighbours.
func _delay(l: Lot, around: Vector2) -> float:
	var t := EVOLVE_TIME * lerpf(0.6, 1.6, _hash(l.id, l.stage, 3.3)) * (1.0 + l.stage * 0.4)
	if l.main:
		t *= 0.7
	if around.y >= 3.0 and around.x > l.stage + 1.2:
		t *= 0.35
	return t


func _set_stage(l: Lot, stage: int) -> void:
	l.stage = clampi(stage, 0, l.cap)
	if l.stage < MERGE_STAGE:
		_split(l)
	elif not _try_merge(l):
		# it may be the one its taller neighbour ahead was waiting for
		var after := _next_to(l, 1)
		if after and after.host == 0 and after.group.is_empty() and after.stage >= MERGE_STAGE:
			_try_merge(after)
	_rebuild(l.host if l.host != 0 else l.id)


# ------------------------------------------------------------------ joined buildings

const MERGE_STAGE := 3
const MERGE_MAX := 4
const MERGE_WIDTH := 10.0


## Remakes a plot's building: a house, or the joined building it hosts.
func _rebuild(id: int) -> void:
	var l: Lot = lots.get(id)
	if l == null:
		return
	if l.group.size() > 1:
		var members: Array = []
		for m in l.group:
			if lots.has(m):
				members.append(lots[m])
		l.arrays = HouseGen.build_block(members, land, l.street_y, l.sd, l.main)
		for m: Lot in members:
			if m != l:
				m.arrays = []
				_dirty_patches[m.patch] = true
	else:
		l.arrays = HouseGen.build(l, land, l.street_y, l.sd, l.main)
	_dirty_patches[l.patch] = true
	reshaped.emit()


## The plot next along the same side of the same street, before (-1) or after
## (+1) this one, if they share a side line.
func _next_to(l: Lot, dirn: int) -> Lot:
	var mine := l.quad[0] if dirn < 0 else l.quad[1]
	for o: Lot in lots.values():
		if o != l and o.street == l.street and o.side == l.side and o.type == "house":
			var theirs := o.quad[1] if dirn < 0 else o.quad[0]
			if theirs.distance_to(mine) < 0.35:
				return o
	return null


## Joins a tall house onto the building of the tall house before it, now and
## then (more often in a centre), up to four plots and ten metres wide.
func _try_merge(l: Lot) -> bool:
	if l.host != 0 or not l.group.is_empty() or l.stage < MERGE_STAGE:
		return false
	var p := _next_to(l, -1)
	if p == null or p.stage < MERGE_STAGE:
		return false
	var h: Lot = lots.get(p.host) if p.host != 0 else p
	if h == null:
		return false
	var group: Array = h.group if not h.group.is_empty() else [h.id]
	if group.size() >= MERGE_MAX or group[group.size() - 1] != p.id:
		return false
	var width := l.width
	for m in group:
		width += lots[m].width if lots.has(m) else 0.0
	if width > MERGE_WIDTH:
		return false
	# chance by place, so the same plots join up after a reload
	var odds := 0.55 if mini(l.stage, p.stage) < 4 else 0.8
	if _hash(roundi(l.origin.x * 10.0), l.origin.y, 9.1) > odds:
		return false
	group.append(l.id)
	h.group = group
	l.host = h.id
	_rebuild(h.id)
	return true


## Takes a plot out of the joined building it is part of; the rest stand as
## houses again (and may join up afresh).
func _split(l: Lot) -> void:
	var h: Lot = lots.get(l.host) if l.host != 0 else (l if not l.group.is_empty() else null)
	if h == null:
		l.host = 0
		return
	var members: Array = h.group.duplicate()
	h.group = []
	for m in members:
		var o: Lot = lots.get(m)
		if o == null:
			continue
		o.host = 0
		if o != l:
			_rebuild(o.id)
	for m in members:
		var o: Lot = lots.get(m)
		if o and o != l and o.stage >= MERGE_STAGE:
			_try_merge(o)


## Every house straight to its cap (tests, and a town shown fully grown).
func evolve_all() -> void:
	for l: Lot in lots.values():
		if l.type == "house" and l.stage != l.cap:
			_set_stage(l, l.cap)
	for c in _dirty_patches.keys():
		_commit_patch(c)
	_dirty_patches.clear()


## How far each house has grown, by plot, for saving.
func stages() -> Dictionary:
	var out := {}
	for l: Lot in lots.values():
		if l.type == "house" and l.stage > 0:
			out[_plot_key(l.origin)] = l.stage
	return out


## Houses come back at these stages as their plots are laid out again.
func keep_stages(d: Dictionary) -> void:
	_kept_stages = d.duplicate()


## How far the house on the plot at p had grown before, if one stood there:
## the same spot, or near enough, since plots can shift a little when the
## ground they were levelled on comes back from a save.
func _take_kept(p: Vector2, width: float) -> int:
	if _kept_stages.is_empty():
		return 0
	var key := _plot_key(p)
	if not _kept_stages.has(key):
		key = ""
		var best := minf(width * 0.5, 1.2)
		for k: String in _kept_stages:
			var xz := k.split("_")
			var d := p.distance_to(Vector2(float(xz[0]) * 0.1, float(xz[1]) * 0.1))
			if d < best:
				best = d
				key = k
		if key == "":
			return 0
	var stage := int(_kept_stages[key])
	_kept_stages.erase(key)
	return stage


static func _plot_key(p: Vector2) -> String:
	return "%d_%d" % [roundi(p.x * 10.0), roundi(p.y * 10.0)]


## The stage a plot may grow to: the painted level, give or take a little,
## and a touch higher on a main street.
func _cap_at(s: Streets.Street, p: Vector2, side: float) -> int:
	var lv := land.level_at(p.x, p.y)
	var j := (_hash(roundi(p.x * 7.0), p.y, side * 5.0) - 0.5) * 1.3 + (_wobble(p) - 0.5) * 0.4
	if s.kind == "main":
		j += 0.35
	return clampi(roundi(lv - 0.45 + j), 0, 4)


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
			# plots are laid out for what they may grow into
			var q := p + streets._sidef(s, f) * side * (s.reach() + 1.5)
			var cap := _cap_at(s, q, side)
			var dense: float = STAGE_DENSE[cap]
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
					lot = _try_lot(s, f, f1, side, off, dense, kind, cap)
					if lot:
						lot.capq = q
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
	_inner(s)
	return true


# ------------------------------------------------------------------ inside the blocks

## How far inside a block a cottage or a pocket park may stand from its street.
const INNER_REACH := 13.0


## Fills ground left free deep inside the blocks along a street, behind its
## plots and within a short walk of it: a pocket park where the player
## painted green, otherwise now and then a cottage, the way back lanes and
## courtyards fill in an old town.
func _inner(s: Streets.Street) -> void:
	var n := s.pts.size()
	var f := 2.0
	while f < n - 2.0:
		var p := streets._ptf(s, f)
		for side: float in [-1.0, 1.0]:
			var nrm := streets._sidef(s, f) * side
			var d := s.reach() + 3.5
			while d <= INNER_REACH:
				var c := p + nrm * d
				d += 1.0
				if land.zone_at(c.x, c.y) < 0.3 or is_built(c):
					continue
				var park := land.green_at(c.x, c.y) > 0.5
				if not park and _hash(roundi(c.x * 3.0), c.y, 4.4) > 0.6:
					continue
				# it belongs to whichever street is nearest
				var nearest := true
				for o: Streets.Street in streets._touching(s):
					if o.near_box(c, d) and o.closest(c).x < d - 0.5:
						nearest = false
						break
				if nearest and _inner_lot(s, f, c, park):
					break
		f += 6.0


## A small plot centred on c, facing the street it belongs to, if the ground
## there is free and fit to build on.
func _inner_lot(s: Streets.Street, f: float, c: Vector2, park: bool) -> bool:
	var to_street := (streets._ptf(s, s.closest(c).z) - c).normalized()
	var w := 4.2 if park else lerpf(2.6, 3.2, _hash(roundi(c.x * 5.0), c.y, 1.3))
	var dep := 4.2 if park else lerpf(3.2, 3.8, _hash(roundi(c.y * 5.0), c.x, 2.1))
	var yaw := atan2(to_street.x, to_street.y)
	var right := Vector2(cos(yaw), -sin(yaw))
	var origin := c + to_street * dep * 0.5
	var poly := PackedVector2Array([origin - right * w * 0.5, origin + right * w * 0.5,
		origin + right * w * 0.5 - to_street * dep, origin - right * w * 0.5 - to_street * dep])
	var cells := _free_cells(poly, s.id, -to_street)
	if cells.is_empty() or not _ground_ok(poly):
		return false
	# never on another street's frontage, which its own plots may still want
	for k in cells:
		if _front[k] != 0 and _front[k] != s.id:
			return false
	var l := Lot.new()
	l.id = _next_id
	_next_id += 1
	l.street = s.id
	l.side = signf(streets._sidef(s, f).dot(-to_street))
	l.quad = poly
	l.origin = origin
	l.yaw = yaw
	l.width = w
	l.depth = dep
	l.back = PackedVector2Array([Vector2(-w * 0.5, -dep), Vector2(w * 0.5, -dep)])
	l.inner = true
	l.cells = cells
	for k in cells:
		_occ[k] = l.id
	l.patch = Vector2i(int(floor((origin.x + Land.HALF) / PATCH)), int(floor((origin.y + Land.HALF) / PATCH)))
	lots[l.id] = l
	var ground := land.height_at(c.x, c.y)
	l.type = "park" if park else "house"
	if not park:
		land.pad(poly, ground + 0.02, 1.2, _near_street)
	l.kit = HouseGen.kit_at(land, origin)
	l.sd = int(floor(origin.x * 8.0)) * 73856093 ^ int(floor(origin.y * 8.0)) * 19349663
	l.street_y = ground + 0.02
	# a cottage or a small house: back lanes never grow tall
	l.cap = mini(_cap_at(s, c, l.side), 1)
	l.capq = c
	l.stage = mini(_take_kept(origin, w), l.cap)
	l.dense = STAGE_DENSE[l.cap]
	l.next_up = _clock + _delay(l, Vector2.ZERO)
	if park:
		l.arrays = CivicGen.build(l, land, l.street_y, l.sd)
	else:
		l.arrays = HouseGen.build(l, land, l.street_y, l.sd, false)
	reshaped.emit()
	_dirty_patches[l.patch] = true
	return true


## What a new lot here should hold: green where the player painted parks, now
## and then a square on a busy main street or a church, spaced well apart.
func _kind_at(s: Streets.Street, f: float, p: Vector2, side: float, dense: float) -> String:
	var q := p + streets._sidef(s, f) * side * (s.reach() + 2.5)
	if land.green_at(q.x, q.y) > 0.5:
		return "park"
	var h := _hash(s.id, f, side * 7.0)
	# squares and churches go by the area's level, not one plot's own luck
	dense = maxf(dense, STAGE_DENSE[clampi(roundi(land.level_at(q.x, q.y)), 0, 4)])
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


func _try_lot(s: Streets.Street, f0: float, f1: float, side: float, off: float, dense: float, kind := "house", cap := 0) -> Lot:
	var a := streets._ptf(s, f0) + streets._sidef(s, f0) * side * off
	var b := streets._ptf(s, f1) + streets._sidef(s, f1) * side * off
	var fm := (f0 + f1) * 0.5
	var inward := streets._sidef(s, fm) * side
	# side lines square to the street, so neighbouring lots share them exactly
	var na := streets._sidef(s, f0) * side
	var nb := streets._sidef(s, f1) * side
	var deepest := MAX_DEPTH if s.kind == "main" else MAX_DEPTH - 0.8
	var ds := _depths(s, a, b, na, nb, deepest)
	var n := ds.size()
	var least := MIN_DEPTH
	if kind == "church":
		least = 3.5
	elif kind == "square":
		least = 3.0
	# squares, churches and parks are laid out square; houses take the shape
	# of the block behind them, tapering where it narrows
	if kind != "house":
		var flat := INF
		for d in ds:
			flat = minf(flat, d)
		ds.fill(flat)
	var core := INF
	for k in range(n / 4, n - n / 4):
		core = minf(core, ds[k])
	for attempt in 3:
		if core < least:
			return null
		var poly := PackedVector2Array([a, b])
		for k in range(n - 1, -1, -1):
			var u := k / float(n - 1)
			poly.append(a.lerp(b, u) + na.lerp(nb, u).normalized() * maxf(ds[k], 0.3))
		var cells := _free_cells(poly, s.id, inward)
		if not cells.is_empty() and _ground_ok(poly):
			return _make_lot(s, a, b, na, nb, fm, side, poly, core, cells, dense, kind, cap)
		for k in n:
			ds[k] *= 0.8
		core *= 0.8
	return null


## How deep the block is behind each half metre of a frontage from a to b:
## up to another plot, a landmark's ground or another street's frontage, or
## halfway to the street behind, so plots meet back to back.
func _depths(s: Streets.Street, a: Vector2, b: Vector2, na: Vector2, nb: Vector2, deepest: float) -> PackedFloat32Array:
	var w := a.distance_to(b)
	var n := maxi(3, ceili(w / 0.5) + 1)
	# just inside the side lines, clear of the neighbours' cells
	var inset := minf(0.26, w * 0.2) / maxf(w, 0.01)
	var ds := PackedFloat32Array()
	for k in n:
		var u := lerpf(inset, 1.0 - inset, k / float(n - 1))
		var p := a.lerp(b, u)
		var nrm := na.lerp(nb, u).normalized()
		var lim := deepest
		var t := 0.25
		while t < deepest * 2.0 + 0.5:
			var c := _cell(p + nrm * t)
			if c.x < 0 or c.y < 0 or c.x >= RES or c.y >= RES:
				lim = minf(lim, t - 0.25)
				break
			var i := c.y * RES + c.x
			var o := _occ[i]
			if o < 0 and o != RESERVED:
				lim = minf(lim, snappedf(t * 0.5 - 0.1, 0.25))
				break
			if t > lim:
				if o != 0:
					break
			elif o != 0 or (_front[i] != 0 and _front[i] != s.id and t > FRONTAGE):
				lim = t - 0.25
				break
			t += 0.25
		ds.append(maxf(lim, 0.0))
	# no sudden steps from one half metre to the next
	for k in range(1, n):
		ds[k] = minf(ds[k], ds[k - 1] + 0.75)
	for k in range(n - 2, -1, -1):
		ds[k] = minf(ds[k], ds[k + 1] + 0.75)
	return ds


func _make_lot(s: Streets.Street, a: Vector2, b: Vector2, na: Vector2, nb: Vector2, fm: float, side: float, poly: PackedVector2Array,
		depth: float, cells: PackedInt32Array, dense: float, kind: String, cap: int) -> Lot:
	var inward := streets._sidef(s, fm) * side
	var l := Lot.new()
	l.id = _next_id
	_next_id += 1
	l.street = s.id
	l.side = side
	l.quad = poly
	l.origin = (a + b) * 0.5
	# local +Z faces the street
	l.yaw = atan2(-inward.x, -inward.y)
	l.width = a.distance_to(b)
	l.depth = depth
	var right := Vector2(cos(l.yaw), -sin(l.yaw))
	var fwd := Vector2(sin(l.yaw), cos(l.yaw))
	for k in range(2, poly.size()):
		var q := poly[k] - l.origin
		l.back.append(Vector2(q.dot(right), q.dot(fwd)))
	for sx: float in [-1.0, 1.0]:
		var q := l.origin + right * sx * (l.width * 0.5 + 1.1) - fwd * minf(1.5, depth * 0.5)
		var c := _cell(q)
		if c.x >= 0 and c.y >= 0 and c.x < RES and c.y < RES and _occ[c.y * RES + c.x] < 0 and _occ[c.y * RES + c.x] != RESERVED:
			l.corner = sx
	if l.back.size() > 1 and l.back[0].x > l.back[l.back.size() - 1].x:
		l.back.reverse()
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
	l.sd = sd
	l.street_y = street_y
	l.main = s.kind == "main"
	l.cap = cap
	# a new house starts as a cottage, unless this plot had grown before
	l.stage = mini(_take_kept(l.origin, l.width), cap)
	l.next_up = _clock + _delay(l, Vector2.ZERO)
	if kind == "house":
		l.arrays = HouseGen.build(l, land, street_y, sd, s.kind == "main")
	else:
		l.arrays = CivicGen.build(l, land, street_y, sd)
	reshaped.emit()
	_dirty_patches[l.patch] = true
	if kind == "house" and l.stage >= MERGE_STAGE:
		_try_merge(l)
	return l


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
	var c := l.origin - Vector2(sin(l.yaw), cos(l.yaw)) * 2.5
	return land.green_at(c.x, c.y)


func _zone(l: Lot) -> float:
	var c := l.origin - Vector2(sin(l.yaw), cos(l.yaw)) * l.depth * 0.5
	return land.zone_at(c.x, c.y)


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
		sm.surface_set_material(0, Palette.shadow_material())
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
