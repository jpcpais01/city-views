class_name AdvisorBot
extends Control
## Pip, the little city advisor who lives in the bottom corner. Tap Pip and
## ask for a look round: Pip thinks for a moment, gives the city a score with
## four meters (jobs, shops, green, calm), and up to three tips, each lit up
## on the map. Tap a tip to fly there; Paint picks up the right brush, with
## the district and level already chosen. Now and then Pip has a quiet look
## by itself and waves (a little badge) when something needs the mayor.

const INK := Color("f5f7fb")
const SOFT := Color(0.92, 0.94, 0.98, 0.66)
const GLASS := Color(0.075, 0.09, 0.125)
const ACCENT := Color("ff7a6b")
const FACE := 84.0
const WIDTH := 430.0
## the bubble stays below the pills along the top
const TOP := 92.0
## seconds between Pip's quiet looks round
const LOOK_EVERY := 25.0
const HELLO := "Hi, I'm Pip, your city advisor! I can look over your districts, jobs, shops and parks, then show you where to paint what."

var island: IslandWorld
var hud: Hud
var marks: AdvisorMarks
var _face: PipFace
var _bubble: PanelContainer
var _tail: Control
var _say: Label
var _score_row: HBoxContainer
var _score_badge: PanelContainer
var _score_label: Label
var _headline: Label
var _meters: GridContainer
var _tips_box: VBoxContainer
var _go: Button
var _report := {}
# a report from a quiet look, waiting to be opened
var _fresh := {}
var _open := false
var _think := -1.0
var _look := LOOK_EVERY
var _seen := ""
var _glass: ShaderMaterial
var _tw: Tween
var _bold: Font
var _reg: Font
var _raised := false
var _settle := 0.5


## Puts Pip in the corner of the interface.
static func attach(h: Hud, world: IslandWorld) -> AdvisorBot:
	var bot := AdvisorBot.new()
	bot.hud = h
	bot.island = world
	var root: Control = h.get("_root")
	root.add_child(bot)
	# under the menu, which covers everything when open
	var menu: Variant = h.get("_menu")
	if menu is Control and (menu as Control).get_parent() == root:
		root.move_child(bot, (menu as Control).get_index())
	return bot


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bold = hud.font_bold if hud and hud.font_bold else ThemeDB.fallback_font
	_reg = hud.font_reg if hud and hud.font_reg else ThemeDB.fallback_font
	_glass = ShaderMaterial.new()
	_glass.shader = preload("res://src/ui/glass.gdshader")
	_glass.set_shader_parameter("tint", 0.66)
	marks = AdvisorMarks.new(island.land, _bold)
	island.add_child(marks)
	_build_face()
	_build_bubble()
	island.progress.title_changed.connect(func(_t): _face.cheer())
	resized.connect(_place)
	_place.call_deferred()


func _exit_tree() -> void:
	if is_instance_valid(marks):
		marks.queue_free()


# ------------------------------------------------------------------ building

func _build_face() -> void:
	_face = PipFace.new()
	_face.size = Vector2(FACE, FACE)
	_face.custom_minimum_size = _face.size
	_face.pivot_offset = _face.size * Vector2(0.5, 1.0)
	_face.gui_input.connect(_on_face_input)
	_face.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_face.tooltip_text = "Pip, your city advisor"
	add_child(_face)


func _build_bubble() -> void:
	_tail = BubbleTail.new()
	_tail.size = Vector2(26, 14)
	_tail.visible = false
	add_child(_tail)
	_bubble = PanelContainer.new()
	_bubble.material = _glass
	_bubble.add_theme_stylebox_override("panel", _glass_box(GLASS, 24, 16))
	_bubble.custom_minimum_size = Vector2(WIDTH, 0)
	_bubble.visible = false
	_bubble.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_bubble)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_bubble.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	v.add_child(head)
	var name_l := _label("Pip", 20, true)
	head.add_child(name_l)
	var role := _label("City advisor", 14, false, SOFT)
	role.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(role)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(gap)
	var close := Button.new()
	close.flat = true
	close.focus_mode = Control.FOCUS_NONE
	close.custom_minimum_size = Vector2(34, 34)
	for st in ["normal", "hover", "pressed", "focus"]:
		close.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	var x := UiIcon.new("close", SOFT, ACCENT)
	x.set_anchors_preset(Control.PRESET_FULL_RECT)
	x.offset_left = 7
	x.offset_top = 7
	x.offset_right = -7
	x.offset_bottom = -7
	close.add_child(x)
	close.pressed.connect(func(): _close(true))
	head.add_child(close)
	_score_row = HBoxContainer.new()
	_score_row.add_theme_constant_override("separation", 12)
	_score_row.visible = false
	v.add_child(_score_row)
	_score_badge = PanelContainer.new()
	_score_badge.custom_minimum_size = Vector2(58, 58)
	_score_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_score_row.add_child(_score_badge)
	_score_label = _label("", 26, true, Color.WHITE)
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_score_badge.add_child(_score_label)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 4)
	sv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_score_row.add_child(sv)
	_headline = _label("", 18, true)
	sv.add_child(_headline)
	_meters = GridContainer.new()
	_meters.columns = 4
	_meters.add_theme_constant_override("h_separation", 8)
	_meters.add_theme_constant_override("v_separation", 1)
	sv.add_child(_meters)
	_say = _label(HELLO, 15, false)
	_say.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_say.custom_minimum_size = Vector2(WIDTH - 32, 0)
	v.add_child(_say)
	_tips_box = VBoxContainer.new()
	_tips_box.add_theme_constant_override("separation", 6)
	v.add_child(_tips_box)
	_go = Button.new()
	_go.text = "Look over my city"
	_go.focus_mode = Control.FOCUS_NONE
	_go.custom_minimum_size = Vector2(0, 46)
	_go.add_theme_font_override("font", _bold)
	_go.add_theme_font_size_override("font_size", 17)
	_go.add_theme_stylebox_override("normal", _box(ACCENT, 23, 16))
	_go.add_theme_stylebox_override("hover", _box(ACCENT.lightened(0.08), 23, 16))
	_go.add_theme_stylebox_override("pressed", _box(ACCENT.darkened(0.1), 23, 16))
	_go.add_theme_stylebox_override("disabled", _box(Color(ACCENT, 0.55), 23, 16))
	_go.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color"]:
		_go.add_theme_color_override(c, Color.WHITE)
	_go.pressed.connect(_analyse)
	v.add_child(_go)


## Keeps Pip in the bottom corner, and lifts Pip above the brushes when the
## screen is too narrow for both side by side.
func _place() -> void:
	var lift := 14.0
	var row: Variant = hud.get("_undo_btn") if hud else null
	if row is Control and (row as Control).get_parent() is Control:
		var bar := (row as Control).get_parent() as Control
		_raised = bar.get_global_rect().end.x + 12.0 > global_position.x + size.x - FACE - 6.0
	if _raised:
		lift = 118.0
	_face.position = Vector2(size.x - FACE - 6.0, size.y - FACE - lift)
	_fit_bubble()


func _fit_bubble() -> void:
	var w := minf(WIDTH, size.x - 12.0)
	_bubble.custom_minimum_size.x = w
	_say.custom_minimum_size.x = w - 32.0
	_bubble.reset_size()
	var h := _bubble.get_combined_minimum_size().y
	_bubble.size = Vector2(w, h)
	var y := _face.position.y - 15.0 - h
	if y >= TOP or size.x - w - FACE - 14.0 < 0.0:
		_bubble.position = Vector2(size.x - w - 2.0, maxf(y, 6.0))
		_bubble.pivot_offset = Vector2(w - FACE * 0.5, h)
		_tail.rotation = 0.0
		_tail.position = Vector2(size.x - FACE * 0.5 - 6.0 - 13.0, _face.position.y - 16.0)
	else:
		# too tall to sit over Pip: beside Pip instead, the tail pointing right
		_bubble.position = Vector2(size.x - w - FACE - 14.0, clampf(_face.position.y + FACE - h, TOP, maxf(size.y - h - 6.0, TOP)))
		_bubble.pivot_offset = Vector2(w, h)
		_tail.rotation = -PI * 0.5
		_tail.position = Vector2(size.x - FACE - 15.0, _face.position.y + FACE * 0.5 + 13.0)


# ------------------------------------------------------------------ talking

func _on_face_input(e: InputEvent) -> void:
	var tap: bool = (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) or (e is InputEventScreenTouch and e.pressed)
	if not tap:
		return
	accept_event()
	Sfx.play("pop", 1.25, -4.0)
	_face.boop()
	if _open:
		_close(false)
		return
	if not _fresh.is_empty():
		_report = _fresh
		_fresh = {}
		_face.badge = false
		_open_bubble()
		_show_report(_report)
		return
	_open_bubble()
	if _report.is_empty():
		_hello()
	else:
		_show_report(_report)


func _hello() -> void:
	_score_row.visible = false
	_clear_tips()
	_type(HELLO)
	_go.text = "Look over my city"
	_go.disabled = false
	_fit_bubble()


func _open_bubble() -> void:
	_open = true
	_bubble.visible = true
	_tail.visible = true
	_fit_bubble()
	if _tw:
		_tw.kill()
	_bubble.scale = Vector2(0.86, 0.86)
	_bubble.modulate.a = 0.0
	_tail.modulate.a = 0.0
	_tw = create_tween().set_parallel(true)
	_tw.tween_property(_bubble, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tw.tween_property(_bubble, "modulate:a", 1.0, 0.18)
	_tw.tween_property(_tail, "modulate:a", 1.0, 0.18)


## Closes the bubble; `forget` also takes the marks off the map.
func _close(forget: bool) -> void:
	if forget:
		marks.clear()
		_report = {}
	if not _open:
		return
	_open = false
	if _tw:
		_tw.kill()
	_tw = create_tween().set_parallel(true)
	_tw.tween_property(_bubble, "scale", Vector2(0.9, 0.9), 0.14)
	_tw.tween_property(_bubble, "modulate:a", 0.0, 0.14)
	_tw.tween_property(_tail, "modulate:a", 0.0, 0.14)
	_tw.chain().tween_callback(func():
		if not _open:
			_bubble.visible = false
			_tail.visible = false)


## Says `text`, a few letters at a time.
func _type(text: String) -> void:
	_say.text = text
	_say.visible_ratio = 0.0
	var tw := create_tween()
	tw.tween_property(_say, "visible_ratio", 1.0, clampf(text.length() * 0.012, 0.25, 1.2))


func _analyse() -> void:
	if _think >= 0.0:
		return
	Sfx.play("click", 1.1, -4.0)
	_think = 0.0
	_face.mood = "think"
	_go.disabled = true
	_go.text = "Looking round…"
	_score_row.visible = false
	_clear_tips()
	marks.clear()
	_type(["Hmm, let me have a look round…", "One moment, counting rooftops…", "Checking every street…"][randi() % 3])
	_fit_bubble()


func _process(delta: float) -> void:
	# the map marks belong to Pip: hidden with the interface in photo mode
	marks.visible = is_visible_in_tree()
	_settle -= delta
	if _settle <= 0.0:
		_settle = 1.0
		_place()
	if _think >= 0.0:
		_think += delta
		if _think > 1.1:
			_think = -1.0
			_report = Advisor.analyse(island)
			_seen = _top_key(_report)
			_face.badge = false
			_fresh = {}
			_show_report(_report)
			Sfx.play("pop", 0.9, -3.0)
		return
	if _open or not is_visible_in_tree():
		return
	_look -= delta
	if _look <= 0.0:
		_look = LOOK_EVERY
		if island.town.is_busy() or island.brush != "":
			return
		var r := Advisor.analyse(island)
		var key := _top_key(r)
		if key != "" and key != _seen and float(r.tips[0].score) >= 0.5:
			_seen = key
			_fresh = r
			_face.badge = true
			_face.hop()
			Sfx.play("pop", 1.5, -10.0)


static func _top_key(r: Dictionary) -> String:
	var tips: Array = r.get("tips", [])
	return str(tips[0].key) if not tips.is_empty() else ""


func _show_report(r: Dictionary) -> void:
	var score := int(r.get("score", 0))
	var meters: Array = r.get("meters", [])
	_score_row.visible = not meters.is_empty()
	_score_label.text = str(score)
	var col := Color("3fae8c") if score >= 80 else (Color("e8a21a") if score >= 55 else Color("e0584a"))
	_score_badge.add_theme_stylebox_override("panel", _box(col, 29, 0))
	_headline.text = str(r.get("headline", ""))
	for c in _meters.get_children():
		c.queue_free()
	for m in meters:
		var l := _label(m[0], 11, true, SOFT)
		_meters.add_child(l)
	for m in meters:
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.max_value = 1.0
		bar.step = 0.0
		bar.value = 0.0
		bar.custom_minimum_size = Vector2(62, 7)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.add_theme_stylebox_override("background", _box(Color(1, 1, 1, 0.12), 4, 0, false))
		bar.add_theme_stylebox_override("fill", _box(m[2], 4, 0, false))
		_meters.add_child(bar)
		create_tween().tween_property(bar, "value", float(m[1]), 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).set_delay(0.15)
	_type(str(r.get("line", "")))
	_face.mood = "happy" if score >= 80 or meters.is_empty() else ("calm" if score >= 55 else "worry")
	_clear_tips()
	var tips: Array = r.get("tips", [])
	for i in tips.size():
		var row := _tip_row(i, tips[i])
		_tips_box.add_child(row)
		row.modulate.a = 0.0
		row.position.x = 20
		create_tween().tween_property(row, "modulate:a", 1.0, 0.25).set_delay(0.25 + i * 0.12)
	marks.show_tips(tips)
	_go.disabled = false
	_go.text = "Look again"
	_fit_bubble()


func _clear_tips() -> void:
	for c in _tips_box.get_children():
		_tips_box.remove_child(c)
		c.queue_free()


func _tip_row(i: int, t: Dictionary) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _box(Color(1, 1, 1, 0.08), 16, 10, false))
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 9)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)
	var badge := PanelContainer.new()
	badge.add_theme_stylebox_override("panel", _box(t.colour, 14, 0, false))
	badge.custom_minimum_size = Vector2(28, 28)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(badge)
	var n := _label(str(i + 1), 15, true, Color.WHITE)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_child(n)
	var ic := UiIcon.new(str(t.icon), INK, ACCENT)
	ic.custom_minimum_size = Vector2(30, 30)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(tv)
	tv.add_child(_label(str(t.title), 15, true))
	var body := _label(str(t.text), 12, false, SOFT)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(maxf(minf(WIDTH, size.x - 12.0) - 200.0, 120.0), 0)
	tv.add_child(body)
	var act: Dictionary = t.action
	var b := Button.new()
	b.text = {"grow": "Paint", "green": "Plant", "street": "Draw"}.get(act.brush, "Go")
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(70, 40)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_override("font", _bold)
	b.add_theme_font_size_override("font_size", 15)
	var bc: Color = t.colour
	b.add_theme_stylebox_override("normal", _box(bc.darkened(0.08), 20, 10, false))
	b.add_theme_stylebox_override("hover", _box(bc, 20, 10, false))
	b.add_theme_stylebox_override("pressed", _box(bc.darkened(0.2), 20, 10, false))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for c in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(c, Color.WHITE)
	b.pressed.connect(func(): _act(i))
	h.add_child(b)
	p.gui_input.connect(func(e: InputEvent):
		if (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) or (e is InputEventScreenTouch and e.pressed):
			accept_event()
			_show_tip(i))
	return p


func _tips() -> Array:
	return _report.get("tips", [])


## Flies the camera over tip i and lights its mark.
func _show_tip(i: int) -> void:
	var tips := _tips()
	if i < 0 or i >= tips.size():
		return
	Sfx.play("click", 1.2, -5.0)
	var at: Vector2 = tips[i].pos
	var rig := island.rig
	rig.focus(Vector3(at.x, 0.0, at.y))
	var want := clampf(tips[i].radius * 5.5, 34.0, 70.0)
	var now: float = rig.get("_t_dist") if rig.get("_t_dist") != null else rig.dist
	if now > want * 1.4 or now < want * 0.6:
		rig.zoom(want / maxf(now, 1.0))
	marks.light(i)
	_face.look_at_world()


## Picks up the brush tip i asks for, set to its district and level.
func _act(i: int) -> void:
	var tips := _tips()
	if i < 0 or i >= tips.size():
		return
	var act: Dictionary = tips[i].action
	match str(act.brush):
		"grow":
			island.grow_use = int(act.use)
			island.grow_level = int(act.level)
			if island.brush != "grow":
				island.set_brush("grow")
			else:
				island.brush_changed.emit()
		"green":
			if island.brush != "green":
				island.set_brush("green")
		"street":
			island.street_kind = "main"
			if island.brush != "street":
				island.set_brush("street")
			else:
				island.brush_changed.emit()
	_show_tip(i)
	_face.cheer()
	_close(false)
	var how := "Paint inside the glowing ring"
	if act.brush == "street":
		how = "Draw a street into the glowing ring"
	island.note.emit(how, "info")


# ------------------------------------------------------------------ style

func _label(text: String, px := 16, bold := false, col := INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _bold if bold else _reg)
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func _box(bg: Color, radius := 22, pad := 14, shadow := false) -> StyleBoxFlat:
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


## The same frosted glass as the rest of the interface.
static func _glass_box(tint: Color, radius := 24, pad := 14) -> StyleBoxFlat:
	var sb := _box(tint, radius, pad)
	sb.border_color = Color(1, 1, 1, 0.16)
	sb.border_width_top = 2
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_blend = true
	sb.shadow_color = Color(0.05, 0.1, 0.2, 0.14)
	sb.shadow_size = 14
	sb.shadow_offset = Vector2(0, 6)
	return sb


## The little point under the speech bubble, aimed at Pip.
class BubbleTail:
	extends Control

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(size.x, 0), Vector2(size.x * 0.5, size.y)]), Color(0.1, 0.12, 0.16, 0.94))


## Pip: a round glass robot with a little screen for a face. Pip bobs,
## blinks, glances about, looks puzzled while thinking, beams at a thriving
## city and frets at a struggling one.
class PipFace:
	extends Control

	var mood := "calm"
	var badge := false:
		set(v):
			badge = v
			queue_redraw()
	var _t := 0.0
	var _blink := 2.0
	var _blink_t := 1.0
	var _look := Vector2.ZERO
	var _look_to := Vector2.ZERO
	var _look_wait := 1.5
	var _hop := 0.0
	var _cheer := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	## A little jump.
	func hop() -> void:
		_hop = 1.0

	## A tap on the nose.
	func boop() -> void:
		var tw := create_tween()
		tw.tween_property(self, "scale", Vector2(1.12, 0.88), 0.07)
		tw.tween_property(self, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

	## Happy for a moment, with a hop.
	func cheer() -> void:
		_cheer = 2.2
		hop()

	func look_at_world() -> void:
		_look_to = Vector2(-1.0, -0.6)
		_look_wait = 1.6

	func _process(delta: float) -> void:
		_t += delta
		_blink -= delta
		if _blink <= 0.0:
			_blink = randf_range(2.2, 5.0)
			_blink_t = 0.0
		_blink_t = minf(_blink_t + delta * 7.0, 1.0)
		_look_wait -= delta
		if _look_wait <= 0.0:
			_look_wait = randf_range(1.2, 3.4)
			var mouse := get_local_mouse_position()
			if not OS.has_feature("mobile") and mouse.distance_to(size * 0.5) < 380.0 and randf() < 0.6:
				_look_to = ((mouse - size * 0.5) / 120.0).limit_length(1.0)
			else:
				_look_to = Vector2(randf_range(-1.0, 1.0), randf_range(-0.6, 0.6)) if randf() < 0.7 else Vector2.ZERO
		_look = _look.lerp(_look_to, 1.0 - exp(-delta * 9.0))
		_hop = maxf(_hop - delta * 2.2, 0.0)
		_cheer = maxf(_cheer - delta, 0.0)
		queue_redraw()

	func _draw() -> void:
		var s := size.x / 84.0
		var bob := sin(_t * 2.1) * 2.0 * s - sin((1.0 - _hop) * PI) * 12.0 * s * float(_hop > 0.0)
		var c := Vector2(size.x * 0.5, size.y * 0.56 + bob)
		var happy := mood == "happy" or _cheer > 0.0
		var think := mood == "think"
		# a soft shadow on the "ground", smaller while Pip is up in the air
		var sh := 1.0 - clampf(-bob / (14.0 * s), 0.0, 0.5)
		_ellipse(Vector2(size.x * 0.5, size.y - 4.0 * s), Vector2(24.0, 4.5) * s * sh, Color(0.05, 0.1, 0.2, 0.22))
		# antenna, its tip glowing (coral when Pip has something to say)
		var tip := c + Vector2(sin(_t * 1.7) * 2.5 * s, -36.0 * s)
		draw_line(c + Vector2(0, -24.0 * s), tip, Color(0.62, 0.68, 0.76), 2.5 * s, true)
		var glow := ACCENT if badge or think else Color("6fe3d0")
		var pulse := 0.5 + 0.5 * sin(_t * (6.0 if think or badge else 2.5))
		_circle(tip, (6.5 + pulse * 3.0) * s, Color(glow, 0.22 + pulse * 0.18))
		_circle(tip, 4.2 * s, glow)
		_circle(tip + Vector2(-1.3, -1.3) * s, 1.4 * s, Color(1, 1, 1, 0.8))
		# ears
		for sx in [-1.0, 1.0]:
			_rr(Rect2(c + Vector2(sx * 31.0 * s - 4.5 * s, -9.0 * s), Vector2(9.0, 18.0) * s), 4.0 * s, ACCENT.darkened(0.05))
		# the head: frosted white with a bright rim
		var head := Rect2(c - Vector2(30.0, 26.0) * s, Vector2(60.0, 50.0) * s)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.97, 0.98, 1.0, 0.97)
		sb.set_corner_radius_all(int(22 * s))
		sb.corner_detail = 6
		sb.border_color = Color(1, 1, 1)
		sb.border_width_top = int(maxf(2.0 * s, 1.0))
		sb.shadow_color = Color(0.05, 0.1, 0.2, 0.2)
		sb.shadow_size = int(8 * s)
		sb.shadow_offset = Vector2(0, 3) * s
		sb.anti_aliasing = true
		draw_style_box(sb, head)
		# a shine across the top of the head
		_rr(Rect2(head.position + Vector2(12.0, 4.0) * s, Vector2(18.0, 4.0) * s), 2.0 * s, Color(1, 1, 1, 0.9))
		# the screen face
		var scr := Rect2(c - Vector2(22.0, 15.0) * s, Vector2(44.0, 32.0) * s)
		_rr(scr, 12.0 * s, Color("243246"))
		var eye_col := Color("8ff5e3") if mood != "worry" or _cheer > 0.0 else Color("ffd27a")
		var look := _look * Vector2(4.0, 2.5) * s
		var open := 1.0 - sin(_blink_t * PI) if _blink_t < 1.0 else 1.0
		for sx in [-1.0, 1.0]:
			var e := c + Vector2(sx * 9.0 * s, -3.0 * s) + look
			if think:
				# eyes scan side to side, like reading a map
				var dx := sin(_t * 5.0) * 3.0 * s
				_rr(Rect2(e + Vector2(dx - 4.0 * s, -1.5 * s), Vector2(8.0, 3.0) * s), 1.5 * s, eye_col)
			elif happy:
				draw_arc(e + Vector2(0, 2.0 * s), 4.0 * s, PI * 1.1, PI * 1.9, 8, eye_col, 2.6 * s, true)
			else:
				var hgt := maxf(11.0 * open, 1.6) * s
				_rr(Rect2(e - Vector2(3.5 * s, hgt * 0.5), Vector2(7.0 * s, hgt)), 3.0 * s, eye_col)
				if mood == "worry":
					draw_line(e + Vector2(-4.5 * s * sx, -8.5 * s), e + Vector2(3.5 * s * sx, -6.5 * s), eye_col, 1.8 * s, true)
		# mouth
		var m := c + Vector2(0, 8.0 * s) + look * 0.4
		if think:
			_circle(m, 2.2 * s, eye_col)
		elif happy:
			draw_arc(m + Vector2(0, -2.5 * s), 5.0 * s, PI * 0.15, PI * 0.85, 10, eye_col, 2.2 * s, true)
		elif mood == "worry":
			draw_arc(m + Vector2(0, 3.0 * s), 4.0 * s, PI * 1.2, PI * 1.8, 8, eye_col, 2.0 * s, true)
		else:
			draw_arc(m + Vector2(0, -1.5 * s), 4.0 * s, PI * 0.2, PI * 0.8, 8, eye_col, 2.0 * s, true)
		# rosy cheeks
		for sx in [-1.0, 1.0]:
			_circle(c + Vector2(sx * 16.0 * s, 7.0 * s), 3.2 * s, Color(1.0, 0.5, 0.55, 0.35 + 0.25 * float(happy)))
		if badge:
			var bp := c + Vector2(25.0, -24.0) * s
			var pop := 1.0 + 0.12 * sin(_t * 7.0)
			_circle(bp, 10.0 * s * pop, Color.WHITE)
			_circle(bp, 8.5 * s * pop, ACCENT)
			draw_rect(Rect2(bp + Vector2(-1.2, -5.0) * s, Vector2(2.4, 6.0) * s), Color.WHITE)
			_circle(bp + Vector2(0, 3.6) * s, 1.4 * s, Color.WHITE)

	func _circle(p: Vector2, r: float, col: Color) -> void:
		var n := clampi(int(r * 1.4), 10, 36)
		var pts := PackedVector2Array()
		pts.resize(n)
		for i in n:
			var a := TAU * i / n
			pts[i] = p + Vector2(cos(a), sin(a)) * r
		draw_colored_polygon(pts, col)

	func _ellipse(p: Vector2, r: Vector2, col: Color) -> void:
		var pts := PackedVector2Array()
		pts.resize(24)
		for i in 24:
			var a := TAU * i / 24
			pts[i] = p + Vector2(cos(a) * r.x, sin(a) * r.y)
		draw_colored_polygon(pts, col)

	func _rr(r: Rect2, rad: float, col: Color) -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = col
		sb.set_corner_radius_all(int(rad))
		sb.corner_detail = 4
		sb.anti_aliasing = true
		draw_style_box(sb, r)
