class_name Smoke
extends Node3D
## Soft grey smoke curling up from the chimney stacks of the big works and
## drifting off with the wind. One MultiMesh of low round puffs for the
## whole town: each puff rises, swells and fades, then starts again at the
## top of its stack.

## the most stacks that smoke at once, and puffs on each
const STACKS := 20
const PUFFS := 5
## seconds a puff lives, how high it climbs and how far the wind takes it
const LIFE := 6.0
const RISE := 3.2
const WIND := Vector3(1.5, 0.0, 0.6)

var town: Town
var _mm: MultiMesh
var _stacks: PackedVector3Array = []
var _look := 0.0


func _ready() -> void:
	var puff := SphereMesh.new()
	puff.radius = 0.5
	puff.height = 0.8
	puff.radial_segments = 6
	puff.rings = 2
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.roughness = 1.0
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	puff.material = m
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.mesh = puff
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


## Where smoke rises now: the tops of the works' stacks, busiest first.
func stacks() -> PackedVector3Array:
	var out: PackedVector3Array = []
	if town == null:
		return out
	for l: Town.Lot in town.lots.values():
		if l.use == "industry" and l.smoke != Vector3.INF:
			out.append(l.smoke)
			if out.size() >= STACKS:
				break
	return out


func _process(delta: float) -> void:
	_look -= delta
	if _look <= 0.0:
		_look = 2.0
		_stacks = stacks()
		_mm.instance_count = _stacks.size() * PUFFS
	var t := Time.get_ticks_msec() * 0.001
	for s in _stacks.size():
		var top := _stacks[s]
		for k in PUFFS:
			# each stack runs a little out of step with the next
			var age := fposmod(t / LIFE + float(k) / PUFFS + s * 0.37, 1.0)
			var size := lerpf(0.25, 1.0, sqrt(age))
			var p := top + Vector3(0, RISE * sqrt(age), 0) + WIND * age * age
			p.x += sin(t * 0.7 + s + k) * 0.08 * age
			var i := s * PUFFS + k
			_mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * size), p))
			var grey := lerpf(0.62, 0.86, age)
			var alpha := smoothstep(0.0, 0.08, age) * (1.0 - age) * 0.85
			_mm.set_instance_color(i, Color(grey, grey, grey * 1.02, alpha))
