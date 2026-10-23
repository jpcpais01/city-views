extends Node
## Screenshot of the new tile-free island.
## CV_SEED, CV_TIME, CV_DIST, CV_YAW (degrees), CV_FOCUS=x,z, CV_BRUSH=raise|lower|smooth|flatten
## (holds that brush at the focus for a second), CV_STREETS=1 (lays a few streets), CV_OUT.


func _ready() -> void:
	var island := IslandWorld.new()
	add_child(island)
	var hud := IslandHud.new()
	hud.world = island
	hud.island = island
	add_child(hud)
	if OS.get_environment("CV_SEED") != "":
		island.new_island(int(OS.get_environment("CV_SEED")))
	island.time_of_day = float(OS.get_environment("CV_TIME")) if OS.get_environment("CV_TIME") != "" else 0.4
	var f := Vector3.ZERO
	if OS.get_environment("CV_FOCUS") != "":
		var parts := OS.get_environment("CV_FOCUS").split(",")
		f = Vector3(float(parts[0]), 0, float(parts[1]))
	island.rig.focus(f)
	island.rig._t_dist = float(OS.get_environment("CV_DIST")) if OS.get_environment("CV_DIST") != "" else 70.0
	if OS.get_environment("CV_YAW") != "":
		island.rig._t_yaw = deg_to_rad(float(OS.get_environment("CV_YAW")))
	if OS.get_environment("CV_BRUSH") != "":
		island.set_brush(OS.get_environment("CV_BRUSH"))
		island._ring_at = Vector3(f.x, island.land.height_at(f.x, f.z), f.z)
		island._stroke_level = island.land.height_at(f.x, f.z)
		island._stroke = true
		await get_tree().create_timer(1.2).timeout
		island._stroke = false
	if OS.get_environment("CV_STREETS") != "":
		# a gently curving main street, one crossing it and one ending on it
		var lines := [[], [], []]
		for k in 41:
			var t := k / 40.0
			lines[0].append(Vector2(f.x - 20.0 + 40.0 * t, f.z + sin(t * PI * 1.3) * 4.0))
			lines[1].append(Vector2(f.x + 2.0 + sin(t * 2.0) * 2.0, f.z - 16.0 + 32.0 * t))
			lines[2].append(Vector2(f.x - 12.0 + 3.0 * t, f.z + 3.0 + 13.0 * t))
		for l in lines:
			island.streets.add_stroke(PackedVector2Array(l))
		print("streets: ", island.streets.streets.size())
	await get_tree().create_timer(float(OS.get_environment("CV_WAIT")) if OS.get_environment("CV_WAIT") != "" else 3.0).timeout
	print("prims: ", Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var img := get_viewport().get_texture().get_image()
	img.save_png(OS.get_environment("CV_OUT") if OS.get_environment("CV_OUT") != "" else "/tmp/island.png")
	get_tree().quit()
