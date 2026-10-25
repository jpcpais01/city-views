class_name CityCharts
extends VBoxContainer
## Graphs of how the city has grown, at the foot of the stats panel (tap the
## population): People (residents and jobs) or Money (coins in hand and
## income a minute), drawn from CityHistory as soft lines over a shaded area,
## with the latest value at the end of each line.

const INK := Color("f5f7fb")
const SOFT := Color(0.92, 0.94, 0.98, 0.66)
const VIEWS := [
	["People", [[0, "Residents", Color("3fae8c")], [1, "Jobs", Color("22a5c7")]]],
	["Money", [[2, "Coins", Color("e8a21a")], [3, "Income /min", Color("ff7a6b")]]],
]

var history: CityHistory
var _view := 0
var _chart: LineChart
var _legend: HBoxContainer
var _tabs: Array[Button] = []
var _span: Label
var _bold: Font
var _reg: Font


## Records the city's history and shows it in the hud's stats panel.
static func attach(h: Hud, world: IslandWorld) -> CityCharts:
	var hist := CityHistory.new(world)
	world.add_child(hist)
	var c := CityCharts.new()
	c.history = hist
	c._bold = h.font_bold
	c._reg = h.font_reg
	var panel: Variant = h.get("_stats_panel")
	if panel is PanelContainer and (panel as PanelContainer).get_child_count() > 0 and (panel as PanelContainer).get_child(0) is VBoxContainer:
		(panel as PanelContainer).get_child(0).add_child(c)
	return c


func _ready() -> void:
	add_theme_constant_override("separation", 4)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	add_child(head)
	var title := _label("Trends", 15, true, INK)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	for i in VIEWS.size():
		var b := Button.new()
		b.text = VIEWS[i][0]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(66, 28)
		if _bold:
			b.add_theme_font_override("font", _bold)
		b.add_theme_font_size_override("font_size", 13)
		b.add_theme_stylebox_override("normal", _box(Color(1, 1, 1, 0.06)))
		b.add_theme_stylebox_override("hover", _box(Color(1, 1, 1, 0.14)))
		b.add_theme_stylebox_override("pressed", _box(Color.WHITE))
		b.add_theme_stylebox_override("hover_pressed", _box(Color.WHITE))
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		b.add_theme_color_override("font_color", INK)
		b.add_theme_color_override("font_hover_color", INK)
		b.add_theme_color_override("font_pressed_color", Color("161b24"))
		b.add_theme_color_override("font_hover_pressed_color", Color("161b24"))
		b.pressed.connect(func(): _pick(i))
		head.add_child(b)
		_tabs.append(b)
	_chart = LineChart.new()
	_chart.custom_minimum_size = Vector2(290, 112)
	_chart.font = _reg
	add_child(_chart)
	var foot := HBoxContainer.new()
	add_child(foot)
	_legend = HBoxContainer.new()
	_legend.add_theme_constant_override("separation", 12)
	_legend.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(_legend)
	_span = _label("", 11, false, SOFT)
	_span.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(_span)
	history.sampled.connect(_refresh)
	visibility_changed.connect(func():
		if is_visible_in_tree():
			_chart.replay()
			_refresh())
	_pick(0)


func _pick(i: int) -> void:
	_view = i
	for k in _tabs.size():
		_tabs[k].set_pressed_no_signal(k == i)
	_chart.replay()
	_refresh()


func _refresh() -> void:
	if not is_visible_in_tree() and _chart.lines.size() > 0:
		return
	var lines: Array = []
	for s in VIEWS[_view][1]:
		lines.append({"values": history.series(s[0]), "colour": s[2]})
	_chart.lines = lines
	_chart.queue_redraw()
	for c in _legend.get_children():
		c.queue_free()
	for s in VIEWS[_view][1]:
		var vals := history.series(s[0])
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 4)
		var dot := ColorRect.new()
		dot.color = s[2]
		dot.custom_minimum_size = Vector2(10, 10)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(dot)
		h.add_child(_label("%s %s" % [s[1], LineChart.short(vals[vals.size() - 1] if vals.size() > 0 else 0.0)], 12, true, INK))
		_legend.add_child(h)
	_span.text = "last %s" % _duration(history.span()) if history.points.size() > 1 else "just started"


static func _duration(sec: float) -> String:
	if sec < 90.0:
		return "%d s" % int(sec)
	if sec < 5400.0:
		return "%d min" % int(round(sec / 60.0))
	return "%.1f h" % (sec / 3600.0)


func _label(text: String, px: int, bold: bool, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	var f: Font = _bold if bold else _reg
	if f:
		l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func _box(bg: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(14)
	sb.corner_detail = 5
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	sb.anti_aliasing = true
	return sb


## Lines over time on a soft grid: the first one shaded beneath, each
## ending in a dot; drawn in from the left when shown.
class LineChart:
	extends Control

	## [{values: PackedFloat32Array, colour: Color}]
	var lines: Array = []
	var font: Font
	var _grow := 1.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func replay() -> void:
		_grow = 0.0
		set_process(true)

	func _process(delta: float) -> void:
		_grow = minf(_grow + delta * 1.6, 1.0)
		queue_redraw()
		if _grow >= 1.0:
			set_process(false)

	static func short(v: float) -> String:
		if absf(v) >= 1000000.0:
			return "%.1fM" % (v / 1000000.0)
		if absf(v) >= 10000.0:
			return "%dk" % int(round(v / 1000.0))
		if absf(v) >= 1000.0:
			return "%.1fk" % (v / 1000.0)
		return str(int(round(v)))

	## A round number at or above v for the top of the scale.
	static func nice_top(v: float) -> float:
		if v <= 0.0:
			return 10.0
		var mag := pow(10.0, floor(log(v) / log(10.0)))
		for m in [1.0, 2.0, 2.5, 5.0, 10.0]:
			if m * mag >= v:
				return m * mag
		return 10.0 * mag

	func _draw() -> void:
		var r := Rect2(Vector2(30, 6), size - Vector2(34, 12))
		var top := 0.0
		var n := 0
		for l in lines:
			var vals: PackedFloat32Array = l.values
			n = maxi(n, vals.size())
			for v in vals:
				top = maxf(top, v)
		top = nice_top(top * 1.05)
		var grid := Color(1, 1, 1, 0.1)
		for k in 3:
			var y := r.position.y + r.size.y * k / 2.0
			draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), grid, 1.0)
			if font:
				draw_string(font, Vector2(0, y + 4), short(top * (1.0 - k / 2.0)), HORIZONTAL_ALIGNMENT_RIGHT, 26, 10, Color(1, 1, 1, 0.5))
		if n < 2:
			if font:
				draw_string(font, Vector2(r.position.x, r.get_center().y + 4), "The graph fills in as your city grows", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 12, Color(1, 1, 1, 0.5))
			return
		var upto := 1.0 + (n - 1) * _grow
		for li in lines.size():
			var vals: PackedFloat32Array = lines[li].values
			var col: Color = lines[li].colour
			var pts := PackedVector2Array()
			for i in vals.size():
				if i > upto:
					break
				pts.append(Vector2(r.position.x + r.size.x * i / (n - 1), r.end.y - r.size.y * clampf(vals[i] / top, 0.0, 1.0)))
			var f := upto - floorf(upto)
			var last := int(floorf(upto))
			if f > 0.0 and last + 1 < vals.size():
				var a := pts[pts.size() - 1]
				var b := Vector2(r.position.x + r.size.x * (last + 1) / (n - 1), r.end.y - r.size.y * clampf(vals[last + 1] / top, 0.0, 1.0))
				pts.append(a.lerp(b, f))
			if pts.size() < 2:
				continue
			if li == 0:
				# the area under the first line, fading to nothing at the bottom
				var poly := pts.duplicate()
				poly.append(Vector2(pts[pts.size() - 1].x, r.end.y))
				poly.append(Vector2(pts[0].x, r.end.y))
				var cols := PackedColorArray()
				for p in poly:
					cols.append(Color(col, 0.28 * (1.0 - (p.y - r.position.y) / r.size.y) + 0.02))
				draw_polygon(poly, cols)
			draw_polyline(pts, col, 2.5, true)
			var end := pts[pts.size() - 1]
			draw_circle(end, 4.5, Color.WHITE)
			draw_circle(end, 3.0, col)
