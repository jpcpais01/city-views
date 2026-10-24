class_name Ships
extends Node3D
## Big ships passing the island now and then: a white cruise liner with rows
## of cabins, a container ship stacked with coloured boxes, and a ferry. Each
## comes in from beyond the horizon, sails past well offshore on a straight
## course and goes out of sight again; there is rarely more than one in view.

const WAIT := Vector2(25.0, 70.0)
const SPEED := 2.2
# how far past the coast they keep, and how far each run is
const OFFSHORE := 26.0
const RUN := 300.0
const NIGHT_GLOW := 2.0

var material: Material
var world: World
var _kinds: Array[Array] = []
var _ships: Array = []
var _wait := 8.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	# each with the wake it leaves: from its stern, how long, how wide
	for k: Array in [[_cruise, -8.2, 30.0, 2.4], [_freighter, -8.6, 28.0, 2.5], [_ferry, -5.6, 22.0, 2.2]]:
		var mk := MeshKit.new(_kinds.size() + 40)
		(k[0] as Callable).call(mk)
		var m := mk.commit(material)
		Wake.add(m, Vector3(k[1], 0.09, 0), Vector3.LEFT, Vector3.BACK, k[2], k[3])
		_kinds.append([m, mk.commit_shadow(Palette.shadow_material())])


func _process(delta: float) -> void:
	_wait -= delta
	if _wait <= 0.0:
		_wait = _rng.randf_range(WAIT.x, WAIT.y)
		var land: Land = world.get("land")
		if _ships.size() < 2 and (land == null or land.has_sea()):
			spawn(_rng.randi() % _kinds.size())
	var t := Time.get_ticks_msec() * 0.001
	for sh in _ships.duplicate():
		sh.d += SPEED * sh.v * delta
		if sh.d > RUN:
			sh.node.queue_free()
			_ships.erase(sh)
			continue
		var p: Vector2 = sh.a + sh.dir * sh.d
		var node: Node3D = sh.node
		var roll := sin(t * 0.6 + sh.ph) * 0.015
		node.transform = Transform3D(Basis(Vector3.UP, sh.yaw) * Basis(Vector3.RIGHT, roll),
			Vector3(p.x, sin(t * 0.8 + sh.ph) * 0.03 - 0.05, p.y))


## Sends a ship of `kind` past the island on a fresh course.
func spawn(kind: int, halfway := false) -> void:
	var land: Land = world.get("land")
	var r := minf(land.reach if land else Land.HALF, Land.HALF * 1.2) + OFFSHORE + _rng.randf() * 12.0
	var side := _rng.randf() * TAU
	var mid := Vector2.from_angle(side) * r
	var dir := Vector2.from_angle(side + PI * 0.5) * (1.0 if _rng.randf() < 0.5 else -1.0)
	if land and land.kind in Land.OPEN_KINDS:
		# along the coast, well out past the beaches
		var c := land.coast()
		var inland := Vector2(c.x, c.y)
		dir = inland.orthogonal() * (1.0 if _rng.randf() < 0.5 else -1.0)
		mid = inland * (c.z - 75.0 - _rng.randf() * 30.0) + dir * _rng.randf_range(-80.0, 80.0)
	var node := Node3D.new()
	add_child(node)
	var body := MeshInstance3D.new()
	body.mesh = _kinds[kind][0]
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(body)
	if _kinds[kind][1]:
		var sm := MeshInstance3D.new()
		sm.mesh = _kinds[kind][1]
		sm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		node.add_child(sm)
	# local +X is the bow
	_ships.append({"node": node, "a": mid - dir * RUN * 0.5, "dir": dir, "d": RUN * 0.5 if halfway else 0.0,
		"yaw": -dir.angle(), "v": _rng.randf_range(0.8, 1.15), "ph": _rng.randf() * TAU})


func ship_count() -> int:
	return _ships.size()


# ------------------------------------------------------------------ hulls

## A lofted hull (BoatKit.hull) `length` long and `beam` wide with its bow
## towards +X: a fine, raked bow, a long parallel middle and a squared stern,
## the deck at `top` rising a little towards the bow.
func _hull(mk: MeshKit, length: float, beam: float, top: float, col: Color, below: Color, deck: Color) -> void:
	var h := length * 0.5
	var w := beam * 0.5
	mk.push(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3.ZERO))
	BoatKit.hull(mk, [Vector4(-h, w * 0.92, top, -0.05), Vector4(-h + 1.0, w, top, -0.3), Vector4(h - 4.0, w, top, -0.3),
		Vector4(h - 2.0, w * 0.82, top + 0.05, -0.28), Vector4(h - 0.8, w * 0.42, top + 0.12, -0.2), Vector4(h, 0.0, top + 0.2, 0.0)],
		col, below, 0.12, deck)
	mk.pop()
	# a boot stripe in the line's colour along the waterline, and the anchors
	for sz: float in [-1.0, 1.0]:
		mk.quad(Vector3(-h + 1.0, 0.13, sz * (w + 0.002)), Vector3(h - 4.0, 0.13, sz * (w + 0.002)), Vector3(h - 4.0, 0.2, sz * (w + 0.002)), Vector3(-h + 1.0, 0.2, sz * (w + 0.002)), Vector3(0, 0, sz), below.lightened(0.15))
		mk.box_faces(Vector3(h - 1.4, top - 0.18, sz * w * 0.62), Vector3(0.18, 0.16, 0.02), Color(0.18, 0.18, 0.2), MeshKit.LEFT | MeshKit.RIGHT | MeshKit.FRONT | MeshKit.BACK)


func _walls(mk: MeshKit, pts: PackedVector2Array, y0: float, y1: float, col: Color, e := 0.0) -> void:
	var cw := Geometry2D.is_polygon_clockwise(pts)
	for k in pts.size():
		var a := pts[k]
		var b := pts[(k + 1) % pts.size()]
		var t := (b - a).normalized()
		var out := Vector2(-t.y, t.x) if cw else Vector2(t.y, -t.x)
		mk.quad(Vector3(a.x, y0, a.y), Vector3(b.x, y0, b.y), Vector3(b.x, y1, b.y), Vector3(a.x, y1, a.y), Vector3(out.x, 0, out.y), col, e)


func _cap(mk: MeshKit, pts: PackedVector2Array, y: float, col: Color) -> void:
	var tris := Geometry2D.triangulate_polygon(pts)
	for k in range(0, tris.size(), 3):
		var a := pts[tris[k]]
		var b := pts[tris[k + 1]]
		var c := pts[tris[k + 2]]
		mk.tri(Vector3(a.x, y, a.y), Vector3(b.x, y, b.y), Vector3(c.x, y, c.y), col, 0.0, 0.0, Vector3.UP)


## A row of lit cabin windows down both sides of a deck.
func _cabins(mk: MeshKit, x0: float, x1: float, half_beam: float, y: float, count: int) -> void:
	for side: float in [-1.0, 1.0]:
		mk.window_row(Vector3((x0 + x1) * 0.5, y, side * (half_beam + 0.005)), Vector3(0, 0, side), x1 - x0, count, 0.16, 0.12, Palette.GLASS, false)


## A white rail round the edge of a deck outline at height y.
func _deck_rail(mk: MeshKit, pts: PackedVector2Array, y: float) -> void:
	var loop := []
	for p in pts:
		loop.append(Vector3(p.x, y, p.y))
	loop.append(loop[0])
	BoatKit.rail(mk, loop, 0.14, Color(0.95, 0.95, 0.93), 0.025)


## A radar mast: a pole with a crossbar, a turning scanner and a white dome.
func _radar(mk: MeshKit, at: Vector3, h: float) -> void:
	mk.cylinder(at, 0.05, h, 6, Color(0.95, 0.95, 0.93))
	BoatKit.line(mk, at + Vector3(0, h * 0.75, -0.45), at + Vector3(0, h * 0.75, 0.45), 0.05, Color(0.95, 0.95, 0.93))
	mk.box(at + Vector3(0, h + 0.03, 0), Vector3(0.08, 0.04, 0.7), Color(0.2, 0.2, 0.22))
	mk.cylinder(at + Vector3(-0.3, h * 0.75, 0.0), 0.12, 0.18, 8, Color(0.97, 0.97, 0.95))
	mk.box(at + Vector3(0, h + 0.12, 0), Vector3(0.06, 0.06, 0.06), Color(1, 0.9, 0.6), null, false, NIGHT_GLOW)


## Bridge wings: a deck reaching out over each side, glassed at the front.
func _wings(mk: MeshKit, x: float, y: float, reach: float) -> void:
	mk.box(Vector3(x, y, 0), Vector3(0.5, 0.08, reach * 2.0), Color(0.97, 0.97, 0.95), null, true)
	for sz: float in [-1.0, 1.0]:
		mk.box_faces(Vector3(x + 0.1, y + 0.13, sz * (reach - 0.15)), Vector3(0.3, 0.18, 0.3), Color(0.97, 0.97, 0.95), MeshKit.TOP | MeshKit.FRONT | MeshKit.BACK | MeshKit.LEFT | MeshKit.RIGHT)
		mk.window_row(Vector3(x + 0.251, y + 0.15, sz * (reach - 0.15)), Vector3.RIGHT, 0.26, 2, 0.1, 0.09, Palette.GLASS, false)


## A funnel tapering up from `at`, the line's colours with a black top.
func _funnel(mk: MeshKit, at: Vector3, h: float, r: float, col: Color, band: Color) -> void:
	mk.push(Transform3D(Basis.from_scale(Vector3(1.4, 1.0, 1.0)), at))
	mk.cylinder(Vector3.ZERO, r, h * 0.6, 10, col, false, null, r * 0.94)
	mk.cylinder(Vector3(0, h * 0.6, 0), r * 0.94, h * 0.25, 10, band, false, null, r * 0.9)
	mk.cylinder(Vector3(0, h * 0.85, 0), r * 0.9, h * 0.15, 10, Color("1b1b1f"), true, Color(0.08, 0.08, 0.09), r * 0.88)
	mk.pop()


## A lifeboat in its davits: an orange hull under a white canopy.
func _lifeboat(mk: MeshKit, at: Vector3) -> void:
	mk.box_faces(at, Vector3(0.75, 0.14, 0.24), Color("f08a24"), MeshKit.FRONT | MeshKit.BACK | MeshKit.LEFT | MeshKit.RIGHT)
	mk.box_faces(at + Vector3(0, 0.1, 0), Vector3(0.6, 0.09, 0.2), Color(0.97, 0.97, 0.95), MeshKit.TOP | MeshKit.FRONT | MeshKit.BACK | MeshKit.LEFT | MeshKit.RIGHT)


# ------------------------------------------------------------------ ships

func _cruise(mk: MeshKit) -> void:
	_hull(mk, 16.0, 2.4, 1.0, Color("f4f3ef"), Color("1f3550"), Color("c99a6b"))
	_cabins(mk, -7.2, 5.0, 1.2, 0.68, 22)
	var white := Color("fbfaf6")
	# decks stepping back towards the stern, each a little narrower, balconied
	var decks := [[-7.0, 4.4, 1.05], [-6.6, 3.6, 0.98], [-6.0, 2.6, 0.9], [-5.2, 1.4, 0.8]]
	var y := 1.0
	var outline := PackedVector2Array()
	for d in decks:
		var x0: float = d[0]
		var x1: float = d[1]
		var hw: float = d[2]
		outline = PackedVector2Array([Vector2(x0, -hw), Vector2(x1 - 0.5, -hw), Vector2(x1, 0), Vector2(x1 - 0.5, hw), Vector2(x0, hw)])
		_walls(mk, outline, y, y + 0.42, white)
		_cap(mk, outline, y + 0.42, Color("dfe6ea"))
		_cabins(mk, x0 + 0.3, x1 - 0.7, hw, y + 0.22, int((x1 - x0) * 1.6))
		# a balcony rail down each side, between this deck and the next
		for sz: float in [-1.0, 1.0]:
			mk.box_faces(Vector3((x0 + x1 - 0.7) * 0.5, y + 0.06, sz * (hw + 0.02)), Vector3(x1 - x0 - 0.9, 0.05, 0.04), Color(0.55, 0.68, 0.76), MeshKit.TOP | MeshKit.LEFT | MeshKit.RIGHT)
		y += 0.42
	_deck_rail(mk, outline, y)
	# the sun deck: a pool ringed by loungers, a waterslide, the funnel and the radar
	mk.box_faces(Vector3(-1.5, y + 0.01, 0), Vector3(1.4, 0.02, 0.7), Color("49b6d6"), MeshKit.TOP)
	for k in 6:
		for sz: float in [-1.0, 1.0]:
			mk.box_faces(Vector3(-2.1 + k * 0.24, y + 0.03, sz * 0.52), Vector3(0.16, 0.03, 0.2), Color("f2f0e8") if k % 2 == 0 else Color("e7804f"), MeshKit.TOP)
	for k in 5:
		var a := float(k) / 5.0 * PI * 1.5
		var b := float(k + 1) / 5.0 * PI * 1.5
		BoatKit.line(mk, Vector3(-3.0 + cos(a) * 0.35, y + 0.75 - k * 0.14, sin(a) * 0.35), Vector3(-3.0 + cos(b) * 0.35, y + 0.61 - k * 0.14, sin(b) * 0.35), 0.1, Color("e3a33b"))
	_funnel(mk, Vector3(-4.2, y, 0), 1.0, 0.36, Color("1f3550"), Color("c8553d"))
	_radar(mk, Vector3(2.4, 2.68, 0), 0.6)
	# the bridge's windows across the front, with its wings
	mk.window_row(Vector3(3.82, 2.25, 0), Vector3.RIGHT, 1.6, 8, 0.14, 0.12, Palette.GLASS, false)
	_wings(mk, 3.4, 2.5, 1.45)
	# lifeboats in a row along each side
	for side: float in [-1.0, 1.0]:
		for k in 5:
			_lifeboat(mk, Vector3(-4.8 + k * 1.9, 1.2, side * 1.12))
	# a string of lights from the bow up to the funnel, lit at night
	var bow := Vector3(7.6, 1.25, 0)
	var top := Vector3(-4.2, y + 1.0, 0)
	BoatKit.line(mk, bow, top, 0.015, Color(0.3, 0.3, 0.3))
	for k in 8:
		mk.box_faces(bow.lerp(top, (k + 0.5) / 8.0) - Vector3(0, 0.04, 0), Vector3(0.06, 0.06, 0.06), Color(1, 0.86, 0.55), MeshKit.TOP | MeshKit.LEFT | MeshKit.RIGHT, NIGHT_GLOW)
	BoatKit.rail(mk, [Vector3(5.0, 1.02, -1.1), Vector3(6.6, 1.05, -0.75), Vector3(7.9, 1.18, 0), Vector3(6.6, 1.05, 0.75), Vector3(5.0, 1.02, 1.1)], 0.14, Color(0.95, 0.95, 0.93), 0.025)


func _freighter(mk: MeshKit) -> void:
	_hull(mk, 17.0, 2.5, 0.85, Color("2f4f7a"), Color("9a2f2a"), Color("6d6f73"))
	# containers in stacks of colours across the deck
	var cols := [Color("c8553d"), Color("2f8f83"), Color("e3a33b"), Color("3d5f8f"), Color("8c5aa8"), Color("d9d4c7"), Color("5e8f4a")]
	var x := 5.0
	var k := 0
	while x > -4.5:
		for row: float in [-0.62, 0.0, 0.62]:
			var hgt := 0.3 * (2 + (k * 7 + int(row * 10.0)) % 3)
			var c: Color = cols[(k * 3 + int(row * 10.0 + 10.0)) % cols.size()]
			mk.box_faces(Vector3(x, 0.85 + hgt * 0.5, row), Vector3(1.05, hgt, 0.58), c, MeshKit.TOP | MeshKit.FRONT | MeshKit.BACK | MeshKit.LEFT | MeshKit.RIGHT)
		x -= 1.15
		k += 1
	# two deck cranes between the stacks
	for cx: float in [2.1, -2.5]:
		var base := Vector3(cx, 0.85, 1.05)
		mk.cylinder(base, 0.12, 1.5, 6, Color("e3a33b"))
		mk.box(base + Vector3(0, 1.6, 0), Vector3(0.3, 0.22, 0.3), Color("e3a33b"))
		BoatKit.line(mk, base + Vector3(0, 1.5, 0), base + Vector3(1.6, 1.9, -0.9), 0.08, Color("e3a33b"))
		BoatKit.line(mk, base + Vector3(1.6, 1.9, -0.9), base + Vector3(1.6, 1.0, -0.9), 0.015, Color(0.2, 0.2, 0.2))
	# the bridge and accommodation at the stern
	var tower := PackedVector2Array([Vector2(-7.6, -1.05), Vector2(-5.6, -1.05), Vector2(-5.6, 1.05), Vector2(-7.6, 1.05)])
	_walls(mk, tower, 0.85, 2.5, Color("f4f3ef"))
	_cap(mk, tower, 2.5, Color("dfe6ea"))
	mk.box_faces(Vector3(-6.6, 2.55, 0), Vector3(2.2, 0.08, 2.5), Color("f4f3ef"), MeshKit.TOP | MeshKit.FRONT | MeshKit.BACK | MeshKit.LEFT | MeshKit.RIGHT)
	mk.window_row(Vector3(-5.59, 2.25, 0), Vector3.RIGHT, 1.8, 6, 0.18, 0.14, Palette.GLASS, false)
	for fl in 3:
		_cabins(mk, -7.4, -5.8, 1.05, 1.2 + fl * 0.4, 3)
	_wings(mk, -5.85, 2.55, 1.35)
	_radar(mk, Vector3(-6.4, 2.59, 0), 0.7)
	_funnel(mk, Vector3(-7.1, 2.59, 0), 0.75, 0.28, Color("1b1b1f"), Color("c8553d"))
	# a free-fall lifeboat on its ramp off the stern, and a mast at the bow
	mk.push(Transform3D(Basis(Vector3.BACK, 0.35), Vector3(-8.3, 1.5, 0)))
	_lifeboat(mk, Vector3.ZERO)
	mk.pop()
	mk.cylinder(Vector3(7.2, 0.95, 0), 0.04, 1.0, 5, Color(0.95, 0.95, 0.93))
	mk.box(Vector3(7.2, 2.0, 0), Vector3(0.06, 0.06, 0.06), Color(1, 0.9, 0.6), null, false, NIGHT_GLOW)
	mk.box(Vector3(-5.7, 2.75, 0), Vector3(0.06, 0.06, 0.06), Color(1, 0.9, 0.6), null, false, NIGHT_GLOW)


func _ferry(mk: MeshKit) -> void:
	_hull(mk, 11.0, 2.2, 0.75, Color("f4f3ef"), Color("2f8f83"), Color("c99a6b"))
	_cabins(mk, -4.8, 3.2, 1.1, 0.5, 10)
	var deck := PackedVector2Array([Vector2(-4.4, -1.0), Vector2(2.4, -1.0), Vector2(3.2, 0), Vector2(2.4, 1.0), Vector2(-4.4, 1.0)])
	_walls(mk, deck, 0.75, 1.3, Color("fbfaf6"))
	_cap(mk, deck, 1.3, Color("dfe6ea"))
	_cabins(mk, -4.0, 2.2, 1.0, 1.02, 12)
	_deck_rail(mk, deck, 1.3)
	# a green band round the passenger deck and a funnel in the line's colours
	mk.box_faces(Vector3(-1.0, 1.27, 0), Vector3(6.9, 0.06, 2.02), Color("2f8f83"), MeshKit.LEFT | MeshKit.RIGHT | MeshKit.BACK)
	var bridge := PackedVector2Array([Vector2(0.4, -0.7), Vector2(1.8, -0.7), Vector2(2.2, 0), Vector2(1.8, 0.7), Vector2(0.4, 0.7)])
	_walls(mk, bridge, 1.3, 1.7, Color("fbfaf6"))
	_cap(mk, bridge, 1.7, Color("dfe6ea"))
	mk.window_row(Vector3(1.6, 1.52, 0), Vector3.RIGHT, 1.2, 4, 0.18, 0.12, Palette.GLASS, false)
	_wings(mk, 1.5, 1.6, 1.15)
	_radar(mk, Vector3(1.0, 1.7, 0), 0.5)
	_funnel(mk, Vector3(-2.6, 1.3, 0), 0.8, 0.3, Color("2f8f83"), Color(0.97, 0.97, 0.95))
	# life-raft canisters along the rails, and the car deck's ramp at the stern
	for sz: float in [-1.0, 1.0]:
		for k in 4:
			BoatKit.tube(mk, Vector3(-3.8 + k * 0.5, 1.38, sz * 0.82), Vector3.RIGHT, 0.3, 0.08, 0.08, 6, Color(0.97, 0.97, 0.95))
	mk.quad(Vector3(-5.51, 0.2, -0.7), Vector3(-5.51, 0.2, 0.7), Vector3(-5.51, 0.68, 0.7), Vector3(-5.51, 0.68, -0.7), Vector3.LEFT, Color(0.22, 0.24, 0.27))
