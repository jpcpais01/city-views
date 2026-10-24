class_name BusStops
extends RefCounted
## Bus stops along the main streets and avenues: a glass shelter on the
## pavement with a bench inside, a lit advert at one end that glows at night,
## and the stop's sign on a pole at the kerb. The buses pull in at them (see
## Traffic). Worked out from the street alone, so every player has the same.

## how far apart the stops on one side are, in samples, and how far in the first is
const GAP := 72
const FIRST := 22
## half the shelter's length along the street, in samples
const HALF := 0.9
const ROOF := Color(0.3, 0.36, 0.42)
const GLASS := Color(0.62, 0.74, 0.8)
const AD := Color(0.97, 0.95, 0.88)
const SIGN := Color(0.22, 0.42, 0.78)


## Where street `s` has its stops: (sample index, side), staggered so the two
## sides' stops face each other a little way apart; never at a junction, on a
## bridge or where a corner takes the pavement.
static func place(s: Streets.Street, skip: PackedVector2Array, cuts: Dictionary) -> PackedVector2Array:
	var out := PackedVector2Array()
	if s.kind != "main" and s.kind != "avenue":
		return out
	var n := s.pts.size()
	for side: float in [1.0, -1.0]:
		var f := float(FIRST + (0 if side > 0.0 else GAP / 3))
		while f < n - FIRST:
			if _clear(f, skip) and _clear(f, cuts[side]) and _clear(f, s.spans) and _off_quay(s, f, side):
				out.append(Vector2(f, side))
				f += GAP
			else:
				f += 4.0
	return out


static func _clear(f: float, list: PackedVector2Array) -> bool:
	for c in list:
		if f > c.x - HALF - 3.0 and f < c.y + HALF + 3.0:
			return false
	return true


static func _off_quay(s: Streets.Street, f: float, side: float) -> bool:
	if s.quay.is_empty():
		return true
	var q := s.quay[clampi(int(f), 0, s.quay.size() - 1)]
	return not (q & (1 if side < 0.0 else 2))


## Puts up the shelters and signs of `stops` into `buf`.
static func build(st: Streets, s: Streets.Street, buf: Streets.MeshBuf, stops: PackedVector2Array) -> void:
	if stops.is_empty():
		return
	var g := BridgeGen.Geo.new(st, s)
	var edge := s.w() + Streets.PAVE
	var walk := Streets.CURB
	for stop in stops:
		var f := stop.x
		var side := stop.y
		var back := side * (edge - 0.05)
		var front := side * (edge - 0.3)
		var f0 := f - HALF
		var f1 := f + HALF
		var out := g.at(f, side, 0.0) - g.at(f, 0.0, 0.0)
		# the roof, a thin slab reaching a little out over the front
		var lip := side * (edge - 0.36)
		var r0 := walk + 0.55
		var r1 := walk + 0.6
		buf.quad(g.at(f0, back, r1), g.at(f1, back, r1), g.at(f1, lip, r1), g.at(f0, lip, r1), ROOF, 0.0, Vector3.UP)
		buf.quad(g.at(f0, lip, r0), g.at(f1, lip, r0), g.at(f1, lip, r1), g.at(f0, lip, r1), ROOF.darkened(0.15), 0.0, -out)
		buf.quad(g.at(f0, back, r0), g.at(f1, back, r0), g.at(f1, back, r1), g.at(f0, back, r1), ROOF.darkened(0.15), 0.0, out)
		# the glass back, seen from the street and from behind
		buf.quad(g.at(f0, back, walk + 0.04), g.at(f1, back, walk + 0.04), g.at(f1, back, r0), g.at(f0, back, r0), GLASS, 0.0, -out)
		buf.quad(g.at(f0, back, walk + 0.04), g.at(f1, back, walk + 0.04), g.at(f1, back, r0), g.at(f0, back, r0), GLASS.darkened(0.1), 0.0, out)
		# an advert at the end facing the oncoming traffic, lit at night
		var fe := f0 if side > 0.0 else f1
		var along := g.at(fe + side, 0.0, 0.0) - g.at(fe, 0.0, 0.0)
		buf.quad(g.at(fe, back, walk + 0.08), g.at(fe, front, walk + 0.08), g.at(fe, front, r0 - 0.04), g.at(fe, back, r0 - 0.04), AD, 2.0, -along)
		buf.quad(g.at(fe, back, walk + 0.08), g.at(fe, front, walk + 0.08), g.at(fe, front, r0 - 0.04), g.at(fe, back, r0 - 0.04), ROOF, 0.0, along)
		# the posts at the front corners, and a bench along the back
		for fp: float in [f0 + 0.1, f1 - 0.1]:
			BridgeGen.beam(buf, g.at(fp, front, walk), g.at(fp, front, r0), 0.04, ROOF)
		BridgeGen.beam(buf, g.at(f0 + 0.3, back - side * 0.1, walk + 0.14), g.at(f1 - 0.3, back - side * 0.1, walk + 0.14), 0.08, Palette.ASPHALT.lightened(0.25))
		# the stop's sign on a pole at the kerb, a little ahead of the shelter
		var fs := f + side * (HALF + 0.6)
		var kerb := side * (s.w() + 0.07)
		var top := g.at(fs, kerb, walk + 0.72)
		BridgeGen.beam(buf, g.at(fs, kerb, walk), top, 0.03, ROOF)
		BridgeGen.beam(buf, top, top + Vector3.UP * 0.14, 0.13, SIGN, 0.0, true)
