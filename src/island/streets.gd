class_name Streets
extends Node3D
## Streets on the new island. Each street is a smooth centre line with a graded
## height profile: it follows the land but evens out bumps and keeps slopes
## walkable, and the ground is cut and filled to meet it. Built as one mesh per
## street with asphalt, kerbs, paved pavements and centre dashes. Where streets
## meet, their asphalt stops short and one junction piece joins them, with
## rounded kerbs at the corners.

signal changed
signal added(s: Street)
signal removed(s: Street)
## a street changed kind (see rekind): `pieces` are the streets it is now,
## `old` itself among them when it changed all along its length
signal rekinded(old: Street, pieces: Array)

const SAMPLE := 0.5
const MAX_GRADE := 0.16
const CURB := 0.06
const PAVE := 0.42
const SKIRT := 0.2
# radius of the rounded kerb at street corners
const KERB_R := 1.1
# the farthest a junction's corner starts along a street from where they meet
const MAX_CUT := 2.2
## w: half the width kerb to kerb; median: half the width of the planted
## strip down the middle (avenues, highways), the lanes either side of it;
## verge: no pavements, just a shoulder (highways, which nobody lives along)
const KINDS := {
	"main": {"w": 0.78, "dash": true, "median": 0.0, "verge": false},
	"side": {"w": 0.56, "dash": false, "median": 0.0, "verge": false},
	"avenue": {"w": 1.5, "dash": true, "median": 0.3, "verge": false},
	# grade: a highway keeps to gentle slopes, cutting and banking the land
	# and tunnelling through the hills it can't climb
	"highway": {"w": 1.95, "dash": true, "median": 0.3, "verge": true, "grade": 0.06},
	# a paved walk through a park or green: no cars, only people (see Growth)
	"walk": {"w": 0.7, "dash": false, "median": 0.0, "verge": false},
	# a slip road between a highway and the street flying over it, laid by
	# the town itself (see _refresh_ramps)
	"ramp": {"w": 0.85, "dash": false, "median": 0.0, "verge": true},
}
## a highway's crash barrier (down the middle) and guardrails (along the edges)
const BARRIER := 0.2
const BARRIER_GREY := Color(0.74, 0.73, 0.7)
## how far out past the carriageway's edge the guardrail stands
const RAIL_OUT := 0.22
const RAIL_LO := 0.12
const RAIL_HI := 0.2
const GUARDRAIL := Color(0.72, 0.75, 0.78)
const POST_EVERY := 5.0
const GANTRY_EVERY := 150.0
const SIGN_GREEN := Color(0.12, 0.45, 0.3)
## a highway tunnels where the land stands this far over it (starting where
## there is at least TUNNEL_EDGE over it), for at least TUNNEL_MIN samples
const TUNNEL_COVER := 2.2
const TUNNEL_EDGE := 0.9
const TUNNEL_MIN := 24
## how far a highway's height profile is smoothed either side (samples)
const HIGHWAY_SMOOTH := 24
const TUNNEL_DARK := Color(0.05, 0.05, 0.06)
## a walk's paving, warmer and lighter than a pavement
const PAVING := Color(0.86, 0.8, 0.7)
## the kinds a player can draw, with what a metre costs compared with a street
const DRAWN := {"main": 1.0, "avenue": 2.5, "highway": 4.0}
## the kinds a road can be changed between with the Road tool's Change mode,
## plainest first (a grown back street can be raised to a street and back)
const GRADES := ["side", "main", "avenue", "highway"]
## a changed stretch closer than this many samples to a street's end takes the end too
const MIN_PIECE := 8

var land: Land
var material: Material
var streets: Array = []
var _meshes := {}
var _next_id := 1
var _links := {}
var _links_dirty := true
var _junctions: Array = []
var _junctions_dirty := true
## [street id, street id] -> [fingerprint, meetings] (see _meetings_of)
var _meet_cache := {}
# the junctions last worked out, by what they were made from (see _meets_sig)
var _shaped := {}
## where street meets highway, see _crossing: (id, id) -> [hash, result]
var _cross_cache := {}
## this builder's mark on the streets it makes, so keys never clash in co-op
static var tag := ""
# streets being laid out along their length: id -> seconds since placed
var _laying := {}
const LAY_TIME := 0.8
# a bridge's deck stands at least this high over the water, and runs on this
# many samples past the water onto each bank (where its abutments stand)
const DECK := 0.9
const BANK := 8
const DECK_DEPTH := 0.32
const CONCRETE := Color(0.8, 0.78, 0.74)
# a quay: how far out past the pavement the water must be, and how deep the
# water is dredged along its wall
## how high a street's deck stands over a highway it flies over
const CLEARANCE := 2.5
const QUAY_PROBE := 2.9
const QUAY_DEPTH := -0.9
const QUAY_STONE := Color(0.74, 0.69, 0.6)
# streets whose mesh needs remaking, a few per frame: id -> Street
var _pending := {}


class Street:
	var id := 0
	## stable across saves and between co-op builders (ids are only this session's)
	var key := ""
	var kind := "main"
	## laid by the streets themselves (an interchange's ramps): never saved,
	## worked out again from the streets that are, from these points
	var auto := false
	var src := PackedVector2Array()
	var pts := PackedVector2Array()
	var ys := PackedFloat32Array()
	var lo := Vector2.ZERO
	var hi := Vector2.ZERO
	# where junction corners take over the pavements: side -> (from, to) sample ranges
	var cuts := {}
	## where it crosses water on a bridge: (from, to) sample ranges
	var spans := PackedVector2Array()
	## where it flies over a highway it crosses without joining it: (from, to)
	## sample ranges, the deck from abutment to abutment (see _flyovers)
	var overs := PackedVector2Array()
	## where a highway runs through a hill in a tunnel: (from, to) sample
	## ranges, portal to portal (see _tunnels)
	var tunnels := PackedVector2Array()
	## per sample, which sides run along the water on a stone quay (1 left, 2 right)
	var quay := PackedByteArray()
	## its bus stops: (sample index, side), set once it is built (see BusStops)
	var stops := PackedVector2Array()
	# its segments by cell (see _cells), and the points they were found for
	const GRID := 6.0
	var _grid := {}
	var _grid_sig := 0
	var _grid_n := -1

	func w() -> float:
		return Streets.KINDS[kind].w

	func reach() -> float:
		return w() + Streets.PAVE

	## A street that matters more than a back street: busier, with shops.
	func major() -> bool:
		return kind == "main" or kind == "avenue"

	func update_bounds() -> void:
		lo = Vector2(INF, INF)
		hi = Vector2(-INF, -INF)
		for p in pts:
			lo = lo.min(p)
			hi = hi.max(p)

	func near_box(p: Vector2, r: float) -> bool:
		return p.x > lo.x - r and p.y > lo.y - r and p.x < hi.x + r and p.y < hi.y + r

	## Distance from p to the centre line, with the street height there.
	func closest(p: Vector2) -> Vector3:
		var best := INF
		var by := 0.0
		var bs := 0.0
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var ab := b - a
			var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
			var d := p.distance_to(a + ab * t)
			if d < best:
				best = d
				by = lerpf(ys[i], ys[i + 1], t)
				bs = i + t
		return Vector3(best, by, bs)

	## Whether p lies within `r` of the centre line (only the stretches of it
	## near p are looked at, see segments_near).
	func within(p: Vector2, r: float) -> bool:
		var g := _cells()
		var c0 := Vector2i(((p - Vector2(r, r)) / GRID).floor())
		var c1 := Vector2i(((p + Vector2(r, r)) / GRID).floor())
		for cy in range(c0.y, c1.y + 1):
			for cx in range(c0.x, c1.x + 1):
				var segs: Variant = g.get(Vector2i(cx, cy))
				if segs == null:
					continue
				for k: int in segs:
					var a := pts[k]
					var ab := pts[k + 1] - a
					var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
					if p.distance_to(a + ab * t) < r:
						return true
		return false

	## The segments (k: from pts[k] to pts[k + 1]) that may reach into the box
	## lo..hi, in order along the street, each once.
	func segments_near(lo_: Vector2, hi_: Vector2) -> PackedInt32Array:
		var g := _cells()
		var out := PackedInt32Array()
		var c0 := Vector2i((lo_ / GRID).floor())
		var c1 := Vector2i((hi_ / GRID).floor())
		var many := false
		for cy in range(c0.y, c1.y + 1):
			for cx in range(c0.x, c1.x + 1):
				var segs: Variant = g.get(Vector2i(cx, cy))
				if segs != null:
					many = many or not out.is_empty()
					out.append_array(PackedInt32Array(segs))
		if many:
			out.sort()
			var k := 0
			for i in out.size():
				if i == 0 or out[i] != out[k - 1]:
					out[k] = out[i]
					k += 1
			out.resize(k)
		return out

	## Like closest(), but only looking within `r` of p (much quicker on a
	## long street): x is INF when no part of it comes that near.
	func closest_near(p: Vector2, r: float) -> Vector3:
		var best := INF
		var by := 0.0
		var bs := 0.0
		for i in segments_near(p - Vector2(r, r), p + Vector2(r, r)):
			var a := pts[i]
			var b := pts[i + 1]
			var ab := b - a
			var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
			var d := p.distance_to(a + ab * t)
			if d < best:
				best = d
				by = lerpf(ys[i], ys[i + 1], t)
				bs = i + t
		if best > r:
			best = INF
		return Vector3(best, by, bs)

	## A fingerprint of its course and width (cached with the cells).
	func shape_sig() -> int:
		_cells()
		return hash([_grid_sig, kind])

	## The street's segments by the GRID-metre cells their boxes cover, worked
	## out again whenever its points change.
	func _cells() -> Dictionary:
		var sig := hash(pts)
		if sig == _grid_sig and _grid_n == pts.size():
			return _grid
		_grid_sig = sig
		_grid_n = pts.size()
		_grid = {}
		for k in pts.size() - 1:
			var a := pts[k]
			var b := pts[k + 1]
			var c0 := Vector2i((a.min(b) / GRID).floor())
			var c1 := Vector2i((a.max(b) / GRID).floor())
			for cy in range(c0.y, c1.y + 1):
				for cx in range(c0.x, c1.x + 1):
					var key := Vector2i(cx, cy)
					if _grid.has(key):
						_grid[key].append(k)
					else:
						_grid[key] = [k]
		return _grid


# ------------------------------------------------------------------ building streets

## Turns a finger stroke into a street. Returns it, or null if too short.
func add_stroke(raw: PackedVector2Array, kind := "main") -> Street:
	var pts := _resample(raw, 1.2)
	if pts.size() < 2 or _length(pts) < 2.5:
		return null
	if SMOOTHING.has(kind):
		# a hand-drawn line wobbles: fine for a street, but an avenue sweeps
		# along it in easy curves and a highway in long, wide ones
		pts = _relax(pts, SMOOTHING[kind])
	pts = _chaikin(_chaikin(pts))
	# ends that stop just short of another street join it
	pts = _snap_ends(pts)
	pts = _resample(pts, SAMPLE)
	if pts.size() < 3:
		return null
	var s := _new_street()
	s.kind = kind
	s.pts = pts
	return _lay(s)


## Lays a highway of the map's network (see HighwayPlan) along exactly the
## line given, already smooth, named `key`. The back streets and walks in its
## way stop short of it, as they would of any highway.
func lay_highway(line: PackedVector2Array, key: String) -> Street:
	var pts := _resample(line, SAMPLE)
	if pts.size() < 3:
		return null
	var s := _new_street()
	s.key = key
	s.kind = "highway"
	s.pts = pts
	_lay(s)
	_clear_off(s)
	return s


## Takes up every highway (and their interchanges), easing the ground they
## were cut and banked into back to how the land lay, for a new network. The
## streets that flew over them come back down.
func clear_highways() -> void:
	var gone: Array = streets.filter(func(o): return o.kind == "highway")
	if gone.is_empty():
		return
	var flew := {}
	for h: Street in gone:
		for o: Street in _touching(h):
			if o.kind != "highway" and not o.auto and _flies(o, h):
				flew[o] = true
	for h: Street in gone:
		land.renature(h.pts, h.w() + PAVE + 3.0)
	for r: Street in streets:
		if r.kind == "ramp":
			land.renature(r.pts, r.w() + PAVE + 5.0)
	for h: Street in gone:
		_take_up(h)
	_refresh_ramps()
	for o: Street in flew:
		if o in streets:
			_grade(o)
			_conform(o)
			_reconform_near(o)
			_build_later(o)
	_junctions_dirty = true
	changed.emit()


## Lays a new street along its points: graded, the ground shaped to it, and
## everything round it made to fit.
func _lay(s: Street) -> Street:
	s.update_bounds()
	_grade(s)
	streets.append(s)
	_junctions_dirty = true
	_conform(s)
	if s.kind == "highway":
		# streets it crosses go up and over it (as does a highway with a
		# later key: one with an earlier key, it goes over itself)
		for o in _touching(s):
			if _flies(o, s) and (o.kind != "highway" or o.key > s.key):
				_grade(o)
				_conform(o)
		# and the banks their ramps stand on stop at its shoulders
		_lower_onto(s)
	# the streets round it settle onto it over the next few frames (a long
	# road through a big town touches a hundred or more)
	_lower_later.append([s, _touching(s)])
	_conform_junctions(s)
	_laying[s.id] = 0.0
	_build(s)
	for o in _touching(s):
		_build_later(o)
	added.emit(s)
	_refresh_ramps()
	changed.emit()
	return s


## Removes street within `radius` of p, splitting streets that pass through
## (but for the map's highways, with `spare_highways`).
func erase_at(p: Vector2, radius: float, spare_highways := false) -> bool:
	var hit := false
	for s in streets.duplicate():
		# an interchange's ramps go with the street that has them
		if s.auto or not s.near_box(p, radius + s.reach()) or (spare_highways and s.kind == "highway"):
			continue
		var pieces: Array = []
		var cur := PackedVector2Array()
		var cy := PackedFloat32Array()
		var cut := false
		for i in s.pts.size():
			if s.pts[i].distance_to(p) < radius:
				cut = true
				if cur.size() >= 3:
					pieces.append([cur, cy])
				cur = PackedVector2Array()
				cy = PackedFloat32Array()
			else:
				cur.append(s.pts[i])
				cy.append(s.ys[i])
		if not cut:
			continue
		hit = true
		if cur.size() >= 3:
			pieces.append([cur, cy])
		var touching := _touching(s)
		var flew := touching.filter(func(o): return _flies(o, s))
		_remove(s)
		for pc in pieces:
			var ns := _new_street()
			ns.kind = s.kind
			ns.pts = pc[0]
			ns.ys = pc[1]
			ns.update_bounds()
			ns.spans = _bridges(ns)
			ns.quay = _quays(ns)
			streets.append(ns)
			_junctions_dirty = true
			_build(ns)
			added.emit(ns)
		for o in flew:
			if o in streets:
				_grade(o)
				_conform(o)
		for o in touching:
			if o in streets:
				_build_later(o)
	if hit:
		_refresh_ramps()
		changed.emit()
	return hit


## After the ground was reshaped under some streets, re-grade and re-lay them.
func regrade_in(lo: Vector2, hi: Vector2) -> void:
	var moved: Array = []
	for s in streets:
		if s.hi.x < lo.x or s.hi.y < lo.y or s.lo.x > hi.x or s.lo.y > hi.y:
			continue
		_grade(s)
		_conform(s)
		moved.append(s)
	_junctions_dirty = true
	for s in moved:
		_reconform_near(s)
		_conform_junctions(s)
	for s in moved:
		_build(s)
		for o in _touching(s):
			if not o in moved:
				_build_later(o)
	_refresh_ramps()


func _remove(s: Street, quiet := false) -> void:
	_forget(s)
	streets.erase(s)
	rev += 1
	_junctions_dirty = true
	if quiet:
		_links_dirty = true
	else:
		removed.emit(s)
	if _meshes.has(s.id):
		_meshes[s.id].queue_free()
		_meshes.erase(s.id)
	_laying.erase(s.id)
	_pending.erase(s.id)


## Drops what was remembered about where s crosses others.
func _forget(s: Street) -> void:
	for k: Vector2i in _cross_cache.keys():
		if k.x == s.id or k.y == s.id:
			_cross_cache.erase(k)


## bumped whenever a street is added, taken up or changed
var rev := 0


func _init() -> void:
	changed.connect(_touched)
	removed.connect(func(_s): _touched())
	added.connect(func(_s): _touched())
	rekinded.connect(func(_s, _p): _touched())


func _touched() -> void:
	_links_dirty = true
	rev += 1


func clear() -> void:
	for s in streets.duplicate():
		_remove(s)
	_next_id = 1


## Height profile: the land's, smoothed, kept off the sea, never steeper than
## MAX_GRADE, and pinned to other streets' heights where it crosses or joins them.
func _grade(s: Street) -> void:
	var n := s.pts.size()
	var ys := PackedFloat32Array()
	ys.resize(n)
	for i in n:
		ys[i] = maxf(land.height_at(s.pts[i].x, s.pts[i].y), 0.14)
	for pass_i in 8:
		var src := ys.duplicate()
		for i in range(1, n - 1):
			ys[i] = src[i - 1] * 0.25 + src[i] * 0.5 + src[i + 1] * 0.25
	var grade: float = KINDS[s.kind].get("grade", MAX_GRADE)
	if KINDS[s.kind].has("grade"):
		# a highway evens out the hills and dips over a long stretch
		for pass_i in 3:
			ys = _smoothed(ys, HIGHWAY_SMOOTH)
	_limit(s.pts, ys, {}, grade)
	# over water a bridge: its deck level from bank to bank, arching a little
	# over a long crossing, the ramps up to it graded like any street
	s.spans = _bridges(s)
	var pins := {}
	for sp in s.spans:
		var a := int(sp.x)
		var b := int(sp.y)
		var deck := maxf(DECK, maxf(ys[a], ys[b]))
		var arch := minf((b - a) * SAMPLE * 0.012, 0.35)
		for i in range(a, b + 1):
			ys[i] = deck + arch * sin(PI * float(i - a) / maxf(b - a, 1))
			pins[i] = ys[i]
	# over a highway it crosses, a deck at a lorry's height over the
	# carriageway, the ramps up to it graded like any street
	s.overs = PackedVector2Array()
	for fly in _flyovers(s):
		var o: Street = fly.hw
		var deck := _yf(o, fly.fo) + CLEARANCE
		s.overs.append(Vector2(fly.a, fly.b))
		for i in range(int(ceil(fly.a)), int(floor(fly.b)) + 1):
			ys[i] = deck
			pins[i] = deck
	if not pins.is_empty():
		_limit(s.pts, ys, pins, grade)
	# meet other streets at their height, easing the change in over a few metres
	for o in streets:
		if o == s or not _boxes_overlap(s, o) or _flies(s, o):
			continue
		var best := Vector3(INF, 0, 0)
		var bi := -1
		var meet: float = o.w() + 0.2 + (s.w() + 0.1 if _merges(s, o) else 0.0)
		var span := _near_span(s, o, meet)
		for i in range(span.x, span.y + 1):
			# (only samples close enough to meet it can, and most are far)
			var c: Vector3 = o.closest_near(s.pts[i], meet)
			if c.x >= meet:
				continue
			if c.x < best.x:
				best = c
				bi = i
		if bi < 0 or best.x > meet:
			continue
		var shift: float = best.y - ys[bi]
		for i in n:
			var d := absf(i - bi) * SAMPLE
			ys[i] += shift * clampf(1.0 - d / 9.0, 0.0, 1.0)
		pins[bi] = best.y
	if not pins.is_empty():
		_limit(s.pts, ys, pins, grade)
	s.ys = ys
	s.tunnels = _tunnels(s) if s.kind == "highway" else PackedVector2Array()


## A running mean of ys over r samples either side (the ends held).
static func _smoothed(ys: PackedFloat32Array, r: int) -> PackedFloat32Array:
	var n := ys.size()
	var sum := PackedFloat64Array()
	sum.resize(n + 1)
	for i in n:
		sum[i + 1] = sum[i] + ys[i]
	var out := ys.duplicate()
	for i in range(1, n - 1):
		var k := mini(r, mini(i, n - 1 - i))
		out[i] = (sum[i + k + 1] - sum[i - k]) / float(2 * k + 1)
	return out


## Where a highway runs under a hill: each run of samples with the land at
## least TUNNEL_EDGE over the road that somewhere has TUNNEL_COVER over it,
## long enough to be worth a tunnel, off bridges and decks and clear of the
## ends. A tunnel it already has stays while the hill over it does (its
## mouths are cut back to the road, which mustn't shorten it).
func _tunnels(s: Street) -> PackedVector2Array:
	var n := s.pts.size()
	var cover := PackedFloat32Array()
	cover.resize(n)
	for i in n:
		cover[i] = land.height_at(s.pts[i].x, s.pts[i].y) - s.ys[i]
	var keep := PackedByteArray()
	keep.resize(n)
	for t in s.tunnels:
		var m := clampi(int((t.x + t.y) * 0.5), 0, n - 1)
		if t.y < n and cover[m] > TUNNEL_EDGE:
			for i in range(int(t.x), int(t.y) + 1):
				keep[i] = 1
	var out := PackedVector2Array()
	var i := 4
	while i < n - 4:
		if cover[i] <= TUNNEL_EDGE and not keep[i]:
			i += 1
			continue
		var j := i
		var deep := false
		while j + 1 < n - 4 and (cover[j + 1] > TUNNEL_EDGE or keep[j + 1]):
			j += 1
		for k in range(i, j + 1):
			deep = deep or cover[k] > TUNNEL_COVER or keep[k]
		var clear := true
		for c in s.spans + s.overs:
			clear = clear and (c.y < i or c.x > j)
		if deep and clear and j - i >= TUNNEL_MIN:
			out.append(Vector2(i, j))
		i = j + 1
	return out


## Where a street crosses water: each run of samples over water, carried on
## BANK samples onto the land either side.
func _bridges(s: Street) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := s.pts.size()
	var i := 0
	while i < n:
		if land.height_at(s.pts[i].x, s.pts[i].y) >= 0.05:
			i += 1
			continue
		var j := i
		while j + 1 < n and land.height_at(s.pts[j + 1].x, s.pts[j + 1].y) < 0.05:
			j += 1
		if j - i >= 2:
			var a := float(maxi(0, i - BANK))
			var b := float(mini(n - 1, j + BANK))
			if not out.is_empty() and a <= out[out.size() - 1].y:
				out[out.size() - 1] = Vector2(out[out.size() - 1].x, b)
			else:
				out.append(Vector2(a, b))
		i = j + 1
	return out


## Cuts and fills the ground to meet a street, except under its bridges;
## along the water, a quay wall with the water dredged deep right up to it.
func _conform(s: Street) -> void:
	s.quay = _quays(s)
	var start := 0
	var n := s.pts.size()
	var ends := s.spans.duplicate()
	ends.append_array(s.overs)
	ends.append_array(s.tunnels)
	var by_start := Array(ends)
	by_start.sort_custom(func(a: Vector2, b: Vector2): return a.x < b.x)
	ends = PackedVector2Array(by_start)
	ends.append(Vector2(n, n))
	for sp in ends:
		var stop := mini(int(sp.x), n - 1)
		if stop - start >= 1:
			# a ramp's bank, up to a street flying over, eases out further
			land.conform(s.pts.slice(start, stop + 1), s.ys.slice(start, stop + 1), s.w() + PAVE + 0.15, 4.5 if s.kind == "ramp" else 2.6)
		start = maxi(start, int(sp.y))
	for bit in [1, 2]:
		var side := -1.0 if bit == 1 else 1.0
		var run := PackedVector2Array()
		var deep := PackedFloat32Array()
		for i in n + 1:
			if i < n and s.quay[i] & bit:
				run.append(s.pts[i] + _side(s, i) * side * (s.w() + PAVE + 1.45))
				deep.append(QUAY_DEPTH)
				continue
			if run.size() >= 2:
				land.conform(run, deep, 1.35, 0.0, true)
			run = PackedVector2Array()
			deep = PackedFloat32Array()


## Which sides of each sample run along the water (and get a quay): open
## water just past where the street's banks would ease out, off any bridge.
func _quays(s: Street) -> PackedByteArray:
	var out := PackedByteArray()
	var n := s.pts.size()
	out.resize(n)
	if KINDS[s.kind].verge:
		return out
	var reach := s.w() + PAVE + QUAY_PROBE
	for i in n:
		if _in_cuts(s.spans, float(i)):
			continue
		var nrm := _side(s, i)
		for bit in [1, 2]:
			var q: Vector2 = s.pts[i] + nrm * (-1.0 if bit == 1 else 1.0) * reach
			if land.height_at(q.x, q.y) < -0.05:
				out[i] |= bit
	# a lone sample or two is just a wiggle in the shore
	for bit in [1, 2]:
		var i := 0
		while i < n:
			if not out[i] & bit:
				i += 1
				continue
			var j := i
			while j + 1 < n and out[j + 1] & bit:
				j += 1
			if j - i < 6:
				for k in range(i, j + 1):
					out[k] &= ~bit
			i = j + 1
	return out


## Keeps every step within MAX_GRADE, holding pinned samples at their height.
static func _limit(pts: PackedVector2Array, ys: PackedFloat32Array, pins: Dictionary, grade := MAX_GRADE) -> void:
	var n := pts.size()
	for it in 4:
		for i in pins:
			ys[i] = pins[i]
		for i in range(1, n):
			if pins.has(i):
				continue
			var step := grade * pts[i].distance_to(pts[i - 1])
			ys[i] = clampf(ys[i], ys[i - 1] - step, ys[i - 1] + step)
		for i in range(n - 2, -1, -1):
			if pins.has(i):
				continue
			var step := grade * pts[i].distance_to(pts[i + 1])
			ys[i] = clampf(ys[i], ys[i + 1] - step, ys[i + 1] + step)


func _boxes_overlap(a: Street, b: Street) -> bool:
	var r := a.reach() + b.reach()
	return not (a.hi.x + r < b.lo.x or b.hi.x + r < a.lo.x or a.hi.y + r < b.lo.y or b.hi.y + r < a.lo.y)


## The samples of s (first, last) that may come within `r` of o: none
## (an empty range) when no part of s comes near o's box.
static func _near_span(s: Street, o: Street, r: float) -> Vector2i:
	var pad := Vector2.ONE * (r + 0.1)
	var near := s.segments_near(o.lo - pad, o.hi + pad)
	if near.is_empty():
		return Vector2i(0, -1)
	return Vector2i(near[0], mini(near[near.size() - 1] + 1, s.pts.size() - 1))


# while every pair of streets is looked over: each one's box grown by its
# reach (lo x, lo y, hi x, hi y), and its shape_sig() by id
var _pair_box := PackedFloat32Array()
var _sigs := {}


func _begin_pairs() -> void:
	_pair_box.resize(streets.size() * 4)
	for i in streets.size():
		var st: Street = streets[i]
		var r := st.reach()
		_pair_box[i * 4] = st.lo.x - r
		_pair_box[i * 4 + 1] = st.lo.y - r
		_pair_box[i * 4 + 2] = st.hi.x + r
		_pair_box[i * 4 + 3] = st.hi.y + r
		_sigs[st.id] = st.shape_sig()


func _end_pairs() -> void:
	_sigs.clear()


## _boxes_overlap() of streets[i] and streets[k], from _begin_pairs().
func _pair_near(i: int, k: int) -> bool:
	var a := i * 4
	var b := k * 4
	return not (_pair_box[a + 2] < _pair_box[b] or _pair_box[b + 2] < _pair_box[a] or _pair_box[a + 3] < _pair_box[b + 1] or _pair_box[b + 3] < _pair_box[a + 1])


func _touching(s: Street) -> Array:
	var out: Array = []
	for o in streets:
		if o != s and _boxes_overlap(s, o):
			out.append(o)
	return out


func _reconform_near(s: Street) -> void:
	for o in _touching(s):
		_reconform_one(s, o)


## The ground taken down to o where it rises over o's edges near s.
func _reconform_one(s: Street, o: Street) -> void:
	# only the stretch of it near s (a long highway's far end is as it was)
	# (as far as the banks of s can reach, its ramps' eased out widest)
	var r: float = s.reach() + o.reach() + 4.5 + Land.STEP + 6.0
	var a := -1
	var b := -1
	var span := _near_span(o, s, r)
	for i in range(span.x, span.y + 1):
		if s.near_box(o.pts[i], r) and s.within(o.pts[i], r):
			if a < 0:
				a = i
			b = i
	if a < 0:
		return
	a = maxi(a - 1, 0)
	b = mini(b + 1, o.pts.size() - 1)
	if b - a < 1:
		return
	# a grid step past the pavement too, so the ground can't rise over its edge in between
	_lower_onto(o, a, b)


## Takes the ground down to a street wherever it rises over its edges (as a
## neighbour's banks can), except over its tunnels.
## Only samples a to b, when given.
func _lower_onto(s: Street, a := 0, b := -1) -> void:
	var start := a
	var n := s.pts.size() if b < 0 else b + 1
	for t in s.tunnels + PackedVector2Array([Vector2(n, n)]):
		if t.y <= start:
			continue
		var stop := mini(int(t.x), n - 1)
		if stop - start >= 1:
			land.conform(s.pts.slice(start, stop + 1), s.ys.slice(start, stop + 1), s.w() + PAVE + 0.15 + Land.STEP * 0.75, 0.0, true)
		start = maxi(start, int(t.y))


## how far short of another street a stroke may start or end and still join it
const SNAP := 2.5


func _snap_ends(pts: PackedVector2Array) -> PackedVector2Array:
	for end in [0, 1]:
		if pts.size() < 2:
			break
		var p := pts[0] if end == 0 else pts[pts.size() - 1]
		var best: Street = null
		var bd := INF
		for o: Street in streets:
			# anywhere on the other street's paving, or a few metres short of it
			var reach := o.reach() + SNAP
			if not o.near_box(p, reach):
				continue
			var c: Vector3 = o.closest(p)
			if c.x < reach and c.x - o.reach() < bd:
				bd = c.x - o.reach()
				best = o
		if best == null:
			continue
		var c2: Vector3 = best.closest(p)
		if c2.x < 0.3:
			continue
		var i := int(c2.z)
		var n := best.pts.size()
		var on := best.pts[mini(i, n - 1)].lerp(best.pts[mini(i + 1, n - 1)], c2.z - i)
		# close to the other street's own end: carry straight on from it
		if on.distance_to(best.pts[0]) < SNAP:
			on = best.pts[0]
		elif on.distance_to(best.pts[n - 1]) < SNAP:
			on = best.pts[n - 1]
		# the stretch of the stroke still over the other street (or just
		# short of it) goes, so the new street meets it squarely, with no kink
		var drop := 0
		while drop < pts.size() - 2:
			var q := pts[drop] if end == 0 else pts[pts.size() - 1 - drop]
			if best.closest(q).x > best.reach() + 0.6:
				break
			drop += 1
		if end == 0:
			pts = pts.slice(drop)
			pts.insert(0, on)
		else:
			pts = pts.slice(0, pts.size() - drop)
			pts.append(on)
	return pts


# ------------------------------------------------------------------ polyline helpers

static func _length(pts: PackedVector2Array) -> float:
	var l := 0.0
	for i in pts.size() - 1:
		l += pts[i].distance_to(pts[i + 1])
	return l


## How much drawn roads are evened out, by kind: passes of easing each point
## (1.2 m apart) towards its neighbours; the wobbles smoothed away grow with
## the square root (about 3 m for an avenue, 6 m for a highway).
const SMOOTHING := {"avenue": 25, "highway": 90}


## Eases each point but the ends towards the middle of its neighbours,
## `passes` times: wobbles melt away, the overall line stays where it was drawn.
static func _relax(pts: PackedVector2Array, passes: int) -> PackedVector2Array:
	var out := pts.duplicate()
	for k in passes:
		var src := out.duplicate()
		for i in range(1, src.size() - 1):
			out[i] = src[i].lerp((src[i - 1] + src[i + 1]) * 0.5, 0.5)
	return out


## Evenly spaced points along the line.
static func _resample(pts: PackedVector2Array, step: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if pts.size() < 2:
		return pts
	out.append(pts[0])
	var carry := 0.0
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var seg := a.distance_to(b)
		var t := step - carry
		while t <= seg:
			out.append(a.lerp(b, t / seg))
			t += step
		carry = seg - (t - step)
	if out[out.size() - 1].distance_to(pts[pts.size() - 1]) > step * 0.3:
		out.append(pts[pts.size() - 1])
	else:
		out[out.size() - 1] = pts[pts.size() - 1]
	return out


## Corner cutting: rounds the drawn line into gentle curves, ends kept.
static func _chaikin(pts: PackedVector2Array) -> PackedVector2Array:
	if pts.size() < 3:
		return pts
	var out := PackedVector2Array([pts[0]])
	for i in pts.size() - 1:
		out.append(pts[i].lerp(pts[i + 1], 0.25))
		out.append(pts[i].lerp(pts[i + 1], 0.75))
	out.append(pts[pts.size() - 1])
	return out


# ------------------------------------------------------------------ mesh

func _process(delta: float) -> void:
	var start := Time.get_ticks_usec()
	for id in _laying.keys():
		var before: float = _laying[id]
		_laying[id] += delta
		var s: Street = null
		for o in streets:
			if o.id == id:
				s = o
		if s == null or _laying[id] >= LAY_TIME:
			_laying.erase(id)
			if s:
				_build(s)
				# the junctions it makes can now take over the other streets' ends
				for o in _touching(s):
					_build_later(o)
		# lay it out in a few steps rather than remaking it every frame
		elif int(before / 0.1) != int(_laying[id] / 0.1):
			_build(s)
	# the streets round a new one settling onto it, a few a frame
	while not _lower_later.is_empty() and Time.get_ticks_usec() - start < FrameBudget.cap(3000):
		_lower_step()
	for id in _pending.keys():
		if Time.get_ticks_usec() - start > FrameBudget.cap(3000):
			break
		var s: Street = _pending[id]
		_pending.erase(id)
		if s in streets:
			_build(s)


# [street, the streets round it still to settle onto it]
var _lower_later: Array = []


func _lower_step() -> void:
	var job: Array = _lower_later[0]
	var round_it: Array = job[1]
	if round_it.is_empty() or not job[0] in streets:
		_lower_later.pop_front()
		return
	var o: Street = round_it.pop_back()
	if o in streets:
		_reconform_one(job[0], o)


## Finishes laying and remaking every street now (tests, loading).
func flush() -> void:
	while not _lower_later.is_empty():
		_lower_step()
	if not _laying.is_empty():
		for id in _laying:
			var s := by_id(id)
			if s:
				for o in _touching(s) + [s]:
					_pending[o.id] = o
		_laying.clear()
	for id in _pending.keys():
		_build(_pending[id])
	_pending.clear()
	for st in streets:
		if st.cuts.is_empty():
			_build(st)


## Whether the street is still being laid out or waiting for its mesh.
func is_settling(s: Street) -> bool:
	return _laying.has(s.id) or _pending.has(s.id)


func _build_later(s: Street) -> void:
	_pending[s.id] = s


class MeshBuf:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()

	## A flat four-sided piece facing the side of `hint`.
	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, e: float, hint: Vector3) -> void:
		var nrm := (c - a).cross(d - b)
		if nrm.length_squared() < 1e-10:
			return
		nrm = nrm.normalized()
		if nrm.dot(hint) < 0.0:
			nrm = -nrm
		var base := verts.size()
		verts.append_array([a, b, c, d])
		for k in 4:
			norms.append(nrm)
			cols.append(col)
			uvs.append(Vector2(e, 0.0))
		# Godot's front faces wind clockwise seen from the front
		if (b - a).cross(c - a).dot(nrm) > 0.0:
			idx.append_array([base, base + 2, base + 1, base, base + 3, base + 2])
		else:
			idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])

	## A lidded box with no floor: size.x along `ax`, size.y up, size.z along `az`.
	func box(c: Vector3, size: Vector3, ax: Vector3, az: Vector3, col: Color) -> void:
		var x := ax * size.x * 0.5
		var z := az * size.z * 0.5
		var lo := c + Vector3.DOWN * size.y * 0.5
		var hi := c + Vector3.UP * size.y * 0.5
		for f: Vector3 in [x, -x, z, -z]:
			var g := z if f == x or f == -x else x
			quad(lo + f - g, lo + f + g, hi + f + g, hi + f - g, col, 0.0, f)
		quad(hi - x - z, hi + x - z, hi + x + z, hi - x + z, col, 0.0, Vector3.UP)

	## A stretch of carriageway whose markings the city shader paints: a-b
	## across the start (a on the left kerb), c-d across the end. Colour alpha
	## carries the way across (0 left kerb, 1 right), UV.y the way along.
	func road(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, e: float, s0: float, s1: float) -> void:
		var nrm := (c - a).cross(d - b)
		if nrm.length_squared() < 1e-10:
			return
		nrm = nrm.normalized()
		if nrm.y < 0.0:
			nrm = -nrm
		var base := verts.size()
		verts.append_array([a, b, c, d])
		for k in 4:
			norms.append(nrm)
		cols.append_array([Color(col, 0.0), Color(col, 1.0), Color(col, 1.0), Color(col, 0.0)])
		uvs.append_array([Vector2(e, s0), Vector2(e, s0), Vector2(e, s1), Vector2(e, s1)])
		if (b - a).cross(c - a).dot(nrm) > 0.0:
			idx.append_array([base, base + 2, base + 1, base, base + 3, base + 2])
		else:
			idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])

	## `level` shades it as if flat, so a fan of slightly tilted pieces reads as one surface.
	func tri(a: Vector3, b: Vector3, c: Vector3, col: Color, e: float, level := false) -> void:
		var nrm := (b - a).cross(c - a)
		if nrm.length_squared() < 1e-10:
			return
		nrm = nrm.normalized()
		if nrm.y < 0.0:
			nrm = -nrm
		var face := nrm
		if level:
			nrm = Vector3.UP
		var base := verts.size()
		verts.append_array([a, b, c])
		for k in 3:
			norms.append(nrm)
			cols.append(col)
			uvs.append(Vector2(e, 0.0))
		if (b - a).cross(c - a).dot(face) > 0.0:
			idx.append_array([base, base + 2, base + 1])
		else:
			idx.append_array([base, base + 1, base + 2])


func _build(s: Street) -> void:
	var n := s.pts.size()
	var upto := float(n - 1)
	if _laying.has(s.id):
		var t: float = clampf(_laying[s.id] / LAY_TIME, 0.0, 1.0)
		upto = clampf((n - 1) * (1.0 - pow(1.0 - t, 3.0)), 1.0, n - 1)
	var w := s.w()
	var buf := MeshBuf.new()
	var asphalt := Palette.ASPHALT.darkened(0.05) if s.kind != "side" else Palette.ASPHALT
	var walk := s.kind == "walk"
	var median: float = KINDS[s.kind].median
	var verge: bool = KINDS[s.kind].verge
	var flyovers := _flyovers(s)
	s.overs = PackedVector2Array()
	for fly in flyovers:
		s.overs.append(Vector2(fly.a, fly.b))
	# where junction corners take over this street's pavements, per side,
	# and where a junction's own asphalt takes over from this street's
	var cuts := {-1.0: PackedVector2Array(), 1.0: PackedVector2Array()}
	var skip := PackedVector2Array()
	var last_i := int(upto)
	if not _laying.has(s.id):
		for jn in junctions():
			var mine := false
			var settled := true
			for arm in jn.arms:
				mine = mine or arm.st == s
				settled = settled and not _laying.has(arm.st.id)
			if not mine or not settled:
				continue
			for arm in jn.arms:
				if arm.st != s:
					continue
				skip.append(Vector2(minf(arm.f, arm.f_end), maxf(arm.f, arm.f_end)))
				for q in 2:
					if arm.cut[q] <= 0.0:
						continue
					var fc: float = arm.f + arm.sgn * arm.cut[q] / SAMPLE
					cuts[arm.sgn * (-1.0 if q == 0 else 1.0)].append(Vector2(minf(arm.f, fc), maxf(arm.f, fc)))
			if jn.owner == s.id:
				_build_junction(jn, buf)
		_overlap_cuts(s, cuts)
	# which rows to keep: every bend, slope change and pavement gap; straight even runs collapse
	var rows := {0.0: true, upto: true}
	var last := 0
	for i in range(1, last_i):
		var d0 := (s.pts[i] - s.pts[last]).normalized()
		var d1 := (s.pts[i + 1] - s.pts[i]).normalized()
		var bend := absf(d0.angle_to(d1)) > 0.08
		var grade_change := absf((s.ys[i + 1] - s.ys[i]) - (s.ys[i] - s.ys[i - 1])) > 0.007
		if bend or grade_change or (i - last) * SAMPLE >= 10.0:
			rows[float(i)] = true
			last = i
	for i in range(1, mini(s.quay.size(), last_i + 1)):
		if s.quay[i] != s.quay[i - 1]:
			rows[float(i)] = true
	for list in [cuts[-1.0], cuts[1.0], skip, s.spans, s.overs, s.tunnels]:
		for c in list:
			for f in [c.x, c.y]:
				if f > 0.0 and f < upto:
					rows[f] = true
	# where each bridge's water begins and ends, so its sides change there
	for c in s.spans:
		for f in [c.x + BANK, c.y - BANK]:
			if f > 0.0 and f < upto:
				rows[f] = true
	var styles := BridgeGen.styles(s)
	if upto >= n - 1:
		s.cuts = cuts
	var fs: Array = rows.keys()
	fs.sort()
	var pave := Palette.SIDEWALK
	var kerb := Palette.SIDEWALK.darkened(0.12)
	# each row's centre, sideways direction and height, worked out once
	var rp := PackedVector2Array()
	var rn := PackedVector2Array()
	var ry := PackedFloat32Array()
	for f in fs:
		rp.append(_ptf(s, f))
		rn.append(_sidef(s, f))
		ry.append(_yf(s, f) + 0.03)
	for r in fs.size() - 1:
		var f0: float = fs[r]
		var f1: float = fs[r + 1]
		if f1 - f0 < 0.01:
			continue
		var fm := (f0 + f1) * 0.5
		if _in_cuts(s.tunnels, fm):
			# under the hill: nothing to see
			continue
		var p0 := rp[r]
		var p1 := rp[r + 1]
		var n0 := rn[r]
		var n1 := rn[r + 1]
		var y0 := ry[r]
		var y1 := ry[r + 1]
		var over := _in_cuts(s.overs, fm)
		var bridge := over or _in_cuts(s.spans, fm)
		var stone := bridge and not over and styles[BridgeGen.span_at(s.spans, fm)] == "stone"
		if bridge:
			# the deck's underside, seen from the water and the banks
			var edge := w + (0.3 if verge else PAVE)
			_band(buf, p0, n0, y0, p1, n1, y1, -edge, -DECK_DEPTH, edge, -DECK_DEPTH, CONCRETE.darkened(0.25), 0.0, Vector3.DOWN)
		if not _in_cuts(skip, fm) and median > 0.0:
			# two carriageways with lanes painted on, and a planted strip
			# between them behind low kerbs
			var code := MeshKit.ASPHALT_HIGHWAY if verge else MeshKit.ASPHALT_AVENUE
			for side: float in [-1.0, 1.0]:
				var a := p0 + n0 * side * w
				var b := p0 + n0 * side * median
				var c := p1 + n1 * side * median
				var d := p1 + n1 * side * w
				buf.road(Vector3(a.x, y0, a.y), Vector3(b.x, y0, b.y), Vector3(c.x, y1, c.y), Vector3(d.x, y1, d.y), asphalt, code, f0 * SAMPLE, f1 * SAMPLE)
				var out_dir := (n0 + n1) * 0.5 * side
				_band(buf, p0, n0, y0, p1, n1, y1, side * median, 0.0, side * median, CURB, kerb, 0.0, Vector3(out_dir.x, 0.0, out_dir.y))
			_band(buf, p0, n0, y0, p1, n1, y1, -median, CURB, median, CURB, Palette.VERGE, MeshKit.MOWN_X, Vector3.UP)
			if verge:
				# a concrete crash barrier down the middle, sloping in to a narrow top
				var nm := (n0 + n1) * 0.5
				var nm3 := Vector3(nm.x, 0.0, nm.y)
				_band(buf, p0, n0, y0, p1, n1, y1, -0.09, CURB, -0.035, CURB + BARRIER, BARRIER_GREY, 0.0, -nm3 + Vector3.UP * 0.3)
				_band(buf, p0, n0, y0, p1, n1, y1, -0.035, CURB + BARRIER, 0.035, CURB + BARRIER, BARRIER_GREY.lightened(0.08), 0.0, Vector3.UP)
				_band(buf, p0, n0, y0, p1, n1, y1, 0.035, CURB + BARRIER, 0.09, CURB, BARRIER_GREY, 0.0, nm3 + Vector3.UP * 0.3)
		elif not _in_cuts(skip, fm):
			if KINDS[s.kind].dash:
				# the centre line is painted by the shader, not drawn
				var a := p0 - n0 * w
				var b := p0 + n0 * w
				var c := p1 + n1 * w
				var d := p1 - n1 * w
				buf.road(Vector3(a.x, y0, a.y), Vector3(b.x, y0, b.y), Vector3(c.x, y1, c.y), Vector3(d.x, y1, d.y), asphalt, MeshKit.ASPHALT_DASHED, f0 * SAMPLE, f1 * SAMPLE)
			elif walk:
				_band(buf, p0, n0, y0, p1, n1, y1, -w, 0.0, w, 0.0, PAVING, MeshKit.SLABS, Vector3.UP)
			else:
				_band(buf, p0, n0, y0, p1, n1, y1, -w, 0.0, w, 0.0, asphalt, MeshKit.ASPHALT, Vector3.UP)
		for side: float in [-1.0, 1.0]:
			if _in_cuts(cuts[side], fm):
				continue
			var out_dir := (n0 + n1) * 0.5 * side
			var out3 := Vector3(out_dir.x, 0.0, out_dir.y)
			if bridge:
				# on a bridge: kerb and pavement (a shoulder on a highway), a
				# parapet along the edge, and the deck's side down to its soffit
				# (down to the ground over the banks, where the abutments stand)
				var edge := w + (0.3 if verge else PAVE)
				if verge:
					_band(buf, p0, n0, y0, p1, n1, y1, side * w, 0.0, side * edge, 0.0, kerb, 0.0, Vector3.UP)
				else:
					_band(buf, p0, n0, y0, p1, n1, y1, side * w, 0.0, side * w, CURB, kerb, 0.0, -out3)
					_band(buf, p0, n0, y0, p1, n1, y1, side * w, CURB, side * edge, CURB, pave, MeshKit.SLABS, Vector3.UP)
				var top := CURB + 0.16
				var lip := 0.06
				var e0 := p0 + n0 * side * edge
				var e1 := p1 + n1 * side * edge
				# down to the ground over the banks, where the abutments stand;
				# over the water only the deck's own depth (arches fill in under stone)
				var g0 := minf(-DECK_DEPTH, land.height_at(e0.x, e0.y) - 0.1 - y0)
				var g1 := minf(-DECK_DEPTH, land.height_at(e1.x, e1.y) - 0.1 - y1)
				if land.height_at(e0.x, e0.y) < 0.0:
					g0 = -DECK_DEPTH - (0.0 if stone else 0.1)
				if land.height_at(e1.x, e1.y) < 0.0:
					g1 = -DECK_DEPTH - (0.0 if stone else 0.1)
				if over:
					# over the highway only the deck's own depth; down to the
					# bank where the ramps' embankments come up to meet it
					if g0 < -1.2:
						g0 = -DECK_DEPTH - 0.1
					if g1 < -1.2:
						g1 = -DECK_DEPTH - 0.1
				var wall := BridgeGen.STONE if stone else CONCRETE
				var base := 0.0 if verge else CURB
				if stone or over:
					# a solid parapet, of stone or (over a highway) concrete
					_band(buf, p0, n0, y0, p1, n1, y1, side * (edge - lip), base, side * (edge - lip), top, wall.darkened(0.04), 0.0, -out3)
					_band(buf, p0, n0, y0, p1, n1, y1, side * (edge - lip), top, side * edge, top, wall.lightened(0.1), 0.0, Vector3.UP)
					buf.quad(Vector3(e0.x, y0 + top, e0.y), Vector3(e1.x, y1 + top, e1.y), Vector3(e1.x, y1 + maxf(g1, -DECK_DEPTH - 3.0), e1.y), Vector3(e0.x, y0 + maxf(g0, -DECK_DEPTH - 3.0), e0.y), wall, 0.0, out3)
				else:
					# an open railing on posts (see BridgeGen), its top rail here
					var rail := BridgeGen.RAIL + base
					var r0 := side * (edge - 0.05)
					_band(buf, p0, n0, y0, p1, n1, y1, r0, rail - 0.05, r0, rail, HouseGen.IRON, 0.0, -out3)
					_band(buf, p0, n0, y0, p1, n1, y1, r0, rail, side * edge, rail, HouseGen.IRON.lightened(0.15), 0.0, Vector3.UP)
					_band(buf, p0, n0, y0, p1, n1, y1, side * edge, rail, side * edge, rail - 0.05, HouseGen.IRON, 0.0, out3)
					_band(buf, p0, n0, y0, p1, n1, y1, side * (edge - lip), base, side * edge, base, CONCRETE.lightened(0.08), 0.0, Vector3.UP)
					buf.quad(Vector3(e0.x, y0 + base, e0.y), Vector3(e1.x, y1 + base, e1.y), Vector3(e1.x, y1 + maxf(g1, -DECK_DEPTH - 3.0), e1.y), Vector3(e0.x, y0 + maxf(g0, -DECK_DEPTH - 3.0), e0.y), wall.darkened(0.06), 0.0, out3)
				continue
			if walk:
				# a stone edging flush with the grass, and the edge down into the ground
				_band(buf, p0, n0, y0, p1, n1, y1, side * w, 0.0, side * (w + 0.12), 0.0, kerb, 0.0, Vector3.UP)
				_band(buf, p0, n0, y0, p1, n1, y1, side * (w + 0.12), 0.0, side * (w + 0.3), -SKIRT, kerb.darkened(0.1), 0.0, out3 + Vector3.UP)
				continue
			if verge:
				# a pale shoulder line, a steel guardrail along the edge (its posts
				# are put in below), and the edge of the road down into the ground
				_band(buf, p0, n0, y0, p1, n1, y1, side * w, 0.0, side * (w + 0.12), 0.0, kerb, 0.0, Vector3.UP)
				_band(buf, p0, n0, y0, p1, n1, y1, side * (w + 0.12), 0.0, side * (w + 0.3), -SKIRT, kerb.darkened(0.1), 0.0, out3 + Vector3.UP)
				var rail := side * (w + RAIL_OUT)
				_band(buf, p0, n0, y0, p1, n1, y1, rail, RAIL_LO, rail, RAIL_HI, GUARDRAIL, 0.0, -out3)
				_band(buf, p0, n0, y0, p1, n1, y1, rail, RAIL_HI, rail, RAIL_LO, GUARDRAIL.darkened(0.15), 0.0, out3)
				continue
			# kerb face, pavement, and the pavement's outer edge down into the ground
			_band(buf, p0, n0, y0, p1, n1, y1, side * w, 0.0, side * w, CURB, kerb, 0.0, -out3)
			_band(buf, p0, n0, y0, p1, n1, y1, side * w, CURB, side * (w + PAVE), CURB, pave, MeshKit.SLABS, Vector3.UP)
			var qi := clampi(int(round(fm)), 0, s.quay.size() - 1)
			if not s.quay.is_empty() and s.quay[qi] & (1 if side < 0.0 else 2):
				# a stone quay wall down into the water, a coping along its top
				# and a railing a little in from the edge
				var e0 := p0 + n0 * side * (w + PAVE)
				var e1 := p1 + n1 * side * (w + PAVE)
				buf.quad(Vector3(e0.x, y0 + CURB, e0.y), Vector3(e1.x, y1 + CURB, e1.y), Vector3(e1.x, QUAY_DEPTH - 0.1, e1.y), Vector3(e0.x, QUAY_DEPTH - 0.1, e0.y), QUAY_STONE, 0.0, out3)
				_band(buf, p0, n0, y0, p1, n1, y1, side * (w + PAVE - 0.07), CURB + 0.004, side * (w + PAVE), CURB + 0.004, QUAY_STONE.lightened(0.15), 0.0, Vector3.UP)
				_band(buf, p0, n0, y0, p1, n1, y1, side * (w + PAVE - 0.09), CURB + 0.16, side * (w + PAVE - 0.09), CURB + 0.19, HouseGen.IRON, 0.0, out3)
				continue
			_band(buf, p0, n0, y0, p1, n1, y1, side * (w + PAVE), CURB, side * (w + PAVE), -SKIRT, kerb, 0.0, out3)
	if verge and not _laying.has(s.id):
		_highway_kit(s, buf, upto, skip + s.tunnels)
		if s.kind == "highway":
			_beyond(s, buf)
		for t in s.tunnels:
			if t.x <= upto:
				_portal(s, buf, t.x, 1.0)
			if t.y <= upto:
				_portal(s, buf, t.y, -1.0)
	# a dead end rounds off in a half circle, like a turning head
	if not _laying.has(s.id):
		for f: float in [0.0, upto]:
			if _dead_end(s, int(f)) and not _in_cuts(s.spans, f) and not _in_cuts(s.overs, f) and not _in_cuts(skip, f) and not _in_cuts(s.tunnels, f):
				_build_cap(s, buf, f, asphalt, pave, kerb)
	# bus stops, once the street is laid out and knows its junctions
	if not _laying.has(s.id):
		s.stops = BusStops.place(s, skip + s.overs, cuts)
		BusStops.build(self, s, buf, s.stops)
	# what carries the bridges: arches, piers, pylons and cables
	var sup := MeshBuf.new()
	BridgeGen.build(self, s, buf, sup, upto, styles)
	for fly in flyovers:
		if fly.b <= upto:
			_flyover_pier(s, fly, sup)
	var mi: MeshInstance3D = _meshes.get(s.id)
	if mi == null:
		mi = MeshInstance3D.new()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_meshes[s.id] = mi
	_put_bridges(mi, sup)
	if buf.idx.is_empty():
		mi.mesh = null
		return
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = buf.verts
	arr[Mesh.ARRAY_NORMAL] = buf.norms
	arr[Mesh.ARRAY_COLOR] = buf.cols
	arr[Mesh.ARRAY_TEX_UV] = buf.uvs
	arr[Mesh.ARRAY_INDEX] = buf.idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	m.surface_set_material(0, material)
	mi.mesh = m


## The parts of a street's bridges that cast shadows, on a mesh of their own.
func _put_bridges(mi: MeshInstance3D, sup: MeshBuf) -> void:
	var bm: MeshInstance3D = mi.get_node_or_null("Bridges")
	if sup.idx.is_empty():
		if bm:
			mi.remove_child(bm)
			bm.queue_free()
		return
	if bm == null:
		bm = MeshInstance3D.new()
		bm.name = "Bridges"
		mi.add_child(bm)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = sup.verts
	arr[Mesh.ARRAY_NORMAL] = sup.norms
	arr[Mesh.ARRAY_COLOR] = sup.cols
	arr[Mesh.ARRAY_TEX_UV] = sup.uvs
	arr[Mesh.ARRAY_INDEX] = sup.idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	m.surface_set_material(0, material)
	bm.mesh = m


## Where this street's pavement would lie on another street's carriageway
## (streets drawn close alongside or meeting at a shallow angle), the
## pavement gives way, so no kerb ever stands across a road.
func _overlap_cuts(s: Street, cuts: Dictionary) -> void:
	var out := s.w() + PAVE * 0.5
	for o: Street in streets:
		if o == s or not _boxes_overlap(s, o) or _flies(s, o):
			continue
		var r := o.w() + 0.05
		# only the stretch of s near o can run onto it
		var pad := Vector2.ONE * (r + out + 0.1)
		var near := s.segments_near(o.lo - pad, o.hi + pad)
		if near.is_empty():
			continue
		var n := s.pts.size()
		var from := near[0]
		var to := mini(near[near.size() - 1] + 2, n - 1)
		for side: float in [-1.0, 1.0]:
			var open := -1
			var i := from
			while i < n:
				var q := s.pts[i] + _side(s, i) * side * out
				var hit := o.near_box(q, r) and o.within(q, r)
				if hit and open < 0:
					open = i
				elif not hit and open >= 0:
					cuts[side].append(Vector2(maxf(open - 0.75, 0.0), i - 0.25))
					open = -1
				if i >= to and open < 0:
					break
				i += 1
			if open >= 0:
				cuts[side].append(Vector2(maxf(open - 0.75, 0.0), s.pts.size()))


## Whether a point lies on the carriageway of one of the streets `among`, well inside its kerbs.
func _on_carriageway(p: Vector2, among: Array) -> bool:
	for o: Street in among:
		if o.near_box(p, o.w()) and o.within(p, o.w() - 0.08):
			return true
	return false


static func _in_cuts(list: PackedVector2Array, f: float) -> bool:
	for c in list:
		if f > c.x and f < c.y:
			return true
	return false


# ------------------------------------------------------------------ junctions

## A flyover's pier: a slim concrete wall standing on the highway's median
## under the deck, lined up with the traffic either side of it.
func _flyover_pier(s: Street, fly: Dictionary, sup: MeshBuf) -> void:
	var o: Street = fly.hw
	var c := _ptf(o, fly.fo)
	var do := (_ptf(o, minf(fly.fo + 1.0, o.pts.size() - 1)) - _ptf(o, maxf(fly.fo - 1.0, 0.0))).normalized()
	var ds := (_ptf(s, minf(fly.f + 1.0, s.pts.size() - 1)) - _ptf(s, maxf(fly.f - 1.0, 0.0))).normalized()
	var sin_a := maxf(absf(ds.cross(do)), 0.35)
	var lo := _yf(o, fly.fo) + CURB
	var hi := _yf(s, fly.f) + 0.03 - DECK_DEPTH
	var length := minf((s.w() + PAVE) * 2.0 * 0.8 / sin_a, 6.0)
	sup.box(Vector3(c.x, (lo + hi) * 0.5, c.y), Vector3(length, hi - lo, 0.16), Vector3(do.x, 0.0, do.y), Vector3(-do.y, 0.0, do.x), CONCRETE.darkened(0.08))


## Where two streets meet, as (index on s, index on o) pairs (fractional
## sample indices): ends that stop on the other street, and crossings.
## Where two streets meet, remembered between rebuilds while neither changes
## (laying one street then only works out its own meetings afresh).
func _meetings_of(s: Street, o: Street, seen: Dictionary) -> PackedVector2Array:
	var key := Vector2i(s.id, o.id)
	var sig := hash([_sigs[s.id] if _sigs.has(s.id) else s.shape_sig(), _sigs[o.id] if _sigs.has(o.id) else o.shape_sig()])
	var hit: Array = _meet_cache.get(key, [])
	var out: PackedVector2Array = hit[1] if not hit.is_empty() and hit[0] == sig else _meetings(s, o)
	seen[key] = [sig, out]
	return out


func _meetings(s: Street, o: Street) -> PackedVector2Array:
	var out := PackedVector2Array()
	if _flies(s, o):
		return out
	var spots := PackedVector2Array()
	var ns := s.pts.size()
	var no := o.pts.size()
	# a ramp merges alongside a highway's outer lane rather than onto it
	var slip_s := s.w() + 0.1 if _merges(s, o) and s.kind == "ramp" else 0.0
	var slip_o := o.w() + 0.1 if _merges(s, o) and o.kind == "ramp" else 0.0
	for e in [0, ns - 1]:
		if not o.within(s.pts[e], o.w() + 0.3 + slip_s):
			continue
		var c: Vector3 = o.closest(s.pts[e])
		if c.x < o.w() + 0.3 + slip_s:
			out.append(Vector2(e, c.z))
			spots.append(s.pts[e])
	for e in [0, no - 1]:
		if not s.within(o.pts[e], s.w() + 0.3 + slip_o):
			continue
		var c: Vector3 = s.closest(o.pts[e])
		if c.x < s.w() + 0.3 + slip_o and not _near_any(spots, o.pts[e], 1.5):
			out.append(Vector2(c.z, e))
			spots.append(o.pts[e])
	for i in s.segments_near(o.lo - Vector2(0.6, 0.6), o.hi + Vector2(0.6, 0.6)):
		var a := s.pts[i]
		var b := s.pts[i + 1]
		if not o.near_box(a, 0.6) and not o.near_box(b, 0.6):
			continue
		for j in o.segments_near(a.min(b), a.max(b)):
			var hit: Variant = Geometry2D.segment_intersects_segment(a, b, o.pts[j], o.pts[j + 1])
			if hit == null or _near_any(spots, hit, 1.5):
				continue
			var fs := i + a.distance_to(hit) / maxf(a.distance_to(b), 1e-6)
			var fo := j + o.pts[j].distance_to(hit) / maxf(o.pts[j].distance_to(o.pts[j + 1]), 1e-6)
			out.append(Vector2(fs, fo))
			spots.append(hit)
	return out


## Whether one of the two is a highway the other crosses on a bridge of its
## own instead of meeting it at a junction (of two highways, the one with the
## later key goes over).
func _flies(a: Street, b: Street) -> bool:
	var ha := a.kind == "highway"
	var hb := b.kind == "highway"
	if not ha and not hb:
		return false
	var low := a if ha else b
	if ha and hb:
		low = b if a.key > b.key else a
	var high := b if low == a else a
	return _crossing(high, low).x >= 0.0


## Whether one is a ramp and the other a highway it runs alongside.
static func _merges(a: Street, b: Street) -> bool:
	return (a.kind == "ramp" and b.kind == "highway") or (a.kind == "highway" and b.kind == "ramp")


## Where street s crosses highway o, carrying on well past it either way,
## as (index on s, index on o); (-1, -1) where it doesn't, or only ends on it.
func _crossing(s: Street, o: Street) -> Vector2:
	if not _boxes_overlap(s, o):
		return Vector2(-1, -1)
	# (asked often, for every street built near a highway: remembered while
	# neither changes)
	var key := Vector2i(s.id, o.id)
	var sig := hash([s.pts, o.pts])
	var hit: Array = _cross_cache.get(key, [])
	if not hit.is_empty() and hit[0] == sig:
		return hit[1]
	var x := _find_crossing(s, o)
	_cross_cache[key] = [sig, x]
	return x


func _find_crossing(s: Street, o: Street) -> Vector2:
	var clear := (o.reach() + 1.0) / SAMPLE
	var ns := s.pts.size()
	var no := o.pts.size()
	for i in s.segments_near(o.lo - Vector2(0.6, 0.6), o.hi + Vector2(0.6, 0.6)):
		var a := s.pts[i]
		var b := s.pts[i + 1]
		if not o.near_box(a, 0.6) and not o.near_box(b, 0.6):
			continue
		for j in o.segments_near(a.min(b), a.max(b)):
			var hit: Variant = Geometry2D.segment_intersects_segment(a, b, o.pts[j], o.pts[j + 1])
			if hit == null:
				continue
			var fs := i + a.distance_to(hit) / maxf(a.distance_to(b), 1e-6)
			var fo := j + o.pts[j].distance_to(hit) / maxf(o.pts[j].distance_to(o.pts[j + 1]), 1e-6)
			if fs > clear and fs < ns - 1 - clear and fo > clear and fo < no - 1 - clear:
				return Vector2(fs, fo)
	return Vector2(-1, -1)


## The highways street s flies over: [{hw, fo, f, a, b}], the deck running
## from a to b on s, far enough out each side to clear the highway's shoulders
## at whatever angle the two cross.
func _flyovers(s: Street) -> Array:
	var out: Array = []
	if s.kind == "ramp":
		return out
	for o: Street in streets:
		if o.kind != "highway" or o == s or (s.kind == "highway" and s.key < o.key):
			continue
		var x := _crossing(s, o)
		if x.x < 0.0 or _in_cuts(o.tunnels, x.y) or _in_cuts(s.tunnels, x.x):
			# a street over a highway's tunnel just carries on over the hill
			continue
		var ds := (_ptf(s, minf(x.x + 1.0, s.pts.size() - 1)) - _ptf(s, maxf(x.x - 1.0, 0.0))).normalized()
		var do := (_ptf(o, minf(x.y + 1.0, o.pts.size() - 1)) - _ptf(o, maxf(x.y - 1.0, 0.0))).normalized()
		var sin_a := maxf(absf(ds.cross(do)), 0.35)
		var cos_a := absf(ds.dot(do))
		var half := (o.w() + 0.3 + 1.2 + (s.w() + PAVE) * cos_a) / sin_a
		var k := half / SAMPLE
		out.append({"hw": o, "fo": x.y, "f": x.x, "a": maxf(x.x - k, 0.0), "b": minf(x.x + k, s.pts.size() - 1.0)})
	return out


## Whether p lies within r of some street's deck where it flies over a highway.
func under_deck(p: Vector2, r: float) -> bool:
	for o: Street in streets:
		if o.overs.is_empty() or not o.near_box(p, o.reach() + r):
			continue
		for sp in o.overs:
			for i in range(int(sp.x), int(ceil(sp.y)) + 1):
				if o.pts[mini(i, o.pts.size() - 1)].distance_to(p) < o.reach() + r:
					return true
	return false


static func _near_any(list: PackedVector2Array, p: Vector2, r: float) -> bool:
	for q in list:
		if q.distance_to(p) < r:
			return true
	return false


## The directions a street leaves a junction at index f: [dir, +1 forward / -1 back].
func _arms(st: Street, f: float) -> Array:
	var out: Array = []
	var n := st.pts.size()
	var here := _ptf(st, f)
	if f < n - 2.0:
		out.append({"st": st, "f": f, "sgn": 1.0, "dir": (_ptf(st, minf(f + 3.0, n - 1)) - here).normalized()})
	if f > 1.0:
		out.append({"st": st, "f": f, "sgn": -1.0, "dir": (_ptf(st, maxf(f - 3.0, 0.0)) - here).normalized()})
	return out


## Every place where streets meet, worked out once after streets change. Each
## is one flat-topped piece: the arms' asphalt stops a little short of the
## middle and the junction fills in between, its corners rounded with kerbs
## and pavement, so streets meeting at any angle join without seams or holes.
## {at, y, arms: [{st, f, sgn, dir, back}], edge: [Vector3], corners: [[Vector3]], owner}
func junctions() -> Array:
	if _junctions_dirty:
		_junctions = _find_junctions()
		_junctions_dirty = false
	return _junctions


func _find_junctions() -> Array:
	var found: Array = []
	var seen := {}
	# the junctions found so far, by 3 m cell
	var near := {}
	_begin_pairs()
	for i in streets.size():
		for k in range(i + 1, streets.size()):
			var a: Street = streets[i]
			var b: Street = streets[k]
			# a ramp joins its highway alongside, with no junction to lay
			if not _pair_near(i, k) or _merges(a, b):
				continue
			for m in _meetings_of(a, b, seen):
				var at := (_ptf(a, m.x) + _ptf(b, m.y)) * 0.5
				# the first one found within 3 m, looked for only round here
				var jn: Dictionary = {}
				var first := found.size()
				var cell := Vector2i((at / 3.0).floor())
				for dz in range(-1, 2):
					for dx in range(-1, 2):
						for qi: int in near.get(cell + Vector2i(dx, dz), []):
							if qi < first and found[qi].at.distance_to(at) < 3.0:
								first = qi
				if first < found.size():
					jn = found[first]
				else:
					jn = {"at": at, "meets": []}
					found.append(jn)
					if near.has(cell):
						near[cell].append(first)
					else:
						near[cell] = [first]
				jn.meets.append([a, m.x, b, m.y])
	_meet_cache = seen
	_end_pairs()
	# a junction where the same streets meet as before, as they were, stands as it was
	var shaped := {}
	for k in found.size():
		var sig := _meets_sig(found[k].meets)
		var was: Variant = _shaped.get(sig)
		if was != null:
			found[k] = was
		else:
			_shape_junction(found[k])
		shaped[sig] = found[k]
	_shaped = shaped
	return found.filter(func(q): return q.arms.size() >= 2)


## A fingerprint of what a junction is made from: the streets meeting there
## (their courses, kinds and heights) and where along them they meet.
static func _meets_sig(meets: Array) -> int:
	var parts: Array = []
	for m in meets:
		for e in [[m[0], m[1]], [m[2], m[3]]]:
			var st: Street = e[0]
			parts.append_array([st.id, st.shape_sig(), hash(st.ys), e[1]])
	return hash(parts)


## Arms, corners and the outline of one junction.
func _shape_junction(jn: Dictionary) -> void:
	# the same street meeting the junction twice close together counts once
	var spots := {}
	var at := Vector2.ZERO
	for m in jn.meets:
		at += (_ptf(m[0], m[1]) + _ptf(m[2], m[3])) * 0.5
		for e in [[m[0], m[1]], [m[2], m[3]]]:
			var st: Street = e[0]
			var list: Array = spots.get(st, [])
			var merged := false
			for qi in list.size():
				var q: Vector2 = list[qi]
				if not merged and absf(q.x - e[1]) < 8.0:
					list[qi] = Vector2((q.x * q.y + e[1]) / (q.y + 1.0), q.y + 1.0)
					merged = true
			if not merged:
				list.append(Vector2(e[1], 1.0))
			spots[st] = list
	at /= jn.meets.size()
	var arms: Array = []
	var y := 0.0
	var ny := 0
	var owner := 0
	for st: Street in spots:
		owner = maxi(owner, st.id)
		for q: Vector2 in spots[st]:
			y += _yf(st, q.x)
			ny += 1
			arms.append_array(_arms(st, q.x))
	arms.sort_custom(func(p, q): return p.dir.angle() < q.dir.angle())
	jn.at = at
	jn.y = y / maxf(ny, 1.0) + 0.03
	jn.arms = arms
	jn.owner = owner
	jn.edge = []
	jn.corners = []
	if arms.size() < 2:
		return
	for arm in arms:
		arm.cut = [0.0, 0.0]  # pavement taken over: toward the previous arm, toward the next
	# the curve between each arm and the next, going round
	var curves: Array = []
	for k in arms.size():
		var A: Dictionary = arms[k]
		var B: Dictionary = arms[(k + 1) % arms.size()]
		curves.append(_corner_curve(at, A, B))
	# each arm's asphalt stops where its farther corner begins
	for arm in arms:
		arm.back = maxf(maxf(arm.cut[0], arm.cut[1]), 0.3)
		arm.f_end = clampf(arm.f + arm.sgn * arm.back / SAMPLE, 0.0, arm.st.pts.size() - 1.0)
	# the outline, going round: each arm's end, then the way round to the next
	for k in arms.size():
		var A: Dictionary = arms[k]
		var B: Dictionary = arms[(k + 1) % arms.size()]
		var sa: float = A.sgn
		var sb: float = -B.sgn
		jn.edge.append(_kerb_pt(A.st, A.f_end, -sa))
		jn.edge.append(_kerb_pt(A.st, A.f_end, sa))
		var c: Dictionary = curves[k]
		if c.same:
			# one street running on through: follow its kerb
			_kerb_run(jn.edge, A.st, A.f_end, B.f_end, sa)
			continue
		_kerb_run(jn.edge, A.st, A.f_end, c.fa, sa)
		jn.edge.append_array(c.pts)
		# a sliver between arms at a shallow angle gets no kerb of its own
		if not c.open:
			jn.corners.append(c.pts)
		_kerb_run(jn.edge, B.st, c.fb, B.f_end, sb)


## The rounded kerb from arm A round to the next arm B, and how far along each
## arm it starts. Sharp corners get a tighter round, and where two arms are
## almost in line (or the gap is the outside of a bend) the kerb swings round
## the junction's middle instead.
func _corner_curve(j: Vector2, A: Dictionary, B: Dictionary) -> Dictionary:
	# one street running on through (not the same street coming back round)
	if A.st == B.st and absf(A.f - B.f) < 1.0:
		return {"same": true}
	var a: Vector2 = A.dir
	var b: Vector2 = B.dir
	var th := wrapf(b.angle() - a.angle(), 0.0, TAU)
	var wa: float = A.st.w()
	var wb: float = B.st.w()
	var sa: float = A.sgn
	var sb: float = -B.sgn
	var na := a.rotated(PI * 0.5)
	var nb := b.rotated(-PI * 0.5)
	var pts: Array = []
	var ta := 0.0
	var tb := 0.0
	if th < PI - 0.12:
		var r := KERB_R * clampf(th / 1.2, 0.35, 1.0)
		var det := -a.cross(b)
		var d := nb * (wb + r) - na * (wa + r)
		# arms meeting at a shallow angle would push the corner far down both
		# streets: stop it a short way along, letting their asphalt overlap
		ta = clampf(b.cross(d) / det, 0.0, MAX_CUT)
		tb = clampf(a.cross(d) / det, 0.0, MAX_CUT)
	var fa := clampf(A.f + A.sgn * ta / SAMPLE, 0.0, A.st.pts.size() - 1.0)
	var fb := clampf(B.f + B.sgn * tb / SAMPLE, 0.0, B.st.pts.size() - 1.0)
	A.cut[1] = absf(fa - A.f) * SAMPLE
	B.cut[0] = absf(fb - B.f) * SAMPLE
	var pa := _kerb_pt(A.st, fa, sa)
	var pb := _kerb_pt(B.st, fb, sb)
	var pa2 := Vector2(pa.x, pa.z)
	var pb2 := Vector2(pb.x, pb.z)
	if th < PI - 0.12:
		# a curve between the two kerbs, bending through where they would meet
		var det := -a.cross(b)
		var dc := nb * wb - na * wa
		var c := j + na * wa + a * (b.cross(dc) / det)
		if c.distance_to(j) > MAX_CUT + wa:
			c = (pa2 + pb2) * 0.5
		var steps := 4 if th > 0.9 else 3
		for k in steps + 1:
			var t := float(k) / steps
			var p := pa2 * (1.0 - t) * (1.0 - t) + c * 2.0 * t * (1.0 - t) + pb2 * t * t
			pts.append(Vector3(p.x, lerpf(pa.y, pb.y, t), p.y))
	else:
		# round the outside of the junction's middle
		var r0 := pa2.distance_to(j)
		var r1 := pb2.distance_to(j)
		var a0 := (pa2 - j).angle()
		var sweep := wrapf((pb2 - j).angle() - a0, 0.0, TAU)
		var steps := clampi(ceili(sweep / 0.45), 1, 10)
		for k in steps + 1:
			var t := float(k) / steps
			var p := j + Vector2.from_angle(a0 + sweep * t) * lerpf(r0, r1, t)
			pts.append(Vector3(p.x, lerpf(pa.y, pb.y, t), p.y))
	return {"same": false, "pts": pts, "fa": fa, "fb": fb, "open": th < 0.45}


## A point on a street's kerb line (asphalt height) at index f on `side`.
func _kerb_pt(st: Street, f: float, side: float) -> Vector3:
	var p := _ptf(st, f) + _sidef(st, f) * side * st.w()
	return Vector3(p.x, _yf(st, f) + 0.03, p.y)


## Kerb points strictly between f0 and f1 (either order), added to `out` in that order.
func _kerb_run(out: Array, st: Street, f0: float, f1: float, side: float) -> void:
	var dirn := signf(f1 - f0)
	if dirn == 0.0:
		return
	var f := floorf(f0) + 1.0 if dirn > 0.0 else ceilf(f0) - 1.0
	while (f1 - f) * dirn > 0.05:
		out.append(_kerb_pt(st, f, side))
		f += dirn * 2.0


## Lowers the ground under the junctions a street is part of, so none shows
## through where the arms' slopes differ.
func _conform_junctions(s: Street) -> void:
	for jn in junctions():
		var mine := false
		for arm in jn.arms:
			mine = mine or arm.st == s
		if not mine:
			continue
		var j3 := Vector2(jn.at.x, jn.at.y)
		for arm in jn.arms:
			var e := _ptf(arm.st, arm.f_end)
			land.conform(PackedVector2Array([j3, e]), PackedFloat32Array([jn.y - 0.03, _yf(arm.st, arm.f_end)]), arm.st.w() + 0.2, 0.0, true)
		for c in jn.corners:
			var cp := PackedVector2Array()
			var cy := PackedFloat32Array()
			for p: Vector3 in c:
				cp.append(Vector2(p.x, p.z))
				cy.append(p.y - 0.03)
			land.conform(cp, cy, PAVE + 0.2 + Land.STEP * 0.75, 0.0, true)


## Builds a junction's asphalt and corner kerbs into a street's mesh.
func _build_junction(jn: Dictionary, buf: MeshBuf) -> void:
	var main := false
	var walks := true
	for arm in jn.arms:
		main = main or arm.st.kind != "side"
		walks = walks and arm.st.kind == "walk"
	if walks:
		_build_plaza(jn, buf)
		return
	var asphalt := Palette.ASPHALT.darkened(0.05) if main else Palette.ASPHALT
	var c3 := Vector3(jn.at.x, jn.y, jn.at.y)
	var edge: Array = jn.edge
	for k in edge.size():
		buf.tri(c3, edge[k], edge[(k + 1) % edge.size()], asphalt, MeshKit.ASPHALT, true)
	var pave := Palette.SIDEWALK
	var kerb := Palette.SIDEWALK.darkened(0.12)
	# the streets whose carriageways the corners might reach onto
	var far := 0.0
	for c: Array in jn.corners:
		for p3: Vector3 in c:
			far = maxf(far, Vector2(p3.x, p3.z).distance_to(jn.at))
	far += PAVE + 0.5
	var near: Array = []
	for o: Street in streets:
		if o.near_box(jn.at, o.w() + far):
			near.append(o)
	for c: Array in jn.corners:
		var prev_p := Vector3.ZERO
		var prev_o := Vector3.ZERO
		var prev_n := Vector3.ZERO
		for k in c.size():
			var p3: Vector3 = c[k]
			var tan: Vector3 = c[mini(k + 1, c.size() - 1)] - c[maxi(k - 1, 0)]
			var n3 := Vector3(-tan.z, 0.0, tan.x).normalized()
			if n3.dot(p3 - c3) < 0.0:
				n3 = -n3
			var o3 := p3 + n3 * PAVE
			if k > 0 and not _on_carriageway(Vector2((p3.x + prev_p.x + o3.x + prev_o.x) * 0.25, (p3.z + prev_p.z + o3.z + prev_o.z) * 0.25), near):
				buf.quad(prev_p, p3, p3 + Vector3.UP * CURB, prev_p + Vector3.UP * CURB, kerb, 0.0, -(n3 + prev_n))
				buf.quad(prev_p + Vector3.UP * CURB, p3 + Vector3.UP * CURB, o3 + Vector3.UP * CURB, prev_o + Vector3.UP * CURB, pave, MeshKit.SLABS, Vector3.UP)
				buf.quad(prev_o + Vector3.UP * CURB, o3 + Vector3.UP * CURB, o3 + Vector3.DOWN * SKIRT, prev_o + Vector3.DOWN * SKIRT, kerb, 0.0, n3 + prev_n)
			prev_p = p3
			prev_o = o3
			prev_n = n3


## A highway's guardrail posts, and now and then a gantry of direction signs
## over both carriageways.
## how far a highway leaving the map runs on into the country beyond it
const BEYOND := 300.0
const BEYOND_STEP := 8.0


## A highway that leaves the map runs on into the country past its edge (the
## horizon's land) instead of stopping short: both carriageways, the planted
## strip between them and the verges, rising and falling with the far land,
## on piers where it carries on over the sea, out until the haze takes it.
func _beyond(s: Street, buf: MeshBuf) -> void:
	var n := s.pts.size()
	var w := s.w()
	var median: float = KINDS[s.kind].median
	var asphalt := Palette.ASPHALT.darkened(0.05)
	var kerb := Palette.SIDEWALK.darkened(0.12)
	var reach := minf(BEYOND, Land.FAR - BEYOND_STEP)
	for e: int in [0, n - 1]:
		var p := s.pts[e]
		if maxf(absf(p.x), absf(p.y)) < Land.HALF - 2.0:
			continue
		var dir := (p - s.pts[1 if e == 0 else n - 2]).normalized()
		var nrm := Vector2(-dir.y, dir.x)
		var y := s.ys[e] + 0.03
		var along := (n - 1) * SAMPLE if e == n - 1 else 0.0
		var t := 0.0
		while t < reach:
			var t1 := t + BEYOND_STEP
			var p0 := p + dir * t
			var p1 := p + dir * t1
			var g := land.natural_at(p1)
			# on the far land just over it; over the sea on a deck, as on the map
			var want := g + 0.15 if g > 0.05 else DECK + 0.03
			var y1 := clampf(want, y - KINDS.highway.grade * BEYOND_STEP, y + KINDS.highway.grade * BEYOND_STEP)
			var s0 := along + t
			var s1 := along + t1
			for side: float in [-1.0, 1.0]:
				var a := p0 + nrm * side * w
				var b := p0 + nrm * side * median
				var c := p1 + nrm * side * median
				var d := p1 + nrm * side * w
				buf.road(Vector3(a.x, y, a.y), Vector3(b.x, y, b.y), Vector3(c.x, y1, c.y), Vector3(d.x, y1, d.y), asphalt, MeshKit.ASPHALT_HIGHWAY, s0, s1)
				# the verge, and its edge well down into the ground
				var o3 := Vector3(nrm.x, 0.0, nrm.y) * side
				_band(buf, p0, nrm, y, p1, nrm, y1, side * w, 0.0, side * (w + 0.3), 0.0, kerb, 0.0, Vector3.UP)
				_band(buf, p0, nrm, y, p1, nrm, y1, side * (w + 0.3), 0.0, side * (w + 0.5), -1.2, kerb.darkened(0.1), 0.0, o3 + Vector3.UP)
			_band(buf, p0, nrm, y, p1, nrm, y1, -median, CURB, median, CURB, Palette.VERGE, MeshKit.MOWN_X, Vector3.UP)
			if g <= 0.05 and fmod(t1, BEYOND_STEP * 3.0) < 0.01:
				# a pier under the deck, down into the water
				var top := y1 - DECK_DEPTH
				buf.box(Vector3(p1.x, (top + Land.LOW) * 0.5, p1.y), Vector3(0.5, top - Land.LOW, w * 1.6), Vector3(dir.x, 0.0, dir.y), Vector3(nrm.x, 0.0, nrm.y), CONCRETE.darkened(0.1))
			y = y1
			t = t1


func _highway_kit(s: Street, buf: MeshBuf, upto: float, skip: PackedVector2Array) -> void:
	var w := s.w()
	var f := 1.0
	var since_gantry := GANTRY_EVERY * 0.5
	while f < upto - 1.0:
		var on_bridge := _in_cuts(s.spans, f)
		if not _in_cuts(skip, f) and not on_bridge:
			for side: float in [-1.0, 1.0]:
				var base := _atf(s, f, side * (w + RAIL_OUT), 0.0)
				var nn := _sidef(s, f)
				var t := Vector3(-nn.y, 0.0, nn.x) * 0.025
				var out := Vector3(nn.x, 0.0, nn.y) * side
				# a thin steel post, its two broad faces along the road
				buf.quad(base - t, base + t, base + t + Vector3.UP * RAIL_HI, base - t + Vector3.UP * RAIL_HI, GUARDRAIL.darkened(0.25), 0.0, out)
				buf.quad(base - t, base + t, base + t + Vector3.UP * RAIL_HI, base - t + Vector3.UP * RAIL_HI, GUARDRAIL.darkened(0.25), 0.0, -out)
		since_gantry += POST_EVERY
		var by_tunnel := false
		for t in s.tunnels:
			by_tunnel = by_tunnel or (f > t.x - 30.0 and f < t.y + 30.0)
		if since_gantry >= GANTRY_EVERY and s.kind == "highway" and not on_bridge and not by_tunnel and not _in_cuts(skip, f) and f > 4.0 and f < upto - 4.0:
			since_gantry = 0.0
			_gantry(s, buf, f, w)
		f += POST_EVERY / SAMPLE


## A tunnel mouth at sample f (the tunnel running on towards +dirn): a
## concrete headwall into the hill with the opening dark beyond it, a row of
## lamps lit under its lintel.
func _portal(s: Street, buf: MeshBuf, f: float, dirn: float) -> void:
	var nn := _sidef(s, f)
	var n3 := Vector3(nn.x, 0.0, nn.y)
	var d3 := Vector3(-nn.y, 0.0, nn.x)
	var fwd := (_ptf(s, minf(f + 1.0, s.pts.size() - 1)) - _ptf(s, maxf(f - 1.0, 0.0))).normalized() * dirn
	var into := Vector3(fwd.x, 0.0, fwd.y)
	var open := s.w() + 0.4
	var high := 2.0
	var c := _atf(s, f, 0.0, 0.0)
	var face := CONCRETE.darkened(0.04)
	for side: float in [-1.0, 1.0]:
		# the headwall either side of the opening, stepping down into the hill
		buf.box(c + n3 * side * (open + 0.8) + Vector3.UP * 1.3 + into * 0.2, Vector3(1.6, 3.2, 0.5), n3, d3, face)
	buf.box(c + Vector3.UP * (high + 0.55) + into * 0.2, Vector3(open * 2.0 + 3.2, 1.1, 0.5), n3, d3, face)
	# the dark inside, a little way in
	var a := c + into * 0.45 - n3 * open + Vector3.DOWN * 0.3
	var b := c + into * 0.45 + n3 * open + Vector3.DOWN * 0.3
	buf.quad(a, b, b + Vector3.UP * (high + 0.31), a + Vector3.UP * (high + 0.31), TUNNEL_DARK, 0.0, -into)
	var la := c + into * 0.44 - n3 * (open - 0.2) + Vector3.UP * (high - 0.12)
	var lb := c + into * 0.44 + n3 * (open - 0.2) + Vector3.UP * (high - 0.12)
	buf.quad(la, lb, lb + Vector3.UP * 0.06, la + Vector3.UP * 0.06, Color(1.0, 0.82, 0.55), 2.0, -into)


func _gantry(s: Street, buf: MeshBuf, f: float, w: float) -> void:
	var nn := _sidef(s, f)
	var n3 := Vector3(nn.x, 0.0, nn.y)
	var t3 := Vector3(-nn.y, 0.0, nn.x)
	var span := w + 0.4
	var top := 2.1
	var steel := Color(0.62, 0.64, 0.66)
	for side: float in [-1.0, 1.0]:
		var b := _atf(s, f, side * span, 0.0)
		buf.box(b + Vector3.UP * top * 0.5, Vector3(0.12, top, 0.12), n3, t3, steel)
	# the beam, and a sign over each carriageway facing its traffic
	var mid := _atf(s, f, 0.0, top)
	buf.box(mid, Vector3(span * 2.0 + 0.1, 0.1, 0.12), n3, t3, steel)
	for side: float in [-1.0, 1.0]:
		var c := _atf(s, f, side * (w + KINDS[s.kind].median) * 0.5, top - 0.32)
		var face := t3 * side
		buf.box(c, Vector3(w * 0.8, 0.5, 0.04), n3, t3, SIGN_GREEN)
		for row in 2:
			var stripe := c + face * 0.025 + Vector3.UP * (0.1 - row * 0.2)
			var a := stripe - n3 * (w * 0.3 - row * 0.06)
			var b := stripe + n3 * (w * 0.3 - row * 0.06)
			buf.quad(a + Vector3.DOWN * 0.03, b + Vector3.DOWN * 0.03, b + Vector3.UP * 0.03, a + Vector3.UP * 0.03, Color(0.95, 0.96, 0.95), 0.0, face)


## Where walks meet: a little round paved square, with a fountain in the
## middle where three or more meet.
func _build_plaza(jn: Dictionary, buf: MeshBuf) -> void:
	const SEGS := 14
	var c3 := Vector3(jn.at.x, jn.y, jn.at.y)
	var edge: Array = jn.edge
	for k in edge.size():
		buf.tri(c3, edge[k], edge[(k + 1) % edge.size()], PAVING, MeshKit.SLABS, true)
	var r := KINDS.walk.w + PAVE + 1.4
	var kerb := Palette.SIDEWALK.darkened(0.12)
	var ring := func(rad: float, dy: float, k: int) -> Vector3:
		var a := TAU * k / SEGS
		return c3 + Vector3(cos(a) * rad, dy, sin(a) * rad)
	for k in SEGS:
		var a0: Vector3 = ring.call(r, 0.004, k)
		var a1: Vector3 = ring.call(r, 0.004, k + 1)
		buf.tri(c3 + Vector3.UP * 0.004, a0, a1, PAVING.lightened(0.04), MeshKit.SLABS, true)
		var mid := TAU * (k + 0.5) / SEGS
		var out := Vector3(cos(mid), 0.0, sin(mid))
		buf.quad(a0, a1, ring.call(r + 0.12, 0.004, k + 1), ring.call(r + 0.12, 0.004, k), kerb, 0.0, Vector3.UP)
		buf.quad(ring.call(r + 0.12, 0.004, k), ring.call(r + 0.12, 0.004, k + 1), ring.call(r + 0.3, -SKIRT, k + 1), ring.call(r + 0.3, -SKIRT, k), kerb.darkened(0.1), 0.0, out + Vector3.UP)
	if jn.arms.size() < 3:
		return
	# a stone basin, its water, and a column with a bowl spilling into it
	const BASIN := 0.85
	const WALL := 0.28
	var stone := Color(0.8, 0.77, 0.72)
	var water := Color(0.36, 0.62, 0.74)
	for k in SEGS:
		var mid := TAU * (k + 0.5) / SEGS
		var out := Vector3(cos(mid), 0.0, sin(mid))
		buf.quad(ring.call(BASIN, 0.0, k), ring.call(BASIN, 0.0, k + 1), ring.call(BASIN, WALL, k + 1), ring.call(BASIN, WALL, k), stone, 0.0, out)
		buf.quad(ring.call(BASIN, WALL, k), ring.call(BASIN, WALL, k + 1), ring.call(BASIN - 0.12, WALL, k + 1), ring.call(BASIN - 0.12, WALL, k), stone.lightened(0.1), 0.0, Vector3.UP)
		buf.quad(ring.call(BASIN - 0.12, WALL, k), ring.call(BASIN - 0.12, WALL, k + 1), ring.call(BASIN - 0.12, WALL - 0.08, k + 1), ring.call(BASIN - 0.12, WALL - 0.08, k), stone.darkened(0.08), 0.0, -out)
		buf.tri(c3 + Vector3.UP * (WALL - 0.08), ring.call(BASIN - 0.12, WALL - 0.08, k), ring.call(BASIN - 0.12, WALL - 0.08, k + 1), water, 0.0, true)
	for k in 6:
		var a0 := TAU * k / 6.0
		var a1 := TAU * (k + 1) / 6.0
		var out := Vector3(cos((a0 + a1) * 0.5), 0.0, sin((a0 + a1) * 0.5))
		var p0 := c3 + Vector3(cos(a0) * 0.1, 0.0, sin(a0) * 0.1)
		var p1 := c3 + Vector3(cos(a1) * 0.1, 0.0, sin(a1) * 0.1)
		buf.quad(p0, p1, p1 + Vector3.UP * 0.75, p0 + Vector3.UP * 0.75, stone, 0.0, out)
		# the bowl on top, flaring out, with water in it
		var b0 := c3 + Vector3(cos(a0) * 0.36, 0.86, sin(a0) * 0.36)
		var b1 := c3 + Vector3(cos(a1) * 0.36, 0.86, sin(a1) * 0.36)
		buf.quad(p0 + Vector3.UP * 0.75, p1 + Vector3.UP * 0.75, b1, b0, stone.lightened(0.05), 0.0, out + Vector3.DOWN)
		buf.tri(c3 + Vector3.UP * 0.84, b0, b1, water.lightened(0.15), 0.0, true)


# ------------------------------------------------------------------ sampling

## Where streets meet, for things that travel along them: street id to a list
## of [place along it, the other street, place along that one].
func links() -> Dictionary:
	if _links_dirty:
		_links.clear()
		for s in streets:
			_links[s.id] = []
		_begin_pairs()
		for i in streets.size():
			for j in range(i + 1, streets.size()):
				if not _pair_near(i, j):
					continue
				var a: Street = streets[i]
				var b: Street = streets[j]
				for m in _meetings_of(a, b, _meet_cache):
					_links[a.id].append([m.x, b, m.y])
					_links[b.id].append([m.y, a, m.x])
		_end_pairs()
		_links_dirty = false
	return _links


## Whether the street stops at sample i with nothing to meet: no other
## street there, not back on itself, not by the water and not off the map.
func _dead_end(s: Street, i: int) -> bool:
	var n := s.pts.size()
	if i != 0 and i != n - 1:
		return false
	var p := s.pts[i]
	if absf(p.x) > Land.HALF - 3.0 or absf(p.y) > Land.HALF - 3.0:
		return false
	if not s.quay.is_empty() and s.quay[i] != 0:
		return false
	if p.distance_to(s.pts[n - 1 - i]) < s.reach() + 0.5:
		return false
	for o: Street in streets:
		if o != s and o.near_box(p, o.reach() + 0.5) and o.within(p, o.reach() + 0.5):
			return false
	return true


## A half circle of road at a dead end, with the kerb and pavement
## carried round it.
func _build_cap(s: Street, buf: MeshBuf, f: float, asphalt: Color, pave: Color, kerb: Color) -> void:
	const SEGS := 7
	var n := s.pts.size()
	var w := s.w()
	var median: float = KINDS[s.kind].median
	var verge: bool = KINDS[s.kind].verge
	var walk := s.kind == "walk"
	var c := _ptf(s, f)
	var side := _sidef(s, f)
	var out := (s.pts[0] - s.pts[1]).normalized() if f < 0.5 else (s.pts[n - 1] - s.pts[n - 2]).normalized()
	var y := _yf(s, f) + 0.03
	var c3 := Vector3(c.x, y, c.y)
	var at := func(th: float, r: float, dy: float) -> Vector3:
		var v := side * cos(th) + out * sin(th)
		return Vector3(c.x + v.x * r, y + dy, c.y + v.y * r)
	for k in SEGS:
		var t0 := PI * k / SEGS
		var t1 := PI * (k + 1) / SEGS
		var tm := (t0 + t1) * 0.5
		var o := side * cos(tm) + out * sin(tm)
		var o3 := Vector3(o.x, 0.0, o.y)
		buf.tri(c3, at.call(t0, w, 0.0), at.call(t1, w, 0.0), PAVING if walk else asphalt, MeshKit.SLABS if walk else MeshKit.ASPHALT, true)
		if verge or walk:
			buf.quad(at.call(t0, w, 0.0), at.call(t1, w, 0.0), at.call(t1, w + 0.12, 0.0), at.call(t0, w + 0.12, 0.0), kerb, 0.0, Vector3.UP)
			buf.quad(at.call(t0, w + 0.12, 0.0), at.call(t1, w + 0.12, 0.0), at.call(t1, w + 0.3, -SKIRT), at.call(t0, w + 0.3, -SKIRT), kerb.darkened(0.1), 0.0, o3 + Vector3.UP)
			continue
		# the kerb as a short slope up to the pavement, which saves a face
		buf.quad(at.call(t0, w, 0.0), at.call(t1, w, 0.0), at.call(t1, w + 0.05, CURB), at.call(t0, w + 0.05, CURB), kerb, 0.0, Vector3.UP - o3)
		buf.quad(at.call(t0, w + 0.05, CURB), at.call(t1, w + 0.05, CURB), at.call(t1, w + PAVE, CURB), at.call(t0, w + PAVE, CURB), pave, MeshKit.SLABS, Vector3.UP)
		buf.quad(at.call(t0, w + PAVE, CURB), at.call(t1, w + PAVE, CURB), at.call(t1, w + PAVE, -SKIRT), at.call(t0, w + PAVE, -SKIRT), kerb, 0.0, o3)
	if median > 0.0:
		# the planted strip's blunt end gets a kerb too
		var a := c - side * median
		var b := c + side * median
		buf.quad(Vector3(a.x, y, a.y), Vector3(b.x, y, b.y), Vector3(b.x, y + CURB, b.y), Vector3(a.x, y + CURB, a.y), kerb, 0.0, Vector3(out.x, 0.0, out.y))


func _ptf(s: Street, f: float) -> Vector2:
	var i := clampi(int(f), 0, s.pts.size() - 2)
	return s.pts[i].lerp(s.pts[i + 1], clampf(f - i, 0.0, 1.0))


func _yf(s: Street, f: float) -> float:
	var i := clampi(int(f), 0, s.pts.size() - 2)
	return lerpf(s.ys[i], s.ys[i + 1], clampf(f - i, 0.0, 1.0))


## Unit vector to the street's right at sample i.
func _side(s: Street, i: int) -> Vector2:
	var a := s.pts[maxi(i - 1, 0)]
	var b := s.pts[mini(i + 1, s.pts.size() - 1)]
	var t := (b - a).normalized()
	return Vector2(-t.y, t.x)


func _sidef(s: Street, f: float) -> Vector2:
	var i := clampi(int(f), 0, s.pts.size() - 2)
	return _side(s, i).lerp(_side(s, i + 1), clampf(f - i, 0.0, 1.0)).normalized()


func _atf(s: Street, f: float, off: float, dy: float) -> Vector3:
	var p := _ptf(s, f) + _sidef(s, f) * off
	return Vector3(p.x, _yf(s, f) + 0.03 + dy, p.y)


## One band of the cross-section between two rows, from (o0, dy0) to (o1, dy1).
static func _band(buf: MeshBuf, p0: Vector2, n0: Vector2, y0: float, p1: Vector2, n1: Vector2, y1: float,
		o0: float, dy0: float, o1: float, dy1: float, col: Color, e: float, hint: Vector3) -> void:
	var a := p0 + n0 * o0
	var b := p0 + n0 * o1
	var c := p1 + n1 * o1
	var d := p1 + n1 * o0
	buf.quad(Vector3(a.x, y0 + dy0, a.y), Vector3(b.x, y0 + dy1, b.y), Vector3(c.x, y1 + dy1, c.y), Vector3(d.x, y1 + dy0, d.y), col, e, hint)


# ------------------------------------------------------------------ saving

func to_data() -> Array:
	var out := []
	for s in streets:
		if not s.auto:
			out.append(street_data(s))
	return out


func street_data(s: Street) -> Dictionary:
	return data_of(raw_of(s))


## What street_data() is made from, copied out so another thread can turn
## it into data (see to_raw, data_of).
static func raw_of(s: Street) -> Array:
	return [s.key, s.kind, s.pts.duplicate(), s.ys.duplicate(), s.tunnels.duplicate()]


## to_data(), but only copied out: data_of() each, on any thread, gives it.
func to_raw() -> Array:
	var out := []
	for s in streets:
		if not s.auto:
			out.append(raw_of(s))
	return out


static func data_of(raw: Array) -> Dictionary:
	var p := []
	for v: Vector2 in raw[2]:
		p.append_array([snappedf(v.x, 0.01), snappedf(v.y, 0.01)])
	var y := []
	for v: float in raw[3]:
		y.append(snappedf(v, 0.01))
	var d := {"id": raw[0], "k": raw[1], "p": p, "y": y}
	if not (raw[4] as PackedVector2Array).is_empty():
		var t := []
		for v: Vector2 in raw[4]:
			t.append_array([v.x, v.y])
		d["t"] = t
	return d


func from_data(data: Array) -> void:
	clear()
	for d in data:
		var s := _from_dict(d)
		if s:
			streets.append(s)
			_junctions_dirty = true
	for s in streets:
		_build(s)
	for s in streets:
		added.emit(s)
	_refresh_ramps()


## Brings the streets back to `data` (as to_data() gave it), taking up and
## laying only the streets that differ. Returns whether any did.
func restore_data(data: Array) -> bool:
	var want := {}
	for d in data:
		want[d.id] = d
	var gone: Array[Street] = []
	for st: Street in streets:
		if st.auto:
			continue
		if not want.has(st.key) or street_data(st) != want[st.key]:
			gone.append(st)
		else:
			want.erase(st.key)
	for st in gone:
		remove_street(st)
	for d in data:
		if want.has(d.id):
			add_data(d, false)
	_refresh_ramps()
	return not gone.is_empty() or not want.is_empty()


## Lays one street exactly as saved (from another builder, or an undo).
func add_data(d: Dictionary, ramps := true) -> Street:
	var s := _from_dict(d)
	if s == null:
		return null
	streets.append(s)
	_junctions_dirty = true
	_build(s)
	for o in _touching(s):
		_build_later(o)
	added.emit(s)
	if ramps:
		_refresh_ramps()
	changed.emit()
	return s


func remove_street(s: Street) -> void:
	_take_up(s)
	_refresh_ramps()
	changed.emit()


## Takes a street up, re-laying the ones it touched.
func _take_up(s: Street) -> void:
	var touching := _touching(s)
	_remove(s)
	for o in touching:
		if o in streets:
			_build_later(o)


# ------------------------------------------------------------------ changing a road's kind

## Whether the Road tool's Change mode can turn s into another kind.
static func gradable(s: Street) -> bool:
	return not s.auto and GRADES.has(s.kind)


## The stretch of s, as (from, to) samples, that changes kind when the player
## picks it between samples fa and fb: out to the junction either side, or to
## its end, like a road between two crossroads in a real city.
func stretch(s: Street, fa: float, fb: float) -> Vector2:
	var n := s.pts.size()
	var a := 0.0
	var b := float(n - 1)
	for m in links().get(s.id, []):
		var o: Street = m[1]
		if o.auto:
			continue
		var f: float = m[0]
		if f <= fa + 1.0 and f > a:
			a = f
		if f >= fb - 1.0 and f < b:
			b = f
	if a <= MIN_PIECE:
		a = 0.0
	if b >= n - 1 - MIN_PIECE:
		b = n - 1.0
	return Vector2(a, b)


## Changes s to `kind` from sample a to b (as stretch() gave them), splitting
## it at those junctions when only part of it changes. Everything worked out
## from a road's kind follows: its height over the land (highways go over
## the streets they cross, and streets come back down to meet a highway made
## a street), bridges and quays, interchanges, junctions, and the side
## streets and walks that may not meet a highway stopping short of it.
## Returns the streets s now is (empty if nothing changed).
func rekind(s: Street, kind: String, a: float, b: float) -> Array:
	if not GRADES.has(kind) or not gradable(s) or not s in streets or s.kind == kind:
		return []
	var n := s.pts.size()
	var ia := roundi(a)
	var ib := roundi(b)
	if ia <= MIN_PIECE:
		ia = 0
	if ib >= n - 1 - MIN_PIECE:
		ib = n - 1
	if ib - ia < 2:
		return []
	var touching := _touching(s)
	# streets flying over it (or it over them) may come down to meet it now
	var flew := touching.filter(func(o): return _flies(o, s))
	var pieces: Array = []
	var c: Street = s
	if ia == 0 and ib == n - 1:
		_forget(s)
		s.kind = kind
		pieces.append(s)
	else:
		_remove(s, true)
		var runs := []
		if ia > 0:
			runs.append([0, ia, s.kind])
		runs.append([ia, ib, kind])
		if ib < n - 1:
			runs.append([ib, n - 1, s.kind])
		for r in runs:
			var ns := _new_street()
			ns.kind = r[2]
			ns.pts = s.pts.slice(r[0], r[1] + 1)
			ns.ys = s.ys.slice(r[0], r[1] + 1)
			ns.update_bounds()
			ns.spans = _bridges(ns)
			ns.quay = _quays(ns)
			streets.append(ns)
			pieces.append(ns)
			if r[2] == kind:
				# the stretch that changes keeps the road's key (saves, co-op)
				ns.key = s.key
				c = ns
	_junctions_dirty = true
	_grade(c)
	_conform(c)
	if c.kind == "highway":
		# as when one is drawn: the streets it crosses go up and over it
		for o in _touching(c):
			if _flies(o, c) and (o.kind != "highway" or o.key > c.key):
				_grade(o)
				_conform(o)
		_lower_onto(c)
	for o in flew:
		if o in streets and not o in pieces:
			_grade(o)
			_conform(o)
	_reconform_near(c)
	_conform_junctions(c)
	_laying[c.id] = 0.0
	for p: Street in pieces:
		_build(p)
	for o in _touching(c):
		_build_later(o)
	rekinded.emit(s, pieces)
	if KINDS[c.kind].verge:
		_clear_off(c)
	_refresh_ramps()
	changed.emit()
	return pieces


## Nobody walks onto a highway and no back street joins one: the side
## streets and walks that reach highway h stop short of it, a little way
## off its shoulder (any crossing it on a bridge of their own stay).
func _clear_off(h: Street) -> void:
	var r := h.reach() + 1.2
	for o: Street in _touching(h):
		if o.auto or not (o.kind == "side" or o.kind == "walk") or _flies(o, h):
			continue
		var keep := PackedByteArray()
		keep.resize(o.pts.size())
		var cut := false
		for i in o.pts.size():
			var near := h.near_box(o.pts[i], r) and h.within(o.pts[i], r)
			keep[i] = 0 if near else 1
			cut = cut or near
		if not cut:
			continue
		var runs := []
		var i := 0
		while i < keep.size():
			if keep[i] == 0:
				i += 1
				continue
			var j := i
			while j + 1 < keep.size() and keep[j + 1] == 1:
				j += 1
			if j - i >= 2 and (j - i) * SAMPLE >= 2.5:
				runs.append([i, j])
			i = j + 1
		_take_up(o)
		for run in runs:
			var ns := _new_street()
			ns.kind = o.kind
			ns.pts = o.pts.slice(run[0], run[1] + 1)
			ns.ys = o.ys.slice(run[0], run[1] + 1)
			ns.update_bounds()
			ns.spans = _bridges(ns)
			ns.quay = _quays(ns)
			streets.append(ns)
			_junctions_dirty = true
			_build(ns)
			added.emit(ns)


# ------------------------------------------------------------------ interchanges

## how far along the highway a ramp leaves it, from the street flying over
const RAMP_RUN := 30.0
## how far along the street flying over a ramp meets it, past its deck
const RAMP_MEET := 6.0


## Interchanges: wherever a main street or an avenue flies over a highway, a
## diamond of four ramps, one in each corner, from alongside the highway's
## outer lanes up to a crossroads on the street either side of its deck.
## Laid and taken up to match the streets there are, so every builder (and
## every reload) works out the same ones.
func _refresh_ramps() -> void:
	var want := {}
	for s: Street in streets:
		if s.auto or not (s.major() or s.kind == "highway"):
			continue
		for fly in _flyovers(s):
			for r in (_cloverleaf(s, fly) if s.kind == "highway" else _diamond(s, fly)):
				want[r.key] = r.pts
	for s: Street in streets.duplicate():
		if not s.auto:
			continue
		if want.has(s.key) and want[s.key] == s.src:
			want.erase(s.key)
		else:
			_take_up(s)
	for k: String in want:
		var raw: PackedVector2Array = want[k]
		var s := _new_street()
		s.key = k
		s.kind = "ramp"
		s.auto = true
		s.src = raw
		s.pts = _resample(raw, SAMPLE)
		if s.pts.size() < 3:
			continue
		s.update_bounds()
		_grade(s)
		streets.append(s)
		_junctions_dirty = true
		_conform(s)
		_reconform_near(s)
		_conform_junctions(s)
		_build(s)
		for o in _touching(s):
			_build_later(o)
		added.emit(s)


## Where highway s flies over highway o, a cloverleaf: in each corner a loop
## (leaving one highway alongside, turning three quarters of a circle and
## joining the other alongside) and, round the outside of it, a sweeping
## ramp from one highway further out to the other. [{key, pts}]
func _cloverleaf(s: Street, fly: Dictionary) -> Array:
	const R := 7.0
	var out: Array = []
	var o: Street = fly.hw
	var x := _ptf(o, fly.fo)
	var d1 := (_ptf(o, minf(fly.fo + 1.0, o.pts.size() - 1)) - _ptf(o, maxf(fly.fo - 1.0, 0.0))).normalized()
	var d2 := (_ptf(s, minf(fly.f + 1.0, s.pts.size() - 1)) - _ptf(s, maxf(fly.f - 1.0, 0.0))).normalized()
	var sin_a := absf(d1.cross(d2))
	if sin_a < 0.5:
		return out
	var off := o.w() + KINDS.ramp.w
	for t1: float in [-1.0, 1.0]:
		for t2: float in [-1.0, 1.0]:
			var e1 := d1 * t1
			var e2 := d2 * t2
			# the corner between the highways heading e1 and e2: its loop's
			# middle stands off both by its radius and the ramp's own offset
			var n1 := Vector2(-e1.y, e1.x) * signf(Vector2(-e1.y, e1.x).dot(e2))
			var n2 := Vector2(-e2.y, e2.x) * signf(Vector2(-e2.y, e2.x).dot(e1))
			var a := (off + R) / sin_a
			var c := x + e1 * a + e2 * a
			var p1 := c - n1 * R
			var p2 := c - n2 * R
			var far := (off + R * 2.0) / sin_a + 26.0
			var g1: float = fly.fo + t1 * far / SAMPLE
			var g2: float = fly.f + t2 * far / SAMPLE
			if g1 < 1.0 or g1 > o.pts.size() - 2.0 or g2 < 1.0 or g2 > s.pts.size() - 2.0:
				continue
			# the loop, the long way round (away from the crossing)
			var a1 := (p1 - c).angle()
			var a2 := (p2 - c).angle()
			var sweep := wrapf(a2 - a1, -PI, PI)
			sweep = sweep - TAU * signf(sweep)
			var loop := PackedVector2Array()
			for k in 37:
				loop.append(c + Vector2.from_angle(a1 + sweep * k / 36.0) * R)
			var tag := "~%s~%s~%d%d" % [s.key, o.key, int(t1), int(t2)]
			out.append({"key": tag + "l", "pts": loop})
			# round the outside, from further out on one to further out on the
			# other, leaving and joining each alongside
			var q1 := _ptf(o, g1) + n1 * off
			var q2 := _ptf(s, g2) + n2 * off
			var k1 := q1 - e1 * far * 0.25
			var k2 := q2 - e2 * far * 0.25
			var sweep_pts := PackedVector2Array()
			for k in 41:
				var t := k / 40.0
				var u := 1.0 - t
				sweep_pts.append(q1 * u * u * u + k1 * 3.0 * u * u * t + k2 * 3.0 * u * t * t + q2 * t * t * t)
			out.append({"key": tag + "o", "pts": sweep_pts})
	return out


## The four ramps of a diamond where street s flies over a highway, as
## [{key, pts}]: each leaves the highway alongside its outer lane RAMP_RUN
## ahead of or behind the crossing, runs beside it a while, then swings out
## to meet s RAMP_MEET past the end of its deck.
func _diamond(s: Street, fly: Dictionary) -> Array:
	var out: Array = []
	var o: Street = fly.hw
	var no := o.pts.size()
	var ns := s.pts.size()
	var nh := _sidef(o, fly.fo)
	var ds := (_ptf(s, minf(fly.f + 1.0, ns - 1)) - _ptf(s, maxf(fly.f - 1.0, 0.0))).normalized()
	var off := o.w() + KINDS.ramp.w
	for side: float in [-1.0, 1.0]:
		# which way along s leads to this side of the highway
		var fwd := signf(ds.dot(nh)) * side
		var fs: float = (fly.b if fwd > 0.0 else fly.a) + fwd * RAMP_MEET / SAMPLE
		if fs < 2.0 or fs > ns - 3.0:
			continue
		var meet := _ptf(s, fs)
		for way: float in [-1.0, 1.0]:
			var fo: float = fly.fo + way * RAMP_RUN / SAMPLE
			if fo < 1.0 or fo > no - 2.0:
				continue
			var d := (_ptf(o, minf(fo + 1.0, no - 1)) - _ptf(o, maxf(fo - 1.0, 0.0))).normalized()
			var start := _ptf(o, fo) + _sidef(o, fo) * side * off
			var c1 := start - d * way * RAMP_RUN * 0.45
			var d0 := (_ptf(o, minf(fly.fo + 1.0, no - 1)) - _ptf(o, maxf(fly.fo - 1.0, 0.0))).normalized()
			var c2 := meet + d0 * way * RAMP_RUN * 0.3
			var pts := PackedVector2Array()
			for k in 41:
				var t := k / 40.0
				var u := 1.0 - t
				pts.append(start * u * u * u + c1 * 3.0 * u * u * t + c2 * 3.0 * u * t * t + meet * t * t * t)
			out.append({"key": "~%s~%s~%d%d" % [s.key, o.key, int(side), int(way)], "pts": pts})
	return out


func by_id(id: int) -> Street:
	# (looked up by id, the list read again whenever the streets change)
	if _ids_rev != rev or _ids_n != streets.size():
		_ids.clear()
		for s: Street in streets:
			_ids[s.id] = s
		_ids_rev = rev
		_ids_n = streets.size()
	return _ids.get(id)


var _ids := {}
var _ids_rev := -1
var _ids_n := -1


func by_key(k: String) -> Street:
	for s in streets:
		if s.key == k:
			return s
	return null


func _new_street() -> Street:
	var s := Street.new()
	s.id = _next_id
	_next_id += 1
	if tag == "":
		tag = "%04x" % (randi() % 65536)
	s.key = "%s%d_%d" % [tag, Time.get_ticks_msec() % 100000, s.id]
	return s


func _from_dict(d: Variant) -> Street:
	if not d is Dictionary:
		return null
	var s := _new_street()
	if str(d.get("id", "")) != "":
		s.key = str(d.id)
	s.kind = str(d.get("k", "main"))
	if not KINDS.has(s.kind):
		s.kind = "main"
	var p: Array = d.get("p", [])
	var y: Array = d.get("y", [])
	for i in range(0, p.size() - 1, 2):
		s.pts.append(Vector2(float(p[i]), float(p[i + 1])))
	for v in y:
		s.ys.append(float(v))
	if s.pts.size() < 2 or s.ys.size() != s.pts.size():
		return null
	s.update_bounds()
	s.spans = _bridges(s)
	s.quay = _quays(s)
	var t: Array = d.get("t", [])
	for i in range(0, t.size() - 1, 2):
		var a := clampi(int(t[i]), 0, s.pts.size() - 1)
		var b := clampi(int(t[i + 1]), a, s.pts.size() - 1)
		s.tunnels.append(Vector2(a, b))
	return s
