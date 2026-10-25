class_name BrushMask
extends RefCounted
## Where a Grow or Green dab paints: a crisp disc that keeps to its own side
## of the streets and stops where ground of another colour begins, so
## districts meet in clean borders instead of blurring into each other.
## A stroke started on a colour may paint over that colour (to repaint a
## district); every other colour it fills up to and leaves alone. Started on
## a street, it paints both sides of it, as far as the next street.

## what a ground sample is painted as, besides a district (a Land.USES index)
const EMPTY := -1
const PARK := 100
## the most ground a stroke's block fill takes in one go (m²), and how much
## ground it may look over at the end of a stroke
const BLOCK_MAX := 2500
const FILL_LOOK := 60000
## how far a filled block may reach past the stroke
const FILL_MARGIN := 24.0
## steps into a street's ground the paint takes from the side it was painted
## on, so the houses along it know which district they front
const KERB_STEPS := 2

var i0 := 0
var j0 := 0
var w := 0
var h := 0
## how much of each sample in the window the dab covers (0: none), row by row
var cov := PackedFloat32Array()
## which samples in the window lie under a street and its pavements
var road := PackedByteArray()
var centre := Vector2.ZERO
var radius := 0.0
## how many samples it covers more than half of
var count := 0


## What the ground at sample k is painted as: PARK, a district, or EMPTY.
static func class_of(land: Land, k: int) -> int:
	if land.green[k] >= 0.5:
		return PARK
	if land.zone[k] < 0.5:
		return EMPTY
	var lv := land.level[k]
	return Land._use_of(lv) if lv >= 0.5 else 0


static func class_at(land: Land, p: Vector2) -> int:
	var i := clampi(int(round((p.x + Land.HALF) / Land.STEP)), 0, Land.CELLS)
	var j := clampi(int(round((p.y + Land.HALF) / Land.STEP)), 0, Land.CELLS)
	return class_of(land, j * Land.SIDE + i)


func _window(lo: Vector2, hi: Vector2) -> void:
	i0 = maxi(0, int(floor((lo.x + Land.HALF) / Land.STEP)))
	j0 = maxi(0, int(floor((lo.y + Land.HALF) / Land.STEP)))
	var i1 := mini(Land.CELLS, int(ceil((hi.x + Land.HALF) / Land.STEP)))
	var j1 := mini(Land.CELLS, int(ceil((hi.y + Land.HALF) / Land.STEP)))
	w = maxi(i1 - i0 + 1, 1)
	h = maxi(j1 - j0 + 1, 1)
	cov = PackedFloat32Array()
	cov.resize(w * h)
	count = 0


func _pos(q: int) -> Vector2:
	return Vector2((i0 + q % w) * Land.STEP - Land.HALF, (j0 + q / w) * Land.STEP - Land.HALF)


func _k(q: int) -> int:
	return (j0 + q / w) * Land.SIDE + i0 + q % w


## Marks the samples in the window that lie under a street.
func _rasterise(streets: Streets) -> void:
	road = PackedByteArray()
	road.resize(w * h)
	var lo := Vector2(i0, j0) * Land.STEP - Vector2.ONE * Land.HALF
	var hi := lo + Vector2(w - 1, h - 1) * Land.STEP
	for st: Streets.Street in streets.streets:
		# at least a sample wide, so no gap in it lets the paint slip across
		var r := maxf(st.reach(), 1.0)
		if st.hi.x < lo.x - r or st.lo.x > hi.x + r or st.hi.y < lo.y - r or st.lo.y > hi.y + r:
			continue
		var r2 := r * r
		for s in st.pts.size() - 1:
			var a := st.pts[s]
			var b := st.pts[s + 1]
			if maxf(a.x, b.x) < lo.x - r or minf(a.x, b.x) > hi.x + r or maxf(a.y, b.y) < lo.y - r or minf(a.y, b.y) > hi.y + r:
				continue
			var ab := b - a
			var l2 := maxf(ab.length_squared(), 1e-6)
			var ci0 := clampi(int(ceil((minf(a.x, b.x) - r + Land.HALF) / Land.STEP)) - i0, 0, w - 1)
			var ci1 := clampi(int(floor((maxf(a.x, b.x) + r + Land.HALF) / Land.STEP)) - i0, 0, w - 1)
			var cj0 := clampi(int(ceil((minf(a.y, b.y) - r + Land.HALF) / Land.STEP)) - j0, 0, h - 1)
			var cj1 := clampi(int(floor((maxf(a.y, b.y) + r + Land.HALF) / Land.STEP)) - j0, 0, h - 1)
			for jj in range(cj0, cj1 + 1):
				var row := jj * w
				var pz := (j0 + jj) * Land.STEP - Land.HALF
				for ii in range(ci0, ci1 + 1):
					if road[row + ii] == 1:
						continue
					var p := Vector2((i0 + ii) * Land.STEP - Land.HALF, pz)
					var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
					if p.distance_squared_to(a + ab * t) < r2:
						road[row + ii] = 1


static func _claims(c: int, own: int, over: int) -> bool:
	return c == EMPTY or c == own or c == over


## Works out the dab at `c` of radius `r` painting `own`, in a stroke begun
## on ground painted `over`.
func compute(land: Land, streets: Streets, c: Vector2, r: float, own: int, over: int) -> void:
	centre = c
	radius = r
	var reach := r + 0.5
	_window(c - Vector2(reach, reach), c + Vector2(reach, reach))
	_rasterise(streets)
	var si := clampi(int(round((c.x + Land.HALF) / Land.STEP)) - i0, 0, w - 1)
	var sj := clampi(int(round((c.y + Land.HALF) / Land.STEP)) - j0, 0, h - 1)
	var start := sj * w + si
	if road[start] == 0 and not _claims(class_of(land, _k(start)), own, over):
		return
	var seen := PackedByteArray()
	seen.resize(w * h)
	seen[start] = 1
	var queue := PackedInt32Array([start])
	var head := 0
	while head < queue.size():
		var q := queue[head]
		head += 1
		var d := _pos(q).distance_to(c)
		cov[q] = clampf(reach - d, 0.0, 1.0) if q != start else 1.0
		var on_road := road[q] == 1
		var ii := q % w
		var jj := q / w
		for n in 4:
			var ni := ii + (1 if n == 0 else -1 if n == 1 else 0)
			var nj := jj + (1 if n == 2 else -1 if n == 3 else 0)
			if ni < 0 or nj < 0 or ni >= w or nj >= h:
				continue
			var nq := nj * w + ni
			if seen[nq] == 1 or _pos(nq).distance_to(c) >= reach:
				continue
			if road[nq] == 1:
				# off the street, the paint stops at its kerb (and only
				# steps onto it below, from the side it is on)
				if not on_road:
					continue
			elif not _claims(class_of(land, _k(nq)), own, over):
				continue
			seen[nq] = 1
			queue.append(nq)
	_onto_kerbs(c, reach)


## Carries the paint a couple of samples onto the streets it meets, so the
## plots along them see the district painted on their side.
func _onto_kerbs(c: Vector2, reach: float) -> void:
	var front := PackedInt32Array()
	for q in w * h:
		if cov[q] > 0.0 and road[q] == 0:
			front.append(q)
	for step in KERB_STEPS:
		var next := PackedInt32Array()
		for q in front:
			var ii := q % w
			var jj := q / w
			for n in 4:
				var ni := ii + (1 if n == 0 else -1 if n == 1 else 0)
				var nj := jj + (1 if n == 2 else -1 if n == 3 else 0)
				if ni < 0 or nj < 0 or ni >= w or nj >= h:
					continue
				var nq := nj * w + ni
				if road[nq] == 0 or cov[nq] > 0.0:
					continue
				var a := clampf(reach - _pos(nq).distance_to(c), 0.0, 1.0)
				if a > 0.0:
					cov[nq] = a
					next.append(nq)
		front = next


## Whether the dab covers the point p (more than half of its sample).
func covers(p: Vector2) -> bool:
	var ii := int(round((p.x + Land.HALF) / Land.STEP)) - i0
	var jj := int(round((p.y + Land.HALF) / Land.STEP)) - j0
	if ii < 0 or jj < 0 or ii >= w or jj >= h:
		return false
	return cov[jj * w + ii] >= 0.5


## Paints the dab into the land: "grow" as district `use` at level `lv`,
## "green" as parks. Returns how many samples it turned to `own`.
func apply(land: Land, mode: String, use: int, lv: float) -> int:
	var own := PARK if mode == "green" else use
	var base := use * Land.USE_STRIDE + lv
	var claimed := 0
	for q in w * h:
		var a := cov[q]
		if a <= 0.0:
			continue
		var k := _k(q)
		var was := class_of(land, k)
		land.zone[k] = maxf(land.zone[k], a)
		if mode == "green":
			land.green[k] = maxf(land.green[k], a)
		elif a >= 0.5:
			land.level[k] = base
			land.green[k] = 0.0
		elif land.level[k] < 0.5 or was == EMPTY:
			# the soft rim of the disc takes its colour too
			land.level[k] = base
		if a >= 0.5:
			count += 1
		if was != own and class_of(land, k) == own:
			claimed += 1
	land.mark_painted(i0, j0, i0 + w - 1, j0 + h - 1)
	return claimed


## The Clear brush: wipes the painting in a crisp disc.
static func clear(land: Land, c: Vector2, r: float) -> void:
	var b := BrushMask.new()
	var reach := r + 0.5
	b._window(c - Vector2(reach, reach), c + Vector2(reach, reach))
	for q in b.w * b.h:
		var a := clampf(reach - b._pos(q).distance_to(c), 0.0, 1.0)
		if a <= 0.0:
			continue
		var k := b._k(q)
		land.zone[k] = minf(land.zone[k], 1.0 - a)
		land.green[k] = minf(land.green[k], 1.0 - a)
		if a >= 0.5:
			land.level[k] = 0.0
	land.mark_painted(b.i0, b.j0, b.i0 + b.w - 1, b.j0 + b.h - 1)


## At the end of a stroke: the rest of each block (ground walled in by
## streets, other colours and the stroke's own paint) that the stroke mostly
## covered fills in too, so a few strokes paint whole blocks cleanly. Returns
## the mask it painted (count 0: nothing).
static func fill_blocks(land: Land, streets: Streets, lo: Vector2, hi: Vector2, own: int, over: int, mode: String, use: int, lv: float, painted: int) -> BrushMask:
	var b := BrushMask.new()
	var m := Vector2(FILL_MARGIN, FILL_MARGIN)
	b._window(lo - m, hi + m)
	if b.w * b.h > FILL_LOOK * 2 or painted <= 0:
		return b
	b._rasterise(streets)
	var label := PackedByteArray()
	label.resize(b.w * b.h)
	var most := mini(BLOCK_MAX, maxi(12, int(painted * 0.8)))
	var budget := FILL_LOOK
	var si0 := clampi(int(floor((lo.x + Land.HALF) / Land.STEP)) - b.i0, 0, b.w - 1)
	var si1 := clampi(int(ceil((hi.x + Land.HALF) / Land.STEP)) - b.i0, 0, b.w - 1)
	var sj0 := clampi(int(floor((lo.y + Land.HALF) / Land.STEP)) - b.j0, 0, b.h - 1)
	var sj1 := clampi(int(ceil((hi.y + Land.HALF) / Land.STEP)) - b.j0, 0, b.h - 1)
	var any := false
	for jj in range(sj0, sj1 + 1):
		for ii in range(si0, si1 + 1):
			var q := jj * b.w + ii
			if b.road[q] == 1 or class_of(land, b._k(q)) != own:
				continue
			for n in 4:
				var ni := ii + (1 if n == 0 else -1 if n == 1 else 0)
				var nj := jj + (1 if n == 2 else -1 if n == 3 else 0)
				if ni < 0 or nj < 0 or ni >= b.w or nj >= b.h:
					continue
				var nq := nj * b.w + ni
				if label[nq] != 0 or not b._fillable(land, nq, own, over):
					continue
				var part := b._flood(land, nq, own, over, label, most)
				budget -= part.size()
				if part.is_empty():
					continue
				for p in part:
					b.cov[p] = 1.0
				any = true
			if budget <= 0:
				break
		if budget <= 0:
			break
	if not any:
		return b
	var mid := Vector2(b.i0 + b.w * 0.5, b.j0 + b.h * 0.5) * Land.STEP - Vector2.ONE * Land.HALF
	b._onto_kerbs(mid, INF)
	b.apply(land, mode, use, lv)
	return b


func _fillable(land: Land, q: int, own: int, over: int) -> bool:
	if road[q] == 1:
		return false
	var k := _k(q)
	if land.heights[k] <= 0.0:
		return false
	var c := class_of(land, k)
	return c != own and (c == EMPTY or c == over)


## One walled-in piece of ground from q: its samples, or none when it runs
## out of the window or is bigger than `most` (open country, not a block).
func _flood(land: Land, q: int, own: int, over: int, label: PackedByteArray, most: int) -> PackedInt32Array:
	var part := PackedInt32Array([q])
	label[q] = 1
	var open := false
	var head := 0
	while head < part.size():
		var p := part[head]
		head += 1
		var ii := p % w
		var jj := p / w
		if ii == 0 or jj == 0 or ii == w - 1 or jj == h - 1 or part.size() > most:
			open = true
			break
		for n in 4:
			var nq := p + (1 if n == 0 else -1 if n == 1 else w if n == 2 else -w)
			if label[nq] != 0 or not _fillable(land, nq, own, over):
				continue
			label[nq] = 1
			part.append(nq)
	if open:
		# the rest of it stays marked, so no other seed floods it again
		return PackedInt32Array()
	return part
