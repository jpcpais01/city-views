class_name AdvisorMarks
extends Node3D
## Where Pip's tips are, on the map: a soft disc on the ground in the tip's
## colour, a beam of light rising from it and a numbered tag over it, so the
## places stand out from any distance. A few hundred triangles each, only
## while there are tips to show.

const SEGS := 40
const RINGS := 4
const BEAM := 7.0

var land: Land
var _marks: Array = []
var _font: Font
var _beam_tex: GradientTexture2D
var _t := 0.0


func _init(l: Land, font: Font = null) -> void:
	land = l
	_font = font
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.0))
	g.set_color(1, Color(1, 1, 1, 0.75))
	_beam_tex = GradientTexture2D.new()
	_beam_tex.gradient = g
	_beam_tex.width = 4
	_beam_tex.height = 64
	_beam_tex.fill_from = Vector2(0, 0)
	_beam_tex.fill_to = Vector2(0, 1)


## Shows these tips (Advisor tips), numbered from 1.
func show_tips(tips: Array) -> void:
	clear()
	for i in tips.size():
		var t: Dictionary = tips[i]
		_marks.append(_make(i, t))


func clear() -> void:
	for m in _marks:
		(m.node as Node3D).queue_free()
	_marks.clear()


func has_marks() -> bool:
	return not _marks.is_empty()


## Brightens the i-th mark (and dims none of the others).
func light(i: int) -> void:
	for k in _marks.size():
		_marks[k].lit = 1.0 if k == i else 0.0


func _make(i: int, t: Dictionary) -> Dictionary:
	var at: Vector2 = t.pos
	var radius: float = t.radius
	var col: Color = t.colour
	var root := Node3D.new()
	add_child(root)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/advisor_mark.gdshader")
	mat.set_shader_parameter("tint", col)
	mat.set_shader_parameter("appear", 0.0)
	mat.set_shader_parameter("phase", i * 0.33)
	mat.render_priority = 4
	var disc := MeshInstance3D.new()
	disc.mesh = _disc(at, radius)
	disc.material_override = mat
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(disc)
	var ground := maxf(land.height_at(at.x, at.y), 0.0)
	var beam := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.9, BEAM)
	beam.mesh = q
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	bm.albedo_texture = _beam_tex
	bm.albedo_color = Color(col.r, col.g, col.b, 0.0)
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	bm.render_priority = 4
	beam.material_override = bm
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.position = Vector3(at.x, ground + BEAM * 0.5, at.y)
	root.add_child(beam)
	var tag := Label3D.new()
	tag.text = "%d  %s" % [i + 1, t.get("tag", t.title)]
	if _font:
		tag.font = _font
	tag.font_size = 36
	tag.outline_size = 14
	tag.modulate = Color.WHITE
	tag.outline_modulate = col.darkened(0.45)
	tag.fixed_size = true
	tag.pixel_size = 0.0007
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.render_priority = 6
	tag.outline_render_priority = 5
	tag.position = Vector3(at.x, ground + BEAM + 0.6, at.y)
	tag.modulate.a = 0.0
	tag.outline_modulate.a = 0.0
	root.add_child(tag)
	return {"node": root, "mat": mat, "beam": bm, "tag": tag, "y": ground + BEAM + 0.6, "colour": col,
		"born": _t + i * 0.18, "lit": 0.0, "shown_lit": 0.0}


## A disc of rings lying on the ground, following its rises and falls.
func _disc(at: Vector2, radius: float) -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var y0 := maxf(land.height_at(at.x, at.y), 0.0) + 0.12
	verts.append(Vector3(at.x, y0, at.y))
	uvs.append(Vector2(0, 0))
	for ring in RINGS:
		var f := float(ring + 1) / RINGS
		for s in SEGS:
			var a := TAU * s / SEGS
			var p := at + Vector2(cos(a), sin(a)) * radius * f
			verts.append(Vector3(p.x, maxf(land.height_at(p.x, p.y), 0.0) + 0.12, p.y))
			uvs.append(Vector2(f, float(s) / SEGS))
	for s in SEGS:
		idx.append_array([0, 1 + s, 1 + (s + 1) % SEGS])
	for ring in RINGS - 1:
		var a0 := 1 + ring * SEGS
		var b0 := a0 + SEGS
		for s in SEGS:
			var s1 := (s + 1) % SEGS
			idx.append_array([a0 + s, b0 + s, b0 + s1, a0 + s, b0 + s1, a0 + s1])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


func _process(delta: float) -> void:
	_t += delta
	for m in _marks:
		var age: float = _t - m.born
		var grow := clampf(age / 0.6, 0.0, 1.0)
		# springs open with a little overshoot
		var appear := 1.0 - pow(1.0 - grow, 3.0) + sin(grow * PI) * 0.08
		m.shown_lit = lerpf(m.shown_lit, m.lit, 1.0 - exp(-delta * 6.0))
		var mat: ShaderMaterial = m.mat
		mat.set_shader_parameter("appear", appear)
		mat.set_shader_parameter("lit", m.shown_lit)
		var bm: StandardMaterial3D = m.beam
		bm.albedo_color.a = (0.5 + 0.25 * sin(_t * 2.4 + m.born * 3.0) + 0.25 * m.shown_lit) * grow
		var tag: Label3D = m.tag
		tag.position.y = m.y + sin(_t * 2.0 + m.born * 2.0) * 0.25 + (1.0 - grow) * 1.5
		tag.modulate.a = grow
		tag.outline_modulate.a = grow
		tag.scale = Vector3.ONE * (1.0 + 0.15 * m.shown_lit)
