extends RefCounted
## The city's history for the graphs: noted regularly, thinned in pairs when
## full so the whole life of the city fits, and drawn in the stats panel.


static func run(t: Node) -> void:
	var island := IslandWorld.new()
	t.add_child(island)
	island.new_island(4, "island")
	var h := CityHistory.new(island, false)
	island.add_child(h)
	await t.get_tree().process_frame
	await t.get_tree().process_frame
	t.check(h.points.size() == 1, "the history starts with a first note")
	for i in CityHistory.KEEP * 2:
		island.progress.residents = i * 3
		h.sample()
	t.check(h.points.size() <= CityHistory.KEEP and h.every > CityHistory.EVERY, "a full history thins out and notes less often (%d points, every %d s)" % [h.points.size(), h.every])
	var res := h.series(0)
	var rising := true
	for i in res.size() - 1:
		rising = rising and res[i] <= res[i + 1]
	t.check(rising and res[res.size() - 1] == (CityHistory.KEEP * 2 - 1) * 3, "thinning keeps the shape and the latest value")
	island.island_seed += 1
	await t.get_tree().process_frame
	await t.get_tree().process_frame
	t.check(h.points.size() == 1, "a new city starts its own history")
	var hud := Hud.new()
	hud.island = island
	t.add_child(hud)
	var c := CityCharts.attach(hud, island)
	await t.get_tree().process_frame
	t.check(c.get_parent() != null and c.history != null, "the graphs sit in the stats panel")
	c._pick(1)
	t.check(c._chart.lines.size() == 2, "the Money graph shows coins and income")
	hud.queue_free()
	island.queue_free()
	await t.get_tree().process_frame
