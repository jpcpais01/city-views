class_name HomeGen
extends RefCounted
## Homes, one generator per sub-type. Each reads its street, corner, neighbours,
## district, sea and hill, so no two plots come out the same.

const H := CityGen.H
const FRAME := CityGen.FRAME
const GLASS := CityGen.GLASS
const DOOR := CityGen.DOOR
const SIDEWALK := CityGen.SIDEWALK
const LEAF := CityGen.LEAF
const DOORS := [Color("8b5a44"), Color("4a7bb5"), Color("3d8a6a"), Color("b04a4a"), Color("2f3a48"), Color("e0b44a")]
const TERRACE_COLS := [Color("f3c6a5"), Color("c9dbe9"), Color("f6dca7"), Color("cfe0c3"), Color("e7d3ec"), Color("fbf1df"), Color("f2b8a8"), Color("b9d4c8")]
const APT_COLS := [Color("efe4d2"), Color("f2d4a8"), Color("e9b8a5"), Color("cfe0c3"), Color("dfe6ec"), Color("f6e3c4"), Color("d48a6a")]


static func build(mk: MeshKit, x: int, z: int) -> void:
	var g := Game.grw(x, z)
	if g == 0:
		CityGen._lot(mk, x, z)
		return
	match Game.sub(x, z):
		Game.HOME.TERRACE: _terrace(mk, x, z, g)
		Game.HOME.VILLA: _villa(mk, x, z, g)
		Game.HOME.APARTMENTS: _apartments(mk, x, z, g)
		_: _cottage(mk, x, z, g)


## Wall pattern for a district: brick streets, painted timber in the north, plaster elsewhere.
static func wall_code(x: int, z: int, sea: bool) -> float:
	if sea:
		return MeshKit.SIDING if Game.hashf(x, z, 9) > 0.6 else 0.0
	match CityGen.district(x, z):
		2: return MeshKit.BRICKS
		5: return MeshKit.SIDING
		1: return MeshKit.SIDING if Game.hashf(x, z, 9) > 0.5 else 0.0
	return 0.0


static func _joins(x: int, z: int, dir: int) -> bool:
	return CityGen.joined(x, z, dir, Game.K.HOUSE) or CityGen.joined(x, z, dir, Game.K.SHOP)


# ------------------------------------------------------------------ cottages

static func _cottage(mk: MeshKit, x: int, z: int, g: int) -> void:
	var f := CityGen.facing(x, z)
	var sea := CityGen.coastal(x, z)
	var hill := Game.lvl(x, z) >= 4
	var wall: Color = CityGen.pick(CityGen.SEA_WALLS, x, z, 10) if sea else (CityGen.pick(CityGen.HILL_WALLS, x, z, 10) if hill and Game.hashf(x, z, 8) > 0.5 else CityGen.district_wall(x, z, 10))
	var roof: Color = CityGen.pick(CityGen.SEA_ROOFS, x, z, 11) if sea else (CityGen.pick(CityGen.HILL_ROOFS, x, z, 11) if hill else CityGen.district_roof(x, z, 11))
	if roof.is_equal_approx(Color("ffffff")) and wall.v > 0.95:
		roof = Color("3f7cc4")
	var we := wall_code(x, z, sea) if g < 3 else 0.0
	var right := (f + 1) % 4
	var left := (f + 3) % 4
	var jr := _joins(x, z, right)
	var jl := _joins(x, z, left)
	mk.push_at(Vector3.ZERO, CityGen.yaw_of(f))
	CityGen._plot(mk, Color(0.6, 0.8, 0.45) if g < 3 else SIDEWALK)
	# local frame: +Z = street; local +X is world 'left' (f+3)%4, -X is 'right'
	var join_px := jl
	var join_nx := jr
	var w := 1.25 + 0.2 * Game.hashf(x, z, 12)
	var d := 1.05 + 0.2 * Game.hashf(x, z, 13)
	if g == 2:
		w = 1.5; d = 1.3
	elif g == 3:
		w = 1.72; d = 1.6
	var x0 := -w * 0.5
	var x1 := w * 0.5
	if join_nx: x0 = -H
	if join_px: x1 = H
	w = x1 - x0
	var cx := (x0 + x1) * 0.5
	var cz := -0.1 if g < 3 else 0.0
	var fh := 0.62
	var floors := 1 + int(Game.hashf(x, z, 14) > 0.6)
	if g == 2:
		floors = 2 + int(Game.hashf(x, z, 14) > 0.5)
	elif g == 3:
		floors = 4 + Game.hash2(x, z, 14) % 2 + min(3, CityGen.density(x, z) / 6)
	var hgt := floors * fh + 0.1
	var sides := [true, not join_px, true, not join_nx]
	# a corner plot with a free side towards the side street grows a wing that way
	var side_st := CityGen.side_street(x, z, f)
	var wing := 0.0
	if g < 3 and side_st >= 0:
		var ld := CityGen.local_dir(f, side_st)
		if (ld.x > 0.0 and not join_px) or (ld.x < 0.0 and not join_nx):
			wing = signf(ld.x)
	mk.push_at(Vector3(cx, 0, cz))
	# foundation: a stone plinth on hills and by the sea
	var plinth := Color(0.72, 0.7, 0.66) if hill or sea else wall.darkened(0.25)
	mk.rbox(Vector3(0, 0.08, 0), Vector3(w + 0.06, 0.16, d + 0.06), 0.04, plinth)
	var flat_roof := g == 3 or (sea and Game.hashf(x, z, 15) > 0.55)
	if g == 3:
		_cottage_block(mk, x, z, w, d, fh, floors, hgt, sides)
	else:
		mk.rbox_walls(Vector3(0, 0.1 + hgt * 0.5, 0), Vector3(w, hgt, d), 0.05, wall, we)
		var glass := GLASS
		var door_col: Color = CityGen.pick(DOORS, x, z, 19)
		for fl in floors:
			var yy := 0.1 + fl * fh + fh * 0.52
			var nf := 2 if w < 1.7 else 3
			if fl == 0:
				mk.rbox(Vector3(0, 0.37, d * 0.5 + 0.005), Vector3(0.26, 0.48, 0.05), 0.03, door_col)
				mk.box(Vector3(0.08, 0.37, d * 0.5 + 0.035), Vector3(0.03, 0.03, 0.02), Color(1, 0.85, 0.4))
				if g == 2 and Game.hashf(x, z, 29) > 0.45:
					# bay window
					mk.rbox(Vector3(-w * 0.3, yy, d * 0.5 + 0.1), Vector3(0.44, 0.5, 0.2), 0.03, wall.lightened(0.08))
					mk.window(Vector3(-w * 0.3, yy, d * 0.5 + 0.2), Vector3.BACK, 0.3, 0.3, glass, FRAME)
					mk.box_faces(Vector3(-w * 0.3, yy + 0.28, d * 0.5 + 0.11), Vector3(0.5, 0.05, 0.24), roof, MeshKit.TOP | MeshKit.FRONT)
					mk.window(Vector3(w * 0.3, yy, d * 0.5), Vector3.BACK, 0.24, 0.28, glass, FRAME)
				else:
					for s in [-1, 1]:
						mk.window(Vector3(s * w * 0.3, yy, d * 0.5), Vector3.BACK, 0.24, 0.28, glass, FRAME)
				CityGen._windows_row(mk, yy, w, d, 0, 1, glass, FRAME, [false, sides[1], false, sides[3]])
				CityGen._windows_row(mk, yy, w, d, nf, 0, glass, FRAME, [false, false, true, false])
			else:
				CityGen._windows_row(mk, yy, w, d, nf, 1, glass, FRAME, sides)
				if g == 2 and fl == 1 and Game.hashf(x, z, 20) > 0.4:
					mk.box_faces(Vector3(0, yy - 0.2, d * 0.5 + 0.13), Vector3(0.7, 0.04, 0.26), FRAME, MeshKit.TOP | MeshKit.FRONT | MeshKit.LEFT | MeshKit.RIGHT)
					mk.box_faces(Vector3(0, yy - 0.1, d * 0.5 + 0.255), Vector3(0.7, 0.18, 0.015), Color(0.95, 0.95, 0.95), MeshKit.FRONT | MeshKit.BACK)
					for k in 3:
						mk.blob(Vector3(-0.25 + k * 0.25, yy - 0.13, d * 0.5 + 0.2), Vector3(0.06, 0.05, 0.06), CityGen.AWNINGS[(k + x) % CityGen.AWNINGS.size()])
		var top := 0.1 + hgt
		if flat_roof:
			mk.ledge(Vector3(0, top + 0.05, 0), Vector3(w + 0.05, 0.1, d + 0.05), 0.03, wall.lightened(0.1))
			mk.box_faces(Vector3(0, top + 0.08, 0), Vector3(w - 0.12, 0.02, d - 0.12), wall.darkened(0.12), MeshKit.TOP)
			if Game.hashf(x, z, 21) > 0.5:
				# blue-domed seaside cupola
				mk.cylinder(Vector3(w * 0.2, top + 0.08, -d * 0.15), 0.18, 0.22, 10, wall)
				mk.blob(Vector3(w * 0.2, top + 0.3, -d * 0.15), Vector3(0.18, 0.16, 0.18), roof if roof.b > roof.r else Color("3f7cc4"))
			else:
				# canvas sunshade
				mk.box(Vector3(-w * 0.15, top + 0.38, 0), Vector3(0.6, 0.03, 0.5), CityGen.AWNINGS[Game.hash2(x, z, 22) % CityGen.AWNINGS.size()])
				for px in [-1, 1]:
					for pz in [-1, 1]:
						mk.box(Vector3(-w * 0.15 + px * 0.27, top + 0.22, pz * 0.22), Vector3(0.025, 0.3, 0.025), FRAME)
		else:
			var pitch := (0.5 if not hill else 0.75) * (0.8 + g * 0.15)
			var style := Game.hash2(x, z, 30) % 4
			if join_px or join_nx:
				style = 0  # rows share a ridge along the street
			match style:
				2:
					mk.hip_roof(Vector3(0, top, 0), w, d, pitch * 0.85, 0.12, roof)
				3:
					# gable end to the street
					mk.push_at(Vector3(0, top, 0), PI * 0.5)
					mk.gable_roof(Vector3.ZERO, d, w, pitch * 1.1, 0.12, roof, wall)
					mk.pop()
					mk.window(Vector3(0, top + pitch * 0.4, d * 0.5 + 0.005), Vector3.BACK, 0.16, 0.2, glass, FRAME)
				_:
					mk.gable_roof(Vector3(0, top, 0), w, d, pitch, 0.12, roof, wall)
					if style == 1:
						# a cross gable over the front door
						mk.box_faces(Vector3(0, top - 0.02, d * 0.36), Vector3(0.62, 0.04, 0.32), wall, MeshKit.FRONT | MeshKit.LEFT | MeshKit.RIGHT)
						mk.push_at(Vector3(0, top, d * 0.3), PI * 0.5)
						mk.gable_roof(Vector3.ZERO, 0.5, 0.64, pitch * 0.85, 0.08, roof, wall, 0.05)
						mk.pop()
					elif g == 2 and Game.hashf(x, z, 24) > 0.5:
						# dormer
						mk.rbox(Vector3(0, top + 0.16, d * 0.18), Vector3(0.34, 0.3, 0.3), 0.03, wall)
						mk.window(Vector3(0, top + 0.17, d * 0.18 + 0.15), Vector3.BACK, 0.16, 0.16, glass, FRAME)
						mk.push_at(Vector3(0, top + 0.3, d * 0.18), PI * 0.5)
						mk.gable_roof(Vector3.ZERO, 0.32, 0.36, 0.16, 0.04, roof, wall, 0.04)
						mk.pop()
			if Game.hashf(x, z, 23) > 0.45:
				mk.rbox(Vector3(w * 0.28, top + pitch * 0.6, -d * 0.2), Vector3(0.16, 0.5, 0.16), 0.03, wall.darkened(0.2), null, false, MeshKit.BRICKS)
				mk.box(Vector3(w * 0.28, top + pitch * 0.6 + 0.26, -d * 0.2), Vector3(0.2, 0.04, 0.2), wall.darkened(0.35))
		if wing != 0.0:
			# side wing on a corner plot, its gable to the side street
			var ww := 0.5
			var wd := d * 0.62
			var wx := wing * (w * 0.5 + ww * 0.5 - 0.02)
			var wh := fh + 0.1
			var wmask := MeshKit.FRONT | MeshKit.BACK | (MeshKit.RIGHT if wing > 0.0 else MeshKit.LEFT)
			mk.shadow_faces(Vector3(wx, 0.1 + wh * 0.5, -d * 0.12), Vector3(ww, wh, wd), wmask)
			var was_sh := mk.shadow
			mk.shadow = false
			mk.box_faces(Vector3(wx, 0.1 + wh * 0.5, -d * 0.12), Vector3(ww, wh, wd), wall, wmask, we)
			mk.shadow = was_sh
			mk.window(Vector3(wx + wing * ww * 0.5, 0.1 + fh * 0.52, -d * 0.12), Vector3(wing, 0, 0), 0.24, 0.26, glass, FRAME)
			mk.push_at(Vector3(wx, 0.1 + wh, -d * 0.12), PI * 0.5)
			mk.gable_roof(Vector3.ZERO, wd, ww, 0.3, 0.08, roof, wall, 0.05)
			mk.pop()
		elif g == 1 and Game.hashf(x, z, 31) > 0.45:
			# porch: a little roof on two posts over the door
			mk.box_faces(Vector3(0, 0.66, d * 0.5 + 0.2), Vector3(0.62, 0.04, 0.42), roof.darkened(0.1), MeshKit.TOP | MeshKit.FRONT | MeshKit.LEFT | MeshKit.RIGHT)
			for s in [-1, 1]:
				mk.box(Vector3(s * 0.27, 0.4, d * 0.5 + 0.38), Vector3(0.04, 0.5, 0.04), FRAME)
			mk.box_faces(Vector3(0, 0.12, d * 0.5 + 0.12), Vector3(0.4, 0.06, 0.2), Color(0.8, 0.77, 0.72), MeshKit.TOP | MeshKit.FRONT)
	mk.pop()
	if g < 3:
		_front_garden(mk, x, z, x0, x1, cz, d)
		if not join_px and not join_nx:
			_back_garden(mk, x, z, cz - d * 0.5, wing)
	mk.pop()


## The brick apartment block a cottage becomes downtown.
static func _cottage_block(mk: MeshKit, x: int, z: int, w: float, d: float, fh: float, floors: int, hgt: float, sides: Array) -> void:
	var brick: Color = CityGen.pick(CityGen.BRICK, x, z, 16)
	mk.rbox_walls(Vector3(0, 0.1 + hgt * 0.5, 0), Vector3(w, hgt, d), 0.06, brick, MeshKit.BRICKS if brick.r > brick.b else 0.0)
	mk.bands(0.1 + fh, w, d, fh, floors - 1, 0.04, brick.lightened(0.25))
	for fl in floors:
		var yy := 0.1 + fl * fh + fh * 0.5
		if fl == 0:
			CityGen._windows_row(mk, yy, w, d, 2, 2, GLASS, FRAME, [false, sides[1], true, sides[3]], 0.24, 0.32)
			mk.rbox(Vector3(0, 0.38, d * 0.5 + 0.01), Vector3(0.36, 0.56, 0.06), 0.03, DOOR)
			mk.rbox(Vector3(0, 0.72, d * 0.5 + 0.14), Vector3(0.6, 0.05, 0.3), 0.02, brick.darkened(0.3))
		else:
			CityGen._windows_row(mk, yy, w, d, 3, 3, GLASS, FRAME, sides, 0.24, 0.32)
			if fl % 2 == 1 and Game.hashf(x, z, 17) > 0.4:
				for i in [-1, 1]:
					mk.box_faces(Vector3(i * w * 0.25, yy - fh * 0.32, d * 0.5 + 0.12), Vector3(0.42, 0.04, 0.24), FRAME, MeshKit.TOP | MeshKit.FRONT | MeshKit.LEFT | MeshKit.RIGHT)
					mk.box_faces(Vector3(i * w * 0.25, yy - fh * 0.2, d * 0.5 + 0.235), Vector3(0.42, 0.2, 0.015), Color(1, 1, 1, 1).darkened(0.1), MeshKit.FRONT | MeshKit.BACK)
	var top := 0.1 + hgt
	mk.ledge(Vector3(0, top + 0.06, 0), Vector3(w + 0.06, 0.12, d + 0.06), 0.03, brick.lightened(0.3))
	mk.box_faces(Vector3(0, top + 0.1, 0), Vector3(w - 0.12, 0.02, d - 0.12), Color(0.55, 0.55, 0.57), MeshKit.TOP)
	_roof_kit(mk, x, z, w, d, top + 0.1)


## Rooftop clutter for flat roofs: water tower, garden, plant room or solar panels.
static func _roof_kit(mk: MeshKit, x: int, z: int, w: float, d: float, top: float) -> void:
	match Game.hash2(x, z, 18) % 4:
		0:
			mk.cylinder(Vector3(w * 0.22, top, -d * 0.2), 0.18, 0.32, 8, Color(0.55, 0.42, 0.32), false, null, 0.16)
			mk.cone(Vector3(w * 0.22, top + 0.32, -d * 0.2), 0.2, 0.14, 8, Color(0.45, 0.35, 0.28))
			for k in 4:
				var a := TAU * k / 4.0 + 0.6
				mk.box(Vector3(w * 0.22 + cos(a) * 0.12, top + 0.05, -d * 0.2 + sin(a) * 0.12), Vector3(0.03, 0.12, 0.03), Color(0.3, 0.3, 0.3))
		1:
			for k in 3:
				mk.blob(Vector3(-w * 0.3 + k * w * 0.3, top + 0.1, -d * 0.15), Vector3(0.16, 0.13, 0.16), LEAF[(k + x) % LEAF.size()], 0.04)
		2:
			solar(mk, Vector3(0, top, -d * 0.05), w * 0.7, d * 0.5)
		_:
			mk.rbox(Vector3(-w * 0.2, top + 0.095, 0), Vector3(0.3, 0.19, 0.25), 0.04, Color(0.8, 0.82, 0.85))
			mk.rbox(Vector3(w * 0.15, top + 0.08, -d * 0.2), Vector3(0.2, 0.16, 0.2), 0.04, Color(0.8, 0.82, 0.85))


## A field of tilted solar panels on a flat roof.
static func solar(mk: MeshKit, c: Vector3, w: float, d: float) -> void:
	var rows := maxi(1, int(d / 0.3))
	for r in rows:
		var p := c + Vector3(0, 0.1, -d * 0.5 + (r + 0.5) * d / rows)
		mk.push(Transform3D(Basis(Vector3.RIGHT, -0.5), p))
		mk.box_faces(Vector3.ZERO, Vector3(w, 0.025, 0.22), Color(0.2, 0.28, 0.42), MeshKit.TOP | MeshKit.FRONT, 1.0)
		mk.pop()


static func _front_garden(mk: MeshKit, x: int, z: int, x0: float, x1: float, cz: float, d: float) -> void:
	var gz := cz + d * 0.5 + 0.12
	var room := H - gz
	if room <= 0.3:
		return
	if Game.hashf(x, z, 25) > 0.5:
		# picket fence
		var fx0 := x0 + 0.05
		var fx1 := x1 - 0.05
		var n := int((fx1 - fx0) / 0.2)
		for k in n + 1:
			mk.box(Vector3(fx0 + k * (fx1 - fx0) / max(n, 1), 0.15, H - 0.08), Vector3(0.035, 0.18, 0.03), FRAME)
		mk.box_faces(Vector3((fx0 + fx1) * 0.5, 0.17, H - 0.08), Vector3(fx1 - fx0, 0.03, 0.02), FRAME, MeshKit.TOP | MeshKit.FRONT | MeshKit.BACK)
	else:
		mk.rbox(Vector3((x0 + x1) * 0.5, 0.14, H - 0.12), Vector3(x1 - x0 - 0.1, 0.18, 0.16), 0.07, Color("5c9e4e"))
	mk.blob(Vector3(x0 + 0.2, 0.15, gz + 0.12), Vector3(0.13, 0.11, 0.13), CityGen.pick(CityGen.FLOWERS, x, z, 26))
	mk.blob(Vector3(x1 - 0.22, 0.13, gz + 0.1), Vector3(0.1, 0.09, 0.1), CityGen.pick(CityGen.FLOWERS, x, z, 27))
	mk.box_faces(Vector3(0, 0.065, gz + room * 0.5), Vector3(0.22, 0.01, room), Color(0.86, 0.8, 0.7), MeshKit.TOP)


## Something different behind every detached house.
static func _back_garden(mk: MeshKit, x: int, z: int, back: float, wing: float) -> void:
	var room := back - (-H)
	if room < 0.28:
		return
	var zc := -H + room * 0.5
	var side := -1.0 if wing > 0.0 else 1.0
	match Game.hash2(x, z, 32) % 6:
		0:
			# garden shed
			mk.box(Vector3(side * 0.6, 0.2, zc), Vector3(0.32, 0.28, 0.24), Color(0.62, 0.46, 0.32), null, false, MeshKit.SIDING)
			mk.push_at(Vector3(side * 0.6, 0.34, zc), PI * 0.5)
			mk.gable_roof(Vector3.ZERO, 0.24, 0.32, 0.12, 0.04, Color("5b4a42"), Color(0.62, 0.46, 0.32), 0.03)
			mk.pop()
		1:
			# washing line
			for s in [-1, 1]:
				mk.pole(Vector3(s * 0.55, 0.06, zc), 0.015, 0.4, 4, Color(0.55, 0.55, 0.58))
			mk.box_faces(Vector3(0, 0.44, zc), Vector3(1.1, 0.008, 0.008), Color(0.9, 0.9, 0.9), MeshKit.TOP | MeshKit.FRONT)
			for k in 4:
				mk.box_faces(Vector3(-0.38 + k * 0.25, 0.37, zc), Vector3(0.14, 0.13, 0.01), CityGen.pick(CityGen.AWNINGS + [Color.WHITE], x, z, 33 + k), MeshKit.FRONT | MeshKit.BACK)
		2:
			# vegetable patch
			mk.rbox(Vector3(side * 0.45, 0.08, zc), Vector3(0.7, 0.06, room * 0.7), 0.02, Color(0.5, 0.36, 0.25))
			for k in 3:
				mk.blob(Vector3(side * 0.45 - 0.22 + k * 0.22, 0.15, zc), Vector3(0.07, 0.05, 0.07), Color("6fb35a").lerp(Color("ef5b5b"), 0.3 * (k % 2)))
		3:
			# swing on an A-frame
			for s in [-1, 1]:
				mk.pole(Vector3(side * 0.5 + s * 0.2, 0.06, zc), 0.015, 0.42, 4, Color("e85d5d"))
			mk.box_faces(Vector3(side * 0.5, 0.48, zc), Vector3(0.44, 0.03, 0.03), Color("e85d5d"), MeshKit.TOP | MeshKit.FRONT | MeshKit.BACK)
			mk.box_faces(Vector3(side * 0.5, 0.2, zc), Vector3(0.12, 0.02, 0.06), Color(0.55, 0.4, 0.28), MeshKit.TOP | MeshKit.FRONT)
		4:
			# a tree and a bench
			CityGen._round_tree(mk, Vector3(side * 0.66, 0.06, zc), 0.42, CityGen.pick(LEAF + CityGen.AUTUMN, x, z, 34))
			mk.box_faces(Vector3(-side * 0.3, 0.14, zc), Vector3(0.3, 0.03, 0.1), Color(0.7, 0.5, 0.33), MeshKit.TOP | MeshKit.FRONT | MeshKit.BACK)
		_:
			pass


# ------------------------------------------------------------------ row houses

static func _terrace(mk: MeshKit, x: int, z: int, g: int) -> void:
	var f := CityGen.facing(x, z)
	var jl := _joins(x, z, (f + 3) % 4)
	var jr := _joins(x, z, (f + 1) % 4)
	# alternate colours down the row: neighbours along the street never match
	var along := x if _row_along_x(f) else z
	var wall: Color = TERRACE_COLS[(along * 3 + Game.hash2(x, z, 40) % 2) % TERRACE_COLS.size()]
	var brown := g == 3
	if brown:
		wall = CityGen.pick([Color("a9574a"), Color("8b5a44"), Color("b8735a"), Color("c2684f")], x, z, 41)
	var trim := Color(0.98, 0.97, 0.94)
	var roof: Color = CityGen.district_roof(x, z, 42)
	mk.push_at(Vector3.ZERO, CityGen.yaw_of(f))
	CityGen._plot(mk, SIDEWALK)
	var x0 := -H if jr else -0.88
	var x1 := H if jl else 0.88
	var w := x1 - x0
	var cx := (x0 + x1) * 0.5
	var d := 1.3
	var cz := -0.18
	var fh := 0.6
	var floors: int = [0, 2, 3, 4][g] + (1 if g == 3 and CityGen.density(x, z) > 12 else 0)
	var hgt := floors * fh + 0.16
	var front := cz + d * 0.5
	var door_left := (along % 2) == 0
	var dx := -0.42 if door_left else 0.42
	mk.push_at(Vector3(cx, 0, 0))
	mk.rbox_walls(Vector3(0, hgt * 0.5, cz), Vector3(w, hgt, d), 0.03, wall, MeshKit.BRICKS if brown else 0.0)
	# basement / plinth course and cornice
	mk.box_faces(Vector3(0, 0.1, front + 0.01), Vector3(w, 0.2, 0.04), wall.darkened(0.25), MeshKit.FRONT | MeshKit.TOP)
	mk.bands(0.16 + fh, w, d, fh, floors - 1, 0.035, trim)
	mk.ledge(Vector3(0, hgt + 0.04, cz), Vector3(w + 0.04, 0.08, d + 0.08), 0.02, trim)
	# stoop: steps up to the door with a railing
	mk.rbox(Vector3(dx, 0.36, front + 0.006), Vector3(0.24, 0.42, 0.04), 0.02, CityGen.pick(DOORS, x, z, 43))
	mk.window(Vector3(dx, 0.62, front + 0.004), Vector3.BACK, 0.22, 0.08, CityGen.GLASS_LIGHT, Color(0, 0, 0, 0), true)
	for k in 3:
		mk.box_faces(Vector3(dx, 0.04 + k * 0.05, front + 0.26 - k * 0.07), Vector3(0.3, 0.05, 0.12), Color(0.8, 0.77, 0.72), MeshKit.TOP | MeshKit.FRONT)
	mk.box_faces(Vector3(dx, 0.68, front + 0.12), Vector3(0.38, 0.04, 0.24), trim, MeshKit.TOP | MeshKit.FRONT | MeshKit.LEFT | MeshKit.RIGHT)
	# bay window beside the door, the full height of the lower floors
	var bx := -dx * 0.85
	var bay_h := fh * mini(floors - 1, 2)
	mk.box_faces(Vector3(bx, 0.16 + bay_h * 0.5, front + 0.1), Vector3(0.62, bay_h, 0.2), wall.lightened(0.06), MeshKit.FRONT | MeshKit.LEFT | MeshKit.RIGHT, MeshKit.BRICKS if brown else 0.0)
	for fl in mini(floors - 1, 2):
		mk.window_row(Vector3(bx, 0.16 + fl * fh + fh * 0.52, front + 0.2), Vector3.BACK, 0.56, 2, 0.2, 0.3, GLASS)
	mk.box_faces(Vector3(bx, 0.16 + bay_h + 0.02, front + 0.1), Vector3(0.66, 0.04, 0.24), trim, MeshKit.TOP | MeshKit.FRONT | MeshKit.LEFT | MeshKit.RIGHT)
	var sides := [true, not jl, true, not jr]
	for fl in floors:
		var yy := 0.16 + fl * fh + fh * 0.52
		if fl >= 2 or (fl == 1 and floors == 2):
			mk.window_row(Vector3(0, yy, front), Vector3.BACK, w * 0.86, 2 if w < 1.85 else 3, 0.22, 0.32, GLASS)
		elif fl == 1:
			mk.window(Vector3(dx, yy, front), Vector3.BACK, 0.22, 0.32, GLASS, FRAME)
		CityGen._windows_row(mk, yy, w, d, 2, 2, GLASS, FRAME, [false, sides[1], true, sides[3]])
		if fl >= 2 and Game.hashf(x, z, 44 + fl) > 0.55:
			# window boxes with flowers
			mk.box_faces(Vector3(0, yy - 0.2, front + 0.04), Vector3(w * 0.5, 0.06, 0.08), wall.darkened(0.3), MeshKit.TOP | MeshKit.FRONT)
			mk.blob(Vector3(-w * 0.12, yy - 0.15, front + 0.05), Vector3(0.06, 0.04, 0.05), CityGen.pick(CityGen.FLOWERS, x, z, 50 + fl))
			mk.blob(Vector3(w * 0.12, yy - 0.15, front + 0.05), Vector3(0.06, 0.04, 0.05), CityGen.pick(CityGen.FLOWERS, x, z, 52 + fl))
	var top := hgt + 0.08
	if brown:
		# mansard roof with dormers
		mk.hip_roof(Vector3(0, top, cz), w - 0.04, d - 0.04, 0.3, 0.0, Color("4b5262"))
		for s in [-1, 1]:
			mk.box_faces(Vector3(s * w * 0.22, top + 0.14, cz + d * 0.42), Vector3(0.24, 0.22, 0.16), trim, MeshKit.TOP | MeshKit.FRONT | MeshKit.LEFT | MeshKit.RIGHT)
			mk.window(Vector3(s * w * 0.22, top + 0.14, cz + d * 0.5), Vector3.BACK, 0.13, 0.14, GLASS, FRAME)
	else:
		mk.gable_roof(Vector3(0, top, cz), w, d, 0.42, 0.06 if not (jl or jr) else 0.02, roof, wall)
		if Game.hashf(x, z, 46) > 0.4:
			mk.box_faces(Vector3(0, top + 0.16, cz + d * 0.22), Vector3(0.3, 0.26, 0.26), wall, MeshKit.FRONT | MeshKit.LEFT | MeshKit.RIGHT)
			mk.window(Vector3(0, top + 0.17, cz + d * 0.22 + 0.13), Vector3.BACK, 0.14, 0.14, GLASS, FRAME)
			mk.push_at(Vector3(0, top + 0.3, cz + d * 0.22), PI * 0.5)
			mk.gable_roof(Vector3.ZERO, 0.28, 0.32, 0.14, 0.03, roof, wall, 0.03)
			mk.pop()
	# chimney stacks on the party walls (and the end wall)
	for s in [-1.0, 1.0]:
		var free := not jr if s < 0.0 else not jl
		if s > 0.0 or free:
			var px: float = s * w * 0.5 - s * (0.12 if free else 0.0)
			mk.box(Vector3(px, top + 0.35, cz - d * 0.15), Vector3(0.2, 0.42, 0.26), wall.darkened(0.15), null, false, MeshKit.BRICKS)
			for k in 2:
				mk.pole(Vector3(px - 0.05 + k * 0.1, top + 0.56, cz - d * 0.15), 0.035, 0.08, 5, Color("c9774b"))
	# railings round the area in front of the bay
	mk.box_faces(Vector3(bx, 0.24, H - 0.1), Vector3(0.7, 0.03, 0.02), Color(0.2, 0.22, 0.25), MeshKit.TOP | MeshKit.FRONT | MeshKit.BACK)
	mk.pop()
	mk.pop()


## Whether a row facing direction f runs along x (so neighbours along it differ in x).
static func _row_along_x(f: int) -> bool:
	return CityGen.DIRS[f].x == 0


# ------------------------------------------------------------------ villas

static func _villa(mk: MeshKit, x: int, z: int, g: int) -> void:
	var f := CityGen.facing(x, z)
	var sea := CityGen.coastal(x, z)
	var hill := Game.lvl(x, z) >= 4
	var wall: Color = CityGen.pick([Color("fbf1df"), Color("f8f6f0"), Color("f2d4a8"), Color("efe4d2"), Color("f6e3c4")], x, z, 60)
	var roof: Color = CityGen.pick([Color("c9774b"), Color("d9694f"), Color("b9503f")], x, z, 61) if not hill else Color("4b5262")
	mk.push_at(Vector3.ZERO, CityGen.yaw_of(f))
	# lawn, hedged on every side that isn't the street
	mk.rbox(Vector3(0, 0.03, 0), Vector3(1.96, 0.06, 1.96), 0.03, Color(0.5, 0.78, 0.42), null, false, MeshKit.MOWN_X if f % 2 == 0 else MeshKit.MOWN_Z)
	var hedge := Color("4e8f45")
	for i in 4:
		var wd := CityGen.DIRS[i]
		var lc := CityGen.local_dir(f, i)
		if lc == Vector3.BACK:
			continue
		if Game.knd(x + wd.x, z + wd.y) == Game.K.HOUSE and Game.sub(x + wd.x, z + wd.y) == Game.HOME.VILLA:
			continue  # neighbouring villas share one open lawn
		var along := Vector3(absf(lc.z), 0, absf(lc.x))
		mk.rbox(lc * 0.9 + Vector3(0, 0.145, 0), along * 1.8 + Vector3(absf(lc.x), 0, absf(lc.z)) * 0.14 + Vector3(0, 0.17, 0), 0.04, hedge)
	# gate posts and a gravel drive
	for s in [-1, 1]:
		mk.box(Vector3(s * 0.26, 0.2, 0.9), Vector3(0.065, 0.32, 0.065), wall.darkened(0.1))
	mk.box_faces(Vector3(0, 0.065, 0.62), Vector3(0.36, 0.01, 0.56), Color(0.9, 0.86, 0.78), MeshKit.TOP)
	var w: float = [0, 1.2, 1.34, 1.3][g]
	var d := 0.86
	var cz := 0.12
	var fh := 0.6
	var floors := 1 if g == 1 else 2
	var hgt := floors * fh + 0.08
	mk.rbox(Vector3(0, 0.08, cz), Vector3(w + 0.1, 0.1, d + 0.1), 0.03, Color(0.86, 0.82, 0.76))
	mk.rbox_walls(Vector3(0, 0.1 + hgt * 0.5, cz), Vector3(w, hgt, d), 0.04, wall)
	var front := cz + d * 0.5
	for fl in floors:
		var yy := 0.1 + fl * fh + fh * 0.52
		mk.window_row(Vector3(0, yy, front), Vector3.BACK, w * 0.9, 4 if fl > 0 else 2, 0.2, 0.34, GLASS)
		CityGen._windows_row(mk, yy, w, d, 3, 2, GLASS, FRAME, [false, true, true, true])
	# a glazed front door under a portico
	mk.rbox(Vector3(0, 0.38, front + 0.006), Vector3(0.28, 0.5, 0.04), 0.02, CityGen.pick(DOORS, x, z, 62))
	if g >= 2:
		var cols := 4 if g == 3 else 2
		for k in cols:
			var px: float = -0.3 + k * 0.6 / (cols - 1)
			mk.cylinder(Vector3(px, 0.13, front + 0.24), 0.04, fh + 0.02, 8, Color(0.98, 0.97, 0.94))
		mk.rbox(Vector3(0, fh + 0.16, front + 0.18), Vector3(0.8, 0.07, 0.42), 0.02, Color(0.98, 0.97, 0.94))
		# balcony over the portico
		mk.box(Vector3(0, fh + 0.27, front + 0.37), Vector3(0.8, 0.12, 0.02), Color(0.98, 0.97, 0.94))
	var top := 0.1 + hgt
	mk.hip_roof(Vector3(0, top, cz), w, d, 0.36 if not hill else 0.5, 0.14, roof)
	if g == 3:
		# a mansion: low wings either side
		for s in [-1.0, 1.0]:
			var wx: float = s * (w * 0.5 + 0.18)
			mk.rbox(Vector3(wx, 0.1 + (fh + 0.06) * 0.5, cz - 0.05), Vector3(0.38, fh + 0.06, 0.62), 0.03, wall)
			mk.window(Vector3(wx, 0.1 + fh * 0.52, cz + 0.26), Vector3.BACK, 0.2, 0.3, GLASS, FRAME)
			mk.hip_roof(Vector3(wx, 0.16 + fh, cz - 0.05), 0.38, 0.62, 0.2, 0.08, roof)
	if Game.hashf(x, z, 63) > 0.35:
		mk.rbox(Vector3(-w * 0.3, top + 0.22, cz - 0.12), Vector3(0.14, 0.4, 0.14), 0.02, wall.darkened(0.12))
	# back garden: a pool with loungers, or a terrace with a pergola
	var pz := -0.66
	if Game.hashf(x, z, 64) > 0.25 or sea:
		mk.rbox(Vector3(0.08, 0.075, pz), Vector3(1.0, 0.05, 0.46), 0.02, Color(0.96, 0.95, 0.92), null, false, MeshKit.PAVING)
		mk.box_faces(Vector3(0.08, 0.1, pz), Vector3(0.84, 0.004, 0.32), Color(0.35, 0.75, 0.9), MeshKit.TOP, 3.0)
		for k in 2:
			mk.box_faces(Vector3(-0.7, 0.12, pz - 0.12 + k * 0.24), Vector3(0.26, 0.03, 0.1), Color.WHITE, MeshKit.TOP | MeshKit.FRONT | MeshKit.BACK)
		mk.pole(Vector3(-0.62, 0.06, pz), 0.012, 0.36, 4, Color(0.9, 0.9, 0.9))
		mk.cone(Vector3(-0.62, 0.36, pz), 0.2, 0.08, 8, CityGen.pick(CityGen.AWNINGS, x, z, 65))
	else:
		mk.rbox(Vector3(0, 0.07, pz), Vector3(1.0, 0.04, 0.42), 0.02, Color(0.78, 0.66, 0.5), null, false, MeshKit.PAVING)
		for k in 3:
			mk.box_faces(Vector3(-0.4 + k * 0.4, 0.42, pz), Vector3(0.04, 0.04, 0.44), Color(0.6, 0.45, 0.3), MeshKit.TOP | MeshKit.LEFT | MeshKit.RIGHT)
		for s in [-1, 1]:
			mk.box(Vector3(s * 0.44, 0.25, pz + 0.18), Vector3(0.04, 0.36, 0.04), Color(0.6, 0.45, 0.3))
		mk.blob(Vector3(0.44, 0.48, pz), Vector3(0.12, 0.08, 0.2), Color("7cb35a"), 0.04)
	# trees that suit the spot
	var corner := Vector3(0.68, 0.06, -0.2)
	if sea:
		CityGen._palm(mk, corner, 0.62, Game.hash2(x, z, 66) % 100)
	elif hill:
		CityGen._pine(mk, corner, 0.7, Color("3f7f4f"))
	else:
		CityGen._round_tree(mk, corner, 0.5, CityGen.pick(LEAF, x, z, 67))
	mk.pop()


# ------------------------------------------------------------------ apartments

static func _apartments(mk: MeshKit, x: int, z: int, g: int) -> void:
	var f := CityGen.facing(x, z)
	var jl := _joins(x, z, (f + 3) % 4)
	var jr := _joins(x, z, (f + 1) % 4)
	var wall: Color = CityGen.pick(APT_COLS, x, z, 70)
	var trim := Color(0.97, 0.96, 0.93)
	var dens := CityGen.density(x, z)
	mk.push_at(Vector3.ZERO, CityGen.yaw_of(f))
	CityGen._plot(mk, SIDEWALK)
	var x0 := -H if jr else -0.86
	var x1 := H if jl else 0.86
	var w := x1 - x0
	var cx := (x0 + x1) * 0.5
	var d := 1.5
	var cz := -0.12
	var fh := 0.52
	var floors: int = [0, 3, 5, 7][g] + (mini(3, dens / 6) if g == 3 else 0)
	var base := 0.68  # tall ground floor
	var hgt := base + (floors - 1) * fh
	var front := cz + d * 0.5
	# shops on the ground floor when the street is busy
	var retail := g >= 2 and (CityGen.around(x, z, Game.K.SHOP) > 0 or _on_avenue(x, z))
	mk.push_at(Vector3(cx, 0, 0))
	mk.rbox_walls(Vector3(0, 0.06 + hgt * 0.5, cz), Vector3(w, hgt, d), 0.04, wall)
	mk.box_faces(Vector3(0, 0.06 + base * 0.5, front + 0.012), Vector3(w, base, 0.02), wall.darkened(0.2) if not retail else Color(0.3, 0.32, 0.36), MeshKit.FRONT)
	if retail:
		var awn: Color = CityGen.pick(CityGen.AWNINGS, x, z, 71)
		mk.window_row(Vector3(0, 0.36, front + 0.02), Vector3.BACK, w * 0.9, 3, w * 0.24, 0.42, CityGen.GLASS_LIGHT, false)
		mk.push(Transform3D(Basis(Vector3.RIGHT, 0.45), Vector3(0, 0.66, front + 0.02)))
		mk.box_faces(Vector3(0, 0, 0.17), Vector3(w * 0.92, 0.03, 0.34), awn, MeshKit.TOP | MeshKit.FRONT)
		mk.pop()
	else:
		mk.rbox(Vector3(0, 0.36, front + 0.03), Vector3(0.36, 0.5, 0.05), 0.02, Color(0.45, 0.5, 0.56))
		mk.window(Vector3(0, 0.38, front + 0.06), Vector3.BACK, 0.26, 0.38, CityGen.GLASS_LIGHT, Color(0, 0, 0, 0), true)
		mk.box_faces(Vector3(0, 0.68, front + 0.2), Vector3(0.6, 0.04, 0.4), trim, MeshKit.TOP | MeshKit.FRONT | MeshKit.LEFT | MeshKit.RIGHT)
		for s in [-1, 1]:
			mk.box_faces(Vector3(s * w * 0.32, 0.16, front + 0.22), Vector3(0.3, 0.2, 0.2), Color(0.74, 0.72, 0.68), MeshKit.TOP | MeshKit.FRONT | MeshKit.LEFT | MeshKit.RIGHT)
			mk.blob(Vector3(s * w * 0.32, 0.32, front + 0.22), Vector3(0.12, 0.1, 0.09), CityGen.pick(LEAF, x, z, 72 + s), 0.04)
	mk.bands(0.06 + base, w, d, fh, floors - 1, 0.03, trim)
	# balconies: stacked down the front, alternating on every other floor
	var cols := 2 if w < 1.85 else 3
	var bal_glass := Color(0.75, 0.88, 0.95)
	for fl in range(1, floors):
		var yy := 0.06 + base + (fl - 1) * fh + fh * 0.52
		mk.window_row(Vector3(0, yy, front), Vector3.BACK, w * 0.9, cols * 2, w * 0.9 / (cols * 2) * 0.62, fh * 0.6, GLASS, false)
		CityGen._windows_row(mk, yy, w, d, cols * 2, 3, GLASS, Color(0, 0, 0, 0), [false, not jl, true, not jr], 0.16, fh * 0.56)
		var stagger := fl % 2
		for c in cols:
			if (c + stagger) % 2 == 1 and cols == 3:
				continue
			var bx := -w * 0.45 + (c + 0.5) * w * 0.9 / cols
			mk.box_faces(Vector3(bx, yy - fh * 0.42, front + 0.11), Vector3(w * 0.9 / cols * 0.8, 0.035, 0.22), trim, MeshKit.TOP | MeshKit.FRONT | MeshKit.LEFT | MeshKit.RIGHT)
			mk.box_faces(Vector3(bx, yy - fh * 0.3, front + 0.215), Vector3(w * 0.9 / cols * 0.8, 0.2, 0.012), bal_glass, MeshKit.FRONT | MeshKit.BACK)
	var top := 0.06 + hgt
	mk.ledge(Vector3(0, top + 0.05, cz), Vector3(w + 0.04, 0.1, d + 0.04), 0.02, trim)
	if g == 3 and w > 1.5:
		# penthouse set back behind a roof terrace
		mk.rbox(Vector3(0, top + 0.08 + fh * 0.5, cz - 0.2), Vector3(w * 0.6, fh, d * 0.55), 0.03, wall.lightened(0.1))
		mk.window_row(Vector3(0, top + 0.08 + fh * 0.5, cz - 0.2 + d * 0.275), Vector3.BACK, w * 0.5, 3, 0.2, fh * 0.6, GLASS, false)
		mk.box(Vector3(0, top + 0.18, front - 0.02), Vector3(w * 0.9, 0.1, 0.02), bal_glass)
		mk.pole(Vector3(w * 0.32, top + 0.08, front - 0.25), 0.012, 0.32, 4, Color(0.9, 0.9, 0.9))
		mk.cone(Vector3(w * 0.32, top + 0.4, front - 0.25), 0.2, 0.08, 8, CityGen.pick(CityGen.AWNINGS, x, z, 73))
	else:
		_roof_kit(mk, x, z, w, d, top + 0.1)
	mk.pop()
	mk.pop()


static func _on_avenue(x: int, z: int) -> bool:
	for d in CityGen.DIRS:
		if Game.knd(x + d.x, z + d.y) == Game.K.ROAD and Game.sub(x + d.x, z + d.y) == Game.ROAD_SUB.AVENUE:
			return true
	return false
