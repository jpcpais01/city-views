extends Node
## Ground mesh cost probe: CV_SEED, CV_MAP.


func _ready() -> void:
	var land := Land.new()
	add_child(land)
	var t0 := Time.get_ticks_msec()
	land.generate(int(OS.get_environment("CV_SEED")) if OS.get_environment("CV_SEED") != "" else 11, OS.get_environment("CV_MAP") if OS.get_environment("CV_MAP") != "" else "island")
	print("generate: %d ms" % (Time.get_ticks_msec() - t0))
	var hist := {}
	for s in land._steps:
		hist[s] = hist.get(s, 0) + 1
	print("steps: ", hist)
	var img := Image.create(Land.BLOCKS, Land.BLOCKS, false, Image.FORMAT_RGB8)
	for j in Land.BLOCKS:
		for i in Land.BLOCKS:
			var st: int = land._steps[j * Land.BLOCKS + i]
			var h := land.heights[(j * Land.BLOCK + 4) * Land.SIDE + i * Land.BLOCK + 4]
			img.set_pixel(i, j, Color(1.0 / st, clampf(h / 8.0, 0, 1), 0.3 if h < 0 else 0.0))
	img.resize(Land.BLOCKS * 4, Land.BLOCKS * 4, Image.INTERPOLATE_NEAREST)
	img.save_png("/tmp/shots/steps.png")
	var acc := TriBudget.count(land)
	for k in acc:
		print("  %s %d +%d" % [k, acc[k][0], acc[k][1]])
	var t1 := Time.get_ticks_msec()
	land.sculpt(Vector3(10, 0, 10), 6.0, 1.0)
	land.rebuild_dirty(1 << 20)
	print("stroke rebuild: %d ms" % (Time.get_ticks_msec() - t1))
	t1 = Time.get_ticks_msec()
	land.shore_image(16.0)
	print("shore: %d ms" % (Time.get_ticks_msec() - t1))
	get_tree().quit()
