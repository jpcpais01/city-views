class_name LoadingScreen
extends CanvasLayer
## Boot loader: a sunset card in the app icon's palette that covers the first
## frames while the island is generated and its shaders warm up, then dissolves
## so the city blooms into view behind it.

signal finished

const TOP := Color("ff9484")
const MID := Color("ffb592")
const BOTTOM := Color("ffdcae")
const INK := Color("8a4a3c")
const ICON_PX := 156.0
const MIN_TIME := 1.8
const MAX_TIME := 12.0
## tiles still waiting when we reveal; the rest fade in on screen as a bloom
const REVEAL_LEFT := 320

const LINES := [
	"Shaping the coastline",
	"Planting the forests",
	"Laying the streets",
	"Painting the windows",
	"Waking the harbour",
]

var world: World

var _root: Control
var _float: Control
var _glow: TextureRect
var _line: Label
var _fill: Panel
var _track: Panel
var _shown := 0.0
var _target := 0.05
var _elapsed := 0.0
var _line_i := 0
var _line_t := 0.0
var _total := 0
var _leaving := false


func _ready() -> void:
	layer = 100
	var base: Font = load("res://assets/fonts/Nunito.ttf")
	var wght := TextServerManager.get_primary_interface().name_to_tag("wght")
	var bold := FontVariation.new()
	bold.base_font = base
	bold.variation_opentype = {wght: 850}
	var reg := FontVariation.new()
	reg.base_font = base
	reg.variation_opentype = {wght: 650}

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var sky := TextureRect.new()
	sky.set_anchors_preset(Control.PRESET_FULL_RECT)
	sky.stretch_mode = TextureRect.STRETCH_SCALE
	sky.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	g.colors = PackedColorArray([TOP, MID, BOTTOM])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 4
	gt.height = 256
	sky.texture = gt
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(sky)

	# low warm sun behind the icon, like the one setting in the launcher art
	_glow = TextureRect.new()
	var sg := Gradient.new()
	sg.offsets = PackedFloat32Array([0.0, 0.32, 1.0])
	sg.colors = PackedColorArray([Color(1, 0.96, 0.86, 0.75), Color(1, 0.9, 0.75, 0.35), Color(1, 0.88, 0.75, 0.0)])
	var st := GradientTexture2D.new()
	st.gradient = sg
	st.fill = GradientTexture2D.FILL_RADIAL
	st.fill_from = Vector2(0.5, 0.5)
	st.fill_to = Vector2(1.0, 0.5)
	st.width = 256
	st.height = 256
	_glow.texture = st
	_glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_glow)

	# drawn opaque inside a group so overlapping puffs fade as one shape
	var group := CanvasGroup.new()
	group.self_modulate = Color(1, 1, 1, 0.62)
	_root.add_child(group)
	var clouds := _Clouds.new()
	clouds.mouse_filter = Control.MOUSE_FILTER_IGNORE
	group.add_child(clouds)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(col)

	# the icon floats in a holder so the container never fights the bob
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(ICON_PX, ICON_PX + 18)
	holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(holder)
	_float = Control.new()
	_float.size = Vector2(ICON_PX, ICON_PX)
	_float.pivot_offset = _float.size * 0.5
	_float.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(_float)
	var shadow := Panel.new()
	shadow.size = _float.size
	var sb := StyleBoxFlat.new()
	sb.bg_color = TOP
	sb.set_corner_radius_all(int(ICON_PX * 0.23))
	sb.shadow_color = Color(0.55, 0.2, 0.15, 0.22)
	sb.shadow_size = 34
	sb.shadow_offset = Vector2(0, 16)
	sb.anti_aliasing_size = 1.2
	shadow.add_theme_stylebox_override("panel", sb)
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_float.add_child(shadow)
	var icon := TextureRect.new()
	icon.texture = load("res://icon.png")
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_SCALE
	icon.size = _float.size
	var mask := ShaderMaterial.new()
	mask.shader = Shader.new()
	mask.shader.code = ROUND_SHADER
	icon.material = mask
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_float.add_child(icon)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 26)
	col.add_child(spacer)

	var title := Label.new()
	title.text = "City Views"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", bold)
	title.add_theme_font_size_override("font_size", 50)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.add_theme_color_override("font_shadow_color", Color(0.6, 0.25, 0.18, 0.16))
	title.add_theme_constant_override("shadow_offset_x", 0)
	title.add_theme_constant_override("shadow_offset_y", 3)
	title.add_theme_constant_override("shadow_outline_size", 6)
	col.add_child(title)

	_line = Label.new()
	_line.text = LINES[0] + "…"
	_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_line.add_theme_font_override("font", reg)
	_line.add_theme_font_size_override("font_size", 19)
	_line.add_theme_color_override("font_color", Color(INK, 0.78))
	col.add_child(_line)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 22)
	col.add_child(gap)

	# a slim frosted pill that fills as the island is built
	_track = Panel.new()
	_track.custom_minimum_size = Vector2(240, 10)
	_track.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var tb := StyleBoxFlat.new()
	tb.bg_color = Color(1, 1, 1, 0.32)
	tb.set_corner_radius_all(5)
	tb.border_color = Color(1, 1, 1, 0.55)
	tb.set_border_width_all(1)
	tb.anti_aliasing_size = 1.0
	_track.add_theme_stylebox_override("panel", tb)
	col.add_child(_track)
	_fill = Panel.new()
	var fb := StyleBoxFlat.new()
	fb.bg_color = Color.WHITE
	fb.set_corner_radius_all(5)
	fb.shadow_color = Color(1, 1, 1, 0.55)
	fb.shadow_size = 6
	fb.anti_aliasing_size = 1.0
	_fill.add_theme_stylebox_override("panel", fb)
	_fill.position = Vector2.ZERO
	_fill.size = Vector2(10, 10)
	_track.add_child(_fill)

	var ver := Label.new()
	ver.text = "v" + str(ProjectSettings.get_setting("application/config/version", ""))
	ver.add_theme_font_override("font", reg)
	ver.add_theme_font_size_override("font_size", 14)
	ver.add_theme_color_override("font_color", Color(INK, 0.45))
	ver.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	ver.grow_horizontal = Control.GROW_DIRECTION_BOTH
	ver.grow_vertical = Control.GROW_DIRECTION_BEGIN
	ver.offset_bottom = -22
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(ver)

	# entrance: the icon settles in with a soft overshoot
	_float.scale = Vector2(0.86, 0.86)
	_float.modulate.a = 0.0
	var tw := create_tween().set_parallel()
	tw.tween_property(_float, "scale", Vector2.ONE, 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_float, "modulate:a", 1.0, 0.45)


## Advance the bar to at least p (0..1) and optionally swap the caption.
func set_progress(p: float, caption := "") -> void:
	_target = maxf(_target, clampf(p, 0.0, 1.0))
	if caption != "":
		_swap_line(caption)


## Follow the world's build queue and dissolve once most of the city exists.
func track(w: World) -> void:
	world = w
	_total = maxi(w._build_queue.size(), 1)


func _process(delta: float) -> void:
	# the world build stalls a frame or two; don't let that skip the animation
	delta = minf(delta, 0.1)
	_elapsed += delta
	var t := Time.get_ticks_msec() * 0.001
	var vs := _root.size
	var gs := minf(vs.x, vs.y) * 1.35 * (1.0 + 0.03 * sin(t * 1.3))
	_glow.size = Vector2(gs, gs)
	_glow.position = vs * 0.5 - _glow.size * 0.5 + Vector2(0, -vs.y * 0.08)
	if not _leaving:
		_float.position.y = sin(t * 2.0) * 5.0

	if world and not _leaving:
		var left := world._build_queue.size()
		var built := 1.0 - float(maxi(left - REVEAL_LEFT, 0)) / float(maxi(_total - REVEAL_LEFT, 1))
		set_progress(0.3 + 0.7 * built)
		if (left <= REVEAL_LEFT and _elapsed >= MIN_TIME) or _elapsed >= MAX_TIME:
			_target = 1.0

	# the bar eases toward its target but never quite stalls
	_shown = move_toward(_shown, _target, delta * 0.9)
	_shown = lerpf(_shown, _target, 1.0 - exp(-delta * 5.0))
	_fill.size = Vector2(lerpf(10.0, _track.size.x, _shown), _track.size.y)

	_line_t += delta
	if _line_t > 1.5 and not _leaving and _target < 1.0:
		_line_i = (_line_i + 1) % LINES.size()
		_swap_line(LINES[_line_i] + "…")

	if not _leaving and _target >= 1.0 and _shown > 0.995:
		_leave()


func _swap_line(text: String) -> void:
	_line_t = 0.0
	var tw := create_tween()
	tw.tween_property(_line, "modulate:a", 0.0, 0.18)
	tw.tween_callback(func(): _line.text = text)
	tw.tween_property(_line, "modulate:a", 1.0, 0.25)


func _leave() -> void:
	_leaving = true
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_swap_line("Welcome to " + Game.city_name)
	var tw := create_tween()
	tw.tween_interval(0.35)
	tw.set_parallel()
	tw.tween_property(_float, "scale", Vector2(1.12, 1.12), 0.75).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_root, "modulate:a", 0.0, 0.75).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.chain().tween_callback(func():
		finished.emit()
		queue_free())


const ROUND_SHADER := """
shader_type canvas_item;
// squircle-ish rounded mask so the square icon reads like a launcher tile
uniform float radius = 0.23;
void fragment() {
	vec2 p = abs(UV - 0.5) - (0.5 - radius);
	float d = length(max(p, 0.0)) - radius;
	float aa = fwidth(d) * 1.2;
	COLOR.a *= 1.0 - smoothstep(-aa, aa, d);
}
"""


## Three soft puffs drifting across the sunset.
class _Clouds extends Control:
	var _puffs := [
		{"x": 0.14, "y": 0.18, "s": 1.0, "v": 0.010},
		{"x": 0.78, "y": 0.12, "s": 0.75, "v": 0.006},
		{"x": 0.62, "y": 0.80, "s": 0.6, "v": 0.008},
	]

	func _process(delta: float) -> void:
		for p in _puffs:
			p.x += p.v * delta
			if p.x > 1.2:
				p.x = -0.2
		queue_redraw()

	func _draw() -> void:
		size = get_viewport_rect().size
		var u := minf(size.x, size.y) * 0.09
		var col := Color(1, 0.97, 0.94)
		for p in _puffs:
			var c := Vector2(p.x * size.x, p.y * size.y)
			var s: float = u * p.s
			draw_circle(c + Vector2(-0.55, 0.12) * s, 0.42 * s, col)
			draw_circle(c + Vector2(0.0, -0.12) * s, 0.58 * s, col)
			draw_circle(c + Vector2(0.55, 0.14) * s, 0.38 * s, col)
			draw_rect(Rect2(c + Vector2(-0.55, 0.12) * s, Vector2(1.1, 0.42) * s), col)
