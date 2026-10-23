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
	# icon corners are a few pixels across: 3 segments draw them just as round
	sb.corner_detail = 3
	sb.anti_aliasing = true
	draw_style_box(sb, r)


## Filled circle with just enough sides to look round at its size on screen
## (the built-in one always spends 64).
func _circle(c: Vector2, r: float, col: Color) -> void:
	var n := clampi(int(r * 1.3), 10, 40)
	var pts := PackedVector2Array()
	pts.resize(n)
	for i in n:
		var a := TAU * i / n
		pts[i] = c + Vector2(cos(a), sin(a)) * r
	draw_colored_polygon(pts, col)


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
			_circle(P.call(0.5, 0.42), 0.3 * s, Color("6fb35a"))
			_circle(P.call(0.36, 0.5), 0.18 * s, Color("82c063"))
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
			_circle(P.call(0.5, 0.26), 0.12 * s, Color("8fd6f5"))
			_circle(P.call(0.34, 0.36), 0.06 * s, Color("8fd6f5"))
			_circle(P.call(0.66, 0.36), 0.06 * s, Color("8fd6f5"))
		"windmill":
			draw_colored_polygon(PackedVector2Array([P.call(0.38, 0.9), P.call(0.62, 0.9), P.call(0.57, 0.42), P.call(0.43, 0.42)]), Color("efe7d8"))
			draw_colored_polygon(PackedVector2Array([P.call(0.4, 0.43), P.call(0.6, 0.43), P.call(0.5, 0.3)]), Color("8b5a44"))
			for k in 4:
				var ang := PI * 0.25 + k * PI * 0.5
				var d := Vector2(cos(ang), sin(ang))
				draw_line(P.call(0.5, 0.38), P.call(0.5, 0.38) + d * 0.36 * s, Color("8b5a44"), 0.07 * s, true)
			_circle(P.call(0.5, 0.38), 0.05 * s, Color("5b4a42"))
		"lighthouse":
			draw_colored_polygon(PackedVector2Array([P.call(0.36, 0.9), P.call(0.64, 0.9), P.call(0.58, 0.32), P.call(0.42, 0.32)]), Color.WHITE)
			draw_colored_polygon(PackedVector2Array([P.call(0.38, 0.72), P.call(0.62, 0.72), P.call(0.61, 0.6), P.call(0.39, 0.6)]), Color("d9534f"))
			draw_colored_polygon(PackedVector2Array([P.call(0.41, 0.48), P.call(0.59, 0.48), P.call(0.58, 0.38), P.call(0.42, 0.38)]), Color("d9534f"))
			_rr(Rect2(P.call(0.42, 0.2), Vector2(0.16, 0.12) * s), 0.02 * s, Color("ffd36e"))
			draw_colored_polygon(PackedVector2Array([P.call(0.38, 0.2), P.call(0.62, 0.2), P.call(0.5, 0.08)]), Color("d9534f"))
		"clocktower":
			_rr(Rect2(P.call(0.36, 0.3), Vector2(0.28, 0.6) * s), 0.04 * s, Color("c97b5a"))
			draw_colored_polygon(PackedVector2Array([P.call(0.32, 0.32), P.call(0.68, 0.32), P.call(0.5, 0.06)]), Color("4b5a70"))
			_circle(P.call(0.5, 0.46), 0.1 * s, Color("fbf6ea"))
			draw_line(P.call(0.5, 0.46), P.call(0.5, 0.39), Color(0.2, 0.2, 0.2), 0.025 * s, true)
			draw_line(P.call(0.5, 0.46), P.call(0.55, 0.46), Color(0.2, 0.2, 0.2), 0.025 * s, true)
		"ferris":
			draw_arc(P.call(0.5, 0.44), 0.32 * s, 0, TAU, 32, Color("b7c4cf"), 0.05 * s, true)
			for k in 8:
				var ang := k * TAU / 8.0
				var d := Vector2(cos(ang), sin(ang))
				draw_line(P.call(0.5, 0.44), P.call(0.5, 0.44) + d * 0.32 * s, Color("b7c4cf"), 0.025 * s, true)
				_circle(P.call(0.5, 0.44) + d * 0.32 * s, 0.06 * s, [Color("e85d5d"), Color("4b86d6"), Color("f2b33d"), Color("3fae8c")][k % 4])
			draw_line(P.call(0.5, 0.44), P.call(0.32, 0.9), Color("8a96a3"), 0.05 * s, true)
			draw_line(P.call(0.5, 0.44), P.call(0.68, 0.9), Color("8a96a3"), 0.05 * s, true)
		"lane":
			_rr(Rect2(P.call(0.26, 0.08), Vector2(0.48, 0.84) * s), 0.08 * s, Color("a39a8c"))
			for yy in 5:
				for xx in 3:
					var off := 0.07 if yy % 2 == 0 else 0.0
					_rr(Rect2(P.call(0.3 + xx * 0.14 + off - 0.035, 0.12 + yy * 0.16), Vector2(0.11, 0.12) * s), 0.03 * s, Color("cfc4b2"))
			_circle(P.call(0.86, 0.22), 0.07 * s, Color("ffd36e"))
			draw_rect(Rect2(P.call(0.845, 0.28), Vector2(0.03, 0.6) * s), Color("4a4f57"))
		"avenue":
			_rr(Rect2(P.call(0.14, 0.08), Vector2(0.72, 0.84) * s), 0.08 * s, Color(0.36, 0.38, 0.43))
			_rr(Rect2(P.call(0.44, 0.08), Vector2(0.12, 0.84) * s), 0.05 * s, Color("8fc56a"))
			for i in 3:
				_circle(P.call(0.5, 0.2 + i * 0.3), 0.1 * s, Color("5ea552"))
			for i in 2:
				draw_rect(Rect2(P.call(0.27, 0.22 + i * 0.36), Vector2(0.05, 0.16) * s), Color(1, 0.95, 0.8))
				draw_rect(Rect2(P.call(0.68, 0.22 + i * 0.36), Vector2(0.05, 0.16) * s), Color(1, 0.95, 0.8))
		"terrace":
			var tc := [Color("f3c6a5"), Color("c9dbe9"), Color("f6dca7")]
			for i in 3:
				var x0 := 0.08 + i * 0.28
				_rr(Rect2(P.call(x0, 0.34), Vector2(0.28, 0.54) * s), 0.02 * s, tc[i])
				draw_colored_polygon(PackedVector2Array([P.call(x0, 0.36), P.call(x0 + 0.14, 0.18), P.call(x0 + 0.28, 0.36)]), Color("b9503f").darkened(i * 0.08))
				_rr(Rect2(P.call(x0 + 0.09, 0.66), Vector2(0.1, 0.22) * s), 0.02 * s, Color("5b4a42"))
				_rr(Rect2(P.call(x0 + 0.08, 0.44), Vector2(0.12, 0.12) * s), 0.02 * s, Color("6fa8d8"))
		"villa":
			_rr(Rect2(P.call(0.06, 0.78), Vector2(0.88, 0.12) * s), 0.04 * s, Color("8fd6f5"))
			draw_colored_polygon(PackedVector2Array([P.call(0.1, 0.4), P.call(0.3, 0.2), P.call(0.7, 0.2), P.call(0.9, 0.4)]), Color("c9774b"))
			_rr(Rect2(P.call(0.16, 0.4), Vector2(0.68, 0.38) * s), 0.04 * s, Color("fbf1df"))
			for i in 3:
				_rr(Rect2(P.call(0.22 + i * 0.2, 0.48), Vector2(0.14, 0.2) * s), 0.02 * s, Color("6fa8d8"))
			_circle(P.call(0.12, 0.7), 0.1 * s, Color("5ea552"))
		"apartments":
			_rr(Rect2(P.call(0.18, 0.1), Vector2(0.64, 0.8) * s), 0.05 * s, Color("e9b8a5"))
			for yy in 4:
				for xx in 3:
					_rr(Rect2(P.call(0.24 + xx * 0.19, 0.16 + yy * 0.17), Vector2(0.13, 0.1) * s), 0.02 * s, Color("6fa8d8"))
				_rr(Rect2(P.call(0.2, 0.27 + yy * 0.17), Vector2(0.6, 0.03) * s), 0.01 * s, Color.WHITE)
			_rr(Rect2(P.call(0.43, 0.76), Vector2(0.14, 0.14) * s), 0.02 * s, Color("5b4a42"))
		"cafe":
			_rr(Rect2(P.call(0.18, 0.62), Vector2(0.44, 0.2) * s), 0.08 * s, Color.WHITE)
			_rr(Rect2(P.call(0.2, 0.6), Vector2(0.4, 0.06) * s), 0.03 * s, Color("8b5a44"))
			draw_arc(P.call(0.66, 0.72), 0.08 * s, -PI * 0.5, PI * 0.5, 10, Color.WHITE, 0.05 * s, true)
			for k in 3:
				var xx := 0.28 + k * 0.12
				draw_line(P.call(xx, 0.52), P.call(xx + 0.04, 0.3), Color(0.6, 0.62, 0.68), 0.035 * s, true)
			_rr(Rect2(P.call(0.12, 0.84), Vector2(0.62, 0.05) * s), 0.02 * s, Color("8b5a44"))
		"market":
			for i in 3:
				var col: Color = [Color("e85d5d"), Color("f2b33d"), Color("3fae8c")][i]
				var x0 := 0.06 + i * 0.3
				draw_colored_polygon(PackedVector2Array([P.call(x0, 0.42), P.call(x0 + 0.14, 0.24), P.call(x0 + 0.28, 0.42)]), col)
				draw_rect(Rect2(P.call(x0 + 0.02, 0.42), Vector2(0.03, 0.4) * s), Color("8b5a44"))
				draw_rect(Rect2(P.call(x0 + 0.23, 0.42), Vector2(0.03, 0.4) * s), Color("8b5a44"))
				_rr(Rect2(P.call(x0 + 0.02, 0.62), Vector2(0.24, 0.12) * s), 0.02 * s, Color("d9a46a"))
				_circle(P.call(x0 + 0.09, 0.6), 0.04 * s, Color("ef5b5b"))
				_circle(P.call(x0 + 0.18, 0.6), 0.04 * s, Color("97c45a"))
		"store":
			_rr(Rect2(P.call(0.08, 0.3), Vector2(0.84, 0.58) * s), 0.05 * s, Color("e8e2d6"))
			_rr(Rect2(P.call(0.08, 0.3), Vector2(0.84, 0.12) * s), 0.04 * s, Color("8a6fd6"))
			_rr(Rect2(P.call(0.3, 0.14), Vector2(0.4, 0.18) * s), 0.04 * s, Color("8fc8ec"))
			for xx in 4:
				_rr(Rect2(P.call(0.14 + xx * 0.19, 0.5), Vector2(0.14, 0.18) * s), 0.02 * s, Color("8fc8ec"))
			_rr(Rect2(P.call(0.42, 0.72), Vector2(0.16, 0.16) * s), 0.02 * s, Color("5b8db8"))
		"studio":
			_rr(Rect2(P.call(0.08, 0.5), Vector2(0.84, 0.38) * s), 0.04 * s, Color("dfe6ec"))
			_rr(Rect2(P.call(0.3, 0.3), Vector2(0.56, 0.22) * s), 0.04 * s, Color("cfe3d6"))
			_rr(Rect2(P.call(0.3, 0.26), Vector2(0.56, 0.06) * s), 0.03 * s, Color("6fb35a"))
			for xx in 4:
				_rr(Rect2(P.call(0.12 + xx * 0.2, 0.58), Vector2(0.16, 0.2) * s), 0.02 * s, Color("5b8db8"))
			for xx in 3:
				draw_colored_polygon(PackedVector2Array([P.call(0.1 + xx * 0.06, 0.48), P.call(0.14 + xx * 0.06, 0.38), P.call(0.18 + xx * 0.06, 0.38), P.call(0.14 + xx * 0.06, 0.48)]), Color("4b5a70"))
		"hotel":
			_rr(Rect2(P.call(0.24, 0.12), Vector2(0.52, 0.76) * s), 0.05 * s, Color("f2d9c4"))
			for yy in 5:
				_rr(Rect2(P.call(0.2, 0.26 + yy * 0.12), Vector2(0.6, 0.04) * s), 0.02 * s, Color.WHITE)
				for xx in 3:
					_rr(Rect2(P.call(0.29 + xx * 0.15, 0.2 + yy * 0.12), Vector2(0.1, 0.06) * s), 0.02 * s, Color("6fa8d8"))
			_rr(Rect2(P.call(0.3, 0.04), Vector2(0.4, 0.1) * s), 0.03 * s, a)
			_rr(Rect2(P.call(0.38, 0.8), Vector2(0.24, 0.08) * s), 0.02 * s, Color("5b4a42"))
		"playground":
			draw_line(P.call(0.14, 0.88), P.call(0.3, 0.26), Color("e85d5d"), 0.05 * s, true)
			draw_line(P.call(0.46, 0.88), P.call(0.3, 0.26), Color("e85d5d"), 0.05 * s, true)
			draw_line(P.call(0.3, 0.26), P.call(0.6, 0.26), Color("e85d5d"), 0.05 * s, true)
			draw_line(P.call(0.4, 0.28), P.call(0.4, 0.62), Color(0.4, 0.4, 0.45), 0.02 * s, true)
			_rr(Rect2(P.call(0.34, 0.6), Vector2(0.12, 0.05) * s), 0.02 * s, Color("4b86d6"))
			draw_colored_polygon(PackedVector2Array([P.call(0.6, 0.26), P.call(0.68, 0.26), P.call(0.92, 0.86), P.call(0.82, 0.88)]), Color("f2b33d"))
			draw_rect(Rect2(P.call(0.6, 0.26), Vector2(0.04, 0.62) * s), Color(0.4, 0.4, 0.45))
		"pond":
			_circle(P.call(0.5, 0.6), 0.36 * s, Color("8fc56a"))
			_circle(P.call(0.5, 0.6), 0.28 * s, Color("6fc3e8"))
			_circle(P.call(0.4, 0.56), 0.07 * s, Color("5ea552"))
			_circle(P.call(0.6, 0.66), 0.05 * s, Color("5ea552"))
			_circle(P.call(0.62, 0.5), 0.06 * s, Color.WHITE)
			_circle(P.call(0.67, 0.46), 0.035 * s, Color.WHITE)
			draw_rect(Rect2(P.call(0.69, 0.455), Vector2(0.04, 0.02) * s), Color("f2b33d"))
			for k in 3:
				draw_line(P.call(0.16 + k * 0.05, 0.6), P.call(0.14 + k * 0.06, 0.3), Color("5e8f3e"), 0.03 * s, true)
		"plaza":
			_rr(Rect2(P.call(0.08, 0.3), Vector2(0.84, 0.6) * s), 0.06 * s, Color("e8dcc6"))
			for yy in 3:
				for xx in 4:
					if (xx + yy) % 2 == 0:
						_rr(Rect2(P.call(0.12 + xx * 0.2, 0.34 + yy * 0.18), Vector2(0.16, 0.14) * s), 0.02 * s, Color("d2c3a8"))
			_rr(Rect2(P.call(0.4, 0.5), Vector2(0.2, 0.14) * s), 0.03 * s, Color("b8ab9c"))
			_circle(P.call(0.5, 0.34), 0.16 * s, Color("5ea552"))
			draw_rect(Rect2(P.call(0.48, 0.4), Vector2(0.04, 0.12) * s), Color("8b5a44"))
		"pitch":
			_rr(Rect2(P.call(0.06, 0.2), Vector2(0.88, 0.6) * s), 0.04 * s, Color("5fae4e"))
			for xx in 4:
				if xx % 2 == 0:
					draw_rect(Rect2(P.call(0.06 + xx * 0.22, 0.2), Vector2(0.22, 0.6) * s), Color("6fbf5a"))
			var wl := Color(1, 1, 1, 0.95)
			draw_rect(Rect2(P.call(0.1, 0.24), Vector2(0.8, 0.52) * s), wl, false, 0.025 * s)
			draw_line(P.call(0.5, 0.24), P.call(0.5, 0.76), wl, 0.025 * s)
			draw_arc(P.call(0.5, 0.5), 0.1 * s, 0, TAU, 16, wl, 0.025 * s, true)
			draw_rect(Rect2(P.call(0.1, 0.4), Vector2(0.08, 0.2) * s), wl, false, 0.02 * s)
			draw_rect(Rect2(P.call(0.82, 0.4), Vector2(0.08, 0.2) * s), wl, false, 0.02 * s)
		"oak":
			draw_rect(Rect2(P.call(0.45, 0.58), Vector2(0.1, 0.32) * s), Color("8b5a44"))
			_circle(P.call(0.5, 0.4), 0.28 * s, Color("5ea552"))
			_circle(P.call(0.32, 0.52), 0.17 * s, Color("6fb35a"))
			_circle(P.call(0.68, 0.52), 0.17 * s, Color("4e9a54"))
			_circle(P.call(0.42, 0.32), 0.1 * s, Color("82c063"))
		"pine":
			draw_rect(Rect2(P.call(0.46, 0.78), Vector2(0.08, 0.14) * s), Color("8b5a44"))
			for k in 3:
				var y0 := 0.06 + k * 0.22
				draw_colored_polygon(PackedVector2Array([P.call(0.5, y0), P.call(0.74 + k * 0.05, y0 + 0.32), P.call(0.26 - k * 0.05, y0 + 0.32)]), Color("3f7f4f").lightened(k * 0.06))
		"palm":
			draw_line(P.call(0.46, 0.92), P.call(0.56, 0.32), Color("a88a5c"), 0.07 * s, true)
			for k in 5:
				var ang := PI + 0.25 + k * 0.62
				var d := Vector2(cos(ang), sin(ang) * 0.6 + 0.25)
				draw_line(P.call(0.56, 0.32), P.call(0.56, 0.32) + d * 0.34 * s, Color("5fae4e"), 0.08 * s, true)
			_circle(P.call(0.56, 0.34), 0.05 * s, Color("8b5a44"))
		"blossom":
			draw_rect(Rect2(P.call(0.45, 0.58), Vector2(0.1, 0.32) * s), Color("7a5a4a"))
			_circle(P.call(0.5, 0.4), 0.28 * s, Color("f4a7c0"))
			_circle(P.call(0.32, 0.52), 0.16 * s, Color("f7c2d4"))
			_circle(P.call(0.68, 0.5), 0.17 * s, Color("ee8fb0"))
			for k in 4:
				_circle(P.call(0.24 + k * 0.17, 0.9 - (k % 2) * 0.04), 0.03 * s, Color("f7c2d4"))
		"flowers":
			for k in 7:
				var xx := 0.12 + k * 0.125
				draw_line(P.call(xx, 0.9), P.call(xx + 0.02, 0.5 + (k % 3) * 0.08), Color("5e8f3e"), 0.03 * s, true)
			var fl := [Color("ef5b5b"), Color("f2c14e"), Color.WHITE, Color("8a6fd6"), Color("ef7fa8"), Color("f2c14e"), Color("4b86d6")]
			for k in 7:
				_circle(P.call(0.14 + k * 0.125, 0.48 + (k % 3) * 0.08), 0.06 * s, fl[k])
			_rr(Rect2(P.call(0.06, 0.86), Vector2(0.88, 0.06) * s), 0.03 * s, Color("8fc56a"))
		"bandstand":
			_rr(Rect2(P.call(0.12, 0.78), Vector2(0.76, 0.1) * s), 0.04 * s, Color("e8e2d6"))
			for k in 4:
				draw_rect(Rect2(P.call(0.18 + k * 0.2, 0.4), Vector2(0.04, 0.38) * s), Color.WHITE)
			draw_colored_polygon(PackedVector2Array([P.call(0.08, 0.42), P.call(0.5, 0.12), P.call(0.92, 0.42)]), Color("3fae8c"))
			for k in 5:
				_circle(P.call(0.16 + k * 0.17, 0.46), 0.035 * s, [Color("e85d5d"), Color("f2b33d"), Color("4b86d6")][k % 3])
			_circle(P.call(0.5, 0.1), 0.04 * s, Color("f2c14e"))
		"pier":
			_rr(Rect2(P.call(0.04, 0.62), Vector2(0.92, 0.3) * s), 0.06 * s, Color("6fc3e8"))
			_rr(Rect2(P.call(0.06, 0.5), Vector2(0.88, 0.08) * s), 0.02 * s, Color("c9a06a"))
			for k in 5:
				draw_rect(Rect2(P.call(0.1 + k * 0.19, 0.58), Vector2(0.04, 0.24) * s), Color("8b5a44"))
			_rr(Rect2(P.call(0.66, 0.3), Vector2(0.24, 0.2) * s), 0.03 * s, Color("fbefd9"))
			draw_colored_polygon(PackedVector2Array([P.call(0.62, 0.32), P.call(0.78, 0.18), P.call(0.94, 0.32)]), Color("e85d5d"))
		"observatory":
			_rr(Rect2(P.call(0.2, 0.52), Vector2(0.6, 0.36) * s), 0.04 * s, Color("e8e2d6"))
			_circle(P.call(0.5, 0.52), 0.3 * s, Color("dfe6ec"))
			draw_rect(Rect2(P.call(0.2, 0.52), Vector2(0.6, 0.06) * s), Color("c9bfb2"))
			draw_line(P.call(0.5, 0.42), P.call(0.74, 0.18), Color("4b5a70"), 0.08 * s, true)
			draw_rect(Rect2(P.call(0.46, 0.24), Vector2(0.08, 0.3) * s), Color("8a96a3"))
			_rr(Rect2(P.call(0.42, 0.68), Vector2(0.16, 0.2) * s), 0.02 * s, Color("5b4a42"))
			_circle(P.call(0.18, 0.18), 0.04 * s, Color("ffd36e"))
			_circle(P.call(0.3, 0.1), 0.025 * s, Color("ffd36e"))
		"raise":
			_rr(Rect2(P.call(0.14, 0.6), Vector2(0.72, 0.28) * s), 0.06 * s, Color("8fc56a"))
			draw_colored_polygon(PackedVector2Array([P.call(0.5, 0.1), P.call(0.74, 0.4), P.call(0.26, 0.4)]), a)
			draw_rect(Rect2(P.call(0.43, 0.38), Vector2(0.14, 0.16) * s), a)
		"lower":
			_rr(Rect2(P.call(0.14, 0.6), Vector2(0.72, 0.28) * s), 0.06 * s, Color("6fc3e8"))
			draw_colored_polygon(PackedVector2Array([P.call(0.5, 0.54), P.call(0.74, 0.26), P.call(0.26, 0.26)]), a)
			draw_rect(Rect2(P.call(0.43, 0.1), Vector2(0.14, 0.18) * s), a)
		"smooth":
			# a rough hill eased into a soft one
			var pts := PackedVector2Array([P.call(0.1, 0.86)])
			for k in 13:
				var u := k / 12.0
				pts.append(P.call(0.1 + u * 0.8, 0.86 - 0.42 * sin(u * PI) * (1.0 - 0.18 * (k % 2))))
			pts.append(P.call(0.9, 0.86))
			draw_colored_polygon(pts, Color("8fc56a"))
			var arc := PackedVector2Array()
			for k in 13:
				var u := k / 12.0
				arc.append(P.call(0.1 + u * 0.8, 0.36 - 0.2 * sin(u * PI)))
			draw_polyline(arc, a, 0.07 * s, true)
		"flatten":
			draw_colored_polygon(PackedVector2Array([P.call(0.1, 0.86), P.call(0.1, 0.56), P.call(0.9, 0.56), P.call(0.9, 0.86)]), Color("8fc56a"))
			draw_rect(Rect2(P.call(0.14, 0.4), Vector2(0.72, 0.08) * s), a)
			draw_colored_polygon(PackedVector2Array([P.call(0.5, 0.36), P.call(0.66, 0.14), P.call(0.34, 0.14)]), a)
		"bulldoze":
			_rr(Rect2(P.call(0.18, 0.42), Vector2(0.5, 0.3) * s), 0.06 * s, Color("f2b33d"))
			_rr(Rect2(P.call(0.3, 0.26), Vector2(0.24, 0.18) * s), 0.04 * s, Color("f2b33d"))
			draw_colored_polygon(PackedVector2Array([P.call(0.7, 0.36), P.call(0.9, 0.3), P.call(0.9, 0.8), P.call(0.7, 0.74)]), Color("6c7a89"))
			_rr(Rect2(P.call(0.14, 0.72), Vector2(0.58, 0.14) * s), 0.07 * s, Color("3a3f47"))
		"people":
			_circle(P.call(0.5, 0.3), 0.16 * s, c)
			_rr(Rect2(P.call(0.22, 0.52), Vector2(0.56, 0.38) * s), 0.2 * s, c)
		"star":
			var pts := PackedVector2Array()
			for k in 10:
				var r := 0.42 if k % 2 == 0 else 0.19
				var ang := -PI * 0.5 + k * PI / 5.0
				pts.append(P.call(0.5 + cos(ang) * r, 0.53 + sin(ang) * r))
			draw_colored_polygon(pts, Color("ffc94d"))
			var inner := PackedVector2Array()
			for q in pts:
				inner.append(P.call(0.5, 0.53).lerp(q, 0.55))
			draw_colored_polygon(inner, Color("ffe08a"))
		"coin":
			_circle(P.call(0.5, 0.5), 0.4 * s, Color("f2b33d"))
			_circle(P.call(0.5, 0.5), 0.3 * s, Color("ffd36e"))
			_rr(Rect2(P.call(0.45, 0.32), Vector2(0.1, 0.36) * s), 0.04 * s, Color("e09a1f"))
		"smile":
			_circle(P.call(0.5, 0.5), 0.4 * s, Color("7be08f"))
			_circle(P.call(0.37, 0.42), 0.05 * s, Color(0.15, 0.3, 0.2))
			_circle(P.call(0.63, 0.42), 0.05 * s, Color(0.15, 0.3, 0.2))
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
			_circle(P.call(0.5, 0.56), 0.24 * s, c)
			for i in 4:
				_rr(Rect2(P.call(0.3 + i * 0.11, 0.16 + absf(i - 1.5) * 0.06), Vector2(0.09, 0.4) * s), 0.045 * s, c)
		"undo", "redo":
			# a curled arrow; redo is the mirror image
			var m := 1.0 if kind == "undo" else -1.0
			var Q := func(x: float, y: float) -> Vector2: return P.call(0.5 + (x - 0.5) * m, y)
			draw_arc(Q.call(0.52, 0.56), 0.24 * s, -PI * 0.5 if kind == "undo" else PI * 0.5, PI * 0.5 if kind == "undo" else PI * 1.5, 20, c, 0.09 * s, true)
			draw_line(Q.call(0.52, 0.8), Q.call(0.36, 0.8), c, 0.09 * s, true)
			draw_line(Q.call(0.52, 0.32), Q.call(0.36, 0.32), c, 0.09 * s, true)
			draw_colored_polygon(PackedVector2Array([Q.call(0.14, 0.32), Q.call(0.4, 0.14), Q.call(0.4, 0.5)]), c)
