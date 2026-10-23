class_name Hud
extends CanvasLayer
## The whole interface, built in code: stats, title progress, tool palette, toasts,
## tutorial hints, co-op player chips, tile info and the main menu.

var world: World

var font_bold: FontVariation
var font_reg: FontVariation
var _root: Control
var _pop_label: Label
var _coin_label: Label
var _happy_label: Label
var _name_label: Label
var _title_label: Label
var _progress: ProgressBar
var _next_label: Label
var _tool_buttons := {}
var _cat_buttons := {}
var _sub_wrap: Control
var _sub_row: HBoxContainer
var _open_cat := ""
var _last_tool := {}
var _hint: Label
var _hint_card: PanelContainer
var _toasts: VBoxContainer
var _tutorial: PanelContainer
var _tutorial_label: Label
var _players_row: HBoxContainer
var _menu: Control
var _info: PanelContainer
var _info_label: Label
var _coins_shown := 0.0
var _selected := ""
var _fps_label: Label
var _fps_time := 0.0
var _page := "island"
var _pages := {}
var _tab_buttons := {}
var _pages_root: VBoxContainer
var _new_btn: Button
var _island_summary: Label
var _coop_out: VBoxContainer
var _coop_join: VBoxContainer
var _coop_in: VBoxContainer
var _room_big: Label
var _room_players: Label
var _acct_form: VBoxContainer
var _acct_signed: HBoxContainer
var _acct_msg: Label
var _acct_status: Label
var _room_status: Label
var _email: LineEdit
var _password: LineEdit
var _room_code: LineEdit
var _name_edit: LineEdit
var _confirm_new := false
var _undo_btn: Button
var _menu_card: PanelContainer
var _redo_btn: Button
var _glass_light: ShaderMaterial
var _glass_dark: ShaderMaterial
var _glass_accent: ShaderMaterial

const INK := Color("2b3440")
const SOFT := Color("6b7785")
const CARD := Color(1, 1, 1, 0.9)
const ACCENT := Color("ff7a6b")
const MINT := Color("3fae8c")
const MENU_TABS := [["island", "Island"], ["coop", "Co-op"], ["account", "Account"], ["settings", "Settings"], ["notes", "What's new"]]
const GLASS := Color(0.9, 0.93, 0.98)
const GLASS_DARK := Color(0.1, 0.13, 0.18)


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
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = _make_theme()
	add_child(_root)
	# keep every panel and button 3% in from the left and right edges in
	# landscape (rounded corners, cut-outs); the 3D view still fills the screen
	get_viewport().size_changed.connect(_apply_side_margins)
	_apply_side_margins()
	_build_top()
	_build_fps()
	_build_toolbar()
	_build_toasts()
	_build_tutorial()
	_build_info()
	_build_menu()
	Game.stats_changed.connect(_refresh_stats)
	Game.coins_changed.connect(func(_d): pass)
	Game.tool_unlocked.connect(_on_unlocked)
	Game.title_changed.connect(_on_title)
	Game.toast.connect(func(t, k): show_toast(t, k))
	Game.world_reset.connect(_on_reset)
	Game.history_changed.connect(_refresh_history)
	Net.room_changed.connect(_refresh_players)
	Net.players_changed.connect(_refresh_players)
	Net.message.connect(func(t): show_toast(t, "info"))
	Firebase.auth_changed.connect(_refresh_account)
	world.hover_changed.connect(_on_hover)
	world.tool_failed.connect(func(r): _flash_hint(r, true))
	world.tile_tapped.connect(_on_tile_tapped)
	_coins_shown = Game.coins
	_refresh_stats()
	_refresh_tools()
	_refresh_account()
	_refresh_players()
	_update_tutorial()
	_refresh_history()


# ------------------------------------------------------------------ theme

func _glass_mat(tint: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://src/ui/glass.gdshader")
	m.set_shader_parameter("tint", tint)
	return m


## Frosted glass panel style: a soft tint, hairline white rim (brighter on top,
## like light catching the edge) and a faint drop shadow.
func _glass_box(tint := GLASS, radius := 24, pad := 14, rim := Color(1, 1, 1, 0.95), shadow := true) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = tint
	sb.set_corner_radius_all(radius)
	# 5 segments per corner already bend by under half a pixel at this radius
	sb.corner_detail = 5
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = pad * 0.7
	sb.content_margin_bottom = pad * 0.7
	sb.border_color = rim
	sb.border_width_top = 2
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_blend = true
	sb.anti_aliasing = true
	if shadow:
		sb.shadow_color = Color(0.05, 0.1, 0.2, 0.14)
		sb.shadow_size = 14
		sb.shadow_offset = Vector2(0, 6)
	return sb


func _glassify(c: Control, dark := false) -> void:
	c.material = _glass_dark if dark else _glass_light
	if c is PanelContainer:
		c.add_theme_stylebox_override("panel", _glass_box(GLASS_DARK if dark else GLASS, 24, 14, Color(1, 1, 1, 0.35) if dark else Color(1, 1, 1, 0.95)))

func _box(bg: Color, radius := 22, pad := 14, shadow := true) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.corner_detail = 5
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = pad * 0.7
	sb.content_margin_bottom = pad * 0.7
	sb.anti_aliasing = true
	if shadow:
		sb.shadow_color = Color(0.1, 0.2, 0.3, 0.16)
		sb.shadow_size = 10
		sb.shadow_offset = Vector2(0, 4)
	return sb


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = font_reg
	t.default_font_size = 20
	t.set_color("font_color", "Label", INK)
	t.set_stylebox("panel", "PanelContainer", _box(CARD))
	var b := _box(Color(1, 1, 1, 0.96), 25, 16)
	t.set_stylebox("normal", "Button", b)
	var bh := _box(Color("fff6ee"), 25, 16)
	t.set_stylebox("hover", "Button", bh)
	var bp := _box(Color("ffe3d9"), 25, 16, false)
	t.set_stylebox("pressed", "Button", bp)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_stylebox("disabled", "Button", _box(Color(0.92, 0.92, 0.92, 0.9), 25, 16, false))
	t.set_color("font_color", "Button", INK)
	t.set_color("font_hover_color", "Button", INK)
	t.set_color("font_pressed_color", "Button", INK)
	t.set_font("font", "Button", font_bold)
	var le := _box(Color("f3f5f7"), 14, 12, false)
	t.set_stylebox("normal", "LineEdit", le)
	t.set_stylebox("focus", "LineEdit", _box(Color("ffffff"), 14, 12, false))
	t.set_color("font_color", "LineEdit", INK)
	t.set_color("font_placeholder_color", "LineEdit", Color(0.6, 0.64, 0.7))
	var pb_bg := _box(Color(0.85, 0.88, 0.9, 1.0), 6, 0, false)
	var pb_fill := _box(MINT, 6, 0, false)
	t.set_stylebox("background", "ProgressBar", pb_bg)
	t.set_stylebox("fill", "ProgressBar", pb_fill)
	t.set_color("font_color", "CheckButton", INK)
	t.set_font("font", "CheckButton", font_bold)
	return t


func _label(text: String, size := 20, bold := false, col := INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font_bold if bold else font_reg)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _icon(kind: String, px := 30) -> UiIcon:
	var i := UiIcon.new(kind, INK, ACCENT)
	i.custom_minimum_size = Vector2(px, px)
	return i


# ------------------------------------------------------------------ top bar

func _build_top() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_TOP_WIDE)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	_root.add_child(margin)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)
	# city card
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
	_name_label = _label(Game.city_name, 26, true)
	name_row.add_child(_name_label)
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", _box(Color("ffe9c7"), 12, 8, false))
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_label = _label("Hamlet", 16, true, Color("b46a1f"))
	chip.add_child(_title_label)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_row.add_child(chip)
	_progress = ProgressBar.new()
	_progress.custom_minimum_size = Vector2(230, 9)
	_progress.show_percentage = false
	_progress.max_value = 1.0
	_progress.step = 0.0
	v.add_child(_progress)
	_next_label = _label("", 14, false, SOFT)
	v.add_child(_next_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)
	# co-op players
	_players_row = HBoxContainer.new()
	_players_row.add_theme_constant_override("separation", 6)
	_players_row.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(_players_row)
	var spacer2 := Control.new()
	spacer2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer2)
	# stats pills
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 10)
	stats.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(stats)
	_pop_label = _pill(stats, "people")
	_coin_label = _pill(stats, "coin")
	_happy_label = _pill(stats, "smile")
	var menu_btn := _glass_button(58)
	var mi := _icon("menu", 30)
	mi.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_btn.add_child(mi)
	menu_btn.pressed.connect(_toggle_menu)
	stats.add_child(menu_btn)


## Tiny frame-rate readout under the city card; refreshed twice a second so it costs nothing.
func _short_count(n: float) -> String:
	if n >= 1e6:
		return "%.2fM" % (n / 1e6)
	if n >= 1e3:
		return "%dk" % int(n / 1e3)
	return str(int(n))


func _build_fps() -> void:
	_fps_label = _label("", 13, true, Color(1, 1, 1, 0.9))
	_fps_label.add_theme_color_override("font_outline_color", Color(0.1, 0.14, 0.2, 0.55))
	_fps_label.add_theme_constant_override("outline_size", 4)
	_fps_label.position = Vector2(30, 112)
	_fps_label.visible = Game.settings.get("fps", true)
	_root.add_child(_fps_label)


func _pill(parent: Control, icon: String) -> Label:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glassify(p)
	p.add_theme_stylebox_override("panel", _glass_box(GLASS, 29, 14))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	p.add_child(h)
	h.add_child(_icon(icon, 28))
	var l := _label("0", 22, true)
	l.custom_minimum_size.x = 54
	h.add_child(l)
	parent.add_child(p)
	return l


func _refresh_stats() -> void:
	_pop_label.text = _short(Game.population)
	_happy_label.text = "%d%%" % int(Game.happiness * 100)
	_name_label.text = Game.city_name
	_title_label.text = Game.title
	var np := Game.next_title_progress()
	if np[0] != "":
		_next_label.text = "%s → %s" % [Game.title, np[0]]
		_progress.value = np[1]
	else:
		_next_label.text = "The finest city on the sea"
		_progress.value = 1.0
	_refresh_tools()
	_update_tutorial()


func _short(n: float) -> String:
	if n >= 10000:
		return "%.1fk" % (n / 1000.0)
	return str(int(n))


func _process(delta: float) -> void:
	_coins_shown = lerpf(_coins_shown, Game.coins, 1.0 - exp(-delta * 6.0))
	if absf(_coins_shown - Game.coins) < 0.5:
		_coins_shown = Game.coins
	_coin_label.text = _short(_coins_shown)
	if _fps_label.visible:
		_fps_time += delta
		if _fps_time >= 0.5:
			_fps_time = 0.0
			var tris := Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
			_fps_label.text = "%d FPS\n%s tris" % [Engine.get_frames_per_second(), _short_count(tris)]


# ------------------------------------------------------------------ tools

func _build_toolbar() -> void:
	var bottom := VBoxContainer.new()
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_top = -330
	bottom.offset_bottom = -10
	bottom.offset_left = 16
	bottom.offset_right = -16
	bottom.alignment = BoxContainer.ALIGNMENT_END
	bottom.add_theme_constant_override("separation", 6)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bottom)
	# undo / redo float on the left above the tools; the hint sits centred
	var over := HBoxContainer.new()
	over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	over.add_theme_constant_override("separation", 10)
	bottom.add_child(over)
	_undo_btn = _glass_button(56, "undo")
	_undo_btn.pressed.connect(_on_undo)
	over.add_child(_undo_btn)
	_redo_btn = _glass_button(56, "redo")
	_redo_btn.pressed.connect(_on_redo)
	over.add_child(_redo_btn)
	var hint_row := CenterContainer.new()
	hint_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	over.add_child(hint_row)
	var pad := Control.new()
	pad.custom_minimum_size.x = 122
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	over.add_child(pad)
	_hint_card = PanelContainer.new()
	_hint_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_card.material = _glass_dark
	_hint_card.add_theme_stylebox_override("panel", _glass_box(GLASS_DARK, 18, 16, Color(1, 1, 1, 0.3)))
	_hint = _label("", 17, true, Color.WHITE)
	_hint_card.add_child(_hint)
	_hint_card.modulate.a = 0.0
	hint_row.add_child(_hint_card)
	# the open category's sub-types float in their own row above the bar
	var sub_center := CenterContainer.new()
	sub_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(sub_center)
	_sub_wrap = sub_center
	_sub_row = HBoxContainer.new()
	_sub_row.add_theme_constant_override("separation", 8)
	_sub_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub_center.add_child(_sub_row)
	_sub_wrap.visible = false
	# no bar behind the categories: each one is its own floating glass key
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(center)
	var m := MarginContainer.new()
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 8)
	center.add_child(m)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(row)
	for c in Game.CATEGORIES:
		row.add_child(_cat_button(c))


func _tools_in(cat: String) -> Array:
	var out := []
	for t in Game.TOOLS:
		if t.cat == cat:
			out.append(t)
	return out


func _cat_of(id: String) -> String:
	return Game.tool_def(id).get("cat", "")


## The tool a category key stands for: the last one used, else its first unlocked one.
func _cat_tool(cat: String) -> String:
	if _last_tool.has(cat) and Game.is_unlocked(_last_tool[cat]):
		return _last_tool[cat]
	for t in _tools_in(cat):
		if Game.is_unlocked(t.id):
			return t.id
	return _tools_in(cat)[0].id


func _key(w: int, h: int) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(w, h)
	b.toggle_mode = true
	b.material = _glass_light
	b.pivot_offset = Vector2(w, h) * 0.5
	b.add_theme_stylebox_override("normal", _glass_box(GLASS, 26, 4))
	b.add_theme_stylebox_override("hover", _glass_box(Color(0.97, 0.98, 1.0), 26, 4))
	b.add_theme_stylebox_override("pressed", _glass_box(Color(1, 0.62, 0.55), 26, 4, Color.WHITE))
	b.add_theme_stylebox_override("hover_pressed", _glass_box(Color(1, 0.62, 0.55), 26, 4, Color.WHITE))
	b.add_theme_stylebox_override("disabled", _glass_box(GLASS, 26, 4))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.button_down.connect(func(): _squish(b, 0.92))
	return b


func _cat_button(c: Dictionary) -> Control:
	var b := _key(80, 84)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", -2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var ic := _icon(_cat_tool(c.id), 44)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(ic)
	var cl := _label(c.name, 13, true, INK)
	cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(cl)
	b.pressed.connect(_on_cat_pressed.bind(c.id))
	_cat_buttons[c.id] = {"button": b, "icon": ic, "label": cl}
	return b


## A round glass key holding only an icon (menu, undo, redo).
func _glass_button(px: int, icon := "menu") -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(px, px)
	b.material = _glass_light
	var r := px / 2
	b.add_theme_stylebox_override("normal", _glass_box(GLASS, r, 0))
	b.add_theme_stylebox_override("hover", _glass_box(Color(0.97, 0.98, 1.0), r, 0))
	b.add_theme_stylebox_override("pressed", _glass_box(Color(1, 0.88, 0.84), r, 0, Color.WHITE, false))
	b.add_theme_stylebox_override("disabled", _glass_box(GLASS, r, 0, Color(1, 1, 1, 0.4), false))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var ic := _icon(icon, int(px * 0.5))
	ic.set_anchors_preset(Control.PRESET_FULL_RECT)
	b.add_child(ic)
	b.pivot_offset = Vector2(px, px) * 0.5
	b.button_down.connect(func(): _squish(b, 0.9))
	b.button_up.connect(func(): _squish(b, 1.0))
	return b


func _squish(c: Control, to: float) -> void:
	var tw := create_tween()
	tw.tween_property(c, "scale", Vector2(to, to), 0.12 if to < 1.0 else 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _tool_button(t: Dictionary) -> Control:
	var b := _key(84, 96)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", -3)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var ic := _icon(t.id, 42)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(ic)
	var nl := _label(t.name, 11, true, INK)
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nl.clip_text = true
	nl.custom_minimum_size.x = 78
	v.add_child(nl)
	var cl := _label("", 13, true, SOFT)
	cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(cl)
	b.pressed.connect(_on_tool_pressed.bind(t.id))
	_tool_buttons[t.id] = {"button": b, "icon": ic, "cost": cl, "name": nl}
	return b


## Fills the floating row with the open category's sub-types.
func _show_subs(cat: String) -> void:
	for c in _sub_row.get_children():
		c.queue_free()
	_tool_buttons.clear()
	_open_cat = cat
	var tools := _tools_in(cat) if cat != "" and cat != "clear" else []
	_sub_wrap.visible = tools.size() > 0
	var k := 0
	for t in tools:
		var b := _tool_button(t)
		_sub_row.add_child(b)
		# keys rise into place one after another
		b.modulate.a = 0.0
		b.position.y = 20.0
		var tw := create_tween()
		tw.tween_interval(k * 0.025)
		tw.tween_property(b, "modulate:a", 1.0, 0.16)
		k += 1


func _refresh_tools() -> void:
	for c in Game.CATEGORIES:
		var e: Dictionary = _cat_buttons.get(c.id, {})
		if e.is_empty():
			continue
		var any := false
		var cheapest := 1 << 30
		for t in _tools_in(c.id):
			if Game.is_unlocked(t.id):
				any = true
			cheapest = mini(cheapest, t.unlock)
		var ic: UiIcon = e.icon
		ic.set_kind(_cat_tool(c.id) if any else "lock")
		ic.color = SOFT
		e.label.text = c.name if any else "%d pop" % cheapest
		var open: bool = _open_cat == c.id or (c.id == "clear" and _selected == "bulldoze")
		e.button.button_pressed = open
		e.button.modulate = Color(1, 1, 1, 1) if any else Color(1, 1, 1, 0.6)
		e.label.add_theme_color_override("font_color", Color.WHITE if open else (INK if any else SOFT))
		_lift(e.button, open)
	for t in _tools_in(_open_cat):
		var e: Dictionary = _tool_buttons.get(t.id, {})
		if e.is_empty():
			continue
		var unlocked := Game.is_unlocked(t.id)
		var ic: UiIcon = e.icon
		ic.set_kind(t.id if unlocked else "lock")
		ic.color = SOFT
		e.cost.text = ("%d" % t.cost if t.cost > 0 else "free") if unlocked else "%d pop" % t.unlock
		e.button.modulate = Color(1, 1, 1, 1) if unlocked else Color(1, 1, 1, 0.6)
		var sel: bool = _selected == t.id
		e.button.button_pressed = sel
		e.cost.add_theme_color_override("font_color", Color.WHITE if sel else (INK if unlocked else SOFT))
		e.name.add_theme_color_override("font_color", Color.WHITE if sel else (INK if unlocked else SOFT))
		_lift(e.button, sel)


## PS5-style focus: the chosen key lifts and grows, the rest settle.
func _lift(b: Button, on: bool) -> void:
	var target := Vector2(1.1, 1.1) if on else Vector2.ONE
	if b.scale != target and b.is_inside_tree():
		var tw := create_tween()
		tw.tween_property(b, "scale", target, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _refresh_history() -> void:
	if _undo_btn == null:
		return
	_undo_btn.disabled = not Game.can_undo()
	_redo_btn.disabled = not Game.can_redo()
	_undo_btn.modulate.a = 1.0 if Game.can_undo() else 0.45
	_redo_btn.modulate.a = 1.0 if Game.can_redo() else 0.45


func _on_undo() -> void:
	if Game.undo():
		Sfx.play("pop", 0.8, -3.0)
		_flash_hint("Undone · coins refunded", false, 1.2)
	_refresh_history()


func _on_redo() -> void:
	if Game.redo():
		Sfx.play("pop", 1.2, -3.0)
		_flash_hint("Redone", false, 1.0)
	_refresh_history()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_F11 or (event.alt_pressed and event.keycode == KEY_ENTER)):
		var w := get_window()
		w.mode = Window.MODE_WINDOWED if w.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and (event.ctrl_pressed or event.meta_pressed) and event.keycode == KEY_Z:
		if event.shift_pressed:
			_on_redo()
		else:
			_on_undo()
		get_viewport().set_input_as_handled()


func _on_cat_pressed(cat: String) -> void:
	Sfx.play("click")
	_info.visible = false
	if cat == "clear":
		_show_subs("")
		_select("" if _selected == "bulldoze" else "bulldoze")
		return
	if _open_cat == cat:
		# a second tap folds the row away and puts the tool down
		_show_subs("")
		_select("")
		return
	_show_subs(cat)
	var id := _cat_tool(cat)
	if Game.is_unlocked(id):
		_select(id)
	else:
		_select("")
		var def := Game.tool_def(id)
		_flash_hint("%s unlocks at %d citizens" % [def.name, def.unlock], true)


func _on_tool_pressed(id: String) -> void:
	Sfx.play("click")
	if not Game.is_unlocked(id):
		var def := Game.tool_def(id)
		_flash_hint("%s unlocks at %d citizens" % [def.name, def.unlock], true)
		_tool_buttons[id].button.button_pressed = false
		return
	_select("" if _selected == id else id)
	_info.visible = false


func _select(id: String) -> void:
	_selected = id
	world.set_tool(_selected)
	if id != "":
		_last_tool[_cat_of(id)] = id
	_refresh_tools()
	if _selected != "":
		var def := Game.tool_def(id)
		_flash_hint("%s  ·  %s" % [def.name, def.desc], false, 3.5)


func _flash_hint(text: String, warn := false, secs := 2.2) -> void:
	_hint.text = text
	_hint_card.add_theme_stylebox_override("panel", _glass_box(Color(0.85, 0.3, 0.27) if warn else GLASS_DARK, 18, 16, Color(1, 1, 1, 0.3)))
	var tw := create_tween()
	tw.tween_property(_hint_card, "modulate:a", 1.0, 0.15)
	tw.tween_interval(secs)
	tw.tween_property(_hint_card, "modulate:a", 0.0, 0.4)


func _on_hover(_t: Vector2i, _reason: String) -> void:
	pass


# ------------------------------------------------------------------ toasts

func _build_toasts() -> void:
	_toasts = VBoxContainer.new()
	_toasts.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toasts.offset_top = 110
	_toasts.offset_left = -260
	_toasts.offset_right = 260
	_toasts.alignment = BoxContainer.ALIGNMENT_BEGIN
	_toasts.add_theme_constant_override("separation", 8)
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_toasts)


func show_toast(text: String, kind := "info") -> void:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := GLASS
	var col := INK
	var size := 19
	p.material = _glass_light
	if kind == "unlock":
		bg = GLASS_DARK
		col = Color("ffe9c7")
		size = 24
		p.material = _glass_dark
	elif kind == "title":
		bg = ACCENT
		col = Color.WHITE
		size = 26
		p.material = _glass_accent
	elif kind == "warn":
		bg = Color(0.85, 0.3, 0.27)
		col = Color.WHITE
		p.material = _glass_accent
	p.add_theme_stylebox_override("panel", _glass_box(bg, 24, 18, Color(1, 1, 1, 0.5 if bg == GLASS_DARK else 0.95)))
	var l := _label(text, size, true, col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	_toasts.add_child(p)
	p.pivot_offset = Vector2(260, 24)
	p.scale = Vector2(0.6, 0.6)
	p.modulate.a = 0.0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(p, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(p, "modulate:a", 1.0, 0.2)
	tw.chain().tween_interval(3.2 if kind != "info" else 2.2)
	tw.chain().tween_property(p, "modulate:a", 0.0, 0.5)
	tw.chain().tween_callback(p.queue_free)


func _on_unlocked(id: String) -> void:
	var def := Game.tool_def(id)
	show_toast("New: %s unlocked!" % def.name, "unlock")
	Sfx.play("unlock")
	_confetti()
	_refresh_tools()
	# the new tool's category key bounces (and the key itself, if its row is open)
	var e: Dictionary = _tool_buttons.get(id, _cat_buttons.get(_cat_of(id), {}))
	if e.is_empty():
		return
	var b: Button = e.button
	b.pivot_offset = b.size * 0.5
	var tw := create_tween()
	for k in 3:
		tw.tween_property(b, "scale", Vector2(1.15, 1.15), 0.15)
		tw.tween_property(b, "scale", Vector2.ONE, 0.15)


func _on_title(title: String) -> void:
	show_toast("%s is now a %s!" % [Game.city_name, title], "title")
	Sfx.play("unlock", 0.8)
	_confetti()


func _confetti() -> void:
	var p := CPUParticles2D.new()
	p.position = Vector2(_root.size.x * 0.5, -20)
	p.amount = 90
	p.one_shot = true
	p.explosiveness = 0.9
	p.lifetime = 2.6
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(_root.size.x * 0.4, 10)
	p.direction = Vector2(0, 1)
	p.spread = 30.0
	p.initial_velocity_min = 200.0
	p.initial_velocity_max = 420.0
	p.gravity = Vector2(0, 260)
	p.angular_velocity_min = -400.0
	p.angular_velocity_max = 400.0
	p.scale_amount_min = 6.0
	p.scale_amount_max = 11.0
	var grad := Gradient.new()
	grad.set_color(0, Color("ff7a6b"))
	grad.set_color(1, Color("5fb8ff"))
	grad.add_point(0.33, Color("ffc94d"))
	grad.add_point(0.66, Color("7be08f"))
	p.color_initial_ramp = grad
	_root.add_child(p)
	p.emitting = true
	get_tree().create_timer(3.0).timeout.connect(p.queue_free)


# ------------------------------------------------------------------ tutorial

func _build_tutorial() -> void:
	_tutorial = PanelContainer.new()
	_tutorial.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	_tutorial.offset_left = 18
	_tutorial.offset_top = -40
	_tutorial.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glassify(_tutorial)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	_tutorial.add_child(h)
	h.add_child(_icon("hand", 34))
	_tutorial_label = _label("", 17, true)
	_tutorial_label.custom_minimum_size.x = 260
	_tutorial_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	h.add_child(_tutorial_label)
	_root.add_child(_tutorial)


func _update_tutorial() -> void:
	if _tutorial == null:
		return
	var texts := [
		"Tap Roads and drag a street across the grass.",
		"Now open Homes and paint houses right beside the road.",
		"Watch your homes grow! Add shops and parks to help them thrive.",
	]
	if Game.tutorial_step < texts.size() and not Net.in_room():
		_tutorial.visible = true
		_tutorial_label.text = texts[Game.tutorial_step]
	else:
		_tutorial.visible = false


# ------------------------------------------------------------------ tile info

func _build_info() -> void:
	_info = PanelContainer.new()
	_info.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_info.offset_left = -320
	_info.offset_right = -18
	_info.offset_top = -60
	_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glassify(_info)
	_info_label = _label("", 17, false)
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_label.custom_minimum_size.x = 270
	_info.add_child(_info_label)
	_info.visible = false
	_root.add_child(_info)


func _on_tile_tapped(t: Vector2i) -> void:
	if not Game.inside(t.x, t.y):
		_info.visible = false
		return
	var k := Game.knd(t.x, t.y)
	var g := Game.grw(t.x, t.y)
	var names := {Game.K.HOUSE: [["Cottage", "Townhouse", "Apartments"], ["Row house", "Terrace", "Brownstones"], ["Bungalow", "Villa", "Mansion"], ["Flats", "Apartment block", "High-rise flats"]],
		Game.K.SHOP: [["Corner shop", "High street shop", "Department store"], ["Café", "Bistro", "Rooftop restaurant"], ["Market stalls", "Covered market", "Market hall"], ["Store", "Department store", "Shopping centre"]],
		Game.K.OFFICE: [["Studio offices", "Office tower", "Skyscraper"], ["Workshop", "Studios", "Campus"], ["Guesthouse", "Hotel", "Grand hotel"]]}
	var text := ""
	if Game.is_building(k):
		if g == 0:
			text = "Building site\nNeeds a road right next to it to start building."
		else:
			text = "%s  ·  level %d\n" % [names[k][Game.sub(t.x, t.y)][g - 1], g]
			var target := Game.target_growth(t.x, t.y)
			if g < 3:
				if target > g:
					text += "Growing soon!"
				elif g == 1 and Game.population < 30:
					text += "Grows taller once the city reaches 30 citizens."
				elif g == 2 and Game.population < 220:
					text += "Grows taller once the city reaches 220 citizens."
				else:
					text += "Add parks, shops and neighbours nearby to grow."
			else:
				text += "Fully grown. Lovely!"
	elif k == Game.K.LANDMARK:
		text = "%s\nLifts happiness and helps nearby buildings grow." % Game.tool_at(t.x, t.y).get("name", "Landmark")
	elif k == Game.K.PARK:
		text = "%s\nNeighbours within 3 tiles grow faster." % Game.tool_at(t.x, t.y).get("name", "Park")
	else:
		_info.visible = false
		return
	_info_label.text = text
	_info.visible = true
	Sfx.play("click", 1.2)


# ------------------------------------------------------------------ players

func _refresh_players() -> void:
	for c in _players_row.get_children():
		c.queue_free()
	if not Net.in_room():
		_update_tutorial()
		_refresh_account()
		return
	var chip := PanelContainer.new()
	_glassify(chip)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	chip.add_child(h)
	h.add_child(_icon("globe", 22))
	h.add_child(_label("Room %s" % Net.room_code, 17, true))
	for p in Net.active_players():
		var dot := PanelContainer.new()
		dot.add_theme_stylebox_override("panel", _box(Color(str(p.get("color", "ffffff"))), 10, 8, false))
		dot.add_child(_label(str(p.get("name", "?")), 14, true, Color.WHITE))
		h.add_child(dot)
	_players_row.add_child(chip)
	_refresh_account()


# ------------------------------------------------------------------ menu

func _toggle_menu() -> void:
	Sfx.play("click")
	_set_menu(not _menu.visible)


func _set_menu(open: bool) -> void:
	if open == _menu.visible:
		return
	_menu.visible = open
	_confirm_new = false
	_new_btn.text = "Start a new island"
	if open:
		_name_edit.text = Game.player_name
		_show_page(_page)
		# springy sheet entrance
		_menu_card.pivot_offset = _menu_card.size * 0.5
		_menu_card.scale = Vector2(0.92, 0.92)
		_menu.modulate.a = 0.0
		var tw := create_tween().set_parallel(true)
		tw.tween_property(_menu_card, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(_menu, "modulate:a", 1.0, 0.18)
	else:
		_name_edit.release_focus()
		Game.save_local()


func _notification(what: int) -> void:
	# Android back gesture closes the menu first
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and _menu != null and _menu.visible:
		_set_menu(false)


func _input(event: InputEvent) -> void:
	if _menu != null and _menu.visible and event.is_action_pressed("ui_cancel"):
		_set_menu(false)
		get_viewport().set_input_as_handled()


func _section(parent: Control, title: String) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.add_child(_label(title, 18, true, ACCENT))
	parent.add_child(v)
	return v


func _button(text: String, cb: Callable, primary := false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 50)
	b.add_theme_font_size_override("font_size", 18)
	if primary:
		b.add_theme_stylebox_override("normal", _box(ACCENT, 25, 16))
		b.add_theme_stylebox_override("hover", _box(ACCENT.lightened(0.1), 25, 16))
		b.add_theme_stylebox_override("pressed", _box(ACCENT.darkened(0.1), 25, 16, false))
		b.add_theme_color_override("font_color", Color.WHITE)
		b.add_theme_color_override("font_hover_color", Color.WHITE)
		b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.pressed.connect(func():
		Sfx.play("click")
		cb.call())
	return b


func _wrap_label(text: String, size := 16, bold := false, col := SOFT) -> Label:
	var l := _label(text, size, bold, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 200
	return l


## One page of the menu: a scrollable column that only shows when its tab is picked.
func _page_box(id: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_pages_root.add_child(scroll)
	var m := MarginContainer.new()
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.add_theme_constant_override("margin_right", 4)
	scroll.add_child(m)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 20)
	m.add_child(v)
	_pages[id] = scroll
	return v


func _apply_side_margins() -> void:
	var size := get_viewport().get_visible_rect().size
	var m := 0.03 if size.x > size.y else 0.0
	_root.anchor_left = m
	_root.anchor_right = 1.0 - m
	_root.offset_left = 0
	_root.offset_right = 0


func _build_menu() -> void:
	_menu = Control.new()
	_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu.visible = false
	_root.add_child(_menu)
	var dim := ColorRect.new()
	dim.color = Color(0.06, 0.09, 0.14, 0.35)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	# the dimmer still covers the whole screen, past the side margins
	dim.offset_left = -400
	dim.offset_right = 400
	dim.gui_input.connect(func(e):
		if (e is InputEventMouseButton and e.pressed) or (e is InputEventScreenTouch and e.pressed):
			_toggle_menu())
	_menu.add_child(dim)
	var card := PanelContainer.new()
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.offset_left = -380
	card.offset_right = 380
	card.offset_top = -300
	card.offset_bottom = 300
	_menu_card = card
	card.material = _glass_mat(0.72)
	card.add_theme_stylebox_override("panel", _glass_box(Color(0.96, 0.97, 0.99), 34, 28))
	_menu.add_child(card)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 14)
	card.add_child(outer)

	# header: title + close
	var head := HBoxContainer.new()
	outer.add_child(head)
	var t := _label("City Views", 30, true)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var close := _glass_button(48, "close")
	close.pressed.connect(_toggle_menu)
	head.add_child(close)

	# segmented tabs, iOS style
	var track := PanelContainer.new()
	track.add_theme_stylebox_override("panel", _box(Color(0.2, 0.25, 0.32, 0.08), 24, 4, false))
	outer.add_child(track)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	track.add_child(tabs)
	var group := ButtonGroup.new()
	for tab in MENU_TABS:
		var tb := Button.new()
		tb.text = tab[1]
		tb.toggle_mode = true
		tb.button_group = group
		tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tb.custom_minimum_size.y = 42
		tb.add_theme_font_size_override("font_size", 17)
		tb.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		tb.add_theme_stylebox_override("hover", _box(Color(1, 1, 1, 0.4), 20, 8, false))
		tb.add_theme_stylebox_override("pressed", _box(Color.WHITE, 20, 8))
		tb.add_theme_stylebox_override("hover_pressed", _box(Color.WHITE, 20, 8))
		tb.add_theme_color_override("font_color", SOFT)
		tb.add_theme_color_override("font_hover_color", INK)
		tb.add_theme_color_override("font_pressed_color", INK)
		tb.add_theme_color_override("font_hover_pressed_color", INK)
		tb.pressed.connect(func():
			Sfx.play("click", 1.1, -4.0)
			_show_page(tab[0]))
		tabs.add_child(tb)
		_tab_buttons[tab[0]] = tb

	_pages_root = VBoxContainer.new()
	_pages_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(_pages_root)

	# ---- island
	var island := _page_box("island")
	var prof := _section(island, "Your name")
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Mayor"
	_name_edit.max_length = 16
	_name_edit.text_changed.connect(func(s):
		Game.player_name = s if s.strip_edges() != "" else "Mayor")
	prof.add_child(_name_edit)
	prof.add_child(_wrap_label("Other builders see this name next to your cursor."))
	var about := _section(island, "This island")
	_island_summary = _wrap_label("", 17, true, INK)
	about.add_child(_island_summary)
	_new_btn = _button("Start a new island", func(): pass)
	_new_btn.pressed.connect(_on_new_island)
	about.add_child(_new_btn)
	about.add_child(_wrap_label("Starting over replaces this city with a fresh island. Tap twice to confirm."))

	# ---- co-op
	var coop := _page_box("coop")
	_coop_out = _section(coop, "Build together")
	_coop_out.add_child(_wrap_label("Host your city and share the code, and up to 3 friends can build on it with you in real time."))
	_coop_out.add_child(_button("Host this city", _host, true))
	var jl := _section(coop, "Join a friend")
	_coop_join = jl
	var crow := HBoxContainer.new()
	crow.add_theme_constant_override("separation", 8)
	jl.add_child(crow)
	_room_code = LineEdit.new()
	_room_code.placeholder_text = "Room code"
	_room_code.max_length = 6
	_room_code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_room_code.text_submitted.connect(func(_s): _join())
	crow.add_child(_room_code)
	var jb := _button("Join", _join)
	jb.custom_minimum_size.x = 120
	crow.add_child(jb)
	_coop_in = _section(coop, "You're in a room")
	_room_big = _label("", 44, true, INK)
	_coop_in.add_child(_room_big)
	_room_players = _wrap_label("", 17, true, INK)
	_coop_in.add_child(_room_players)
	_coop_in.add_child(_button("Leave room", func():
		Net.leave_room()
		_room_status.text = "You left the room. This is your own city again."
		_refresh_account()))
	_room_status = _wrap_label("", 16, true, MINT)
	coop.add_child(_room_status)

	# ---- account
	var acct := _page_box("account")
	var asec := _section(acct, "Account & cloud saves")
	_acct_status = _wrap_label("")
	asec.add_child(_acct_status)
	_acct_form = VBoxContainer.new()
	_acct_form.add_theme_constant_override("separation", 8)
	asec.add_child(_acct_form)
	_email = LineEdit.new()
	_email.placeholder_text = "Email"
	_email.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_EMAIL_ADDRESS
	_acct_form.add_child(_email)
	_password = LineEdit.new()
	_password.placeholder_text = "Password (6+ characters)"
	_password.secret = true
	_password.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_PASSWORD
	_password.text_submitted.connect(func(_s): _sign_in())
	_acct_form.add_child(_password)
	var arow := HBoxContainer.new()
	arow.add_theme_constant_override("separation", 8)
	_acct_form.add_child(arow)
	var si := _button("Sign in", _sign_in)
	si.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	arow.add_child(si)
	var reg := _button("Create account", _register, true)
	reg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	arow.add_child(reg)
	_acct_signed = HBoxContainer.new()
	_acct_signed.add_theme_constant_override("separation", 8)
	asec.add_child(_acct_signed)
	var save := _button("Save to cloud now", func():
		if Firebase.signed_in:
			Firebase.save_city(Game.to_dict())
			_acct_msg.text = "Saved to the cloud ✓"
		else:
			_acct_msg.text = "Not connected yet, try again in a moment")
	save.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_acct_signed.add_child(save)
	var so := _button("Sign out", func():
		await Firebase.sign_out()
		_acct_msg.text = "Signed out. You're playing as a guest."
		_refresh_account())
	so.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_acct_signed.add_child(so)
	_acct_msg = _wrap_label("", 16, true, MINT)
	acct.add_child(_acct_msg)

	# ---- settings
	var st := _section(_page_box("settings"), "Settings")
	for key in [["music", "Music"], ["sfx", "Sound effects"], ["shadows", "Shadows"], ["fps", "Show FPS & triangles"]]:
		var cb := CheckButton.new()
		cb.text = key[1]
		cb.add_theme_font_size_override("font_size", 18)
		cb.custom_minimum_size.y = 54
		var row := _box(Color(1, 1, 1, 0.85), 18, 16, false)
		for st_name in ["normal", "pressed", "hover", "hover_pressed"]:
			cb.add_theme_stylebox_override(st_name, row)
		cb.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		for c in ["font_color", "font_pressed_color", "font_hover_color", "font_hover_pressed_color"]:
			cb.add_theme_color_override(c, INK)
		cb.add_theme_icon_override("checked", _switch_icon(true))
		cb.add_theme_icon_override("unchecked", _switch_icon(false))
		cb.button_pressed = Game.settings.get(key[0], true)
		cb.toggled.connect(func(on):
			Game.settings[key[0]] = on
			match key[0]:
				"shadows": world.sun.shadow_enabled = on
				"fps": _fps_label.visible = on
			Game.save_local())
		st.add_child(cb)

	# ---- what's new
	var notes := _page_box("notes")
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.scroll_active = false
	rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rt.add_theme_font_override("normal_font", font_reg)
	rt.add_theme_font_override("bold_font", font_bold)
	rt.add_theme_font_size_override("normal_font_size", 16)
	rt.add_theme_font_size_override("bold_font_size", 17)
	rt.add_theme_color_override("default_color", INK)
	rt.text = _patch_notes_bbcode()
	notes.add_child(rt)
	_show_page("island")


## iOS-style switch drawn once into a texture: green pill with the knob right when on.
func _switch_icon(on: bool) -> Texture2D:
	var w := 56
	var h := 32
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	var track := MINT if on else Color(0.78, 0.8, 0.84)
	var r := h * 0.5
	var knob := Vector2(w - r, r) if on else Vector2(r, r)
	for y in h:
		for x in w:
			var p := Vector2(x + 0.5, y + 0.5)
			var cx := clampf(p.x, r, w - r)
			var d := p.distance_to(Vector2(cx, r)) - r
			var a := clampf(0.5 - d, 0.0, 1.0)
			var col := track
			var kd := p.distance_to(knob) - (r - 3.0)
			var ka := clampf(0.5 - kd, 0.0, 1.0)
			col = col.lerp(Color.WHITE, ka)
			img.set_pixel(x, y, Color(col.r, col.g, col.b, a))
	return ImageTexture.create_from_image(img)


func _show_page(id: String) -> void:
	_page = id
	for k in _pages:
		_pages[k].visible = k == id
		_tab_buttons[k].button_pressed = k == id
	_pages[id].scroll_vertical = 0
	_refresh_account()


func _on_new_island() -> void:
	if not _confirm_new:
		_confirm_new = true
		_new_btn.text = "Tap again to start over"
		return
	_confirm_new = false
	_new_btn.text = "Start a new island"
	if Net.in_room():
		Net.leave_room()
	Game.new_world(randi() % 1000000)
	Game.save_local()
	_set_menu(false)


func _patch_notes_bbcode() -> String:
	var path := "res://PATCH_NOTES.md"
	if not FileAccess.file_exists(path):
		return ""
	var out := ""
	var count := 0
	for line in FileAccess.get_file_as_string(path).split("\n"):
		if line.begins_with("## "):
			count += 1
			if count > 6:
				break
			out += "\n[b]%s[/b]\n" % line.substr(3)
		elif line.begins_with("- "):
			out += "  •  %s\n" % line.substr(2)
	return out.strip_edges()


func _host() -> void:
	_room_status.text = "Creating room…"
	var err: String = await Net.create_room()
	_room_status.text = err if err != "" else "Room open! Share the code with up to 3 friends."
	_refresh_account()


func _join() -> void:
	if _room_code.text.strip_edges() == "":
		_room_status.text = "Type the room code your friend shared"
		return
	_room_status.text = "Joining…"
	var err: String = await Net.join_room(_room_code.text)
	_room_status.text = err
	_refresh_account()
	if err == "":
		_room_code.text = ""
		_set_menu(false)


func _sign_in() -> void:
	_acct_msg.text = "Signing in…"
	var err: String = await Firebase.sign_in_email(_email.text.strip_edges(), _password.text)
	_acct_msg.text = err if err != "" else "Welcome back!"
	_password.text = ""
	_refresh_account()


func _register() -> void:
	_acct_msg.text = "Creating account…"
	var err: String = await Firebase.register_email(_email.text.strip_edges(), _password.text)
	_acct_msg.text = err if err != "" else "Account created. Your city is saved to the cloud."
	_password.text = ""
	_refresh_account()


## Shows only the controls that make sense right now (in a room or not, guest or signed in).
func _refresh_account() -> void:
	if _acct_status == null:
		return
	var online := Firebase.enabled and Firebase.signed_in
	if not Firebase.enabled:
		_acct_status.text = "Online services aren't set up in this build, so your city is saved on this device."
	elif not Firebase.signed_in:
		_acct_status.text = "Connecting…"
	elif Firebase.is_guest:
		_acct_status.text = "Playing as a guest. Your city is backed up, but create an account to keep it across phones."
	else:
		_acct_status.text = "Signed in as %s. Your city syncs to the cloud automatically." % Firebase.email
	_acct_form.visible = online and Firebase.is_guest
	_acct_signed.visible = online and not Firebase.is_guest
	var in_room := Net.in_room()
	_coop_out.visible = not in_room
	_coop_join.visible = not in_room
	_coop_in.visible = in_room
	if in_room:
		_room_big.text = Net.room_code
		var names := []
		for p in Net.active_players():
			names.append(str(p.get("name", "?")))
		_room_players.text = "Building now: %s" % ", ".join(names) if not names.is_empty() else "Waiting for friends to join…"
	if _island_summary:
		_island_summary.text = "%s  ·  %s\n%s citizens  ·  %s coins" % [Game.city_name, Game.title, _short(Game.population), _short(Game.coins)]


func _on_reset() -> void:
	_refresh_stats()
	_info.visible = false
