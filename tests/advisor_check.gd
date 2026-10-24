extends RefCounted
## Pip, the city advisor: on a town of only homes Pip asks for shops, a park
## and work; works beside homes get a green buffer; every tip stands on the
## map with a brush Pip can hand over; and the same town gets the same advice.


static func run(t: Node) -> void:
	var island := IslandWorld.new()
	t.add_child(island)
	island.new_island(9, "island")
	var empty := Advisor.analyse(island)
	t.check(empty.tips.is_empty() and str(empty.line).contains("Street"), "with no streets Pip says to draw one")
	for z in [0.0, 14.0, -14.0]:
		var pts := PackedVector2Array()
		for k in 81:
			pts.append(Vector2(-40 + k, z))
		island.streets.add_stroke(pts)
	island.streets.flush()
	island.land.paint_zone(Vector3(0, 0, 0), 30.0, 2.0)
	island.land.paint_level(Vector3(0, 0, 0), 30.0, 3.0, 9.0, HouseGen.HOMES)
	island.town.fill_all()
	island.town.evolve_all()
	var pr := island.progress
	pr.best = maxi(pr.best, 1300)
	pr.recount(true)
	var t0 := Time.get_ticks_usec()
	var r := Advisor.analyse(island)
	var took := (Time.get_ticks_usec() - t0) / 1000.0
	print("  advisor: %d residents, %d jobs, score %d, %.1f ms: %s" % [pr.residents, pr.jobs, r.score, took, str(r.tips.map(func(x): return x.kind))])
	t.check(pr.residents > 100 and r.tips.size() >= 2, "a town of only homes gets tips (%d)" % r.tips.size())
	var kinds: Array = r.tips.map(func(x): return x.kind)
	t.check("shops" in kinds or "jobs" in kinds or "offices" in kinds, "homes with no shops or work get asked for them (%s)" % str(kinds))
	var sane := true
	for tip in r.tips:
		var p: Vector2 = tip.pos
		sane = sane and absf(p.x) < Land.HALF and absf(p.y) < Land.HALF and str(tip.text) != "" and tip.action.has("brush")
		if tip.action.brush == "grow":
			sane = sane and pr.can_use(Land.USES[tip.action.use]) and island.can_grow_at(p)
		for other in r.tips:
			sane = sane and (other == tip or p.distance_to(other.pos) >= Advisor.APART)
	t.check(sane, "every tip stands apart on the map with a brush that can be used there")
	t.check(r.score >= 0 and r.score <= 100 and r.meters.size() == 4, "the city gets a score out of 100 and four meters (%d)" % r.score)
	t.check(str(Advisor.analyse(island).tips.map(func(x): return x.key)) == str(r.tips.map(func(x): return x.key)), "the same town gets the same advice")
	t.check(took < 60.0, "a look round is quick (%.1f ms)" % took)
	# works right beside the homes: Pip asks for a green buffer
	island.land.paint_level(Vector3(-16, 0, 14), 7.0, 3.0, 9.0, HouseGen.INDUSTRY)
	island.town.fill_all()
	island.town.zone_changed(Vector2(-16, 14), 7.0)
	island.town.fill_all()
	island.town.evolve_all()
	pr.recount(true)
	var a := Advisor.new()
	a.island = island
	a._run()
	var smoke := a._cands.filter(func(x): return x.kind == "smoke")
	t.check(not smoke.is_empty() and smoke[0].action.brush == "green", "works beside homes get a green buffer (%d)" % smoke.size())
	# taking a tip hands over the right brush, set to its district and level
	var hud := Hud.new()
	hud.island = island
	t.add_child(hud)
	var bot := AdvisorBot.attach(hud, island)
	await t.get_tree().process_frame
	bot._report = r
	bot._show_report(r)
	t.check(bot.marks.has_marks() and bot._tips_box.get_child_count() == r.tips.size(), "the tips are listed and marked on the map")
	var gi := -1
	for i in r.tips.size():
		if r.tips[i].action.brush == "grow":
			gi = i
	if gi >= 0:
		bot._act(gi)
		var act: Dictionary = r.tips[gi].action
		t.check(island.brush == "grow" and island.grow_use == act.use and island.grow_level == act.level, "Paint picks up Grow with the tip's district and level")
	bot._close(true)
	t.check(not bot.marks.has_marks(), "closing Pip takes the marks off the map")
	hud.queue_free()
	island.queue_free()
	await t.get_tree().process_frame
