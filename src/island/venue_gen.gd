class_name VenueGen
extends RefCounted
## The entertainment district's buildings, growing with its level: bars and
## pubs under flats, then nightclubs and arcades, theatres with columned
## porticos and bowling alleys, cinemas and concert halls under a copper
## vault, a casino glittering gold and, across joined plots at the Mega
## level, an arena under a great oval roof ringed with floodlights. Every one
## is lit up at night. Built in world space, as the raw arrays the town
## merges into one mesh per patch (as HouseGen does).

const FH := HouseGen.FH
const NAMES := {"bar": "Bar", "pub": "Pub", "music": "Music bar", "club": "Nightclub", "arcade": "Arcade", "theatre": "Theatre",
	"bowling": "Bowling alley", "cinema": "Multiplex", "concert": "Concert hall", "casino": "Casino", "arena": "Arena"}
## staff on a busy night, before its floors
const JOBS := {"bar": 6, "pub": 8, "music": 10, "club": 20, "arcade": 15, "bowling": 25, "theatre": 40, "cinema": 45,
	"concert": 60, "casino": 120, "arena": 150}
## neon, lit at night (never red-dominant: that blinks, for aircraft)
const NEON := [Color("ff4fd8"), Color("3fd0ff"), Color("ffcf3f"), Color("9b6bff"), Color("4fffa8"), Color("ff8a3d")]
const GOLD := Color("e6b24a")
const COPPER := Color("6fae9a")
const IRON := HouseGen.IRON
const BAR_FRONTS := ["bar", "pub", "music"]


## The jobs a venue (or the bar under a house) brings.
static func jobs(l: Town.Lot) -> int:
	return int(JOBS.get(l.trade, 8)) + l.floors * 4


## A bar, pub or music bar on a house's ground floor: dark woodwork or a
## painted front, warm windows, a hanging sign and a neon strip, lit at night.
## Returns its trade.
static func barfront(mk: MeshKit, rng: RandomNumberGenerator, hw: float, front: float, wall: Color) -> String:
	var trade: String = BAR_FRONTS[rng.randi() % BAR_FRONTS.size()]
	var wood: Color = [Color("2f3a30"), Color("3a2a26"), Color("1f2a38"), Color("5a2f3a")][rng.randi() % 4]
	mk.box_faces(Vector3(0, FH * 0.5, front + 0.02), Vector3(hw - 0.06, FH * 0.96, 0.04), wood, MeshKit.FRONT | MeshKit.TOP)
	# big warm windows either side of the door
	var run := (hw - 0.5) * 0.5
	for sx: float in [-1.0, 1.0]:
		if run > 0.2:
			mk.box_faces(Vector3(sx * (0.25 + run * 0.5), FH * 0.48, front + 0.045), Vector3(run - 0.08, FH * 0.56, 0.01), Color(0.95, 0.72, 0.42), MeshKit.FRONT, 2.0)
	mk.box_faces(Vector3(0, FH * 0.4, front + 0.045), Vector3(0.3, FH * 0.72, 0.01), wood.darkened(0.3), MeshKit.FRONT)
	# its name over the windows, and a strip of neon or a hanging sign
	var neon: Color = NEON[rng.randi() % NEON.size()]
	if trade == "pub":
		mk.box_faces(Vector3(0, FH * 0.9, front + 0.05), Vector3(hw * 0.7, 0.1, 0.02), GOLD, MeshKit.FRONT, 1.2)
		mk.box(Vector3(hw * 0.5 - 0.12, FH * 1.2, front + 0.2), Vector3(0.04, 0.3, 0.26), wood.lightened(0.2))
	else:
		mk.box_faces(Vector3(0, FH * 0.9, front + 0.05), Vector3(hw * 0.75, 0.07, 0.02), neon, MeshKit.FRONT, 2.7)
	return trade


## One venue over one plot or several joined plots (the first is the host).
static func build(ls: Array, land: Land, street_y: float, seed_value: int) -> Array:
	var h: Town.Lot = ls[0]
	var mk := MeshKit.new(seed_value)
	mk.quiet_sprites = true
	var rng := mk.rng
	var right := Vector2(cos(h.yaw), -sin(h.yaw))
	var fwd := Vector2(sin(h.yaw), cos(h.yaw))
	var stage := 0
	for l: Town.Lot in ls:
		stage = maxi(stage, l.stage)
	var kind := _kind(stage, ls.size(), rng)
	var floors: int = {"club": 2, "arcade": 2, "theatre": 3, "bowling": 2, "cinema": 3, "concert": 4, "casino": 4 + rng.randi() % 2, "arena": 3}[kind]
	var pts := HouseGen.block_outline(ls)
	var box := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		box = box.expand(p)
	h.foot = box
	var fronts := pts.slice(0, ls.size() + 1)
	var lo := INF
	var hi := -INF
	for p in pts:
		var w := h.origin + right * p.x + fwd * p.y
		var g := land.height_at(w.x, w.y)
		lo = minf(lo, g)
		hi = maxf(hi, g)
	var y0 := maxf(street_y, (lo + hi) * 0.5 + 0.04)
	var hgt := floors * FH + 0.3
	var neon: Color = NEON[rng.randi() % NEON.size()]
	var wall: Color
	match kind:
		"club": wall = [Color("2b2540"), Color("1f2a38"), Color("33243a")][rng.randi() % 3]
		"arcade": wall = [Color("ffd166"), Color("7ad3c9"), Color("ff9fb2")][rng.randi() % 3]
		"theatre", "concert": wall = [Color("efe4d2"), Color("e8d8bc"), Color("f3ece0")][rng.randi() % 3]
		"bowling": wall = [Color("f2b8a8"), Color("b9d4c8"), Color("fff1c4")][rng.randi() % 3]
		"cinema": wall = Color("3d3a52")
		"casino": wall = [Color("f3e6c4"), Color("2b2540"), Color("7a1f3d")][rng.randi() % 3]
		_: wall = Color(0.92, 0.92, 0.9)
	for l: Town.Lot in ls:
		l.use = "fun"
		l.shop = false
		l.trade = kind
		l.floors = floors
	mk.push_at(Vector3(h.origin.x, y0, h.origin.y), h.yaw)
	if y0 - lo > 0.04:
		mk.shadow = false
		HouseGen._walls(mk, pts, lo - y0 - 0.12, 0.02, HouseGen.STONE.darkened(0.06))
		mk.shadow = true
	var body := hgt if kind != "arena" else FH * 1.2
	HouseGen._prism(mk, pts, body, wall, 0.0, 0, wall.lightened(0.3), fronts.size() - 1)
	var cw := Geometry2D.is_polygon_clockwise(pts)
	if kind == "club" or kind == "casino" or kind == "arcade":
		# neon bands right round the top
		var band: Color = GOLD if kind == "casino" else neon
		for k in pts.size():
			var a := pts[k]
			var b := pts[(k + 1) % pts.size()]
			if a.distance_to(b) < 0.3:
				continue
			var t := (b - a).normalized()
			var out := Vector2(-t.y, t.x) if cw else Vector2(t.y, -t.x)
			var a2 := a + out * 0.015
			var b2 := b + out * 0.015
			var o3 := Vector3(out.x, 0, out.y)
			for y: float in ([body - 0.3, body * 0.55] if kind == "club" else [body - 0.3]):
				mk.quad(Vector3(a2.x, y, a2.y), Vector3(b2.x, y, b2.y), Vector3(b2.x, y + 0.07, b2.y), Vector3(a2.x, y + 0.07, a2.y), o3, band, 2.7)
	var mid := fronts.size() / 2 - 1
	for k in fronts.size() - 1:
		var a := fronts[k]
		var b := fronts[k + 1]
		var run := a.distance_to(b)
		if run < 0.4:
			continue
		var t := (b - a) / run
		var out := Vector2(-t.y, t.x) if cw else Vector2(t.y, -t.x)
		var m := (a + b) * 0.5
		mk.push_at(Vector3(m.x, 0, m.y), atan2(out.x, out.y))
		_front(mk, rng, kind, run, body, wall, neon, k == mid or fronts.size() == 2)
		if posmod(seed_value + k, 2) == 0:
			CivicGen._lamp(mk, Vector3(run * 0.5, street_y - y0, 0.5))
		mk.pop()
	var c := box.get_center()
	match kind:
		"concert":
			HouseGen._flat_roof(mk, pts, hgt, wall)
			_vault(mk, box, hgt, COPPER)
		"arena":
			HouseGen._flat_roof(mk, pts, body, wall)
			_arena(mk, box, body, neon)
		"casino":
			HouseGen._flat_roof(mk, pts, hgt, wall)
			# a lit gold dome, and a beacon
			mk.cylinder(Vector3(c.x, hgt, c.y), 0.7, 0.35, 10, GOLD, true, GOLD.lightened(0.2), 0.3, 1.0)
			mk.box(Vector3(c.x, hgt + 0.6, c.y), Vector3(0.12, 0.5, 0.12), GOLD, null, false, 2.7)
		"bowling":
			HouseGen._flat_roof(mk, pts, hgt, wall)
			# a giant pin on the roof
			mk.cylinder(Vector3(c.x, hgt, c.y), 0.16, 0.7, 6, Color(0.97, 0.96, 0.93), false, null, 0.1)
			mk.box(Vector3(c.x, hgt + 0.5, c.y), Vector3(0.24, 0.06, 0.24), Color("d9534f"))
			mk.blob(Vector3(c.x, hgt + 0.8, c.y), Vector3(0.13, 0.15, 0.13), Color(0.97, 0.96, 0.93))
		_:
			HouseGen._flat_roof(mk, pts, hgt, wall)
			mk.box(Vector3(c.x, hgt + 0.2, c.y), Vector3(0.8, 0.4, 0.55), Color(0.62, 0.64, 0.66))
	mk.pop()
	return [mk.verts, mk.norms, mk.cols, mk.uvs, mk.dverts, mk.dnorms, mk.dcols, mk.duvs, mk.sverts, mk.snorms,
		mk.bverts, mk.bcols, mk.buvs, mk.bradius, mk.qverts, mk.qcols, mk.quvs, mk.qradius]


## What a venue of this stage and size is: small clubs and arcades first,
## theatres and bowling, then cinemas and concert halls, casinos, and an
## arena across joined plots at the Mega level.
static func _kind(stage: int, plots: int, rng: RandomNumberGenerator) -> String:
	if stage >= 7 and plots >= 2:
		return "arena"
	if stage >= 6:
		return ["casino", "concert", "cinema"][rng.randi() % 3] if stage < 7 else ["casino", "concert"][rng.randi() % 2]
	if stage >= 5:
		return ["cinema", "concert", "theatre"][rng.randi() % 3]
	if stage >= 4:
		return ["theatre", "bowling", "club"][rng.randi() % 3]
	return ["club", "arcade", "club", "bowling"][rng.randi() % 4]


## One plot's front of a venue (local: x along it, z out to the street).
static func _front(mk: MeshKit, rng: RandomNumberGenerator, kind: String, run: float, hgt: float, wall: Color, neon: Color, main: bool) -> void:
	# lit glass doors along the ground floor
	mk.box_faces(Vector3(0, FH * 0.45, 0.01), Vector3(run - 0.16, FH * 0.8, 0.02), Color(0.5, 0.48, 0.55) if kind == "club" else Color(0.95, 0.78, 0.5), MeshKit.FRONT, 2.0)
	match kind:
		"theatre", "concert":
			# a portico: columns up to a lintel and a pediment, the name lit over the doors
			var n := clampi(int(run / 0.55), 2, 8)
			var span := run - 0.4
			mk.shadow = false
			for i in n:
				var x := -span * 0.5 + span * i / float(n - 1)
				mk.cylinder(Vector3(x, 0.0, 0.35), 0.07, hgt - 0.5, 6, wall.lightened(0.15), false)
			mk.shadow = true
			mk.box(Vector3(0, hgt - 0.42, 0.24), Vector3(span + 0.2, 0.16, 0.46), wall.lightened(0.1))
			if main:
				mk.quad(Vector3(-span * 0.5 - 0.1, hgt - 0.34, 0.47), Vector3(span * 0.5 + 0.1, hgt - 0.34, 0.47), Vector3(0, hgt + 0.1, 0.47), Vector3(0, hgt + 0.1, 0.47), Vector3.BACK, wall.lightened(0.1))
				mk.box_faces(Vector3(0, FH * 1.05, 0.5), Vector3(minf(run * 0.6, 2.2), 0.22, 0.08), neon if kind == "theatre" else Color(1.0, 0.9, 0.7), MeshKit.FRONT | MeshKit.TOP, 2.7)
		"cinema":
			for px: float in [-run * 0.3, run * 0.3]:
				mk.box_faces(Vector3(px, FH * 1.6, 0.012), Vector3(0.45, 0.6, 0.02), NEON[rng.randi() % NEON.size()], MeshKit.FRONT, 2.7)
			mk.box_faces(Vector3(0, FH * 1.15, 0.3), Vector3(minf(run * 0.7, 2.6), 0.3, 0.12), neon, MeshKit.FRONT | MeshKit.TOP | MeshKit.LEFT | MeshKit.RIGHT, 2.7)
			if main:
				mk.box(Vector3(run * 0.5 - 0.15, hgt * 0.62, 0.3), Vector3(0.1, hgt * 0.7, 0.45), neon, null, false, 2.7)
		"casino":
			# a gold canopy, and the name in lights up a tall blade
			mk.box_faces(Vector3(0, FH * 0.95, 0.3), Vector3(run - 0.1, 0.06, 0.6), GOLD, MeshKit.TOP | MeshKit.FRONT, 1.0)
			if main:
				mk.box(Vector3(0, hgt * 0.6, 0.25), Vector3(0.5, hgt * 0.75, 0.1), GOLD, null, false, 2.7)
			for fl in range(1, maxi(2, int(hgt / FH))):
				var y := fl * FH + FH * 0.3
				mk.quad(Vector3(-run * 0.5 + 0.1, y, 0.006), Vector3(run * 0.5 - 0.1, y, 0.006), Vector3(run * 0.5 - 0.1, y + FH * 0.4, 0.006), Vector3(-run * 0.5 + 0.1, y + FH * 0.4, 0.006), Vector3.BACK, Color(0.95, 0.78, 0.5), 1.6)
		"arena":
			mk.box_faces(Vector3(0, FH * 1.12, 0.3), Vector3(run - 0.05, 0.05, 0.5), Color(0.9, 0.9, 0.88), MeshKit.TOP | MeshKit.FRONT)
		_:
			# a sign over the doors in lights, posters each side
			if main:
				mk.box_faces(Vector3(0, hgt - 0.5, 0.05), Vector3(minf(run * 0.7, 2.2), 0.4, 0.08), neon, MeshKit.FRONT | MeshKit.TOP, 2.7)
			for px: float in [-run * 0.32, run * 0.32]:
				if run > 1.4:
					mk.box_faces(Vector3(px, FH * 1.45, 0.012), Vector3(0.36, 0.48, 0.02), NEON[rng.randi() % NEON.size()], MeshKit.FRONT, 2.0)


## A copper barrel vault over a concert hall, running back from the street.
static func _vault(mk: MeshKit, box: Rect2, hgt: float, col: Color) -> void:
	const N := 8
	var x0 := box.position.x + 0.1
	var x1 := box.end.x - 0.1
	var z0 := box.position.y + 0.1
	var z1 := box.end.y - 0.1
	var rise := minf((x1 - x0) * 0.3, 1.2)
	for i in N:
		var t0 := float(i) / N
		var t1 := float(i + 1) / N
		var xa := lerpf(x0, x1, t0)
		var xb := lerpf(x0, x1, t1)
		var ya := hgt + sin(t0 * PI) * rise
		var yb := hgt + sin(t1 * PI) * rise
		var n := Vector3(ya - yb, xb - xa, 0).normalized()
		mk.quad(Vector3(xa, ya, z1), Vector3(xb, yb, z1), Vector3(xb, yb, z0), Vector3(xa, ya, z0), n, col)
		# the gable ends
		for z: float in [z0, z1]:
			mk.quad(Vector3(xa, hgt, z), Vector3(xb, hgt, z), Vector3(xb, yb, z), Vector3(xa, ya, z), Vector3(0, 0, signf(z - (z0 + z1) * 0.5)), Color(0.82, 0.86, 0.88), 0.6)


## An arena: an oval bowl of white ribs on its podium under a pale roof, a
## ring of floodlights round the rim.
static func _arena(mk: MeshKit, box: Rect2, base: float, neon: Color) -> void:
	var c := box.get_center()
	var r := Vector2(box.size.x * 0.47, box.size.y * 0.47)
	var rr := minf(r.x, r.y)
	mk.push_at(Vector3(c.x, base, c.y), 0.0, Vector3(r.x / rr, 1.0, r.y / rr))
	mk.cylinder(Vector3.ZERO, rr, 1.1, 20, Color(0.95, 0.95, 0.93), false, null, rr * 1.06)
	mk.cylinder(Vector3(0, 1.1, 0), rr * 1.06, 0.45, 20, Color(0.86, 0.88, 0.9), true, Color(0.8, 0.84, 0.86), rr * 0.55)
	# a band of light round the bowl, in the home team's colour
	mk.cylinder(Vector3(0, 0.75, 0), rr * 1.04, 0.1, 20, neon, false, null, rr * 1.045, 2.7)
	mk.pop()
	for k in 6:
		var ang := k * TAU / 6.0 + 0.3
		var p := c + Vector2(cos(ang) * r.x, sin(ang) * r.y) * 1.02
		mk.cylinder(Vector3(p.x, base, p.y), 0.03, 1.9, 4, IRON, false)
		mk.box(Vector3(p.x, base + 1.95, p.y), Vector3(0.18, 0.1, 0.06), Color(1.0, 0.97, 0.88), null, false, 2.7)
