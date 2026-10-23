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
var _menu_status: Label
var _acct_status: Label
var _room_status: Label
var _email: LineEdit
var _password: LineEdit
var _room_code: LineEdit
var _name_edit: LineEdit
var _confirm_new := false

const INK := Color("2b3440")
const SOFT := Color("6b7785")
const CARD := Color(1, 1, 1, 0.9)
const ACCENT := Color("ff7a6b")
const MINT := Color("3fae8c")


func _ready() -> void:
	layer = 5
	var base: Font = load("res://assets/fonts/Nunito.ttf")
	font_bold = FontVariation.new()
	font_bold.base_font = base
	font_bold.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 850}
	font_reg = FontVariation.new()
	font_reg.base_font = base
	font_reg.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 650}
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = _make_theme()
	add_child(_root)
	_build_top()
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


# ------------------------------------------------------------------ theme

func _box(bg: Color, radius := 22, pad := 14, shadow := true) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
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
	var b := _box(Color(1, 1, 1, 0.96), 18, 16)
	t.set_stylebox("normal", "Button", b)
	var bh := _box(Color("fff6ee"), 18, 16)
	t.set_stylebox("hover", "Button", bh)
	var bp := _box(Color("ffe3d9"), 18, 16, false)
	t.set_stylebox("pressed", "Button", bp)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_stylebox("disabled", "Button", _box(Color(0.92, 0.92, 0.92, 0.9), 18, 16, false))
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
	var menu_btn := Button.new()
	menu_btn.custom_minimum_size = Vector2(58, 58)
	var mi := _icon("menu", 30)
	mi.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_btn.add_child(mi)
	menu_btn.pressed.connect(_toggle_menu)
	stats.add_child(menu_btn)


func _pill(parent: Control, icon: String) -> Label:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", _box(CARD, 29, 14))
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


# ------------------------------------------------------------------ tools

func _build_toolbar() -> void:
	var bottom := VBoxContainer.new()
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_top = -190
	bottom.offset_bottom = -14
	bottom.offset_left = 16
	bottom.offset_right = -16
	bottom.alignment = BoxContainer.ALIGNMENT_END
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bottom)
	var hint_row := CenterContainer.new()
	hint_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(hint_row)
	_hint_card = PanelContainer.new()
	_hint_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_card.add_theme_stylebox_override("panel", _box(Color(0.17, 0.2, 0.25, 0.82), 16, 14))
	_hint = _label("", 17, false, Color.WHITE)
	_hint_card.add_child(_hint)
	_hint_card.modulate.a = 0.0
	hint_row.add_child(_hint_card)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(center)
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", _box(CARD, 30, 12))
	center.add_child(bar)
	var scroll := ScrollContainer.new()
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.custom_minimum_size = Vector2(min(1180, 86 * Game.TOOLS.size()), 112)
	bar.add_child(scroll)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	scroll.add_child(row)
	for t in Game.TOOLS:
		row.add_child(_tool_button(t))


func _tool_button(t: Dictionary) -> Control:
	var b := Button.new()
	b.custom_minimum_size = Vector2(82, 108)
	b.toggle_mode = true
	b.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("hover", _box(Color(0, 0, 0, 0.04), 20, 4, false))
	b.add_theme_stylebox_override("pressed", _box(Color("ffe3d9"), 20, 4, false))
	b.add_theme_stylebox_override("hover_pressed", _box(Color("ffd6c9"), 20, 4, false))
	b.add_theme_stylebox_override("disabled", StyleBoxEmpty.new())
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var ic := _icon(t.id, 54)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(ic)
	var nl := _label(t.name, 15, true)
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(nl)
	var cl := _label("", 13, false, SOFT)
	cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(cl)
	b.pressed.connect(_on_tool_pressed.bind(t.id))
	_tool_buttons[t.id] = {"button": b, "icon": ic, "cost": cl, "name": nl}
	return b


func _refresh_tools() -> void:
	for t in Game.TOOLS:
		var e: Dictionary = _tool_buttons.get(t.id, {})
		if e.is_empty():
			continue
		var unlocked := Game.is_unlocked(t.id)
		var ic: UiIcon = e.icon
		ic.set_kind(t.id if unlocked else "lock")
		ic.color = SOFT
		e.cost.text = ("%d" % t.cost if t.cost > 0 else "free") if unlocked else "at %d pop" % t.unlock
		if not unlocked:
			e.cost.text = "at %d pop" % t.unlock
		e.button.modulate = Color(1, 1, 1, 1) if unlocked else Color(1, 1, 1, 0.55)
		e.button.button_pressed = _selected == t.id


func _on_tool_pressed(id: String) -> void:
	Sfx.play("click")
	if not Game.is_unlocked(id):
		var def := Game.tool_def(id)
		_flash_hint("%s unlocks at %d citizens" % [def.name, def.unlock], true)
		_tool_buttons[id].button.button_pressed = false
		return
	_selected = "" if _selected == id else id
	world.set_tool(_selected)
	_refresh_tools()
	if _selected != "":
		var def := Game.tool_def(id)
		_flash_hint(def.desc, false, 3.5)
	_info.visible = false


func _flash_hint(text: String, warn := false, secs := 2.2) -> void:
	_hint.text = text
	_hint_card.add_theme_stylebox_override("panel", _box(Color(0.78, 0.3, 0.27, 0.9) if warn else Color(0.17, 0.2, 0.25, 0.82), 16, 14))
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
	var bg := CARD
	var col := INK
	var size := 19
	if kind == "unlock":
		bg = Color("2b3440")
		col = Color("ffe9c7")
		size = 24
	elif kind == "title":
		bg = Color("ff7a6b")
		col = Color.WHITE
		size = 26
	p.add_theme_stylebox_override("panel", _box(bg, 20, 18))
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
	var e: Dictionary = _tool_buttons[id]
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
	_tutorial.add_theme_stylebox_override("panel", _box(Color(1, 1, 1, 0.92), 18, 16))
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
		"Pick Road and drag across the grass to lay your first street.",
		"Now choose Homes and paint them right beside the road.",
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
	var names := {Game.K.HOUSE: ["Cottage", "Townhouse", "Apartments"], Game.K.SHOP: ["Corner shop", "High street shop", "Department store"], Game.K.OFFICE: ["Studio offices", "Office tower", "Skyscraper"]}
	var text := ""
	if Game.is_building(k):
		if g == 0:
			text = "Building site\nNeeds a road right next to it to start building."
		else:
			text = "%s  ·  level %d\n" % [names[k][g - 1], g]
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
		text = "Landmark\nLifts happiness and helps nearby buildings grow."
	elif k == Game.K.PARK:
		text = "Park\nNeighbours within 3 tiles grow faster."
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
	chip.add_theme_stylebox_override("panel", _box(CARD, 18, 12))
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
	_menu.visible = not _menu.visible
	_confirm_new = false
	if _menu.visible:
		_name_edit.text = Game.player_name
		_refresh_account()


func _section(parent: Control, title: String) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.add_child(_label(title, 20, true, ACCENT))
	parent.add_child(v)
	return v


func _button(text: String, cb: Callable, primary := false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 50)
	b.add_theme_font_size_override("font_size", 18)
	if primary:
		b.add_theme_stylebox_override("normal", _box(ACCENT, 18, 16))
		b.add_theme_stylebox_override("hover", _box(ACCENT.lightened(0.1), 18, 16))
		b.add_theme_stylebox_override("pressed", _box(ACCENT.darkened(0.1), 18, 16, false))
		b.add_theme_color_override("font_color", Color.WHITE)
		b.add_theme_color_override("font_hover_color", Color.WHITE)
		b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.pressed.connect(func():
		Sfx.play("click")
		cb.call())
	return b


func _build_menu() -> void:
	_menu = Control.new()
	_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu.visible = false
	_root.add_child(_menu)
	var dim := ColorRect.new()
	dim.color = Color(0.1, 0.14, 0.2, 0.35)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			_toggle_menu())
	_menu.add_child(dim)
	var card := PanelContainer.new()
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.custom_minimum_size = Vector2(620, 560)
	card.offset_left = -310
	card.offset_right = 310
	card.offset_top = -300
	card.offset_bottom = 300
	card.add_theme_stylebox_override("panel", _box(Color(1, 1, 1, 0.97), 28, 26))
	_menu.add_child(card)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	card.add_child(outer)
	var head := HBoxContainer.new()
	outer.add_child(head)
	var t := _label("City Views", 30, true)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var close := Button.new()
	close.custom_minimum_size = Vector2(48, 48)
	var ci := _icon("close", 22)
	ci.set_anchors_preset(Control.PRESET_FULL_RECT)
	close.add_child(ci)
	close.pressed.connect(_toggle_menu)
	head.add_child(close)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 22)
	scroll.add_child(body)

	# profile
	var prof := _section(body, "Your name")
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Mayor"
	_name_edit.max_length = 16
	_name_edit.text_changed.connect(func(s):
		Game.player_name = s if s.strip_edges() != "" else "Mayor")
	prof.add_child(_name_edit)

	# co-op
	var coop := _section(body, "Build together")
	coop.add_child(_label("Up to 4 builders share one island in real time.", 16, false, SOFT))
	var crow := HBoxContainer.new()
	crow.add_theme_constant_override("separation", 8)
	coop.add_child(crow)
	var host := _button("Host this city", _host, true)
	host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	crow.add_child(host)
	_room_code = LineEdit.new()
	_room_code.placeholder_text = "CODE"
	_room_code.max_length = 6
	_room_code.custom_minimum_size = Vector2(120, 50)
	crow.add_child(_room_code)
	crow.add_child(_button("Join", _join))
	coop.add_child(_button("Leave room", func():
		Net.leave_room()
		_refresh_account()))
	_room_status = _label("", 16, true, SOFT)
	_room_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	coop.add_child(_room_status)

	# account
	var acct := _section(body, "Account & cloud saves")
	_acct_status = _label("", 16, false, SOFT)
	_acct_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	acct.add_child(_acct_status)
	_email = LineEdit.new()
	_email.placeholder_text = "email"
	_email.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_EMAIL_ADDRESS
	acct.add_child(_email)
	_password = LineEdit.new()
	_password.placeholder_text = "password (6+ characters)"
	_password.secret = true
	_password.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_PASSWORD
	acct.add_child(_password)
	var arow := HBoxContainer.new()
	arow.add_theme_constant_override("separation", 8)
	acct.add_child(arow)
	var si := _button("Sign in", _sign_in)
	si.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	arow.add_child(si)
	var reg := _button("Create account", _register)
	reg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	arow.add_child(reg)
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 8)
	acct.add_child(srow)
	var save := _button("Save to cloud", func():
		if Firebase.signed_in:
			Firebase.save_city(Game.to_dict())
			_menu_status.text = "Saved to the cloud ✓"
		else:
			_menu_status.text = "Sign in first")
	save.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	srow.add_child(save)
	var so := _button("Sign out", func(): Firebase.sign_out())
	so.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	srow.add_child(so)

	# city
	var city := _section(body, "Island")
	var new_btn := _button("New island", func(): pass)
	new_btn.pressed.connect(func():
		if not _confirm_new:
			_confirm_new = true
			new_btn.text = "Tap again to start over"
			return
		_confirm_new = false
		new_btn.text = "New island"
		if Net.in_room():
			Net.leave_room()
		Game.new_world(randi() % 1000000)
		Game.save_local()
		_toggle_menu())
	city.add_child(new_btn)

	# settings
	var st := _section(body, "Settings")
	for key in [["music", "Music"], ["sfx", "Sounds"], ["shadows", "Shadows"]]:
		var cb := CheckButton.new()
		cb.text = key[1]
		cb.add_theme_font_size_override("font_size", 18)
		cb.button_pressed = Game.settings.get(key[0], true)
		cb.toggled.connect(func(on):
			Game.settings[key[0]] = on
			if key[0] == "shadows":
				world.sun.shadow_enabled = on
			Game.save_local())
		st.add_child(cb)

	# patch notes
	var notes := _section(body, "What's new")
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.scroll_active = false
	rt.add_theme_font_override("normal_font", font_reg)
	rt.add_theme_font_override("bold_font", font_bold)
	rt.add_theme_font_size_override("normal_font_size", 16)
	rt.add_theme_font_size_override("bold_font_size", 17)
	rt.add_theme_color_override("default_color", INK)
	rt.text = _patch_notes_bbcode()
	notes.add_child(rt)

	_menu_status = _label("", 16, true, MINT)
	outer.add_child(_menu_status)


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
	_room_status.text = err if err != "" else "Room %s is open. Share the code with up to 3 friends!" % Net.room_code
	_refresh_account()


func _join() -> void:
	_room_status.text = "Joining…"
	var err: String = await Net.join_room(_room_code.text)
	_room_status.text = err if err != "" else "Joined room %s" % Net.room_code
	if err == "":
		_toggle_menu()


func _sign_in() -> void:
	_menu_status.text = "Signing in…"
	var err: String = await Firebase.sign_in_email(_email.text.strip_edges(), _password.text)
	_menu_status.text = err if err != "" else "Welcome back!"
	_password.text = ""


func _register() -> void:
	_menu_status.text = "Creating account…"
	var err: String = await Firebase.register_email(_email.text.strip_edges(), _password.text)
	_menu_status.text = err if err != "" else "Account created. Your city is saved to the cloud."
	_password.text = ""


func _refresh_account() -> void:
	if _acct_status == null:
		return
	if not Firebase.enabled:
		_acct_status.text = "Online services aren't set up in this build, so your city is saved on this device."
	elif not Firebase.signed_in:
		_acct_status.text = "Connecting…"
	elif Firebase.is_guest:
		_acct_status.text = "Playing as a guest. Create an account to keep your city safe across devices."
	else:
		_acct_status.text = "Signed in as %s. Your city syncs to the cloud." % Firebase.email
	if _room_status and Net.in_room() and _room_status.text == "":
		_room_status.text = "In room %s" % Net.room_code


func _on_reset() -> void:
	_refresh_stats()
	_info.visible = false
