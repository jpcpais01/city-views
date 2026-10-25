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
	# (only in Change mode: a back street like the ones the town grows itself)
	"side": ["Lane", "Drag along roads to calm them into quiet lanes, like the town's own back streets"],
	"main": ["Street", "Draw a line: the street lays itself over the land"],
	"avenue": ["Avenue", "A wide boulevard with a planted middle: side streets branch off it and shops line it"],
}
const LEVELS := ["Village", "Town", "City", "Centre", "Downtown", "Skyline", "Mega"]
const LEVEL_INFO := ["cottages and small houses", "houses and low terraces", "terraces with shops", "tall terraces and blocks, shops everywhere",
	"apartment blocks and offices", "towers over a busy podium", "supertall towers, mega malls, arenas and industrial complexes"]
## the districts the Grow brush paints: [name, icon, help]
const USES := [["Homes", "house", "homes"], ["Shops", "shop", "shops on every ground floor"],
	["Offices", "office", "offices and jobs"], ["Industry", "factory", "workshops and factories, jobs but no homes"],
	["Entertainment", "ferris", "bars, clubs, theatres, cinemas and arenas: jobs and nights out"]]

var island: IslandWorld
var _brush_keys := {}
var _size_btn: Button
var _size_i := 1
var _level_bar: Control
var _road_bar: Control
var _road_keys := {}
var _change_key: Button
## plans the map's highways afresh (IslandWorld.reroll_highways)
var _reroll_key: Button
var _rerolling := false
## what the Change mode's stroke would cost, floating over the road
var _change_tag: PanelContainer
var _change_label: Label
var _level_keys: Array[Button] = []
var _use_keys: Array[Button] = []
var _use_bar: Control
var _help: Label
var _island_name: LineEdit
var _title_chip: Label
var _next_line: Label
var _income_label: Label
var _locks := {}

var font_bold: FontVariation
var font_reg: FontVariation
var _root: Control
var _pop_label: Label
var _coin_label: Label
var _progress: ProgressBar
var _toasts: VBoxContainer
var _players_row: HBoxContainer
## the pause menu (GameMenu), over everything else in _root
var _menu: GameMenu
var _coins_shown := 0.0
var _fps_label: Label
var _fps_time := 0.0
var _undo_btn: Button
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
# drive mode (DriveMode): the HUD steps aside while the player drives
var drive: DriveMode
var _driving := false
var _drive_hidden: Array[Control] = []

# the HUD wears UiKit's smoked glass: white type on dark frosted panels
const INK := Color("f5f7fb")
const SOFT := Color(0.92, 0.94, 0.98, 0.66)
const CARD := Color(0.085, 0.1, 0.135, 0.97)
const ACCENT := Color("ff7a6b")
const MINT := Color("4fd6a6")
const GOLD := Color("ffcf6b")
const GLASS := Color(0.075, 0.09, 0.125)
const GLASS_DARK := Color(0.03, 0.04, 0.06)
## a selected key: bright like the menu rail, with dark type
const KEY_ON := Color(0.97, 0.98, 1.0)
const ON_LIGHT := Color("161b24")


# ------------------------------------------------------------------ theme

func _glass_mat(tint: float) -> ShaderMaterial:
	return UiKit.glass_mat(tint)


## Smoked glass panel style (see UiKit.glass_box): `tint` is its colour, and
## the rim is kept to a hairline whatever colour is asked for.
func _glass_box(tint := GLASS, radius := 24, pad := 14, rim := Color(1, 1, 1, 0.16), shadow := true) -> StyleBoxFlat:
	var sb := UiKit.glass_box(radius, pad, tint, 16 if shadow else 0)
	sb.content_margin_top = pad * 0.7
	sb.content_margin_bottom = pad * 0.7
	sb.border_color = Color(rim.r, rim.g, rim.b, minf(rim.a, 0.22))
	return sb


func _glassify(c: Control, dark := false) -> void:
	c.material = _glass_dark if dark else _glass_light
	if c is PanelContainer:
		c.add_theme_stylebox_override("panel", _glass_box(GLASS_DARK if dark else GLASS, 22, 14))


func _box(bg: Color, radius := 22, pad := 14, shadow := true) -> StyleBoxFlat:
	var sb := UiKit.box(bg, radius, pad, Color(0, 0, 0, 0), 0, 8 if shadow else 0)
	sb.content_margin_top = pad * 0.7
	sb.content_margin_bottom = pad * 0.7
	return sb


func _make_theme() -> Theme:
	return UiKit.theme()


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
	font_bold = UiKit.font(800)
	font_reg = UiKit.font(600)
	_glass_light = _glass_mat(0.62)
	_glass_dark = _glass_mat(0.78)
	_glass_accent = _glass_mat(0.84)
	if not OS.has_feature("mobile"):
		get_window().size_changed.connect(_fit_desktop_scale)
	apply_ui_scale()
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = _make_theme()
	add_child(_root)
	get_viewport().size_changed.connect(_apply_side_margins)
	_apply_side_margins()
	_build_island_top()
	_build_brushes()
	_build_hint()
	_build_fps()
	_build_toasts()
	_build_info()
	_build_stats_panel()
	_build_goals()
	_build_menu()
	_build_photo_exit()
	drive = DriveMode.new()
	drive.island = island
	drive.hud = self
	add_child(drive)
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
	_refresh_brushes()
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
	var csb := UiKit.box(Color(GOLD, 0.16), 8, 9, Color(GOLD, 0.5), 1)
	csb.content_margin_top = 2
	csb.content_margin_bottom = 2
	chip.add_theme_stylebox_override("panel", csb)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_title_chip = _label("Hamlet", 13, true, GOLD)
	chip.add_child(_title_chip)
	name_row.add_child(chip)
	_progress = ProgressBar.new()
	_progress.custom_minimum_size = Vector2(230, 7)
	_progress.show_percentage = false
	_progress.max_value = 1.0
	_progress.step = 0.0
	_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_progress.add_theme_stylebox_override("fill", UiKit.box(GOLD, 4, 0))
	_progress.add_theme_stylebox_override("background", UiKit.box(Color(1, 1, 1, 0.12), 4, 0))
	v.add_child(_progress)
	# the next milestone, in small type under the bar
	_next_line = _label("", 12, false, Color(1, 1, 1, 0.5))
	v.add_child(_next_line)
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
	# what the city pays in taxes, small beside the coins
	_income_label = _label("", 12, true, MINT)
	_income_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_coin_label.get_parent().add_child(_income_label)
	var photo_btn := _glass_button(58, "camera")
	photo_btn.tooltip_text = "Photo mode  (H)"
	photo_btn.pressed.connect(func(): set_photo(true))
	photo_btn.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	stats.add_child(photo_btn)
	var drive_btn := _glass_button(58, "car")
	drive_btn.tooltip_text = "Drive a car through your streets"
	drive_btn.pressed.connect(func(): drive.set_active(true))
	drive_btn.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	stats.add_child(drive_btn)
	var menu_btn := _glass_button(58, "menu")
	menu_btn.tooltip_text = "Menu  (Esc)"
	menu_btn.pressed.connect(_toggle_menu)
	menu_btn.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	stats.add_child(menu_btn)


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
	e.add_theme_color_override("caret_color", ACCENT)
	for st in ["normal", "read_only"]:
		e.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	e.add_theme_stylebox_override("focus", UiKit.box(Color(0, 0, 0, 0.35), 10, 6, ACCENT, 1))
	e.text_submitted.connect(func(t):
		island.set_island_name(t)
		e.release_focus())
	e.focus_exited.connect(func(): island.set_island_name(e.text))
	return e


func _refresh_island_name() -> void:
	if _island_name and not _island_name.has_focus():
		_island_name.text = island.island_name


func _refresh_stats() -> void:
	_refresh_stats_panel()
	var pr := island.progress
	_pop_label.text = _short(pr.residents)
	_title_chip.text = pr.title
	var nt := pr.next_title()
	_progress.value = nt[1]
	_next_line.text = "Next: %s at %s residents" % [nt[0], UiKit.short(nt[2])] if nt[0] != "" else "Every milestone reached"
	var inc := pr.income()
	_income_label.text = "+%s" % (str(int(inc)) if inc >= 10.0 else str(snappedf(inc, 0.1))) if inc > 0.0 else ""
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
		var n := IslandWorld.BRUSHES.find(id) + 1
		b.tooltip_text = "%s  (%d)\n%s" % [BRUSH_INFO[id][0], n, BRUSH_INFO[id][1]] if n <= 9 else BRUSH_INFO[id][0]
		if n <= 9 and not OS.has_feature("mobile"):
			# the number key that picks it, small in the corner, as on a PC hotbar
			var nk := _label(str(n), 10, true, Color(1, 1, 1, 0.45))
			nk.position = Vector2(8, 4)
			b.add_child(nk)
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
	_size_btn.add_theme_color_override("font_pressed_color", ON_LIGHT)
	_size_btn.add_theme_color_override("font_hover_pressed_color", ON_LIGHT)
	_size_btn.tooltip_text = "Brush size  ([ and ])"
	var cap := UiKit.eyebrow("Size", Color(1, 1, 1, 0.45), 9)
	cap.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	cap.grow_horizontal = Control.GROW_DIRECTION_BOTH
	cap.offset_top = -22
	cap.offset_bottom = -8
	_size_btn.add_child(cap)
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
	# Change: raise or lower roads already there to the kind picked
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(6, 0)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(gap)
	_change_key = _key(116, 50)
	var ch := HBoxContainer.new()
	ch.set_anchors_preset(Control.PRESET_FULL_RECT)
	ch.alignment = BoxContainer.ALIGNMENT_CENTER
	ch.add_theme_constant_override("separation", 4)
	ch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_change_key.add_child(ch)
	var ci := _icon("road_change", 34)
	ci.custom_minimum_size = Vector2(34, 34)
	ch.add_child(ci)
	ch.add_child(_label("Change", 14, true, INK))
	_change_key.pressed.connect(func():
		island.street_change = not island.street_change
		if not island.street_change and island.street_kind == "side":
			island.street_kind = "main"
		island.change_plan = []
		Sfx.play("click", 1.3 if island.street_change else 1.0, -4.0)
		_refresh_brushes())
	row.add_child(_change_key)
	# Reroll: a new highway network for the whole map
	_reroll_key = _key(116, 50)
	var rr := HBoxContainer.new()
	rr.set_anchors_preset(Control.PRESET_FULL_RECT)
	rr.alignment = BoxContainer.ALIGNMENT_CENTER
	rr.add_theme_constant_override("separation", 4)
	rr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reroll_key.add_child(rr)
	var ri := _icon("road_reroll", 34)
	ri.custom_minimum_size = Vector2(34, 34)
	rr.add_child(ri)
	rr.add_child(_label("Highways", 14, true, INK))
	_reroll_key.pressed.connect(_reroll)
	row.add_child(_reroll_key)
	_build_change_tag()


## Plans the map's highways afresh: a word first (it takes a moment), then
## the new network and what it has.
func _reroll() -> void:
	if _rerolling:
		return
	_rerolling = true
	Sfx.play("click", 1.2, -4.0)
	show_toast("Planning a new highway network...", "info")
	# (two frames, so the word shows before the work)
	await get_tree().process_frame
	await get_tree().process_frame
	var count := island.reroll_highways()
	_rerolling = false
	Sfx.play("unlock", 1.1, -6.0, 0.05)
	Sfx.play("road", 0.8, -4.0)
	if count == 0:
		show_toast("No room for a highway on this map", "warn")
	else:
		show_toast("A new highway network: %d highway%s%s" % [count, "" if count == 1 else "s",
			", %d interchange%s" % [count - 1, "" if count == 2 else "s"] if count > 1 else ""], "info")
	_help.text = "Every tap plans the map's highways afresh, interchanges and all. Undo brings the last network back"
	_flash_hint()


## The cost of a Change stroke, in a little glass tag over the road.
func _build_change_tag() -> void:
	_change_tag = PanelContainer.new()
	_change_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_change_tag.material = _glass_dark
	_change_tag.add_theme_stylebox_override("panel", _glass_box(GLASS_DARK, 12, 12, Color(1, 1, 1, 0.12), false))
	_change_label = _label("", 14, true, INK)
	_change_tag.add_child(_change_label)
	_change_tag.visible = false
	_root.add_child(_change_tag)


func _tick_change_tag() -> void:
	var show := island.brush == "street" and island.street_change and not island.change_plan.is_empty() \
		and island._ring_at != null and not _photo and not _driving
	_change_tag.visible = show
	if not show:
		return
	var cost := island.change_cost
	var what: String = ROADS[island.street_kind][0]
	if cost > island.progress.coins:
		_change_label.text = "%s  ·  need %d coins" % [what, ceili(cost)]
		_change_label.add_theme_color_override("font_color", ACCENT)
	elif cost >= 0.0:
		_change_label.text = "%s  ·  %d coins" % [what, ceili(cost)]
		_change_label.add_theme_color_override("font_color", INK)
	else:
		_change_label.text = "%s  ·  +%d back" % [what, floori(-cost)]
		_change_label.add_theme_color_override("font_color", MINT)
	_change_tag.reset_size()
	var at: Vector3 = island._ring_at
	var cam := island.rig.cam
	if cam.is_position_behind(at):
		_change_tag.visible = false
		return
	_change_tag.global_position = cam.unproject_position(at) - Vector2(_change_tag.size.x * 0.5, _change_tag.size.y + 64.0)


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
		var b := _key(150 if USES[i][0].length() > 9 else 110, 44)
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
		_tint_key(_brush_keys[id], id == island.brush)
	island.brush_radius = SIZES[_size_i][1]
	_size_btn.text = SIZES[_size_i][0]
	if _road_bar:
		_road_bar.visible = island.brush == "street" and not _photo
		for id: String in _road_keys:
			var k: Button = _road_keys[id]
			k.set_pressed_no_signal(island.street_kind == id)
			_tint_key(k, island.street_kind == id)
			k.modulate.a = 1.0 if island.progress.can_use(id) else 0.5
			if id == "side":
				k.visible = island.street_change
		_change_key.set_pressed_no_signal(island.street_change)
		_tint_key(_change_key, island.street_change)
	if _level_bar:
		_level_bar.visible = island.brush == "grow" and not _photo
		for i in _level_keys.size():
			_level_keys[i].set_pressed_no_signal(island.grow_level == i + 1)
			_tint_key(_level_keys[i], island.grow_level == i + 1)
			_level_keys[i].modulate.a = 1.0 if island.progress.can_use("level%d" % (i + 1)) else 0.5
		_use_bar.visible = _level_bar.visible
		for i in _use_keys.size():
			_use_keys[i].set_pressed_no_signal(island.grow_use == i)
			_tint_key(_use_keys[i], island.grow_use == i)
			_use_keys[i].modulate.a = 1.0 if island.progress.can_use(IslandProgress.USE_KEYS[i]) else 0.5
	if island.brush != "":
		_help.text = BRUSH_INFO[island.brush][1]
		if island.brush == "street":
			_help.text = ROADS[island.street_kind][1]
			if island.street_change and island.street_kind != "side":
				_help.text = "Drag along roads, or tap one, to make them %s: between junctions, paying the difference" % ("streets" if island.street_kind == "main" else island.street_kind + "s")
		if island.brush == "grow":
			_help.text = "Paint beside a street. %s %s: %s" % [LEVELS[island.grow_level - 1], USES[island.grow_use][0].to_lower(), LEVEL_INFO[island.grow_level - 1]]
			if island.grow_use >= 3:
				_help.text = "Paint beside a street. %s %s: %s" % [LEVELS[island.grow_level - 1], USES[island.grow_use][0].to_lower(), USES[island.grow_use][2]]
	else:
		_help.text = "Draw streets, or shape the land: pick a brush"
	_flash_hint()



# ------------------------------------------------------------------ brush hint

var _hint: PanelContainer
var _hint_title: Label
var _hint_text: Label
var _hint_tw: Tween
var _hint_said := ""


## A slim card just above the tools saying what the brush in hand does; it
## shows when the brush (or its road, level or district) changes, then fades.
func _build_hint() -> void:
	var holder := CenterContainer.new()
	holder.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	holder.offset_top = -170
	holder.offset_bottom = -120
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(holder)
	_hint = PanelContainer.new()
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.material = _glass_dark
	_hint.add_theme_stylebox_override("panel", _glass_box(GLASS_DARK, 14, 16, Color(1, 1, 1, 0.12), false))
	holder.add_child(_hint)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.add_child(h)
	_hint_title = UiKit.eyebrow("", ACCENT, 11)
	_hint_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(_hint_title)
	_hint_text = _label("", 14, false, INK)
	_hint_text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(_hint_text)
	_hint.visible = false


func _flash_hint() -> void:
	if _hint == null:
		return
	var say := "" if island.brush == "" else _help.text
	if say == _hint_said:
		return
	_hint_said = say
	if _hint_tw:
		_hint_tw.kill()
	if say == "" or _photo or _driving:
		_hint.visible = false
		return
	_hint_title.text = BRUSH_INFO[island.brush][0].to_upper()
	if island.brush == "street":
		_hint_title.text = ROADS[island.street_kind][0].to_upper()
		if island.street_change:
			_hint_title.text = "CHANGE TO " + _hint_title.text
	_hint_text.text = say
	# sits just above whichever option bars are showing
	var holder := _hint.get_parent() as Control
	var top := -118.0
	if _road_bar and _road_bar.visible:
		top = -188.0
	if _use_bar and _use_bar.visible:
		top = -244.0
	holder.offset_bottom = top - 4.0
	holder.offset_top = top - 54.0
	_hint.visible = true
	_hint.modulate.a = 0.0
	_hint_tw = create_tween()
	_hint_tw.tween_property(_hint, "modulate:a", 1.0, 0.18)
	_hint_tw.tween_interval(3.2)
	_hint_tw.tween_property(_hint, "modulate:a", 0.0, 0.5)
	_hint_tw.tween_callback(func(): _hint.visible = false)


func _process(delta: float) -> void:
	var coins := island.progress.coins
	_coins_shown = lerpf(_coins_shown, coins, 1.0 - exp(-delta * 6.0))
	if absf(_coins_shown - coins) < 0.5:
		_coins_shown = coins
	_coin_label.text = _short(_coins_shown)
	if _goals.visible and _goals_open:
		_tick_goals()
	if _change_tag:
		_tick_change_tag()
	if _fps_label.visible:
		_fps_time += delta
		if _fps_time >= 0.5:
			_fps_time = 0.0
			var tris := Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
			_fps_label.text = "%d FPS\n%s tris" % [Engine.get_frames_per_second(), _short_count(tris)]


func _unhandled_key_input(event: InputEvent) -> void:
	# 1-9 pick the brushes in the order the bar shows them, [ and ] the brush size
	if event is InputEventKey and event.pressed and not event.echo and not event.ctrl_pressed and not _driving and not _photo:
		var n: int = event.keycode - KEY_1
		if n >= 0 and n < mini(9, IslandWorld.BRUSHES.size()):
			(_brush_keys[IslandWorld.BRUSHES[n]] as Button).pressed.emit()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_BRACKETLEFT or event.keycode == KEY_BRACKETRIGHT:
			_size_i = clampi(_size_i + (1 if event.keycode == KEY_BRACKETRIGHT else -1), 0, SIZES.size() - 1)
			Sfx.play("click", 0.9 + _size_i * 0.15, -4.0)
			_refresh_brushes()
			get_viewport().set_input_as_handled()
			return
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
	b.focus_mode = Control.FOCUS_NONE
	b.material = _glass_light
	b.pivot_offset = Vector2(w, h) * 0.5
	b.add_theme_stylebox_override("normal", _glass_box(GLASS, 20, 4))
	b.add_theme_stylebox_override("hover", _glass_box(GLASS.lightened(0.16), 20, 4))
	# picked: lit white like the menu's chosen section, with dark type (see _tint_key)
	var on := UiKit.box(KEY_ON, 20, 4, Color(0, 0, 0, 0), 0, 14)
	on.content_margin_top = 2.8
	on.content_margin_bottom = 2.8
	b.add_theme_stylebox_override("pressed", on)
	b.add_theme_stylebox_override("hover_pressed", on)
	b.add_theme_stylebox_override("disabled", _glass_box(GLASS, 20, 4))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.button_down.connect(func(): _squish(b, 0.92))
	b.button_up.connect(func(): _squish(b, 1.0))
	return b


## Recolours a key's type and icons for picked (dark on white) or not (white on glass),
## and drops the blur under a picked key so its white stays clean.
func _tint_key(b: Button, on: bool) -> void:
	if b.has_meta("on") and b.get_meta("on") == on:
		return
	b.set_meta("on", on)
	b.material = null if on else _glass_light
	for c in b.find_children("*", "", true, false):
		if c is UiIcon:
			c.color = ON_LIGHT if on else INK
			c.queue_redraw()
		elif c is Label and c.get_theme_font_size("font_size") > 10:
			c.add_theme_color_override("font_color", ON_LIGHT if on else INK)
		elif c is Label:
			c.add_theme_color_override("font_color", Color(ON_LIGHT, 0.4) if on else Color(1, 1, 1, 0.45))
	if on:
		b.pivot_offset = b.size * 0.5
		b.scale = Vector2(1.06, 1.06)
		_squish(b, 1.0)


## A round glass key holding only an icon (menu, undo, redo).
func _glass_button(px: int, icon := "menu") -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(px, px)
	b.focus_mode = Control.FOCUS_NONE
	b.material = _glass_light
	var r := px / 2
	b.add_theme_stylebox_override("normal", _glass_box(GLASS, r, 0))
	b.add_theme_stylebox_override("hover", _glass_box(GLASS.lightened(0.16), r, 0))
	b.add_theme_stylebox_override("pressed", _glass_box(GLASS.lightened(0.3), r, 0, Color(1, 1, 1, 0.3), false))
	b.add_theme_stylebox_override("disabled", _glass_box(GLASS, r, 0, Color(1, 1, 1, 0.08), false))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var ic := _icon(icon, int(px * 0.46))
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
	_info_lines = _label("", 14, false, SOFT)
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

const DEMAND_COLS := [Color("59b84a"), Color("3f8cff"), Color("22b5b5"), Color("e8a21a"), Color("d94fc8")]
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
	_stats_next = _label("", 13, false, SOFT)
	_stats_next.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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


## A notice under the top bar. "info" is a quiet glass line, "warn" a slim red
## pill, "unlock" a dark card with a gold eyebrow and "title" a big accent banner
## for a new milestone.
func show_toast(text: String, kind := "info") -> void:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var body := _label(text, 16, true, INK)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size.x = mini(text.length() * 9, 460)
	match kind:
		"warn":
			# warnings stay small: a slim red pill, not a banner
			p.material = _glass_accent
			p.add_theme_stylebox_override("panel", _glass_box(Color(0.78, 0.22, 0.2), 14, 14, Color(1, 1, 1, 0.2), false))
			body.add_theme_font_size_override("font_size", 13)
			body.custom_minimum_size.x = mini(text.length() * 7, 420)
		"unlock":
			p.material = _glass_dark
			p.add_theme_stylebox_override("panel", _glass_box(GLASS_DARK, 18, 18, Color(GOLD, 0.5)))
			var ic := _icon("star", 30)
			ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			h.add_child(ic)
			col.add_child(UiKit.eyebrow("Unlocked" if not text.begins_with("Goal") else "Goal complete", GOLD, 11))
			body.text = text.trim_prefix("Goal complete: ")
			body.add_theme_font_size_override("font_size", 19)
		"title":
			p.material = _glass_accent
			p.add_theme_stylebox_override("panel", _glass_box(ACCENT.darkened(0.08), 22, 24, Color(1, 1, 1, 0.4)))
			col.add_child(UiKit.eyebrow("New milestone", Color(1, 1, 1, 0.8), 12))
			body.add_theme_font_size_override("font_size", 24)
			body.custom_minimum_size.x = mini(text.length() * 13, 520)
		_:
			p.material = _glass_light
			p.add_theme_stylebox_override("panel", _glass_box(GLASS, 16, 16, Color(1, 1, 1, 0.16), false))
	col.add_child(body)
	h.add_child(col)
	_toasts.add_child(p)
	if _toasts.get_child_count() > 4:
		_toasts.get_child(0).queue_free()
	p.modulate.a = 0.0
	p.resized.connect(func(): p.pivot_offset = Vector2(p.size.x * 0.5, 0.0))
	p.scale = Vector2(0.9, 0.9)
	var tw := p.create_tween()
	tw.set_parallel(true)
	tw.tween_property(p, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(p, "modulate:a", 1.0, 0.2)
	tw.chain().tween_interval(3.4 if kind != "info" else 2.4)
	tw.chain().tween_property(p, "modulate:a", 0.0, 0.45)
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
	_goals.visible = not list.is_empty() and not _driving


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
	_set_menu(not _menu.is_open())


func _set_menu(open: bool, page := "") -> void:
	if open:
		_hide_info()
		_fade_hud(false)
		_menu.open(page)
	else:
		_menu.close()


## While the menu is up the rest of the HUD steps back, so nothing ghosts
## through the blur behind it.
func _fade_hud(show: bool) -> void:
	for c in _root.get_children():
		if c == _menu or not c is CanvasItem:
			continue
		var ci := c as CanvasItem
		var tw := ci.create_tween()
		tw.tween_property(ci, "modulate:a", 1.0 if show else 0.0, 0.2 if show else 0.15)


## Builds the pause menu on top of the rest of the HUD.
func _build_menu() -> void:
	_menu = GameMenu.new(self)
	_root.add_child(_menu)
	_menu.closed.connect(func(): _fade_hud(true))


func set_fps_visible(on: bool) -> void:
	_fps_label.visible = on


## What the Settings page says after a check for updates (kept here for older callers).
static func update_text(status: String, version: String) -> String:
	return GameMenu.update_text(status, version)


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
			if c != _photo_exit and c != _menu and c.visible:
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


## Drive mode hides the building HUD (all but the FPS counter and toasts)
## and brings it back when the player gets out of the car.
func set_drive(on: bool) -> void:
	if on == _driving:
		return
	_driving = on
	if on:
		if _photo:
			set_photo(false)
		_set_menu(false)
		_hide_info()
		_drive_hidden.clear()
		for c: Control in _root.get_children():
			if c.visible and c != _fps_label and c != _toasts and c != _menu:
				_drive_hidden.append(c)
				c.hide()
	else:
		for c in _drive_hidden:
			c.show()
			c.modulate.a = 0.0
			create_tween().tween_property(c, "modulate:a", 1.0, 0.3)
		_drive_hidden.clear()


func _notification(what: int) -> void:
	# Android back gesture leaves photo mode, or closes the menu
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and _photo:
		set_photo(false)
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST and _menu != null and _menu.is_open():
		_set_menu(false)


func _input(event: InputEvent) -> void:
	UiKit.track_input(event)
	if _photo and event.is_action_pressed("ui_cancel"):
		set_photo(false)
		get_viewport().set_input_as_handled()
	elif _menu != null and not _menu.visible and not _driving and not get_viewport().gui_get_focus_owner() is LineEdit:
		# Esc or a pad's Start opens the menu, like any PC or console game
		var esc: bool = event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE
		var start: bool = event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_START
		if esc or start:
			_set_menu(true)
			get_viewport().set_input_as_handled()


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
	var f := clampf(0.95 * clampf(px, 0.85, 3.0) / stretch, 0.45, 1.0) * ui_scale()
	if absf(w.content_scale_factor - f) > 0.001:
		w.content_scale_factor = f


## The player's Interface size setting (Settings > Interface), 1.0 = normal.
static func ui_scale() -> float:
	return clampf(float(Game.settings.get("ui_scale", 1.0)), 0.75, 1.3)


func apply_ui_scale() -> void:
	if OS.has_feature("mobile"):
		get_window().content_scale_factor = ui_scale()
	else:
		_fit_desktop_scale()


func _apply_side_margins() -> void:
	var size := get_viewport().get_visible_rect().size
	var m := 0.03 if size.x > size.y else 0.0
	_root.anchor_left = m
	_root.anchor_right = 1.0 - m
	_root.offset_left = 0
	_root.offset_right = 0


