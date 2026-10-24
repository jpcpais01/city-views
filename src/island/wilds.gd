class_name Wilds
extends Node3D
## The countryside the town hasn't reached: woods on the hills, copses and lone
## trees in the meadows, pines up high, and a wood wherever green is painted
## away from the streets. Trees keep off the beaches, bare rock, the streets and
## anything built, and give way to the town where Grow is painted, so the town
## clears its own ground as it spreads. Everything follows from the island's
## seed, ground, painting and town, so every co-op builder sees the same woods.

const SPAN := float(Land.TILE)
const CHUNKS := Land.TILES
# one candidate spot per GAP x GAP metres, nudged off the grid
const GAP := 1.8
const PER := int(SPAN / GAP)
# how far a trunk keeps from anything built, and from a street's edge
const CLEAR := 0.75
const ROADSIDE := 1.25
# the most trees one chunk holds, so even an island painted all green stays cheap
const MOST := 36
const TRUNK := Color(0.42, 0.31, 0.22)
const PINE := [Color("3f7d4e"), Color("356f45"), Color("4a8a55")]

var world: IslandWorld
# the next chunk to fingerprint while looking for changes (-1: not looking)
var _scan := -1
var _woods := FastNoiseLite.new()
var _mix := FastNoiseLite.new()
var _seed := 0
var _nodes := {}
# what each chunk was built from, to know when to build it again
var _sigs := {}
var _counts := {}
var _todo: Array[Vector2i] = []
var _check := 1.0
var _seen := -1


func _process(delta: float) -> void:
	if not _todo.is_empty():
		# a few chunks a frame keeps the frame time flat
		var start := Time.get_ticks_usec()
		while not _todo.is_empty() and Time.get_ticks_usec() - start < 2500:
			_build(_todo.pop_back())
		return
	if _scan >= 0:
		_scan_some()
		return
	_check -= delta
	if _check > 0.0:
		return
	_check = 1.0
	if world.town.is_busy() or not world.land.is_settled():
		return
	var sig := hash([world.island_seed, world.land.revision, world.town.lots.size(), world.town._next_id, world.streets.streets.size(), world.town._reserved.size()])
	if sig != _seen:
		_seen = sig
		_queue_changed()


## Rebuilds every chunk now (a fresh island, a load, and tests).
func rebuild_all() -> void:
	_reseed()
	_todo.clear()
	_scan = -1
	for cz in CHUNKS:
		for cx in CHUNKS:
			var c := Vector2i(cx, cz)
			_sigs[c] = _chunk_sig(c)
			_build(c)


func tree_count() -> int:
	var n := 0
	for c in _counts:
		n += _counts[c]
	return n


func _reseed() -> void:
	if _seed == world.island_seed and _woods.seed == _seed + 71:
		return
	_seed = world.island_seed
	_woods.seed = _seed + 71
	_woods.frequency = 0.035
	_woods.fractal_octaves = 3
	_mix.seed = _seed + 83
	_mix.frequency = 0.08
	_sigs.clear()


## Starts looking over the chunks for any whose trees need redoing, a few
## each frame (see _scan_some).
func _queue_changed() -> void:
	_reseed()
	_scan = 0


func _scan_some() -> void:
	var start := Time.get_ticks_usec()
	while _scan < CHUNKS * CHUNKS and Time.get_ticks_usec() - start < 2000:
		var c := Vector2i(_scan % CHUNKS, _scan / CHUNKS)
		_scan += 1
		var s := _chunk_sig(c)
		if _sigs.get(c, -1) != s:
			_sigs[c] = s
			_todo.append(c)
	if _scan >= CHUNKS * CHUNKS:
		_scan = -1


## A fingerprint of everything a chunk's trees depend on: the ground and its
## painting there, and what the town has built there.
func _chunk_sig(c: Vector2i) -> int:
	var land := world.land
	var parts := [_seed]
	parts.append(land.tile_sig(c))
	# the town map, with a margin for the clearance round the chunk's edge
	var cells := int(SPAN / Town.CELL)
	var m := 4
	var ti0 := maxi(c.x * cells - m, 0)
	var ti1 := mini((c.x + 1) * cells + m, Town.RES)
	for tj in range(maxi(c.y * cells - m, 0), mini((c.y + 1) * cells + m, Town.RES)):
		parts.append(hash(world.town._occ.slice(tj * Town.RES + ti0, tj * Town.RES + ti1)))
	return hash(parts)


func _build(c: Vector2i) -> void:
	var old: Node3D = _nodes.get(c)
	if old:
		old.queue_free()
		_nodes.erase(c)
	var mk := MeshKit.new()
	# trunks are too thin to cast a shadow worth drawing
	mk.quiet_sprites = true
	var n := 0
	var x0 := c.x * SPAN - Land.HALF
	var z0 := c.y * SPAN - Land.HALF
	var rng := RandomNumberGenerator.new()
	for j in PER:
		for i in PER:
			rng.seed = hash([_seed, c, i, j])
			var x := x0 + (i + 0.5 + (rng.randf() - 0.5) * 0.85) * GAP
			var z := z0 + (j + 0.5 + (rng.randf() - 0.5) * 0.85) * GAP
			var keep := rng.randf()
			var kind := _spot(x, z, keep)
			if kind < 0:
				continue
			_tree(mk, rng, Vector3(x, world.land.height_at(x, z) - 0.04, z), kind)
			n += 1
			if n >= MOST:
				break
		if n >= MOST:
			break
	_counts[c] = n
	if n == 0:
		return
	var node := Node3D.new()
	add_child(node)
	_nodes[c] = node
	var body := MeshInstance3D.new()
	body.mesh = mk.commit(world.city_mat, false)
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(body)
	var crowns := mk.commit_blobs()
	if crowns:
		var mi := MeshInstance3D.new()
		mi.mesh = crowns
		node.add_child(mi)
	var trunks := mk.commit_quiet()
	if trunks:
		var mi := MeshInstance3D.new()
		mi.mesh = trunks
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(mi)
	var sm := mk.commit_shadow(Palette.shadow_material())
	if sm:
		var sh := MeshInstance3D.new()
		sh.mesh = sm
		sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		node.add_child(sh)


## What grows at a spot: -1 nothing, 0 a broadleaf tree, 1 a pine.
## `keep` is the spot's own dice roll against how wooded the ground is there.
func _spot(x: float, z: float, keep: float) -> int:
	var land := world.land
	var h := land.height_at(x, z)
	# no trees on the sand or in the surf
	if h < 0.5:
		return -1
	# nor on rock too steep to hold them
	if land.normal_at(x, z).y < 0.84:
		return -1
	var green := land.green_at(x, z)
	# ground painted for the town is left for the town
	if land.zone_at(x, z) > 0.15 and green < 0.3:
		return -1
	if green < 0.3 and land.farm_at(x, z):
		# fields stay open, with now and then a tree in the hedge round one
		return 0 if land.field_edge(x, z) < 0.5 and keep < 0.1 else -1
	var woods := smoothstep(-0.02, 0.3, _woods.get_noise_2d(x, z))
	# a few lone trees anywhere, woods where the noise says, thick where green is painted
	var dense := 0.03 + maxf(woods * 0.85, green * 0.9)
	# thinning out towards the shore and the windswept tops
	dense *= smoothstep(0.5, 1.6, h) * (1.0 - smoothstep(8.5, 10.5, h) * 0.8)
	if keep > dense:
		return -1
	if _blocked(x, z):
		return -1
	# pines take over higher up, in stands of their own
	var pine := smoothstep(2.5, 6.5, h) * 0.75 + _mix.get_noise_2d(x, z) * 0.45
	return 1 if pine > 0.45 else 0


## Whether a trunk here would stand on or right beside a street, a plot or
## ground kept for a landmark.
func _blocked(x: float, z: float) -> bool:
	var town := world.town
	var c := Town._cell(Vector2(x, z))
	var r := int(ceil(ROADSIDE / Town.CELL))
	var rc := int(ceil(CLEAR / Town.CELL))
	for dj in range(-r, r + 1):
		var j := c.y + dj
		if j < 0 or j >= Town.RES:
			continue
		for di in range(-r, r + 1):
			var i := c.x + di
			if i < 0 or i >= Town.RES:
				continue
			var o := town._occ[j * Town.RES + i]
			if o == 0:
				continue
			# streets (negative ids, not landmark ground) keep a wider verge
			if o < 0 and o != Town.RESERVED:
				return true
			if absi(di) <= rc and absi(dj) <= rc:
				return true
	return false


func _tree(mk: MeshKit, rng: RandomNumberGenerator, at: Vector3, kind: int) -> void:
	var s := lerpf(1.05, 1.7, rng.randf())
	if kind == 1:
		var col: Color = PINE[rng.randi() % PINE.size()]
		mk.pole(at, 0.05 * s, 0.4 * s, 4, TRUNK)
		mk.cone(at + Vector3(0, 0.22 * s, 0), 0.4 * s, 0.85 * s, 6, col)
		mk.cone(at + Vector3(0, 0.62 * s, 0), 0.29 * s, 0.75 * s, 6, col.lightened(0.06))
		return
	var leaf: Color = Palette.LEAF[rng.randi() % Palette.LEAF.size()]
	leaf = leaf.darkened(rng.randf() * 0.12)
	if rng.randf() < 0.04:
		leaf = Palette.BLOSSOM[rng.randi() % Palette.BLOSSOM.size()]
	mk.pole(at, 0.06 * s, 0.6 * s, 5, TRUNK)
	mk.blob(at + Vector3(0, 0.82 * s, 0), Vector3(0.5, 0.46, 0.5) * s, leaf, 0.1)
	var side := rng.randf() * TAU
	mk.blob(at + Vector3(cos(side) * 0.2 * s, 1.08 * s, sin(side) * 0.2 * s), Vector3(0.33, 0.3, 0.33) * s, leaf.lightened(0.07), 0.1)
