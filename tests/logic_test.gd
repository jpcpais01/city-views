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
	_streets()
	await _island_budget()
	await _island_undo()
	await _island_coop()
	await _island_progress()
	print("FAILURES: %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)


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
	b.load_room(7, a.sync.full_state())
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
	island.land.paint_zone(Vector3.ZERO, 70.0, 2.0)
	island.growth.focus = Vector2.ZERO
	var made := island.growth.grow_all()
	island.streets.flush()
	island.town.fill_all()
	while not island.land.is_settled():
		island.land.rebuild_dirty(1 << 20)
	island.land.rebuild_shadow()
	await get_tree().process_frame
	await get_tree().process_frame
	var acc := TriBudget.count(island)
	for k in acc:
		print("  island tris %-16s %7d +shadow %7d" % [k, acc[k][0], acc[k][1]])
	var total := TriBudget.total(acc)
	var reserve := 8000 + 16000
	print("island: %d streets, %d houses, %d triangles (+%d for HUD, traffic and people)" % [made + 2, island.town.house_count(), total, reserve])
	check(island.town.house_count() > 150, "a whole island grows a real town (%d houses)" % island.town.house_count())
	check(total + reserve < TriBudget.BUDGET, "a whole-island town stays under budget (%d)" % (total + reserve))
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
	var again := HouseGen.build(some, island.land, island.land.height_at(some.origin.x, some.origin.y), 1234)
	var twice := HouseGen.build(some, island.land, island.land.height_at(some.origin.x, some.origin.y), 1234)
	check(again[0] == twice[0] and again[2] == twice[2], "houses are built the same from the same seed")
	var civic := 0
	for l: Town.Lot in island.town.lots.values():
		if l.type == "square" or l.type == "church":
			civic += 1
	check(civic >= 1, "the town grows a square or a church (%d)" % civic)
	# painting green turns the houses there into parks
	var at: Vector2 = some.origin
	island.land.paint_green(Vector3(at.x, 0, at.y), 8.0, 1.0)
	island.town.zone_changed(at, 8.0)
	island.town.fill_all()
	var parks := 0
	var built := 0
	for l: Town.Lot in island.town.lots.values():
		if island.town._green(l) > 0.6:
			if l.type == "park":
				parks += 1
			else:
				built += 1
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
