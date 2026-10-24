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
	if OS.get_environment("CV_ONLY") == "budget":
		# just the triangle budget (with CV_BUDGET_R / CV_BUDGET_LEVEL)
		await _island_budget()
		print("FAILURES: %d" % failures)
		get_tree().quit(1 if failures > 0 else 0)
		return
	if OS.get_environment("CV_ONLY") == "districts":
		await _districts()
		print("FAILURES: %d" % failures)
		get_tree().quit(1 if failures > 0 else 0)
		return
	if OS.get_environment("CV_ONLY") == "farm":
		await _farmland()
		print("FAILURES: %d" % failures)
		get_tree().quit(1 if failures > 0 else 0)
		return
	if OS.get_environment("CV_ONLY") == "live":
		await _live_matches_full()
		print("FAILURES: %d" % failures)
		get_tree().quit(1 if failures > 0 else 0)
		return
	if OS.get_environment("CV_ONLY") == "undo":
		await _island_undo()
		print("FAILURES: %d" % failures)
		get_tree().quit(1 if failures > 0 else 0)
		return
	if OS.get_environment("CV_ONLY") == "updates":
		await _update_check()
		print("FAILURES: %d" % failures)
		get_tree().quit(1 if failures > 0 else 0)
		return
	if OS.get_environment("CV_ONLY") == "bridges":
		await _bridges()
		print("FAILURES: %d" % failures)
		get_tree().quit(1 if failures > 0 else 0)
		return
	if OS.get_environment("CV_ONLY") == "charts":
		await preload("res://tests/charts_check.gd").run(self)
		print("FAILURES: %d" % failures)
		get_tree().quit(1 if failures > 0 else 0)
		return
	if OS.get_environment("CV_ONLY") == "advisor":
		await preload("res://tests/advisor_check.gd").run(self)
		print("FAILURES: %d" % failures)
		get_tree().quit(1 if failures > 0 else 0)
		return
	if OS.get_environment("CV_ONLY") == "roads":
		await _road_kinds()
		print("FAILURES: %d" % failures)
		get_tree().quit(1 if failures > 0 else 0)
		return
	_streets()
	await _update_check()
	_street_snap()
	await _live_matches_full()
	await _junction_fuzz()
	await _island_budget()
	await _island_undo()
	await _island_coop()
	await _island_grow()
	await _island_levels()
	await _island_skyline()
	await _districts()
	await _farmland()
	await _road_kinds()
	await _bridges()
	await _island_inner()
	await _island_wilds()
	await _island_progress()
	await preload("res://tests/advisor_check.gd").run(self)
	await preload("res://tests/charts_check.gd").run(self)
	await _legacy_save()
	await _map_kinds()
	print("FAILURES: %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)


## Hand-drawn streets meeting at every angle, shallow ones included: every
## junction stays a compact piece of road round where they meet, and every
## joined building stands on a clean outline.
func _junction_fuzz() -> void:
	var island := IslandWorld.new()
	add_child(island)
	island.new_island(5)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for n in 22:
		var a := Vector2(rng.randf_range(-30, 30), rng.randf_range(-30, 30))
		var heading := rng.randf() * TAU
		var pts := PackedVector2Array()
		for k in 30:
			pts.append(a)
			heading += rng.randf_range(-0.35, 0.35)
			a += Vector2.from_angle(heading) * 1.0
		island.streets.add_stroke(pts)
	# a street joining another at a shallow angle, and one crossing almost along it
	island.streets.add_stroke(PackedVector2Array([Vector2(-20, 34), Vector2(20, 34)]))
	island.streets.add_stroke(PackedVector2Array([Vector2(-20, 30), Vector2(0, 33.6)]))
	island.streets.add_stroke(PackedVector2Array([Vector2(-5, 32), Vector2(20, 36)]))
	island.streets.flush()
	var worst := 0.0
	var where := Vector2.ZERO
	for jn in island.streets.junctions():
		for p: Vector3 in jn.edge:
			var d: float = Vector2(p.x, p.z).distance_to(jn.at)
			if d > worst:
				worst = d
				where = jn.at
	check(worst < 4.5, "junctions stay compact, whatever the angle (%.1f m at %s)" % [worst, where])
	island.land.paint_zone(Vector3.ZERO, 40.0, 2.0)
	island.land.paint_level(Vector3.ZERO, 40.0, 4.0, 2.0)
	island.town.fill_all()
	island.town.evolve_all()
	var bad := 0
	var blocks := 0
	for l: Town.Lot in island.town.lots.values():
		if l.group.size() > 1:
			blocks += 1
			var ls: Array = []
			for m in l.group:
				ls.append(island.town.lots[m])
			if not HouseGen.outline_ok(HouseGen.block_outline(ls)):
				bad += 1
	check(bad == 0, "joined buildings stand on clean outlines (%d bad of %d)" % [bad, blocks])
	island.queue_free()
	await get_tree().process_frame


## Island streets: a drawn line becomes a graded street the ground meets, the
## eraser splits it, and it survives a save round trip.
func _streets() -> void:
	var land := Land.new()
	add_child(land)
	land.generate(7)
	var st := Streets.new()
	st.land = land
	add_child(st)
	var raw := PackedVector2Array()
	for k in 31:
		raw.append(Vector2(-15.0 + k, sin(k * 0.2) * 3.0))
	var s: Streets.Street = st.add_stroke(raw)
	check(s != null and s.pts.size() > 40, "a drawn line becomes a street")
	var steep := 0.0
	for i in s.pts.size() - 1:
		steep = maxf(steep, absf(s.ys[i + 1] - s.ys[i]) / s.pts[i].distance_to(s.pts[i + 1]))
	check(steep <= Streets.MAX_GRADE + 0.01, "streets never get steeper than the grade limit (%.3f)" % steep)
	var mid := s.pts[s.pts.size() / 2]
	check(absf(land.height_at(mid.x, mid.y) - (s.ys[s.pts.size() / 2] - 0.03)) < 0.08, "the ground is cut and filled to meet the street")
	var cross := PackedVector2Array([Vector2(mid.x, mid.y - 10.0), Vector2(mid.x, mid.y + 10.0)])
	var c: Streets.Street = st.add_stroke(cross)
	check(c != null and absf(c.closest(mid).y - s.closest(mid).y) < 0.05, "crossing streets meet at one height")
	check(st.erase_at(s.pts[s.pts.size() / 2 - 16], 1.0) and st.streets.size() == 3, "the eraser splits a street in two")
	# growing a painted area around a main street lays out a network of side streets
	st.clear()
	land.generate(11)
	var main := PackedVector2Array()
	for k in 41:
		main.append(Vector2(-32.0 + 48.0 * k / 40.0, 4.0 + sin(k / 40.0 * PI) * 3.0))
	st.add_stroke(main)
	land.paint_zone(Vector3(-8, 0, 4), 28.0, 2.0)
	var g := Growth.new()
	g.land = land
	g.streets = st
	add_child(g)
	var t0 := Time.get_ticks_msec()
	var made := g.grow_all()
	print("grew %d side streets in %d ms" % [made, Time.get_ticks_msec() - t0])
	check(made >= 8, "painting an area grows a network of side streets (%d)" % made)
	var worst := 0.0
	for a2 in st.streets:
		for i in a2.pts.size() - 1:
			worst = maxf(worst, absf(a2.ys[i + 1] - a2.ys[i]) / maxf(a2.pts[i].distance_to(a2.pts[i + 1]), 0.01))
	check(worst <= Streets.MAX_GRADE + 0.02, "grown streets keep to the grade limit (%.3f)" % worst)
	var joined := 0
	for a2 in st.streets:
		if a2.kind == "side":
			for e in [0, a2.pts.size() - 1]:
				for o in st.streets:
					if o != a2 and o.closest(a2.pts[e]).x < o.w() + 0.3:
						joined += 1
						break
	check(joined >= made, "side streets join the network (%d ends joined)" % joined)
	g.queue_free()
	st.clear()
	land.generate(7)
	st.add_stroke(raw)
	var s2: Streets.Street = st.streets[0]
	var mid2 := s2.pts[s2.pts.size() / 2]
	st.add_stroke(PackedVector2Array([Vector2(mid2.x, mid2.y - 10.0), Vector2(mid2.x, mid2.y + 10.0)]))
	st.erase_at(s2.pts[s2.pts.size() / 2 - 16], 1.0)
	var data := st.to_data()
	st.from_data(JSON.parse_string(JSON.stringify(data)))
	check(st.streets.size() == 3 and st.to_data().size() == 3, "streets survive a save")
	st.queue_free()
	land.queue_free()


## The new island grown into one town from coast to coast must leave room in
## the frame budget for the HUD and for traffic and people still to come.
func _island_undo() -> void:
	var island := IslandWorld.new()
	add_child(island)
	island.new_island(5)
	var before := island.land.heights.duplicate()
	island._undo.append(island.snapshot())
	var pts := PackedVector2Array()
	for k in 30:
		pts.append(Vector2(-12 + k, 2 + sin(k * 0.2) * 2.0))
	var s := island.streets.add_stroke(pts)
	island._redo.clear()
	check(s != null and island.streets.streets.size() == 1 and island.land.heights != before, "a street is laid and cuts into the land")
	var key := s.key
	check(island.undo() and island.streets.streets.is_empty() and island.land.heights == before, "undo takes the street and its earthworks away")
	check(island.redo() and island.streets.streets.size() == 1 and island.streets.streets[0].key == key, "redo puts the same street back")
	var data := island.streets.to_data()
	island.streets.from_data(data)
	check(island.streets.streets[0].key == key, "streets keep their keys through a save")
	# undo only takes back what the stroke changed: the town elsewhere stands
	island.land.paint_zone(Vector3(0, 0, 2), 14.0, 2.0)
	island.town.fill_all()
	var standing := island.town.lots.keys()
	island._undo.append(island.snapshot())
	var far := PackedVector2Array()
	for k in 20:
		far.append(Vector2(40 + k, -40 + k * 0.3))
	island.streets.add_stroke(far)
	island.land.paint_zone(Vector3(50, 0, -36), 6.0, 2.0)
	var t0 := Time.get_ticks_msec()
	island.undo()
	var took := Time.get_ticks_msec() - t0
	var kept := 0
	for id in standing:
		kept += int(island.town.lots.has(id))
	check(standing.size() > 3 and kept == standing.size() and island.streets.streets.size() == 1, "undo leaves the rest of the town standing (%d of %d houses)" % [kept, standing.size()])
	check(took < 50, "undo is quick (%d ms)" % took)
	island.redo()
	check(island.streets.streets.size() == 2 and island.land.zone_at(50, -36) > 0.5, "redo lays the far street and its town again")
	# the clock can be held at a time of day, or left to run
	Game.settings["time"] = "night"
	island.time_of_day = 0.4
	for k in 60:
		island.advance_time(0.1)
	check(absf(island.time_of_day - World.TIMES.night) < 0.01, "the clock settles on the time picked (%.3f)" % island.time_of_day)
	Game.settings["time"] = "auto"
	var t1 := island.time_of_day
	island.advance_time(1.0)
	check(island.time_of_day != t1, "on Auto the day goes round by itself")
	island.rig.tilt_by(10.0)
	check(is_equal_approx(island.rig._t_tilt, CameraRig.MAX_TILT), "the view tilts only so far")
	island.rig.tilt_by(-10.0)
	check(is_equal_approx(island.rig._t_tilt, CameraRig.MIN_TILT), "and up towards the horizon further than down")
	island.rig.tilt_by(10.0 + CameraRig.MIN_TILT)
	island.queue_free()
	await get_tree().process_frame


func _island_grow() -> void:
	var island := IslandWorld.new()
	add_child(island)
	island.new_island(9)
	island.progress.from_dict({})
	var pts := PackedVector2Array()
	for k in 60:
		pts.append(Vector2(-30 + k, 3.0))
	island.streets.add_stroke(pts)
	island.streets.flush()
	var far := Vector2(-30, -30)
	for st: Streets.Street in island.streets.streets:
		far = far if st.closest(far).x > 20.0 else Vector2(30, -30)
	check(island.can_grow_at(Vector2(0, 6)) and not island.can_grow_at(far), "the Grow brush knows where there is a street to grow from")
	# one tap beside the street
	var at := Vector3(0, island.land.height_at(0, 6.5), 6.5)
	island.brush = "grow"
	island._ring_at = at
	island._stroke = true
	island._undo.append(island.snapshot())
	island._stroke_lo = Vector2(at.x, at.z)
	island._stroke_hi = Vector2(at.x, at.z)
	island._paint_town(at, 0.55)
	island._stroke_did = true
	island._end_stroke()
	var t := 0.0
	while t < 8.0 and island.streets.streets.size() < 2:
		await get_tree().process_frame
		t += get_process_delta_time()
	check(island.streets.streets.size() >= 2, "a single Grow tap beside a street grows a new street (%d streets, %.1f s)" % [island.streets.streets.size(), t])
	# a long drag along the other side grows while the finger is still down
	var before := island.streets.streets.size()
	island._stroke = true
	island._undo.append(island.snapshot())
	t = 0.0
	while t < 4.0:
		var x := -20.0 + t * 10.0
		island._ring_at = Vector3(x, island.land.height_at(x, -0.5), -0.5)
		await get_tree().process_frame
		t += get_process_delta_time()
	check(island.streets.streets.size() > before, "the town grows while the Grow brush is still painting (%d new)" % (island.streets.streets.size() - before))
	island._end_stroke()
	island.queue_free()
	await get_tree().process_frame


## Grow levels: a level-4 area grows taller than a level-1 one, houses start
## small and climb over time to their cap, and how far they got is saved.
func _island_levels() -> void:
	var island := IslandWorld.new()
	add_child(island)
	island.new_island(9)
	var pts := PackedVector2Array()
	for k in 70:
		pts.append(Vector2(-35 + k, 3.0))
	island.streets.add_stroke(pts)
	island.streets.flush()
	island.land.paint_zone(Vector3(-18, 0, 3), 16.0, 2.0)
	island.land.paint_zone(Vector3(18, 0, 3), 16.0, 2.0)
	island.land.paint_level(Vector3(-18, 0, 3), 16.0, 1.0, 2.0)
	island.land.paint_level(Vector3(18, 0, 3), 16.0, 4.0, 2.0)
	check(island.land.level_at(-18, 3) == 1.0 and island.land.level_at(18, 3) == 4.0, "the Grow brush paints its level into the ground")
	island.town.fill_all()
	var lo := Vector2.ZERO
	var hi := Vector2.ZERO
	var caps := {}
	var started := true
	for l: Town.Lot in island.town.lots.values():
		if l.type != "house":
			continue
		started = started and l.stage == 0
		caps[l.cap] = true
		if l.origin.x < -6.0:
			lo += Vector2(l.cap, 1)
		elif l.origin.x > 6.0:
			hi += Vector2(l.cap, 1)
	check(lo.y > 3 and hi.y > 3, "houses grow on both halves (%d, %d)" % [lo.y, hi.y])
	check(started, "new houses start as small cottages")
	var lo_avg := lo.x / maxf(lo.y, 1.0)
	var hi_avg := hi.x / maxf(hi.y, 1.0)
	check(hi_avg > lo_avg + 1.5, "a Centre area aims much taller than a Village one (%.1f vs %.1f)" % [hi_avg, lo_avg])
	check(caps.size() >= 3, "levels vary a little from house to house (%d different)" % caps.size())
	# let time pass: houses climb one stage at a time, never past their cap
	for k in 400:
		island.town._clock += 2.0
		island.town._evolve_one()
	var grown := 0
	var over := false
	for l: Town.Lot in island.town.lots.values():
		if l.type == "house":
			grown += 1 if l.stage > 0 else 0
			over = over or l.stage > l.cap
	check(grown > 4 and not over, "houses grow over time up to their area's level (%d grew)" % grown)
	island.town.evolve_all()
	var joined := 0
	var spans := 0
	var low := 0
	for l: Town.Lot in island.town.lots.values():
		if l.group.size() > 1:
			joined += 1
			spans += l.group.size()
			low += 1 if l.origin.x < 0.0 else 0
	check(joined >= 2 and low == 0, "tall neighbours in the centre join into wider buildings (%d buildings over %d plots)" % [joined, spans])
	var before := island.town.stages()
	var civic_before := _civic_kinds(island)
	island._apply_save(JSON.parse_string(JSON.stringify(island.to_dict())))
	island.town.fill_all()
	var after := island.town.stages()
	var civic_after := _civic_kinds(island)
	check(civic_before.size() > 0 and civic_before == civic_after, "squares and public buildings come back with the island (%s, %s)" % [civic_before, civic_after])
	# plots may shift a little on ground levelled the first time round
	var sum_before := 0
	var sum_after := 0
	for v in before.values():
		sum_before += int(v)
	for v in after.values():
		sum_after += int(v)
	check(before.size() > 0 and sum_after >= sum_before * 0.85, "how far houses grew comes back with the island (%d of %d stages)" % [sum_after, sum_before])
	island.queue_free()
	await get_tree().process_frame


## Deep blocks fill in from behind: cottages and pocket parks that stand
## near a street without fronting it.
func _island_inner() -> void:
	var island := IslandWorld.new()
	add_child(island)
	island.new_island(9)
	for z in [-12.0, 12.0]:
		var pts := PackedVector2Array()
		for k in 60:
			pts.append(Vector2(-30 + k, z))
		island.streets.add_stroke(pts)
	island.streets.flush()
	island.land.paint_zone(Vector3(0, 0, 0), 26.0, 2.0)
	island.land.paint_level(Vector3(0, 0, 0), 26.0, 1.0, 2.0)
	island.land.paint_green(Vector3(12, 0, 0), 4.0, 2.0)
	island.town.fill_all()
	var cottages := 0
	var parks := 0
	var far := INF
	for l: Town.Lot in island.town.lots.values():
		if l.inner:
			if l.type == "park":
				parks += 1
			else:
				cottages += 1
				var mid := l.origin - Vector2(sin(l.yaw), cos(l.yaw)) * l.depth * 0.5
				far = minf(far, absf(absf(mid.y) - 12.0))
	check(cottages >= 2 and far > 3.5, "cottages stand inside deep blocks, back from the street (%d)" % cottages)
	check(parks >= 1, "painted green deep in a block becomes a pocket park (%d)" % parks)
	island.queue_free()
	await get_tree().process_frame


## The countryside: woods and lone trees on open ground, none on the streets
## or where Grow is painted, a wood where green is painted, and not too dear.
func _island_wilds() -> void:
	var island := IslandWorld.new()
	add_child(island)
	island.new_island(11, "island")
	var pts := PackedVector2Array()
	for k in 50:
		pts.append(Vector2(-25 + k, 6))
	island.streets.add_stroke(pts)
	island.streets.flush()
	island.town.fill_all()
	island.wilds.rebuild_all()
	var wild := island.wilds.tree_count()
	var acc: Dictionary = _busiest_view(island, [Vector2.ZERO, Vector2(60, 60), Vector2(-60, 40)])[1]
	var cost: int = acc.get("Wilds", [0, 0])[0] + acc.get("Wilds", [0, 0])[1]
	print("  wilds: %d trees, %d triangles in view" % [wild, cost])
	check(wild > 150, "the countryside grows woods and lone trees (%d)" % wild)
	# (a whole view of countryside: woods on top of the ground they stand on)
	check(cost < 20000, "the woods stay cheap (%d triangles)" % cost)
	var near := 0
	var s0: Streets.Street = island.streets.streets[0]
	for j in Wilds.PER * Wilds.CHUNKS:
		for i in Wilds.PER * Wilds.CHUNKS:
			var p := Vector2(-Land.HALF + (i + 0.5) * Wilds.GAP, -Land.HALF + (j + 0.5) * Wilds.GAP)
			if s0.closest(p).x < s0.reach() + 0.6 and island.wilds._spot(p.x, p.y, 0.0) >= 0:
				near += 1
	check(near == 0, "no tree stands on a street or its verge (%d)" % near)
	# Grow painted: the trees there make way for the town; green grows a wood
	var spots: Array[Vector2] = []
	for j in 13:
		for i in 13:
			var q := Vector2(-36 + i * 6, -36 + j * 4)
			var h := island.land.height_at(q.x, q.y)
			if h > 2.0 and h < 7.0 and island.land.normal_at(q.x, q.y).y > 0.97 and q.distance_to(Vector2(q.x, 6)) > 12.0:
				spots.append(q)
	var za: Vector2 = spots[0]
	var gb: Vector2 = spots[-1]
	island.land.paint_zone(Vector3(za.x, 0, za.y), 10.0, 2.0)
	island.land.paint_green(Vector3(gb.x, 0, gb.y), 10.0, 2.0)
	var zoned := 0
	var wood := 0
	var tried := 0
	for k in 400:
		var off := Vector2.from_angle(k * 0.7) * (k % 5)
		var a := za + off
		zoned += int(island.wilds._spot(a.x, a.y, 0.0) >= 0)
		var b := gb + off
		if island.land.normal_at(b.x, b.y).y > 0.9:
			tried += 1
			wood += int(island.wilds._spot(b.x, b.y, 0.6) >= 0)
	check(zoned == 0, "trees give way where Grow is painted (%d left)" % zoned)
	check(wood > tried * 0.8, "painted green away from the streets becomes a wood (%d of %d)" % [wood, tried])
	island.queue_free()
	await get_tree().process_frame


func _island_progress() -> void:
	var island := IslandWorld.new()
	add_child(island)
	island.new_island(9)
	var pr := island.progress
	pr.from_dict({})
	check(not pr.can_use("green") and pr.can_use("street"), "a new island starts with the Green brush locked")
	island.set_brush("green")
	check(island.brush == "", "a locked brush can't be picked")
	var pts := PackedVector2Array()
	for k in 60:
		pts.append(Vector2(-30 + k, 3.0))
	pr.coins = 10.0
	island.brush = "street"
	island._stroke = true
	island._path = pts
	island._undo.append(island.snapshot())
	island._end_stroke()
	check(island.streets.streets.is_empty() and pr.coins == 10.0, "a street you can't afford isn't laid")
	pr.coins = 100.0
	island._stroke = true
	island._path = pts
	island._undo.append(island.snapshot())
	island._end_stroke()
	check(island.streets.streets.size() == 1 and absf(pr.coins - (100.0 - 59.0 * IslandProgress.STREET_COST)) < 0.5, "a street costs coins by its length (%.1f left)" % pr.coins)
	pr.recount(true)
	check(pr.goals.size() == 3 and pr.street_m > 50.0, "there are three goals and the street counts (%d m)" % int(pr.street_m))
	pr.goals[0] = {"type": "streets", "base": 0, "target": 1, "icon": "road", "text": "test", "reward": 40}
	pr.recount(true)
	var paid := pr.claim_goal(0)
	check(paid == 40.0 and pr.goals_done == 1 and pr.goals.size() == 3, "a finished goal pays out and a new one takes its place")
	var saved := island.to_dict()
	pr.coins = 0.0
	pr.goals_done = 0
	island._apply_save(JSON.parse_string(JSON.stringify(saved)))
	check(absf(pr.coins - float(saved.progress.coins)) < 0.01 and pr.goals_done == 1 and pr.goals.size() == 3, "coins and goals come back with the island")
	island.queue_free()
	await get_tree().process_frame


func _island_coop() -> void:
	var a := IslandWorld.new()
	add_child(a)
	a.new_island(7)
	a.sync.begin()
	var b := IslandWorld.new()
	add_child(b)
	b.load_room(7, a.sync.full_state(), a.land.kind)
	# A lays a street and paints; B hears about it as one patch
	var pts := PackedVector2Array()
	for k in 30:
		pts.append(Vector2(-10 + k, -4 + cos(k * 0.2) * 2.0))
	var s := a.streets.add_stroke(pts)
	a.streets.flush()
	a.land.paint_zone(Vector3(0, 0, 0), 6.0, 1.0)
	a.land.paint_green(Vector3(3, 0, 3), 3.0, 1.0)
	var patch := a.sync.changes()
	check(patch.has("streets/" + s.key) and patch.size() > 20, "a builder's street and painting go out as one patch (%d entries)" % patch.size())
	check(a.sync.changes().is_empty(), "nothing is sent twice")
	b.sync.apply("/", patch)
	var got := b.streets.by_key(s.key)
	var same := got != null
	if got:
		same = got.pts.size() == s.pts.size() and got.pts[5].distance_to(s.pts[5]) < 0.02 and absf(got.ys[5] - s.ys[5]) < 0.02
	var k := 64 * Land.SIDE + 64
	check(same and absf(b.land.zone[k] - a.land.zone[k]) < 0.02 and absf(b.land.heights[k] - a.land.heights[k]) < 0.02, "the other builder gets the same street, ground and painting")
	check(b.sync.changes().is_empty(), "what came from the room is not sent back")
	# taking the street away reaches the room too
	a.streets.remove_street(s)
	var gone := a.sync.changes()
	check(gone.has("streets/" + s.key) and gone["streets/" + s.key] == null, "a removed street is removed for everyone")
	b.sync.apply("/streets/" + s.key, null)
	check(b.streets.by_key(s.key) == null, "and it goes from the other island")
	a.queue_free()
	b.queue_free()
	await get_tree().process_frame


func _island_budget() -> void:
	var island := IslandWorld.new()
	add_child(island)
	island.new_island(11)
	for line in [[Vector2(-34, 4), Vector2(26, 2)], [Vector2(-6, -30), Vector2(-2, 30)]]:
		var pts := PackedVector2Array()
		for k in 41:
			var a: Vector2 = line[0]
			pts.append(a.lerp(line[1], k / 40.0) + Vector2(0, sin(k / 40.0 * PI) * 3.0))
		island.streets.add_stroke(pts)
	# a big town (the whole first island's worth), painted where it grows
	island.land.paint_zone(Vector3.ZERO, float(OS.get_environment("CV_BUDGET_R")) if OS.get_environment("CV_BUDGET_R") != "" else 80.0, 2.0)
	if OS.get_environment("CV_BUDGET_LEVEL") != "":
		# the same island at another Grow level, to see what it costs
		island.land.paint_level(Vector3.ZERO, 70.0, float(OS.get_environment("CV_BUDGET_LEVEL")), 2.0)
	island.growth.focus = Vector2.ZERO
	var made := island.growth.grow_all()
	island.streets.flush()
	island.town.fill_all()
	island.town.evolve_all()
	while not island.land.is_settled():
		island.land.rebuild_dirty(1 << 20)
	island.land.rebuild_shadow()
	await get_tree().process_frame
	await get_tree().process_frame
	# a town this size has its windmill and lighthouse
	island.progress.recount(true)
	island.landmarks.settle()
	await get_tree().process_frame
	check(island.bunting.spans().size() > 0, "bunting hangs across the main streets (%d strings)" % island.bunting.spans().size())
	check(island.landmarks.spots.has("windmill"), "a big town gets a windmill (%s)" % str(island.landmarks.spots))
	var wm: Vector2 = island.landmarks.spots.get("windmill", Vector2.ZERO)
	check(island.town.is_built(wm) and island.landmarks.beams().size() <= 1, "the town leaves room round a landmark")
	island.wilds.rebuild_all()
	island.yards.rebuild_all()
	check(island.yards.yard_count() > 30, "the gaps between buildings fill with gardens, courtyards and yards (%d)" % island.yards.yard_count())
	# the two biggest ships passing at once
	island.ships.spawn(0, true)
	island.ships.spawn(1, true)
	# the frame draws what is in view: the worst of a few views over the town
	# from as far out as the camera goes
	var view := _busiest_view(island, [Vector2.ZERO, Vector2(-25, 15), Vector2(25, -15)])
	var total: int = view[0]
	var worst: Dictionary = view[1]
	for k in worst:
		print("  island tris %-16s %7d +shadow %7d" % [k, worst[k][0], worst[k][1]])
	var reserve := 8000 + 16000
	print("island: %d streets, %d houses, %d triangles in the busiest view (+%d for HUD, traffic and people)" % [made + 2, island.town.house_count(), total, reserve])
	check(island.town.house_count() > 130, "a whole island grows a real town (%d houses)" % island.town.house_count())
	check(total + reserve < TriBudget.BUDGET, "the busiest view over a big town stays under budget (%d)" % (total + reserve))
	# pulled all the way out (João, 2026-10-24) a little more is allowed: more
	# of the town fills the view
	var far_view := _busiest_view(island, [Vector2.ZERO, Vector2(-25, 15), Vector2(25, -15)], CameraRig.MAX_D, deg_to_rad(-32.0))
	var far: int = far_view[0]
	if OS.get_environment("CV_ONLY") == "budget":
		for k in far_view[1]:
			print("  far tris %-16s %7d +shadow %7d" % [k, far_view[1][k][0], far_view[1][k][1]])
	print("island: %d triangles in the busiest view from all the way out" % far)
	check(far + reserve < TriBudget.FAR_BUDGET, "and from all the way out stays under %dk (%d)" % [TriBudget.FAR_BUDGET / 1000, far + reserve])
	# and tilted right up to look across the town from the side, more again
	var side: int = _busiest_view(island, [Vector2.ZERO, Vector2(-25, 15), Vector2(25, -15)], CameraRig.MAX_D, CameraRig.MIN_TILT)[0]
	side = maxi(side, _busiest_view(island, [Vector2.ZERO, Vector2(-25, 15), Vector2(25, -15)], CameraRig.FAR_D, CameraRig.MIN_TILT)[0])
	print("island: %d triangles in the busiest view from the side" % side)
	check(side + reserve < TriBudget.SIDE_BUDGET, "and from the side stays under %dk (%d)" % [TriBudget.SIDE_BUDGET / 1000, side + reserve])
	var kits := {}
	for l: Town.Lot in island.town.lots.values():
		kits[l.kit] = true
	check(kits.size() >= 3, "the town has quarters in different styles (%d)" % kits.size())
	var pr := island.progress
	pr.recount(true)
	var houses := 0
	for l: Town.Lot in island.town.lots.values():
		houses += int(l.type == "house")
	check(pr.homes == houses and pr.residents > pr.homes and pr.shops > 0, "the town counts its homes, residents and shops (%d, %d, %d)" % [pr.homes, pr.residents, pr.shops])
	check(pr.title != "Hamlet" and pr.can_use("green") and pr.income() > 0.0, "a big town earns a title, opens brushes and pays its way (%s)" % pr.title)
	# the same lot grows the same house every time
	var some: Town.Lot = island.town.lots.values()[0]
	# (building levels the ground under the house, so the ground is put back between the two)
	var ground := island.land.heights.duplicate()
	var sy := island.land.height_at(some.origin.x, some.origin.y)
	var again := HouseGen.build(some, island.land, sy, 1234)
	island.land.heights = ground.duplicate()
	var twice := HouseGen.build(some, island.land, sy, 1234)
	check(again[0] == twice[0] and again[2] == twice[2], "houses are built the same from the same seed")
	var civic := 0
	for l: Town.Lot in island.town.lots.values():
		if l.type == "square" or l.type == "church":
			civic += 1
	check(civic >= 1, "the town grows a square or a church (%d)" % civic)
	var public := {}
	for l: Town.Lot in island.town.lots.values():
		if l.type in ["hall", "school", "market"]:
			public[l.type] = public.get(l.type, 0) + 1
	check(public.size() >= 2, "the town grows public buildings: a town hall, schools, market halls (%s)" % str(public))
	check(public.get("hall", 0) <= 1, "there is only one town hall in the middle of town")
	var bases := []
	for l: Town.Lot in island.town.lots.values():
		if l.type == "house" and l.group.size() < 2:
			bases.append(l.plinth)
	bases.sort()
	var tall := bases.filter(func(b): return b > 0.3).size()
	print("  stone bases: median %.2f m, tallest %.2f m, %d of %d over 0.3 m" % [bases[bases.size() / 2], bases[-1], tall, bases.size()])
	check(tall * 5 < bases.size(), "houses on slopes stand on levelled ground, with few tall stone bases (%d of %d)" % [tall, bases.size()])
	# tapping a building tells what it is
	var picked := 0
	var told := ""
	for l: Town.Lot in island.town.lots.values():
		if l.type != "house" or l.host != 0:
			continue
		var c := l.origin + Vector2(sin(l.yaw), cos(l.yaw)) * -1.0
		var hit: Variant = island.town.lot_on_ray(Vector3(c.x, 60.0, c.y), Vector3.DOWN)
		if hit == l:
			picked += 1
			told = island.town.describe(l).title + ", " + ", ".join(island.town.describe(l).lines)
		if picked >= 10:
			break
	check(picked >= 8, "tapping a building picks it (%d of 10): %s" % [picked, told])
	# from a low slant, a tap picks the building drawn under the finger: the
	# nearest walls or roof along the ray, whatever plots it crosses first
	var slant_ok := 0
	var slant_n := 0
	for l: Town.Lot in island.town.lots.values():
		if l.type != "house" or l.host != 0 or l.arrays.is_empty() or slant_n >= 12:
			continue
		var v: PackedVector3Array = l.arrays[0]
		var aim := (v[v.size() / 2] + v[v.size() / 2 + 1] + v[v.size() / 2 + 2]) / 3.0
		var eye := aim + Vector3(25.0, 18.0, 25.0)
		var dir := (aim - eye).normalized()
		var truth: Town.Lot = null
		var near := INF
		for o: Town.Lot in island.town.lots.values():
			var d := island.town._ray_hit(o, eye, dir)
			if d < near:
				near = d
				truth = o
		if truth == null:
			continue
		slant_n += 1
		if island.town.lot_on_ray(eye, dir) == truth:
			slant_ok += 1
	check(slant_n >= 8 and slant_ok == slant_n, "a slanting tap picks the building drawn under it (%d of %d)" % [slant_ok, slant_n])
	# painting green turns the houses there into parks
	var at: Vector2 = some.origin
	island.land.paint_green(Vector3(at.x, 0, at.y), 8.0, 1.0)
	island.town.zone_changed(at, 8.0)
	island.town.fill_all()
	island.town.evolve_all()
	var parks := 0
	var built := 0
	for l: Town.Lot in island.town.lots.values():
		if island.town._green(l) > 0.6:
			if l.type == "park":
				parks += 1
			elif l.type == "house":
				# (a church or a school may well stand in a park)
				built += 1
				print("  left: %s at %s (%.1f from the brush), green %.2f, host %d, group %s, street %d" % [l.type, l.origin, l.origin.distance_to(at), island.town._green(l), l.host, l.group, l.street])
	check(parks > 0 and built == 0, "painted green becomes parks (%d parks, %d houses left)" % [parks, built])
	# cars wander the streets, turning where they meet, never leaving them
	var graph := island.streets.links()
	var rng := RandomNumberGenerator.new()
	var off := 0.0
	var turns := 0
	var lost := 0
	for k in 6:
		var m := StreetWalk.spawn(island.streets, rng)
		for step in 600:
			var was: Streets.Street = m.s
			if not StreetWalk.advance(island.streets, graph, m, 0.05, 0.4, rng):
				lost += 1
				break
			if m.s != was:
				turns += 1
			var spot: Vector3 = StreetWalk.place(island.streets, m, 0.3)[0]
			var nearest := INF
			for st: Streets.Street in island.streets.streets:
				if st.near_box(Vector2(spot.x, spot.z), 2.0):
					nearest = minf(nearest, st.closest(Vector2(spot.x, spot.z)).x)
			off = maxf(off, nearest)
	check(off < 0.6 and turns > 0 and lost == 0, "traffic keeps to the streets and turns at junctions (%.2f off, %d turns)" % [off, turns])
	_gulls(island.wildlife)
	island.queue_free()
	await get_tree().process_frame


## The most triangles seen from as far out as the camera goes, looking at any
## of `focuses` from several sides: [total, by part].
func _busiest_view(island: IslandWorld, focuses: Array, d := CameraRig.FAR_D, tilt := -CameraRig.MAX_TILT) -> Array:
	var total := 0
	var worst := {}
	for yaw_deg in [0, 35, 80, 135, 200, 290]:
		# as the zoom tilts it, and tilted out as far as the player can
		for pitch in [island.rig.pitch_for(d), maxf(island.rig.pitch_for(d) + tilt, deg_to_rad(3.0))]:
			for focus: Vector2 in focuses:
				var yaw := deg_to_rad(yaw_deg)
				var at := Vector3(focus.x, maxf(island.land.height_at(focus.x, focus.y), 0.0) * 0.8, focus.y)
				var eye := at + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * d
				var acc := TriBudget.count_view(island, eye, at)
				var t := TriBudget.total(acc)
				if t > total:
					total = t
					worst = acc
	return [total, worst]


## The two top Grow levels: Downtown grows apartment blocks of eight to ten
## floors, Skyline grows towers of twelve and more, set back over a podium.
func _island_skyline() -> void:
	var island := IslandWorld.new()
	add_child(island)
	island.new_island(9)
	var pts := PackedVector2Array()
	for k in 70:
		pts.append(Vector2(-35 + k, 3.0))
	island.streets.add_stroke(pts)
	island.streets.flush()
	island.land.paint_zone(Vector3(0, 0, 3), 34.0, 2.0)
	island.land.paint_level(Vector3(-18, 0, 3), 16.0, 5.0, 2.0)
	island.land.paint_level(Vector3(18, 0, 3), 16.0, 6.0, 2.0)
	island.town.fill_all()
	island.town.evolve_all()
	var mid := 0
	var tall := 0
	var top := 0.0
	var bad := 0
	for l: Town.Lot in island.town.lots.values():
		if l.type != "house" or l.host != 0:
			continue
		if l.arrays.is_empty():
			bad += 1
			continue
		if l.stage == 5 and l.floors >= 8 and l.floors <= 11:
			mid += 1
		if l.stage == 6 and l.floors >= 12:
			tall += 1
			var hi := -INF
			for v: Vector3 in l.arrays[0]:
				hi = maxf(hi, v.y)
			top = maxf(top, hi - l.street_y)
	check(mid >= 2, "Downtown grows apartment blocks of eight to ten floors (%d)" % mid)
	check(tall >= 2 and top > 12 * Town.FH, "Skyline grows towers (%d, the tallest %.1f m)" % [tall, top])
	check(bad == 0, "every building is drawn")
	var sky := 0
	var sky_top := 0.0
	for l: Town.Lot in island.town.lots.values():
		if l.type == "house" and l.host == 0 and l.group.size() >= 2 and l.stage == 6 and l.floors >= 20:
			sky += 1
			for v: Vector3 in l.arrays[0]:
				sky_top = maxf(sky_top, v.y - l.street_y)
	check(sky >= 1 and sky_top > 20 * Town.FH, "joined Skyline plots rise as skyscrapers (%d, the tallest %.1f m)" % [sky, sky_top])
	island.queue_free()
	await get_tree().process_frame


## Fields cover open country but keep clear of the town and its parks, and
## the woods leave them open.
## The Settings page's Check for updates: what it reports for each answer.
func _update_check() -> void:
	var got := []
	var on := func(status: String, version: String): got.append([status, version])
	Updater.checked.connect(on)
	# this build can't update itself (no Android or Windows release)
	Updater.check_now()
	await get_tree().process_frame
	check(not got.is_empty() and got[-1][0] == "unsupported", "a build that can't update says so (%s)" % str(got))
	var cur: String = Updater.current
	var release := func(tag: String, assets: Array) -> PackedByteArray:
		return JSON.stringify({"tag_name": tag, "assets": assets, "html_url": ""}).to_utf8_buffer()
	Updater.current = "0.1.50"
	Updater._manual = true
	Updater._on_release(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), release.call("v0.1.50", []))
	check(got[-1] == ["latest", "0.1.50"], "on the newest release it says you're up to date (%s)" % str(got[-1]))
	Updater._manual = true
	Updater._on_release(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), release.call("v0.1.51", []))
	check(got[-1] == ["pending", "0.1.51"], "a release still uploading is on its way (%s)" % str(got[-1]))
	Updater._dismissed = true
	Updater._manual = true
	var assets := [{"name": "CityViews.apk", "browser_download_url": "https://x/a.apk"}, {"name": "CityViews-Windows.zip", "browser_download_url": "https://x/w.zip"}]
	Updater._on_release(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), release.call("v0.1.51", assets))
	check(got[-1] == ["newer", "0.1.51"] and Updater._card != null and Updater._card.visible, "a newer one shows the update card again, even after it was closed")
	Updater._manual = true
	Updater._on_release(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray())
	check(got[-1][0] == "failed", "no connection says so")
	check(Hud.update_text("latest", "0.1.50").contains("latest"), "the Settings page words each answer")
	Updater.checked.disconnect(on)
	Updater.current = cur
	Updater._state = Updater.State.IDLE
	Updater._card.visible = false


## A town grown live, its work spread over many frames, ends up the same as
## one worked out all at once.
func _live_matches_full() -> void:
	var island := IslandWorld.new()
	add_child(island)
	island.new_island(11, "river")
	var pts := PackedVector2Array()
	for k in 31:
		pts.append(Vector2(-30 + k * 2.0, sin(k * 0.2) * 4.0))
	island.streets.add_stroke(pts)
	island.streets.flush()
	island.land.paint_zone(Vector3.ZERO, 30.0, 2.0)
	island.land.paint_level(Vector3.ZERO, 30.0, 5.0, 2.0)
	island.growth.wake(Vector2.ZERO)
	# let it grow and settle on its own, a frame at a time
	for f in 1500:
		await get_tree().process_frame
		if f > 200 and not island.growth.is_growing() and not island.town.is_busy() and island.land.is_settled() and island._maps_stage == 0:
			break
	await get_tree().process_frame
	var land := island.land
	check(island.streets.streets.size() > 3 and island.town.lots.size() > 20, "the town grew live (%d streets, %d lots)" % [island.streets.streets.size(), island.town.lots.size()])
	var farm := land._farm.duplicate()
	var shadow := land._shadow_hs.duplicate()
	var juncs := island.streets.junctions().size()
	land.update_farm()
	land._shadow_all = true
	land.rebuild_shadow()
	island.streets._meet_cache.clear()
	island.streets._junctions_dirty = true
	var off := 0
	for k in farm.size():
		off += int(absf(farm[k] - land._farm[k]) > 1e-4)
	check(off == 0, "the farm map worked out bit by bit matches one done at once (%d cells off)" % off)
	check(shadow == land._shadow_hs, "so does the ground's shadow stand-in")
	check(island.streets.junctions().size() == juncs, "and the junctions, with the street meetings remembered (%d)" % juncs)
	island.queue_free()
	await get_tree().process_frame


func _farmland() -> void:
	var island := IslandWorld.new()
	add_child(island)
	island.new_island(5, "river")
	var land := island.land
	var farmed := 0
	var total := 0
	for j in range(-180, 181, 6):
		for i in range(-180, 181, 6):
			total += 1
			farmed += int(land.farm_at(i, j))
	check(farmed > total / 10, "the country is farmed (%d of %d spots)" % [farmed, total])
	var c := land.start_point()
	land.paint_zone(Vector3(c.x, 0, c.y), 40.0, 2.0)
	island._update_maps(false)
	var near := 0
	for j in range(-40, 41, 4):
		for i in range(-40, 41, 4):
			if Vector2(i, j).length() < 40.0 and land.farm_at(c.x + i, c.y + j):
				near += 1
	check(near == 0, "no fields where the town is to grow (%d)" % near)
	var trees := 0
	var in_fields := 0
	island.wilds._reseed()
	for j in range(-180, 181, 3):
		for i in range(-180, 181, 3):
			if land.farm_at(i, j) and land.field_edge(i, j) > 0.6:
				trees += 1
				in_fields += int(island.wilds._spot(i, j, 0.0) >= 0)
	check(in_fields == 0, "no trees in the middle of a field (%d of %d)" % [in_fields, trees])
	island.queue_free()
	await get_tree().process_frame


## Districts painted with the Grow brush: industry grows works and no homes,
## a shops district puts a shop under every house, offices bring jobs; the
## districts and the top levels come back from a save.
func _districts() -> void:
	var island := IslandWorld.new()
	add_child(island)
	island.new_island(9, "island")
	var pts := PackedVector2Array()
	for k in 81:
		pts.append(Vector2(-40 + k, 3.0))
	island.streets.add_stroke(pts)
	island.streets.flush()
	island.land.paint_zone(Vector3(0, 0, 3), 42.0, 2.0)
	island.land.paint_level(Vector3(-30, 0, 3), 9.0, 3.0, 9.0, HouseGen.SHOPS)
	island.land.paint_level(Vector3(-10, 0, 3), 9.0, 3.0, 9.0, HouseGen.INDUSTRY)
	island.land.paint_level(Vector3(10, 0, 3), 9.0, 4.0, 9.0, HouseGen.OFFICES)
	island.land.paint_level(Vector3(30, 0, 3), 9.0, 6.0, 9.0, HouseGen.HOMES)
	check(island.land.use_at(-10, 3) == HouseGen.INDUSTRY and island.land.level_at(-10, 3) > 2.5, "the Grow brush paints a district and its level")
	island.town.fill_all()
	island.town.evolve_all()
	var works := 0
	var works_ok := true
	var shops := 0
	var shops_all := true
	var offices := 0
	var tall := 0
	var homes_office := 0
	for l: Town.Lot in island.town.lots.values():
		if l.type != "house" or l.host != 0 or absf(l.origin.y - 3.0) > 8.0:
			continue
		var x := l.origin.x
		if absf(x + 10) < 5.0:
			works += int(l.use == "industry")
			works_ok = works_ok and l.use == "industry" and l.group.is_empty() and not l.arrays.is_empty()
		elif absf(x + 30) < 5.0 and l.stage < 5:
			shops += int(l.shop)
			shops_all = shops_all and l.shop
		elif absf(x - 10) < 5.0:
			offices += int(l.use == "office")
		elif absf(x - 30) < 5.0:
			tall += int(l.stage == 6)
			homes_office += int(l.use != "home")
	check(works >= 2 and works_ok, "an industrial district grows works, each on its own plot (%d)" % works)
	check(shops >= 2 and shops_all, "a shops district puts a shop under every house (%d)" % shops)
	check(offices >= 2, "an office district grows offices (%d)" % offices)
	check(tall >= 1 and homes_office == 0, "homes grow into residential towers, never offices (%d tall, %d not homes)" % [tall, homes_office])
	# smoke rises from the stacks of the works, never from anything else
	var stacks := island.smoke.stacks()
	var stacks_ok := true
	for l: Town.Lot in island.town.lots.values():
		if l.smoke != Vector3.INF and l.use == "industry":
			stacks_ok = stacks_ok and l.smoke.y > island.land.height_at(l.origin.x, l.origin.y) + 1.0 and l.smoke.distance_to(Vector3(l.origin.x, l.smoke.y, l.origin.y)) < 8.0
	check(stacks_ok and stacks.size() <= Smoke.STACKS, "smoke rises from the top of the works' stacks (%d)" % stacks.size())
	# an airliner now and then, high over the town and cheap to draw
	island.planes.spawn(true)
	var plane: Node3D = island.planes._plane
	check(plane != null and plane.position.y > 30.0 and Vector2(plane.position.x, plane.position.z).length() < 400.0, "an airliner crosses high over the town")
	check(island.planes.tris() < 900, "an airliner is cheap to draw (%d tris)" % island.planes.tris())
	island.progress.recount(true)
	check(island.progress.jobs > 0, "offices and works bring jobs (%d)" % island.progress.jobs)
	var data := island.to_dict()
	island._apply_save(JSON.parse_string(JSON.stringify(data)))
	check(island.land.use_at(-10, 3) == HouseGen.INDUSTRY and island.land.use_at(10, 3) == HouseGen.OFFICES, "districts come back from a save")
	check(island.land.level_at(30, 3) > 5.5, "a Skyline level comes back from a save (%.1f)" % island.land.level_at(30, 3))
	# painting over a district changes what grows there
	island.land.paint_level(Vector3(-10, 0, 3), 9.0, 3.0, 9.0, HouseGen.HOMES)
	island.town.fill_all()
	island.town.zone_changed(Vector2(-10, 3), 9.0)
	island.town.fill_all()
	island.town.evolve_all()
	var left := 0
	for l: Town.Lot in island.town.lots.values():
		if l.type == "house" and absf(l.origin.x + 10) < 3.0 and absf(l.origin.y - 3.0) < 8.0:
			left += int(l.use == "industry" and island.land.use_at(l.origin.x, l.origin.y) == HouseGen.HOMES)
	check(left == 0, "repainting works as homes turns them into houses (%d left)" % left)
	# milestones pay out and open up the city; demand steers what grows
	var pr := island.progress
	var before := pr.coins
	pr.title = "Hamlet"
	pr.best = maxi(pr.best, 1300)
	pr.recount(false)
	check(pr.title in ["Big City", "Large City", "Metropolis"] and pr.coins >= before + pr.milestone_reward(pr.title) - 0.01, "a milestone gives a title and coins (%s, +%d)" % [pr.title, int(pr.coins - before)])
	check(pr.can_use("level6") and pr.can_use("industry") and pr.can_use("offices"), "milestones open the Skyline level and the districts")
	var sane := true
	for d in pr.demand:
		sane = sane and d >= 0.0 and d <= 1.0
	check(sane and island.town.demand == pr.demand, "demand is worked out for every district (%s)" % str(pr.demand))
	var any: Town.Lot = island.town.lots.values()[0]
	island.town.demand = [1.0, 1.0, 1.0, 1.0]
	var quick := island.town._delay(any, Vector2.ZERO)
	island.town.demand = [0.0, 0.0, 0.0, 0.0]
	check(island.town._delay(any, Vector2.ZERO) > quick * 2.0, "a district in demand grows faster")
	# at the top levels a shops district grows stores, malls and cinemas, not offices
	island.land.paint_level(Vector3(-30, 0, 3), 9.0, 6.0, 9.0, HouseGen.SHOPS)
	island.town.zone_changed(Vector2(-30, 3), 9.0)
	island.town.fill_all()
	island.town.evolve_all()
	var retail := {}
	var shop_offices := 0
	for l: Town.Lot in island.town.lots.values():
		if l.type == "house" and absf(l.origin.x + 30) < 5.0 and absf(l.origin.y - 3.0) < 8.0:
			if l.use == "retail":
				retail[l.trade] = true
			shop_offices += int(l.use == "office")
	check(not retail.is_empty() and shop_offices == 0, "a top-level shops district grows %s, never offices" % str(retail.keys()))
	# and brings its attractions: a Ferris wheel, and with enough stores a stadium
	island.landmarks._looked.clear()
	island.landmarks.settle()
	print("  retail plots: %d, attractions: %s" % [island.landmarks._retail().size(), str(island.landmarks.spots.keys())])
	check(island.landmarks.spots.has("wheel"), "a Ferris wheel turns by the shops")
	if island.landmarks.spots.has("stadium"):
		var st: Vector2 = island.landmarks.spots.stadium
		check(not island.town.lots.values().any(func(l: Town.Lot) -> bool: return l.origin.distance_to(st) < 5.0), "the stadium stands clear of the houses")
	island.queue_free()
	await get_tree().process_frame


## Avenues and highways: an avenue is lined with shops and houses and side
## streets grow off it; nobody lives along a highway and nothing branches off
## it; both come back from a save as what they were.
func _road_kinds() -> void:
	var island := IslandWorld.new()
	add_child(island)
	island.new_island(4, "island")
	var av := PackedVector2Array()
	var hw := PackedVector2Array()
	for k in 61:
		av.append(Vector2(-30 + k, -12.0))
		hw.append(Vector2(-30 + k, 22.0))
	var a := island.streets.add_stroke(av, "avenue")
	var h := island.streets.add_stroke(hw, "highway")
	island.streets.flush()
	check(a != null and h != null and a.kind == "avenue" and h.kind == "highway", "the Street brush lays avenues and highways")
	check(a.w() > Streets.KINDS.main.w * 1.6 and h.w() > a.w(), "avenues are wider than streets, highways wider still")
	# a lone road's ends are dead ends, rounded off past the end of the line
	var hm: MeshInstance3D = island.streets._meshes[h.id]
	var hb := hm.mesh.get_aabb()
	check(island.streets._dead_end(h, 0) and island.streets._dead_end(h, h.pts.size() - 1), "a road with nothing at its ends has dead ends")
	check(hb.position.x < h.pts[0].x - h.w() * 0.9 and hb.end.x > h.pts[h.pts.size() - 1].x + h.w() * 0.9, "dead ends are rounded off (%s)" % str(hb))
	# a shaky hand: streets keep the wobble, avenues smooth it, highways more so
	var shaky := PackedVector2Array()
	for k in 61:
		shaky.append(Vector2(-30 + k, -40.0 + (0.45 if k % 2 == 0 else -0.45) + sin(k * 0.9) * 0.6))
	var wob := {}
	for kind in ["main", "avenue", "highway"]:
		var pts := Streets._resample(shaky, 1.2)
		pts = Streets._relax(pts, Streets.SMOOTHING.get(kind, 0))
		pts = Streets._resample(Streets._chaikin(Streets._chaikin(pts)), Streets.SAMPLE)
		# how sharply it bends from point to point
		var bend := 0.0
		for i in range(1, pts.size() - 1):
			bend = maxf(bend, (pts[i + 1] - pts[i]).angle_to(pts[i] - pts[i - 1]))
		wob[kind] = bend
	check(wob.avenue < wob.main * 0.5 and wob.highway < wob.avenue * 0.7, "drawn avenues and highways even out a shaky line (%s)" % str(wob))
	island.land.paint_zone(Vector3(0, 0, 5), 40.0, 2.0)
	island.growth.focus = Vector2(0, 5)
	island.growth.grow_all(30)
	island.streets.flush()
	island.town.fill_all()
	var off_avenue := 0
	var off_highway := 0
	for s: Streets.Street in island.streets.streets:
		if s == a or s == h:
			continue
		for e in [s.pts[0], s.pts[s.pts.size() - 1]]:
			if a.closest(e).x < a.reach() + 1.0:
				off_avenue += 1
			if h.closest(e).x < h.reach() + 1.0:
				off_highway += 1
	# bus stops along the avenue, clear of its junctions, and none on the highway
	var near_junction := 0
	for st in a.stops:
		for jn in island.streets.junctions():
			if jn.at.distance_to(island.streets._ptf(a, st.x)) < 2.5:
				near_junction += 1
	check(a.stops.size() >= 1 and h.stops.is_empty(), "the avenue has bus stops (%d), the highway none" % a.stops.size())
	check(near_junction == 0, "no bus stop stands in a junction (%d)" % near_junction)
	var on_avenue := 0
	var on_highway := 0
	var main := true
	for l: Town.Lot in island.town.lots.values():
		if l.street == a.id and not l.inner:
			on_avenue += 1
			main = main and l.main
		if l.street == h.id:
			on_highway += 1
	check(off_avenue >= 2, "side streets grow off an avenue (%d)" % off_avenue)
	check(off_highway == 0, "grown streets never join a highway (%d)" % off_highway)
	# the Magic brush sends the houses under it straight to their top level
	var sparks := [0]
	island.town.magicked.connect(func(_at, _size): sparks[0] += 1)
	var to_go := island.town.magic(Vector2(0, 5), 14.0, true)
	island.town.magic(Vector2(0, 5), 14.0)
	for k in 600:
		if island.town._magic.is_empty():
			break
		island.town._process(0.016)
	var below := 0
	var topped := 0
	for l: Town.Lot in island.town.lots.values():
		if l.type == "house" and l.origin.distance_to(Vector2(0, 5)) <= 14.0:
			if l.stage < l.cap:
				below += 1
			else:
				topped += 1
	check(to_go > 0 and below == 0 and topped >= 4 and sparks[0] > 0, "the Magic brush tops out every house under it (%d stages, %d topped, %d below, %d sparkles)" % [to_go, topped, below, sparks[0]])
	var joined_dead := 0
	for s: Streets.Street in island.streets.streets:
		if s != a and s != h and a.closest(s.pts[0]).x < a.reach() and island.streets._dead_end(s, 0):
			joined_dead += 1
	check(joined_dead == 0, "a street that meets another is not a dead end (%d)" % joined_dead)
	check(on_avenue >= 6 and main, "houses and shops line an avenue, as on a main street (%d)" % on_avenue)
	check(on_highway == 0, "nobody lives along a highway")
	var seeds: Array = island.growth._seeds(h)
	check(seeds.is_empty(), "no street branches off a highway")
	# street lights down the middle of the avenue and the highway
	island.lights.rebuild()
	var on_mid := 0
	for t: Transform3D in island.lights.places():
		var q := Vector2(t.origin.x, t.origin.z)
		if a.closest(q).x < 0.1 or h.closest(q).x < 0.1:
			on_mid += 1
	check(on_mid >= 8, "street lights stand down the middle of avenues and highways (%d)" % on_mid)
	# traffic: lanes, queues, buses and lorries
	var tr := island.cars
	# a fixed draw of vehicles, so a run never just happens to spawn no bus or lorry
	tr._rng.seed = 11
	var lanes_av := {}
	var kinds_seen := {}
	for k in 600:
		tr._process(0.05)
		if k >= 300:
			for c in tr._cars:
				kinds_seen[tr.STYLES[c.v][0]] = true
				if c.s == a and c.grow >= 1.0:
					lanes_av[c.lane] = true
	var overlaps := 0
	for c in tr._cars:
		if c.ahead < -0.05 and c.grow >= 1.0:
			overlaps += 1
	check(tr._cars.size() >= 20, "traffic fills the streets (%d vehicles)" % tr._cars.size())
	check(lanes_av.size() == 2, "an avenue is driven in two lanes each way (%s)" % str(lanes_av.keys()))
	check(overlaps <= 1, "vehicles queue behind the one ahead rather than run into it (%d overlap)" % overlaps)
	check(kinds_seen.has("car") and (kinds_seen.has("bus") or kinds_seen.has("truck")), "buses and lorries drive among the cars (%s)" % str(kinds_seen.keys()))
	var data := island.to_dict()
	island._apply_save(JSON.parse_string(JSON.stringify(data)))
	var kinds := {}
	for s: Streets.Street in island.streets.streets:
		kinds[s.kind] = kinds.get(s.kind, 0) + 1
	check(kinds.get("avenue", 0) == 1 and kinds.get("highway", 0) == 1, "avenues and highways come back from a save (%s)" % kinds)
	island.queue_free()
	await get_tree().process_frame


## A street drawn across the river is a bridge: its deck stands clear of the
## water, which still flows under it; one along the bank gets a quay wall.
func _bridges() -> void:
	var island := IslandWorld.new()
	add_child(island)
	island.new_island(7, "river")
	var land := island.land
	var rv: PackedVector2Array = land._river
	var mid := 0
	for k in rv.size():
		if rv[k].length() < rv[mid].length():
			mid = k
	var t := (rv[mid + 1] - rv[mid - 1]).normalized()
	var across := Vector2(-t.y, t.x)
	var pts := PackedVector2Array()
	for k in 41:
		pts.append(rv[mid] + across * (k - 20) * 1.0)
	var s := island.streets.add_stroke(pts, "main")
	island.streets.flush()
	check(s != null and s.spans.size() == 1, "a street across the river becomes a bridge (%d spans)" % (s.spans.size() if s else -1))
	if s and s.spans.size() == 1:
		var c := s.pts.size() / 2
		check(s.ys[c] >= Streets.DECK and land.height_at(s.pts[c].x, s.pts[c].y) < -0.5, "its deck stands clear of the water, still flowing under it (%.2f over %.2f)" % [s.ys[c], land.height_at(s.pts[c].x, s.pts[c].y)])
		island._apply_save(JSON.parse_string(JSON.stringify(island.to_dict())))
		var back: Streets.Street = island.streets.streets[0]
		check(back.spans.size() == 1 and land.height_at(back.pts[c].x, back.pts[c].y) < -0.5, "and it is still a bridge after a reload")
		# every style of bridge stands up, at a modest cost in triangles
		BridgeGen.force = "none"
		island.streets._build(back)
		var plain := _tris(island.streets._meshes[back.id].mesh)
		for style in ["stone", "arch", "stayed", "suspension"]:
			BridgeGen.force = style
			island.streets._build(back)
			var mi: MeshInstance3D = island.streets._meshes[back.id]
			var bm: MeshInstance3D = mi.get_node_or_null("Bridges")
			var extra := _tris(mi.mesh) - plain + (_tris(bm.mesh) * 2 if bm else 0)
			print("  %s bridge: +%d tris (shadow casters counted twice)" % [style, extra])
			check((bm != null) == (style != "stone") and extra > 50 and extra < 6000, "the %s bridge is built (+%d triangles)" % [style, extra])
		BridgeGen.force = ""
		island.streets._build(back)
	# a street running along the bank, just clear of the water
	var bank := PackedVector2Array()
	for k in range(mid - 6, mid + 7):
		var tk := (rv[k + 1] - rv[k - 1]).normalized()
		bank.append(rv[k] + Vector2(-tk.y, tk.x) * (land._river_w[k] + 2.5) + t * 30.0)
	var q := island.streets.add_stroke(bank, "main")
	island.streets.flush()
	var quays := 0
	for f in q.quay:
		quays += int(f != 0)
	check(quays > q.pts.size() / 3, "a street along the bank gets a quay (%d of %d samples)" % [quays, q.pts.size()])
	island.queue_free()
	await get_tree().process_frame


## A save from before the big maps (a 128 m island, its samples numbered on a
## 129 x 129 grid) comes back as the same island, in the middle of the map.
func _legacy_save() -> void:
	var island := IslandWorld.new()
	add_child(island)
	# sample (i, j) of the old grid lay at (i - 64, j - 64)
	var k_old := 70 * 129 + 60
	var at := Vector2(60 - 64, 70 - 64)
	var old := {"v": 1, "seed": 11, "t": 0.0, "land": {str(k_old): 1.5}, "zone": {str(k_old): 1.0}, "level": {str(k_old): 3.0},
		"streets": [{"id": "a1", "k": "main", "p": [-10.0, 0.0, 0.0, 0.0, 10.0, 0.0], "y": [0.5, 0.5, 0.5]}], "name": "Old isle"}
	island._apply_save(old)
	check(island.land.kind == "legacy" and island.island_name == "Old isle", "an old save loads as the first kind of island (%s)" % island.land.kind)
	var k_new := island.land.index(int(at.x + Land.HALF), int(at.y + Land.HALF))
	check(absf(island.land.heights[k_new] - island.land.base_height(k_new) - 1.5) < 0.02, "its reshaped ground is where it was")
	check(island.land.zone_at(at.x, at.y) > 0.9 and island.land.level_at(at.x, at.y) == 3.0, "its painting is where it was")
	check(island.land.height_at(0, 0) > 0.0 and island.land.height_at(150, 150) < -1.0, "the old island sits in the middle of open sea")
	var saved := island.to_dict()
	check(int(saved.v) == IslandWorld.SAVE_VERSION and saved.map == "legacy", "and saves in the new format, as the same island")
	island._apply_save(JSON.parse_string(JSON.stringify(saved)))
	check(island.land.kind == "legacy" and island.land.zone_at(at.x, at.y) > 0.9, "which loads back the same")
	island.queue_free()
	await get_tree().process_frame


## Every kind of map: open country runs on past the map's edge (no rim of
## sea), with its river, lakes or coast; the kind is saved and comes back.
func _map_kinds() -> void:
	var island := IslandWorld.new()
	add_child(island)
	for kind: String in ["river", "coast", "lakes"]:
		island.new_island(3, kind)
		var land := island.land
		var wet := 0
		var dry_rim := 0
		var rim := 0
		for j in range(0, Land.SIDE, 4):
			for i in range(0, Land.SIDE, 4):
				var h := land.heights[j * Land.SIDE + i]
				wet += int(h < 0.0)
				if i == 0 or j == 0 or i >= Land.CELLS - 3 or j >= Land.CELLS - 3:
					rim += 1
					dry_rim += int(h > 0.0)
		var share := float(wet) / float((Land.SIDE / 4 + 1) * (Land.SIDE / 4 + 1))
		check(share > 0.01 and share < 0.45, "a %s map has water but is mostly land (%.0f%% water)" % [kind, share * 100.0])
		check(dry_rim > rim / 2, "the land of a %s map runs on past its edge (%d of %d rim samples dry)" % [kind, dry_rim, rim])
		check(not land._horizon.is_empty(), "and the country carries on to the horizon")
		var sp := island._home()
		check(land.height_at(sp.x, sp.z) > 0.3, "a fresh %s map opens over dry ground" % kind)
		check(land.has_sea() == (kind == "coast"), "ships sail past a %s map only if it has a sea" % kind)
		var saved := island.to_dict()
		check(saved.map == kind, "the map's kind is saved (%s)" % saved.map)
	island.new_island(3, "coast")
	var before := island.land.heights.duplicate()
	island._apply_save(JSON.parse_string(JSON.stringify(island.to_dict())))
	check(island.land.kind == "coast" and island.land.heights == before, "a coast map loads back the same")
	island.new_island(3, "island")
	check(island.land._horizon.is_empty() and island.land.has_sea(), "an island stands in open sea")
	island.queue_free()
	await get_tree().process_frame


## Three simulated minutes of gulls: they should land, perch, take off and dive, and never leave the sky.
func _gulls(life: Life) -> void:
	life.set_process(false)
	var seen := {}
	var sane := true
	for step in 3600:
		life._process(0.05)
		for g in life._gulls:
			seen[g.st] = true
			var p: Vector3 = g.p
			if not p.is_finite() or p.y < -0.2 or p.y > 20.0:
				sane = false
	print("  gull states seen: ", seen.keys())
	check(sane, "gulls stay between the sea and the sky")
	check(seen.has(Life.PERCH) and seen.has(Life.TAKEOFF), "gulls come down to perch and take off again")
	check(seen.has(Life.DIVE), "gulls dive for fish")


## The squares, churches and public buildings standing, sorted by kind.
func _civic_kinds(island: IslandWorld) -> Array:
	var out := []
	for l: Town.Lot in island.town.lots.values():
		if l.type in Town.CIVIC_WIDTH:
			out.append(l.type)
	out.sort()
	return out


## A street started just beside another snaps onto it; one started near the
## other's end carries straight on from it.
func _street_snap() -> void:
	var land := Land.new()
	add_child(land)
	land.generate(7)
	var st := Streets.new()
	st.land = land
	add_child(st)
	var raw := PackedVector2Array()
	for k in 21:
		raw.append(Vector2(-10.0 + k, 0.0))
	var a: Streets.Street = st.add_stroke(raw)
	# starts 2.4 m off the first street's centre, heading away at a slant
	raw = PackedVector2Array()
	for k in 12:
		raw.append(Vector2(-2.0 + k * 0.6, 2.4 + k))
	var b: Streets.Street = st.add_stroke(raw)
	var joined := b != null and a.closest(b.pts[0]).x < 0.05
	check(joined, "a street started just beside another joins it (%.2f m off)" % (a.closest(b.pts[0]).x if b else -1.0))
	# starts 2 m past the first street's end, going on the same way
	raw = PackedVector2Array()
	for k in 12:
		raw.append(Vector2(a.pts[a.pts.size() - 1].x + 2.0 + k, 0.4))
	var c: Streets.Street = st.add_stroke(raw)
	check(c != null and c.pts[0].distance_to(a.pts[a.pts.size() - 1]) < 0.05, "a street started near another's end carries on from it")
	st.queue_free()
	land.queue_free()


func _tris(m: Mesh) -> int:
	var n := 0
	if m == null:
		return 0
	for k in m.get_surface_count():
		var arr := m.surface_get_arrays(k)
		n += (arr[Mesh.ARRAY_INDEX].size() if arr[Mesh.ARRAY_INDEX] else arr[Mesh.ARRAY_VERTEX].size()) / 3
	return n
