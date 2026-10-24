class_name BridgeGen
extends RefCounted
## What carries a street's bridges over the water, by how far each crosses:
## a row of stone arches over a short stretch, a steel arch over the deck, a
## cable-stayed span hung from white pylons, or for the longest a suspension
## bridge between two tall towers. Each gets lamps along its pavements and,
## all but the stone ones, an open railing. Worked out from the street alone
## (its points and kind), so every player sees the same bridge.

const STONE := Color(0.79, 0.72, 0.61)
const STONE_DARK := Color(0.4, 0.36, 0.31)
const WHITE := Color(0.93, 0.93, 0.91)
const CABLE := Color(0.86, 0.87, 0.88)
const POLE := Color(0.24, 0.26, 0.29)
const BEACON := Color(1.0, 0.12, 0.08)
## the painted steel of arches and towers
const STEEL := [Color(0.33, 0.52, 0.66), Color(0.76, 0.31, 0.22), Color(0.29, 0.53, 0.44), Color(0.36, 0.38, 0.42)]
## how far apart the lamps and the railing's posts stand, in samples
const LAMP_GAP := 16
const POST_GAP := 2
## how high the railing's top rail is over the pavement
const RAIL := 0.22
## the city shader's code for a light in its own colour that never blinks:
## arches, towers and main cables are floodlit at night
const FLOOD := 2.75


## every bridge in this style instead (screenshots and tests)
static var force := ""


## The style of each of a street's bridges (see the class notes).
static func styles(s: Streets.Street) -> PackedStringArray:
	var out := PackedStringArray()
	for sp in s.spans:
		if force != "":
			out.append(force)
			continue
		var water := (sp.y - sp.x - 2.0 * Streets.BANK) * Streets.SAMPLE
		var pick := absi(hash(Vector2i(s.pts[int(sp.x)].round()) + Vector2i(s.pts[int(sp.y)].round())))
		if water < 7.0:
			out.append("stone")
		elif water < 30.0:
			out.append(["stone", "arch", "stayed"][pick % 3])
		elif water < 55.0:
			out.append(["arch", "stayed", "suspension"][pick % 3])
		else:
			out.append("suspension")
	return out


## Which of `spans` sample index f lies on, or -1.
static func span_at(spans: PackedVector2Array, f: float) -> int:
	for k in spans.size():
		if f > spans[k].x and f < spans[k].y:
			return k
	return -1


## Puts up the bridges of street `s` that are laid out as far as `upto`: the
## lighter, shadowless parts (railing posts, lamps, stone arches) into `buf`,
## the towers, arches and cables that cast shadows into `sup`.
static func build(st: Streets, s: Streets.Street, buf: Streets.MeshBuf, sup: Streets.MeshBuf, upto: float, kinds: PackedStringArray) -> void:
	for k in s.spans.size():
		var sp := s.spans[k]
		if sp.y > upto + 0.01:
			continue
		var g := Geo.new(st, s)
		var a := sp.x + Streets.BANK
		var b := sp.y - Streets.BANK
		var water := (b - a) * Streets.SAMPLE
		var pick := absi(hash(Vector2i(s.pts[int(sp.x)].round())))
		var steel: Color = STEEL[pick % STEEL.size()]
		_lamps(g, buf, sp, kinds[k] == "stone")
		match kinds[k]:
			"stone":
				_stone(g, buf, a, b, water)
			"arch":
				_railing(g, buf, sp)
				_arch(g, sup, a, b, water, steel)
			"stayed":
				_railing(g, buf, sp)
				_stayed(g, sup, a, b, water)
			"suspension":
				_railing(g, buf, sp)
				_suspension(g, sup, sp, a, b, water, steel)


## Positions along a street, worked out from its samples.
class Geo:
	var st: Streets
	var s: Streets.Street
	## half the deck's width, out to the parapet's outer face
	var edge := 0.0
	var verge := false

	func _init(streets: Streets, street: Streets.Street) -> void:
		st = streets
		s = street
		verge = Streets.KINDS[s.kind].verge
		edge = s.w() + (0.3 if verge else Streets.PAVE)

	## The point `off` metres to the right of the street at index f, `h` over its surface.
	func at(f: float, off: float, h: float) -> Vector3:
		var p := st._ptf(s, f) + st._sidef(s, f) * off
		return Vector3(p.x, st._yf(s, f) + 0.03 + h, p.y)

	## The surface of the street at f.
	func y(f: float) -> float:
		return st._yf(s, f) + 0.03

	func ground(f: float, off: float) -> float:
		var p := st._ptf(s, f) + st._sidef(s, f) * off
		return st.land.height_at(p.x, p.y)

	## The pavement's level (the shoulder on a highway).
	func walk() -> float:
		return 0.0 if verge else Streets.CURB


## A square-sectioned bar `t` thick from a to b; `caps` closes its ends.
static func beam(buf: Streets.MeshBuf, a: Vector3, b: Vector3, t: float, col: Color, e := 0.0, caps := false) -> void:
	var d := b - a
	if d.length_squared() < 1e-8:
		return
	d = d.normalized()
	var u := d.cross(Vector3.UP)
	if u.length_squared() < 1e-4:
		u = d.cross(Vector3.RIGHT)
	u = u.normalized() * t * 0.5
	var v := d.cross(u).normalized() * t * 0.5
	var cs := [u + v, -u + v, -u - v, u - v]
	for k in 4:
		var p: Vector3 = cs[k]
		var q: Vector3 = cs[(k + 1) % 4]
		buf.quad(a + p, b + p, b + q, a + q, col, e, p + q)
	if caps:
		buf.quad(b + cs[0], b + cs[1], b + cs[2], b + cs[3], col, e, d)
		buf.quad(a + cs[0], a + cs[1], a + cs[2], a + cs[3], col, e, -d)


## An upright block on footprint `pts` (going round) from y0 up to y1, with a top.
static func prism(buf: Streets.MeshBuf, pts: PackedVector2Array, y0: float, y1: float, col: Color, top_col: Color) -> void:
	var c := Vector2.ZERO
	for p in pts:
		c += p
	c /= pts.size()
	for k in pts.size():
		var p := pts[k]
		var q := pts[(k + 1) % pts.size()]
		var out := (p + q) * 0.5 - c
		buf.quad(Vector3(p.x, y0, p.y), Vector3(q.x, y0, q.y), Vector3(q.x, y1, q.y), Vector3(p.x, y1, p.y), col, 0.0, Vector3(out.x, 0.0, out.y))
	for k in range(1, pts.size() - 1):
		buf.tri(Vector3(pts[0].x, y1, pts[0].y), Vector3(pts[k].x, y1, pts[k].y), Vector3(pts[k + 1].x, y1, pts[k + 1].y), top_col, 0.0)


## A pier standing in the water at f, `half` wide across the street and
## `thick` along it, pointed upstream and down so the water parts round it.
static func _pier(g: Geo, buf: Streets.MeshBuf, f: float, half: float, thick: float, top: float, col: Color) -> void:
	var c := g.st._ptf(g.s, f)
	var nrm := g.st._sidef(g.s, f)
	var along := Vector2(-nrm.y, nrm.x)
	var t := thick * 0.5
	var pts := PackedVector2Array([c - nrm * half - along * t, c - nrm * (half + t * 1.4), c - nrm * half + along * t,
		c + nrm * half + along * t, c + nrm * (half + t * 1.4), c + nrm * half - along * t])
	var bottom := minf(g.st.land.height_at(c.x, c.y), -0.2) - 0.2
	prism(buf, pts, bottom, top, col, col.lightened(0.08))


## Lamp posts along both pavements, staggered; on a stone bridge, lanterns
## on short posts, otherwise a tall post with an arm out over the road.
static func _lamps(g: Geo, buf: Streets.MeshBuf, sp: Vector2, stone: bool) -> void:
	var count := int((sp.y - sp.x) / LAMP_GAP)
	var step := (sp.y - sp.x) / (count + 1)
	for k in count:
		var f := sp.x + step * (k + 1)
		var side := -1.0 if k % 2 == 0 else 1.0
		var off := side * (g.edge - 0.14)
		var base := g.at(f, off, g.walk())
		if stone:
			var post := base + Vector3.UP * 0.7
			beam(buf, base, post, 0.08, STONE_DARK)
			beam(buf, post, post + Vector3.UP * 0.16, 0.13, POLE, 2.0, true)
			continue
		var top := base + Vector3.UP * 1.25
		beam(buf, base, top, 0.06, POLE)
		var arm := g.at(f, off - side * 0.4, g.walk() + 1.3)
		beam(buf, top, arm, 0.05, POLE)
		beam(buf, arm + Vector3.DOWN * 0.03, arm + Vector3.DOWN * 0.09, 0.15, POLE, 2.0, true)


## Posts holding the open railing up, every metre or so.
static func _railing(g: Geo, buf: Streets.MeshBuf, sp: Vector2) -> void:
	var f := sp.x + 1.0
	while f < sp.y - 0.5:
		for side: float in [-1.0, 1.0]:
			var off := side * (g.edge - 0.03)
			beam(buf, g.at(f, off, g.walk()), g.at(f, off, g.walk() + RAIL), 0.035, POLE)
		f += POST_GAP


## Stone arches from bank to bank, about four metres each, springing from
## piers with cutwaters: a face over each arch on both sides, a darker
## barrel under it, and a pale ring of voussoirs round its edge.
static func _stone(g: Geo, buf: Streets.MeshBuf, a: float, b: float, water: float) -> void:
	var n := maxi(1, roundi(water / 4.0))
	var pier := 0.7 / Streets.SAMPLE
	var span := ((b - a) - (n - 1) * pier) / n
	var spring := -0.15
	const SEG := 8
	for k in n:
		var f0 := a + k * (span + pier)
		var f1 := f0 + span
		var crown := minf(g.y(f0), g.y(f1)) - Streets.DECK_DEPTH - 0.08
		var prev := {}
		for q in SEG + 1:
			var t := float(q) / SEG
			var f := lerpf(f0, f1, t)
			var ay := spring + (crown - spring) * pow(sin(PI * t), 0.55)
			var soffit := g.y(f) - Streets.DECK_DEPTH
			var cur := {"f": f, "ay": ay, "top": soffit}
			if not prev.is_empty():
				for side: float in [-1.0, 1.0]:
					var o := side * g.edge
					var hint := g.at(f, side, 0.0) - g.at(f, 0.0, 0.0)
					# the face over the arch, up to the deck
					buf.quad(_p(g, prev.f, o, prev.top), _p(g, f, o, soffit), _p(g, f, o, ay), _p(g, prev.f, o, prev.ay), STONE, 0.0, hint)
					# the ring of voussoirs, standing a little proud
					var o2 := side * (g.edge + 0.03)
					buf.quad(_p(g, prev.f, o2, prev.ay + 0.16), _p(g, f, o2, ay + 0.16), _p(g, f, o2, ay), _p(g, prev.f, o2, prev.ay), STONE.lightened(0.12), 0.0, hint)
				# the barrel underneath
				buf.quad(_p(g, prev.f, -g.edge, prev.ay), _p(g, f, -g.edge, ay), _p(g, f, g.edge, ay), _p(g, prev.f, g.edge, prev.ay), STONE_DARK, 0.0, Vector3.DOWN)
			prev = cur
		if k < n - 1:
			# the pier between this arch and the next, under the deck
			var pf := f1 + pier * 0.5
			var soffit := g.y(pf) - Streets.DECK_DEPTH
			for side: float in [-1.0, 1.0]:
				var o := side * g.edge
				var hint := g.at(pf, side, 0.0) - g.at(pf, 0.0, 0.0)
				buf.quad(_p(g, f1, o, soffit), _p(g, f1 + pier, o, soffit), _p(g, f1 + pier, o, spring - 0.6), _p(g, f1, o, spring - 0.6), STONE, 0.0, hint)
			_pier(g, buf, pf, g.edge, pier * Streets.SAMPLE, spring + 0.45, STONE.darkened(0.06))


static func _p(g: Geo, f: float, off: float, y: float) -> Vector3:
	var p := g.at(f, off, 0.0)
	return Vector3(p.x, y, p.z)


## A steel arch over each side of the deck from bank to bank, with hangers
## down to the deck and, when tall enough, braces across between the two.
static func _arch(g: Geo, sup: Streets.MeshBuf, a: float, b: float, water: float, col: Color) -> void:
	var h := clampf(water * 0.24, 2.0, 7.5)
	const SEG := 14
	var off := g.edge + 0.12
	var ribs := [[], []]
	for q in SEG + 1:
		var t := float(q) / SEG
		var f := lerpf(a, b, t)
		for i in 2:
			ribs[i].append(g.at(f, off * (-1.0 if i == 0 else 1.0), g.walk() + h * 4.0 * t * (1.0 - t)))
	for i in 2:
		for q in SEG:
			beam(sup, ribs[i][q], ribs[i][q + 1], 0.24, col, FLOOD)
	# braces across the top, where they clear the traffic
	for q in range(1, SEG):
		var rise: float = ribs[0][q].y - g.y(lerpf(a, b, float(q) / SEG))
		if q % 2 == 1 and rise > 2.0:
			beam(sup, ribs[0][q], ribs[1][q], 0.12, col.darkened(0.15), FLOOD)
	# hangers down to the deck's edge
	var f := a + 2.0
	while f < b - 1.5:
		var t := (f - a) / (b - a)
		var rise := h * 4.0 * t * (1.0 - t)
		if rise > 0.35:
			for side: float in [-1.0, 1.0]:
				beam(sup, g.at(f, side * off, g.walk()), g.at(f, side * off, g.walk() + rise), 0.045, CABLE)
		f += 3.0
	# the arch's feet, on the banks
	for fe: float in [a, b]:
		for side: float in [-1.0, 1.0]:
			beam(sup, g.at(fe, side * off, -Streets.DECK_DEPTH - 0.4), g.at(fe, side * off, g.walk() + 0.2), 0.4, col.darkened(0.1), 0.0, true)


## White pylons, one in the middle of a short crossing or two on a longer
## one, each with fans of cables down to both edges of the deck.
static func _stayed(g: Geo, sup: Streets.MeshBuf, a: float, b: float, water: float) -> void:
	var at: Array = [(a + b) * 0.5] if water < 30.0 else [lerpf(a, b, 0.3), lerpf(a, b, 0.7)]
	var h := clampf(water * (0.42 if at.size() == 1 else 0.26), 3.6, 12.0)
	var reach := (b - a) * (0.5 if at.size() == 1 else 0.3)
	var leg := g.edge + 0.2
	for fp: float in at:
		_pier(g, sup, fp, leg + 0.2, 1.0, 0.15, Streets.CONCRETE.darkened(0.1))
		var tops: Array[Vector3] = []
		for side: float in [-1.0, 1.0]:
			# each leg leans in a little towards the top
			var foot := g.at(fp, side * leg, -Streets.DECK_DEPTH - 0.8)
			var top := g.at(fp, side * (leg - 0.25), h)
			beam(sup, foot, top, 0.3, WHITE, FLOOD, true)
			beam(sup, top, top + Vector3.UP * 0.14, 0.12, BEACON, 2.7, true)
			tops.append(top)
			# the cables, fanning out both ways
			var n := clampi(int(reach * Streets.SAMPLE / 1.4), 3, 8)
			for dirn: float in [-1.0, 1.0]:
				for j in n:
					var anchor := top + Vector3.DOWN * (0.25 + j * 0.28)
					var fd := fp + dirn * reach * (j + 1) / (n + 0.4)
					beam(sup, anchor, g.at(fd, side * (g.edge - 0.05), g.walk()), 0.04, CABLE)
		# crossbeams under the deck and high over the traffic
		beam(sup, g.at(fp, -leg, -Streets.DECK_DEPTH - 0.15), g.at(fp, leg, -Streets.DECK_DEPTH - 0.15), 0.28, WHITE)
		if h > 3.0:
			beam(sup, tops[0].lerp(g.at(fp, -leg, 0.0), 0.12), tops[1].lerp(g.at(fp, leg, 0.0), 0.12), 0.22, WHITE, FLOOD)


## Two tall towers with a portal frame, the main cables sweeping from an
## anchorage on each bank over the towers and dipping to the deck between,
## and hangers down from them every metre and a half.
static func _suspension(g: Geo, sup: Streets.MeshBuf, sp: Vector2, a: float, b: float, water: float, col: Color) -> void:
	var h := clampf(water * 0.2, 4.5, 13.0)
	var leg := g.edge + 0.25
	var towers: Array[float] = [lerpf(a, b, 0.18), lerpf(a, b, 0.82)]
	for fp in towers:
		_pier(g, sup, fp, leg + 0.25, 1.1, 0.15, Streets.CONCRETE.darkened(0.1))
		var tops: Array[Vector3] = []
		for side: float in [-1.0, 1.0]:
			var top := g.at(fp, side * leg, h)
			beam(sup, g.at(fp, side * leg, -Streets.DECK_DEPTH - 0.8), top, 0.36, col, FLOOD, true)
			beam(sup, top, top + Vector3.UP * 0.14, 0.14, BEACON, 2.7, true)
			tops.append(top)
		# the portal: braces across under the deck, over the traffic and at the top
		for y: float in [-Streets.DECK_DEPTH - 0.2, h * 0.55, h - 0.25]:
			if y > 0.0 and y < 2.2:
				continue
			beam(sup, g.at(fp, -leg, y), g.at(fp, leg, y), 0.26, col, FLOOD)
	# the main cable over each side: anchorage, tower, the dip, tower, anchorage
	var anchors: Array[float] = [sp.x + 3.0, sp.y - 3.0]
	for side: float in [-1.0, 1.0]:
		var pts: Array[Vector3] = []
		var fs: Array[float] = []
		for q in 5:
			fs.append(lerpf(anchors[0], towers[0], q / 5.0))
		for q in 16:
			fs.append(lerpf(towers[0], towers[1], q / 16.0))
		for q in 6:
			fs.append(lerpf(towers[1], anchors[1], q / 5.0))
		for f in fs:
			pts.append(g.at(f, side * leg, _cable_h(f, anchors, towers, h)))
		for q in pts.size() - 1:
			beam(sup, pts[q], pts[q + 1], 0.1, col.darkened(0.12), FLOOD)
		# hangers from the cable down to the deck's edge
		var f := anchors[0] + 2.0
		while f < anchors[1] - 1.0:
			var ch := _cable_h(f, anchors, towers, h)
			if ch > g.walk() + 0.3 and absf(f - towers[0]) > 0.8 and absf(f - towers[1]) > 0.8:
				beam(sup, g.at(f, side * leg, g.walk()), g.at(f, side * leg, ch), 0.035, CABLE)
			f += 3.0
	# the anchorages: heavy blocks the cables run down into
	for fa in anchors:
		for side: float in [-1.0, 1.0]:
			beam(sup, g.at(fa, side * leg, -0.6), g.at(fa, side * leg, 0.5), 0.7, Streets.CONCRETE.darkened(0.05), 0.0, true)


## How high the main cable runs over the deck at f.
static func _cable_h(f: float, anchors: Array[float], towers: Array[float], h: float) -> float:
	if f <= towers[0]:
		var t := (f - anchors[0]) / maxf(towers[0] - anchors[0], 0.01)
		return lerpf(0.4, h - 0.1, t * t * 0.5 + t * 0.5)
	if f >= towers[1]:
		var t := (anchors[1] - f) / maxf(anchors[1] - towers[1], 0.01)
		return lerpf(0.4, h - 0.1, t * t * 0.5 + t * 0.5)
	var u := (f - towers[0]) / (towers[1] - towers[0]) * 2.0 - 1.0
	return lerpf(0.55, h - 0.1, u * u)
