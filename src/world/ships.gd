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
	for build: Callable in [_cruise, _freighter, _ferry]:
		var mk := MeshKit.new(_kinds.size() + 40)
		build.call(mk)
		_kinds.append([mk.commit(material), mk.commit_shadow(Palette.shadow_material())])


func _process(delta: float) -> void:
	_wait -= delta
	if _wait <= 0.0:
		_wait = _rng.randf_range(WAIT.x, WAIT.y)
		if _ships.size() < 2:
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
	var r := Land.HALF + OFFSHORE + _rng.randf() * 12.0
	var side := _rng.randf() * TAU
	var mid := Vector2.from_angle(side) * r
	var dir := Vector2.from_angle(side + PI * 0.5) * (1.0 if _rng.randf() < 0.5 else -1.0)
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

## A hull from a top-down outline (bow towards +X): sides from below the
## waterline up to `top`, a deck on top, and a painted stripe at the waterline.
func _hull(mk: MeshKit, outline: PackedVector2Array, top: float, col: Color, stripe: Color, deck: Color) -> void:
	_walls(mk, outline, -0.25, 0.12, stripe)
	_walls(mk, outline, 0.12, top, col)
	_cap(mk, outline, top, deck)


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


static func _ship_outline(length: float, beam: float, bow: float) -> PackedVector2Array:
	var h := length * 0.5
	var w := beam * 0.5
	return PackedVector2Array([Vector2(-h, -w), Vector2(h - bow, -w), Vector2(h - bow * 0.35, -w * 0.6), Vector2(h, 0),
		Vector2(h - bow * 0.35, w * 0.6), Vector2(h - bow, w), Vector2(-h, w), Vector2(-h - 0.15, 0)])


## A row of lit cabin windows down both sides of a deck.
func _cabins(mk: MeshKit, x0: float, x1: float, half_beam: float, y: float, count: int) -> void:
	for side: float in [-1.0, 1.0]:
		mk.window_row(Vector3((x0 + x1) * 0.5, y, side * (half_beam + 0.005)), Vector3(0, 0, side), x1 - x0, count, 0.16, 0.12, Palette.GLASS, false)


# ------------------------------------------------------------------ ships

func _cruise(mk: MeshKit) -> void:
	var hull := _ship_outline(16.0, 2.4, 3.0)
	_hull(mk, hull, 1.0, Color("f4f3ef"), Color("1f3550"), Color("c99a6b"))
	_cabins(mk, -7.2, 5.0, 1.2, 0.68, 22)
	var white := Color("fbfaf6")
	# decks stepping back towards the stern, each a little narrower
	var decks := [[-7.0, 4.4, 1.05], [-6.6, 3.6, 0.98], [-6.0, 2.6, 0.9], [-5.2, 1.4, 0.8]]
	var y := 1.0
	for d in decks:
		var x0: float = d[0]
		var x1: float = d[1]
		var hw: float = d[2]
		var deck := PackedVector2Array([Vector2(x0, -hw), Vector2(x1 - 0.5, -hw), Vector2(x1, 0), Vector2(x1 - 0.5, hw), Vector2(x0, hw)])
		_walls(mk, deck, y, y + 0.42, white)
		_cap(mk, deck, y + 0.42, Color("dfe6ea"))
		_cabins(mk, x0 + 0.3, x1 - 0.7, hw, y + 0.22, int((x1 - x0) * 1.6))
		y += 0.42
	# a blue pool on the sun deck, the bridge's windows, and the funnel
	mk.box_faces(Vector3(-1.5, y + 0.01, 0), Vector3(1.4, 0.02, 0.7), Color("49b6d6"), MeshKit.TOP)
	mk.box_faces(Vector3(3.7, 2.02, 0), Vector3(0.02, 0.16, 1.6), Color(0.2, 0.28, 0.36), MeshKit.FRONT | MeshKit.RIGHT)
	mk.rbox(Vector3(-4.2, y + 0.45, 0), Vector3(1.2, 0.9, 0.7), 0.25, Color("1f3550"), Color("c8553d"))
	# lifeboats in a row along each side
	for side: float in [-1.0, 1.0]:
		for k in 5:
			mk.rbox(Vector3(-4.8 + k * 1.9, 1.2, side * 1.12), Vector3(0.7, 0.18, 0.22), 0.08, Color("f08a24"))
	mk.box(Vector3(0.3, y + 0.75, 0), Vector3(0.06, 0.06, 0.06), Color(1, 0.9, 0.6), null, false, NIGHT_GLOW)


func _freighter(mk: MeshKit) -> void:
	var hull := _ship_outline(17.0, 2.5, 2.4)
	_hull(mk, hull, 0.85, Color("2f4f7a"), Color("9a2f2a"), Color("6d6f73"))
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
	# the bridge and accommodation at the stern
	var tower := PackedVector2Array([Vector2(-7.6, -1.05), Vector2(-5.6, -1.05), Vector2(-5.6, 1.05), Vector2(-7.6, 1.05)])
	_walls(mk, tower, 0.85, 2.5, Color("f4f3ef"))
	_cap(mk, tower, 2.5, Color("dfe6ea"))
	mk.box_faces(Vector3(-6.6, 2.55, 0), Vector3(2.2, 0.08, 2.5), Color("f4f3ef"), MeshKit.TOP | MeshKit.FRONT | MeshKit.BACK | MeshKit.LEFT | MeshKit.RIGHT)
	mk.window_row(Vector3(-5.59, 2.25, 0), Vector3.RIGHT, 1.8, 6, 0.18, 0.14, Palette.GLASS, false)
	for fl in 3:
		_cabins(mk, -7.4, -5.8, 1.05, 1.2 + fl * 0.4, 3)
	mk.box(Vector3(-7.0, 2.95, 0), Vector3(0.5, 0.7, 0.55), Color("1b1b1f"), Color("c8553d"))
	mk.box(Vector3(-5.7, 2.75, 0), Vector3(0.06, 0.06, 0.06), Color(1, 0.9, 0.6), null, false, NIGHT_GLOW)


func _ferry(mk: MeshKit) -> void:
	var hull := _ship_outline(11.0, 2.2, 2.0)
	_hull(mk, hull, 0.75, Color("f4f3ef"), Color("2f8f83"), Color("c99a6b"))
	_cabins(mk, -4.8, 3.2, 1.1, 0.5, 10)
	var deck := PackedVector2Array([Vector2(-4.4, -1.0), Vector2(2.4, -1.0), Vector2(3.2, 0), Vector2(2.4, 1.0), Vector2(-4.4, 1.0)])
	_walls(mk, deck, 0.75, 1.3, Color("fbfaf6"))
	_cap(mk, deck, 1.3, Color("dfe6ea"))
	_cabins(mk, -4.0, 2.2, 1.0, 1.02, 12)
	# a green band round the passenger deck and a funnel in the line's colours
	mk.box_faces(Vector3(-1.0, 1.27, 0), Vector3(6.9, 0.06, 2.02), Color("2f8f83"), MeshKit.LEFT | MeshKit.RIGHT | MeshKit.BACK)
	var bridge := PackedVector2Array([Vector2(0.4, -0.7), Vector2(1.8, -0.7), Vector2(2.2, 0), Vector2(1.8, 0.7), Vector2(0.4, 0.7)])
	_walls(mk, bridge, 1.3, 1.7, Color("fbfaf6"))
	_cap(mk, bridge, 1.7, Color("dfe6ea"))
	mk.window_row(Vector3(1.6, 1.52, 0), Vector3.RIGHT, 1.2, 4, 0.18, 0.12, Palette.GLASS, false)
	mk.rbox(Vector3(-2.6, 1.7, 0), Vector3(0.8, 0.8, 0.5), 0.2, Color("2f8f83"), Color("1b1b1f"))
