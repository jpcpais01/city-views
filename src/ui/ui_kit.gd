class_name UiKit
extends RefCounted
## The interface's design system: one palette, one typeface, smoked glass
## panels, buttons, focus rings and the motion every screen shares, so the
## menu, the HUD and every card read as one piece.
##
## Everything is static and cached: a style is built once and shared, so the
## whole interface costs a handful of objects and draws no extra geometry.

# ---- palette: smoked glass with white type and one warm accent
const TEXT := Color("f5f7fb")
const DIM := Color(0.92, 0.94, 0.98, 0.66)
const FAINT := Color(0.92, 0.94, 0.98, 0.4)
const PANEL := Color(0.075, 0.09, 0.125)
const PANEL_SOLID := Color(0.085, 0.1, 0.135, 0.97)
const RAISED := Color(1, 1, 1, 0.06)
const RAISED_HI := Color(1, 1, 1, 0.13)
const LINE := Color(1, 1, 1, 0.1)
const RIM := Color(1, 1, 1, 0.16)
const ACCENT := Color("ff7a6b")
const ACCENT_HI := Color("ff9184")
const ACCENT_LO := Color("e8604f")
const GOOD := Color("4fd6a6")
const WARN := Color("ffc35c")
const BAD := Color("ff6159")
const INFO := Color("72bbff")
const GOLD := Color("ffcf6b")
## ink for type on a white (selected) surface
const ON_LIGHT := Color("161b24")

const FONT_PATH := "res://assets/fonts/Manrope.ttf"

static var _fonts := {}
static var _mats := {}
static var _theme: Theme
static var _ring: StyleBoxFlat
static var _no_ring := StyleBoxEmpty.new()
## true while the player steers with keys or a pad: only then do focus rings show
static var nav := false
static var _switch := {}


# ------------------------------------------------------------------ type

## Manrope at a weight from 200 (light) to 800 (extra bold), cached per weight.
static func font(weight := 600) -> FontVariation:
	if _fonts.has(weight):
		return _fonts[weight]
	var f := FontVariation.new()
	f.base_font = load(FONT_PATH)
	f.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	_fonts[weight] = f
	return f


## Wide-tracked caps for small headings (the AAA "eyebrow" over a title).
static func caps_font(weight := 800) -> FontVariation:
	var key := "caps%d" % weight
	if _fonts.has(key):
		return _fonts[key]
	var f := font(weight).duplicate() as FontVariation
	f.spacing_glyph = 2
	_fonts[key] = f
	return f


static func label(text: String, size := 18, weight := 600, col := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(weight))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func eyebrow(text: String, col := FAINT, size := 12) -> Label:
	var l := label(text.to_upper(), size, 800, col)
	l.add_theme_font_override("font", caps_font())
	return l


static func para(text: String, size := 15, col := DIM, min_w := 200) -> Label:
	var l := label(text, size, 500, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = min_w
	return l


static func icon(kind: String, px := 28, col := TEXT) -> UiIcon:
	var i := UiIcon.new(kind, col, ACCENT)
	i.custom_minimum_size = Vector2(px, px)
	return i


# ------------------------------------------------------------------ surfaces

## A rounded box. Corner detail 5 is round to the eye at these radii and keeps
## each box to a few dozen triangles.
static func box(bg: Color, radius := 16, pad := 14.0, border := Color(0, 0, 0, 0), bw := 0, shadow := 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.corner_detail = 5
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = pad * 0.75
	sb.content_margin_bottom = pad * 0.75
	sb.anti_aliasing = true
	if bw > 0:
		sb.border_color = border
		sb.set_border_width_all(bw)
	if shadow > 0:
		sb.shadow_color = Color(0, 0.02, 0.06, 0.28)
		sb.shadow_size = shadow
		sb.shadow_offset = Vector2(0, shadow * 0.4)
	return sb


## The frosted material: blurs the city behind a panel and mixes it with the
## panel's own colour by `tint` (0 = clear glass, 1 = solid).
static func glass_mat(tint := 0.62, blur := 2.6) -> ShaderMaterial:
	var key := "%.2f/%.2f" % [tint, blur]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = preload("res://src/ui/glass.gdshader")
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("blur", blur)
	m.set_shader_parameter("vibrance", 1.15)
	m.set_shader_parameter("lift", 0.0)
	_mats[key] = m
	return m


## Smoked glass panel: dark frosted fill, a hairline rim brighter along the top
## edge where the light catches it, and a soft shadow under it.
static func glass_box(radius := 22, pad := 16.0, col := PANEL, shadow := 18) -> StyleBoxFlat:
	var sb := box(col, radius, pad)
	sb.border_color = RIM
	sb.border_width_top = 1
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_blend = false
	if shadow > 0:
		sb.shadow_color = Color(0, 0.02, 0.06, 0.3)
		sb.shadow_size = shadow
		sb.shadow_offset = Vector2(0, 6)
	return sb


## Turns a PanelContainer (or any Control) into a smoked glass card.
static func glassify(c: Control, radius := 22, pad := 16.0, tint := 0.62, shadow := 18) -> void:
	c.material = glass_mat(tint)
	if c is PanelContainer:
		c.add_theme_stylebox_override("panel", glass_box(radius, pad, PANEL, shadow))


static func panel(radius := 22, pad := 16.0, tint := 0.62) -> PanelContainer:
	var p := PanelContainer.new()
	glassify(p, radius, pad, tint)
	return p


## A flat inset surface for rows and tiles inside a glass panel (no blur, so
## it costs nothing extra to draw).
static func inset(radius := 14, pad := 14.0, col := RAISED) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(col, radius, pad))
	return p


static func hline() -> ColorRect:
	var r := ColorRect.new()
	r.color = LINE
	r.custom_minimum_size = Vector2(0, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


# ------------------------------------------------------------------ focus

## The keyboard / pad focus ring: a crisp white outline just outside the control.
static func ring(radius := 16) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	sb.set_corner_radius_all(radius + 3)
	sb.corner_detail = 5
	sb.border_color = Color(1, 1, 1, 0.95)
	sb.set_border_width_all(2)
	sb.set_expand_margin_all(3)
	sb.anti_aliasing = true
	return sb


## Rings show only while steering with keys or a pad; a mouse or a finger hides them.
static func set_nav(on: bool) -> void:
	if on == nav:
		return
	nav = on
	var t := theme()
	for type in ["Button", "CheckButton", "LineEdit", "HSlider", "OptionButton"]:
		t.set_stylebox("focus", type, _ring if on else _no_ring)


## Feeds every input event here to keep `nav` in step with what the player uses.
static func track_input(e: InputEvent) -> void:
	if e is InputEventMouseButton or e is InputEventScreenTouch:
		set_nav(false)
	elif e is InputEventMouseMotion:
		if e.relative.length() > 6.0:
			set_nav(false)
	elif e is InputEventJoypadButton and e.pressed:
		set_nav(true)
	elif e is InputEventJoypadMotion and absf(e.axis_value) > 0.5:
		set_nav(true)
	elif e is InputEventKey and e.pressed and e.keycode in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_TAB]:
		set_nav(true)


# ------------------------------------------------------------------ theme

## The one Theme every screen hangs off.
static func theme() -> Theme:
	if _theme:
		return _theme
	_ring = ring(14)
	var t := Theme.new()
	t.default_font = font(600)
	t.default_font_size = 17
	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("panel", "PanelContainer", glass_box())
	# buttons: quiet raised glass that lifts on hover; the accent is kept for primaries
	t.set_stylebox("normal", "Button", box(RAISED, 14, 18))
	t.set_stylebox("hover", "Button", box(RAISED_HI, 14, 18))
	t.set_stylebox("pressed", "Button", box(Color(1, 1, 1, 0.92), 14, 18))
	t.set_stylebox("hover_pressed", "Button", box(Color.WHITE, 14, 18))
	t.set_stylebox("disabled", "Button", box(Color(1, 1, 1, 0.03), 14, 18))
	t.set_stylebox("focus", "Button", _no_ring)
	t.set_font("font", "Button", font(700))
	t.set_font_size("font_size", "Button", 17)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", TEXT)
	t.set_color("font_focus_color", "Button", TEXT)
	t.set_color("font_pressed_color", "Button", ON_LIGHT)
	t.set_color("font_hover_pressed_color", "Button", ON_LIGHT)
	t.set_color("font_disabled_color", "Button", FAINT)
	# text fields: a dark well with an accent underline when typing
	var le := box(Color(0, 0, 0, 0.28), 12, 14)
	le.border_color = LINE
	le.set_border_width_all(1)
	t.set_stylebox("normal", "LineEdit", le)
	var lef := le.duplicate() as StyleBoxFlat
	lef.border_color = ACCENT
	lef.border_width_bottom = 2
	lef.bg_color = Color(0, 0, 0, 0.36)
	t.set_stylebox("focus", "LineEdit", lef)
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("caret_color", "LineEdit", ACCENT)
	t.set_color("selection_color", "LineEdit", Color(ACCENT, 0.4))
	t.set_color("font_placeholder_color", "LineEdit", FAINT)
	t.set_font("font", "LineEdit", font(600))
	t.set_font_size("font_size", "LineEdit", 17)
	# progress: a slim track
	t.set_stylebox("background", "ProgressBar", box(Color(1, 1, 1, 0.12), 4, 0))
	t.set_stylebox("fill", "ProgressBar", box(GOOD, 4, 0))
	# sliders: a slim track, accent fill and a white knob
	var tr := box(Color(1, 1, 1, 0.14), 4, 0)
	tr.content_margin_top = 3
	tr.content_margin_bottom = 3
	var fl := box(ACCENT, 4, 0)
	fl.content_margin_top = 3
	fl.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", tr)
	t.set_stylebox("grabber_area", "HSlider", fl)
	t.set_stylebox("grabber_area_highlight", "HSlider", fl)
	t.set_stylebox("focus", "HSlider", _no_ring)
	var knob := _knob()
	t.set_icon("grabber", "HSlider", knob)
	t.set_icon("grabber_highlight", "HSlider", knob)
	# thin, rounded scroll bars that stay out of the way
	var sg := box(Color(1, 1, 1, 0.22), 3, 0)
	sg.content_margin_left = 3
	sg.content_margin_right = 3
	var sgh := box(Color(1, 1, 1, 0.4), 3, 0)
	sgh.content_margin_left = 3
	sgh.content_margin_right = 3
	var none := StyleBoxEmpty.new()
	none.content_margin_left = 3
	none.content_margin_right = 3
	t.set_stylebox("scroll", "VScrollBar", none)
	t.set_stylebox("grabber", "VScrollBar", sg)
	t.set_stylebox("grabber_highlight", "VScrollBar", sgh)
	t.set_stylebox("grabber_pressed", "VScrollBar", sgh)
	# tooltips in the same glass
	t.set_stylebox("panel", "TooltipPanel", box(PANEL_SOLID, 10, 10, RIM, 1))
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_font("font", "TooltipLabel", font(600))
	t.set_font_size("font_size", "TooltipLabel", 14)
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_font("normal_font", "RichTextLabel", font(500))
	t.set_font("bold_font", "RichTextLabel", font(800))
	_theme = t
	return t


## The slider's knob, drawn once: a white disc with a soft edge.
static func _knob() -> Texture2D:
	var n := 22
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	var c := Vector2(n, n) * 0.5
	for y in n:
		for x in n:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c)
			var a := clampf(9.5 - d, 0.0, 1.0)
			var halo := clampf((11.0 - d) * 0.25, 0.0, 0.25)
			img.set_pixel(x, y, Color(1, 1, 1, maxf(a, halo)))
	return ImageTexture.create_from_image(img)


## A sleek on/off switch drawn once into a texture: accent pill, knob right when on.
static func switch_icon(on: bool) -> Texture2D:
	if _switch.has(on):
		return _switch[on]
	var w := 52
	var h := 30
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	var track := ACCENT if on else Color(1, 1, 1, 0.2)
	var r := h * 0.5
	var knob := Vector2(w - r, r) if on else Vector2(r, r)
	for y in h:
		for x in w:
			var p := Vector2(x + 0.5, y + 0.5)
			var cx := clampf(p.x, r, w - r)
			var a := clampf(0.5 - (p.distance_to(Vector2(cx, r)) - r), 0.0, 1.0)
			var col := Color(track.r, track.g, track.b, track.a * a)
			var ka := clampf(0.5 - (p.distance_to(knob) - (r - 3.5)), 0.0, 1.0)
			col = col.blend(Color(1, 1, 1, ka))
			img.set_pixel(x, y, col)
	_switch[on] = ImageTexture.create_from_image(img)
	return _switch[on]


# ------------------------------------------------------------------ buttons

## kind: "primary" (accent), "secondary" (raised glass), "ghost" (text only) or "danger".
static func button(text: String, kind := "secondary", h := 52) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, h)
	b.focus_mode = Control.FOCUS_ALL
	match kind:
		"primary":
			_fill(b, ACCENT, ACCENT_HI, ACCENT_LO, Color.WHITE)
		"danger":
			_fill(b, BAD, BAD.lightened(0.12), BAD.darkened(0.12), Color.WHITE)
		"ghost":
			b.add_theme_stylebox_override("normal", box(Color(1, 1, 1, 0), 14, 14))
			b.add_theme_stylebox_override("hover", box(RAISED, 14, 14))
			b.add_theme_stylebox_override("pressed", box(RAISED_HI, 14, 14))
			b.add_theme_color_override("font_pressed_color", TEXT)
	press_fx(b)
	return b


static func _fill(b: Button, col: Color, hi: Color, lo: Color, ink: Color) -> void:
	b.add_theme_stylebox_override("normal", box(col, 14, 18))
	b.add_theme_stylebox_override("hover", box(hi, 14, 18))
	b.add_theme_stylebox_override("pressed", box(lo, 14, 18))
	b.add_theme_stylebox_override("hover_pressed", box(lo, 14, 18))
	for fc in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(fc, ink)


## A round glass key that holds just an icon (close, back, menu...).
static func icon_button(kind: String, px := 52, tint := 0.62) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(px, px)
	b.focus_mode = Control.FOCUS_ALL
	b.material = glass_mat(tint)
	var r := px / 2
	b.add_theme_stylebox_override("normal", glass_box(r, 0, PANEL, 10))
	b.add_theme_stylebox_override("hover", glass_box(r, 0, PANEL.lightened(0.14), 10))
	b.add_theme_stylebox_override("pressed", glass_box(r, 0, PANEL.lightened(0.28), 0))
	b.add_theme_stylebox_override("disabled", glass_box(r, 0, PANEL, 0))
	var ic := icon(kind, int(px * 0.46))
	ic.set_anchors_preset(Control.PRESET_FULL_RECT)
	b.add_child(ic)
	press_fx(b)
	return b


## The springy squeeze on press that makes a button feel physical.
static func press_fx(b: Control) -> void:
	b.resized.connect(func(): b.pivot_offset = b.size * 0.5)
	if b is BaseButton:
		var bb := b as BaseButton
		bb.button_down.connect(func(): squish(b, 0.95))
		bb.button_up.connect(func(): squish(b, 1.0))


static func squish(c: Control, to: float) -> void:
	if not c.is_inside_tree():
		return
	c.pivot_offset = c.size * 0.5
	var tw := c.create_tween()
	tw.tween_property(c, "scale", Vector2(to, to), 0.09 if to < 1.0 else 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# ------------------------------------------------------------------ motion

## Fades a control in while it glides in from `from` pixels away.
static func enter(c: Control, from := Vector2(0, 14), t := 0.28, delay := 0.0) -> Tween:
	var base := c.position
	c.modulate.a = 0.0
	c.position = base + from
	var tw := c.create_tween().set_parallel(true)
	tw.tween_property(c, "modulate:a", 1.0, t * 0.8).set_delay(delay)
	tw.tween_property(c, "position", base, t).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT).set_delay(delay)
	return tw


## Pops a card in from slightly smaller, springing to size.
static func pop(c: Control, t := 0.32, from := 0.92) -> Tween:
	c.pivot_offset = c.size * 0.5
	c.scale = Vector2(from, from)
	c.modulate.a = 0.0
	var tw := c.create_tween().set_parallel(true)
	tw.tween_property(c, "scale", Vector2.ONE, t).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "modulate:a", 1.0, t * 0.6)
	return tw


# ------------------------------------------------------------------ prompts

## A key cap with what it does beside it, for the hint bar along the bottom
## of a menu ("Esc  Back").
static func key_hint(key: String, what: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cap := PanelContainer.new()
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := box(Color(1, 1, 1, 0.9), 6, 7)
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	cap.add_theme_stylebox_override("panel", sb)
	var k := label(key, 12, 800, ON_LIGHT)
	k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	k.custom_minimum_size.x = 14
	cap.add_child(k)
	h.add_child(cap)
	h.add_child(label(what, 14, 600, DIM))
	return h


## Pad-or-keyboard names for the hint bar.
static func key_name(action: String, pad: bool) -> String:
	match action:
		"back": return "B" if pad else "Esc"
		"select": return "A" if pad else "Enter"
		"tabs": return "LB RB" if pad else "Q  E"
	return action


## Short counts for tiles and pills: 1234 -> 1,234, 12500 -> 12.5k.
static func short(n: float) -> String:
	if n >= 1e6:
		return "%.2fM" % (n / 1e6)
	if n >= 1e4:
		return "%.1fk" % (n / 1e3)
	var s := str(int(n))
	if s.length() > 3:
		s = s.substr(0, s.length() - 3) + "," + s.substr(s.length() - 3)
	return s
