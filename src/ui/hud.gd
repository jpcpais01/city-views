class_name Hud
extends CanvasLayer

## The whole interface, built in code: the island card with its title and
## stats, the brushes, goals, toasts, co-op player chips and the main menu,
## all in the same frosted glass.


const BRUSH_INFO := {
	"street": ["Street", "Draw a line: the street lays itself over the land"],
	"grow": ["Grow", "Paint beside a street: new streets and houses branch off it"],
	"green": ["Green", "Paint parks and gardens: the town keeps them green instead of building"],
	"clear": ["Clear", "Drag to take streets away and stop the town growing there"],
	"raise": ["Raise", "Drag to lift hills out of the land"],
	"lower": ["Lower", "Drag to carve valleys, coves and bays"],
	"smooth": ["Smooth", "Drag to soften bumps and rough slopes"],
	"flatten": ["Flatten", "Drag to level the ground to where you started"],
}
const ICONS := {"street": "road", "grow": "house", "green": "park", "clear": "bulldoze"}
const SIZES := [["S", 3.0], ["M", 5.0], ["L", 8.5]]
const LEVELS := ["Village", "Town", "City", "Centre"]

var island: IslandWorld
var _brush_keys := {}
var _size_btn: Button
var _size_i := 1
var _level_bar: Control
var _level_keys: Array[Button] = []
var _help: Label
var _title_chip: Label
var _locks := {}

var font_bold: FontVariation
var font_reg: FontVariation
var _root: Control
var _pop_label: Label
var _coin_label: Label
var _progress: ProgressBar
var _toasts: VBoxContainer
var _players_row: HBoxContainer
var _menu: Control
var _coins_shown := 0.0
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
var _goals: PanelContainer
var _goal_rows: VBoxContainer
var _goal_count: Label
var _goals_open := true
var _glass_light: ShaderMaterial
var _glass_dark: ShaderMaterial
var _glass_accent: ShaderMaterial
# photo mode: everything but one faint button hidden, brush put down meanwhile
var _photo := false
var _photo_exit: Button
var _photo_brush := ""
var _photo_hidden: Array[Control] = []

const INK := Color("2b3440")
const SOFT := Color("6b7785")
const CARD := Color(1, 1, 1, 0.9)
const ACCENT := Color("ff7a6b")
const MINT := Color("3fae8c")
const MENU_TABS := [["island", "Island"], ["coop", "Co-op"], ["account", "Account"], ["settings", "Settings"], ["notes", "What's new"]]
const GLASS := Color(0.9, 0.93, 0.98)
const GLASS_DARK := Color(0.1, 0.13, 0.18)


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


# ------------------------------------------------------------------ island

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
	_build_toasts()
	_build_goals()
	_build_menu()
	_build_photo_exit()
	island.brush_changed.connect(_refresh_brushes)
	island.note.connect(func(t, k): show_toast(t, k))
	var pr := island.progress
	pr.stats_changed.connect(_refresh_stats)
	pr.goals_changed.connect(_refresh_goals)
	pr.goal_ready.connect(_on_goal_ready)
	pr.unlocked.connect(_on_brush_unlocked)
	pr.title_changed.connect(_on_title)
	_coins_shown = pr.coins
	_refresh_stats()
	_refresh_goals()
	Net.room_changed.connect(_refresh_players)
	Net.players_changed.connect(_refresh_players)
	Net.message.connect(func(t): _help.text = t)
	Firebase.auth_changed.connect(_refresh_account)
	_refresh_brushes()
	_refresh_account()
	_refresh_players()


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
	name_row.add_child(_label("Your island", 26, true))
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", _box(Color("ffe9c7"), 12, 8, false))
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_title_chip = _label("Hamlet", 16, true, Color("b46a1f"))
	chip.add_child(_title_chip)
	name_row.add_child(chip)
	_progress = ProgressBar.new()
	_progress.custom_minimum_size = Vector2(230, 7)
	_progress.show_percentage = false
	_progress.max_value = 1.0
	_progress.step = 0.0
	_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_progress)
	_help = _label("Draw streets, or shape the land: pick a brush", 14, false, SOFT)
	v.add_child(_help)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)
	_players_row = HBoxContainer.new()
	_players_row.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_players_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_players_row)
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 10)
	stats.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(stats)
	_pop_label = _pill(stats, "people")
	_coin_label = _pill(stats, "coin")
	var photo_btn := _glass_button(58, "camera")
	photo_btn.pressed.connect(func(): set_photo(true))
	photo_btn.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	stats.add_child(photo_btn)
	var menu_btn := _glass_button(58)
	var mi := _icon("menu", 30)
	mi.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_btn.add_child(mi)
	menu_btn.pressed.connect(_toggle_menu)
	menu_btn.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	stats.add_child(menu_btn)


## The menu's first page: your name, this island and starting over.
func _build_world_page(page: VBoxContainer) -> void:
	var prof := _section(page, "Your name")
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Mayor"
	_name_edit.max_length = 16
	_name_edit.text_changed.connect(func(t):
		Game.player_name = t if t.strip_edges() != "" else "Mayor")
	prof.add_child(_name_edit)
	prof.add_child(_wrap_label("Builders in your co-op room see this name."))
	var about := _section(page, "This island")
	_island_summary = _wrap_label("", 17, true, INK)
	about.add_child(_island_summary)
	_new_btn = _button("Start a new island", func(): pass)
	_new_btn.pressed.connect(_on_new_island)
	about.add_child(_new_btn)
	about.add_child(_wrap_label("A fresh landscape replaces this island. Tap twice to confirm."))


func _world_summary() -> String:
	var pr := island.progress
	return "%d residents in %d homes  ·  %d shops  ·  %d parks  ·  %d m of streets\nThe town pays %s coins every few seconds" % [
		pr.residents, pr.homes, pr.shops, pr.parks, int(pr.street_m), str(pr.income())]


func _refresh_stats() -> void:
	var pr := island.progress
	_pop_label.text = _short(pr.residents)
	_title_chip.text = pr.title
	_progress.value = pr.next_title()[1]
	_refresh_locks()


func _on_title(title: String) -> void:
	show_toast("Your island is now a %s!" % title, "title")
	Sfx.play("unlock", 0.8)
	_confetti()


func _on_brush_unlocked(id: String) -> void:
	show_toast("New brush: %s" % BRUSH_INFO[id][0], "unlock")
	Sfx.play("unlock")
	_confetti()
	_refresh_locks()
	var b: Button = _brush_keys[id]
	b.pivot_offset = b.size * 0.5
	var tw := create_tween()
	tw.tween_property(b, "scale", Vector2(1.2, 1.2), 0.15).set_trans(Tween.TRANS_BACK)
	tw.tween_property(b, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK)


## Brushes the town hasn't grown into yet are dimmed, with a little lock.
func _refresh_locks() -> void:
	for id in _locks:
		var open := island.progress.can_use(id)
		_locks[id].visible = not open
		_brush_keys[id].modulate.a = 1.0 if open else 0.55


func _goal_list() -> Array:
	return island.progress.goals


func _goal_frac(g: Dictionary) -> float:
	return island.progress.goal_progress(g)


func _goals_done() -> int:
	return island.progress.goals_done


func _claim(i: int) -> float:
	return island.progress.claim_goal(i)


func _save_cloud() -> void:
	island.save_cloud()


func _on_new_island() -> void:
	if not _confirm_new:
		_confirm_new = true
		_new_btn.text = "Tap again to start over"
		return
	_confirm_new = false
	_new_btn.text = "Start a new island"
	if Net.in_room():
		Net.leave_room()
	Sfx.play("unlock", 1.0, -6.0)
	island.new_island(randi() % 1000000)
	_set_menu(false)


func _refresh_players() -> void:
	for c in _players_row.get_children():
		c.queue_free()
	if Net.in_room():
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
		if IslandProgress.UNLOCK.has(id):
			var lock := _icon("lock", 22)
			lock.position = Vector2(54, 4)
			lock.size = Vector2(22, 22)
			lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.add_child(lock)
			_locks[id] = lock
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
	_build_levels()
	# undo / redo float on the left above the brushes
	var over := HBoxContainer.new()
	over.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	over.offset_top = -184
	over.offset_bottom = -124
	over.offset_left = 18
	over.add_theme_constant_override("separation", 10)
	over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(over)
	_undo_btn = _glass_button(56, "undo")
	_undo_btn.pressed.connect(_on_undo)
	over.add_child(_undo_btn)
	_redo_btn = _glass_button(56, "redo")
	_redo_btn.pressed.connect(_on_redo)
	over.add_child(_redo_btn)
	island.history_changed.connect(_refresh_history)
	_refresh_history()


## While the Grow brush is in hand: how far the town may grow up where it is
## painted, from a village of cottages to a centre of tall terraces.
func _build_levels() -> void:
	var holder := CenterContainer.new()
	holder.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	holder.offset_top = -188
	holder.offset_bottom = -118
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(holder)
	_level_bar = holder
	var m := PanelContainer.new()
	_glassify(m)
	holder.add_child(m)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(row)
	for i in LEVELS.size():
		var b := _key(104, 50)
		var h := HBoxContainer.new()
		h.set_anchors_preset(Control.PRESET_FULL_RECT)
		h.alignment = BoxContainer.ALIGNMENT_CENTER
		h.add_theme_constant_override("separation", 4)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(h)
		var ic := _icon("level%d" % (i + 1), 34)
		ic.custom_minimum_size = Vector2(34, 34)
		h.add_child(ic)
		h.add_child(_label(LEVELS[i], 14, true, INK))
		b.pressed.connect(func():
			Sfx.play("click", 0.85 + i * 0.12, -4.0)
			island.grow_level = i + 1
			_refresh_brushes())
		row.add_child(b)
		_level_keys.append(b)


func _refresh_history() -> void:
	if _undo_btn == null:
		return
	_undo_btn.disabled = not island.can_undo()
	_redo_btn.disabled = not island.can_redo()
	_undo_btn.modulate.a = 1.0 if island.can_undo() else 0.45
	_redo_btn.modulate.a = 1.0 if island.can_redo() else 0.45


func _on_undo() -> void:
	if island.undo():
		Sfx.play("pop", 0.8, -3.0)
	_refresh_history()


func _on_redo() -> void:
	if island.redo():
		Sfx.play("pop", 1.2, -3.0)
	_refresh_history()


func _refresh_brushes() -> void:
	for id in _brush_keys:
		_brush_keys[id].set_pressed_no_signal(id == island.brush)
	island.brush_radius = SIZES[_size_i][1]
	_size_btn.text = SIZES[_size_i][0]
	if _level_bar:
		_level_bar.visible = island.brush == "grow" and not _photo
		for i in _level_keys.size():
			_level_keys[i].set_pressed_no_signal(island.grow_level == i + 1)
	if island.brush != "":
		_help.text = BRUSH_INFO[island.brush][1]
		if island.brush == "grow":
			_help.text = "Paint beside a street. %s: %s" % [LEVELS[island.grow_level - 1], ["cottages and small houses", "houses and low terraces", "terraces with shops", "tall terraces, shops everywhere"][island.grow_level - 1]]
	else:
		_help.text = "Draw streets, or shape the land: pick a brush"


func _process(delta: float) -> void:
	var coins := island.progress.coins
	_coins_shown = lerpf(_coins_shown, coins, 1.0 - exp(-delta * 6.0))
	if absf(_coins_shown - coins) < 0.5:
		_coins_shown = coins
	_coin_label.text = _short(_coins_shown)
	if _goals.visible and _goals_open:
		_tick_goals()
	if _fps_label.visible:
		_fps_time += delta
		if _fps_time >= 0.5:
			_fps_time = 0.0
			var tris := Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
			_fps_label.text = "%d FPS\n%s tris" % [Engine.get_frames_per_second(), _short_count(tris)]


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_H and not event.ctrl_pressed:
		set_photo(not _photo)
		get_viewport().set_input_as_handled()
		return
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


# ------------------------------------------------------------------ top bar

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


func _short(n: float) -> String:
	if n >= 10000:
		return "%.1fk" % (n / 1000.0)
	return str(int(n))


# ------------------------------------------------------------------ tools

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


# ------------------------------------------------------------------ goals

func _build_goals() -> void:
	_goals = PanelContainer.new()
	_goals.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	_goals.offset_left = 18
	_goals.offset_top = -120
	_glassify(_goals)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_goals.add_child(v)
	# the header folds the list away, for when the view needs the room
	var head := Button.new()
	head.flat = true
	head.focus_mode = Control.FOCUS_NONE
	head.custom_minimum_size = Vector2(286, 34)
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		head.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	var hr := HBoxContainer.new()
	hr.set_anchors_preset(Control.PRESET_FULL_RECT)
	hr.add_theme_constant_override("separation", 8)
	hr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(hr)
	hr.add_child(_icon("star", 28))
	var title := _label("Town goals", 18, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hr.add_child(title)
	_goal_count = _label("", 15, true, SOFT)
	hr.add_child(_goal_count)
	head.pressed.connect(func():
		Sfx.play("click")
		_goals_open = not _goals_open
		_goal_rows.visible = _goals_open)
	v.add_child(head)
	_goal_rows = VBoxContainer.new()
	_goal_rows.add_theme_constant_override("separation", 10)
	v.add_child(_goal_rows)
	_root.add_child(_goals)


func _refresh_goals() -> void:
	if _goal_rows == null:
		return
	for c in _goal_rows.get_children():
		c.queue_free()
	var ready := 0
	var list := _goal_list()
	for i in list.size():
		var g: Dictionary = list[i]
		if g.get("ready", false):
			ready += 1
		_goal_rows.add_child(_goal_row(i, g))
	_goal_count.text = ("%d to collect" % ready) if ready > 0 else ("%d done" % _goals_done())
	_goal_count.add_theme_color_override("font_color", ACCENT if ready > 0 else SOFT)
	_goals.visible = not list.is_empty()


func _goal_row(i: int, g: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var ic := _icon(str(g.icon), 34)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ic)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	var t := _label(str(g.text), 15, true)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size.x = 160
	col.add_child(t)
	if g.get("ready", false):
		var b := Button.new()
		b.text = "Collect +%s" % _short(float(g.reward))
		b.custom_minimum_size = Vector2(0, 38)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 16)
		b.add_theme_stylebox_override("normal", _box(ACCENT, 19, 12))
		b.add_theme_stylebox_override("hover", _box(ACCENT.lightened(0.1), 19, 12))
		b.add_theme_stylebox_override("pressed", _box(ACCENT.darkened(0.1), 19, 12, false))
		for fc in ["font_color", "font_hover_color", "font_pressed_color"]:
			b.add_theme_color_override(fc, Color.WHITE)
		b.pressed.connect(_claim_goal.bind(i, b))
		col.add_child(b)
		# a gentle breathing pulse so it is hard to miss
		b.pivot_offset = Vector2(60, 19)
		var tw := b.create_tween().set_loops()
		tw.tween_property(b, "scale", Vector2(1.04, 1.04), 0.55).set_trans(Tween.TRANS_SINE)
		tw.tween_property(b, "scale", Vector2.ONE, 0.55).set_trans(Tween.TRANS_SINE)
	else:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		col.add_child(h)
		var pb := ProgressBar.new()
		pb.custom_minimum_size = Vector2(0, 8)
		pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pb.show_percentage = false
		pb.max_value = 1.0
		pb.step = 0.0
		pb.value = _goal_frac(g)
		pb.set_meta("goal", i)
		h.add_child(pb)
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 2)
		r.add_child(_icon("coin", 16))
		r.add_child(_label(_short(float(g.reward)), 13, true, Color("b46a1f")))
		h.add_child(r)
	return row


## Keeps the goal bars moving as the town changes, without rebuilding the rows.
func _tick_goals() -> void:
	for row in _goal_rows.get_children():
		for pb in row.find_children("*", "ProgressBar", true, false):
			var i: int = pb.get_meta("goal", -1)
			if i >= 0 and i < _goal_list().size():
				pb.value = lerpf(pb.value, _goal_frac(_goal_list()[i]), 0.25)


func _on_goal_ready(i: int) -> void:
	if i < _goal_list().size():
		show_toast("Goal complete: %s" % _goal_list()[i].text, "unlock")
	Sfx.play("bell", 1.2)
	if not _goals_open:
		_goals_open = true
		_goal_rows.visible = true
	_refresh_goals()


func _claim_goal(i: int, from: Control) -> void:
	var start := from.get_global_rect().get_center()
	var paid := _claim(i)
	if paid <= 0.0:
		return
	Sfx.play("unlock", 1.25)
	_fly_coins(start, 9)
	_refresh_goals()


## Little coins that arc from a point into the coin counter, one chime each.
func _fly_coins(start: Vector2, count: int) -> void:
	var end := _coin_label.get_global_rect().get_center() - _root.get_global_rect().position
	start -= _root.get_global_rect().position
	for k in count:
		var c := _icon("coin", 30)
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.position = start + Vector2(randf_range(-30, 30), randf_range(-14, 14)) - Vector2(15, 15)
		c.z_index = 10
		_root.add_child(c)
		var mid := (c.position + end) * 0.5 + Vector2(randf_range(-80, 80), -140)
		var tw := c.create_tween()
		var from_p := c.position
		tw.tween_interval(k * 0.06)
		tw.tween_method(func(t: float):
			c.position = from_p.lerp(mid, t).lerp(mid.lerp(end - Vector2(15, 15), t), t)
			c.scale = Vector2.ONE * (1.0 - 0.4 * t), 0.0, 1.0, 0.7).set_ease(Tween.EASE_IN)
		tw.tween_callback(func():
			Sfx.play("coin", 1.0 + k * 0.04, -6.0)
			c.queue_free())


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
		Game.save_settings()


func _build_photo_exit() -> void:
	_photo_exit = _glass_button(52, "close")
	_photo_exit.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_photo_exit.offset_left = -70
	_photo_exit.offset_right = -18
	_photo_exit.offset_top = 18
	_photo_exit.offset_bottom = 70
	_photo_exit.visible = false
	_photo_exit.pressed.connect(func(): set_photo(false))
	_root.add_child(_photo_exit)


## Photo mode hides the whole HUD so the island can be admired (and captured)
## on its own; one faint button in the corner brings it all back.
func set_photo(on: bool) -> void:
	if on == _photo:
		return
	_photo = on
	Sfx.play("click")
	if on:
		_set_menu(false)
		_photo_brush = island.brush
		if island.brush != "":
			island.set_brush(island.brush)
	if on:
		_photo_hidden.clear()
		for c: Control in _root.get_children():
			if c != _photo_exit and c.visible:
				_photo_hidden.append(c)
				var tw := create_tween()
				tw.tween_property(c, "modulate:a", 0.0, 0.25)
				tw.tween_callback(func(): if _photo: c.hide())
	else:
		for c in _photo_hidden:
			c.show()
			create_tween().tween_property(c, "modulate:a", 1.0, 0.25)
	_photo_exit.visible = on
	if on:
		# shown clearly for a moment, then it steps back out of the picture
		_photo_exit.modulate.a = 1.0
		var tw := create_tween()
		tw.tween_interval(2.0)
		tw.tween_property(_photo_exit, "modulate:a", 0.35, 0.6)
	elif _photo_brush != "" and island.brush == "":
		island.set_brush(_photo_brush)


func _notification(what: int) -> void:
	# Android back gesture leaves photo mode, or closes the menu
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and _photo:
		set_photo(false)
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST and _menu != null and _menu.visible:
		_set_menu(false)


func _input(event: InputEvent) -> void:
	if _photo and event.is_action_pressed("ui_cancel"):
		set_photo(false)
		get_viewport().set_input_as_handled()
	elif _menu != null and _menu.visible and event.is_action_pressed("ui_cancel"):
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


## The layout is sized for a 720-tall phone screen stretched to fit. On a monitor that
## makes every panel huge, so on desktop shrink the stretch back towards real pixels
## (scaled by the monitor's DPI); phones keep the stretched layout untouched.
func _fit_desktop_scale() -> void:
	var w := get_window()
	var stretch := minf(w.size.x / 1280.0, w.size.y / 720.0)
	if stretch <= 0.0:
		return
	var dpi := float(DisplayServer.screen_get_dpi(w.current_screen))
	var px := maxf(DisplayServer.screen_get_scale(w.current_screen), dpi / 96.0 if dpi > 0.0 else 1.0)
	var f := clampf(0.95 * clampf(px, 0.85, 3.0) / stretch, 0.45, 1.0)
	if absf(w.content_scale_factor - f) > 0.001:
		w.content_scale_factor = f


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
	_build_world_page(_page_box("island"))

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
			_save_cloud()
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
				"shadows": island.sun.shadow_enabled = on
				"fps": _fps_label.visible = on
			Game.save_settings())
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
		_island_summary.text = _world_summary()

