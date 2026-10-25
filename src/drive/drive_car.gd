class_name DriveCar
extends Node3D
## The player's own little car for Drive mode: a rounded toy hatchback with
## wheels that turn and steer, driven arcade-style over the real streets.
## It rides the road surface (kerbs, bridges, hills) and the bare ground off
## it, leans into slopes, and stops against buildings and at the water.

## half the body across and half its length, for bumping into things
const HALF_W := 0.18
const HALF_L := 0.36
const WHEELBASE := 0.44
const WHEEL_R := 0.068
## top speed on a street, off it, and backing up (m/s at toy scale)
const TOP := 3.4
const TOP_ROUGH := 1.6
const TOP_BACK := 1.1
const ACCEL := 2.3
const BRAKE := 5.5
## real-world km/h for the speedometer: the town is about 1:7.3
const KMH := 7.3 * 3.6
const BODY := Color("ff7a6b")

var land: Land
var streets: Streets
var town: Town
var material: Material

## signed speed along the car's heading
var speed := 0.0
## where the nose points, as a yaw about +Y (0 faces +Z)
var heading := 0.0
## -1 left .. 1 right, eased towards what the driver asks
var steer := 0.0
## what the driver is doing: throttle -1 (brake / reverse) .. 1, steer -1 .. 1
var input_throttle := 0.0
var input_steer := 0.0
## whether it is on a street now (faster, smoother)
var on_road := false
## set for a frame when it bumps into something, with how hard
var bumped := 0.0

var _pitch := 0.0
var _roll := 0.0
var _y := NAN
var _wheels: Array[Node3D] = []
var _spin := 0.0
var _beam: SpotLight3D
## how dark it is (World.night), for the headlights
var night := 0.0
# the street the car is on and where along it, so each frame only looks
# at the few samples round the last spot
var _near: Array = []
var _near_timer := 0.0


func _ready() -> void:
	var mk := MeshKit.new(7)
	_build_body(mk)
	var body := MeshInstance3D.new()
	body.mesh = mk.commit(material)
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(body)
	var sh := mk.commit_shadow(Palette.shadow_material())
	if sh:
		var smi := MeshInstance3D.new()
		smi.mesh = sh
		smi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		add_child(smi)
	var wheel := _wheel_mesh()
	for z in [WHEELBASE * 0.5, -WHEELBASE * 0.5]:
		for x in [-1.0, 1.0]:
			var pivot := Node3D.new()
			pivot.position = Vector3(x * (HALF_W - 0.012), WHEEL_R, z)
			add_child(pivot)
			var w := MeshInstance3D.new()
			w.mesh = wheel
			w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			w.rotation.z = -PI * 0.5 * x
			pivot.add_child(w)
			_wheels.append(pivot)
	# headlights that light the road ahead after dark
	_beam = SpotLight3D.new()
	_beam.position = Vector3(0, 0.16, HALF_L)
	_beam.rotation = Vector3(deg_to_rad(-8.0), PI, 0)
	_beam.spot_range = 7.0
	_beam.spot_angle = 32.0
	_beam.spot_attenuation = 0.6
	_beam.light_color = Color(1.0, 0.92, 0.78)
	_beam.shadow_enabled = false
	_beam.visible = false
	add_child(_beam)


## A hatchback along +Z: rounded body, a glasshouse with pillars, bumpers,
## lamps that light at night, mirrors and a roof rack of sorts.
func _build_body(mk: MeshKit) -> void:
	var glass := Color(0.2, 0.27, 0.35)
	var trim := Color(0.22, 0.23, 0.26)
	var cream := Color(0.97, 0.96, 0.93)
	# the body, sitting on its wheels, a little wider over the arches
	mk.rbox(Vector3(0, 0.125, 0.0), Vector3(HALF_W * 2.0, 0.12, HALF_L * 2.0), 0.045, BODY)
	mk.rbox(Vector3(0, 0.205, 0.17), Vector3(HALF_W * 2.0 - 0.02, 0.05, 0.22), 0.025, BODY)
	# the cabin: pillars and roof in cream, windows set into it
	mk.rbox(Vector3(0, 0.255, -0.06), Vector3(HALF_W * 2.0 - 0.035, 0.13, 0.4), 0.04, cream)
	mk.shadow = false
	var cy := 0.262
	var hw := HALF_W - 0.0175
	# windscreen and rear window, set just proud of the cabin's flat faces
	var zf := 0.14 + 0.004
	mk.quad(Vector3(-hw + 0.03, cy - 0.045, zf), Vector3(hw - 0.03, cy - 0.045, zf), Vector3(hw - 0.035, cy + 0.04, zf), Vector3(-hw + 0.035, cy + 0.04, zf), Vector3.BACK, glass, 0.0, 0.8)
	var zb := -0.26 - 0.004
	mk.quad(Vector3(hw - 0.035, cy - 0.035, zb), Vector3(-hw + 0.035, cy - 0.035, zb), Vector3(-hw + 0.04, cy + 0.04, zb), Vector3(hw - 0.04, cy + 0.04, zb), Vector3.FORWARD, glass, 0.0, 0.8)
	# side windows, split by the middle pillar
	for sx in [-1.0, 1.0]:
		var x: float = sx * (hw + 0.003)
		for seg in [[-0.235, -0.07], [-0.05, 0.115]]:
			var a := Vector3(x, cy - 0.04, seg[0])
			var b := Vector3(x, cy - 0.04, seg[1])
			var c := Vector3(x, cy + 0.04, seg[1] - 0.01)
			var d := Vector3(x, cy + 0.04, seg[0] + 0.01)
			if sx > 0.0:
				mk.quad(a, b, c, d, Vector3(1, 0, 0), glass, 0.0, 0.8)
			else:
				mk.quad(b, a, d, c, Vector3(-1, 0, 0), glass, 0.0, 0.8)
		# a mirror by the windscreen
		mk.box(Vector3(sx * (HALF_W + 0.012), 0.215, 0.115), Vector3(0.025, 0.02, 0.03), BODY.darkened(0.1))
		# a dark sill along the bottom and the wheel arches above the tyres
		mk.box(Vector3(sx * (HALF_W - 0.004), 0.072, 0.0), Vector3(0.012, 0.022, HALF_L * 1.4), trim)
	# bumpers, front and back
	mk.rbox(Vector3(0, 0.085, HALF_L + 0.008), Vector3(HALF_W * 2.0 + 0.008, 0.05, 0.04), 0.018, trim)
	mk.rbox(Vector3(0, 0.085, -HALF_L - 0.008), Vector3(HALF_W * 2.0 + 0.008, 0.05, 0.04), 0.018, trim)
	# lamps: warm headlights and red tail lights glow at night, a grille between
	for sx in [-0.11, 0.11]:
		var f := HALF_L + 0.003
		mk.quad(Vector3(sx - 0.04, 0.135, f), Vector3(sx + 0.04, 0.135, f), Vector3(sx + 0.035, 0.165, f), Vector3(sx - 0.035, 0.165, f), Vector3.BACK, Color(1, 0.97, 0.86), 2.0)
		mk.quad(Vector3(sx + 0.04, 0.14, -f), Vector3(sx - 0.04, 0.14, -f), Vector3(sx - 0.04, 0.165, -f), Vector3(sx + 0.04, 0.165, -f), Vector3.FORWARD, Color(0.95, 0.12, 0.1), 2.75)
	mk.quad(Vector3(-0.055, 0.13, HALF_L + 0.004), Vector3(0.055, 0.13, HALF_L + 0.004), Vector3(0.055, 0.155, HALF_L + 0.004), Vector3(-0.055, 0.155, HALF_L + 0.004), Vector3.BACK, trim)
	# a number plate at the back
	mk.quad(Vector3(0.045, 0.1, -HALF_L - 0.03), Vector3(-0.045, 0.1, -HALF_L - 0.03), Vector3(-0.045, 0.122, -HALF_L - 0.03), Vector3(0.045, 0.122, -HALF_L - 0.03), Vector3.FORWARD, Color(0.98, 0.84, 0.3))
	# roof bars
	for sx in [-0.1, 0.1]:
		mk.box(Vector3(sx, 0.326, -0.06), Vector3(0.014, 0.012, 0.3), trim)
	mk.shadow = true


func _wheel_mesh() -> ArrayMesh:
	var mk := MeshKit.new(3)
	mk.shadow = false
	# a tyre with a pale hub, standing along local Y (turned on its side by the pivot)
	mk.cylinder(Vector3(0, -0.026, 0), WHEEL_R, 0.052, 12, Color(0.13, 0.13, 0.15))
	mk.cylinder(Vector3(0, 0.026, 0), WHEEL_R * 0.55, 0.004, 8, Color(0.82, 0.83, 0.86))
	return mk.commit(material)


## Puts the car at `p` facing `yaw`, standing still.
func place(p: Vector2, yaw: float) -> void:
	heading = yaw
	speed = 0.0
	steer = 0.0
	_y = NAN
	_near.clear()
	_near_timer = 0.0
	position = Vector3(p.x, 0, p.y)
	_settle(1.0)


## Puts the car on the street nearest `p`, in the right-hand lane, pointing
## along it the way the camera looks (`look_yaw`). False if there is no street.
func place_on_street(p: Vector2, look_yaw: float) -> bool:
	var best: Streets.Street = null
	var best_d := INF
	var best_f := 0.0
	for s: Streets.Street in streets.streets:
		if s.pts.size() < 2:
			continue
		var c := s.closest(p)
		if c.x < best_d:
			best_d = c.x
			best = s
			best_f = c.z
	if best == null:
		return false
	var i := clampi(int(best_f), 0, best.pts.size() - 2)
	var t := best_f - i
	var a := best.pts[i]
	var b := best.pts[i + 1]
	var dir := (b - a).normalized()
	var at := a.lerp(b, t)
	var fwd := Vector2(sin(look_yaw), cos(look_yaw))
	if dir.dot(fwd) < 0.0:
		dir = -dir
	# keep right: the lane on the right of the way it faces
	var right := Vector2(-dir.y, dir.x)
	var off := Traffic.lane_offset(best, 0)
	at += right * off
	place(at, atan2(dir.x, dir.y))
	return true


func _process(delta: float) -> void:
	drive(minf(delta, 0.05))


## One step of driving: the driver's input, the speed, the turn, the bump.
func drive(delta: float) -> void:
	bumped = 0.0
	steer = move_toward(steer, input_steer, delta * (3.2 if absf(input_steer) > absf(steer) else 4.5))
	var top := TOP if on_road else TOP_ROUGH
	var th := input_throttle
	if th > 0.0:
		if speed < -0.05:
			speed = move_toward(speed, 0.0, BRAKE * delta)
		else:
			speed = move_toward(speed, top * th, ACCEL * delta * (1.0 if speed < top else 2.0))
	elif th < 0.0:
		if speed > 0.05:
			speed = move_toward(speed, 0.0, BRAKE * delta * -th)
		else:
			speed = move_toward(speed, -TOP_BACK * -th, ACCEL * 0.6 * delta)
	else:
		# rolling to a stop
		speed = move_toward(speed, 0.0, (0.6 + absf(speed) * 0.35) * delta)
	# steering tightens at low speed and gentles at high speed
	var lock := lerpf(0.62, 0.2, clampf(absf(speed) / TOP, 0.0, 1.0))
	var turn := speed * tan(steer * lock) / WHEELBASE
	var new_heading := heading - turn * delta
	var fwd := Vector2(sin(new_heading), cos(new_heading))
	var from := Vector2(position.x, position.z)
	var to := from + fwd * speed * delta
	if _free(to, new_heading):
		heading = new_heading
	elif _free(Vector2(to.x, from.y), heading):
		to = Vector2(to.x, from.y)
		speed *= 0.85
	elif _free(Vector2(from.x, to.y), heading):
		to = Vector2(from.x, to.y)
		speed *= 0.85
	else:
		bumped = absf(speed)
		speed = -speed * 0.25
		to = from
	var lim := Land.HALF - 6.0
	to = to.clamp(Vector2(-lim, -lim), Vector2(lim, lim))
	position.x = to.x
	position.z = to.y
	_settle(delta)
	# the wheels roll with the speed, the front ones steer
	_beam.visible = night > 0.2
	_beam.light_energy = night * 2.2
	_spin += speed * delta / WHEEL_R
	for k in _wheels.size():
		var w := _wheels[k]
		w.rotation = Vector3(_spin, -steer * lock if k < 2 else 0.0, 0.0)


## Lifts the car onto the surface under its wheels, leaning with the slope.
func _settle(delta: float) -> void:
	_near_timer -= delta
	if _near_timer <= 0.0 or _near.is_empty():
		_find_near()
	var fwd := Vector3(sin(heading), 0, cos(heading))
	var right := Vector3(cos(heading), 0, -sin(heading))
	var c := position
	var hint := c.y if not is_nan(_y) else INF
	var yf := surface(c + fwd * WHEELBASE * 0.5, hint)
	var yb := surface(c - fwd * WHEELBASE * 0.5, hint)
	var yl := surface(c - right * (HALF_W - 0.02), hint)
	var yr := surface(c + right * (HALF_W - 0.02), hint)
	on_road = _road_y(Vector2(c.x, c.z), hint) > -INF
	var want := (yf + yb + yl + yr) * 0.25
	_y = want if is_nan(_y) else lerpf(_y, want, 1.0 - exp(-delta * 18.0))
	position.y = _y
	var pitch := atan2(yf - yb, WHEELBASE)
	var roll := atan2(yr - yl, (HALF_W - 0.02) * 2.0)
	var k := 1.0 if delta >= 1.0 else 1.0 - exp(-delta * 12.0)
	_pitch = lerpf(_pitch, pitch, k)
	_roll = lerpf(_roll, roll, k)
	basis = Basis(Vector3.UP, heading) * Basis(Vector3.RIGHT, -_pitch) * Basis(Vector3.BACK, _roll)


## The streets near the car, refreshed a few times a second.
func _find_near() -> void:
	_near_timer = 0.25
	_near.clear()
	var p := Vector2(position.x, position.z)
	for s: Streets.Street in streets.streets:
		if s.pts.size() >= 2 and s.near_box(p, s.reach() + 3.0):
			var c := s.closest(p)
			if c.x < s.reach() + 3.0:
				_near.append([s, int(c.z)])


## The height of whatever the car drives on at `p`: a street's surface (its
## kerbside pavement a step up) or the bare ground. Where two surfaces stack
## (a bridge over a bank) the one nearest `hint` wins.
func surface(p: Vector3, hint := INF) -> float:
	var q := Vector2(p.x, p.z)
	var y := _road_y(q, hint)
	if y > -INF:
		return y
	return maxf(land.height_at(q.x, q.y), -0.02)


func _road_y(q: Vector2, hint: float) -> float:
	var best := -INF
	for e: Array in _near:
		var s: Streets.Street = e[0]
		var r := _closest_window(s, q, e[1])
		if r.x < s.reach():
			var y := r.y + 0.03 + (Streets.CURB if r.x > s.w() else 0.0)
			if best == -INF or absf(y - hint) < absf(best - hint):
				best = y
	return best


## Like Street.closest() but only round sample `around`, and it follows the
## car along: the nearest spot found becomes the next frame's starting point.
func _closest_window(s: Streets.Street, p: Vector2, around: int) -> Vector3:
	var n := s.pts.size()
	var i0 := clampi(around - 12, 0, n - 2)
	var i1 := clampi(around + 12, 0, n - 2)
	var best := INF
	var by := 0.0
	var bs := float(around)
	for i in range(i0, i1 + 1):
		var a := s.pts[i]
		var ab := s.pts[i + 1] - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
		var d := p.distance_to(a + ab * t)
		if d < best:
			best = d
			by = lerpf(s.ys[i], s.ys[i + 1], t)
			bs = i + t
	return Vector3(best, by, bs)


## Whether the car fits at `p` facing `yaw`: nothing built in the way and no water.
func _free(p: Vector2, yaw: float) -> bool:
	var f := Vector2(sin(yaw), cos(yaw))
	var r := Vector2(f.y, -f.x)
	for k: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1), Vector2(0, 1), Vector2(0, -1)]:
		var q := p + f * HALF_L * k.y + r * HALF_W * k.x
		if blocked(q):
			return false
	return true


## Whether a point is inside a building, a landmark's ground or the water.
func blocked(q: Vector2) -> bool:
	var c := Town._cell(q)
	if c.x < 0 or c.y < 0 or c.x >= Town.RES or c.y >= Town.RES:
		return true
	var o: int = town._occ[c.y * Town.RES + c.x]
	if o == Town.RESERVED:
		return true
	if o < 0:
		# a street or its pavement, bridges over water included
		return false
	if o > 0:
		var l: Town.Lot = town.lots.get(o)
		if l and l.host != 0:
			l = town.lots.get(l.host, l)
		if l and not l.arrays.is_empty() and l.type != "park" and l.type != "square":
			if not l.foot.has_area():
				return true
			var d := q - l.origin
			var local := Vector2(d.dot(Vector2(cos(l.yaw), -sin(l.yaw))), d.dot(Vector2(sin(l.yaw), cos(l.yaw))))
			if l.foot.grow(0.03).has_point(local):
				return true
	# open water off any street
	if land.height_at(q.x, q.y) < -0.05 and _road_y(q, INF) == -INF:
		return true
	return false


func kmh() -> int:
	return int(round(absf(speed) * KMH))
