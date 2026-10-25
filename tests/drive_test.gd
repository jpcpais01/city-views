extends Node
## Drive mode checks: the car rides the streets, stops at buildings and water,
## the cameras hand over and back, and street-level views keep to the
## triangle budget. CV_OUT=path.png (not headless) saves a chase-camera shot,
## CV_FP=1 the driver's view instead; CV_TIME sets the time of day.

var _fails := 0


func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails += 1


func _ready() -> void:
	var island := IslandWorld.new()
	add_child(island)
	var hud := Hud.new()
	hud.island = island
	add_child(hud)
	island.new_island(9)
	island.time_of_day = float(OS.get_environment("CV_TIME")) if OS.get_environment("CV_TIME") != "" else 0.42
	await get_tree().process_frame
	# no streets yet: no drive
	island.streets.clear()
	hud.drive.set_active(true)
	check(not hud.drive.active, "with no streets the car stays in the garage")
	# a long main street with a town grown along it, and a cross street
	var a := PackedVector2Array()
	var b := PackedVector2Array()
	for k in 81:
		a.append(Vector2(-40.0 + k, 2.0 + sin(k * 0.05) * 3.0))
	for k in 41:
		b.append(Vector2(6.0, -20.0 + k))
	island.streets.add_stroke(a)
	island.streets.add_stroke(b)
	island.streets.flush()
	island.land.paint_zone(Vector3(0, 0, 2), 40.0, 2.0)
	island.land.paint_level(Vector3(0, 0, 2), 22.0, 5.0, 2.0)
	island.growth.focus = Vector2.ZERO
	island.growth.grow_all()
	island.streets.flush()
	island.town.fill_all()
	island.town.evolve_all()
	while not island.land.is_settled():
		island.land.rebuild_dirty(1 << 20)
	island.land.rebuild_shadow()
	await get_tree().process_frame
	island.rig.focus(Vector3(-20, 0, 2))
	island.rig.target = Vector3(-20, 0, 2)
	island.rig.yaw = -PI * 0.5
	var fov := island.rig.cam.fov
	hud.drive.set_active(true)
	var car := hud.drive.car
	# the car on its own first; the crowd comes later
	hud.drive.crowd.stop()
	check(hud.drive.active and car != null, "the car comes out onto a street")
	check(not hud._root.get_child(0).visible or hud._drive_hidden.size() > 0, "the building HUD steps aside (%d hidden)" % hud._drive_hidden.size())
	check(not island.rig.is_processing(), "the orbit camera hands over")
	var s0: Streets.Street = island.streets.streets[0]
	var c := Vector3(INF, 0, 0)
	for st: Streets.Street in island.streets.streets:
		var cs := st.closest(Vector2(car.position.x, car.position.z))
		if cs.x < c.x:
			c = cs
			s0 = st
	check(c.x < s0.w(), "it starts on the carriageway (%.2f from the middle)" % c.x)
	check(absf(car.position.y - (c.y + 0.03)) < 0.03, "standing on the road surface (%.3f vs %.3f)" % [car.position.y, c.y + 0.03])
	# drive along: full throttle for three seconds
	car.input_throttle = 1.0
	var off_road := 0.0
	var max_gap := 0.0
	for i in 180:
		car.drive(1.0 / 60.0)
		hud.drive._update_camera(1.0 / 60.0)
		var p := Vector2(car.position.x, car.position.z)
		var cc := s0.closest(p)
		off_road = maxf(off_road, cc.x)
		if cc.x < s0.w():
			max_gap = maxf(max_gap, absf(car.position.y - (cc.y + 0.03)))
	check(car.speed > 2.5, "it gets up to speed (%.1f m/s, %d km/h)" % [car.speed, car.kmh()])
	check(car.on_road and max_gap < 0.05, "and rides the road surface (worst %.3f)" % max_gap)
	# braking holds it, then backs it up
	car.input_throttle = -1.0
	for i in 120:
		car.drive(1.0 / 60.0)
	check(car.speed < 0.0, "the brake stops it and then backs up (%.2f)" % car.speed)
	# steering turns it the way asked: right is clockwise seen from above
	car.place(Vector2(-30, 2), PI * 0.5)
	car.input_throttle = 1.0
	car.input_steer = 1.0
	for i in 40:
		car.drive(1.0 / 60.0)
	check(car.heading < PI * 0.5 - 0.1, "steering right turns it right (%.2f)" % car.heading)
	car.input_steer = 0.0
	# buildings stop it: drive straight at the biggest building there is
	var lot: Town.Lot = null
	for l: Town.Lot in island.town.lots.values():
		if l.host == 0 and not l.arrays.is_empty() and l.type == "house" and l.foot.has_area() and (lot == null or l.floors > lot.floors):
			lot = l
	check(lot != null, "the town has buildings to bump into")
	if lot:
		var inside := lot.origin + Vector2(sin(lot.yaw), cos(lot.yaw)).orthogonal() * 0.0
		var centre_local := lot.foot.get_center()
		var to_world := func(v: Vector2) -> Vector2:
			return lot.origin + Vector2(cos(lot.yaw), -sin(lot.yaw)) * v.x + Vector2(sin(lot.yaw), cos(lot.yaw)) * v.y
		inside = to_world.call(centre_local)
		check(car.blocked(inside), "the middle of a building is solid")
		# from the street in front of it, nose towards it
		var front: Vector2 = to_world.call(Vector2(centre_local.x, 0.9))
		var dir := (inside - front).normalized()
		car.place(front, atan2(dir.x, dir.y))
		car.input_throttle = 1.0
		var got_in := false
		for i in 240:
			car.drive(1.0 / 60.0)
			if car.blocked(Vector2(car.position.x, car.position.z)):
				got_in = true
		check(not got_in and Vector2(car.position.x, car.position.z).distance_to(inside) > 0.2, "and the car stops at its wall (%.2f m from the middle)" % Vector2(car.position.x, car.position.z).distance_to(inside))
	# the river is no road: open water is blocked, a bridge is not
	var wet := Vector2.INF
	for k in 4000:
		var q := Vector2(randf_range(-150, 150), randf_range(-150, 150))
		if island.land.height_at(q.x, q.y) < -0.3:
			wet = q
			break
	if wet != Vector2.INF:
		check(car.blocked(wet), "open water stops the car")
	# the busy streets round the car: lots of cars and walkers, keeping to the streets
	var crowd := hud.drive.crowd
	car.place_on_street(Vector2(-5, 2), PI * 0.5)
	crowd.start()
	check(crowd.car_count() > 30 and crowd.ped_count() > 60, "the streets round the car fill up (%d cars, %d walkers)" % [crowd.car_count(), crowd.ped_count()])
	check(not island.cars.visible and not island.folk.visible, "the everyday traffic and walkers make way meanwhile")
	var t0 := Time.get_ticks_usec()
	var starts := []
	for p in crowd._peds:
		starts.append([p, p.xf.origin])
	for i in 120:
		crowd._process(1.0 / 60.0)
	var per_frame := (Time.get_ticks_usec() - t0) / 120.0
	if OS.get_environment("CV_PROF") != "":
		var g := island.streets.links()
		var t1 := Time.get_ticks_usec()
		for i in 60:
			crowd._queue()
		var t2 := Time.get_ticks_usec()
		for i in 60:
			for nc in crowd._cars:
				crowd._drive(nc, g, 1.0 / 60.0, false)
		var t3 := Time.get_ticks_usec()
		for i in 60:
			for p in crowd._peds:
				crowd._walk(p, g, 1.0 / 60.0, false)
		var t4 := Time.get_ticks_usec()
		for i in 60:
			crowd._draw()
		var t5 := Time.get_ticks_usec()
		for i in 60:
			crowd._find_spots()
		var t6 := Time.get_ticks_usec()
		print("prof ms: queue %.2f drive %.2f walk %.2f draw %.2f spots %.2f" % [(t2 - t1) / 60000.0, (t3 - t2) / 60000.0, (t4 - t3) / 60000.0, (t5 - t4) / 60000.0, (t6 - t5) / 60000.0])
	var worst_off := 0.0
	for nc in crowd._cars:
		var o: Vector3 = nc.xf.origin
		var best := INF
		for st: Streets.Street in island.streets.streets:
			if st.near_box(Vector2(o.x, o.z), 3.0):
				best = minf(best, st.closest(Vector2(o.x, o.z)).x - st.w())
		worst_off = maxf(worst_off, best)
	var moved := 0
	for e in starts:
		if crowd._peds.has(e[0]) and (e[0].xf.origin as Vector3).distance_to(e[1]) > 0.1:
			moved += 1
	check(worst_off < 0.15, "crowd cars keep to the carriageway (%.2f past the kerb at worst)" % worst_off)
	check(moved > crowd.ped_count() / 3, "and the walkers walk (%d of %d moved)" % [moved, crowd.ped_count()])
	print("drive: crowd of %d cars and %d walkers costs %.2f ms a frame here" % [crowd.car_count(), crowd.ped_count(), per_frame / 1000.0])
	if not crowd._cars.is_empty():
		var o: Vector3 = crowd._cars[0].xf.origin
		check(crowd.hits(Vector2(o.x, o.z)), "the player's car bumps into crowd cars")
	# every view, and the street-level triangle budget with the crowd about
	var worst := 0
	var worst_acc := {}
	for v in DriveMode.VIEWS.size():
		hud.drive.set_view(v)
		for spot in [Vector2(-30, 2), Vector2(-5, 2), Vector2(15, 4), Vector2(6, -12), Vector2(6, 14)]:
			car.place_on_street(spot, 0.0)
			crowd.start()
			for yaw_deg in [0, 60, 120, 180, 240, 300]:
				car.place_on_street(spot, deg_to_rad(yaw_deg))
				hud.drive._cam_fresh = true
				hud.drive._update_camera(1.0)
				var cam := island.rig.cam
				var eye := cam.global_position
				var at := eye - cam.global_transform.basis.z * 10.0
				var acc := TriBudget.count_view(island, eye, at, 78.0)
				var t := TriBudget.total(acc)
				if t > worst:
					worst = t
					worst_acc = acc
	for k in worst_acc:
		print("  drive tris %-16s %7d +shadow %7d" % [k, worst_acc[k][0], worst_acc[k][1]])
	var reserve := 8000 + 16000
	print("drive: %d houses, %d triangles in the busiest street-level view" % [island.town.house_count(), worst])
	check(worst + reserve < TriBudget.SIDE_BUDGET, "street-level views stay under %dk (%d)" % [TriBudget.SIDE_BUDGET / 1000, worst + reserve])
	if OS.get_environment("CV_OUT") != "":
		hud.drive.set_view(0 if OS.get_environment("CV_FP") != "" else int(OS.get_environment("CV_VIEW")) if OS.get_environment("CV_VIEW") != "" else 2)
		if OS.get_environment("CV_ORBIT") != "":
			hud.drive._orbit = deg_to_rad(float(OS.get_environment("CV_ORBIT")))
			hud.drive._touched = -100.0
		car.place_on_street(Vector2(-12, 2), PI * 0.5)
		crowd._rng.seed = 42
		crowd.start()
		# (the mode reads the pad every frame)
		hud.drive._pad.throttle = 0.6
		hud.drive._cam_fresh = true
		for i in 90:
			await get_tree().process_frame
		print("shot: car at %s, %.2f m/s" % [car.position, car.speed])
		hud.drive._pad.throttle = 0.0
		if OS.get_environment("CV_PAD") != "":
			var pad := hud.drive._pad
			pad.visible = true
			pad._fingers = {0: "steer", 1: "gas"}
			pad._steer_from = pad._wheel_home()
			pad._steer_at = pad._wheel_home() + Vector2(40, 0)
			pad._update()
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_environment("CV_OUT"))
		print("frame tris: %d" % Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	hud.drive.set_active(false)
	check(island.rig.is_processing() and is_equal_approx(island.rig.cam.fov, fov), "getting out gives the orbit camera back")
	check(not hud.drive._ui.visible and hud._drive_hidden.is_empty(), "and the building HUD returns")
	check(island.cars.visible and crowd.car_count() == 0, "and the everyday traffic comes back")
	print("DRIVE TESTS: %s (%d failed)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(1 if _fails > 0 else 0)
