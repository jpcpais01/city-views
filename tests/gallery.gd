extends Node
## Renders one of every tile type side by side (visual check).

func _ready() -> void:
	Game.new_world(1234)
	for z in range(26, 36):
		for x in range(22, 40):
			Game.set_tile(x, z, Game.K.EMPTY, 2, 0)
	var items := [[Game.K.TREE, 1], [Game.K.TREE, 2], [Game.K.PARK, 0], [Game.K.HOUSE, 1], [Game.K.HOUSE, 2], [Game.K.HOUSE, 3], [Game.K.SHOP, 1], [Game.K.SHOP, 2], [Game.K.OFFICE, 1], [Game.K.OFFICE, 2]]
	for i in items.size():
		var x := 24 + i
		Game.set_tile(x, 30, Game.K.ROAD, 2, 0)
		Game.set_tile(x, 29, items[i][0], 2, 5 + i)
		Game.growth[Game.idx(x, 29)] = items[i][1] if Game.is_building(items[i][0]) else 1
	Game.set_tile(26, 31, Game.K.LANDMARK, 2, Game.LM.FOUNTAIN)
	Game.set_tile(28, 31, Game.K.LANDMARK, 2, Game.LM.CLOCKTOWER)
	Game.set_tile(30, 31, Game.K.LANDMARK, 2, Game.LM.WINDMILL)
	Game.set_tile(32, 31, Game.K.LANDMARK, 2, Game.LM.FERRIS)
	Game.set_tile(34, 31, Game.K.LANDMARK, 2, Game.LM.LIGHTHOUSE)
	Game.population = 50
	var world := World.new()
	add_child(world)
	world.time_of_day = float(OS.get_environment("CV_TIME")) if OS.get_environment("CV_TIME") != "" else 0.4
	await get_tree().create_timer(0.5).timeout
	world.rig.focus(Game.tile_center(29, 30))
	world.rig._t_dist = float(OS.get_environment("CV_DIST")) if OS.get_environment("CV_DIST") != "" else 16.0
	world.rig._t_yaw = float(OS.get_environment("CV_YAW")) if OS.get_environment("CV_YAW") != "" else 0.0
	await get_tree().create_timer(4.0).timeout
	get_viewport().get_texture().get_image().save_png(OS.get_environment("CV_OUT"))
	get_tree().quit()
