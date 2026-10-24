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
	_street_snap()
	await _junction_fuzz()
	await _island_budget()
	await _island_undo()
	await _island_coop()
	await _island_grow()
	await _island_levels()
	await _island_inner()
	await _island_wilds()
	await _island_progress()
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
	island.new_island(11)
	var pts := PackedVector2Array()
	for k in 50:
		pts.append(Vector2(-25 + k, 6))
	island.streets.add_stroke(pts)
	island.streets.flush()
	island.town.fill_all()
	island.wilds.rebuild_all()
	var wild := island.wilds.tree_count()
	var acc := TriBudget.count(island)
	var cost: int = acc.get("Wilds", [0, 0])[0] + acc.get("Wilds", [0, 0])[1]
	print("  wilds: %d trees, %d triangles" % [wild, cost])
	check(wild > 150, "the countryside grows woods and lone trees (%d)" % wild)
	check(cost < 12000, "the woods stay cheap (%d triangles)" % cost)
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
	island.landmarks._check = 0.0
	island.landmarks._process(0.0)
	await get_tree().process_frame
	check(island.bunting.spans().size() > 0, "bunting hangs across the main streets (%d strings)" % island.bunting.spans().size())
	check(island.landmarks.spots.has("windmill") and island.landmarks.spots.has("lighthouse") and island.landmarks.spots.has("pier"), "a big town gets a windmill, a lighthouse and a pier (%s)" % str(island.landmarks.spots))
	var lh: Vector2 = island.landmarks.spots.get("lighthouse", Vector2.ZERO)
	check(island.town.is_built(lh) and island.landmarks.beams().size() <= 1, "the town leaves room round a landmark")
	island.wilds.rebuild_all()
	island.yards.rebuild_all()
	check(island.yards.yard_count() > 30, "the gaps between buildings fill with gardens, courtyards and yards (%d)" % island.yards.yard_count())
	# the two biggest ships passing at once
	island.ships.spawn(0, true)
	island.ships.spawn(1, true)
	var acc := TriBudget.count(island)
	for k in acc:
		print("  island tris %-16s %7d +shadow %7d" % [k, acc[k][0], acc[k][1]])
	var total := TriBudget.total(acc)
	var reserve := 8000 + 16000
	print("island: %d streets, %d houses, %d triangles (+%d for HUD, traffic and people)" % [made + 2, island.town.house_count(), total, reserve])
	check(island.town.house_count() > 130, "a whole island grows a real town (%d houses)" % island.town.house_count())
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
