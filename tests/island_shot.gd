extends Node
## Screenshot of the island.
## CV_SEED, CV_TIME, CV_DIST, CV_YAW (degrees), CV_FOCUS=x,z, CV_LOOK=x,z (camera, after growing), CV_BRUSH=raise|lower|smooth|flatten
## (holds that brush at the focus for a second), CV_STREETS=1 (lays a few streets; 2: one long one), CV_GROW=radius (paints and grows the town),
## CV_MARK=kind (looks at that landmark once it stands), CV_PHOTO=1 (photo mode), CV_MENU=page (opens the menu on that page: island, coop, account, settings, notes), CV_OUT.


func _ready() -> void:
	var island := IslandWorld.new()
	add_child(island)
	var hud := Hud.new()
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
		if OS.get_environment("CV_STREETS") == "2":
			# just one long main street
			lines = [[]]
			for k in 41:
				lines[0].append(Vector2(f.x - 24.0 + 48.0 * k / 40.0, f.z + sin(k / 40.0 * PI) * 3.0))
		for l in lines:
			island.streets.add_stroke(PackedVector2Array(l))
		print("streets: ", island.streets.streets.size())
	if OS.get_environment("CV_GROW") != "":
		var r := float(OS.get_environment("CV_GROW"))
		island.land.paint_zone(Vector3(f.x, 0, f.z), r, 1.0)
		island.land.paint_zone(Vector3(f.x, 0, f.z), r * 0.8, 1.0)
		if OS.get_environment("CV_GREEN") != "":
			# a park painted at x,z,radius
			var g := OS.get_environment("CV_GREEN").split(",")
			island.land.paint_green(Vector3(float(g[0]), 0, float(g[1])), float(g[2]), 1.0)
		island.growth.focus = Vector2(f.x, f.z)
		var t0 := Time.get_ticks_msec()
		var made := island.growth.grow_all()
		print("grew %d streets in %d ms" % [made, Time.get_ticks_msec() - t0])
		island.streets.flush()
		t0 = Time.get_ticks_msec()
		island.town.fill_all()
		island.town.evolve_all()
		print("built %d houses in %d ms" % [island.town.house_count(), Time.get_ticks_msec() - t0])
		var kits := {}
		for l: Town.Lot in island.town.lots.values():
			kits[HouseGen.KIT_NAMES[l.kit]] = kits.get(HouseGen.KIT_NAMES[l.kit], 0) + 1
			if l.type != "house":
				print("  %s at %.1f,%.1f" % [l.type, l.origin.x, l.origin.y])
		print("kits: ", kits)
	if OS.get_environment("CV_LOOK") != "":
		# look somewhere else than where the town was grown from
		var parts := OS.get_environment("CV_LOOK").split(",")
		island.rig.focus(Vector3(float(parts[0]), 0, float(parts[1])))
	if OS.get_environment("CV_LIVE") != "":
		# paint and let the town grow in real time, watching the slowest frame
		var r := float(OS.get_environment("CV_LIVE"))
		island.land.paint_zone(Vector3(f.x, 0, f.z), r, 2.0)
		island.growth.wake(Vector2(f.x, f.z))
		await get_tree().process_frame
		var worst := 0
		var slow := 0
		var frames := 0
		var last := Time.get_ticks_usec()
		var t_end := Time.get_ticks_msec() + 20000
		while Time.get_ticks_msec() < t_end and (island.growth.is_growing() or not island.town._todo.is_empty() or not island.town._job.is_empty()):
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			worst = maxi(worst, now - last)
			if now - last > 16000:
				slow += 1
			frames += 1
			last = now
		print("live: %d streets, %d houses, slowest frame %d ms, %d of %d frames over 16 ms" % [island.streets.streets.size(), island.town.house_count(), worst / 1000, slow, frames])
	if OS.get_environment("CV_PHOTO") != "":
		hud.set_photo(true)
	if OS.get_environment("CV_MENU") != "":
		hud._page = OS.get_environment("CV_MENU")
		hud._set_menu(true)
	await get_tree().create_timer(float(OS.get_environment("CV_WAIT")) if OS.get_environment("CV_WAIT") != "" else 3.0).timeout
	print("prims: ", Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	print("landmarks: ", island.landmarks.spots)
	if island.landmarks.spots.has(OS.get_environment("CV_MARK")):
		# then look at that landmark (a pier from out near its end)
		var m: Vector2 = island.landmarks.spots[OS.get_environment("CV_MARK")]
		if OS.get_environment("CV_MARK") == "pier":
			m += island.landmarks._seaward(m) * Landmarks.PIER_LEN
		island.rig.focus(Vector3(m.x, 0, m.y))
		await get_tree().create_timer(1.5).timeout
	if OS.get_environment("CV_PARTS") != "":
		# what each part of the island costs: hide it and see what drops
		var total := Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		for part in [island.town, island.streets, island.land]:
			part.visible = false
			await get_tree().process_frame
			await get_tree().process_frame
			print("  %s: %d" % [part.get_class() if part.get_script() == null else part.get_script().get_global_name(), total - Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)])
			part.visible = true
			await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(OS.get_environment("CV_OUT") if OS.get_environment("CV_OUT") != "" else "/tmp/island.png")
	get_tree().quit()
