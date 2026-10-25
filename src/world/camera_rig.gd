class_name CameraRig
extends Node3D
## Smooth orbit camera: pan, pinch-zoom, twist-rotate. Tilts flatter as you zoom in.

var target := Vector3.ZERO
var yaw := deg_to_rad(35.0)
var dist := 38.0
var _t_target := Vector3.ZERO
var _t_yaw := deg_to_rad(35.0)
var _t_dist := 38.0
## how far the player has tilted the view from the zoom's own tilt
var tilt := 0.0
var _t_tilt := 0.0
var cam: Camera3D
var idle_spin := false
## Ground height under a point.
var ground_fn: Callable
## How far from the middle the view can pan.
var limit := 64.0
# the ground height the view follows and the lowest the camera may go, both
# eased so gliding over hills and valleys never jolts (NAN: not yet known)
var _ground := NAN
var _floor := NAN

const MIN_D := 9.0
## how far the player may tilt the view from the zoom's own tilt: up towards
## the horizon (negative) and down towards straight below
const MIN_TILT := deg_to_rad(-58.0)
const MAX_TILT := deg_to_rad(15.0)
const MAX_D := 368.0
## past this the camera only pulls back, looking down a little more steeply
const FAR_D := 92.0
## how far out the camera went before it could pull back twice as far (João,
## 2026-10-25): the views budgeted at TriBudget.FAR_BUDGET
const OLD_MAX_D := 184.0


func _ready() -> void:
	cam = Camera3D.new()
	cam.fov = 40.0
	cam.near = 0.3
	cam.far = 12000.0
	add_child(cam)
	cam.make_current()


func pitch_for(d: float) -> float:
	var t := clampf((d - MIN_D) / (FAR_D - MIN_D), 0.0, 1.0)
	var far := clampf((d - FAR_D) / (OLD_MAX_D - FAR_D), 0.0, 1.0)
	var further := clampf((d - OLD_MAX_D) / (MAX_D - OLD_MAX_D), 0.0, 1.0)
	return deg_to_rad(lerpf(28.0, 62.0, pow(t, 0.7)) + far * 6.0 + further * 3.0)


## How steeply the camera looks down now, zoom and tilt together.
func view_pitch() -> float:
	return clampf(pitch_for(dist) + tilt, deg_to_rad(3.0), deg_to_rad(86.0))


func pan_screen(delta: Vector2) -> void:
	# convert screen motion to ground motion proportional to zoom
	var k := dist * 0.0021 * (720.0 / maxf(get_viewport().get_visible_rect().size.y, 1.0)) * 1.0
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var fwd := Vector3(sin(yaw), 0, cos(yaw))
	_t_target -= (right * delta.x + fwd * delta.y) * k
	_t_target.x = clampf(_t_target.x, -limit, limit)
	_t_target.z = clampf(_t_target.z, -limit, limit)


func zoom(factor: float) -> void:
	_t_dist = clampf(_t_dist * factor, MIN_D, MAX_D)


func rotate_by(a: float) -> void:
	_t_yaw += a


## Tilts the view up or down from the tilt the zoom gives it (right-drag on PC).
func tilt_by(a: float) -> void:
	_t_tilt = clampf(_t_tilt + a, MIN_TILT, MAX_TILT)


func focus(p: Vector3) -> void:
	_t_target = Vector3(p.x, 0, p.z)


func _process(delta: float) -> void:
	_keyboard(delta)
	if idle_spin:
		_t_yaw += delta * 0.05
	var k := 1.0 - exp(-delta * 10.0)
	target = target.lerp(_t_target, k)
	yaw = lerp_angle(yaw, _t_yaw, k)
	dist = lerpf(dist, _t_dist, k)
	tilt = lerpf(tilt, _t_tilt, k)
	var pitch := view_pitch()
	var want := _ground_height(target)
	_ground = want if is_nan(_ground) else lerpf(_ground, want, 1.0 - exp(-delta * 2.2))
	var focus_p := Vector3(target.x, _ground, target.z)
	var off := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * dist
	var at := focus_p + off
	# looking across the town from the side, the camera never sinks into a hill:
	# it rises over one quickly but smoothly, and settles back down slowly
	if ground_fn.is_valid():
		var low := _area_height(at, 2.5) + 0.8
		if is_nan(_floor):
			_floor = low
		_floor = lerpf(_floor, low, 1.0 - exp(-delta * (7.0 if low > _floor else 1.8)))
		at.y = maxf(at.y, maxf(_floor, float(ground_fn.call(at.x, at.z)) + 0.3))
	cam.global_position = at
	cam.look_at(focus_p, Vector3.UP)


## Desktop: WASD/arrows pan, Q/E rotate, R/F or +/- zoom. Ignored while typing.
func _keyboard(delta: float) -> void:
	if Game.menu_open or get_viewport().gui_get_focus_owner() is LineEdit or Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META):
		return
	var mv := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): mv.x += 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): mv.x -= 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): mv.y += 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): mv.y -= 1.0
	var fast := 2.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0
	if mv != Vector2.ZERO:
		pan_screen(mv.normalized() * 900.0 * delta * fast)
	var rot := 0.0
	if Input.is_key_pressed(KEY_Q): rot -= 1.0
	if Input.is_key_pressed(KEY_E): rot += 1.0
	if rot != 0.0:
		rotate_by(rot * 1.6 * delta * fast)
	var z := 0.0
	if Input.is_key_pressed(KEY_R) or Input.is_key_pressed(KEY_EQUAL) or Input.is_key_pressed(KEY_KP_ADD): z -= 1.0
	if Input.is_key_pressed(KEY_F) or Input.is_key_pressed(KEY_MINUS) or Input.is_key_pressed(KEY_KP_SUBTRACT): z += 1.0
	if z != 0.0:
		zoom(exp(z * 1.4 * delta * fast))


## The ground the view looks at: not the single point under the focus but the
## lie of the land around it, over an area that widens as the view pulls back,
## so one hillock or bank passing underneath barely moves the view.
func _ground_height(p: Vector3) -> float:
	if not ground_fn.is_valid():
		return 0.0
	return _area_height(p, clampf(dist * 0.18, 2.0, 24.0)) * 0.8


## The ground around `p`: the middle and two rings, the middle counting most.
func _area_height(p: Vector3, r: float) -> float:
	var sum := maxf(0.0, ground_fn.call(p.x, p.z)) * 4.0
	var w := 4.0
	for ring: float in [0.5, 1.0]:
		for k in 8:
			var q := Vector2(p.x, p.z) + Vector2.from_angle(k * TAU / 8.0 + ring) * r * ring
			var wt := 2.0 - ring
			sum += maxf(0.0, ground_fn.call(q.x, q.y)) * wt
			w += wt
	return sum / w

