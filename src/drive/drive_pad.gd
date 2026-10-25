class_name DrivePad
extends Control
## Touch controls for Drive mode: a thumb wheel anywhere low on the left to
## steer (slide sideways), and two pedals low on the right, accelerator and
## brake (hold the brake at a standstill to back up). Anywhere else a drag
## turns and tilts the camera and a pinch zooms it. Several fingers at once.
## A mouse works it too, for trying it on a PC.

## what the pad asks of the car: -1 .. 1 each
var steer := 0.0
var throttle := 0.0
## controls the pad must leave alone (the buttons over it)
var keep_clear: Array[Control] = []
## camera drags and pinches since the camera last took them
var look := Vector2.ZERO
var zoom := 1.0
var accent := Color("ff7a6b")

# finger index -> "steer" | "gas" | "brake" | "look"
var _fingers := {}
# where each camera finger was last
var _look_at := {}
var _steer_from := Vector2.ZERO
var _steer_at := Vector2.ZERO
var _gas := false
var _brake := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func reset() -> void:
	_fingers.clear()
	_look_at.clear()
	look = Vector2.ZERO
	zoom = 1.0
	_gas = false
	_brake = false
	steer = 0.0
	throttle = 0.0
	queue_redraw()


## How big things are drawn: the layout was made for a 720 px tall screen.
func _k() -> float:
	return clampf(size.y / 720.0, 0.6, 2.0)


## The side margin everything keeps inside, landscape only (3% each side).
func _m() -> float:
	return size.x * 0.03 if size.x > size.y else 0.0


func _gas_rect() -> Rect2:
	var k := _k()
	return Rect2(size.x - _m() - 130.0 * k, size.y - 250.0 * k, 110.0 * k, 210.0 * k)


func _brake_rect() -> Rect2:
	var k := _k()
	return Rect2(size.x - _m() - 270.0 * k, size.y - 170.0 * k, 120.0 * k, 130.0 * k)


func _wheel_home() -> Vector2:
	var k := _k()
	return Vector2(_m() + 110.0 * k, size.y - 120.0 * k)


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	var idx := -1
	var pos := Vector2.ZERO
	var pressed := false
	var dragging := false
	if event is InputEventScreenTouch:
		idx = event.index
		pos = event.position
		pressed = event.pressed
	elif event is InputEventScreenDrag:
		idx = event.index
		pos = event.position
		dragging = true
	elif event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION and event.button_index == MOUSE_BUTTON_LEFT:
		idx = 100
		pos = event.position
		pressed = event.pressed
	elif event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION and _fingers.has(100):
		idx = 100
		pos = event.position
		dragging = true
	else:
		return
	pos = make_input_local(event).position
	if dragging:
		if not _fingers.has(idx):
			return
		if _fingers[idx] == "steer":
			_steer_at = pos
		elif _fingers[idx] == "look":
			_drag_look(idx, pos)
		else:
			_fingers[idx] = _pedal_at(pos)
		_update()
		get_viewport().set_input_as_handled()
	elif pressed:
		for c in keep_clear:
			if c.is_visible_in_tree() and c.get_global_rect().has_point(pos):
				return
		var low := pos.y > size.y * 0.42
		if low and pos.x < size.x * 0.42:
			_fingers[idx] = "steer"
			_steer_from = pos
			_steer_at = pos
		elif low and pos.x > size.x * 0.58:
			_fingers[idx] = _pedal_at(pos)
		else:
			_fingers[idx] = "look"
			_look_at[idx] = pos
		_update()
		get_viewport().set_input_as_handled()
	elif _fingers.has(idx):
		_fingers.erase(idx)
		_look_at.erase(idx)
		_update()
		get_viewport().set_input_as_handled()


## One camera finger turns and tilts; two pinch to zoom (and pan together).
func _drag_look(idx: int, pos: Vector2) -> void:
	if _look_at.size() >= 2:
		var keys := _look_at.keys()
		var other: Vector2 = _look_at[keys[1] if keys[0] == idx else keys[0]]
		var before: float = (_look_at[idx] as Vector2).distance_to(other)
		var now := pos.distance_to(other)
		if before > 1.0 and now > 1.0:
			zoom *= before / now
		look += (pos - _look_at[idx]) * 0.5
	else:
		look += pos - _look_at[idx]
	_look_at[idx] = pos


## Which pedal a finger on the right side means: the one under it, or the
## nearer one (a thumb sliding off the accelerator keeps it down).
func _pedal_at(p: Vector2) -> String:
	var g := _gas_rect()
	var b := _brake_rect()
	if g.grow(12).has_point(p):
		return "gas"
	if b.grow(12).has_point(p):
		return "brake"
	return "gas" if p.distance_to(g.get_center()) < p.distance_to(b.get_center()) else "brake"


func _update() -> void:
	_gas = false
	_brake = false
	var steering := false
	for v in _fingers.values():
		if v == "gas":
			_gas = true
		elif v == "brake":
			_brake = true
		elif v == "steer":
			steering = true
	throttle = (1.0 if _gas else 0.0) - (1.0 if _brake else 0.0)
	if _brake and _gas:
		throttle = -1.0
	steer = clampf((_steer_at.x - _steer_from.x) / (85.0 * _k()), -1.0, 1.0) if steering else 0.0
	queue_redraw()


func _glass(r: Rect2, rad: float, col: Color, border := Color(1, 1, 1, 0.55)) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(int(rad))
	sb.corner_detail = 6
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.anti_aliasing = true
	draw_style_box(sb, r)


func _draw() -> void:
	var k := _k()
	var glass := Color(1, 1, 1, 0.22)
	var ink := Color(1, 1, 1, 0.92)
	# the steering wheel: a ring where the thumb went down, or its resting spot
	var steering := _fingers.values().has("steer")
	var c := _steer_from if steering else _wheel_home()
	var r := 70.0 * k
	_glass(Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), r, glass)
	# arrows either side, and the knob following the thumb sideways
	for sx in [-1.0, 1.0]:
		var tip: Vector2 = c + Vector2(sx * r * 0.78, 0)
		var col := ink if (steer * sx) > 0.2 else Color(1, 1, 1, 0.55)
		draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-sx * 13 * k, -11 * k), tip + Vector2(-sx * 13 * k, 11 * k)]), col)
	var knob := c + Vector2(steer * r * 0.55, 0)
	var kr := 30.0 * k
	_glass(Rect2(knob - Vector2(kr, kr), Vector2(kr, kr) * 2.0), kr, accent if steering else Color(1, 1, 1, 0.6), Color(1, 1, 1, 0.9))
	# accelerator: tall, with a chevron pointing on
	var g := _gas_rect()
	_glass(g, 26.0 * k, accent if _gas else glass)
	var gc := g.get_center()
	for i in 2:
		var y := gc.y - 18.0 * k + i * 22.0 * k
		draw_polyline(PackedVector2Array([Vector2(gc.x - 22 * k, y + 12 * k), Vector2(gc.x, y - 8 * k), Vector2(gc.x + 22 * k, y + 12 * k)]), ink, 6.0 * k, true)
	# brake: shorter and wider, with a bar
	var b := _brake_rect()
	_glass(b, 26.0 * k, Color(0.25, 0.3, 0.4, 0.75) if _brake else glass)
	var bc := b.get_center()
	draw_line(bc - Vector2(26 * k, 0), bc + Vector2(26 * k, 0), ink, 9.0 * k, true)
