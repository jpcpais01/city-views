class_name GameMenu
extends Control
## The pause menu, console style: the city blurs behind smoked glass, a rail of
## sections runs down the left, the chosen page fills the right, and a hint bar
## along the bottom names the keys. It steers just as well with a mouse, a
## finger, the keyboard (arrows, Enter, Esc, Q/E) or a game pad (D-pad, A, B,
## LB/RB), and every page glides in.

const K := preload("res://src/ui/ui_kit.gd")
const PAGES := [
	["city", "City", "house", "Your city at a glance"],
	["maps", "New map", "globe", "Start again on a fresh landscape"],
	["coop", "Co-op", "people", "Build together with up to 3 friends"],
	["account", "Account", "smile", "Sign in to keep your city on every device"],
	["settings", "Settings", "menu", "Sound, graphics, the sky and the interface"],
	["controls", "Controls", "hand", "How to move around and build"],
	["notes", "What's new", "star", "Everything the latest updates brought"],
]
const MAP_INFO := {
	"river": "A river winds through open country, waiting for its first bridges.",
	"coast": "Green country running down to the sea, with an estuary to cross.",
	"lakes": "Rolling hills dotted with lakes and long, quiet shores.",
	"island": "An island alone in the sea, beaches all the way round.",
}
const TIMES := [["auto", "Auto"], ["sunrise", "Sunrise"], ["day", "Day"], ["sunset", "Sunset"], ["night", "Night"]]
const UI_SIZES := [[0.88, "Small"], [1.0, "Normal"], [1.14, "Large"]]

signal closed

var hud: Hud
var island: IslandWorld
## the page shown when the menu next opens
var page := "city"

var _backdrop: Panel
var _frame: Control
var _rail: VBoxContainer
var _rail_btns := {}
var _pages := {}
var _page_holder: Control
var _title: Label
var _subtitle: Label
var _hints: HBoxContainer
var _city_name: Label
var _city_title: Label
var _pop_pill: Label
var _coin_pill: Label
var _room_pill: PanelContainer
var _room_pill_lbl: Label
var _resume: Button
var _modal: Control
var _closing: Tween
var _anim: Tween

# city page
var _name_edit: LineEdit
var _city_edit: LineEdit
var _next_lbl: Label
var _next_bar: ProgressBar
var _tiles := {}
var _milestone: Label
# maps page
var _kind := "river"
var _map_btns := {}
# co-op page
var _coop_out: Control
var _coop_in: Control
var _room_code: LineEdit
var _room_big: Label
var _room_players: HBoxContainer
var _room_status: Label
# account page
var _acct_status: Label
var _acct_badge: Label
var _acct_form: Control
var _acct_signed: Control
var _email: LineEdit
var _password: LineEdit
var _acct_msg: Label
# settings page
var _update_btn: Button
var _update_msg: Label


func _init(h: Hud) -> void:
	hud = h
	island = h.island


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = K.theme()
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	Firebase.auth_changed.connect(refresh)
	Net.room_changed.connect(refresh)
	Net.players_changed.connect(refresh)
	island.name_changed.connect(_refresh_name)
	island.progress.stats_changed.connect(func(): if visible: _refresh_city())
	Updater.checked.connect(_on_update_checked)


func is_open() -> bool:
	return visible and _closing == null


# ------------------------------------------------------------------ open / close

func open(at := "") -> void:
	if at != "":
		page = at
	if _closing:
		_closing.kill()
		_closing = null
	var was := visible
	visible = true
	Game.menu_open = true
	_name_edit.text = Game.player_name
	_show(page, false)
	refresh()
	if was:
		return
	Sfx.play("pop", 1.25, -8.0)
	modulate.a = 1.0
	_backdrop.modulate.a = 0.0
	if _anim:
		_anim.kill()
	_anim = create_tween().set_parallel(true)
	_anim.tween_property(_backdrop, "modulate:a", 1.0, 0.22)
	_frame.pivot_offset = _frame.size * 0.5
	_frame.scale = Vector2(1.035, 1.035)
	_frame.modulate.a = 0.0
	_anim.tween_property(_frame, "scale", Vector2.ONE, 0.42).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_anim.tween_property(_frame, "modulate:a", 1.0, 0.2)
	if K.nav:
		_rail_btns[page].grab_focus.call_deferred()


func close() -> void:
	if not visible or _closing:
		return
	if _modal:
		_close_modal()
	var f := get_viewport().gui_get_focus_owner()
	if f and is_ancestor_of(f):
		f.release_focus()
	Game.player_name = _name_edit.text if _name_edit.text.strip_edges() != "" else "Mayor"
	Game.save_settings()
	Game.menu_open = false
	Sfx.play("pop", 0.9, -9.0)
	if _anim:
		_anim.kill()
	_closing = create_tween().set_parallel(true)
	_closing.tween_property(self, "modulate:a", 0.0, 0.16)
	_closing.tween_property(_frame, "scale", Vector2(1.025, 1.025), 0.16).set_ease(Tween.EASE_IN)
	_closing.chain().tween_callback(func():
		visible = false
		modulate.a = 1.0
		_frame.scale = Vector2.ONE
		_closing = null
		closed.emit())


func _input(e: InputEvent) -> void:
	if not visible or _closing:
		return
	K.track_input(e)
	var typing := get_viewport().gui_get_focus_owner() is LineEdit
	if e.is_action_pressed("ui_cancel") or (e is InputEventJoypadButton and e.pressed and e.button_index == JOY_BUTTON_START):
		if _modal:
			_close_modal()
		elif typing:
			get_viewport().gui_get_focus_owner().release_focus()
		else:
			close()
		get_viewport().set_input_as_handled()
		return
	if _modal:
		return
	var step := 0
	if e is InputEventKey and e.pressed and not e.echo and not typing:
		match e.keycode:
			KEY_Q, KEY_PAGEUP: step = -1
			KEY_E, KEY_PAGEDOWN: step = 1
	elif e is InputEventJoypadButton and e.pressed:
		match e.button_index:
			JOY_BUTTON_LEFT_SHOULDER: step = -1
			JOY_BUTTON_RIGHT_SHOULDER: step = 1
	if step != 0:
		var ids := PAGES.map(func(p): return p[0])
		var i := (ids.find(page) + step + ids.size()) % ids.size()
		Sfx.play("click", 1.3, -6.0)
		_show(ids[i])
		if K.nav:
			_rail_btns[page].grab_focus()
		get_viewport().set_input_as_handled()
		return
	# the first arrow or D-pad press puts the focus on the rail
	if K.nav and (e.is_action_pressed("ui_up") or e.is_action_pressed("ui_down") or e.is_action_pressed("ui_left") or e.is_action_pressed("ui_right")):
		var f := get_viewport().gui_get_focus_owner()
		if f == null or not is_ancestor_of(f):
			_rail_btns[page].grab_focus()
			get_viewport().set_input_as_handled()


# ------------------------------------------------------------------ layout

func _build() -> void:
	# the city, blurred deep behind smoked glass, past the side margins to the screen's edges
	_backdrop = Panel.new()
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.offset_left = -400
	_backdrop.offset_right = 400
	_backdrop.material = K.glass_mat(0.58, 4.2)
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color(0.03, 0.045, 0.07)
	_backdrop.add_theme_stylebox_override("panel", bsb)
	add_child(_backdrop)
	_backdrop.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and _modal == null:
			close())

	_frame = MarginContainer.new()
	_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for s in [["left", 4], ["right", 4], ["top", 22], ["bottom", 16]]:
		_frame.add_theme_constant_override("margin_" + s[0], s[1])
	add_child(_frame)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 16)
	outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.add_child(outer)
	outer.add_child(_top_bar())

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 18)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(body)
	body.add_child(_build_rail())

	# the page: a big title, a line under it, then its content gliding in
	var card := K.panel(26, 28, 0.66)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	body.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	card.add_child(col)
	_title = K.label("", 32, 800)
	col.add_child(_title)
	_subtitle = K.label("", 15, 500, K.DIM)
	col.add_child(_subtitle)
	var gap := Control.new()
	gap.custom_minimum_size.y = 12
	col.add_child(gap)
	_page_holder = Control.new()
	_page_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page_holder.clip_contents = true
	col.add_child(_page_holder)

	_build_city(_page_box("city"))
	_build_maps(_page_box("maps"))
	_build_coop(_page_box("coop"))
	_build_account(_page_box("account"))
	_build_settings(_page_box("settings"))
	_build_controls(_page_box("controls"))
	_build_notes(_page_box("notes"))

	_hints = HBoxContainer.new()
	_hints.alignment = BoxContainer.ALIGNMENT_END
	_hints.add_theme_constant_override("separation", 22)
	_hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(_hints)
	_refresh_hints()


func _top_bar() -> Control:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 14)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var brand := VBoxContainer.new()
	brand.add_theme_constant_override("separation", -2)
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(brand)
	brand.add_child(K.eyebrow("City Views", K.ACCENT_HI, 12))
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 12)
	brand.add_child(name_row)
	_city_name = K.label("", 26, 800)
	name_row.add_child(_city_name)
	var chip := PanelContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var csb := K.box(Color(K.GOLD, 0.16), 8, 9, Color(K.GOLD, 0.45), 1)
	csb.content_margin_top = 2
	csb.content_margin_bottom = 2
	chip.add_theme_stylebox_override("panel", csb)
	_city_title = K.label("", 13, 800, K.GOLD)
	chip.add_child(_city_title)
	name_row.add_child(chip)

	_room_pill = _pill("globe")
	_room_pill_lbl = _room_pill.get_child(0).get_child(1)
	bar.add_child(_room_pill)
	var pp := _pill("people")
	_pop_pill = pp.get_child(0).get_child(1)
	bar.add_child(pp)
	var cp := _pill("coin")
	_coin_pill = cp.get_child(0).get_child(1)
	bar.add_child(cp)
	var x := K.icon_button("close", 50, 0.6)
	x.tooltip_text = "Back to the city"
	x.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	x.pressed.connect(close)
	bar.add_child(x)
	return bar


func _pill(ic: String) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.add_theme_stylebox_override("panel", K.box(Color(1, 1, 1, 0.08), 22, 16, K.LINE, 1))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	p.add_child(h)
	h.add_child(K.icon(ic, 22))
	h.add_child(K.label("0", 18, 800))
	return p


func _build_rail() -> Control:
	var wrap := VBoxContainer.new()
	wrap.custom_minimum_size.x = 236
	wrap.add_theme_constant_override("separation", 10)
	_rail = VBoxContainer.new()
	_rail.add_theme_constant_override("separation", 4)
	_rail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	wrap.add_child(_rail)
	var group := ButtonGroup.new()
	for p in PAGES:
		var b := _rail_button(p[1], p[2])
		b.button_group = group
		b.pressed.connect(func():
			if page != p[0]:
				Sfx.play("click", 1.15, -5.0)
			_show(p[0]))
		b.focus_entered.connect(func():
			if K.nav:
				Sfx.play("click", 1.6, -16.0)
				_show(p[0]))
		_rail.add_child(b)
		_rail_btns[p[0]] = b
	_resume = K.button("Resume", "primary", 54)
	_resume.pressed.connect(close)
	wrap.add_child(_resume)
	var ver := K.label("Version %s" % Updater.current, 12, 600, K.FAINT)
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wrap.add_child(ver)
	return wrap


## One section on the rail: an icon and a name; white when it is the open page.
func _rail_button(text: String, ic: String) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(0, 50)
	b.add_theme_stylebox_override("normal", K.box(Color(1, 1, 1, 0), 14, 14))
	b.add_theme_stylebox_override("hover", K.box(K.RAISED_HI, 14, 14))
	b.add_theme_stylebox_override("pressed", K.box(Color(1, 1, 1, 0.94), 14, 14))
	b.add_theme_stylebox_override("hover_pressed", K.box(Color.WHITE, 14, 14))
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.add_theme_constant_override("margin_left", 16)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(m)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(h)
	var i := K.icon(ic, 24)
	i.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(i)
	var l := K.label(text, 17, 700, K.DIM)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	b.toggled.connect(func(on: bool):
		l.add_theme_color_override("font_color", K.ON_LIGHT if on else K.DIM)
		l.add_theme_font_override("font", K.font(800 if on else 700))
		i.color = K.ON_LIGHT if on else K.TEXT
		i.queue_redraw())
	b.mouse_entered.connect(func(): if not b.button_pressed: l.add_theme_color_override("font_color", K.TEXT))
	b.mouse_exited.connect(func(): if not b.button_pressed: l.add_theme_color_override("font_color", K.DIM))
	K.press_fx(b)
	return b


## A page: a scrolling column that fills the card and only shows when picked.
func _page_box(id: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.visible = false
	_page_holder.add_child(scroll)
	var m := MarginContainer.new()
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# room for focus rings, and for the scroll bar on the right
	for s in [["left", 4], ["right", 14], ["top", 4], ["bottom", 8]]:
		m.add_theme_constant_override("margin_" + s[0], s[1])
	scroll.add_child(m)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 18)
	m.add_child(v)
	_pages[id] = scroll
	return v


func _show(id: String, animate := true) -> void:
	var changed: bool = id != page or not _pages[id].visible
	page = id
	for p in PAGES:
		if p[0] == id:
			_title.text = p[1]
			_subtitle.text = p[3]
	for k in _pages:
		_pages[k].visible = k == id
		_rail_btns[k].set_pressed_no_signal(k == id)
		_rail_btns[k].toggled.emit(k == id)
	if id == "city":
		_refresh_city()
	if changed:
		_pages[id].scroll_vertical = 0
		if animate:
			var s: ScrollContainer = _pages[id]
			s.position = Vector2(26, 0)
			s.modulate.a = 0.0
			var tw := s.create_tween().set_parallel(true)
			tw.tween_property(s, "position", Vector2.ZERO, 0.32).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
			tw.tween_property(s, "modulate:a", 1.0, 0.18)
			for l in [_title, _subtitle]:
				l.modulate.a = 0.0
				tw.tween_property(l, "modulate:a", 1.0, 0.22)


func _refresh_hints() -> void:
	for c in _hints.get_children():
		c.queue_free()
	var pad := not Input.get_connected_joypads().is_empty()
	_hints.visible = pad or not OS.has_feature("mobile")
	_hints.add_child(K.key_hint(K.key_name("tabs", pad), "Sections"))
	_hints.add_child(K.key_hint(K.key_name("select", pad), "Select"))
	_hints.add_child(K.key_hint(K.key_name("back", pad), "Back to the city"))


# ------------------------------------------------------------------ pieces

func _section(parent: Control, title: String) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.add_child(K.eyebrow(title))
	parent.add_child(v)
	return v


## A settings-style row: name and a line of help on the left, its control on the right.
func _row(parent: Control, title: String, help: String, control: Control = null) -> PanelContainer:
	var row := K.inset(14, 18)
	row.custom_minimum_size.y = 66
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	row.add_child(h)
	var txt := VBoxContainer.new()
	txt.add_theme_constant_override("separation", 0)
	txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	txt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(txt)
	txt.add_child(K.label(title, 17, 700))
	if help != "":
		txt.add_child(K.para(help, 13, K.FAINT, 160))
	if control:
		control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(control)
	parent.add_child(row)
	return row


## An on/off row: the whole row is one big switch.
func _toggle_row(parent: Control, key: String, title: String, help: String, on_change := Callable()) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size.y = 66
	var plain := K.box(K.RAISED, 14, 18)
	var lit := K.box(K.RAISED_HI, 14, 18)
	for st in ["normal", "pressed"]:
		b.add_theme_stylebox_override(st, plain)
	for st in ["hover", "hover_pressed"]:
		b.add_theme_stylebox_override(st, lit)
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for s in ["left", "right"]:
		m.add_theme_constant_override("margin_" + s, 18)
	b.add_child(m)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(h)
	var txt := VBoxContainer.new()
	txt.add_theme_constant_override("separation", 0)
	txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	txt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	txt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(txt)
	txt.add_child(K.label(title, 17, 700))
	if help != "":
		txt.add_child(K.label(help, 13, 500, K.FAINT))
	var sw := TextureRect.new()
	sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(sw)
	b.button_pressed = bool(Game.settings.get(key, true))
	sw.texture = K.switch_icon(b.button_pressed)
	b.toggled.connect(func(on: bool):
		sw.texture = K.switch_icon(on)
		Sfx.play("click", 1.25 if on else 0.95, -4.0)
		Game.settings[key] = on
		if on_change.is_valid():
			on_change.call(on)
		Game.save_settings())
	parent.add_child(b)
	return b


## A row that steps through a few choices: ◀ value ▶, with left/right keys,
## a tap on the arrows, or a tap on the row to go to the next one.
func _choice_row(parent: Control, title: String, help: String, names: Array, at: int, on_pick: Callable) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size.y = 66
	for st in ["normal", "pressed"]:
		b.add_theme_stylebox_override(st, K.box(K.RAISED, 14, 18))
	b.add_theme_stylebox_override("hover", K.box(K.RAISED_HI, 14, 18))
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for s in ["left", "right"]:
		m.add_theme_constant_override("margin_" + s, 18 if s == "left" else 8)
	b.add_child(m)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(h)
	var txt := VBoxContainer.new()
	txt.add_theme_constant_override("separation", 0)
	txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	txt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	txt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(txt)
	txt.add_child(K.label(title, 17, 700))
	if help != "":
		txt.add_child(K.label(help, 13, 500, K.FAINT))
	var state := {"i": at}
	var val := K.label("", 17, 800)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val.custom_minimum_size.x = 110
	val.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# little dots under the value show where in the list it is
	var dots := HBoxContainer.new()
	dots.alignment = BoxContainer.ALIGNMENT_CENTER
	dots.add_theme_constant_override("separation", 4)
	dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for k in names.size():
		var d := ColorRect.new()
		d.custom_minimum_size = Vector2(12, 3)
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dots.add_child(d)
	var vcol := VBoxContainer.new()
	vcol.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vcol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vcol.add_theme_constant_override("separation", 4)
	vcol.add_child(val)
	vcol.add_child(dots)
	var paint := func():
		val.text = names[state.i]
		for k in dots.get_child_count():
			(dots.get_child(k) as ColorRect).color = K.ACCENT if k == state.i else Color(1, 1, 1, 0.2)
	var go := func(d: int):
		state.i = (state.i + d + names.size()) % names.size()
		Sfx.play("click", 1.0 + state.i * 0.08, -5.0)
		paint.call()
		on_pick.call(state.i)
		val.pivot_offset = val.size * 0.5
		val.scale = Vector2(0.9, 0.9)
		val.create_tween().tween_property(val, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	for d in [-1, 1]:
		var a := Button.new()
		a.text = "‹" if d < 0 else "›"
		a.focus_mode = Control.FOCUS_NONE
		a.custom_minimum_size = Vector2(40, 44)
		a.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		a.add_theme_font_size_override("font_size", 26)
		a.add_theme_stylebox_override("normal", K.box(Color(1, 1, 1, 0), 12, 4))
		a.add_theme_stylebox_override("hover", K.box(K.RAISED_HI, 12, 4))
		a.add_theme_stylebox_override("pressed", K.box(K.RAISED_HI, 12, 4))
		a.add_theme_color_override("font_pressed_color", K.TEXT)
		a.pressed.connect(func(): go.call(d))
		h.add_child(a)
		if d < 0:
			h.add_child(vcol)
	b.pressed.connect(func(): go.call(1))
	b.gui_input.connect(func(e: InputEvent):
		if e.is_action_pressed("ui_left"):
			go.call(-1)
			b.accept_event()
		elif e.is_action_pressed("ui_right"):
			go.call(1)
			b.accept_event())
	paint.call()
	parent.add_child(b)
	return b


func _field(placeholder: String, max_len := 0) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.custom_minimum_size.y = 50
	if max_len > 0:
		e.max_length = max_len
	return e


# ------------------------------------------------------------------ city

func _build_city(v: VBoxContainer) -> void:
	# the name, big, tap to rename; how far to the next milestone under it
	var hero := K.inset(18, 22, Color(1, 1, 1, 0.07))
	v.add_child(hero)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 10)
	hero.add_child(hv)
	hv.add_child(K.eyebrow("City name"))
	_city_edit = LineEdit.new()
	_city_edit.max_length = IslandWorld.NAME_MAX
	_city_edit.placeholder_text = "Your city"
	_city_edit.add_theme_font_override("font", K.font(800))
	_city_edit.add_theme_font_size_override("font_size", 30)
	_city_edit.custom_minimum_size.y = 58
	_city_edit.select_all_on_focus = true
	_city_edit.text_submitted.connect(func(t):
		island.set_island_name(t)
		_city_edit.release_focus())
	_city_edit.focus_exited.connect(func(): island.set_island_name(_city_edit.text))
	hv.add_child(_city_edit)
	_milestone = K.label("", 15, 700, K.GOLD)
	hv.add_child(_milestone)
	_next_bar = ProgressBar.new()
	_next_bar.custom_minimum_size.y = 6
	_next_bar.show_percentage = false
	_next_bar.max_value = 1.0
	_next_bar.step = 0.0
	_next_bar.add_theme_stylebox_override("fill", K.box(K.GOLD, 4, 0))
	hv.add_child(_next_bar)
	_next_lbl = K.para("", 13, K.DIM)
	hv.add_child(_next_lbl)

	var stats := _section(v, "At a glance")
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	stats.add_child(grid)
	for t in [["residents", "people", "Residents"], ["jobs", "office", "Jobs"], ["homes", "house", "Homes"], ["shops", "shop", "Shops"],
			["works", "factory", "Works"], ["parks", "park", "Parks"], ["streets", "road", "Streets"], ["income", "coin", "Taxes per tick"]]:
		grid.add_child(_tile(t[0], t[1], t[2]))

	var me := _section(v, "You")
	_name_edit = _field("Mayor", 16)
	_name_edit.text_changed.connect(func(t): Game.player_name = t if t.strip_edges() != "" else "Mayor")
	_row(me, "Your name", "Builders in your co-op room see it", _name_edit)
	_name_edit.custom_minimum_size.x = 240

	var quick := _section(v, "Quick actions")
	var qr := HBoxContainer.new()
	qr.add_theme_constant_override("separation", 10)
	quick.add_child(qr)
	var ph := K.button("Photo mode", "secondary")
	ph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ph.pressed.connect(func():
		close()
		hud.set_photo(true))
	qr.add_child(ph)
	var nm := K.button("New map…", "secondary")
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.pressed.connect(func(): _show("maps"))
	qr.add_child(nm)


func _tile(id: String, ic: String, caption: String) -> Control:
	var t := K.inset(16, 16)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	t.add_child(v)
	var i := K.icon(ic, 26)
	i.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.add_child(i)
	var n := K.label("0", 26, 800)
	v.add_child(n)
	v.add_child(K.label(caption, 13, 600, K.FAINT))
	_tiles[id] = n
	return t


func _refresh_city() -> void:
	var pr := island.progress
	_tiles.residents.text = K.short(pr.residents)
	_tiles.jobs.text = K.short(pr.jobs)
	_tiles.homes.text = K.short(pr.homes)
	_tiles.shops.text = K.short(pr.shops)
	_tiles.works.text = K.short(pr.works)
	_tiles.parks.text = K.short(pr.parks)
	_tiles.streets.text = "%.1f km" % (pr.street_m / 1000.0)
	_tiles.income.text = str(pr.income())
	_milestone.text = pr.title
	_city_title.text = pr.title
	var nt := pr.next_title()
	_next_bar.value = nt[1]
	if nt[0] == "":
		_next_lbl.text = "The biggest city there is. Every milestone reached."
	else:
		var opens: Array = []
		for k in IslandProgress.unlocks_at(nt[2]):
			opens.append(hud.unlock_name(k).get_slice(": ", 1))
		_next_lbl.text = "Next: %s at %s residents, +%d coins%s" % [nt[0], K.short(nt[2]), int(pr.milestone_reward(nt[0])),
			"  ·  opens " + ", ".join(opens) if not opens.is_empty() else ""]
	_pop_pill.text = K.short(pr.residents)
	_coin_pill.text = K.short(pr.coins)


func _refresh_name() -> void:
	_city_name.text = island.island_name if island.island_name != "" else "Your city"
	if not _city_edit.has_focus():
		_city_edit.text = island.island_name


# ------------------------------------------------------------------ maps

func _build_maps(v: VBoxContainer) -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	v.add_child(grid)
	var group := ButtonGroup.new()
	for k: String in Land.KINDS:
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_ALL
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 196)
		var plain := K.box(K.RAISED, 18, 10)
		var lit := K.box(K.RAISED_HI, 18, 10)
		var picked := K.box(Color(K.ACCENT, 0.16), 18, 10, K.ACCENT, 2)
		b.add_theme_stylebox_override("normal", plain)
		b.add_theme_stylebox_override("hover", lit)
		b.add_theme_stylebox_override("pressed", picked)
		b.add_theme_stylebox_override("hover_pressed", picked)
		var m := MarginContainer.new()
		m.set_anchors_preset(Control.PRESET_FULL_RECT)
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for s in ["left", "right", "top", "bottom"]:
			m.add_theme_constant_override("margin_" + s, 10)
		b.add_child(m)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 6)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		m.add_child(col)
		var thumb := MapThumb.new(k)
		thumb.radius = 12
		thumb.size_flags_vertical = Control.SIZE_EXPAND_FILL
		col.add_child(thumb)
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(row)
		var nm := K.label(Land.KIND_NAMES[k], 17, 800)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(nm)
		var tick := K.label("Selected", 12, 800, K.ACCENT_HI)
		tick.visible = false
		row.add_child(tick)
		var d := K.label(MAP_INFO.get(k, ""), 12, 500, K.FAINT)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size.x = 120
		col.add_child(d)
		b.toggled.connect(func(on: bool): tick.visible = on)
		b.pressed.connect(func():
			_kind = k
			Sfx.play("click", 1.1, -5.0))
		b.focus_entered.connect(func(): if K.nav: Sfx.play("click", 1.6, -16.0))
		K.press_fx(b)
		grid.add_child(b)
		_map_btns[k] = b
	_map_btns[_kind].button_pressed = true
	var go := K.button("Start new map", "primary", 56)
	go.pressed.connect(func():
		_confirm("Start a new map?", "This replaces %s with a fresh %s. Your city now can't be brought back." % [
			"\"%s\"" % island.island_name if island.island_name != "" else "this city", Land.KIND_NAMES[_kind].to_lower()],
			"Start new map", _start_new))
	v.add_child(go)


func _start_new() -> void:
	if Net.in_room():
		Net.leave_room()
	Sfx.play("unlock", 1.0, -6.0)
	island.new_island(randi() % 1000000, _kind)
	page = "city"
	close()


# ------------------------------------------------------------------ co-op

func _build_coop(v: VBoxContainer) -> void:
	_coop_out = VBoxContainer.new()
	_coop_out.add_theme_constant_override("separation", 18)
	v.add_child(_coop_out)
	var host := _section(_coop_out, "Host")
	var hc := K.inset(18, 22, Color(1, 1, 1, 0.07))
	host.add_child(hc)
	var hh := HBoxContainer.new()
	hh.add_theme_constant_override("separation", 18)
	hc.add_child(hh)
	var ic := K.icon("globe", 54)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hh.add_child(ic)
	var ht := VBoxContainer.new()
	ht.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hh.add_child(ht)
	ht.add_child(K.label("Open this city to friends", 19, 800))
	ht.add_child(K.para("Share the room code and up to 3 friends build on it with you, live.", 14))
	var hb := K.button("Host", "primary")
	hb.custom_minimum_size.x = 150
	hb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.pressed.connect(_host)
	hh.add_child(hb)
	var join := _section(_coop_out, "Join a friend")
	var jr := HBoxContainer.new()
	jr.add_theme_constant_override("separation", 10)
	join.add_child(jr)
	_room_code = _field("Room code", 6)
	_room_code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_room_code.add_theme_font_override("font", K.caps_font(800))
	_room_code.add_theme_font_size_override("font_size", 20)
	_room_code.text_submitted.connect(func(_s): _join())
	jr.add_child(_room_code)
	var jb := K.button("Join", "secondary", 50)
	jb.custom_minimum_size.x = 140
	jb.pressed.connect(_join)
	jr.add_child(jb)

	_coop_in = VBoxContainer.new()
	_coop_in.add_theme_constant_override("separation", 18)
	v.add_child(_coop_in)
	var room := K.inset(18, 22, Color(K.GOOD, 0.1))
	_coop_in.add_child(room)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 6)
	room.add_child(rv)
	rv.add_child(K.eyebrow("Room code", K.GOOD))
	_room_big = K.label("", 52, 800)
	_room_big.add_theme_font_override("font", K.caps_font(800))
	rv.add_child(_room_big)
	rv.add_child(K.para("Friends type this code on their Co-op page to join you.", 14))
	var who := _section(_coop_in, "Building now")
	_room_players = HBoxContainer.new()
	_room_players.add_theme_constant_override("separation", 8)
	who.add_child(_room_players)
	var leave := K.button("Leave room", "secondary")
	leave.pressed.connect(func():
		Net.leave_room()
		_room_status.text = "You left the room. This is your own city again."
		refresh())
	_coop_in.add_child(leave)
	_room_status = K.para("", 14, K.GOOD)
	v.add_child(_room_status)


func _host() -> void:
	_room_status.text = "Opening a room…"
	var err: String = await Net.create_room()
	_room_status.text = err if err != "" else "Room open! Share the code with up to 3 friends."
	refresh()


func _join() -> void:
	if _room_code.text.strip_edges() == "":
		_room_status.text = "Type the room code your friend shared"
		return
	_room_status.text = "Joining…"
	var err: String = await Net.join_room(_room_code.text)
	_room_status.text = err
	refresh()
	if err == "":
		_room_code.text = ""
		close()


# ------------------------------------------------------------------ account

func _build_account(v: VBoxContainer) -> void:
	var card := K.inset(18, 22, Color(1, 1, 1, 0.07))
	v.add_child(card)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 18)
	card.add_child(h)
	var av := K.icon("smile", 54)
	av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(av)
	var t := VBoxContainer.new()
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(t)
	_acct_badge = K.eyebrow("Guest")
	t.add_child(_acct_badge)
	_acct_status = K.para("", 15, K.TEXT)
	t.add_child(_acct_status)

	_acct_form = _section(v, "Sign in or create an account")
	_email = _field("Email")
	_email.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_EMAIL_ADDRESS
	_acct_form.add_child(_email)
	_password = _field("Password (6+ characters)")
	_password.secret = true
	_password.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_PASSWORD
	_password.text_submitted.connect(func(_s): _sign_in())
	_acct_form.add_child(_password)
	var ar := HBoxContainer.new()
	ar.add_theme_constant_override("separation", 10)
	_acct_form.add_child(ar)
	var si := K.button("Sign in", "secondary")
	si.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	si.pressed.connect(_sign_in)
	ar.add_child(si)
	var reg := K.button("Create account", "primary")
	reg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reg.pressed.connect(_register)
	ar.add_child(reg)

	_acct_signed = _section(v, "Cloud saves")
	var sr := HBoxContainer.new()
	sr.add_theme_constant_override("separation", 10)
	_acct_signed.add_child(sr)
	var save := K.button("Save to cloud now", "primary")
	save.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save.pressed.connect(func():
		if Firebase.signed_in:
			island.save_cloud()
			_acct_msg.text = "Saved to the cloud ✓"
		else:
			_acct_msg.text = "Not connected yet, try again in a moment")
	sr.add_child(save)
	var so := K.button("Sign out", "secondary")
	so.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	so.pressed.connect(func():
		await Firebase.sign_out()
		_acct_msg.text = "Signed out. You're playing as a guest."
		refresh())
	sr.add_child(so)
	_acct_msg = K.para("", 14, K.GOOD)
	v.add_child(_acct_msg)


func _sign_in() -> void:
	_acct_msg.text = "Signing in…"
	var err: String = await Firebase.sign_in_email(_email.text.strip_edges(), _password.text)
	_acct_msg.text = err if err != "" else "Welcome back!"
	_password.text = ""
	refresh()


func _register() -> void:
	_acct_msg.text = "Creating your account…"
	var err: String = await Firebase.register_email(_email.text.strip_edges(), _password.text)
	_acct_msg.text = err if err != "" else "Account created. Your city is saved to the cloud."
	_password.text = ""
	refresh()


# ------------------------------------------------------------------ settings

func _build_settings(v: VBoxContainer) -> void:
	var audio := _section(v, "Audio")
	_toggle_row(audio, "music", "Music", "The gentle tune under the city")
	_toggle_row(audio, "sfx", "Sound effects", "Clicks, chimes, birds and waves")

	var gfx := _section(v, "Graphics")
	_toggle_row(gfx, "shadows", "Shadows", "Soft sun shadows from every building and tree", func(on): island.sun.shadow_enabled = on)
	_toggle_row(gfx, "hyper", "Hyper graphics in photo mode", "Sharper image and ambient shading while the HUD is hidden")
	_toggle_row(gfx, "fps", "Performance readout", "Frame rate and triangles under the top bar", func(on): hud.set_fps_visible(on))

	var world := _section(v, "Sky")
	var ti := maxi(TIMES.map(func(t): return t[0]).find(str(Game.settings.get("time", "auto"))), 0)
	_choice_row(world, "Time of day", "Round the clock, or held at a moment you like", TIMES.map(func(t): return t[1]), ti, func(i: int):
		Game.settings["time"] = TIMES[i][0]
		Game.save_settings())
	# which way the sun's daily arc runs across the city, swung round the compass
	var sun := HBoxContainer.new()
	sun.add_theme_constant_override("separation", 12)
	var deg := K.label("", 16, 800)
	deg.custom_minimum_size.x = 48
	deg.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var sl := HSlider.new()
	sl.min_value = 0
	sl.max_value = 360
	sl.step = 5
	sl.focus_mode = Control.FOCUS_ALL
	sl.custom_minimum_size = Vector2(220, 30)
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sl.value = float(Game.settings.get("sun_angle", 0.0))
	deg.text = "%d°" % int(sl.value)
	sl.value_changed.connect(func(x: float):
		Game.settings["sun_angle"] = x
		deg.text = "%d°" % int(x))
	sl.drag_ended.connect(func(_c: bool): Game.save_settings())
	sl.focus_exited.connect(Game.save_settings)
	sun.add_child(sl)
	sun.add_child(deg)
	_row(world, "Sun direction", "Swing the sun's daily arc round the compass", sun)

	var ui := _section(v, "Interface")
	var si := 1
	for i in UI_SIZES.size():
		if is_equal_approx(UI_SIZES[i][0], float(Game.settings.get("ui_scale", 1.0))):
			si = i
	_choice_row(ui, "Interface size", "How big the buttons and text are", UI_SIZES.map(func(s): return s[1]), si, func(i: int):
		Game.settings["ui_scale"] = UI_SIZES[i][0]
		Game.save_settings()
		hud.apply_ui_scale())
	if not OS.has_feature("mobile"):
		var w := get_window()
		var fs := w.mode == Window.MODE_EXCLUSIVE_FULLSCREEN or w.mode == Window.MODE_FULLSCREEN
		_choice_row(ui, "Display mode", "F11 or Alt+Enter switches too", ["Fullscreen", "Window"], 0 if fs else 1, func(i: int):
			get_window().mode = Window.MODE_EXCLUSIVE_FULLSCREEN if i == 0 else Window.MODE_MAXIMIZED)

	var upd := _section(v, "Updates")
	_update_btn = K.button("Check now", "secondary", 46)
	_update_btn.custom_minimum_size.x = 150
	_update_btn.pressed.connect(func():
		_update_btn.disabled = true
		_update_btn.text = "Checking…"
		_update_msg.visible = false
		Updater.check_now())
	_row(upd, "Version %s" % Updater.current, "Look for a newer version now, not only at start", _update_btn)
	_update_msg = K.para("", 14, K.DIM)
	_update_msg.visible = false
	upd.add_child(_update_msg)


func _on_update_checked(status: String, version: String) -> void:
	_update_btn.disabled = false
	_update_btn.text = "Check now"
	_update_msg.visible = true
	_update_msg.add_theme_color_override("font_color", K.GOOD if status == "latest" or status == "newer" else K.DIM)
	_update_msg.text = update_text(status, version)


## What the Settings page says after a check for updates.
static func update_text(status: String, version: String) -> String:
	match status:
		"latest":
			return "You have the latest version (%s)." % version
		"newer":
			return "Version %s is out: tap Update on the card at the top." % version
		"pending":
			return "Version %s is on its way. Try again in a few minutes." % version
		"failed":
			return "Couldn't reach GitHub. Check your connection and try again."
	return "This build (%s) doesn't update itself: updates come to the Android and Windows releases." % version


# ------------------------------------------------------------------ controls

func _build_controls(v: VBoxContainer) -> void:
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 14)
	v.add_child(cols)
	var touch := [
		["One finger", "Pan the view, or paint with the brush in hand"],
		["Two fingers", "Pinch to zoom, twist to turn, drag to pan"],
		["Tap a building", "See what it is and who lives there"],
		["Back gesture", "Close the menu or leave photo mode"],
	]
	var keys := [
		["W A S D", "Pan (arrow keys too, Shift for faster)"],
		["Q  E", "Turn the view"],
		["R  F", "Zoom in and out (or the mouse wheel)"],
		["Right drag", "Turn and tilt the view"],
		["Middle drag", "Pan"],
		["Ctrl Z", "Undo  ·  Ctrl Shift Z redo"],
		["H", "Photo mode: hide the interface"],
		["Esc", "Menu, and back out of anything"],
		["F11", "Full screen or window"],
	]
	for set in [["Touch", touch], ["Keyboard & mouse", keys]]:
		var card := K.inset(18, 18)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cols.add_child(card)
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 10)
		card.add_child(cv)
		cv.add_child(K.eyebrow(set[0]))
		for r in set[1]:
			var h := HBoxContainer.new()
			h.add_theme_constant_override("separation", 12)
			cv.add_child(h)
			var cap := PanelContainer.new()
			cap.custom_minimum_size.x = 104
			cap.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			var sb := K.box(Color(1, 1, 1, 0.1), 7, 8, K.LINE, 1)
			sb.content_margin_top = 3
			sb.content_margin_bottom = 3
			cap.add_theme_stylebox_override("panel", sb)
			var kl := K.label(r[0], 13, 800)
			kl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			cap.add_child(kl)
			h.add_child(cap)
			var d := K.para(r[1], 14, K.DIM, 120)
			d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h.add_child(d)
	var pad := K.para("A game pad works in the menu too: D-pad to move, A to pick, B to go back, LB and RB to change section, Start to open and close it.", 13, K.FAINT)
	v.add_child(pad)


# ------------------------------------------------------------------ what's new

func _build_notes(v: VBoxContainer) -> void:
	for g in patch_groups(6):
		var card := K.inset(16, 20)
		v.add_child(card)
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 8)
		card.add_child(cv)
		cv.add_child(K.eyebrow(g.title, K.ACCENT_HI))
		for b: String in g.items:
			var h := HBoxContainer.new()
			h.add_theme_constant_override("separation", 10)
			cv.add_child(h)
			var dot := ColorRect.new()
			dot.color = K.ACCENT
			dot.custom_minimum_size = Vector2(5, 5)
			dot.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			var dm := MarginContainer.new()
			dm.add_theme_constant_override("margin_top", 9)
			dm.add_child(dot)
			h.add_child(dm)
			var l := K.para(b, 15, K.TEXT, 200)
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h.add_child(l)


## The newest groups of PATCH_NOTES.md: [{title, items}], newest first.
static func patch_groups(max_groups: int) -> Array:
	var path := "res://PATCH_NOTES.md"
	var out: Array = []
	if not FileAccess.file_exists(path):
		return out
	for line in FileAccess.get_file_as_string(path).split("\n"):
		if line.begins_with("## "):
			if out.size() >= max_groups:
				break
			out.append({"title": line.substr(3).strip_edges(), "items": []})
		elif line.begins_with("- ") and not out.is_empty():
			out[-1].items.append(line.substr(2).strip_edges())
	return out


# ------------------------------------------------------------------ dialog

## A modal question over the menu: Cancel is focused first, so a stray press is harmless.
func _confirm(title: String, body: String, ok: String, on_ok: Callable) -> void:
	if _modal:
		_close_modal()
	_modal = Control.new()
	_modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_modal)
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.04, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.offset_left = -400
	dim.offset_right = 400
	dim.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed:
			_close_modal())
	_modal.add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modal.add_child(cc)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", K.box(K.PANEL_SOLID, 24, 30, K.RIM, 1, 30))
	card.custom_minimum_size.x = 480
	cc.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	card.add_child(v)
	v.add_child(K.label(title, 24, 800))
	v.add_child(K.para(body, 15, K.DIM, 420))
	var gap := Control.new()
	gap.custom_minimum_size.y = 8
	v.add_child(gap)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	v.add_child(h)
	var no := K.button("Cancel", "secondary")
	no.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	no.pressed.connect(_close_modal)
	h.add_child(no)
	var yes := K.button(ok, "danger")
	yes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	yes.pressed.connect(func():
		_close_modal()
		on_ok.call())
	h.add_child(yes)
	Sfx.play("pop", 1.1, -8.0)
	dim.modulate.a = 0.0
	dim.create_tween().tween_property(dim, "modulate:a", 1.0, 0.18)
	card.resized.connect(func(): card.pivot_offset = card.size * 0.5, CONNECT_ONE_SHOT)
	K.pop(card, 0.3, 0.9)
	no.grab_focus.call_deferred()


func _close_modal() -> void:
	if _modal:
		_modal.queue_free()
		_modal = null
		if K.nav and _map_btns.has(_kind):
			_map_btns[_kind].grab_focus()


# ------------------------------------------------------------------ refresh

## Shows only what makes sense right now: in a room or not, guest or signed in.
func refresh() -> void:
	if _acct_status == null:
		return
	_refresh_name()
	_refresh_city()
	var online := Firebase.enabled and Firebase.signed_in
	if not Firebase.enabled:
		_acct_badge.text = "OFFLINE"
		_acct_status.text = "Online services aren't set up in this build, so your city is saved on this device."
	elif not Firebase.signed_in:
		_acct_badge.text = "CONNECTING"
		_acct_status.text = "Connecting…"
	elif Firebase.is_guest:
		_acct_badge.text = "GUEST"
		_acct_status.text = "Your city is backed up. Create an account to keep it across phones and PCs."
	else:
		_acct_badge.text = "SIGNED IN"
		_acct_status.text = "%s\nYour city syncs to the cloud automatically." % Firebase.email
	_acct_badge.add_theme_color_override("font_color", K.GOOD if online and not Firebase.is_guest else K.FAINT)
	_acct_form.visible = online and Firebase.is_guest
	_acct_signed.visible = online and not Firebase.is_guest
	var in_room := Net.in_room()
	_coop_out.visible = not in_room
	_coop_in.visible = in_room
	_room_pill.visible = in_room
	if in_room:
		_room_big.text = Net.room_code
		_room_pill_lbl.text = Net.room_code
		for c in _room_players.get_children():
			c.queue_free()
		var players: Array = Net.active_players()
		for p in players:
			var chip := PanelContainer.new()
			chip.add_theme_stylebox_override("panel", K.box(Color(str(p.get("color", "ffffff"))), 16, 14))
			chip.add_child(K.label(str(p.get("name", "?")), 15, 800, Color.WHITE))
			_room_players.add_child(chip)
		if players.is_empty():
			_room_players.add_child(K.para("Waiting for friends to join…", 15))
