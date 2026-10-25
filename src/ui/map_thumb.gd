class_name MapThumb
extends Control
## A little painted map of a landscape kind for the map picker: river valley,
## coast, lake country or island, drawn as vectors and clipped to a rounded
## card so it stays sharp at any size.

const LAND := Color("8fc46a")
const LAND_HI := Color("a9d77f")
const WATER := Color("4fa3d9")
const DEEP := Color("2f7fbf")
const SAND := Color("efdca0")
const TREE := Color("3f8f4a")
const ROOF := Color("e8735c")

var kind := "river"
var radius := 16.0


func _init(k := "river") -> void:
	kind = k
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _card() -> PackedVector2Array:
	var pts := PackedVector2Array()
	var r := minf(radius, minf(size.x, size.y) * 0.5)
	var corners := [Vector2(size.x - r, r), Vector2(size.x - r, size.y - r), Vector2(r, size.y - r), Vector2(r, r)]
	for ci in 4:
		for k in 7:
			var a := -PI * 0.5 + (ci + k / 6.0) * PI * 0.5
			pts.append(corners[ci] + Vector2(cos(a), sin(a)) * r)
	return pts


## Fills `poly` cut to the card's rounded outline.
func _fill(poly: PackedVector2Array, col: Color) -> void:
	for p in Geometry2D.intersect_polygons(poly, _card()):
		if p.size() >= 3:
			draw_colored_polygon(p, col)


func _blob(c: Vector2, r: Vector2, wob: float, seed_i: int, n := 28) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * i / n
		var k := 1.0 + wob * sin(a * 3.0 + seed_i) * 0.6 + wob * sin(a * 5.0 + seed_i * 2.0) * 0.4
		pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y) * k)
	return pts


func _band(line: PackedVector2Array, w: float, col: Color) -> void:
	for p in Geometry2D.offset_polyline(line, w * 0.5, Geometry2D.JOIN_ROUND, Geometry2D.END_ROUND):
		_fill(p, col)


func _draw() -> void:
	var s := size
	if s.x < 4.0 or s.y < 4.0:
		return
	var P := func(x: float, y: float) -> Vector2: return Vector2(x * s.x, y * s.y)
	if kind == "island":
		draw_colored_polygon(_card(), DEEP)
		_fill(_blob(P.call(0.5, 0.52), s * Vector2(0.4, 0.36), 0.14, 3), WATER)
		_fill(_blob(P.call(0.5, 0.52), s * Vector2(0.32, 0.28), 0.16, 1), SAND)
		_fill(_blob(P.call(0.5, 0.5), s * Vector2(0.29, 0.25), 0.16, 1), LAND)
		_fill(_blob(P.call(0.46, 0.45), s * Vector2(0.12, 0.09), 0.2, 4), LAND_HI)
	else:
		draw_colored_polygon(_card(), LAND)
		_fill(_blob(P.call(0.28, 0.3), s * Vector2(0.22, 0.14), 0.2, 2), LAND_HI)
		_fill(_blob(P.call(0.78, 0.78), s * Vector2(0.18, 0.12), 0.2, 5), LAND_HI)
	match kind:
		"river":
			var line := PackedVector2Array()
			for i in 13:
				var t := i / 12.0
				line.append(P.call(-0.05 + t * 1.1, 0.55 + sin(t * 5.2) * 0.13 - t * 0.1))
			_band(line, s.y * 0.13, WATER)
			_band(line, s.y * 0.05, Color(WATER.lightened(0.18), 0.7))
		"coast":
			var sea := PackedVector2Array([P.call(1.1, -0.1)])
			for i in 15:
				var t := i / 14.0
				sea.append(P.call(0.62 + sin(t * 7.0) * 0.05 + t * 0.12, -0.05 + t * 1.1))
			sea.append(P.call(1.1, 1.1))
			var beach := Geometry2D.offset_polygon(sea, s.x * 0.035)
			for b in beach:
				_fill(b, SAND)
			_fill(sea, WATER)
			_fill(Geometry2D.offset_polygon(sea, -s.x * 0.08)[0] if not Geometry2D.offset_polygon(sea, -s.x * 0.08).is_empty() else sea, DEEP)
			# an estuary winding in from the sea
			var line := PackedVector2Array()
			for i in 9:
				var t := i / 8.0
				line.append(P.call(0.7 - t * 0.75, 0.62 + sin(t * 4.0) * 0.08))
			_band(line, s.y * 0.08, WATER)
		"lakes":
			_fill(_blob(P.call(0.32, 0.42), s * Vector2(0.2, 0.17), 0.2, 1), WATER)
			_fill(_blob(P.call(0.72, 0.62), s * Vector2(0.15, 0.13), 0.24, 6), WATER)
			_fill(_blob(P.call(0.62, 0.22), s * Vector2(0.08, 0.06), 0.2, 9), WATER)
	# a sprinkle of trees and a few roofs
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	var card := _card()
	for i in 16:
		var p := P.call(rng.randf_range(0.08, 0.92), rng.randf_range(0.1, 0.9)) as Vector2
		if not Geometry2D.is_point_in_polygon(p, card) or _wet(p):
			continue
		var tr := s.y * rng.randf_range(0.03, 0.045)
		_disc(p, tr, TREE)
	for i in 6:
		var p := P.call(rng.randf_range(0.15, 0.85), rng.randf_range(0.2, 0.8)) as Vector2
		if _wet(p):
			continue
		var w := s.y * 0.06
		draw_rect(Rect2(p - Vector2(w, w) * 0.5, Vector2(w, w)), ROOF)


## Rough test for where water was drawn, so trees and roofs stay on land.
func _wet(p: Vector2) -> bool:
	var u := Vector2(p.x / size.x, p.y / size.y)
	match kind:
		"river":
			return absf(u.y - (0.55 + sin((u.x + 0.05) / 1.1 * 5.2) * 0.13 - (u.x + 0.05) / 1.1 * 0.1)) < 0.12
		"coast":
			return u.x > 0.55 or absf(u.y - 0.64) < 0.1
		"lakes":
			return u.distance_to(Vector2(0.32, 0.42)) < 0.24 or u.distance_to(Vector2(0.72, 0.62)) < 0.19 or u.distance_to(Vector2(0.62, 0.22)) < 0.1
		"island":
			return Vector2((u.x - 0.5) / 0.3, (u.y - 0.5) / 0.26).length() > 0.85
	return false


func _disc(c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var a := TAU * i / 10.0
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	draw_colored_polygon(pts, col)
