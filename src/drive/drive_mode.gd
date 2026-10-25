class_name DriveMode
extends CanvasLayer
## Drive mode: take a little car out on your own streets. The building HUD
## steps aside for a chase camera close behind the car, or the driver's seat
## (toggle), with touch pedals and a thumb wheel on phones and WASD / arrows
## on a PC. The orbit camera hands its camera over while driving and gets it
## back, looking at where the car stopped, on the way out.

signal toggled(on: bool)

var island: IslandWorld
var hud: Hud
var active := false
var first_person := false
var car: DriveCar

var _ui: Control
var _catch: Control
var _pad: DrivePad
var _exit_btn: Button
var _view_btn: Button
var _speed: Label
var _hint: Label
var _engine: AudioStreamPlayer
# the orbit camera's lens, put back on the way out
var _fov := 40.0
var _near := 0.3
# the chase camera, eased after the car
var _cam_yaw := 0.0
var _cam_pos := Vector3.ZERO
var _cam_fresh := true
var _shake := 0.0

## chase camera: how far behind, how high, where it looks ahead of the car
const CHASE_BACK := 1.35
const CHASE_UP := 0.5
const CHASE_LOOK := 0.7
## the driver's eye, in the car's own frame
const EYE := Vector3(0.0, 0.305, 0.15)
## how far the sun's shadows reach while driving: as far as when looking down
## on the town close up, so they never thin out at street level
const SHADOW_REACH := 85.0


func _ready() -> void:
	layer = 5
	process_priority = 100
	_catch = Control.new()
	_catch.set_anchors_preset(Control.PRESET_FULL_RECT)
	_catch.mouse_filter = Control.MOUSE_FILTER_STOP
	_catch.visible = false
	add_child(_catch)
	_ui = Control.new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.visible = false
	if hud and hud._root:
		_ui.theme = hud._root.theme
	add_child(_ui)
	_pad = DrivePad.new()
	_ui.add_child(_pad)
	# the side margins every control keeps inside, landscape only
	var inner := Control.new()
	inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(inner)
	get_viewport().size_changed.connect(func(): _margins(inner))
	_margins(inner)
	_exit_btn = _button("close")
	_exit_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_exit_btn.offset_left = -76
	_exit_btn.offset_right = -18
	_exit_btn.offset_top = 18
	_exit_btn.offset_bottom = 76
	_exit_btn.pressed.connect(func(): set_active(false))
	inner.add_child(_exit_btn)
	_view_btn = _button("eye")
	_view_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_view_btn.offset_left = -146
	_view_btn.offset_right = -88
	_view_btn.offset_top = 18
	_view_btn.offset_bottom = 76
	_view_btn.pressed.connect(toggle_view)
	inner.add_child(_view_btn)
	_pad.keep_clear = [_exit_btn, _view_btn]
	# the speedometer, top left
	var pill := PanelContainer.new()
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.position = Vector2(18, 18)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.075, 0.09, 0.125, 0.82)
	sb.set_corner_radius_all(26)
	sb.border_color = Color(1, 1, 1, 0.16)
	sb.set_border_width_all(1)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	pill.add_theme_stylebox_override("panel", sb)
	_speed = Label.new()
	_speed.add_theme_font_size_override("font_size", 30)
	_speed.add_theme_color_override("font_color", Color("f5f7fb"))
	if hud and hud.font_bold:
		_speed.add_theme_font_override("font", hud.font_bold)
	_speed.text = "0 km/h"
	pill.add_child(_speed)
	inner.add_child(pill)
	_hint = Label.new()
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hint.offset_top = -64
	_hint.offset_bottom = -24
	_hint.add_theme_font_size_override("font_size", 20)
	_hint.add_theme_color_override("font_color", Color.WHITE)
	_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.45))
	_hint.add_theme_constant_override("outline_size", 6)
	inner.add_child(_hint)
	_engine = AudioStreamPlayer.new()
	_engine.stream = _engine_loop()
	_engine.volume_db = -60.0
	add_child(_engine)


func _margins(c: Control) -> void:
	var size := get_viewport().get_visible_rect().size
	var m := 0.03 if size.x > size.y else 0.0
	c.anchor_left = m
	c.anchor_right = 1.0 - m


func _button(icon: String) -> Button:
	if hud:
		return hud._glass_button(58, icon)
	var b := Button.new()
	b.custom_minimum_size = Vector2(58, 58)
	return b


## Gets in the car (on the street nearest the middle of the view) or out again.
func set_active(on: bool) -> void:
	if on == active:
		return
	if on:
		if island.streets.streets.is_empty():
			if hud:
				hud.show_toast("Lay a street first, then take a drive", "info")
			return
		_enter()
	else:
		_leave()
	Sfx.play("click")
	toggled.emit(on)


func _enter() -> void:
	var rig := island.rig
	if car == null:
		car = DriveCar.new()
		car.land = island.land
		car.streets = island.streets
		car.town = island.town
		car.material = island.city_mat
		island.add_child(car)
	car.visible = true
	car.process_mode = Node.PROCESS_MODE_INHERIT
	# the camera faces along the street the way the view looks
	var look := rig.yaw + PI
	if not car.place_on_street(Vector2(rig.target.x, rig.target.z), look):
		return
	active = true
	if island.brush != "":
		island.set_brush(island.brush)
	_fov = rig.cam.fov
	_near = rig.cam.near
	rig.set_process(false)
	rig.cam.near = 0.03
	_cam_fresh = true
	_cam_yaw = car.heading
	_pad.reset()
	_pad.visible = DisplayServer.is_touchscreen_available()
	_catch.visible = true
	_ui.visible = true
	_ui.modulate.a = 0.0
	create_tween().tween_property(_ui, "modulate:a", 1.0, 0.3)
	_hint.text = "" if _pad.visible else "W A S D or arrows to drive  ·  C to change view  ·  Esc to get out"
	_hint.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(5.0)
	tw.tween_property(_hint, "modulate:a", 0.0, 0.8)
	if hud:
		hud.set_drive(true)
	if Game.settings.get("sfx", true):
		_engine.play()
	_update_camera(1.0)


func _leave() -> void:
	active = false
	var rig := island.rig
	_catch.visible = false
	_ui.visible = false
	_engine.stop()
	if car:
		car.visible = false
		car.process_mode = Node.PROCESS_MODE_DISABLED
		car.speed = 0.0
		# the orbit view comes back looking at the car from behind, close in,
		# then eases out to an everyday distance
		rig.focus(car.position)
		rig.target = Vector3(car.position.x, 0, car.position.z)
		rig.yaw = car.heading + PI
		rig._t_yaw = rig.yaw
		rig.dist = 10.0
		rig._t_dist = 32.0
		rig._t_tilt = 0.0
	rig.cam.fov = _fov
	rig.cam.near = _near
	rig.set_process(true)
	if hud:
		hud.set_drive(false)


func toggle_view() -> void:
	first_person = not first_person
	_cam_fresh = true
	Sfx.play("click", 1.3)


func _process(delta: float) -> void:
	if not active:
		return
	_keyboard()
	car.night = island.night
	car.input_steer = clampf(car.input_steer, -1.0, 1.0)
	_update_camera(delta)
	if car.bumped > 0.4:
		_shake = minf(car.bumped * 0.05, 0.08)
		Sfx.play("bulldoze", 1.6, -8.0)
	_speed.text = "%d km/h" % car.kmh()
	# the engine note rises with the speed and the throttle
	var load := absf(car.input_throttle)
	var rev := absf(car.speed) / DriveCar.TOP
	_engine.pitch_scale = lerpf(_engine.pitch_scale, 0.75 + rev * 1.25 + load * 0.15, 1.0 - exp(-delta * 6.0))
	_engine.volume_db = lerpf(_engine.volume_db, -22.0 + load * 5.0 + rev * 4.0, 1.0 - exp(-delta * 6.0))
	# the island's view keeps its sense of where the eye is (gulls, clouds)
	var rig := island.rig
	rig.target = car.position
	rig.dist = 12.0
	# street-level shadows reach as far as close-up ones from above
	island.sun.directional_shadow_max_distance = SHADOW_REACH
	var k := clampf(World.SHADOW_NEAR_REACH / SHADOW_REACH, 0.3, 1.0)
	island.sun.shadow_blur = World.SHADOW_BLUR * k
	island.sun.shadow_normal_bias = World.SHADOW_NORMAL_BIAS * maxf(k, 0.5)


## The keyboard drives on a PC (and adds to the touch pad where both exist).
func _keyboard() -> void:
	var th := _pad.throttle
	var st := _pad.steer
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		th += 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_SPACE):
		th -= 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		st -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		st += 1.0
	car.input_throttle = clampf(th, -1.0, 1.0)
	car.input_steer = clampf(st, -1.0, 1.0)


func _update_camera(delta: float) -> void:
	var cam := island.rig.cam
	var xf := car.global_transform
	var fwd := Vector3(sin(car.heading), 0, cos(car.heading))
	var speed_k := clampf(absf(car.speed) / DriveCar.TOP, 0.0, 1.0)
	_shake = maxf(_shake - delta * 0.3, 0.0)
	var jolt := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * _shake
	if first_person:
		cam.fov = 70.0 + speed_k * 8.0
		var eye := xf * EYE
		cam.global_position = eye + jolt
		# the eye leans with the car's pitch but only a little with its roll
		cam.look_at(xf * (EYE + Vector3(0, -0.01, 3.0)), (Vector3.UP * 2.0 + xf.basis.y).normalized())
		return
	cam.fov = 60.0 + speed_k * 8.0
	# the camera swings round behind the car with a little lag (not when backing up)
	var k := 1.0 if _cam_fresh else 1.0 - exp(-delta * (4.0 if car.speed >= -0.1 else 1.0))
	_cam_yaw = lerp_angle(_cam_yaw, car.heading, k)
	var back := Vector3(sin(_cam_yaw), 0, cos(_cam_yaw))
	var focus := car.position + Vector3(0, 0.16, 0)
	var dist := CHASE_BACK * (1.0 + speed_k * 0.15)
	# pulled in ahead of a wall between the car and the camera
	var steps := 8
	for i in range(1, steps + 1):
		var q := focus - back * dist * float(i) / steps
		if car.blocked(Vector2(q.x, q.z)) and not car.land.height_at(q.x, q.z) < -0.05:
			dist = maxf(dist * float(i - 1) / steps - 0.05, 0.35)
			break
	var want := focus - back * dist + Vector3(0, CHASE_UP * (0.6 + 0.4 * dist / CHASE_BACK), 0)
	want.y = maxf(want.y, car.surface(want, car.position.y) + 0.12)
	_cam_pos = want if _cam_fresh else _cam_pos.lerp(want, 1.0 - exp(-delta * 10.0))
	_cam_fresh = false
	cam.global_position = _cam_pos + jolt
	cam.look_at(focus + fwd * CHASE_LOOK * (0.5 + 0.5 * speed_k), Vector3.UP)


func _input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				set_active(false)
				get_viewport().set_input_as_handled()
			KEY_C, KEY_V:
				toggle_view()
				get_viewport().set_input_as_handled()
			KEY_H:
				# photo mode stays out of the way while driving
				get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	# the Android back gesture gets out of the car
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and active:
		set_active(false)


## A small petrol engine's thrum, looped: the pitch follows the revs.
func _engine_loop() -> AudioStreamWAV:
	var rate := 22050
	var n := rate
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var lp := 0.0
	for i in n:
		var t := float(i) / rate
		# whole cycles over the loop so it joins without a click
		var f := 46.0
		var ph := TAU * f * t
		var v := sin(ph) * 0.5 + sin(ph * 2.0) * 0.28 + sin(ph * 3.0) * 0.12 + sin(ph * 0.5) * 0.2
		# firing pulses and a little exhaust noise
		v *= 0.75 + 0.25 * sin(ph * 4.0)
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.08)
		v += lp * 0.3
		data.encode_s16(i * 2, int(clampf(v * 0.6, -1.0, 1.0) * 30000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = rate
	s.data = data
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_begin = 0
	s.loop_end = n
	return s
