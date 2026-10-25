class_name HighwayPlan
extends RefCounted
## The map's highways, planned from a seed rather than drawn: a few long
## roads from one edge of the map to another, the way a motorway network runs
## through a region. Each is routed over a coarse grid of the land (A*, with
## its heading kept, so it only ever turns gently): along valleys and level
## ground, round hills, lakes and the town, over rivers and inlets the short
## way, square on. The route is then evened out into long straights joined by
## wide circular curves. A second highway crosses the first square on, on a
## straight and level stretch of dry land, so the two meet in a full
## cloverleaf (Streets lays its ramps); a street drawn across one gets a
## diamond. Every seed gives another network; the same seed on the same land
## always gives the same one (co-op builders work it out alike).

## the eight ways out of a grid cell, going round
const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1),
	Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1)]
## what a metre over water costs, against about 1 over level land: bridges
## are dear, so crossings are short and square on
const WATER := 7.0
## and each time a route goes out over the water, on top
const WET_ENTRY := 40.0
## what a 45° turn costs (in metres of level road): routes run straight
const TURN := 24.0
## how far a crossing runs straight and level either side, for its cloverleaf
const KEEP := 54.0
## where a crossing highway's own route takes over from the straight through it
const LEAD := 90.0
## how far apart two crossings stand, at least
const CROSS_GAP := 150.0

var land: Land
var cell := 4.0
var n := 0
## what a metre through each cell costs
var cost := PackedFloat32Array()
var wet := PackedByteArray()
var rng := RandomNumberGenerator.new()
var _noise := FastNoiseLite.new()
## the highways planned so far, as smooth lines with points about 2 m apart
var lines: Array[PackedVector2Array] = []
## where they cross, one over the other
var crossings := PackedVector2Array()
# where each cell's route came from, and its open list (a binary heap)
var _g := PackedFloat32Array()
var _from := PackedInt32Array()
var _shut := PackedByteArray()
var _hk := PackedFloat32Array()
var _hv := PackedInt32Array()
var _hn := 0


## The highways for this land and seed, as lines from map edge to map edge,
## the first ones first (a later one crossing an earlier flies over it).
## `keep_clear`: the lines of streets already there, which highways keep off
## (crossing them only where they must) as they do the painted town.
static func make(on: Land, seed_value: int, keep_clear: Array = []) -> Array[PackedVector2Array]:
	var p := HighwayPlan.new()
	p.land = on
	p.rng.seed = seed_value
	p._noise.seed = seed_value + 11
	p._noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	p._noise.fractal_octaves = 2
	p._noise.frequency = 1.0 / 95.0
	p._grid(keep_clear)
	p._network()
	return p.lines


# ------------------------------------------------------------------ the land as costs

func _grid(keep_clear: Array) -> void:
	cell = 4.0 if Land.SIZE <= Land.NORMAL_SIZE else 6.0
	n = int(Land.SIZE / cell)
	cost.resize(n * n)
	wet.resize(n * n)
	for j in n:
		for i in n:
			var p := _centre(i, j)
			var h := land.height_at(p.x, p.y)
			var k := j * n + i
			var c := 1.0
			if h < 0.08:
				wet[k] = 1
				c = WATER + clampf(-h, 0.0, 4.0) * 0.6
			else:
				wet[k] = 0
				var hx := land.height_at(p.x + cell, p.y) - land.height_at(p.x - cell, p.y)
				var hz := land.height_at(p.x, p.y + cell) - land.height_at(p.x, p.y - cell)
				var slope := maxf(absf(hx), absf(hz)) / (2.0 * cell)
				# steep ground is dear (it means deep cuttings), high ground a little
				c += slope * slope * 160.0 + maxf(h - 2.5, 0.0) * 0.15
				# the painted town: go round it
				if land.zone_at(p.x, p.y) > 0.2:
					c += 10.0
				# and keep off the beach, a little way back from the water
				for q: Vector2 in [Vector2(cell, 0), Vector2(-cell, 0), Vector2(0, cell), Vector2(0, -cell)]:
					if land.height_at(p.x + q.x * 2.5, p.y + q.y * 2.5) < 0.08:
						c += 1.2
			# the map's rim: come in across it, don't run along it
			var rim := Land.HALF - maxf(absf(p.x), absf(p.y))
			if rim < 24.0:
				c += (24.0 - rim) / 24.0 * 2.5
			# a gentle lie of the land of the seed's own, so each seed routes its own way
			c *= 1.0 + 0.35 * _noise.get_noise_2d(p.x, p.y)
			cost[k] = c
	for line: PackedVector2Array in keep_clear:
		_stamp(line, 7.0, 6.0)
	if keep_clear.is_empty():
		# a fresh map: the town will start here, so leave it some room
		var sp := land.start_point()
		_stamp(PackedVector2Array([sp, sp + Vector2(0.01, 0.0)]), 40.0, 5.0)


func _centre(i: int, j: int) -> Vector2:
	return Vector2((i + 0.5) * cell - Land.HALF, (j + 0.5) * cell - Land.HALF)


func _cell_of(p: Vector2) -> Vector2i:
	return Vector2i(clampi(int((p.x + Land.HALF) / cell), 0, n - 1), clampi(int((p.y + Land.HALF) / cell), 0, n - 1))


## Adds `amount` to the cost of every cell within `r` of the line (fading
## out towards r).
func _stamp(line: PackedVector2Array, r: float, amount: float) -> void:
	if line.size() < 2:
		return
	var touched := {}
	var rc := int(ceil(r / cell)) + 1
	for s in line.size() - 1:
		var a := line[s]
		var b := line[s + 1]
		var l := a.distance_to(b)
		var t := 0.0
		while t <= l:
			var p := a.lerp(b, t / maxf(l, 1e-6))
			var c := _cell_of(p)
			for dj in range(-rc, rc + 1):
				for di in range(-rc, rc + 1):
					var i := c.x + di
					var j := c.y + dj
					if i < 0 or j < 0 or i >= n or j >= n:
						continue
					var d := _centre(i, j).distance_to(p)
					if d >= r:
						continue
					var k := j * n + i
					var w := 1.0 - d / r
					touched[k] = maxf(touched.get(k, 0.0), w)
			t += cell * 0.5
	for k: int in touched:
		cost[k] += amount * (0.4 + 0.6 * touched[k])


# ------------------------------------------------------------------ the network

func _network() -> void:
	var ends := _entries()
	if ends.size() < 2:
		return
	var big := Land.SIZE > Land.NORMAL_SIZE
	var want := 1
	var roll := rng.randf()
	if big:
		want = 3 if roll < 0.5 else 2
	else:
		want = 2 if roll < 0.7 else 1
	# the trunk: from a good way in on one side to the far side of the map
	# (a few tries, keeping the one with the widest tightest curve)
	ends.sort_custom(func(a, b): return a.score < b.score)
	var trunk := PackedVector2Array()
	var trunk_r := -1.0
	for attempt in 4:
		var a: Dictionary = ends[rng.randi_range(0, maxi(0, int(ends.size() * 0.3) - 1))]
		var best: Dictionary = {}
		var bs := INF
		for e: Dictionary in ends:
			if e.side == a.side:
				continue
			var turn := absf(wrapf(e.p.angle() - a.p.angle(), -PI, PI))
			if turn < deg_to_rad(110.0):
				continue
			var sc: float = e.score + absf(PI - turn) * 18.0 + rng.randf() * 14.0
			if sc < bs:
				bs = sc
				best = e
		if best.is_empty():
			continue
		var line := _join(a, best, [])
		var r := tightest(line)
		if not line.is_empty() and r > trunk_r:
			trunk = line
			trunk_r = r
		if trunk_r >= GOOD_RADIUS:
			break
	if trunk.is_empty():
		return
	lines.append(trunk)
	for k in want - 1:
		if not _cross_one(ends):
			break


## Plans a highway crossing one of those planned (square on, in a cloverleaf)
## from one edge of the map to another. Whether one could be found.
func _cross_one(ends: Array) -> bool:
	var tried := 0
	var near := PackedVector2Array()
	for spot: Dictionary in _crossing_spots():
		if tried >= 4:
			break
		var skip := false
		for q in near:
			skip = skip or q.distance_to(spot.at) < 40.0
		if skip:
			continue
		tried += 1
		near.append(spot.at)
		if _cross_at(ends, spot.at, spot.nrm):
			return true
	return false


## The highway crossing at x, heading along nrm: laid out, and kept if its
## curves are wide enough. Whether it was.
func _cross_at(ends: Array, x: Vector2, nrm: Vector2) -> bool:
	var c := _entry_toward(ends, x, -nrm)
	var d := _entry_toward(ends, x, nrm)
	if c.is_empty() or d.is_empty():
		return false
	# keep off the highways already planned, but for this one crossing
	var saved := cost.duplicate()
	for line in lines:
		_stamp(line, 14.0, 4000.0)
		_stamp(line, 64.0, 7.0)
	var w1 := x - nrm * LEAD
	var w2 := x + nrm * LEAD
	var first := _route(c, w1, c.into, nrm)
	var second := _route_from(w2, nrm, d)
	cost = saved
	if first.is_empty() or second.is_empty():
		return false
	var raw := PackedVector2Array([c.p])
	raw.append_array(first)
	raw[raw.size() - 1] = w1
	raw.append(x)
	second[0] = w2
	raw.append_array(second)
	raw.append(d.p)
	var line := _smooth(raw, [x])
	if line.is_empty() or tightest(line) < GOOD_RADIUS or _meets(line) != 1:
		return false
	lines.append(line)
	crossings.append(x)
	return true


## Where a new highway can cross one planned, best first: a long straight,
## level, dry stretch of it, clear of the town, the others and the map's
## edge, with room for a cloverleaf in every corner. [{at, nrm, score}]
func _crossing_spots() -> Array:
	var out: Array = []
	for li in lines.size():
		var line := lines[li]
		var m := line.size()
		var span := int(KEEP / 2.0)
		for i in range(maxi(int(m * 0.18), span + 1), mini(int(m * 0.82), m - span - 1), 4):
			var x := line[i]
			var d := (line[i + 1] - line[i - 1]).normalized()
			var da := (x - line[i - span]).normalized()
			var db := (line[i + span] - x).normalized()
			if da.dot(db) < cos(deg_to_rad(6.0)) or da.dot(d) < 0.99 or db.dot(d) < 0.99:
				continue
			var nrm := d.orthogonal()
			var ok := true
			var rough := 0.0
			var h0 := land.height_at(x.x, x.y)
			# the ground the interchange stands on: along both roads and in each corner
			var probe := PackedVector2Array()
			for t in range(-int(KEEP + 10.0), int(KEEP + 11.0), 6):
				probe.append(x + d * t)
				probe.append(x + nrm * t)
			# and the crossing road's lead in, both ways, so it comes from inland
			var lead_wet := 0
			for t in range(int(KEEP + 16.0), int(LEAD + 12.0), 8):
				for q: Vector2 in [x + nrm * t, x - nrm * t]:
					if land.height_at(q.x, q.y) < 0.15:
						lead_wet += 1
			if lead_wet > 3:
				continue
			for q in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]:
				for r in [14.0, 30.0]:
					probe.append(x + d * q.x * r + nrm * q.y * r)
			for p in probe:
				var h := land.height_at(p.x, p.y)
				if h < 0.15 or land.zone_at(p.x, p.y) > 0.2:
					ok = false
					break
				rough += absf(h - h0)
			if not ok:
				continue
			# room for the crossing road's straight either side, inside the map
			var room := minf(_to_edge(x, nrm), _to_edge(x, -nrm))
			if room < LEAD + 30.0:
				continue
			var near := false
			for c in crossings:
				near = near or c.distance_to(x) < CROSS_GAP
			for lj in lines.size():
				if lj != li and _dist_to(lines[lj], x) < KEEP + 30.0:
					near = true
			if near:
				continue
			var sc := rough * 1.5 + x.length() * 0.06 + rng.randf() * 10.0
			out.append({"at": x, "nrm": nrm, "score": sc})
	out.sort_custom(func(a, b): return a.score < b.score)
	return out


## How many times a line crosses the highways planned (a new one should
## cross just once, at its interchange).
func _meets(line: PackedVector2Array) -> int:
	var count := 0
	for other in lines:
		for i in range(0, line.size() - 1, 2):
			var a := line[i]
			var b := line[mini(i + 2, line.size() - 1)]
			for j in range(0, other.size() - 1, 2):
				if Geometry2D.segment_intersects_segment(a, b, other[j], other[mini(j + 2, other.size() - 1)]) != null:
					count += 1
	return count


## How far from p, heading `dir`, the map's edge lies.
static func _to_edge(p: Vector2, dir: Vector2) -> float:
	var t := INF
	var h := Land.HALF
	if absf(dir.x) > 1e-4:
		t = minf(t, ((h if dir.x > 0.0 else -h) - p.x) / dir.x)
	if absf(dir.y) > 1e-4:
		t = minf(t, ((h if dir.y > 0.0 else -h) - p.y) / dir.y)
	return t


static func _dist_to(line: PackedVector2Array, p: Vector2) -> float:
	var best := INF
	for k in range(0, line.size() - 1, 2):
		best = minf(best, Geometry2D.get_closest_point_to_segment(p, line[k], line[mini(k + 2, line.size() - 1)]).distance_to(p))
	return best


## Places on the map's edge where a highway can come in, with how good each
## is (lower is better): little water to bridge before dry land, and level
## ground there. [{p, into, side, score}]
func _entries() -> Array:
	var out: Array = []
	var h := Land.HALF - 0.5
	var ins := [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]
	for side in 4:
		var into: Vector2 = ins[side]
		var t := -h + 40.0
		while t <= h - 40.0:
			var p: Vector2
			match side:
				0: p = Vector2(-h, t)
				1: p = Vector2(h, t)
				2: p = Vector2(t, -h)
				_: p = Vector2(t, h)
			t += 8.0
			var run := 0.0
			while run < 150.0 and land.height_at(p.x + into.x * run, p.y + into.y * run) < 0.12:
				run += 4.0
			if run >= 150.0:
				continue
			var q := p + into * (run + 16.0)
			var along := into.orthogonal()
			var hq := land.height_at(q.x, q.y)
			var rough := absf(land.height_at(q.x + into.x * 8.0, q.y + into.y * 8.0) - hq) + absf(land.height_at(q.x + along.x * 8.0, q.y + along.y * 8.0) - hq)
			var sc := run * 0.6 + rough * 14.0 + maxf(hq - 3.0, 0.0) * 2.0 + rng.randf() * 10.0
			out.append({"p": p, "into": into, "side": side, "score": sc})
	return out


## The best entry out from x heading `dir`: near where that way meets the
## map's edge, on that side. {} if there's none.
func _entry_toward(ends: Array, x: Vector2, dir: Vector2) -> Dictionary:
	var hit := x + dir * _to_edge(x, dir)
	var best := {}
	var bs := INF
	for e: Dictionary in ends:
		# on that side, and further out than where the straight begins (a
		# route coming in from behind it would have to turn right round)
		if e.into.dot(dir) > -0.5 or (e.p - x).dot(dir) < LEAD:
			continue
		# not where another highway leaves the map
		var taken := false
		for line in lines:
			taken = taken or e.p.distance_to(line[0]) < 110.0 or e.p.distance_to(line[line.size() - 1]) < 110.0
		if taken:
			continue
		var sc: float = e.score + e.p.distance_to(hit) * 0.25
		if sc < bs:
			bs = sc
			best = e
	return best


## A highway from entry a to entry b, smoothed. Empty if no way was found.
func _join(a: Dictionary, b: Dictionary, through: Array) -> PackedVector2Array:
	var route := _route(a, b.p, a.into, -b.into)
	if route.is_empty():
		return route
	var raw := PackedVector2Array([a.p])
	raw.append_array(route)
	raw.append(b.p)
	return _smooth(raw, through)


func _route(a: Dictionary, to: Vector2, out: Vector2, into: Vector2) -> PackedVector2Array:
	return _astar(_cell_of(a.p + a.into * cell * 0.5), _cell_of(to), out, into)


func _route_from(from: Vector2, out: Vector2, b: Dictionary) -> PackedVector2Array:
	return _astar(_cell_of(from), _cell_of(b.p + b.into * cell * 0.5), out, -b.into)


# ------------------------------------------------------------------ routing

## The cheapest way from cell a to cell b, as cell centres: leaving a heading
## near `out` and reaching b heading near `into` (zero for any heading). It turns 45° at most a step, and each turn costs.
func _astar(a: Vector2i, b: Vector2i, out: Vector2, into: Vector2) -> PackedVector2Array:
	var states := n * n * 8
	_g.resize(states)
	_g.fill(INF)
	_from.resize(states)
	_from.fill(-1)
	_shut.resize(states)
	_shut.fill(0)
	_hk.resize(0)
	_hv.resize(0)
	_hn = 0
	var dirs := PackedVector2Array()
	for d in DIRS:
		dirs.append(Vector2(d).normalized())
	# (a heading asked for is held to within about 25°, so the route leaves and
	# arrives nearly in line with the straight it carries on from)
	for d in 8:
		if out == Vector2.ZERO or dirs[d].dot(out) > 0.9:
			var s := (a.y * n + a.x) * 8 + d
			_g[s] = 0.0
			_push(_guess(a, b), s)
	var goal := -1
	var pops := 0
	while _hn > 0 and pops < 2000000:
		pops += 1
		var s := _pop()
		if _shut[s] == 1:
			continue
		_shut[s] = 1
		var d := s % 8
		var k := s / 8
		var i := k % n
		var j := k / n
		if i == b.x and j == b.y and (into == Vector2.ZERO or dirs[d].dot(into) > 0.9):
			goal = s
			break
		var gs := _g[s]
		for t in [-1, 0, 1]:
			var nd: int = (d + t + 8) % 8
			var step := DIRS[nd]
			var ni := i + step.x
			var nj := j + step.y
			if ni < 0 or nj < 0 or ni >= n or nj >= n:
				continue
			var nk := nj * n + ni
			var l := cell * (1.4142 if step.x != 0 and step.y != 0 else 1.0)
			var c := (cost[k] + cost[nk]) * 0.5 * l
			if t != 0:
				c += TURN
			if wet[nk] == 1 and wet[k] == 0:
				c += WET_ENTRY
			var ns := nk * 8 + nd
			var ng := gs + c
			if ng < _g[ns]:
				_g[ns] = ng
				_from[ns] = s
				_push(ng + _guess(Vector2i(ni, nj), b), ns)
	var path := PackedVector2Array()
	if goal < 0:
		return path
	var s := goal
	while s >= 0:
		var k := s / 8
		path.append(_centre(k % n, k / n))
		s = _from[s]
	path.reverse()
	return path


func _guess(c: Vector2i, b: Vector2i) -> float:
	return Vector2(c - b).length() * cell * 0.85


func _push(key: float, v: int) -> void:
	if _hn == _hk.size():
		_hk.append(key)
		_hv.append(v)
	else:
		_hk[_hn] = key
		_hv[_hn] = v
	var i := _hn
	_hn += 1
	while i > 0:
		var up := (i - 1) / 2
		if _hk[up] <= _hk[i]:
			break
		var tk := _hk[up]
		var tv := _hv[up]
		_hk[up] = _hk[i]
		_hv[up] = _hv[i]
		_hk[i] = tk
		_hv[i] = tv
		i = up


func _pop() -> int:
	var top := _hv[0]
	_hn -= 1
	if _hn > 0:
		_hk[0] = _hk[_hn]
		_hv[0] = _hv[_hn]
		var i := 0
		while true:
			var l := i * 2 + 1
			if l >= _hn:
				break
			var c := l
			if l + 1 < _hn and _hk[l + 1] < _hk[l]:
				c = l + 1
			if _hk[i] <= _hk[c]:
				break
			var tk := _hk[c]
			var tv := _hv[c]
			_hk[c] = _hk[i]
			_hv[c] = _hv[i]
			_hk[i] = tk
			_hv[i] = tv
			i = c
	return top


# ------------------------------------------------------------------ smoothing

## A grid route made a highway's line: the stair steps taken out, then long
## straights joined by circular curves as wide as the straights allow, the
## straight through each of `through` (crossings) kept KEEP either side.
## Points about 2 m apart.
func _smooth(raw: PackedVector2Array, through: Array) -> PackedVector2Array:
	var keep := {0: true, raw.size() - 1: true}
	for x: Vector2 in through:
		for k in raw.size():
			if raw[k] == x:
				keep[k] = true
				# and the ends of its straight
				if k > 0:
					keep[k - 1] = true
				if k < raw.size() - 1:
					keep[k + 1] = true
	var simple := _simplify(raw, cell * 1.6, keep)
	var radius := (75.0 if Land.SIZE <= Land.NORMAL_SIZE else 100.0) * rng.randf_range(0.85, 1.25)
	var curved := Streets._resample(_fillet(simple, radius, through), 2.0)
	# a last easing, so where straights left little room the curve still opens
	# out (straights stay straight, the ends stay on the map's edge)
	curved = Streets._relax(curved, 70)
	return _open_bends(curved, through)


## the tightest a highway may curve
const MIN_RADIUS := 32.0
## a line whose tightest curve is tighter than this is planned another way
const GOOD_RADIUS := 26.0


## The radius of a line's tightest curve, over 6 m chords (INF if straight;
## -1 if empty).
static func tightest(h: PackedVector2Array) -> float:
	if h.is_empty():
		return -1.0
	var best := INF
	for i in range(3, h.size() - 3):
		var a := (h[i] - h[i - 3]).normalized()
		var b := (h[i + 3] - h[i]).normalized()
		var turn := absf(a.angle_to(b))
		if turn > 1e-4:
			best = minf(best, h[i].distance_to(h[i - 3]) / turn)
	return best


## Eases out what bends are still tighter than MIN_RADIUS, a little at a
## time round each, leaving the ends and the straights through crossings be.
static func _open_bends(pts: PackedVector2Array, through: Array) -> PackedVector2Array:
	var m := pts.size()
	var fixed := PackedByteArray()
	fixed.resize(m)
	for k in m:
		if k < 3 or k > m - 4:
			fixed[k] = 1
		for x: Vector2 in through:
			if pts[k].distance_to(x) < KEEP:
				fixed[k] = 1
	for it in 300:
		var loose := {}
		for i in range(3, m - 3):
			var a := (pts[i] - pts[i - 3]).normalized()
			var b := (pts[i + 3] - pts[i]).normalized()
			var turn := absf(a.angle_to(b))
			if turn > 1e-4 and pts[i].distance_to(pts[i - 3]) / turn < MIN_RADIUS:
				for k in range(maxi(i - 14, 1), mini(i + 15, m - 1)):
					loose[k] = true
		if loose.is_empty():
			break
		var src := pts.duplicate()
		for k: int in loose:
			if fixed[k] == 0:
				pts[k] = src[k].lerp((src[k - 1] + src[k + 1]) * 0.5, 0.5)
	return pts


## Douglas-Peucker: the fewest points that stay within eps of the route,
## keeping the ones marked.
static func _simplify(pts: PackedVector2Array, eps: float, keep: Dictionary) -> PackedVector2Array:
	var mark := PackedByteArray()
	mark.resize(pts.size())
	for k: int in keep:
		mark[k] = 1
	var stack := [Vector2i(0, pts.size() - 1)]
	while not stack.is_empty():
		var r: Vector2i = stack.pop_back()
		if r.y - r.x < 2:
			continue
		var far := -1.0
		var at := -1
		for k in range(r.x + 1, r.y):
			if mark[k] == 1:
				at = k
				far = INF
				break
			var d := Geometry2D.get_closest_point_to_segment(pts[k], pts[r.x], pts[r.y]).distance_to(pts[k])
			if d > far:
				far = d
				at = k
		if far > eps:
			mark[at] = 1
			stack.append(Vector2i(r.x, at))
			stack.append(Vector2i(at, r.y))
	var out := PackedVector2Array()
	for k in pts.size():
		if mark[k] == 1:
			out.append(pts[k])
	# straight on through: points in line with their neighbours go
	var clean := PackedVector2Array([out[0]])
	for k in range(1, out.size() - 1):
		var u := (out[k] - clean[clean.size() - 1]).normalized()
		var v := (out[k + 1] - out[k]).normalized()
		if u.dot(v) < 0.9995:
			clean.append(out[k])
	clean.append(out[out.size() - 1])
	return clean


## Rounds each corner with a circular arc of `radius`, or as wide as the
## straights either side leave room for (half of each, all of the first and
## last but a little, and never into the KEEP straight round a crossing).
static func _fillet(pts: PackedVector2Array, radius: float, through: Array) -> PackedVector2Array:
	var m := pts.size()
	if m < 3:
		return pts
	# how much of each straight a curve at each end may take
	var room := PackedFloat32Array()
	room.resize(m - 1)
	for k in m - 1:
		var l := pts[k].distance_to(pts[k + 1])
		room[k] = l * 0.5
		if k == 0 or k == m - 2:
			room[k] = maxf(l - 12.0, 0.0)
			if m == 3:
				room[k] = maxf(l * 0.8 - 12.0, 0.0)
	var out := PackedVector2Array([pts[0]])
	for k in range(1, m - 1):
		var p := pts[k]
		var u := (p - pts[k - 1]).normalized()
		var v := (pts[k + 1] - p).normalized()
		var th := u.angle_to(v)
		if absf(th) < 0.003:
			out.append(p)
			continue
		var tan_half := tan(absf(th) * 0.5)
		var t := minf(radius * tan_half, minf(_room(pts, k - 1, k, room[k - 1], through), _room(pts, k + 1, k, room[k], through)))
		if t < 0.5:
			out.append(p)
			continue
		var r := t / tan_half
		var a := p - u * t
		var b := p + v * t
		# the arc's middle stands off the first tangent point, on the inside of the turn
		var perp := u.orthogonal()
		if perp.dot(v - u) < 0.0:
			perp = -perp
		var c := a + perp * r
		var a0 := (a - c).angle()
		var sweep := (a - c).angle_to(b - c)
		var steps := maxi(2, int(ceil(absf(sweep) * r / 2.5)))
		for q in steps + 1:
			out.append(c + Vector2.from_angle(a0 + sweep * float(q) / steps) * r)
	out.append(pts[m - 1])
	return out


## How much of the straight from pts[k] to pts[at] a curve at `at` may take:
## its share, but none of the KEEP straight round a crossing on it.
static func _room(pts: PackedVector2Array, k: int, at: int, share: float, through: Array) -> float:
	var a := pts[at]
	var b := pts[k]
	for x: Vector2 in through:
		if Geometry2D.get_closest_point_to_segment(x, a, b).distance_to(x) < 1.0:
			return clampf(a.distance_to(x) - KEEP, 0.0, share * 2.0)
	return share
