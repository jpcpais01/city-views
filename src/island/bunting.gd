class_name Bunting
extends Node3D
## Strings of little coloured flags hung across the main streets, wherever
## two terraces of two floors or more face each other there. They follow
## from the streets and houses alone, so every co-op builder sees the same.

const EVERY := 12.0  # street samples between strings (half a metre each)
const HANG := 1.05  # height above the street where a string meets the walls
const SAG := 0.22
const FLAGS := 9

var world: IslandWorld
var _mesh: MeshInstance3D
var _check := 1.5
var _seen := -1


func _ready() -> void:
	_mesh = MeshInstance3D.new()
	# flags this small would only speckle the shadow map
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)


func _process(delta: float) -> void:
	_check -= delta
	if _check > 0.0 or world.town.is_busy():
		return
	_check = 2.0
	# rebuild only when the town has changed
	var sig := hash([world.town.lots.size(), world.town._next_id, world.streets.streets.size()])
	if sig != _seen:
		_seen = sig
		rebuild()


## Where the strings go: pairs of facing house fronts, as [a, b] in 3D.
func spans() -> Array:
	var by_street := {}
	for l: Town.Lot in world.town.lots.values():
		if l.type == "house" and l.floors >= 2 and l.stage >= 2:
			if not by_street.has(l.street):
				by_street[l.street] = []
			by_street[l.street].append(l)
	var out := []
	for s: Streets.Street in world.streets.streets:
		if not s.major() or not by_street.has(s.id):
			continue
		var f := 2.0
		var last := -INF
		while f < s.pts.size() - 3.0:
			var p := world.streets._ptf(s, f)
			var ends := {}
			for l: Town.Lot in by_street[s.id]:
				var d := l.origin.distance_to(p)
				if d < 2.4 and (not ends.has(l.side) or d < ends[l.side][0]):
					ends[l.side] = [d, l.origin]
			if ends.size() == 2 and f - last >= EVERY:
				var a: Vector2 = ends[1.0][1]
				var b: Vector2 = ends[-1.0][1]
				# only fronts that really face each other, not a skewed pair
				var along := (world.streets._ptf(s, f + 1.0) - p).normalized()
				if absf((a - b).dot(along)) < 0.9:
					var y := world.streets._yf(s, f) + HANG
					out.append([Vector3(a.x, y, a.y), Vector3(b.x, y, b.y)])
					last = f
			f += 2.0
	return out


func rebuild() -> void:
	var mk := MeshKit.new(7)
	mk.shadow = false
	var n := 0
	for span in spans():
		_string(mk, span[0], span[1], n)
		n += 1
	_mesh.mesh = null if mk.is_empty() else mk.commit(world.city_mat)


## One sagging string from `a` to `b` with flags hanging off it.
func _string(mk: MeshKit, a: Vector3, b: Vector3, seed_value: int) -> void:
	var across := Vector3(b.x - a.x, 0, b.z - a.z).normalized()
	var flat := Vector3(-across.z, 0, across.x)
	var steps := FLAGS + 1
	var prev := a
	for k in range(1, steps + 1):
		var t := float(k) / steps
		var q := a.lerp(b, t) + Vector3(0, -SAG * 4.0 * t * (1.0 - t), 0)
		# the cord, as a thin ribbon seen from above and from below
		mk.quad(prev + flat * 0.006, q + flat * 0.006, q - flat * 0.006, prev - flat * 0.006, Vector3.UP, Color(0.92, 0.92, 0.9))
		if k < steps:
			var col: Color = Palette.AWNINGS[(seed_value * 3 + k) % Palette.AWNINGS.size()]
			var l0 := q - across * 0.055
			var l1 := q + across * 0.055
			var tip := q + Vector3(0, -0.13, 0)
			mk.tri(l0, l1, tip, col, 0.0, 0.0, flat)
			mk.tri(l0, l1, tip, col, 0.0, 0.0, -flat)
		prev = q
