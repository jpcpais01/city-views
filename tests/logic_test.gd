extends Node
## Headless logic checks: run with `godot --headless --path . tests/logic_test.tscn`

var failures := 0


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		printerr("FAIL: ", msg)
	else:
		print("ok: ", msg)


func _ready() -> void:
	Game.new_world(1234)
	Game.coins = 100000
	# find a flat run of land for a street
	var row := -1
	var x0 := -1
	for z in range(8, Game.N - 8):
		for x in range(6, Game.N - 16):
			var ok := true
			for k in 10:
				for dz in range(-1, 2):
					if Game.lvl(x + k, z + dz) != 2:
						ok = false
			if ok:
				row = z; x0 = x
				break
		if row >= 0:
			break
	check(row >= 0, "found flat land")
	for k in 10:
		Game.apply_tool("road", x0 + k, row)
	check(Game.knd(x0, row) == Game.K.ROAD, "road placed")
	var links := CityGen.road_links(x0 + 3, row)
	check(links[0] and links[2] and not links[1] and not links[3], "straight road links east/west")
	for k in 10:
		Game.apply_tool("house", x0 + k, row - 1)
	Game.apply_tool("shop", x0 + 2, row + 1)
	Game.apply_tool("park", x0 + 5, row + 1)
	check(Game.knd(x0, row - 1) == Game.K.HOUSE, "house placed")
	check(Game.check_tool("house", x0, row) == "Occupied", "can't build over road")
	for i in 400:
		Game._grow_step()
	check(Game.population > 0, "population grows (%d)" % Game.population)
	check(Game.grw(x0, row - 1) >= 1, "house grew to level %d" % Game.grw(x0, row - 1))
	# isolated house stays a building site
	Game.apply_tool("house", x0 + 4, row - 4)
	for i in 200:
		Game._grow_step()
	check(Game.grw(x0 + 4, row - 4) == 0, "house without road stays a lot")
	# every tile type generates geometry without errors
	var mat := ShaderMaterial.new()
	var t0 := Time.get_ticks_msec()
	var built := 0
	for z in Game.N:
		for x in Game.N:
			var n := CityGen.build(x, z, mat, mat)
			if n:
				built += 1
				n.free()
	print("built %d tiles in %d ms" % [built, Time.get_ticks_msec() - t0])
	for lm in ["fountain", "windmill", "lighthouse", "clocktower", "ferris"]:
		Game.unlocked[lm] = true
	Game.set_tile(10, 10, Game.K.LANDMARK, 3, Game.LM.FERRIS)
	for p in [Game.LM.FOUNTAIN, Game.LM.LIGHTHOUSE, Game.LM.WINDMILL, Game.LM.CLOCKTOWER, Game.LM.FERRIS]:
		Game.set_tile(10, 10, Game.K.LANDMARK, 3, p)
		var n := CityGen.build(10, 10, mat, mat)
		check(n != null and (n.get_child(0) as MeshInstance3D).mesh.get_surface_count() >= 1, "landmark %d builds" % p)
		n.free()
	for g in 4:
		for k in [Game.K.HOUSE, Game.K.SHOP, Game.K.OFFICE]:
			Game.set_tile(12, 12, k, 2, 5)
			Game.growth[Game.idx(12, 12)] = g
			var n := CityGen.build(12, 12, mat, mat)
			check(n != null, "kind %d growth %d builds" % [k, g])
			n.free()
	# ramps: road climbing one terrace
	Game.set_tile(20, 20, Game.K.ROAD, 2, 0)
	Game.set_tile(21, 20, Game.K.ROAD, 2, 0)
	Game.set_tile(22, 20, Game.K.ROAD, 3, 0)
	Game.set_tile(20, 19, Game.K.EMPTY, 2, 0)
	Game.set_tile(20, 21, Game.K.EMPTY, 2, 0)
	Game.set_tile(21, 19, Game.K.EMPTY, 2, 0)
	Game.set_tile(21, 21, Game.K.EMPTY, 2, 0)
	check(CityGen.ramp_dir(21, 20) == 0, "ramp detected toward the higher road")
	check(CityGen.road_links(22, 20)[2], "upper road links down the ramp")
	check(absf(CityGen.road_height(21, 20, Vector2(1.0, 0)) - (Game.LEVEL_Y[3] - Game.LEVEL_Y[2])) < 0.01, "ramp top meets upper level")
	# save / load roundtrip
	var d := Game.to_dict()
	var pop := Game.population
	var json := JSON.stringify(d)
	Game.new_world(99)
	Game.from_dict(JSON.parse_string(json))
	check(Game.knd(x0, row) == Game.K.ROAD and Game.population == pop, "save/load roundtrip keeps the city (pop %d)" % pop)
	# terraform
	Game.set_tile(30, 30, Game.K.EMPTY, 2, 0)
	Game.apply_tool("raise", 30, 30)
	check(Game.lvl(30, 30) == 3, "raise works")
	Game.apply_tool("lower", 30, 30)
	Game.apply_tool("lower", 30, 30)
	check(Game.lvl(30, 30) == 1, "lower works")
	# undo / redo: a whole drag undoes as one step and money comes back exactly
	Game.end_stroke()
	Game.set_tile(30, 30, Game.K.EMPTY, 2, 0)
	Game.set_tile(31, 30, Game.K.EMPTY, 2, 0)
	Game.set_tile(32, 30, Game.K.EMPTY, 2, 0)
	Game.coins = 1000.0
	Game.apply_tool("road", 30, 30)
	Game.apply_tool("road", 31, 30)
	Game.apply_tool("road", 32, 30)
	Game.end_stroke()
	var spent := 1000.0 - Game.coins
	check(spent > 0.0, "roads cost coins")
	check(Game.undo() and Game.knd(31, 30) == Game.K.EMPTY and Game.knd(30, 30) == Game.K.EMPTY, "undo clears the stroke")
	check(absf(Game.coins - 1000.0) < 0.01, "undo refunds in full")
	check(Game.redo() and Game.knd(32, 30) == Game.K.ROAD, "redo puts it back")
	check(absf(1000.0 - Game.coins - spent) < 0.01, "redo costs the same, no extra")
	check(not Game.can_redo(), "redo stack empties")
	Game.apply_tool("bulldoze", 31, 30)
	Game.end_stroke()
	var after_doze := Game.coins
	Game.undo()
	check(Game.knd(31, 30) == Game.K.ROAD and Game.coins < after_doze, "undo bulldoze restores road and takes back the refund")
	await _tri_budget()
	print("FAILURES: %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)


## Frame budget: a town the size players have now with every sub-type mixed in,
## the whole island in view and every car and pedestrian out, must draw under
## TriBudget.BUDGET triangles (shadow pass included) with room left for the HUD.
func _tri_budget() -> void:
	Game.new_world(1234)
	for z in range(24, 37):
		for x in range(22, 39):
			if Game.lvl(x, z) < 1:
				continue
			var k := Game.K.ROAD
			if (x - 30) % 4 != 0 and (z - 30) % 4 != 0:
				var r := Game.hashf(x, z, 500)
				k = Game.K.OFFICE if Vector2(x - 30, z - 30).length() < 5 and r < 0.7 else (Game.K.PARK if r < 0.12 else (Game.K.SHOP if r < 0.3 else Game.K.HOUSE))
			Game.set_tile(x, z, k, Game.lvl(x, z), Game.param_for(k, Game.hash2(x, z, 7) % Game.SUB_COUNT.get(k, 1), x, z))
	Game.set_tile(32, 32, Game.K.LANDMARK, Game.lvl(32, 32), Game.LM.FOUNTAIN)
	for i in Game.kind.size():
		if Game.is_building(Game.kind[i]):
			Game.growth[i] = Game.target_growth(i % Game.N, i / Game.N)
	var world := World.new()
	add_child(world)
	await get_tree().process_frame
	while not world._build_queue.is_empty():
		world._process(0.0)
	# let the pop-in animations settle so every tile is merged into its block
	await get_tree().create_timer(1.5).timeout
	for b in world._batch_dirty.keys():
		world._rebuild_batch(b)
	# merged tiles are freed at the end of the frame
	await get_tree().process_frame
	await get_tree().process_frame
	var acc := TriBudget.count(world)
	acc.erase("Traffic")
	acc.erase("People")
	var total := TriBudget.total(acc)
	# moving things at their most: the biggest car / person mesh times the cap
	var car := 0
	for m in world.traffic._meshes:
		car = maxi(car, TriBudget.tris(m))
	var car_sh := 0
	for m in world.traffic._shadow_meshes:
		if m:
			car_sh = maxi(car_sh, TriBudget.tris(m))
	var person := 0
	for mm in world.people._multi:
		person = maxi(person, TriBudget.tris(mm.mesh))
	# as many as this town can hold (the same caps the game uses), at a big population
	world.traffic._rebuild_tiles()
	world.people._rebuild_roads()
	var cars := mini(world.traffic._road_tiles.size() / 3, Traffic.MAX_CARS - 8)
	var people := mini(world.people._roads.size(), People.MAX_PEOPLE - 4)
	print("  %d cars, %d people" % [cars, people])
	total += (car + car_sh) * cars + person * people
	for k in acc:
		print("  tris %-24s %7d +shadow %7d" % [k, acc[k][0], acc[k][1]])
	print("  car %d + %d, person %d" % [car, car_sh, person])
	var hud := 8000
	print("frame triangles, town of today + full traffic: %d (+%d HUD allowance)" % [total, hud])
	check(total + hud < TriBudget.BUDGET, "frame stays under %d triangles (%d)" % [TriBudget.BUDGET, total + hud])
	world.queue_free()
