extends Node
## Building-lag probe: grows a big city (CV_R metres across, CV_GROW streets),
## then paints a Grow stroke over it, draws an avenue through it and lets it
## grow, printing for each stage the slowest whole frames and the time each
## part of the island took (worst and in all).
## Run: godot --headless --path . res://tests/build_probe.tscn

var island: IslandWorld
var frames := 0
var times := PackedInt32Array()
var parts: Array[Node] = []
var worst := {}
var total := {}
var _last := 0


func _ready() -> void:
	island = IslandWorld.new()
	add_child(island)
	island.new_island(11, "river")
	var r := float(OS.get_environment("CV_R")) if OS.get_environment("CV_R") != "" else 90.0
	for line in [[Vector2(-r, 4), Vector2(r, 2)], [Vector2(-6, -r), Vector2(-2, r)]]:
		var pts := PackedVector2Array()
		for k in 81:
			var a: Vector2 = line[0]
			pts.append(a.lerp(line[1], k / 80.0) + Vector2(0, sin(k / 80.0 * PI) * 3.0))
		island.streets.add_stroke(pts)
	island.land.paint_zone(Vector3.ZERO, r, 2.0)
	island.land.paint_level(Vector3.ZERO, r, 4.0, 2.0)
	island.growth.focus = Vector2.ZERO
	var t := Time.get_ticks_msec()
	island.growth.grow_all(int(OS.get_environment("CV_GROW")) if OS.get_environment("CV_GROW") != "" else 400)
	island.streets.flush()
	island.town.fill_all()
	island.town.evolve_all()
	island.growth.stop()
	await get_tree().process_frame
	# take every part's frame over, to time each on its own
	island.set_process(false)
	for c in island.get_children():
		if c.get_script() != null and c.is_processing():
			c.set_process(false)
			parts.append(c)
	print("grown in %d ms: lots %d, streets %d" % [Time.get_ticks_msec() - t, island.town.lots.size(), island.streets.streets.size()])


func _process(delta: float) -> void:
	frames += 1
	if not parts.is_empty():
		var t0 := Time.get_ticks_usec()
		island._process(delta)
		_note("IslandWorld", t0)
		for c in parts:
			t0 = Time.get_ticks_usec()
			c._process(delta)
			_note(str(c.get_script().get_global_name()), t0)
	var now := Time.get_ticks_usec()
	if _last > 0:
		times.append(now - _last)
	_last = now
	if frames < 120:
		# settling
		times = PackedInt32Array()
		worst.clear()
		total.clear()
		return
	if frames == 120:
		print("-- painting a Grow stroke at level 6 across the city")
		island.set_brush("grow")
		island.grow_level = 6
		var at := Vector3(-60, island.land.height_at(-60, -20), -20)
		island.rig.cam.global_position = Vector3(-60, 60, 20)
		island.rig.cam.look_at(at)
		island._begin_stroke(island.rig.cam.unproject_position(at))
		if not island._stroke:
			# (no camera to aim with headless: start it by hand)
			island._ring_at = at
			island._stroke = true
			island._stroke_over = BrushMask.class_at(island.land, Vector2(at.x, at.z))
			island._stroke_lo = Vector2(at.x, at.z) - Vector2.ONE * 20.0
			island._stroke_hi = Vector2(at.x, at.z) + Vector2.ONE * 20.0
	elif frames < 300:
		var p := Vector2(-60, -20).lerp(Vector2(60, 25), (frames - 120) / 180.0)
		island._ring_at = Vector3(p.x, island.land.height_at(p.x, p.y), p.y)
	elif frames == 300:
		island._end_stroke()
	elif frames == 600:
		_dump("grow stroke, and the town growing after it")
		print("-- drawing an avenue across the city")
		var pts := PackedVector2Array()
		for k in 120:
			pts.append(Vector2(-70 + k * 1.2, -40 + k * 0.6))
		island.streets.add_stroke(pts, "avenue")
	elif frames == 900:
		_dump("avenue")
		print("-- growing on its own")
	elif frames == 1300:
		_dump("idle")
		print("-- erasing a district across the city")
		_erase_from(Vector2(-50, -40))
	elif frames < 1480:
		var p := Vector2(-50, -40).lerp(Vector2(40, 30), (frames - 1300) / 180.0)
		island._ring_at = Vector3(p.x, island.land.height_at(p.x, p.y), p.y)
	elif frames == 1480:
		island._end_stroke()
	elif frames == 1700:
		_dump("erase a district, and what follows")
		print("-- erasing along the main street")
		_erase_from(Vector2(-80, 4))
	elif frames < 1880:
		var p := Vector2(-80, 4).lerp(Vector2(80, 2), (frames - 1700) / 180.0)
		island._ring_at = Vector3(p.x, island.land.height_at(p.x, p.y), p.y)
	elif frames == 1880:
		island._end_stroke()
	elif frames == 2100:
		_dump("erase along a street, and what follows")
		get_tree().quit()


func _erase_from(p: Vector2) -> void:
	island.set_brush("clear")
	var at := Vector3(p.x, island.land.height_at(p.x, p.y), p.y)
	island._begin_stroke(island.rig.cam.unproject_position(at))
	if not island._stroke:
		var t := Time.get_ticks_usec()
		island._undo.append(island.snapshot())
		print("  (undo snapshot %.1f ms)" % ((Time.get_ticks_usec() - t) / 1000.0))
		island._ring_at = at
		island._stroke = true
		island._stroke_did = false
		island._stroke_lo = p - Vector2.ONE * 20.0
		island._stroke_hi = p + Vector2.ONE * 20.0
	island._ring_at = at


func _note(k: String, t0: int) -> void:
	var us := Time.get_ticks_usec() - t0
	worst[k] = maxi(worst.get(k, 0), us)
	total[k] = total.get(k, 0) + us


func _dump(title: String) -> void:
	var s := Array(times)
	s.sort()
	s.reverse()
	var over := 0
	for x in s:
		if x > 16667:
			over += 1
	print("== %s: slowest frames (ms) %s, %d of %d over 16.7 ms" % [title, s.slice(0, 8).map(func(x): return "%.0f" % (x / 1000.0)), over, s.size()])
	var keys := total.keys()
	keys.sort_custom(func(a, b): return total[a] > total[b])
	for k in keys.slice(0, 8):
		print("  %-14s worst %6.1f ms   in all %7.1f ms" % [k, worst[k] / 1000.0, total[k] / 1000.0])
	times = PackedInt32Array()
	worst.clear()
	total.clear()
