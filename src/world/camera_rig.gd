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

const MIN_D := 9.0
## how far the player may tilt the view either way from the zoom's own tilt
const MAX_TILT := deg_to_rad(15.0)
const MAX_D := 92.0


func _ready() -> void:
	cam = Camera3D.new()
	cam.fov = 40.0
	cam.near = 0.3
	cam.far = 1100.0
	add_child(cam)
	cam.make_current()


func pitch_for(d: float) -> float:
	var t := clampf((d - MIN_D) / (MAX_D - MIN_D), 0.0, 1.0)
	return deg_to_rad(lerpf(28.0, 62.0, pow(t, 0.7)))


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
	_t_tilt = clampf(_t_tilt + a, -MAX_TILT, MAX_TILT)


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
	var pitch := clampf(pitch_for(dist) + tilt, deg_to_rad(12.0), deg_to_rad(86.0))
	var ground := _ground_height(target)
	var focus_p := Vector3(target.x, ground, target.z)
	var off := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * dist
	cam.global_position = focus_p + off
	cam.look_at(focus_p, Vector3.UP)


## Desktop: WASD/arrows pan, Q/E rotate, R/F or +/- zoom. Ignored while typing.
func _keyboard(delta: float) -> void:
	if get_viewport().gui_get_focus_owner() is LineEdit or Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META):
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


func _ground_height(p: Vector3) -> float:
	if ground_fn.is_valid():
		return maxf(0.0, ground_fn.call(p.x, p.z)) * 0.8
	return 0.0

