class_name ParkGen
extends RefCounted
## Parks, one generator per sub-type. Ponds, plazas and sports fields join up
## with their own kind next door into one lake, one square or one full pitch.

const H := CityGen.H
const DIRS := CityGen.DIRS
const GRASS := Color(0.47, 0.76, 0.4)
const WATER := Color(0.36, 0.66, 0.8)
const PAINT := Color(0.97, 0.97, 0.94)


static func build(mk: MeshKit, x: int, z: int) -> void:
	match Game.sub(x, z):
		Game.PARK_SUB.PLAYGROUND: _playground(mk, x, z)
		Game.PARK_SUB.PLAZA: _plaza(mk, x, z)
		Game.PARK_SUB.PITCH: _pitch(mk, x, z)
		Game.PARK_SUB.POND: _pond(mk, x, z)
		_: CityGen._park(mk, x, z)


static func _road_at(x: int, z: int, i: int) -> bool:
	var d := DIRS[i]
	return Game.knd(x + d.x, z + d.y) == Game.K.ROAD


static func bench(mk: MeshKit, p: Vector3, yaw: float) -> void:
	mk.push_at(p, yaw)
	mk.box_faces(Vector3(0, 0.12, 0), Vector3(0.36, 0.03, 0.1), Color(0.7, 0.5, 0.33), MeshKit.TOP | MeshKit.FRONT)
	mk.box_faces(Vector3(0, 0.2, -0.05), Vector3(0.36, 0.09, 0.02), Color(0.7, 0.5, 0.33), MeshKit.TOP | MeshKit.FRONT | MeshKit.BACK)
	for s in [-1, 1]:
		mk.box_faces(Vector3(s * 0.15, 0.06, 0), Vector3(0.03, 0.11, 0.09), Color(0.3, 0.3, 0.32), MeshKit.LEFT | MeshKit.RIGHT)
	mk.pop()


# ------------------------------------------------------------------ playground

static func _playground(mk: MeshKit, x: int, z: int) -> void:
	mk.rbox(Vector3(0, 0.04, 0), Vector3(2.0, 0.08, 2.0), 0.03, GRASS)
	var soft: Color = CityGen.pick([Color("d9735a"), Color("4fa3a0"), Color("6f8fd6")], x, z, 150)
	mk.box_faces(Vector3(0, 0.085, -0.05), Vector3(1.6, 0.01, 1.5), soft, MeshKit.TOP)
	var flip := -1.0 if Game.hashf(x, z, 151) > 0.5 else 1.0
	# slide: ladder up to a platform, then the chute down
	var sx := -0.45 * flip
	for px in [-0.12, 0.12]:
		for pz in [-0.12, 0.12]:
			mk.pole(Vector3(sx + px, 0.09, -0.45 + pz), 0.018, 0.46, 4, Color(0.9, 0.9, 0.92))
	mk.box(Vector3(sx, 0.55, -0.45), Vector3(0.3, 0.03, 0.3), Color("f2b33d"))
	mk.cone(Vector3(sx, 0.56, -0.45), 0.24, 0.22, 4, Color("e85d5d"))
	var a := Vector3(sx + 0.15 * flip, 0.55, -0.45)
	var b := Vector3(sx + 0.62 * flip, 0.12, -0.45)
	var n := Vector3(0.43 * flip, 0.47, 0).normalized()
	mk.quad(a + Vector3(0, 0, -0.08), b + Vector3(0, 0, -0.08), b + Vector3(0, 0, 0.08), a + Vector3(0, 0, 0.08), n, Color("4b86d6"))
	mk.quad(a + Vector3(0, -0.02, -0.08), b + Vector3(0, -0.02, -0.08), b + Vector3(0, -0.02, 0.08), a + Vector3(0, -0.02, 0.08), -n, Color("3a6fb0"))
	for k in 3:
		mk.box_faces(Vector3(sx - 0.15 * flip, 0.18 + k * 0.13, -0.45), Vector3(0.02, 0.02, 0.22), Color(0.9, 0.9, 0.92), MeshKit.TOP | MeshKit.LEFT | MeshKit.RIGHT)
	# swings on an A-frame
	var wx := 0.42 * flip
	for s in [-1, 1]:
		mk.push(Transform3D(Basis(Vector3.BACK, s * 0.2), Vector3(wx + s * 0.36, 0.09, 0.32)))
		mk.pole(Vector3.ZERO, 0.02, 0.6, 4, Color("3fae8c"))
		mk.pop()
	mk.box_faces(Vector3(wx, 0.66, 0.32), Vector3(0.66, 0.035, 0.035), Color("3fae8c"), MeshKit.TOP | MeshKit.FRONT | MeshKit.BACK)
	for s in [-1, 1]:
		mk.box(Vector3(wx + s * 0.14, 0.42, 0.32), Vector3(0.008, 0.46, 0.008), Color(0.6, 0.6, 0.62))
		mk.box_faces(Vector3(wx + s * 0.14, 0.19, 0.32), Vector3(0.12, 0.02, 0.08), Color("e85d5d") if s < 0 else Color("f2b33d"), MeshKit.TOP | MeshKit.FRONT)
	# sandpit and a seesaw
	mk.rbox(Vector3(-0.42 * flip, 0.11, 0.4), Vector3(0.5, 0.06, 0.5), 0.02, Color(0.86, 0.72, 0.5))
	mk.box_faces(Vector3(-0.42 * flip, 0.142, 0.4), Vector3(0.42, 0.005, 0.42), Color(0.96, 0.88, 0.66), MeshKit.TOP)
	mk.blob(Vector3(-0.36 * flip, 0.16, 0.36), Vector3(0.06, 0.04, 0.06), Color("ef5b5b"))
	mk.push(Transform3D(Basis(Vector3.BACK, 0.18), Vector3(0.45 * flip, 0.2, -0.4)))
	mk.box_faces(Vector3.ZERO, Vector3(0.6, 0.03, 0.08), Color("8a6fd6"), MeshKit.TOP | MeshKit.FRONT | MeshKit.BACK)
	mk.pop()
	mk.cylinder(Vector3(0.45 * flip, 0.09, -0.4), 0.05, 0.1, 6, Color(0.4, 0.4, 0.44))
	bench(mk, Vector3(0.0, 0.08, 0.86), PI)
	CityGen._round_tree(mk, Vector3(0.78 * flip, 0.08, 0.8), 0.45, CityGen.pick(CityGen.LEAF, x, z, 152))
	CityGen._round_tree(mk, Vector3(-0.8 * flip, 0.08, -0.82), 0.4, CityGen.pick(CityGen.LEAF, x, z, 153))


# ------------------------------------------------------------------ plaza

static func _plaza(mk: MeshKit, x: int, z: int) -> void:
	var stone: Color = CityGen.pick([Color(0.9, 0.86, 0.78), Color(0.86, 0.84, 0.8), Color(0.92, 0.84, 0.74)], x, z, 160)
	mk.rbox(Vector3(0, 0.05, 0), Vector3(2.0, 0.1, 2.0), 0.02, stone, null, false, MeshKit.PAVING)
	var joined := 0
	for i in 4:
		if CityGen.same(x, z, i):
			joined += 1
	# edges that face neither street nor more plaza get planters and benches
	for i in 4:
		if CityGen.same(x, z, i) or _road_at(x, z, i):
			continue
		var d := DIRS[i]
		var out := Vector3(d.x, 0, d.y)
		var along := Vector3(absf(out.z), 0, absf(out.x))
		mk.rbox(out * 0.86 + Vector3(0, 0.2, 0) + along * 0.45, along * 0.7 + out.abs() * 0.18 + Vector3(0, 0.2, 0), 0.04, stone.darkened(0.12))
		mk.rbox(out * 0.86 + Vector3(0, 0.36, 0) + along * 0.45, along * 0.62 + out.abs() * 0.12 + Vector3(0, 0.1, 0), 0.04, Color("5c9e4e"))
		bench(mk, out * 0.82 - along * 0.45 + Vector3(0, 0.1, 0), atan2(-out.x, -out.z))
	# a big square keeps one feature every other tile so it reads as one place
	if joined > 0 and (x + z) % 2 == 1:
		CityGen._lamp(mk, Vector3(0, 0.1, 0))
		return
	match Game.hash2(x, z, 161) % 4:
		0:
			# a big tree in a round planter, with seats round it
			mk.cylinder(Vector3(0, 0.1, 0), 0.38, 0.18, 12, stone.darkened(0.15))
			mk.cylinder(Vector3(0, 0.28, 0), 0.32, 0.01, 12, Color(0.45, 0.34, 0.24))
			CityGen._round_tree(mk, Vector3(0, 0.28, 0), 0.85, CityGen.pick(CityGen.LEAF, x, z, 162))
		1:
			# a statue on a stepped plinth
			mk.rbox(Vector3(0, 0.16, 0), Vector3(0.6, 0.12, 0.6), 0.02, stone.darkened(0.1))
			mk.rbox(Vector3(0, 0.36, 0), Vector3(0.34, 0.3, 0.34), 0.02, stone.lightened(0.05))
			var bronze := Color("6f8f6a")
			mk.pole(Vector3(0, 0.51, 0), 0.06, 0.34, 6, bronze)
			mk.blob(Vector3(0, 0.92, 0), Vector3(0.07, 0.07, 0.07), bronze)
			mk.push(Transform3D(Basis(Vector3.BACK, -0.6), Vector3(0.05, 0.78, 0)))
			mk.box(Vector3(0, 0.12, 0), Vector3(0.04, 0.24, 0.04), bronze)
			mk.pop()
		2:
			# a little basin fountain
			mk.cylinder(Vector3(0, 0.1, 0), 0.45, 0.14, 14, stone.darkened(0.08))
			mk.cylinder(Vector3(0, 0.24, 0), 0.4, 0.01, 14, Color(0.45, 0.78, 0.92), true, null, -1.0, 3.0)
			mk.cylinder(Vector3(0, 0.1, 0), 0.06, 0.32, 6, stone)
			mk.blob(Vector3(0, 0.5, 0), Vector3(0.06, 0.16, 0.06), Color(0.8, 0.93, 1.0), 0.0, 3.0)
		_:
			# an obelisk
			mk.rbox(Vector3(0, 0.15, 0), Vector3(0.36, 0.1, 0.36), 0.02, stone.darkened(0.1))
			mk.cylinder(Vector3(0, 0.2, 0), 0.1, 1.1, 4, stone.lightened(0.05), true, null, 0.05)
	CityGen._lamp(mk, Vector3(0.7, 0.1, 0.7))
	CityGen._lamp(mk, Vector3(-0.7, 0.1, -0.7))


# ------------------------------------------------------------------ sports field

static func _pitch(mk: MeshKit, x: int, z: int) -> void:
	# the long axis follows whichever neighbour is also a pitch
	var along_x := CityGen.same(x, z, 0) or CityGen.same(x, z, 2) or not (CityGen.same(x, z, 1) or CityGen.same(x, z, 3))
	var a := Vector3(1, 0, 0) if along_x else Vector3(0, 0, 1)
	var c := Vector3(a.z, 0, a.x)
	var pos_j := CityGen.same(x, z, 0 if along_x else 1)
	var neg_j := CityGen.same(x, z, 2 if along_x else 3)
	mk.rbox(Vector3(0, 0.04, 0), Vector3(2.0, 0.08, 2.0), 0.03, Color(0.42, 0.72, 0.36), null, false, MeshKit.MOWN_Z if along_x else MeshKit.MOWN_X)
	var y := 0.085
	var hl := 0.9  # half length inside this tile
	var hw := 0.72
	var t := 0.025
	mk.detail = true
	# side lines, and an end line wherever the pitch stops
	for s in [-1.0, 1.0]:
		_line(mk, c * hw * s - a * (H if neg_j else hl), c * hw * s + a * (H if pos_j else hl), y, t)
	for e in [[pos_j, 1.0], [neg_j, -1.0]]:
		var sg: float = e[1]
		if e[0]:
			# halfway line at the joint, with half the centre circle
			_line(mk, a * H * sg - c * hw, a * H * sg + c * hw, y, t)
			_arc(mk, a * H * sg, 0.3, a * -sg, y, t)
		else:
			_line(mk, a * hl * sg - c * hw, a * hl * sg + c * hw, y, t)
			# penalty box
			var bx := 0.3
			_line(mk, a * (hl - bx) * sg - c * 0.36, a * (hl - bx) * sg + c * 0.36, y, t)
			for s in [-1.0, 1.0]:
				_line(mk, a * hl * sg + c * 0.36 * s, a * (hl - bx) * sg + c * 0.36 * s, y, t)
	if not pos_j and not neg_j:
		# a lone five-a-side pitch: centre line and circle of its own
		_line(mk, -c * hw, c * hw, y, t)
		_arc(mk, Vector3.ZERO, 0.24, a, y, t)
		_arc(mk, Vector3.ZERO, 0.24, -a, y, t)
	mk.detail = false
	# goals at the open ends, floodlights at the outside corners
	for e in [[pos_j, 1.0], [neg_j, -1.0]]:
		if e[0]:
			continue
		var sg: float = e[1]
		var gp := a * (hl + 0.03) * sg
		for s in [-1.0, 1.0]:
			mk.pole(gp + c * 0.18 * s + Vector3(0, y, 0), 0.012, 0.22, 4, Color.WHITE)
		mk.box(gp + Vector3(0, y + 0.22, 0), c * 0.38 + a.abs() * 0.024 + Vector3(0, 0.024, 0), Color.WHITE)
		var back := gp + a * 0.08 * sg
		mk.quad(back - c * 0.18 + Vector3(0, y, 0), back + c * 0.18 + Vector3(0, y, 0), gp + c * 0.18 + Vector3(0, y + 0.22, 0), gp - c * 0.18 + Vector3(0, y + 0.22, 0), a * sg, Color(0.85, 0.87, 0.9))
		for s in [-1.0, 1.0]:
			var lp: Vector3 = a * 0.92 * sg + c * 0.9 * s
			mk.pole(lp + Vector3(0, y, 0), 0.02, 1.0, 4, Color(0.6, 0.62, 0.66))
			mk.box_faces(lp + Vector3(0, y + 1.02, 0) - c * 0.04 * s, Vector3(0.16, 0.1, 0.16), Color(1, 0.95, 0.8), MeshKit.TOP | MeshKit.FRONT | MeshKit.BACK | MeshKit.LEFT | MeshKit.RIGHT, 2.0)
	# a little stand of seats along a free side
	for s in [-1.0, 1.0]:
		var i := (1 if along_x else 0) if s > 0.0 else (3 if along_x else 2)
		if CityGen.same(x, z, i) or _road_at(x, z, i):
			continue
		for k in 2:
			mk.box(c * (0.84 + k * 0.07) * s + Vector3(0, 0.1 + k * 0.06, 0), a * 1.2 + c.abs() * 0.07 + Vector3(0, 0.05, 0), Color("4b86d6") if k == 0 else Color("e85d5d"))
		break


static func _line(mk: MeshKit, p0: Vector3, p1: Vector3, y: float, t: float) -> void:
	var dir := (p1 - p0).normalized()
	var side := Vector3(-dir.z, 0, dir.x) * t * 0.5
	var a := p0 + Vector3(0, y, 0)
	var b := p1 + Vector3(0, y, 0)
	mk.quad(a - side, b - side, b + side, a + side, Vector3.UP, PAINT)


## Half circle of paint centred on c, bulging towards `toward`.
static func _arc(mk: MeshKit, c: Vector3, r: float, toward: Vector3, y: float, t: float) -> void:
	var base := atan2(toward.z, toward.x)
	var seg := 8
	for k in seg:
		var a0 := base - PI * 0.5 + PI * k / seg
		var a1 := base - PI * 0.5 + PI * (k + 1) / seg
		_line(mk, c + Vector3(cos(a0), 0, sin(a0)) * r, c + Vector3(cos(a1), 0, sin(a1)) * r, y, t)


# ------------------------------------------------------------------ pond

static func _pond(mk: MeshKit, x: int, z: int) -> void:
	mk.rbox(Vector3(0, 0.04, 0), Vector3(2.0, 0.08, 2.0), 0.03, GRASS)
	# the water reaches the tile edge wherever another pond carries on
	var jx := [CityGen.same(x, z, 0), CityGen.same(x, z, 2)]
	var jz := [CityGen.same(x, z, 1), CityGen.same(x, z, 3)]
	var seed_f := Game.hashf(x, z, 170) * TAU
	var ring := PackedVector3Array()
	var n := 24
	for k in n:
		var ang := TAU * k / n
		var cs := cos(ang)
		var sn := sin(ang)
		var px: bool = jx[0] if cs > 0.0 else jx[1]
		var pz: bool = jz[0] if sn > 0.0 else jz[1]
		var ex := H if px else 0.74
		var ez := H if pz else 0.74
		# rounder where the shore curves, squarer where water meets water
		var e := 10.0 if px or pz else 2.6
		var rx := signf(cs) * pow(absf(cs), 2.0 / e) * ex
		var rz := signf(sn) * pow(absf(sn), 2.0 / e) * ez
		if not px and not pz:
			var wob := 1.0 + 0.06 * sin(ang * 3.0 + seed_f)
			rx *= wob
			rz *= wob
		ring.append(Vector3(rx, 0, rz))
	var shore := Color(0.62, 0.56, 0.42)
	_fan(mk, ring, 1.09, 0.084, shore, 0.0, jx, jz)
	_fan(mk, ring, 1.0, 0.09, WATER, 3.0, jx, jz)
	# reeds, lily pads and a pair of ducks
	for k in 3:
		var ang := seed_f + k * 2.1
		var p := Vector3(cos(ang), 0, sin(ang)) * 0.62
		if absf(p.x) < 0.8 and absf(p.z) < 0.8:
			for r in 3:
				mk.box(p + Vector3(r * 0.04 - 0.04, 0.2, (r % 2) * 0.03), Vector3(0.012, 0.24 + r * 0.04, 0.012), Color("5e8f3e"))
	for k in 4:
		var ang := seed_f + 1.0 + k * 1.4
		mk.box_faces(Vector3(cos(ang), 0, sin(ang)) * (0.3 + k * 0.06) + Vector3(0, 0.094, 0), Vector3(0.1, 0.004, 0.1), Color("6fa84e"), MeshKit.TOP)
	for k in 2:
		var dp := Vector3(cos(seed_f * 2.0 + k), 0, sin(seed_f * 2.0 + k)) * 0.28 + Vector3(k * 0.12, 0, 0)
		mk.blob(dp + Vector3(0, 0.12, 0), Vector3(0.05, 0.035, 0.05), Color.WHITE if k == 0 else Color("8b6a4a"))
		mk.blob(dp + Vector3(0.04, 0.17, 0), Vector3(0.025, 0.025, 0.025), Color("3f7f4f") if k == 1 else Color.WHITE)
	# a jetty out over the water from the nearest street
	for i in 4:
		if _road_at(x, z, i):
			var d := DIRS[i]
			var out := Vector3(d.x, 0, d.y)
			var along := Vector3(absf(out.z), 0, absf(out.x))
			mk.box(out * 0.62 + Vector3(0, 0.13, 0), out.abs() * 0.56 + along * 0.2 + Vector3(0, 0.03, 0), Color(0.66, 0.5, 0.34))
			bench(mk, out * 0.85 + along * 0.45 + Vector3(0, 0.08, 0), atan2(out.x, out.z))
			break


## Flat polygon from the centre out to `ring` (scaled; edges on joined sides stay put).
static func _fan(mk: MeshKit, ring: PackedVector3Array, s: float, y: float, col: Color, e: float, jx: Array, jz: Array) -> void:
	var c := Vector3(0, y, 0)
	var n := ring.size()
	var pts := PackedVector3Array()
	for p in ring:
		var q := p * s
		q.x = clampf(q.x, -H, H)
		q.z = clampf(q.z, -H, H)
		if (q.x > 0.0 and jx[0]) or (q.x < 0.0 and jx[1]):
			q.x = p.x
		if (q.z > 0.0 and jz[0]) or (q.z < 0.0 and jz[1]):
			q.z = p.z
		pts.append(Vector3(q.x, y, q.z))
	var was := mk.shadow
	mk.shadow = false
	for k in n:
		mk.tri(c, pts[k], pts[(k + 1) % n], col, e, 0.0, Vector3.UP)
	mk.shadow = was
