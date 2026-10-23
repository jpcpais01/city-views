extends Node
## Visual sanity check: builds a demo town and saves screenshots.
## xvfb-run godot --path . --rendering-driver opengl3 tests/shot.tscn

var world: World


func _ready() -> void:
	Game.new_world(1234)
	Game.coins = 1e6
	for t in Game.TOOLS:
		Game.unlocked[t.id] = true
	var cx := 30
	var cz := 30
	for z in range(cz - 10, cz + 11):
		for x in range(cx - 12, cx + 13):
			if Game.lvl(x, z) < 1:
				continue
			var road := (x - cx) % 4 == 0 or (z - cz) % 4 == 0
			var k := Game.K.ROAD
			if not road:
				var r := Game.hashf(x, z, 500)
				var dc := Vector2(x - cx, z - cz).length()
				if dc < 5 and r < 0.7: k = Game.K.OFFICE
				elif r < 0.12: k = Game.K.PARK
				elif r < 0.3: k = Game.K.SHOP
				else: k = Game.K.HOUSE
			Game.set_tile(x, z, k, Game.lvl(x, z), Game.hash2(x, z, 7) % 250)
	Game.set_tile(cx + 2, cz + 2, Game.K.LANDMARK, Game.lvl(cx + 2, cz + 2), Game.LM.FOUNTAIN)
	Game.set_tile(cx - 6, cz + 6, Game.K.LANDMARK, Game.lvl(cx - 6, cz + 6), Game.LM.FERRIS)
	# CV_HILL=x,z raises a stepped, ragged mound there (terrace edge check)
	var hp := OS.get_environment("CV_HILL")
	if hp != "":
		var hx := int(hp.split(",")[0])
		var hz := int(hp.split(",")[1])
		for z in range(hz - 7, hz + 8):
			for x in range(hx - 7, hx + 8):
				var d := Vector2(x - hx, z - hz).length() + Game.hashf(x, z, 9) * 1.5
				var l := clampi(int(5.0 - d * 0.6), 0, 4)
				if Game.lvl(x, z) >= 1 and l > 0:
					Game.set_tile(x, z, Game.K.TREE if Game.hashf(x, z, 3) < 0.15 else Game.K.EMPTY, 1 + l, 0)
	Game.population = 2000
	for i in Game.kind.size():
		if Game.is_building(Game.kind[i]):
			var x := i % Game.N
			var z := i / Game.N
			Game.growth[i] = Game.target_growth(x, z)
	world = World.new()
	add_child(world)
	var hud := Hud.new()
	hud.world = world
	add_child(hud)
	if OS.get_environment("CV_FLUSH") != "":
		while not world._build_queue.is_empty():
			world._process(0.0)
		if "_batch_dirty" in world:
			for b in world._batch_dirty.keys():
				world._rebuild_batch(b)
	world.time_of_day = float(OS.get_environment("CV_TIME")) if OS.get_environment("CV_TIME") != "" else 0.4
	await get_tree().create_timer(1.0).timeout
	var fp := OS.get_environment("CV_FOCUS")
	if fp != "":
		var parts := fp.split(",")
		world.rig.focus(Game.tile_center(int(parts[0]), int(parts[1])))
	else:
		world.rig.focus(Game.tile_center(cx, cz))
	world.rig._t_dist = float(OS.get_environment("CV_DIST")) if OS.get_environment("CV_DIST") != "" else 34.0
	await get_tree().create_timer(float(OS.get_environment("CV_WAIT")) if OS.get_environment("CV_WAIT") != "" else 10.0).timeout
	if OS.get_environment("CV_MENU") != "":
		hud._page = OS.get_environment("CV_MENU")
		hud._toggle_menu()
		await get_tree().create_timer(1.5).timeout
	print("geometry nodes: ", world.find_children("*", "GeometryInstance3D", true, false).size())
	print("draw calls: ", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), "  objects: ", Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME), "  prims: ", Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var img := get_viewport().get_texture().get_image()
	img.save_png(OS.get_environment("CV_OUT") if OS.get_environment("CV_OUT") != "" else "/tmp/shot.png")
	get_tree().quit()


func _process(_d: float) -> void:
	if world and Engine.get_process_frames() % 120 == 0:
		var bad := 0
		for c in world.traffic._cars:
			var p: Vector3 = c.node.position
			var t := Game.world_to_tile(p)
			if Game.knd(t.x, t.y) != Game.K.ROAD:
				bad += 1
				if bad < 4:
					print("off-road ", t, " car tile ", c.tile, " din ", c.din, " dout ", c.dout, " t ", c.t, " kind ", Game.knd(t.x, t.y))
		print("cars ", world.traffic._cars.size(), " bad ", bad)
