extends Node
## Frame-time probe: paints a big town at a high level and lets it grow live,
## timing each part of the island's frame and printing the worst of each.

var island: IslandWorld
var worst := {}
var over := {}
var frames := 0
var parts: Array[Node] = []


func _ready() -> void:
	island = IslandWorld.new()
	add_child(island)
	island.new_island(11, "river")
	for line in [[Vector2(-34, 4), Vector2(26, 2)], [Vector2(-6, -30), Vector2(-2, 30)]]:
		var pts := PackedVector2Array()
		for k in 41:
			var a: Vector2 = line[0]
			pts.append(a.lerp(line[1], k / 40.0) + Vector2(0, sin(k / 40.0 * PI) * 3.0))
		island.streets.add_stroke(pts)
	island.streets.flush()
	island.land.paint_zone(Vector3.ZERO, 45.0, 2.0)
	island.land.paint_level(Vector3.ZERO, 45.0, float(OS.get_environment("CV_LEVEL")) if OS.get_environment("CV_LEVEL") != "" else 6.0, 2.0)
	island.growth.wake(Vector2.ZERO)
	await get_tree().process_frame
	# take every part's frame over, to time each on its own
	island.set_process(false)
	for c in island.get_children():
		if c.get_script() != null and c.is_processing():
			c.set_process(false)
			parts.append(c)
	island.land.set_process(false)


func _process(delta: float) -> void:
	if island == null or parts.is_empty():
		return
	frames += 1
	var t := Time.get_ticks_usec()
	island._process(delta)
	_note("IslandWorld", Time.get_ticks_usec() - t)
	for c in parts:
		t = Time.get_ticks_usec()
		c._process(delta)
		_note(c.get_script().get_global_name(), Time.get_ticks_usec() - t)
	if frames >= int(OS.get_environment("CV_FRAMES")) if OS.get_environment("CV_FRAMES") != "" else frames >= 1500:
		var keys := worst.keys()
		keys.sort_custom(func(a, b): return worst[a] > worst[b])
		for k in keys:
			print("%-14s worst %6.1f ms   frames over 8 ms: %d" % [k, worst[k] / 1000.0, over.get(k, 0)])
		print("houses: %d, streets: %d" % [island.town.lots.size(), island.streets.streets.size()])
		get_tree().quit()


func _note(k: String, us: int) -> void:
	worst[k] = maxi(worst.get(k, 0), us)
	if us > 8000:
		over[k] = over.get(k, 0) + 1
