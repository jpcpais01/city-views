class_name Growth
extends Node
## How the town decides where its streets go. The player paints where it should
## grow; from the streets already there, side streets branch off at block-sized
## gaps and are traced through a direction field: they line up square with the
## streets nearby, swing round to follow the contours on hillsides, and stop at
## the shore, on slopes too steep to climb, or where they meet another street,
## joining it. Cross streets then branch off those, closing the streets into
## blocks. One street at a time, so the town visibly grows.

const STEP := 0.8
const MAX_LEN := 44.0
const MIN_LEN := 6.0
const PACE := 0.3
# how far from the brush the town looks for places to branch
const NEAR := 34.0
# steepest natural ground a street will climb (it is graded gentler, cutting in)
const MAX_SLOPE := 0.36
# gaps between side streets along a main street (block frontage) and along a
# side street (block depth)
const FRONTAGE := 11.0
const DEPTH := 13.0
# never closer than this between side streets
const MIN_BLOCK := 7.5

var land: Land
var streets: Streets
## where the player last painted: the town grows outwards from here
var focus := Vector2.ZERO
var _timer := 0.0
var _awake := false
var _cands: Array = []
var _scan: Array = []
var _found: Array = []
var _scanning := false
var _failed := {}
var _wobble := FastNoiseLite.new()


func _init() -> void:
	_wobble.frequency = 1.0 / 30.0


## The player painted near `at`: start (or keep) growing.
func wake(at: Vector2) -> void:
	focus = at
	_awake = true
	_cands.clear()
	_scan.clear()
	_found.clear()
	_scanning = false
	_failed.clear()


## The player is still painting near `at`: grow towards it, carrying on with
## the search already under way (a fresh one would never get anywhere while
## the brush moves every frame).
func nudge(at: Vector2) -> void:
	focus = at
	if not _awake:
		wake(at)


func stop() -> void:
	_awake = false
	_cands.clear()
	_scan.clear()
	_found.clear()
	_scanning = false


func is_growing() -> bool:
	return _awake


func _process(delta: float) -> void:
	if not _awake:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	# look over the streets, then try the best spots, a slice of work per frame
	var start := Time.get_ticks_usec()
	while Time.get_ticks_usec() - start < 2500:
		# laying a street is the big step: give it a frame of its own
		if not _cands.is_empty() and Time.get_ticks_usec() - start > 300:
			return
		if not _cands.is_empty():
			if _try(_cands.pop_front()):
				_cands.clear()
				_timer = PACE
				return
			continue
		if _scan.is_empty():
			if _scanning:
				_scanning = false
				if _found.is_empty():
					_awake = false
					return
				_cands = _sorted(_found)
				_found = []
				continue
			_scanning = true
			for st: Streets.Street in streets.streets:
				if st.near_box(focus, NEAR):
					_scan.append(st)
			continue
		var st: Streets.Street = _scan.pop_back()
		if st in streets.streets:
			_found.append_array(_seeds(st))


## Grows the whole town at once (tests, loading a shared island).
func grow_all(limit := 400) -> int:
	var made := 0
	_cands.clear()
	while made < limit:
		# failed seeds drop out, so a fresh list offers the next spots along
		var cands := _candidates()
		if cands.is_empty():
			break
		for c in cands:
			if _try(c):
				made += 1
				break
	_awake = false
	return made


func _try(c: Dictionary) -> bool:
	var key: String = c.key
	if _failed.has(key):
		return false
	var s: Streets.Street = c.street
	if not s in streets.streets:
		return false
	var pts := _trace(c.start, c.dir, s)
	if pts.size() >= 3 and Streets._length(pts) >= MIN_LEN and streets.add_stroke(pts, "side") != null:
		return true
	_failed[key] = true
	return false


# ------------------------------------------------------------------ where to branch

## Where new side streets could branch, best first.
func _candidates() -> Array:
	var out: Array = []
	for st: Streets.Street in streets.streets:
		out.append_array(_seeds(st))
	return _sorted(out)


## Continue a street straight across first (crossroads), then grow outwards from the brush.
func _sorted(list: Array) -> Array:
	list.sort_custom(func(a, b):
		if a.prio != b.prio:
			return a.prio < b.prio
		return a.start.distance_squared_to(focus) < b.start.distance_squared_to(focus))
	return list


func _seeds(s: Streets.Street) -> Array:
	var out: Array = []
	# streets don't branch off a highway (it has no pavements, and nobody lives along it)
	if s.kind == "highway":
		return out
	var n := s.pts.size()
	var total := (n - 1) * Streets.SAMPLE
	var spacing := FRONTAGE if s.major() else DEPTH
	var contacts := _contacts(s)
	for side: float in [-1.0, 1.0]:
		# each side of each street keeps its own slight irregularity
		var gap := spacing * (0.88 + 0.24 * fposmod(sin(s.id * 12.9898 + side * 78.233) * 43758.5453, 1.0))
		# the stretches between junctions on this side, each split into even blocks
		var marks := PackedFloat32Array([0.0, total])
		var opp := PackedFloat32Array()
		for c in contacts:
			if c.y == side:
				marks.append(c.x)
			else:
				opp.append(c.x)
		marks.sort()
		for m in marks.size() - 1:
			var a := marks[m]
			var b := marks[m + 1]
			var k := int((b - a) / (gap * 0.7))
			if k < 2 or (b - a) / k < MIN_BLOCK:
				continue
			for j in range(1, k):
				var arc := a + (b - a) * j / k
				# line up with a street across the way, making a crossroads
				var prio := 1
				for o in opp:
					if absf(o - arc) < 4.0:
						arc = o
						prio = 0
				var i := clampi(int(round(arc / Streets.SAMPLE)), 0, n - 1)
				var nrm := streets._side(s, i) * side
				var start := s.pts[i]
				var probe := start + nrm * (s.reach() + 2.5)
				var key := "%d:%d:%d" % [s.id, int(arc), int(side)]
				if _failed.has(key) or land.zone_at(probe.x, probe.y) < 0.4 or land.height_at(probe.x, probe.y) < 0.35 or _occupied(probe, s):
					continue
				out.append({"street": s, "start": start, "dir": nrm, "prio": prio, "key": key})
	return out


## Where other streets meet this one: (distance along it, side) pairs.
func _contacts(s: Streets.Street) -> PackedVector2Array:
	var out := PackedVector2Array()
	var r := s.reach()
	for o: Streets.Street in streets.streets:
		if o == s or not streets._boxes_overlap(s, o):
			continue
		for p in o.pts:
			if not s.near_box(p, r + 3.0):
				continue
			var c: Vector3 = s.closest(p)
			if c.x < r + 0.3 or c.x > r + 3.0:
				continue
			var i := clampi(int(c.z), 0, s.pts.size() - 1)
			var side := signf(streets._side(s, i).dot(p - s.pts[i]))
			out.append(Vector2(c.z * Streets.SAMPLE, side))
	return out


func _occupied(p: Vector2, parent: Streets.Street) -> bool:
	for o: Streets.Street in streets.streets:
		if o != parent and o.near_box(p, o.reach() + 2.5) and o.closest(p).x < o.reach() + 2.5:
			return true
	return false


# ------------------------------------------------------------------ tracing

## Follows the direction field from a street out into the painted area.
func _trace(start: Vector2, dir: Vector2, parent: Streets.Street) -> PackedVector2Array:
	var pts := PackedVector2Array([start])
	var p := start + dir * (parent.reach() + 0.6)
	if land.height_at(p.x, p.y) < 0.35:
		return PackedVector2Array()
	pts.append(p)
	var heading := dir
	var length := parent.reach() + 0.6
	while length < MAX_LEN:
		heading = (heading * 0.65 + _field(p, heading) * 0.35).normalized()
		var q := p + heading * STEP
		# too steep to climb straight on: swing round across the slope, like a hill road
		if length > parent.reach() + 3.0 and _grade(p, heading) > MAX_SLOPE:
			var turned := false
			for k in [1, -1, 2, -2, 3, -3]:
				var h2 := heading.rotated(k * 0.3)
				if _grade(p, h2) <= MAX_SLOPE:
					heading = h2
					turned = true
					break
			if not turned:
				break
			q = p + heading * STEP
		if land.height_at(q.x, q.y) < 0.35 or land.zone_at(q.x, q.y) < 0.2:
			break
		var hit := _hit(q, heading, parent, start, length)
		if hit.x == 1.0:
			pts.append(Vector2(hit.y, hit.z))
			return pts
		if hit.x == 2.0:
			break
		pts.append(q)
		p = q
		length += STEP
	# rather than stop just short of a street, run on and join it
	var reach: Variant = _reach_ahead(p, heading, parent, start)
	if reach != null:
		pts.append(reach)
		return pts
	# a dead end: keep it only if it reaches somewhere worth going
	if length < MIN_LEN + 2.0:
		return PackedVector2Array()
	return pts


func _reach_ahead(p: Vector2, heading: Vector2, parent: Streets.Street, start: Vector2) -> Variant:
	var best: Variant = null
	var bd := 7.0
	for o: Streets.Street in streets.streets:
		if o == parent or o.closest(start).x < o.reach() + 0.5 or not o.near_box(p, bd):
			continue
		var c: Vector3 = o.closest(p)
		if c.x >= bd:
			continue
		var i := clampi(int(c.z), 0, o.pts.size() - 2)
		var on := o.pts[i].lerp(o.pts[i + 1], clampf(c.z - i, 0.0, 1.0))
		# only ahead of us, and meeting it more across than along
		var to := (on - p).normalized()
		if to.dot(heading) > 0.6 and absf((o.pts[i + 1] - o.pts[i]).normalized().dot(to)) < 0.7:
			bd = c.x
			best = on
	return best


## How steeply the natural ground climbs heading this way from p.
func _grade(p: Vector2, heading: Vector2) -> float:
	var ahead := p + heading * 2.3
	return absf(land.height_at(ahead.x, ahead.y) - land.height_at(p.x, p.y)) / 2.3


## (1, x, z): joins a street at (x, z). (2, ..): runs alongside one too closely. (0, ..): clear.
func _hit(q: Vector2, heading: Vector2, parent: Streets.Street, start: Vector2, length: float) -> Vector3:
	for o: Streets.Street in streets.streets:
		# near the start, ignore the streets that meet at the junction we leave from
		if length < 6.0 and (o == parent or o.closest(start).x < o.reach() + 0.5):
			continue
		if not o.near_box(q, o.reach() + 4.5):
			continue
		var c: Vector3 = o.closest(q)
		if c.x > o.reach() + 4.5:
			continue
		var i := clampi(int(c.z), 0, o.pts.size() - 2)
		var t := (o.pts[i + 1] - o.pts[i]).normalized()
		var along := absf(t.dot(heading))
		# running alongside (not just lined up with the end of one)
		if along > 0.8 and c.z > 0.05 and c.z < o.pts.size() - 1.05:
			return Vector3(2, 0, 0)
		if c.x < o.reach() + 1.0:
			var on := o.pts[i].lerp(o.pts[i + 1], clampf(c.z - i, 0.0, 1.0))
			return Vector3(1, on.x, on.y)
	return Vector3.ZERO


## The way streets want to run here, the one of its four axes nearest `heading`:
## square with the streets nearby, along the contours on a slope.
func _field(p: Vector2, heading: Vector2) -> Vector2:
	var acc := Vector2.ZERO
	var total := 0.0
	for o: Streets.Street in streets.streets:
		if not o.near_box(p, 20.0):
			continue
		var c: Vector3 = o.closest(p)
		if c.x > 20.0:
			continue
		var i := clampi(int(c.z), 0, o.pts.size() - 2)
		var a := (o.pts[i + 1] - o.pts[i]).angle()
		var w := 1.0 / (c.x * c.x + 9.0)
		acc += Vector2(cos(4.0 * a), sin(4.0 * a)) * w
		total += w
	var v := acc / total if total > 0.0 else Vector2.ZERO
	var e := 1.0
	var g := Vector2(land.height_at(p.x + e, p.y) - land.height_at(p.x - e, p.y), land.height_at(p.x, p.y + e) - land.height_at(p.x, p.y - e)) / (2.0 * e)
	var slope := g.length()
	if slope > 0.04:
		var ca := g.angle() + PI * 0.5
		v += Vector2(cos(4.0 * ca), sin(4.0 * ca)) * smoothstep(0.04, 0.25, slope) * 1.5
	var theta := v.angle() / 4.0 + _wobble.get_noise_2d(p.x, p.y) * 0.12 if v.length() > 0.01 else heading.angle()
	var best := heading
	var bd := -2.0
	for k in 4:
		var d := Vector2.from_angle(theta + k * PI * 0.5)
		if d.dot(heading) > bd:
			bd = d.dot(heading)
			best = d
	return best
