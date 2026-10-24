extends Node
## Screenshot of the island.
## CV_SEED, CV_TIME, CV_DIST, CV_YAW (degrees), CV_FOCUS=x,z, CV_LOOK=x,z (camera, after growing), CV_BRUSH=raise|lower|smooth|flatten
## (holds that brush at the focus for a second), CV_STREETS=1 (lays a few streets; 2: one long one; 3: two 24 m apart), CV_GROW=radius (paints and grows the town),
## CV_LEVEL=1..4 (Grow level for CV_GROW), CV_TOP=metres (straight down, no HUD), CV_MARK=kind (looks at that landmark once it stands), CV_HOLD=brush (holds it, e.g. grow shows the painted districts), CV_PHOTO=1 (photo mode, hyper graphics unless CV_NOHYPER=1), CV_SPARKLE=1 (Magic sparkles over a few houses mid-view), CV_TAP=x,y (taps the screen there, as if asking what stands there), CV_MENU=page (opens the menu on that page: island, coop, account, settings, notes), CV_OUT.


func _ready() -> void:
	var island := IslandWorld.new()
	add_child(island)
	var hud := Hud.new()
	hud.island = island
	add_child(hud)
	if OS.get_environment("CV_SEED") != "":
		island.new_island(int(OS.get_environment("CV_SEED")), OS.get_environment("CV_MAP") if OS.get_environment("CV_MAP") != "" else "river")
	island.time_of_day = float(OS.get_environment("CV_TIME")) if OS.get_environment("CV_TIME") != "" else 0.4
	var f := Vector3.ZERO
	if OS.get_environment("CV_FOCUS") != "":
		var parts := OS.get_environment("CV_FOCUS").split(",")
		f = Vector3(float(parts[0]), 0, float(parts[1]))
	island.rig.focus(f)
	island.rig._t_dist = float(OS.get_environment("CV_DIST")) if OS.get_environment("CV_DIST") != "" else 70.0
	if OS.get_environment("CV_TILT") != "":
		island.rig._t_tilt = deg_to_rad(float(OS.get_environment("CV_TILT")))
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
		if OS.get_environment("CV_STREETS") == "fuzz":
			# the hand-drawn tangle the logic test checks junctions on
			lines = []
			var rng := RandomNumberGenerator.new()
			rng.seed = 77
			for n in 22:
				var a := Vector2(rng.randf_range(-30, 30), rng.randf_range(-30, 30))
				var heading := rng.randf() * TAU
				var line := []
				for k in 30:
					line.append(a)
					heading += rng.randf_range(-0.35, 0.35)
					a += Vector2.from_angle(heading) * 1.0
				lines.append(line)
			lines.append([Vector2(-20, 34), Vector2(20, 34)])
			lines.append([Vector2(-20, 30), Vector2(0, 33.6)])
			lines.append([Vector2(-5, 32), Vector2(20, 36)])
		if OS.get_environment("CV_STREETS") == "3":
			# two long streets 24 m apart, a deep block between
			lines = [[], []]
			for k in 41:
				lines[0].append(Vector2(f.x - 24.0 + 48.0 * k / 40.0, f.z - 12.0))
				lines[1].append(Vector2(f.x - 24.0 + 48.0 * k / 40.0, f.z + 12.0 + sin(k / 40.0 * PI) * 2.0))
		# CV_ROADS: kinds for the first lines, e.g. "avenue,highway"
		var kinds := OS.get_environment("CV_ROADS").split(",", false)
		for li in lines.size():
			island.streets.add_stroke(PackedVector2Array(lines[li]), kinds[li] if li < kinds.size() else "main")
		print("streets: ", island.streets.streets.size())
	if OS.get_environment("CV_GROW") != "":
		var r := float(OS.get_environment("CV_GROW"))
		island.land.paint_zone(Vector3(f.x, 0, f.z), r, 1.0)
		island.land.paint_zone(Vector3(f.x, 0, f.z), r * 0.8, 1.0)
		if OS.get_environment("CV_LEVEL") != "":
			# the Grow level painted over the town (1 village .. 6 skyline)
			island.land.paint_level(Vector3(f.x, 0, f.z), r, float(OS.get_environment("CV_LEVEL")), 2.0)
		if OS.get_environment("CV_RINGS") != "":
			# a city: rings of Grow levels rising to the middle (CV_RINGS = the top level)
			var top := int(OS.get_environment("CV_RINGS"))
			for k in 4:
				island.land.paint_level(Vector3(f.x, 0, f.z), r * (1.0 - k * 0.22), float(top - 3 + k), 2.0)
		if OS.get_environment("CV_DISTRICTS") != "":
			# an industrial quarter to one side and an office quarter to the other
			print("districts around ", f)
			# CV_DLEVEL raises the offices and shops (and the homes between them) to that level
			var top := float(OS.get_environment("CV_DLEVEL")) if OS.get_environment("CV_DLEVEL") != "" else 0.0
			if top > 0.0:
				island.land.paint_level(Vector3(f.x, 0, f.z), r, top, 9.0, HouseGen.HOMES)
			island.land.paint_level(Vector3(f.x - r * 0.6, 0, f.z), r * 0.4, 4.0, 9.0, HouseGen.INDUSTRY)
			island.land.paint_level(Vector3(f.x + r * 0.6, 0, f.z), r * 0.4, maxf(5.0, top), 9.0, HouseGen.OFFICES)
			island.land.paint_level(Vector3(f.x, 0, f.z + r * 0.6), r * 0.35, maxf(3.0, top), 9.0, HouseGen.SHOPS)
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
		island._update_maps(false)
		print("built %d houses in %d ms" % [island.town.house_count(), Time.get_ticks_msec() - t0])
		var kits := {}
		for l: Town.Lot in island.town.lots.values():
			kits[HouseGen.KIT_NAMES[l.kit]] = kits.get(HouseGen.KIT_NAMES[l.kit], 0) + 1
			if l.type != "house":
				print("  %s at %.1f,%.1f" % [l.type, l.origin.x, l.origin.y])
		print("kits: ", kits)
	if OS.get_environment("CV_QUAY") != "":
		# a street along the river bank, just clear of the water, then grown
		var rv: PackedVector2Array = island.land._river
		var best := 0
		for k in rv.size():
			if rv[k].distance_to(Vector2(f.x, f.z)) < rv[best].distance_to(Vector2(f.x, f.z)):
				best = k
		var pts := PackedVector2Array()
		for k in range(best - 6, best + 7):
			var t := (rv[k + 1] - rv[k - 1]).normalized()
			pts.append(rv[k] + Vector2(-t.y, t.x) * (island.land._river_w[k] + float(OS.get_environment("CV_QUAY"))))
		island.streets.add_stroke(pts, "main")
		island.streets.flush()
		island.land.paint_zone(Vector3(pts[6].x, 0, pts[6].y), 30.0, 1.0)
		island.land.paint_level(Vector3(pts[6].x, 0, pts[6].y), 30.0, 4.0, 2.0)
		island.growth.focus = pts[6]
		island.growth.grow_all(20)
		island.streets.flush()
		island.town.fill_all()
		island.town.evolve_all()
		island.rig.focus(Vector3(pts[6].x, 0, pts[6].y))
	if OS.get_environment("CV_BRIDGES") != "":
		# streets of each kind across the river (or the estuary), CV_BRIDGES
		# metres along it from the point nearest the focus, then a look at them
		var rv: PackedVector2Array = island.land._river
		var mid := 0
		for k in rv.size():
			if rv[k].distance_to(Vector2(f.x, f.z)) < rv[mid].distance_to(Vector2(f.x, f.z)):
				mid = k
		var gap := int(float(OS.get_environment("CV_BRIDGES")) / 6.0)
		BridgeGen.force = OS.get_environment("CV_BSTYLE")
		var kinds := ["main", "avenue", "highway", "side"]
		for q in kinds.size():
			var k: int = mid + (q - 1) * gap
			var t := (rv[k + 1] - rv[k - 1]).normalized()
			var across := Vector2(-t.y, t.x)
			var half: float = island.land._river_w[k] * 2.2 + 10.0
			var pts := PackedVector2Array()
			for j in 41:
				pts.append(rv[k] + across * lerpf(-half, half, j / 40.0))
			var st := island.streets.add_stroke(pts, kinds[q])
			print("%s bridge: %s" % [kinds[q], str(st.spans) if st else "none"])
		island.streets.flush()
		island.rig.focus(Vector3(rv[mid].x, 0, rv[mid].y))
	if OS.get_environment("CV_STOP") != "":
		# look at the first bus stop
		for st: Streets.Street in island.streets.streets:
			if not st.stops.is_empty():
				var p := island.streets._ptf(st, st.stops[0].x)
				print("bus stop at ", p, " of ", st.stops.size(), " on ", st.kind)
				island.rig.focus(Vector3(p.x, 0, p.y))
				break
	if OS.get_environment("CV_BRIDGE") != "":
		# look at the first bridge
		for st: Streets.Street in island.streets.streets:
			if not st.spans.is_empty():
				var mid := st.pts[int((st.spans[0].x + st.spans[0].y) * 0.5)]
				print("bridge at ", mid)
				island.rig.focus(Vector3(mid.x, 0, mid.y))
				break
	if OS.get_environment("CV_SHIP") != "":
		# a ship of that kind halfway along its run, for a look at it
		island.ships.spawn(int(OS.get_environment("CV_SHIP")), true)
		var sh: Dictionary = island.ships._ships[-1]
		var sp: Vector2 = sh.a + sh.dir * sh.d
		island.rig.focus(Vector3(sp.x, 0, sp.y))
	if OS.get_environment("CV_BOAT") != "":
		# a close look at the first boat of that kind (0 sailing, 1 fishing)
		for b in island.wildlife._boats:
			if b.kind == int(OS.get_environment("CV_BOAT")):
				island.rig.focus(b.p)
				break
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
	if OS.get_environment("CV_STATS") != "":
		# the city stats panel open
		island.progress.recount(true)
		hud._toggle_stats()
	if OS.get_environment("CV_TOP") != "":
		# straight down at the camera's focus, CV_TOP metres across, no HUD
		hud.visible = false
		hud.set_photo(true)
		var cam := Camera3D.new()
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = float(OS.get_environment("CV_TOP"))
		var at: Vector3 = island.rig._t_target
		if OS.get_environment("CV_LOOK") != "":
			var parts := OS.get_environment("CV_LOOK").split(",")
			at = Vector3(float(parts[0]), 0, float(parts[1]))
		cam.far = 400.0
		add_child(cam)
		cam.look_at_from_position(at + Vector3(0, island.land.height_at(at.x, at.z) + 12.0, 0.01), at, Vector3.FORWARD)
		cam.make_current()
	if OS.get_environment("CV_PLANE") != "":
		# an airliner held in view, part way between the camera and its focus
		await get_tree().create_timer(1.0).timeout
		island.planes.spawn(true)
		island.planes.set_process(false)
		var cam := island.rig.cam
		island.planes._plane.position = island.rig._t_target.lerp(cam.global_position, 0.45) + Vector3(4, 4, 0)
	if OS.get_environment("CV_HOLD") != "":
		# hold a brush (no stroke), as when it is picked from the bar
		island.set_brush(OS.get_environment("CV_HOLD"))
	if OS.get_environment("CV_PHOTO") != "":
		Game.settings["hyper"] = OS.get_environment("CV_NOHYPER") == ""
		hud.set_photo(true)
	if OS.get_environment("CV_MENU") != "":
		hud._page = OS.get_environment("CV_MENU")
		hud._set_menu(true)
	await get_tree().create_timer(float(OS.get_environment("CV_WAIT")) if OS.get_environment("CV_WAIT") != "" else 3.0).timeout
	if OS.get_environment("CV_SPARKLE") != "":
		var mid: Vector3 = island.rig._t_target
		var n := 0
		for l: Town.Lot in island.town.lots.values():
			if l.type == "house" and l.host == 0 and l.origin.distance_to(Vector2(mid.x, mid.z)) < 25.0 and n < 8:
				island._sparkle(Vector3(l.origin.x, l.street_y, l.origin.y), Vector3(maxf(l.width, 3.0), HouseGen.FH * maxf(l.floors, 1) + 1.0, maxf(l.depth, 3.0)))
				n += 1
		await get_tree().create_timer(0.45).timeout
	if OS.get_environment("CV_TAP") != "":
		var xy := OS.get_environment("CV_TAP").split(",")
		island._tap(Vector2(float(xy[0]), float(xy[1])))
		await get_tree().create_timer(0.4).timeout
	print("prims: ", Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	if OS.get_environment("CV_EST") != "":
		var cam := island.rig.cam
		var acc := TriBudget.count_view(island, cam.global_position, cam.global_position - cam.global_basis.z * 10.0)
		for k in acc:
			print("  est %-16s %7d +shadow %7d" % [k, acc[k][0], acc[k][1]])
		print("estimate: ", TriBudget.total(acc))
	print("landmarks: ", island.landmarks.spots)
	if island.landmarks.spots.has(OS.get_environment("CV_MARK")):
		# then look at that landmark (a pier from out near its end)
		var m: Vector2 = island.landmarks.spots[OS.get_environment("CV_MARK")]
		if OS.get_environment("CV_MARK") == "pier":
			m += island.landmarks._seaward(m) * Landmarks.PIER_LEN
		island.rig.focus(Vector3(m.x, 0, m.y))
		await get_tree().create_timer(1.5).timeout
	if OS.get_environment("CV_TRADE") != "":
		# then look at a shop of that trade (or a lot of that type) from across its street
		for l: Town.Lot in island.town.lots.values():
			if l.trade == OS.get_environment("CV_TRADE") or l.type == OS.get_environment("CV_TRADE"):
				print("trade at ", l.origin)
				island.rig.focus(Vector3(l.origin.x, 0, l.origin.y))
				island.rig._t_yaw = l.yaw + (PI if OS.get_environment("CV_FLIP") != "" else 0.0)
				break
		await get_tree().create_timer(2.0).timeout
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
