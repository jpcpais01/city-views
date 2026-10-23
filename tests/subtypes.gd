extends Node
## Gallery of every sub-type at every growth stage, in rows along a street, plus
## a per-tile triangle report (CV_OUT saves a screenshot; CV_ROW picks the row).

const ROWS := {
	"homes": [Game.K.HOUSE, 4], "shops": [Game.K.SHOP, 4], "work": [Game.K.OFFICE, 3],
	"parks": [Game.K.PARK, 5], "nature": [Game.K.TREE, 6], "roads": [Game.K.ROAD, 3],
}


func _ready() -> void:
	Game.new_world(1234)
	# keep every tile at the growth stage it is given
	Game.set_process(false)
	Game.coins = 1e6
	for t in Game.TOOLS:
		Game.unlocked[t.id] = true
	var row := OS.get_environment("CV_ROW") if OS.get_environment("CV_ROW") != "" else "homes"
	for z in range(22, 42):
		for x in range(18, 46):
			Game.set_tile(x, z, Game.K.EMPTY, 2, 0)
	var k: int = ROWS.get(row, [Game.K.EMPTY, 0])[0]
	var n: int = ROWS.get(row, [Game.K.EMPTY, 0])[1]
	# columns of sub-types, rows of growth 1..3 with a street in front of each
	for s in n:
		for g in 3:
			var x := 22 + s * 4
			var zz := 26 + g * 4
			for dx in range(-1, 3):
				Game.set_tile(x + dx, zz + 1, Game.K.ROAD, 2, 0)
			for dx in 2:
				var tx := x + dx
				if k == Game.K.ROAD:
					Game.set_tile(tx, zz, Game.K.ROAD, 2, s)
					Game.set_tile(tx, zz - 1, Game.K.ROAD, 2, s)
				else:
					Game.set_tile(tx, zz, k, 2, Game.param_for(k, s, tx, zz))
					Game.growth[Game.idx(tx, zz)] = g + 1 if Game.is_building(k) else 1
	if row == "landmarks":
		# every landmark on its own plot, the pier on the shore of a dug-out bay
		var lms := [Game.LM.FOUNTAIN, Game.LM.BANDSTAND, Game.LM.WINDMILL, Game.LM.LIGHTHOUSE, Game.LM.OBSERVATORY, Game.LM.CLOCKTOWER, Game.LM.FERRIS]
		for z2 in range(22, 42):
			for x2 in range(18, 46):
				Game.set_tile(x2, z2, Game.K.EMPTY, 4 if x2 < 32 else 2, 0)
		for i in lms.size():
			Game.set_tile(22 + i * 3, 30, Game.K.LANDMARK, Game.lvl(22 + i * 3, 30), lms[i])
		for x2 in range(36, 44):
			for z2 in range(33, 38):
				Game.set_tile(x2, z2, Game.K.EMPTY, 0, 0)
		Game.set_tile(40, 33, Game.K.LANDMARK, 0, Game.LM.PIER)
		# a second lighthouse on the bay, so its beam sweeps the water
		Game.set_tile(36, 32, Game.K.LANDMARK, Game.lvl(36, 32), Game.LM.LIGHTHOUSE)
		n = 0
	Game.population = 2000
	var world := World.new()
	add_child(world)
	world.time_of_day = float(OS.get_environment("CV_TIME")) if OS.get_environment("CV_TIME") != "" else 0.4
	await get_tree().process_frame
	while not world._build_queue.is_empty():
		world._process(0.0)
	# per-tile triangle report, from a fresh build of each tile
	for s in n:
		var line := "%s sub %d:" % [row, s]
		for g in 3:
			var node := CityGen.build(22 + s * 4, 26 + g * 4, world.city_mat, world.beam_mat)
			var tris := 0
			for c in node.get_children():
				if c is MeshInstance3D and c.mesh:
					tris += TriBudget.tris(c.mesh)
			node.free()
			line += "  g%d %d" % [g + 1, tris]
		print(line)
	await get_tree().create_timer(1.0).timeout
	var col := int(OS.get_environment("CV_COL")) if OS.get_environment("CV_COL") != "" else -1
	world.rig.focus(Game.tile_center(22 + n * 2, 30) if col < 0 else Game.tile_center(22 + col * 4, 30) + Vector3(1, 0, 0))
	if row == "landmarks":
		world.rig.focus(Game.tile_center(31 + (col if col >= 0 else 0), 31))
	world.rig._t_dist = float(OS.get_environment("CV_DIST")) if OS.get_environment("CV_DIST") != "" else 30.0
	world.rig._t_yaw = float(OS.get_environment("CV_YAW")) if OS.get_environment("CV_YAW") != "" else 0.5
	await get_tree().create_timer(float(OS.get_environment("CV_WAIT")) if OS.get_environment("CV_WAIT") != "" else 4.0).timeout
	if OS.get_environment("CV_OUT") != "":
		get_viewport().get_texture().get_image().save_png(OS.get_environment("CV_OUT"))
	get_tree().quit()
