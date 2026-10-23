class_name UiIcon
extends Control
## Crisp vector icons drawn in code (sharp at any screen density).

var kind := ""
var color := Color(0.2, 0.24, 0.3)
var accent := Color("ff7a6b")


func _init(k := "", c := Color(0.2, 0.24, 0.3), a := Color("ff7a6b")) -> void:
	kind = k
	color = c
	accent = a
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_kind(k: String) -> void:
	kind = k
	queue_redraw()


func _rr(r: Rect2, rad: float, c: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(int(rad))
	sb.anti_aliasing = true
	draw_style_box(sb, r)


func _draw() -> void:
	var s: float = min(size.x, size.y)
	var o := (size - Vector2(s, s)) * 0.5
	var P := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * s
	var c := color
	var a := accent
	match kind:
		"road":
			_rr(Rect2(P.call(0.3, 0.08), Vector2(0.4, 0.84) * s), 0.08 * s, Color(0.36, 0.38, 0.43))
			for i in 3:
				draw_rect(Rect2(P.call(0.47, 0.16 + i * 0.27), Vector2(0.06, 0.16) * s), Color(1, 0.95, 0.8))
		"house":
			draw_colored_polygon(PackedVector2Array([P.call(0.12, 0.5), P.call(0.5, 0.14), P.call(0.88, 0.5)]), Color("e0684f"))
			_rr(Rect2(P.call(0.22, 0.48), Vector2(0.56, 0.4) * s), 0.06 * s, Color("fbefd9"))
			_rr(Rect2(P.call(0.44, 0.62), Vector2(0.14, 0.26) * s), 0.03 * s, Color("8b5a44"))
			_rr(Rect2(P.call(0.28, 0.56), Vector2(0.1, 0.1) * s), 0.02 * s, Color("6fa8d8"))
			_rr(Rect2(P.call(0.64, 0.56), Vector2(0.1, 0.1) * s), 0.02 * s, Color("6fa8d8"))
		"shop":
			_rr(Rect2(P.call(0.16, 0.36), Vector2(0.68, 0.52) * s), 0.06 * s, Color("fbefd9"))
			for i in 4:
				var col := Color("3fae8c") if i % 2 == 0 else Color.WHITE
				draw_colored_polygon(PackedVector2Array([P.call(0.12 + i * 0.19, 0.24), P.call(0.31 + i * 0.19, 0.24), P.call(0.31 + i * 0.19, 0.44), P.call(0.12 + i * 0.19, 0.44)]), col)
			_rr(Rect2(P.call(0.24, 0.54), Vector2(0.22, 0.2) * s), 0.03 * s, Color("8fc8ec"))
			_rr(Rect2(P.call(0.56, 0.54), Vector2(0.16, 0.34) * s), 0.03 * s, Color("8b5a44"))
		"office":
			_rr(Rect2(P.call(0.28, 0.1), Vector2(0.44, 0.8) * s), 0.06 * s, Color("c9d6e0"))
			for yy in 5:
				for xx in 2:
					_rr(Rect2(P.call(0.35 + xx * 0.17, 0.17 + yy * 0.14), Vector2(0.12, 0.08) * s), 0.02 * s, Color("5b8db8"))
		"park":
			draw_circle(P.call(0.5, 0.42), 0.3 * s, Color("6fb35a"))
			draw_circle(P.call(0.36, 0.5), 0.18 * s, Color("82c063"))
			draw_rect(Rect2(P.call(0.46, 0.6), Vector2(0.08, 0.28) * s), Color("8b5a44"))
			_rr(Rect2(P.call(0.1, 0.82), Vector2(0.8, 0.08) * s), 0.04 * s, Color("9fd37f"))
		"tree":
			draw_colored_polygon(PackedVector2Array([P.call(0.5, 0.08), P.call(0.78, 0.5), P.call(0.22, 0.5)]), Color("3f7f4f"))
			draw_colored_polygon(PackedVector2Array([P.call(0.5, 0.28), P.call(0.84, 0.76), P.call(0.16, 0.76)]), Color("4b8b55"))
			draw_rect(Rect2(P.call(0.45, 0.76), Vector2(0.1, 0.16) * s), Color("8b5a44"))
		"fountain":
			_rr(Rect2(P.call(0.12, 0.66), Vector2(0.76, 0.2) * s), 0.08 * s, Color("e8e2d6"))
			_rr(Rect2(P.call(0.18, 0.62), Vector2(0.64, 0.08) * s), 0.04 * s, Color("6fc3e8"))
			draw_rect(Rect2(P.call(0.46, 0.36), Vector2(0.08, 0.3) * s), Color("e8e2d6"))
			draw_circle(P.call(0.5, 0.26), 0.12 * s, Color("8fd6f5"))
			draw_circle(P.call(0.34, 0.36), 0.06 * s, Color("8fd6f5"))
			draw_circle(P.call(0.66, 0.36), 0.06 * s, Color("8fd6f5"))
		"windmill":
			draw_colored_polygon(PackedVector2Array([P.call(0.38, 0.9), P.call(0.62, 0.9), P.call(0.57, 0.42), P.call(0.43, 0.42)]), Color("efe7d8"))
			draw_colored_polygon(PackedVector2Array([P.call(0.4, 0.43), P.call(0.6, 0.43), P.call(0.5, 0.3)]), Color("8b5a44"))
			for k in 4:
				var ang := PI * 0.25 + k * PI * 0.5
				var d := Vector2(cos(ang), sin(ang))
				draw_line(P.call(0.5, 0.38), P.call(0.5, 0.38) + d * 0.36 * s, Color("8b5a44"), 0.07 * s, true)
			draw_circle(P.call(0.5, 0.38), 0.05 * s, Color("5b4a42"))
		"lighthouse":
			draw_colored_polygon(PackedVector2Array([P.call(0.36, 0.9), P.call(0.64, 0.9), P.call(0.58, 0.32), P.call(0.42, 0.32)]), Color.WHITE)
			draw_colored_polygon(PackedVector2Array([P.call(0.38, 0.72), P.call(0.62, 0.72), P.call(0.61, 0.6), P.call(0.39, 0.6)]), Color("d9534f"))
			draw_colored_polygon(PackedVector2Array([P.call(0.41, 0.48), P.call(0.59, 0.48), P.call(0.58, 0.38), P.call(0.42, 0.38)]), Color("d9534f"))
			_rr(Rect2(P.call(0.42, 0.2), Vector2(0.16, 0.12) * s), 0.02 * s, Color("ffd36e"))
			draw_colored_polygon(PackedVector2Array([P.call(0.38, 0.2), P.call(0.62, 0.2), P.call(0.5, 0.08)]), Color("d9534f"))
		"clocktower":
			_rr(Rect2(P.call(0.36, 0.3), Vector2(0.28, 0.6) * s), 0.04 * s, Color("c97b5a"))
			draw_colored_polygon(PackedVector2Array([P.call(0.32, 0.32), P.call(0.68, 0.32), P.call(0.5, 0.06)]), Color("4b5a70"))
			draw_circle(P.call(0.5, 0.46), 0.1 * s, Color("fbf6ea"))
			draw_line(P.call(0.5, 0.46), P.call(0.5, 0.39), Color(0.2, 0.2, 0.2), 0.025 * s, true)
			draw_line(P.call(0.5, 0.46), P.call(0.55, 0.46), Color(0.2, 0.2, 0.2), 0.025 * s, true)
		"ferris":
			draw_arc(P.call(0.5, 0.44), 0.32 * s, 0, TAU, 32, Color("b7c4cf"), 0.05 * s, true)
			for k in 8:
				var ang := k * TAU / 8.0
				var d := Vector2(cos(ang), sin(ang))
				draw_line(P.call(0.5, 0.44), P.call(0.5, 0.44) + d * 0.32 * s, Color("b7c4cf"), 0.025 * s, true)
				draw_circle(P.call(0.5, 0.44) + d * 0.32 * s, 0.06 * s, [Color("e85d5d"), Color("4b86d6"), Color("f2b33d"), Color("3fae8c")][k % 4])
			draw_line(P.call(0.5, 0.44), P.call(0.32, 0.9), Color("8a96a3"), 0.05 * s, true)
			draw_line(P.call(0.5, 0.44), P.call(0.68, 0.9), Color("8a96a3"), 0.05 * s, true)
		"raise":
			_rr(Rect2(P.call(0.14, 0.6), Vector2(0.72, 0.28) * s), 0.06 * s, Color("8fc56a"))
			draw_colored_polygon(PackedVector2Array([P.call(0.5, 0.1), P.call(0.74, 0.4), P.call(0.26, 0.4)]), a)
			draw_rect(Rect2(P.call(0.43, 0.38), Vector2(0.14, 0.16) * s), a)
		"lower":
			_rr(Rect2(P.call(0.14, 0.6), Vector2(0.72, 0.28) * s), 0.06 * s, Color("6fc3e8"))
			draw_colored_polygon(PackedVector2Array([P.call(0.5, 0.54), P.call(0.74, 0.26), P.call(0.26, 0.26)]), a)
			draw_rect(Rect2(P.call(0.43, 0.1), Vector2(0.14, 0.18) * s), a)
		"bulldoze":
			_rr(Rect2(P.call(0.18, 0.42), Vector2(0.5, 0.3) * s), 0.06 * s, Color("f2b33d"))
			_rr(Rect2(P.call(0.3, 0.26), Vector2(0.24, 0.18) * s), 0.04 * s, Color("f2b33d"))
			draw_colored_polygon(PackedVector2Array([P.call(0.7, 0.36), P.call(0.9, 0.3), P.call(0.9, 0.8), P.call(0.7, 0.74)]), Color("6c7a89"))
			_rr(Rect2(P.call(0.14, 0.72), Vector2(0.58, 0.14) * s), 0.07 * s, Color("3a3f47"))
		"people":
			draw_circle(P.call(0.5, 0.3), 0.16 * s, c)
			_rr(Rect2(P.call(0.22, 0.52), Vector2(0.56, 0.38) * s), 0.2 * s, c)
		"coin":
			draw_circle(P.call(0.5, 0.5), 0.4 * s, Color("f2b33d"))
			draw_circle(P.call(0.5, 0.5), 0.3 * s, Color("ffd36e"))
			_rr(Rect2(P.call(0.45, 0.32), Vector2(0.1, 0.36) * s), 0.04 * s, Color("e09a1f"))
		"smile":
			draw_circle(P.call(0.5, 0.5), 0.4 * s, Color("7be08f"))
			draw_circle(P.call(0.37, 0.42), 0.05 * s, Color(0.15, 0.3, 0.2))
			draw_circle(P.call(0.63, 0.42), 0.05 * s, Color(0.15, 0.3, 0.2))
			draw_arc(P.call(0.5, 0.52), 0.18 * s, 0.3, PI - 0.3, 12, Color(0.15, 0.3, 0.2), 0.05 * s, true)
		"menu":
			for i in 3:
				_rr(Rect2(P.call(0.22, 0.28 + i * 0.19), Vector2(0.56, 0.08) * s), 0.04 * s, c)
		"lock":
			draw_arc(P.call(0.5, 0.42), 0.16 * s, PI, TAU, 12, c, 0.07 * s, true)
			_rr(Rect2(P.call(0.28, 0.42), Vector2(0.44, 0.38) * s), 0.06 * s, c)
		"close":
			draw_line(P.call(0.28, 0.28), P.call(0.72, 0.72), c, 0.1 * s, true)
			draw_line(P.call(0.72, 0.28), P.call(0.28, 0.72), c, 0.1 * s, true)
		"globe":
			draw_arc(P.call(0.5, 0.5), 0.36 * s, 0, TAU, 32, c, 0.07 * s, true)
			draw_line(P.call(0.14, 0.5), P.call(0.86, 0.5), c, 0.06 * s, true)
			draw_arc(P.call(0.5, 0.5), 0.36 * s, -PI * 0.5, PI * 0.5, 16, c, 0.05 * s, true)
		"hand":
			draw_circle(P.call(0.5, 0.56), 0.24 * s, c)
			for i in 4:
				_rr(Rect2(P.call(0.3 + i * 0.11, 0.16 + absf(i - 1.5) * 0.06), Vector2(0.09, 0.4) * s), 0.045 * s, c)
