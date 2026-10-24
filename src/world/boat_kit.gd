class_name BoatKit
extends RefCounted
## Shapes shared by the boats, ships and the airliner: a hull lofted through
## cross-sections (a sheer that rises to a raked bow, round bilges and a keel),
## sails cut with a belly, and thin lines for rigging and rails.


## A hull through `stations`, Vector4(z, half beam, deck height, keel height)
## from the stern to the bow (bow towards +Z): `top` above the waterline at
## `water`, `bottom` below it, a `deck` over it and a flat transom at the stern.
static func hull(mk: MeshKit, stations: Array, top: Color, bottom: Color, water: float, deck: Color) -> void:
	var rings: Array = []
	for s: Vector4 in stations:
		var w := s.y
		var wl := minf(water, s.z - 0.02)
		var bilge := lerpf(wl, s.w, 0.65)
		# deck edge, waterline, bilge, keel: one side's points, right (+X) first
		rings.append([Vector3(w, s.z, s.x), Vector3(w * 0.97, wl, s.x), Vector3(w * 0.72, bilge, s.x), Vector3(0, s.w, s.x)])
	var cols := [top, bottom, bottom]
	for i in rings.size() - 1:
		var a: Array = rings[i]
		var b: Array = rings[i + 1]
		for sx: float in [1.0, -1.0]:
			var m := Vector3(sx, 1, 1)
			for k in 3:
				var face := Vector3(sx, -0.4 * k, 0)
				mk.quad(a[k] * m, a[k + 1] * m, b[k + 1] * m, b[k] * m, face, cols[k])
		mk.quad(a[0], a[0] * Vector3(-1, 1, 1), b[0] * Vector3(-1, 1, 1), b[0], Vector3.UP, deck)
	# the transom
	var st: Array = rings[0]
	var mid := Vector3(0, (st[0].y + st[3].y) * 0.5, st[0].z)
	var loop := [st[0], st[1], st[2], st[3], st[2] * Vector3(-1, 1, 1), st[1] * Vector3(-1, 1, 1), st[0] * Vector3(-1, 1, 1)]
	for k in loop.size() - 1:
		mk.tri(mid, loop[k], loop[k + 1], top if loop[k].y >= st[1].y - 0.001 and loop[k + 1].y >= st[1].y - 0.001 else bottom, 0.0, 0.0, Vector3.BACK)
	mk.tri(mid, loop[loop.size() - 1], loop[0], top, 0.0, 0.0, Vector3.BACK)


## A sail from its tack (foot of the luff) up to its head and out to its clew,
## filled out by `belly` in the middle, seen from both sides.
static func sail(mk: MeshKit, tack: Vector3, head: Vector3, clew: Vector3, belly: Vector3, col: Color, foot_col := Color(0, 0, 0, 0)) -> void:
	var rows := 2
	var was := mk.shadow
	for k in rows:
		var t0 := float(k) / rows
		var t1 := float(k + 1) / rows
		var l0 := tack.lerp(head, t0)
		var l1 := tack.lerp(head, t1)
		var r0 := clew.lerp(head, t0)
		var r1 := clew.lerp(head, t1)
		var m0 := (l0 + r0) * 0.5 + belly * (1.0 - t0)
		var m1 := (l1 + r1) * 0.5 + belly * (1.0 - t1)
		var c := foot_col if k == 0 and foot_col.a > 0.0 else col
		var n := (r0 - l0).cross(l1 - l0).normalized()
		for f: float in [1.0, -1.0]:
			# one side is enough in the shadow map
			mk.shadow = was and f > 0.0
			mk.quad(l0, m0, m1, l1, n * f, c)
			mk.quad(m0, r0, r1, m1, n * f, c)
	mk.shadow = was


## A thin line (a stay, a shroud, a rail) `w` thick from `a` to `b`: a
## ribbon turned half way between flat and upright, seen from both faces, so
## it reads from above and from the side; too thin to cast a shadow worth drawing.
static func line(mk: MeshKit, a: Vector3, b: Vector3, w: float, col: Color, e := 0.0) -> void:
	var d := (b - a).normalized()
	var n1 := d.cross(Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT).normalized()
	var n2 := d.cross(n1).normalized()
	var n := (n1 + n2).normalized() * w * 0.5
	var f := d.cross(n).normalized()
	var was := mk.shadow
	mk.shadow = false
	mk.quad(a - n, b - n, b + n, a + n, f, col, e)
	mk.quad(a - n, b - n, b + n, a + n, -f, col, e)
	mk.shadow = was


## A rail along `pts` at `h` above them, with a post at every point.
static func rail(mk: MeshKit, pts: Array, h: float, col: Color, w := 0.02) -> void:
	for k in pts.size():
		var p: Vector3 = pts[k]
		line(mk, p, p + Vector3(0, h, 0), w, col)
		if k > 0:
			var q: Vector3 = pts[k - 1]
			line(mk, q + Vector3(0, h, 0), p + Vector3(0, h, 0), w, col)


## A round tube lying along `axis` (a fuselage, an engine, a drum) from `a`,
## `length` long, radius r0 there narrowing to r1 at its far end.
static func tube(mk: MeshKit, a: Vector3, axis: Vector3, length: float, r0: float, r1: float, sides: int, col: Color, cap := true, cap_col: Variant = null, e := 0.0) -> void:
	var up := axis.normalized()
	var x := up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(up)
	mk.push(Transform3D(Basis(x, up, z), a))
	mk.cylinder(Vector3.ZERO, r0, length, sides, col, cap, cap_col, r1, e)
	mk.pop()
