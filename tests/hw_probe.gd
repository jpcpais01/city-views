extends Node
## Times the highway planner and finds its tightest curves: CV_MAP kind,
## CV_SEED (a list: 3,21,777). CV_HUD=1 presses the Road tool's Highways key.

func _ready() -> void:
	IslandWorld.auto_highways = false
	var island := IslandWorld.new()
	add_child(island)
	var kind := OS.get_environment("CV_MAP") if OS.get_environment("CV_MAP") != "" else "river"
	if OS.get_environment("CV_HUD") != "":
		# the Road tool's Highways key, end to end
		island.new_island(21, kind)
		var hud := Hud.new()
		hud.island = island
		add_child(hud)
		await get_tree().process_frame
		var before := island.highway_seed
		await hud._reroll()
		print("hud reroll: seed %d -> %d, %d highways" % [before, island.highway_seed, island.streets.streets.filter(func(o): return o.kind == "highway").size()])
		get_tree().quit()
		return
	var seeds := OS.get_environment("CV_SEED").split(",") if OS.get_environment("CV_SEED") != "" else PackedStringArray(["3"])
	for sds in seeds:
		await _one(island, kind, int(sds))
	get_tree().quit()


func _one(island: IslandWorld, kind: String, sd: int) -> void:
	var t0 := Time.get_ticks_msec()
	island.new_island(sd, kind)
	print("%s %d map: %d ms" % [kind, sd, Time.get_ticks_msec() - t0])
	t0 = Time.get_ticks_msec()
	var lines := HighwayPlan.make(island.land, island.default_highway_seed())
	print("plan: %d ms, %d lines" % [Time.get_ticks_msec() - t0, lines.size()])
	for k in lines.size():
		var h := lines[k]
		var tight := INF
		var at := Vector2.ZERO
		var ai := 0
		for i in range(3, h.size() - 3, 1):
			var a := (h[i] - h[i - 3]).normalized()
			var b := (h[i + 3] - h[i]).normalized()
			var turn := absf(a.angle_to(b))
			if turn > 1e-4 and 6.0 / turn < tight:
				tight = 6.0 / turn
				at = h[i]
				ai = i
		print("  line %d: %d pts, tightest %.0f m at %s (pt %d)%s" % [k, h.size(), tight, at, ai, "  <<<" if tight < 30.0 else ""])
	await get_tree().process_frame
