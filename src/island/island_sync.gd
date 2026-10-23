class_name IslandSync
extends Node
## Building the new island together. What each builder changes (the ground,
## the painted growing area and green, the streets) is sent to the room as
## small patches, and what the others change comes back and is laid in place.
## The town's houses follow from those, on every builder's own island; the
## town only grows its own side streets where its own builder painted.
##
## In the room: island/land/c<k> and island/zone/c<k>, island/green/c<k> per
## ground sample (offset from the natural ground, or the painted amount) and
## island/streets/<key> per street.

const SEND_EVERY := 0.5

var world: IslandWorld
var active := false
# the island as the room last knew it, to send only what changed since
var _h := PackedFloat32Array()
var _z := PackedFloat32Array()
var _g := PackedFloat32Array()
var _s := {}
var _timer := 0.0


## Everything on this island, as a room holds it.
func full_state() -> Dictionary:
	var land := world.land
	var out := {"land": {}, "zone": {}, "green": {}, "streets": {}}
	for k in land.heights.size():
		var d := land.heights[k] - land.base_height(k)
		if absf(d) > 0.005:
			out.land["c%d" % k] = snappedf(d, 0.01)
		if land.zone[k] > 0.005:
			out.zone["c%d" % k] = snappedf(land.zone[k], 0.01)
		if land.green[k] > 0.005:
			out.green["c%d" % k] = snappedf(land.green[k], 0.01)
	for s: Streets.Street in world.streets.streets:
		out.streets[s.key] = world.streets.street_data(s)
	return out


## Start sending from the island as it is now.
func begin() -> void:
	var land := world.land
	_h = land.heights.duplicate()
	_z = land.zone.duplicate()
	_g = land.green.duplicate()
	_s.clear()
	for s: Streets.Street in world.streets.streets:
		_s[s.key] = JSON.stringify(world.streets.street_data(s))
	land.take_touched()
	active = true


func end() -> void:
	active = false


func _process(delta: float) -> void:
	if not active or not Net.in_room():
		return
	_timer += delta
	if _timer < SEND_EVERY:
		return
	_timer = 0.0
	var patch := changes()
	if not patch.is_empty():
		Firebase.db_patch("rooms/%s/island" % Net.room_code, patch)


## What changed here since the room last heard, as multi-path updates.
func changes() -> Dictionary:
	var out := {}
	var land := world.land
	var box := land.take_touched()
	if box.size.x > 0:
		for z in range(box.position.y, mini(box.end.y, Land.SIDE)):
			for x in range(box.position.x, mini(box.end.x, Land.SIDE)):
				var k := z * Land.SIDE + x
				if absf(land.heights[k] - _h[k]) > 0.004:
					_h[k] = land.heights[k]
					var d := land.heights[k] - land.base_height(k)
					out["land/c%d" % k] = snappedf(d, 0.01) if absf(d) > 0.005 else null
				if absf(land.zone[k] - _z[k]) > 0.004:
					_z[k] = land.zone[k]
					out["zone/c%d" % k] = snappedf(land.zone[k], 0.01) if land.zone[k] > 0.005 else null
				if absf(land.green[k] - _g[k]) > 0.004:
					_g[k] = land.green[k]
					out["green/c%d" % k] = snappedf(land.green[k], 0.01) if land.green[k] > 0.005 else null
	var seen := {}
	for s: Streets.Street in world.streets.streets:
		seen[s.key] = true
		# streets still being laid send once they have settled
		if world.streets.is_settling(s):
			continue
		var d := world.streets.street_data(s)
		var js := JSON.stringify(d)
		if _s.get(s.key, "") != js:
			_s[s.key] = js
			out["streets/" + s.key] = d
	for key in _s.keys():
		if not seen.has(key):
			_s.erase(key)
			out["streets/" + key] = null
	return out


## A change from the room's stream: `path` below island/, and its new value.
func apply(path: String, data: Variant) -> void:
	var parts := path.trim_prefix("/").trim_suffix("/").split("/", false)
	_apply(parts, data)


func _apply(parts: PackedStringArray, data: Variant) -> void:
	if parts.is_empty():
		if data is Dictionary:
			for k in data:
				_apply(str(k).split("/", false), data[k])
		return
	var head := parts[0]
	if head == "streets":
		if parts.size() == 1:
			if data is Dictionary:
				for k in data:
					_street(str(k), data[k])
		elif parts.size() == 2:
			_street(parts[1], data)
		return
	if not head in ["land", "zone", "green"]:
		return
	var values := {}
	if parts.size() == 1:
		if data is Dictionary:
			for k in data:
				values[str(k)] = data[k]
	elif parts.size() == 2:
		values[parts[1]] = data
	_samples(head, values)


func _samples(layer: String, values: Dictionary) -> void:
	var land := world.land
	var vals := {}
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for key in values:
		if not key.begins_with("c"):
			continue
		var k := int(key.substr(1))
		if k < 0 or k >= land.heights.size():
			continue
		var v := float(values[key]) if values[key] != null else 0.0
		var now: float
		match layer:
			"land":
				now = land.base_height(k) + v
				if absf(now - land.heights[k]) < 0.006:
					continue
				_h[k] = now
			"zone":
				if absf(v - land.zone[k]) < 0.006:
					continue
				_z[k] = v
			"green":
				if absf(v - land.green[k]) < 0.006:
					continue
				_g[k] = v
		vals[k] = v
		var p := Vector2((k % Land.SIDE) * Land.STEP - Land.HALF, (k / Land.SIDE) * Land.STEP - Land.HALF)
		lo = lo.min(p)
		hi = hi.max(p)
	if vals.is_empty():
		return
	land.set_samples(layer, vals)
	if layer != "land":
		# the town makes room, or builds, where the painting changed
		world.town.zone_changed((lo + hi) * 0.5, (hi - lo).length() * 0.5 + 2.0)
	world.ground_changed()


func _street(key: String, data: Variant) -> void:
	var streets := world.streets
	var s := streets.by_key(key)
	if data == null:
		_s.erase(key)
		if s:
			streets.remove_street(s)
		return
	if not data is Dictionary:
		return
	var js := JSON.stringify(data)
	if _s.get(key, "") == js:
		return
	_s[key] = js
	if s:
		if JSON.stringify(streets.street_data(s)) == js:
			return
		streets.remove_street(s)
	var d: Dictionary = data
	d["id"] = key
	streets.add_data(d)
