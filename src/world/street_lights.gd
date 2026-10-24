class_name StreetLights
extends Node3D
## Tall street lights down the planted middle of every avenue and highway,
## one arm reaching over each carriageway, lit at night. One MultiMesh for
## all of them, laid out again whenever the streets change.

const SPACING := 9.0
## how far from a junction the first light stands
const CLEAR := 2.6
const IRON := Color("4a5058")

var material: Material
var streets: Streets
var _mm: MultiMesh
var _smm: MultiMesh
var _dirty := true


func _ready() -> void:
	var mk := MeshKit.new(0)
	# the pole and its two arms
	mk.box(Vector3(0, 0.8, 0), Vector3(0.05, 1.6, 0.05), IRON)
	mk.box(Vector3(0, 1.58, 0), Vector3(1.0, 0.035, 0.04), IRON)
	mk.shadow = false
	for sx in [-1.0, 1.0]:
		# the lamp heads, glowing at night
		mk.box_faces(Vector3(sx * 0.46, 1.55, 0), Vector3(0.2, 0.05, 0.1), Color(1, 0.9, 0.7), MeshKit.FRONT | MeshKit.BACK | MeshKit.LEFT | MeshKit.RIGHT, 2.0)
		mk.quad(Vector3(sx * 0.46 - 0.1, 1.525, 0.05), Vector3(sx * 0.46 + 0.1, 1.525, 0.05), Vector3(sx * 0.46 + 0.1, 1.525, -0.05), Vector3(sx * 0.46 - 0.1, 1.525, -0.05), Vector3.DOWN, Color(1, 0.94, 0.78), 2.0)
	var shadow := mk.commit_shadow(Palette.shadow_material())
	_mm = _multi(mk.commit(material), GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	_smm = _multi(shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY)
	streets.changed.connect(func(): _dirty = true)


func _multi(mesh: Mesh, cast: GeometryInstance3D.ShadowCastingSetting) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = cast
	add_child(mmi)
	return mm


func _process(_delta: float) -> void:
	if _dirty and streets._laying.is_empty():
		_dirty = false
		rebuild()


## Where the lights stand, along every avenue and highway.
func places() -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	var graph := streets.links()
	for s: Streets.Street in streets.streets:
		if Streets.KINDS[s.kind].median <= 0.0 or s.pts.size() < 3:
			continue
		var n := s.pts.size()
		var len := (n - 1) * Streets.SAMPLE
		var joins: Array[float] = []
		for l in graph.get(s.id, []):
			joins.append(l[0] * Streets.SAMPLE)
		# the arms reach out over the near lanes, further on a highway
		var med: float = Streets.KINDS[s.kind].median
		var reach := clampf((med + (s.w() - med) * 0.25) / 0.46, 1.0, 1.6)
		var d := CLEAR
		while d < len - CLEAR * 0.5:
			var near := false
			for j in joins:
				near = near or absf(j - d) < 1.6 + s.w() * 0.5
			if not near:
				var f := d / Streets.SAMPLE
				var p := streets._ptf(s, f)
				var side := streets._sidef(s, f)
				var y := streets._yf(s, f) + 0.03 + Streets.CURB
				out.append(Transform3D(Basis(Vector3.UP, atan2(-side.y, side.x)) * Basis.from_scale(Vector3(reach, 1, 1)), Vector3(p.x, y, p.y)))
			d += SPACING
	return out


func rebuild() -> void:
	var at := places()
	for mm in [_mm, _smm]:
		mm.instance_count = at.size()
		for i in at.size():
			mm.set_instance_transform(i, at[i])
