class_name Hud
extends CanvasLayer

## The whole interface, built in code: the island card with its title and
## stats, the brushes, goals, toasts, co-op player chips and the main menu,
## all in the same frosted glass.


const BRUSH_INFO := {
	"street": ["Street", "Draw a line: the street lays itself over the land"],
	"grow": ["Grow", "Paint beside a street: new streets and houses branch off it"],
	"green": ["Green", "Paint parks and gardens: the town keeps them green instead of building"],
	"magic": ["Magic", "Paint over houses: each shoots up to the top level painted there, for a few coins"],
	"clear": ["Clear", "Drag to take streets away and stop the town growing there"],
	"raise": ["Raise", "Drag to lift hills out of the land"],
	"lower": ["Lower", "Drag to carve valleys, coves and bays"],
	"smooth": ["Smooth", "Drag to soften bumps and rough slopes"],
	"flatten": ["Flatten", "Drag to level the ground to where you started"],
}
const ICONS := {"street": "road", "grow": "house", "green": "park", "clear": "bulldoze"}
const SIZES := [["S", 1.5], ["M", 3.33], ["L", 8.5]]
## what the Street brush can lay: id -> [name, help]
const ROADS := {
	"main": ["Street", "Draw a line: the street lays itself over the land"],
	"avenue": ["Avenue", "A wide boulevard with a planted middle: side streets branch off it and shops line it"],
	"highway": ["Highway", "Four fast lanes across the country: no houses along it, no side streets off it"],
}
const LEVELS := ["Village", "Town", "City", "Centre", "Downtown", "Skyline"]
const LEVEL_INFO := ["cottages and small houses", "houses and low terraces", "terraces with shops", "tall terraces and blocks, shops everywhere",
	"apartment blocks and offices", "towers over a busy podium"]
## the districts the Grow brush paints: [name, icon, help]
const USES := [["Homes", "house", "homes"], ["Shops", "shop", "shops on every ground floor"],
	["Offices", "office", "offices and jobs"], ["Industry", "factory", "workshops and factories, jobs but no homes"]]

var island: IslandWorld
var _brush_keys := {}
var _size_btn: Button
var _size_i := 1
var _level_bar: Control
var _road_bar: Control
var _road_keys := {}
var _level_keys: Array[Button] = []
var _use_keys: Array[Button] = []
var _use_bar: Control
var _help: Label
var _island_name: LineEdit
var _island_name_menu: LineEdit
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
var _update_msg: Label
var _acct_status: Label
var _room_status: Label
var _email: LineEdit
var _password: LineEdit
var _room_code: LineEdit
var _name_edit: LineEdit
var _confirm_new := false
var _new_kind := "river"
var _kind_btns := {}
var _undo_btn: Button
var _menu_card: PanelContainer
var _redo_btn: Button
var _goals: PanelContainer
var _goal_rows: VBoxContainer
var _goal_count: Label
var _goal_fold: Label
## the row along the top: the town's name card, then the goals beside it
var _top_row: HBoxContainer
# the name card, with the town goals under it
var _top_col: VBoxContainer
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
const MENU_TABS := [["island", "City"], ["coop", "Co-op"], ["account", "Account"], ["settings", "Settings"], ["notes", "What's new"]]
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
	_build_info()
	_build_stats_panel()
	_build_goals()
	_build_menu()
	_build_photo_exit()
	island.brush_changed.connect(_refresh_brushes)
	island.note.connect(func(t, k): show_toast(t, k))
	island.inspected.connect(_show_info)
	island.brush_changed.connect(func(): _hide_info())
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
	_top_row = row
	_top_col = VBoxContainer.new()
	_top_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top_col.add_theme_constant_override("separation", 8)
	_top_col.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(_top_col)
	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glassify(card)
	_top_col.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	card.add_child(v)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 10)
	v.add_child(name_row)
	# the island's name: tap it to rename
	_island_name = _name_field(26)
	name_row.add_child(_island_name)
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
	# brush hints still update, but no longer take room under the name
	_help = _label("", 14, false, SOFT)
	_help.visible = false
	v.add_child(_help)
	island.name_changed.connect(_refresh_island_name)
	_refresh_island_name()
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
	# tap the population for the city's stats
	var pop_tap := Button.new()
	pop_tap.flat = true
	pop_tap.focus_mode = Control.FOCUS_NONE
	pop_tap.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	pop_tap.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	pop_tap.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	pop_tap.pressed.connect(_toggle_stats)
	_pop_label.get_parent().get_parent().add_child(pop_tap)
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
	var about := _section(page, "This city")
	_island_name_menu = LineEdit.new()
	_island_name_menu.placeholder_text = "Your city"
	_island_name_menu.max_length = IslandWorld.NAME_MAX
	_island_name_menu.text_submitted.connect(func(t): island.set_island_name(t))
	_island_name_menu.focus_exited.connect(func(): island.set_island_name(_island_name_menu.text))
	about.add_child(_island_name_menu)
	_refresh_island_name()
	_island_summary = _wrap_label("", 17, true, INK)
	about.add_child(_island_summary)
	var kinds := GridContainer.new()
	kinds.columns = 2
	kinds.add_theme_constant_override("h_separation", 8)
	kinds.add_theme_constant_override("v_separation", 8)
	about.add_child(kinds)
	for k: String in Land.KINDS:
		var b := _button(Land.KIND_NAMES[k], func(): _pick_kind(k))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		kinds.add_child(b)
		_kind_btns[k] = b
	_pick_kind(_new_kind)
	_new_btn = _button("Start a new map", func(): pass)
	_new_btn.pressed.connect(_on_new_island)
	about.add_child(_new_btn)
	about.add_child(_wrap_label("Pick a landscape: a river through open country, a coast with an estuary, lakes, or an island in the sea. It replaces this map. Tap twice to confirm."))


## A name that reads like a title until tapped, then edits in place.
func _name_field(px: int) -> LineEdit:
	var e := LineEdit.new()
	e.max_length = IslandWorld.NAME_MAX
	e.placeholder_text = "Your city"
	e.expand_to_text_length = true
	e.flat = true
	e.caret_blink = true
	e.select_all_on_focus = true
	e.add_theme_font_override("font", font_bold)
	e.add_theme_font_size_override("font_size", px)
	e.add_theme_color_override("font_color", INK)
	e.add_theme_color_override("font_placeholder_color", INK)
	for st in ["normal", "read_only"]:
		e.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	e.add_theme_stylebox_override("focus", _box(Color(1, 1, 1, 0.85), 10, 6, false))
	e.text_submitted.connect(func(t):
		island.set_island_name(t)
		e.release_focus())
	e.focus_exited.connect(func(): island.set_island_name(e.text))
	return e


func _refresh_island_name() -> void:
	for e: LineEdit in [_island_name, _island_name_menu]:
		if e and not e.has_focus():
			e.text = island.island_name


func _world_summary() -> String:
	var pr := island.progress
	return "%d residents in %d homes  ·  %d jobs  ·  %d shops  ·  %d parks  ·  %d m of streets\nThe city pays %s coins every few seconds" % [
		pr.residents, pr.homes, pr.jobs, pr.shops, pr.parks, int(pr.street_m), str(pr.income())]


func _refresh_stats() -> void:
	_refresh_stats_panel()
	var pr := island.progress
	_pop_label.text = _short(pr.residents)
	_title_chip.text = pr.title
	_progress.value = pr.next_title()[1]
	_refresh_locks()


## How an unlock reads on a toast or in the stats panel.
func unlock_name(id: String) -> String:
	if ROADS.has(id):
		return "New road: %s" % ROADS[id][0]
	if id.begins_with("level"):
		return "New level: %s" % LEVELS[clampi(int(id.substr(5)) - 1, 0, LEVELS.size() - 1)]
	var u := IslandProgress.USE_KEYS.find(id)
	if u >= 0:
		return "New district: %s" % USES[u][0]
	return "New brush: %s" % BRUSH_INFO[id][0] if BRUSH_INFO.has(id) else id.capitalize()


func _on_title(title: String) -> void:
	var reward := island.progress.milestone_reward(title)
	show_toast("Your city is now a %s!%s" % [title, "  +%d coins" % int(reward) if reward > 0.0 else ""], "title")
	Sfx.play("unlock", 0.8)
	_confetti()


func _on_brush_unlocked(id: String) -> void:
	var what := unlock_name(id)
	if not BRUSH_INFO.has(id):
		show_toast(what, "unlock")
		Sfx.play("unlock")
		_confetti()
		_refresh_brushes()
		_refresh_stats_panel()
		return
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


## Which landscape "Start a new map" makes.
func _pick_kind(k: String) -> void:
	_new_kind = k
	for key: String in _kind_btns:
		var b: Button = _kind_btns[key]
		var on := key == k
		for st in ["normal", "hover", "pressed"]:
			if on:
				b.add_theme_stylebox_override(st, _box(ACCENT, 25, 16, st != "pressed"))
			else:
				b.remove_theme_stylebox_override(st)
		for fc in ["font_color", "font_hover_color", "font_pressed_color"]:
			if on:
				b.add_theme_color_override(fc, Color.WHITE)
			else:
				b.remove_theme_color_override(fc)
	if _confirm_new:
		_confirm_new = false
		_new_btn.text = "Start a new map"


func _on_new_island() -> void:
	if not _confirm_new:
		_confirm_new = true
		_new_btn.text = "Tap again: new %s" % Land.KIND_NAMES[_new_kind].to_lower()
		return
	_confirm_new = false
	_new_btn.text = "Start a new map"
	if Net.in_room():
		Net.leave_room()
	Sfx.play("unlock", 1.0, -6.0)
	island.new_island(randi() % 1000000, _new_kind)
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
	# each key stands on its own, no panel behind the row; undo and redo lead it
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(row)
	_undo_btn = _glass_button(56, "undo")
	_undo_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_undo_btn.pressed.connect(_on_undo)
	row.add_child(_undo_btn)
	_redo_btn = _glass_button(56, "redo")
	_redo_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_redo_btn.pressed.connect(_on_redo)
	row.add_child(_redo_btn)
	var lead := Control.new()
	lead.custom_minimum_size = Vector2(14, 0)
	lead.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(lead)
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
	_build_roads()
	island.history_changed.connect(_refresh_history)
	_refresh_history()


## While the Street brush is in hand: which kind of road it lays.
func _build_roads() -> void:
	var holder := CenterContainer.new()
	holder.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	holder.offset_top = -188
	holder.offset_bottom = -118
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(holder)
	_road_bar = holder
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(row)
	var i := 0
	for id: String in ROADS:
		var b := _key(116, 50)
		var h := HBoxContainer.new()
		h.set_anchors_preset(Control.PRESET_FULL_RECT)
		h.alignment = BoxContainer.ALIGNMENT_CENTER
		h.add_theme_constant_override("separation", 4)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(h)
		var ic := _icon("road_" + id, 34)
		ic.custom_minimum_size = Vector2(34, 34)
		h.add_child(ic)
		h.add_child(_label(ROADS[id][0], 14, true, INK))
		var pitch := 0.85 + i * 0.15
		b.pressed.connect(func():
			if not island.progress.can_use(id):
				show_toast(island.progress.unlock_text(id), "warn")
				Sfx.play("error", 1.0, -6.0)
				_refresh_brushes()
				return
			Sfx.play("click", pitch, -4.0)
			island.street_kind = id
			_refresh_brushes())
		row.add_child(b)
		_road_keys[id] = b
		i += 1


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
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(row)
	for i in LEVELS.size():
		var b := _key(106, 50)
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
			var key := "level%d" % (i + 1)
			if not island.progress.can_use(key):
				show_toast(island.progress.unlock_text(key), "warn")
				Sfx.play("error", 1.0, -6.0)
				_refresh_brushes()
				return
			Sfx.play("click", 0.85 + i * 0.12, -4.0)
			island.grow_level = i + 1
			_refresh_brushes())
		row.add_child(b)
		_level_keys.append(b)
	# and above it, what the painted ground is for
	var uh := CenterContainer.new()
	uh.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	uh.offset_top = -244
	uh.offset_bottom = -194
	uh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(uh)
	_use_bar = uh
	var urow := HBoxContainer.new()
	urow.add_theme_constant_override("separation", 6)
	urow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	uh.add_child(urow)
	for i in USES.size():
		var b := _key(110, 44)
		var h := HBoxContainer.new()
		h.set_anchors_preset(Control.PRESET_FULL_RECT)
		h.alignment = BoxContainer.ALIGNMENT_CENTER
		h.add_theme_constant_override("separation", 4)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(h)
		var ic := _icon(USES[i][1], 30)
		ic.custom_minimum_size = Vector2(30, 30)
		h.add_child(ic)
		h.add_child(_label(USES[i][0], 14, true, INK))
		b.pressed.connect(func():
			var key: String = IslandProgress.USE_KEYS[i]
			if not island.progress.can_use(key):
				show_toast(island.progress.unlock_text(key), "warn")
				Sfx.play("error", 1.0, -6.0)
				_refresh_brushes()
				return
			Sfx.play("click", 0.9 + i * 0.1, -4.0)
			island.grow_use = i
			_refresh_brushes())
		urow.add_child(b)
		_use_keys.append(b)


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
	if _road_bar:
		_road_bar.visible = island.brush == "street" and not _photo
		for id: String in _road_keys:
			var k: Button = _road_keys[id]
			k.set_pressed_no_signal(island.street_kind == id)
			k.modulate.a = 1.0 if island.progress.can_use(id) else 0.5
	if _level_bar:
		_level_bar.visible = island.brush == "grow" and not _photo
		for i in _level_keys.size():
			_level_keys[i].set_pressed_no_signal(island.grow_level == i + 1)
			_level_keys[i].modulate.a = 1.0 if island.progress.can_use("level%d" % (i + 1)) else 0.5
		_use_bar.visible = _level_bar.visible
		for i in _use_keys.size():
			_use_keys[i].set_pressed_no_signal(island.grow_use == i)
			_use_keys[i].modulate.a = 1.0 if island.progress.can_use(IslandProgress.USE_KEYS[i]) else 0.5
	if island.brush != "":
		_help.text = BRUSH_INFO[island.brush][1]
		if island.brush == "street":
			_help.text = ROADS[island.street_kind][1]
		if island.brush == "grow":
			_help.text = "Paint beside a street. %s %s: %s" % [LEVELS[island.grow_level - 1], USES[island.grow_use][0].to_lower(), LEVEL_INFO[island.grow_level - 1]]
			if island.grow_use == 3:
				_help.text = "Paint beside a street. %s industry: %s" % [LEVELS[island.grow_level - 1], USES[3][2]]
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
		var full := w.mode == Window.MODE_EXCLUSIVE_FULLSCREEN or w.mode == Window.MODE_FULLSCREEN
		w.mode = Window.MODE_MAXIMIZED if full else Window.MODE_EXCLUSIVE_FULLSCREEN
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
	# under the pills on the right, clear of the name card and the goals
	_fps_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_fps_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_fps_label.offset_right = -30
	_fps_label.offset_top = 86
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


# ------------------------------------------------------------------ building info

var _info: PanelContainer
var _info_title: Label
var _info_lines: Label
var _info_tw: Tween


## A small card above the brushes saying what a tapped building is.
func _build_info() -> void:
	var holder := CenterContainer.new()
	holder.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	holder.offset_top = -236
	holder.offset_bottom = -118
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(holder)
	_info = PanelContainer.new()
	_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info.material = _glass_light
	_info.add_theme_stylebox_override("panel", _glass_box(GLASS, 20, 14))
	holder.add_child(_info)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info.add_child(v)
	_info_title = _label("", 20, true, INK)
	_info_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_info_title)
	_info_lines = _label("", 14, false, INK)
	_info_lines.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_info_lines)
	_info.visible = false


func _show_info(lot: Variant) -> void:
	if lot == null or _photo:
		_hide_info()
		return
	var d: Dictionary = island.town.describe(lot)
	_info_title.text = d.title
	_info_lines.text = "\n".join(d.lines)
	Sfx.play("click", 1.2, -6.0)
	if _info_tw:
		_info_tw.kill()
	_info.visible = true
	_info.modulate.a = 0.0
	_info.pivot_offset = _info.size * 0.5
	_info.scale = Vector2(0.85, 0.85)
	_info_tw = create_tween()
	_info_tw.set_parallel(true)
	_info_tw.tween_property(_info, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_info_tw.tween_property(_info, "modulate:a", 1.0, 0.15)
	_info_tw.chain().tween_interval(5.0)
	_info_tw.chain().tween_property(_info, "modulate:a", 0.0, 0.4)
	_info_tw.chain().tween_callback(func(): _info.visible = false)


func _hide_info() -> void:
	if _info_tw:
		_info_tw.kill()
	_info.visible = false


# ------------------------------------------------------------------ city stats

const DEMAND_COLS := [Color("59b84a"), Color("3f8cff"), Color("22b5b5"), Color("e8a21a")]
var _stats_panel: PanelContainer
var _stats_title: Label
var _stats_next: Label
var _stats_bar: ProgressBar
var _stats_lines: Label
var _demand_bars: Array[ProgressBar] = []


## The city at a glance, under the population: its milestone and the next
## one, people and jobs, what it has built, and what it wants more of.
func _build_stats_panel() -> void:
	_stats_panel = PanelContainer.new()
	_stats_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_stats_panel.offset_left = -340
	_stats_panel.offset_right = -18
	_stats_panel.offset_top = 96
	_stats_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_stats_panel.material = _glass_light
	_stats_panel.add_theme_stylebox_override("panel", _glass_box(GLASS, 20, 14))
	_root.add_child(_stats_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	_stats_panel.add_child(v)
	_stats_title = _label("", 20, true, INK)
	v.add_child(_stats_title)
	_stats_bar = ProgressBar.new()
	_stats_bar.custom_minimum_size = Vector2(290, 7)
	_stats_bar.show_percentage = false
	_stats_bar.max_value = 1.0
	_stats_bar.step = 0.0
	v.add_child(_stats_bar)
	_stats_next = _wrap_label("", 13, false, SOFT)
	_stats_next.custom_minimum_size.x = 290
	v.add_child(_stats_next)
	_stats_lines = _label("", 14, false, INK)
	v.add_child(_stats_lines)
	v.add_child(_label("Demand", 15, true, INK))
	for i in USES.size():
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		v.add_child(h)
		var ic := _icon(USES[i][1], 22)
		ic.custom_minimum_size = Vector2(22, 22)
		h.add_child(ic)
		var nl := _label(USES[i][0], 13, true, INK)
		nl.custom_minimum_size.x = 70
		h.add_child(nl)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(170, 10)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.show_percentage = false
		bar.max_value = 1.0
		bar.step = 0.0
		var fill := StyleBoxFlat.new()
		fill.bg_color = DEMAND_COLS[i]
		fill.set_corner_radius_all(5)
		bar.add_theme_stylebox_override("fill", fill)
		h.add_child(bar)
		_demand_bars.append(bar)
	_stats_panel.visible = false


func _toggle_stats() -> void:
	Sfx.play("click", 1.1, -4.0)
	_stats_panel.visible = not _stats_panel.visible
	_refresh_stats_panel()


func _refresh_stats_panel() -> void:
	if _stats_panel == null or not _stats_panel.visible:
		return
	var pr := island.progress
	_stats_title.text = pr.title
	var nt := pr.next_title()
	_stats_bar.value = nt[1]
	if nt[0] == "":
		_stats_next.text = "The biggest city there is"
	else:
		var opens: Array = []
		for k in IslandProgress.unlocks_at(nt[2]):
			opens.append(unlock_name(k).get_slice(": ", 1))
		_stats_next.text = "Next: %s at %d residents (+%d coins)%s" % [nt[0], nt[2], int(pr.milestone_reward(nt[0])),
			", opens " + ", ".join(opens) if not opens.is_empty() else ""]
	var lines := [
		"%d residents  ·  %d jobs  ·  %d%% out of work" % [pr.residents, pr.jobs, int(round(pr.unemployment() * 100.0))],
		"%d homes  ·  %d shops  ·  %d works  ·  %d parks" % [pr.homes, pr.shops, pr.works, pr.parks],
		"%.1f km of streets  ·  %d vehicles" % [pr.street_m / 1000.0, island.cars._cars.size()],
		"Taxes: %s coins every few seconds" % str(pr.income()),
	]
	_stats_lines.text = "\n".join(lines)
	for i in _demand_bars.size():
		_demand_bars[i].value = pr.demand[i]
		_demand_bars[i].modulate.a = 1.0 if pr.can_use(IslandProgress.USE_KEYS[i]) else 0.4


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
		# warnings stay small: a slim red pill, not a banner
		bg = Color(0.85, 0.3, 0.27)
		col = Color.WHITE
		size = 13
		p.material = _glass_accent
	var warn := kind == "warn"
	p.add_theme_stylebox_override("panel", _glass_box(bg, 14 if warn else 24, 8 if warn else 18, Color(1, 1, 1, 0.5 if bg == GLASS_DARK else 0.95), not warn))
	if warn:
		p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
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
	# beside the town's name card, hanging from the top
	_goals = PanelContainer.new()
	_goals.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_glassify(_goals)
	_goals.add_theme_stylebox_override("panel", _glass_box(GLASS, 14, 8))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	_goals.add_child(v)
	# the header folds the list away, for when the view needs the room
	var head := Button.new()
	head.flat = true
	head.focus_mode = Control.FOCUS_NONE
	head.custom_minimum_size = Vector2(196, 20)
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		head.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	var hr := HBoxContainer.new()
	hr.set_anchors_preset(Control.PRESET_FULL_RECT)
	hr.add_theme_constant_override("separation", 6)
	hr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(hr)
	hr.add_child(_icon("star", 15))
	var title := _label("Town goals", 12, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hr.add_child(title)
	_goal_count = _label("", 10, true, SOFT)
	_goal_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hr.add_child(_goal_count)
	_goal_fold = _label("", 10, true, SOFT)
	_goal_fold.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hr.add_child(_goal_fold)
	head.pressed.connect(func():
		Sfx.play("click")
		_goals_open = not _goals_open
		_goal_rows.visible = _goals_open
		_goal_fold.text = "-" if _goals_open else "+")
	v.add_child(head)
	_goal_rows = VBoxContainer.new()
	_goal_rows.add_theme_constant_override("separation", 5)
	v.add_child(_goal_rows)
	_top_col.add_child(_goals)


func _refresh_goals() -> void:
	if _goal_rows == null:
		return
	for c in _goal_rows.get_children():
		c.queue_free()
	var ready := 0
	var list := _goal_list()
	# the ones to collect first, then the rest nearest to done
	var order: Array = range(list.size())
	order.sort_custom(func(a: int, b: int) -> bool:
		var ra: bool = list[a].get("ready", false)
		var rb: bool = list[b].get("ready", false)
		if ra != rb:
			return ra
		return _goal_frac(list[a]) > _goal_frac(list[b]))
	for i: int in order:
		var g: Dictionary = list[i]
		if g.get("ready", false):
			ready += 1
		_goal_rows.add_child(_goal_row(i, g))
	_goal_count.text = ("%d to collect" % ready) if ready > 0 else ("%d done" % _goals_done())
	_goal_count.add_theme_color_override("font_color", ACCENT if ready > 0 else SOFT)
	_goal_fold.text = "-" if _goals_open else "+"
	_goals.visible = not list.is_empty()


## One goal: its icon, what to do over a thin
## bar of how far along it is, and the reward, which turns into a Collect
## chip once it is done.
func _goal_row(i: int, g: Dictionary) -> Control:
	var ready: bool = g.get("ready", false)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var ic := _icon(str(g.icon), 16)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ic)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(col)
	var t := _label(str(g.text), 10, true)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size.x = 140
	col.add_child(t)
	var pb := ProgressBar.new()
	pb.custom_minimum_size = Vector2(0, 4)
	pb.show_percentage = false
	pb.max_value = 1.0
	pb.step = 0.0
	pb.value = 1.0 if ready else _goal_frac(g)
	pb.add_theme_stylebox_override("background", _box(Color(INK, 0.1), 2, 0, false))
	pb.add_theme_stylebox_override("fill", _box(MINT if ready else Color("f2a93b"), 2, 0, false))
	if not ready:
		pb.set_meta("goal", i)
	col.add_child(pb)
	if ready:
		var b := Button.new()
		b.text = "+%s" % _short(float(g.reward))
		b.custom_minimum_size = Vector2(46, 22)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = "Collect"
		b.add_theme_font_size_override("font_size", 11)
		b.add_theme_stylebox_override("normal", _box(ACCENT, 11, 4))
		b.add_theme_stylebox_override("hover", _box(ACCENT.lightened(0.1), 11, 4))
		b.add_theme_stylebox_override("pressed", _box(ACCENT.darkened(0.1), 11, 4, false))
		for fc in ["font_color", "font_hover_color", "font_pressed_color"]:
			b.add_theme_color_override(fc, Color.WHITE)
		b.pressed.connect(_claim_goal.bind(i, b))
		row.add_child(b)
		# a gentle breathing pulse so it is hard to miss
		b.pivot_offset = Vector2(23, 11)
		var tw := b.create_tween().set_loops()
		tw.tween_property(b, "scale", Vector2(1.06, 1.06), 0.55).set_trans(Tween.TRANS_SINE)
		tw.tween_property(b, "scale", Vector2.ONE, 0.55).set_trans(Tween.TRANS_SINE)
	else:
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 2)
		r.custom_minimum_size.x = 46
		r.alignment = BoxContainer.ALIGNMENT_END
		r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		r.add_child(_icon("coin", 11))
		r.add_child(_label(_short(float(g.reward)), 10, true, Color("b46a1f")))
		row.add_child(r)
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
	_new_btn.text = "Start a new map"
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
	island.set_hyper(on and Game.settings.get("hyper", true))
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
	for key in [["music", "Music"], ["sfx", "Sound effects"], ["shadows", "Shadows"], ["hyper", "Hyper graphics in photo mode"], ["fps", "Show FPS & triangles"]]:
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
	# the time of day: round the clock by itself, or held where the player likes it
	st.add_child(_label("Time of day", 16, true, SOFT))
	var times := HBoxContainer.new()
	times.add_theme_constant_override("separation", 6)
	st.add_child(times)
	var time_group := ButtonGroup.new()
	for key in [["auto", "Auto"], ["sunrise", "Sunrise"], ["day", "Day"], ["sunset", "Sunset"], ["night", "Night"]]:
		var b := Button.new()
		b.text = key[1]
		b.toggle_mode = true
		b.button_group = time_group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = 48
		b.add_theme_font_size_override("font_size", 16)
		b.add_theme_stylebox_override("normal", _box(Color(1, 1, 1, 0.85), 18, 6, false))
		b.add_theme_stylebox_override("hover", _box(Color(1, 1, 1, 0.95), 18, 6, false))
		b.add_theme_stylebox_override("pressed", _box(ACCENT, 18, 6, false))
		b.add_theme_stylebox_override("hover_pressed", _box(ACCENT, 18, 6, false))
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		for c in ["font_color", "font_hover_color"]:
			b.add_theme_color_override(c, INK)
		for c in ["font_pressed_color", "font_hover_pressed_color"]:
			b.add_theme_color_override(c, Color.WHITE)
		b.button_pressed = Game.settings.get("time", "auto") == key[0]
		b.pressed.connect(func():
			Sfx.play("click")
			Game.settings["time"] = key[0]
			Game.save_settings())
		times.add_child(b)
	# which way the sun's daily arc runs across the city, swung round the compass
	var sun_title := _label("", 16, true, SOFT)
	st.add_child(sun_title)
	var sun_slider := HSlider.new()
	sun_slider.min_value = 0
	sun_slider.max_value = 360
	sun_slider.step = 5
	sun_slider.custom_minimum_size.y = 44
	var sun_track := _box(Color(1, 1, 1, 0.85), 6, 0, false)
	sun_track.content_margin_top = 5
	sun_track.content_margin_bottom = 5
	var fill := _box(ACCENT, 6, 0, false)
	fill.content_margin_top = 5
	fill.content_margin_bottom = 5
	sun_slider.add_theme_stylebox_override("slider", sun_track)
	sun_slider.add_theme_stylebox_override("grabber_area", fill)
	sun_slider.add_theme_stylebox_override("grabber_area_highlight", fill)
	sun_slider.value = float(Game.settings.get("sun_angle", 0.0))
	sun_title.text = "Sun direction  %d°" % int(sun_slider.value)
	sun_slider.value_changed.connect(func(v: float):
		Game.settings["sun_angle"] = v
		sun_title.text = "Sun direction  %d°" % int(v))
	sun_slider.drag_ended.connect(func(_changed: bool): Game.save_settings())
	st.add_child(sun_slider)
	# updates: look for a new version now, not only at start
	st.add_child(_label("Version %s" % Updater.current, 16, true, SOFT))
	var upd := Button.new()
	upd.text = "Check for updates"
	upd.custom_minimum_size.y = 54
	upd.add_theme_font_size_override("font_size", 18)
	upd.add_theme_stylebox_override("normal", _box(Color(1, 1, 1, 0.85), 18, 16, false))
	upd.add_theme_stylebox_override("hover", _box(Color(1, 1, 1, 0.95), 18, 16, false))
	upd.add_theme_stylebox_override("pressed", _box(Color(1, 1, 1, 0.7), 18, 16, false))
	upd.add_theme_stylebox_override("disabled", _box(Color(1, 1, 1, 0.6), 18, 16, false))
	upd.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color"]:
		upd.add_theme_color_override(c, INK)
	st.add_child(upd)
	_update_msg = _wrap_label("", 16, true, SOFT)
	_update_msg.visible = false
	st.add_child(_update_msg)
	upd.pressed.connect(func():
		Sfx.play("click")
		upd.disabled = true
		upd.text = "Checking…"
		_update_msg.visible = false
		Updater.check_now())
	Updater.checked.connect(func(status: String, version: String):
		upd.disabled = false
		upd.text = "Check for updates"
		_update_msg.visible = true
		_update_msg.add_theme_color_override("font_color", MINT if status == "latest" or status == "newer" else SOFT)
		_update_msg.text = update_text(status, version))

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

