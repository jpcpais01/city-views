class_name IslandHud
extends Hud
## Interface for the new island: the same frosted-glass look as the classic
## town, with the street and landscape brushes (growing the town comes next).

signal back_to_town

const BRUSH_INFO := {
	"street": ["Street", "Draw a line: the street lays itself over the land"],
	"grow": ["Grow", "Paint where the town should grow: it lays out its own streets"],
	"green": ["Green", "Paint parks and gardens: the town keeps them green instead of building"],
	"clear": ["Clear", "Drag to take streets away and stop the town growing there"],
	"raise": ["Raise", "Drag to lift hills out of the land"],
	"lower": ["Lower", "Drag to carve valleys, coves and bays"],
	"smooth": ["Smooth", "Drag to soften bumps and rough slopes"],
	"flatten": ["Flatten", "Drag to level the ground to where you started"],
}
const ICONS := {"street": "road", "grow": "house", "green": "park", "clear": "bulldoze"}
const SIZES := [["S", 3.0], ["M", 5.0], ["L", 8.5]]

var island: IslandWorld
var _brush_keys := {}
var _size_btn: Button
var _size_i := 1
var _help: Label


func _ready() -> void:
	layer = 5
	var base: Font = load("res://assets/fonts/Nunito.ttf")
	font_bold = FontVariation.new()
	font_bold.base_font = base
	font_bold.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 850}
	font_reg = FontVariation.new()
	font_reg.base_font = base
	font_reg.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 650}
	_glass_light = _glass_mat(0.5)
	_glass_dark = _glass_mat(0.62)
	_glass_accent = _glass_mat(0.72)
	if not OS.has_feature("mobile"):
		get_window().size_changed.connect(_fit_desktop_scale)
		_fit_desktop_scale()
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = _make_theme()
	add_child(_root)
	get_viewport().size_changed.connect(_apply_side_margins)
	_apply_side_margins()
	_build_island_top()
	_build_brushes()
	_build_fps()
	island.brush_changed.connect(_refresh_brushes)
	_refresh_brushes()


func _build_island_top() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_TOP_WIDE)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	_root.add_child(margin)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	margin.add_child(row)
	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glassify(card)
	row.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	card.add_child(v)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 10)
	v.add_child(name_row)
	name_row.add_child(_label("New island", 26, true))
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", _box(Color("dff3ea"), 12, 8, false))
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(_label("Preview", 16, true, MINT))
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_row.add_child(chip)
	_help = _label("Draw streets, or shape the land: pick a brush", 14, false, SOFT)
	v.add_child(_help)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)
	var fresh := _text_pill("New landscape")
	fresh.pressed.connect(func():
		Sfx.play("unlock", 1.0, -6.0)
		island.new_island(randi() % 1000000))
	row.add_child(fresh)
	var back := _text_pill("Classic town")
	back.pressed.connect(func():
		Sfx.play("click")
		back_to_town.emit())
	row.add_child(back)


func _text_pill(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 56)
	b.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	b.material = _glass_light
	b.add_theme_font_override("font", font_bold)
	b.add_theme_font_size_override("font_size", 17)
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("font_hover_color", INK)
	b.add_theme_color_override("font_pressed_color", INK)
	b.add_theme_stylebox_override("normal", _glass_box(GLASS, 28, 18))
	b.add_theme_stylebox_override("hover", _glass_box(Color(0.97, 0.98, 1.0), 28, 18))
	b.add_theme_stylebox_override("pressed", _glass_box(Color(1, 0.88, 0.84), 28, 18))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pivot_offset = Vector2(60, 28)
	b.button_down.connect(func(): _squish(b, 0.93))
	b.button_up.connect(func(): _squish(b, 1.0))
	return b


func _build_brushes() -> void:
	var bottom := CenterContainer.new()
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_top = -110
	bottom.offset_bottom = -10
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bottom)
	var m := PanelContainer.new()
	_glassify(m)
	bottom.add_child(m)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(row)
	for id in IslandWorld.BRUSHES:
		var b := _key(80, 84)
		var v := VBoxContainer.new()
		v.set_anchors_preset(Control.PRESET_FULL_RECT)
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.add_theme_constant_override("separation", -2)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(v)
		var ic := _icon(ICONS.get(id, id), 44)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(ic)
		var cl := _label(BRUSH_INFO[id][0], 13, true, INK)
		cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(cl)
		b.pressed.connect(func():
			Sfx.play("click", 1.1, -4.0)
			island.set_brush(id))
		row.add_child(b)
		_brush_keys[id] = b
		if id == "clear":
			var gap := Control.new()
			gap.custom_minimum_size = Vector2(10, 0)
			gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(gap)
	_size_btn = _key(64, 84)
	_size_btn.toggle_mode = false
	_size_btn.add_theme_font_override("font", font_bold)
	_size_btn.add_theme_font_size_override("font_size", 24)
	_size_btn.add_theme_color_override("font_color", INK)
	_size_btn.add_theme_color_override("font_hover_color", INK)
	_size_btn.add_theme_color_override("font_pressed_color", INK)
	_size_btn.pressed.connect(func():
		_size_i = (_size_i + 1) % SIZES.size()
		Sfx.play("click", 0.9 + _size_i * 0.15, -4.0)
		_refresh_brushes())
	row.add_child(_size_btn)


func _refresh_brushes() -> void:
	for id in _brush_keys:
		_brush_keys[id].set_pressed_no_signal(id == island.brush)
	island.brush_radius = SIZES[_size_i][1]
	_size_btn.text = SIZES[_size_i][0]
	if island.brush != "":
		_help.text = BRUSH_INFO[island.brush][1]
	else:
		_help.text = "Draw streets, or shape the land: pick a brush"


func _process(delta: float) -> void:
	if _fps_label.visible:
		_fps_time += delta
		if _fps_time >= 0.5:
			_fps_time = 0.0
			var tris := Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
			_fps_label.text = "%d FPS\n%s tris" % [Engine.get_frames_per_second(), _short_count(tris)]


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_F11 or (event.alt_pressed and event.keycode == KEY_ENTER)):
		var w := get_window()
		w.mode = Window.MODE_WINDOWED if w.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN
		get_viewport().set_input_as_handled()


func _input(_event: InputEvent) -> void:
	pass
