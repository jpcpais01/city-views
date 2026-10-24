extends Node
## Building cost probe: grows the budget town and prints triangles per lot kind.


func _ready() -> void:
	var island := IslandWorld.new()
	add_child(island)
	island.new_island(11, "island")
	for line in [[Vector2(-34, 4), Vector2(26, 2)], [Vector2(-6, -30), Vector2(-2, 30)]]:
		var pts := PackedVector2Array()
		for k in 41:
			var a: Vector2 = line[0]
			pts.append(a.lerp(line[1], k / 40.0) + Vector2(0, sin(k / 40.0 * PI) * 3.0))
		island.streets.add_stroke(pts)
	island.land.paint_zone(Vector3.ZERO, float(OS.get_environment("CV_R")) if OS.get_environment("CV_R") != "" else 40.0, 2.0)
	if OS.get_environment("CV_LEVEL") != "":
		island.land.paint_level(Vector3.ZERO, 70.0, float(OS.get_environment("CV_LEVEL")), 2.0)
	island.growth.focus = Vector2.ZERO
	island.growth.grow_all()
	island.streets.flush()
	island.town.fill_all()
	island.town.evolve_all()
	var stats := {}
	for l: Town.Lot in island.town.lots.values():
		if l.arrays.is_empty():
			continue
		var key := "%s/%d%s" % [l.type, l.stage, "j" if l.group.size() > 1 else ""]
		if not stats.has(key):
			stats[key] = [0, 0, 0, 0, 0]
		var st: Array = stats[key]
		st[0] += 1
		st[1] += (l.arrays[0] as PackedVector3Array).size() / 3
		st[2] += (l.arrays[4] as PackedVector3Array).size() / 3
		st[3] += (l.arrays[8] as PackedVector3Array).size() / 3
		st[4] += (l.arrays[10] as PackedVector3Array).size() + (l.arrays[14] as PackedVector3Array).size()
	var keys := stats.keys()
	keys.sort()
	var tot := [0, 0, 0, 0, 0]
	for k in keys:
		var st: Array = stats[k]
		print("%-14s n=%3d  main %5.0f  detail %5.0f  shadow %5.0f  blobs %4.0f" % [k, st[0], float(st[1]) / st[0], float(st[2]) / st[0], float(st[3]) / st[0], float(st[4]) / st[0]])
		for i in 5:
			tot[i] += st[i]
	print("total lots %d main %d detail %d shadow %d blobs %d" % tot)
	get_tree().quit()
