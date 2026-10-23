class_name CameraRig
extends Node3D
## Smooth orbit camera: pan, pinch-zoom, twist-rotate. Tilts flatter as you zoom in.

var target := Vector3.ZERO
var yaw := deg_to_rad(35.0)
var dist := 38.0
var _t_target := Vector3.ZERO
var _t_yaw := deg_to_rad(35.0)
var _t_dist := 38.0
var cam: Camera3D
var idle_spin := false

const MIN_D := 9.0
const MAX_D := 95.0


func _ready() -> void:
	cam = Camera3D.new()
	cam.fov = 40.0
	cam.near = 0.3
	cam.far = 600.0
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
	var lim := Game.N * Game.TILE * 0.5
	_t_target.x = clampf(_t_target.x, -lim, lim)
	_t_target.z = clampf(_t_target.z, -lim, lim)


func zoom(factor: float) -> void:
	_t_dist = clampf(_t_dist * factor, MIN_D, MAX_D)


func rotate_by(a: float) -> void:
	_t_yaw += a


func focus(p: Vector3) -> void:
	_t_target = Vector3(p.x, 0, p.z)


func _process(delta: float) -> void:
	if idle_spin:
		_t_yaw += delta * 0.05
	var k := 1.0 - exp(-delta * 10.0)
	target = target.lerp(_t_target, k)
	yaw = lerp_angle(yaw, _t_yaw, k)
	dist = lerpf(dist, _t_dist, k)
	var pitch := pitch_for(dist)
	var ground := _ground_height(target)
	var focus_p := Vector3(target.x, ground, target.z)
	var off := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * dist
	cam.global_position = focus_p + off
	cam.look_at(focus_p, Vector3.UP)


func _ground_height(p: Vector3) -> float:
	var t := Game.world_to_tile(p)
	if not Game.inside(t.x, t.y):
		return 0.0
	return max(0.0, Game.tile_y(t.x, t.y)) * 0.6


## Ray-march the terrain to find the tile under a screen point.
func pick_tile(screen: Vector2) -> Vector2i:
	var o := cam.project_ray_origin(screen)
	var d := cam.project_ray_normal(screen)
	var t := 0.0
	var step := 0.3
	while t < 400.0:
		var p := o + d * t
		var tile := Game.world_to_tile(p)
		if Game.inside(tile.x, tile.y):
			var top: float = max(Game.tile_y(tile.x, tile.y), 0.0)
			if Game.knd(tile.x, tile.y) == Game.K.ROAD:
				top = Game.LEVEL_Y[Game.road_level(tile.x, tile.y)]
			if p.y <= top:
				return tile
		elif p.y < -1.0:
			return Vector2i(-1, -1)
		t += step
	return Vector2i(-1, -1)
