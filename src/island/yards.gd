class_name Yards
extends Node3D
## The space the town leaves between its buildings, lived in: back gardens
## with sheds, washing lines and vegetable patches behind the houses, paved
## courtyards with a tree and benches among the taller blocks, service yards
## with bins and a parked van behind offices, café terraces beside cafés and
## bakeries, and little greens with a bench wherever a patch is left over.
## Purely for looks: they fill whatever ground no plot or street has taken,
## and give way the moment a building grows or joins its neighbours into it.
## Everything follows from the island's seed and its town, so every co-op
## builder sees the same yards.

const SPAN := float(Land.TILE)
const CHUNKS := Land.TILES
# one candidate yard per GAP x GAP metres, nudged off the grid
const GAP := 2.0
const PER := int(SPAN / GAP)
# a yard needs this many free town cells round its middle (0.5 m each)
const FREE := 2
# and keeps this many cells off any street
const STREET_GAP := 2
# and this far off a building's walls
const WALL_GAP := 0.3
# how far it looks for the building it belongs to
const NEAR := 4.5
# the most yards one chunk holds
const MOST := 32
# where a corner may shift to when the spot itself is too tight; never so
# far that its little patch reaches a neighbouring yard's
const NUDGES: Array[Vector2] = [Vector2(0.5, 0), Vector2(-0.5, 0), Vector2(0, 0.5), Vector2(0, -0.5)]
# open ground counts as inside the town when buildings or streets lie
# within this many metres of it in most directions
const ENCLOSE := 11.0
const PAVING := Color(0.84, 0.8, 0.74)
const COBBLES := Color(0.72, 0.69, 0.65)
const YARD_TAR := Color(0.55, 0.56, 0.58)
const IRON := Color(0.22, 0.24, 0.27)
const WOOD := Color(0.55, 0.4, 0.28)

var world: IslandWorld
# the next chunk to fingerprint while looking for changes (-1: not looking)
var _scan := -1
var _near := {}
var _seed := 0
var _nodes := {}
var _sigs := {}
var _counts := {}
var _todo: Array[Vector2i] = []
var _job := {}
var _check := 1.0
var _seen := -1


func _process(delta: float) -> void:
	if not _job.is_empty():
		# laid out over a frame or two, then put up on a frame of its own
		if _job.has("done"):
			_finish(_job)
			_job = {}
		elif _work(_job, 3000):
			_job.done = true
		return
	if not _todo.is_empty():
		_job = _start(_todo.pop_back())
		return
	if _scan >= 0:
		_scan_some()
		return
	_check -= delta
	if _check > 0.0:
		return
	_check = 0.6
	if world.town.is_busy() or not world.land.is_settled():
		return
	var sig := hash([world.island_seed, world.land.revision, world.town.revision, world.town.lots.size(), world.town._next_id, world.streets.streets.size()])
	if sig != _seen:
		_seen = sig
		_queue_changed()


## Rebuilds every chunk now (a fresh island, a load, and tests).
func rebuild_all() -> void:
	_seed = world.island_seed
	_todo.clear()
	_job = {}
	_scan = -1
	var near := _lots_near()
	for cz in CHUNKS:
		for cx in CHUNKS:
			var c := Vector2i(cx, cz)
			_sigs[c] = _chunk_sig(c, near)
			_build(c)


func yard_count() -> int:
	var n := 0
	for c in _counts:
		n += _counts[c]
	return n


## Starts looking over the chunks for any whose yards need redoing: a few
## each frame (see _scan_some), so a big town never stalls one.
func _queue_changed() -> void:
	if _seed != world.island_seed:
		_seed = world.island_seed
		_sigs.clear()
	_near = _lots_near()
	_scan = 0


func _scan_some() -> void:
	var start := Time.get_ticks_usec()
	while _scan < CHUNKS * CHUNKS and Time.get_ticks_usec() - start < 2000:
		var c := Vector2i(_scan % CHUNKS, _scan / CHUNKS)
		_scan += 1
		var s := _chunk_sig(c, _near)
		if _sigs.get(c, -1) != s:
			_sigs[c] = s
			_todo.append(c)
	if _scan >= CHUNKS * CHUNKS:
		_scan = -1
		_near = {}


## A fingerprint of what a chunk's yards depend on: the town map round it
## (with a margin for the buildings they belong to) and the ground.
## Each building's fingerprint, filed under every chunk it stands near.
func _lots_near() -> Dictionary:
	var out := {}
	var m := NEAR + 8.0
	for l: Town.Lot in world.town.lots.values():
		var h := hash([l.id, l.foot, l.host, l.arrays.is_empty()])
		var a := Vector2i(((l.origin - Vector2(m, m)) + Vector2(Land.HALF, Land.HALF)) / SPAN)
		var b := Vector2i(((l.origin + Vector2(m, m)) + Vector2(Land.HALF, Land.HALF)) / SPAN)
		for cz in range(a.y, b.y + 1):
			for cx in range(a.x, b.x + 1):
				var c := Vector2i(cx, cz)
				if not out.has(c):
					out[c] = []
				out[c].append(h)
	return out


func _chunk_sig(c: Vector2i, near: Dictionary) -> int:
	var parts := [_seed]
	var cells := int(SPAN / Town.CELL)
	var m := int(NEAR / Town.CELL) + 2
	var ti0 := maxi(c.x * cells - m, 0)
	var ti1 := mini((c.x + 1) * cells + m, Town.RES)
	for tj in range(maxi(c.y * cells - m, 0), mini((c.y + 1) * cells + m, Town.RES)):
		parts.append(hash(world.town._occ.slice(tj * Town.RES + ti0, tj * Town.RES + ti1)))
	# and the buildings standing round it
	parts.append(hash(near.get(c, [])))
	parts.append(world.land.tile_sig(c))
	return hash(parts)


func _build(c: Vector2i) -> void:
	var job := _start(c)
	_work(job, -1)
	_finish(job)


## A chunk's yards are laid out a row of spots at a time (see _work), so a
## busy chunk spreads over a few frames instead of stalling one.
func _start(c: Vector2i) -> Dictionary:
	var mk := MeshKit.new()
	mk.quiet_sprites = true
	return {"c": c, "mk": mk, "rng": RandomNumberGenerator.new(), "j": 0, "n": 0}


## Lays out rows of the chunk's yards until done or `budget_us` is spent;
## true once the whole chunk is laid out.
func _work(job: Dictionary, budget_us: int) -> bool:
	var start := Time.get_ticks_usec()
	var c: Vector2i = job.c
	var mk: MeshKit = job.mk
	var rng: RandomNumberGenerator = job.rng
	var x0 := c.x * SPAN - Land.HALF
	var z0 := c.y * SPAN - Land.HALF
	while job.j < PER and job.n < MOST:
		var j: int = job.j
		job.j += 1
		for i in PER:
			rng.seed = hash([_seed, c, i, j, 5])
			var p := Vector2(x0 + (i + 0.5 + (rng.randf() - 0.5) * 0.3) * GAP, z0 + (j + 0.5 + (rng.randf() - 0.5) * 0.3) * GAP)
			var room := []
			var owner: Town.Lot = _owner_at(p, room)
			if owner == null and room.is_empty():
				# too near a street or a wall: a small corner a little aside may fit
				for nudge: Vector2 in NUDGES:
					owner = _owner_at(p + nudge, room)
					if owner:
						p += nudge
						room[0] = 1
						break
					room.clear()
			if owner == null:
				# open ground deep inside a block: a pocket park every so often
				if room.is_empty() or room[0] != -1 or (i + j) % 2 != 0 or not _enclosed(p):
					continue
				_pocket(mk, rng, p)
			elif room[0] < FREE:
				_corner(mk, rng, p, owner)
			else:
				_yard(mk, rng, p, owner)
			job.n += 1
			if job.n >= MOST:
				break
		if budget_us >= 0 and Time.get_ticks_usec() - start > budget_us:
			break
	return job.j >= PER or job.n >= MOST


## Swaps the chunk's old yards for the newly laid out ones.
func _finish(job: Dictionary) -> void:
	var c: Vector2i = job.c
	var mk: MeshKit = job.mk
	var n: int = job.n
	var old: Node3D = _nodes.get(c)
	if old:
		old.queue_free()
		_nodes.erase(c)
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
	for pair in [[mk.commit_blobs(), GeometryInstance3D.SHADOW_CASTING_SETTING_ON], [mk.commit_quiet(), GeometryInstance3D.SHADOW_CASTING_SETTING_OFF],
			[mk.commit_shadow(Palette.shadow_material()), GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY]]:
		if pair[0]:
			var mi := MeshInstance3D.new()
			mi.mesh = pair[0]
			mi.cast_shadow = pair[1]
			node.add_child(mi)


## The building a yard at p would belong to, if the ground there is free,
## level enough, off the streets and close to one; null otherwise. `room`
## gets how many free cells round p there are (1: a small corner, 2: a full yard).
func _owner_at(p: Vector2, room: Array) -> Town.Lot:
	var land := world.land
	if land.height_at(p.x, p.y) < 0.5 or land.normal_at(p.x, p.y).y < 0.86:
		return null
	var town := world.town
	var c := Town._cell(p)
	var r := int(NEAR / Town.CELL)
	if c.x - r < 0 or c.y - r < 0 or c.x + r >= Town.RES or c.y + r >= Town.RES:
		return null
	var best := -1
	var bd := INF
	var free := FREE
	for dj in range(-r, r + 1):
		for di in range(-r, r + 1):
			var o := town._occ[(c.y + dj) * Town.RES + c.x + di]
			if o == 0:
				continue
			var d2 := di * di + dj * dj
			if o < 0:
				# well off any street
				if absi(di) <= STREET_GAP and absi(dj) <= STREET_GAP:
					return null
				continue
			# a plot's ground left over round its building counts as free
			var on_building := true
			var l: Town.Lot = town.lots.get(o)
			if l and l.host != 0:
				l = town.lots.get(l.host, l)
			if l and l.arrays.is_empty():
				# a plot not built on yet is open ground for now
				on_building = false
			elif l and l.foot.has_area():
				var q := Vector2((c.x + di + 0.5) * Town.CELL - Land.HALF, (c.y + dj + 0.5) * Town.CELL - Land.HALF) - l.origin
				var local := Vector2(q.dot(Vector2(cos(l.yaw), -sin(l.yaw))), q.dot(Vector2(sin(l.yaw), cos(l.yaw))))
				on_building = l.foot.grow(WALL_GAP).has_point(local)
			if on_building and absi(di) <= free and absi(dj) <= free:
				# too tight for a full yard: a small corner, if even that fits
				if absi(di) <= 1 and absi(dj) <= 1:
					return null
				free = 1
			if d2 < bd:
				bd = d2
				best = o
	if best < 0:
		room.append(-1)
		return null
	if not town.lots.has(best):
		return null
	var l: Town.Lot = town.lots[best]
	if l.host != 0 and town.lots.has(l.host):
		l = town.lots[l.host]
	# only inside the town, not out in the fields round a lone house
	if land.zone_at(p.x, p.y) < 0.25 and l.type != "house":
		return null
	room.append(free)
	return l


## Whether open ground at p lies inside the town: buildings or streets
## within ENCLOSE metres in most directions round it, and either painted
## for growing or with buildings on most sides.
func _enclosed(p: Vector2) -> bool:
	var town := world.town
	var hits := 0
	var homes := 0
	for k in 8:
		var dir := Vector2.from_angle(TAU * k / 8.0)
		for d in range(1, int(ENCLOSE) + 1):
			var c := Town._cell(p + dir * d)
			if c.x < 0 or c.y < 0 or c.x >= Town.RES or c.y >= Town.RES:
				break
			var o := town._occ[c.y * Town.RES + c.x]
			if o != 0:
				hits += 1
				if o > 0:
					homes += 1
				break
	return hits >= 6 and (homes >= 2 or world.land.zone_at(p.x, p.y) >= 0.15)


## A pocket park on open ground in the middle of a block: a mown lawn with
## a gravel path across it, trees, a bench or two and a flower bed.
func _pocket(mk: MeshKit, rng: RandomNumberGenerator, p: Vector2) -> void:
	var y := world.land.height_at(p.x, p.y)
	mk.push_at(Vector3(p.x, y, p.y), (rng.randi() % 4) * PI * 0.5)
	_patch(mk, p, y, Vector2(0.98, 0.98), Palette.LEAF[rng.randi() % Palette.LEAF.size()].lightened(0.1), MeshKit.MOWN_X)
	mk.shadow = false
	var a := Vector3(-0.98, 0, 0.15)
	var b := Vector3(0.98, 0, -0.15)
	var pts: Array[Vector3] = []
	for c in [a + Vector3(0, 0, 0.14), b + Vector3(0, 0, 0.14), b - Vector3(0, 0, 0.14), a - Vector3(0, 0, 0.14)]:
		pts.append(Vector3(c.x, _ground(c, y, mk) + 0.035, c.z))
	mk.quad(pts[0], pts[1], pts[2], pts[3], Vector3.UP, Color(0.86, 0.8, 0.68))
	mk.shadow = true
	for k in 2 + rng.randi() % 2:
		var t := Vector3(rng.randf_range(-0.7, 0.7), 0, (-0.6 if k % 2 == 0 else 0.6) + rng.randf_range(-0.15, 0.15))
		_tree(mk, rng, t + Vector3(0, _ground(t, y, mk), 0), rng.randf_range(0.9, 1.25))
	var bc := Vector3(rng.randf_range(-0.4, 0.4), 0, -0.25)
	CivicGen._bench(mk, bc + Vector3(0, _ground(bc, y, mk), 0), 0.0)
	if rng.randf() < 0.5:
		var lc := Vector3(bc.x + 0.35, 0, -0.3)
		CivicGen._lamp(mk, lc + Vector3(0, _ground(lc, y, mk), 0))
	for k in 5:
		var c := Vector3(rng.randf_range(-0.8, 0.8), 0, rng.randf_range(0.35, 0.85) * (1.0 if k % 2 == 0 else -1.0))
		mk.blob(c + Vector3(0, _ground(c, y, mk) + 0.05, 0), Vector3(0.06, 0.05, 0.06), Palette.FLOWERS[rng.randi() % Palette.FLOWERS.size()], 0.03)
	mk.pop()


## Picks and lays out the yard at p for the building it belongs to.
func _yard(mk: MeshKit, rng: RandomNumberGenerator, p: Vector2, l: Town.Lot) -> void:
	var y := world.land.height_at(p.x, p.y)
	mk.push_at(Vector3(p.x, y, p.y), l.yaw + (rng.randi() % 2) * PI)
	var near := p.distance_to(l.origin)
	var tall := l.use == "office" or l.use == "retail" or l.group.size() > 1 or l.stage >= 3
	var roll := rng.randf()
	if (l.trade == "cafe" or l.trade == "bakery") and near < 5.0 and roll < 0.7:
		_terrace(mk, rng, p, y)
	elif l.type == "park" or l.type == "square" or l.type == "church" or l.type == "hall":
		_green(mk, rng, p, y)
	elif l.type == "school":
		if roll < 0.5:
			_green(mk, rng, p, y)
		else:
			_garden(mk, rng, p, y)
	elif l.use == "office" or l.use == "industry" or l.use == "retail":
		if roll < 0.55 or l.use == "industry":
			_service(mk, rng, p, y)
		else:
			_court(mk, rng, p, y)
	elif tall:
		if roll < 0.45:
			_court(mk, rng, p, y)
		elif roll < 0.7:
			_service(mk, rng, p, y)
		elif roll < 0.85:
			_green(mk, rng, p, y)
		else:
			_garden(mk, rng, p, y)
	else:
		if roll < 0.82:
			_garden(mk, rng, p, y)
		else:
			_green(mk, rng, p, y)
	mk.pop()


## A corner too small for a whole yard: one thing that fits a metre or so.
func _corner(mk: MeshKit, rng: RandomNumberGenerator, p: Vector2, l: Town.Lot) -> void:
	var y := world.land.height_at(p.x, p.y)
	mk.push_at(Vector3(p.x, y, p.y), l.yaw + (rng.randi() % 4) * PI * 0.5)
	var tall := l.use == "office" or l.use == "retail" or l.group.size() > 1 or l.stage >= 3
	var roll := rng.randf()
	if tall and roll < 0.35:
		# bins by a back door
		_patch(mk, p, y, Vector2(0.5, 0.4), YARD_TAR, MeshKit.ASPHALT)
		var bins := [Color("3d7a4a"), Color("5c6670"), Color("3d5f8f")]
		for k in 3:
			var b := Vector3(-0.18 + k * 0.18, _ground(Vector3(-0.18 + k * 0.18, 0, 0), y, mk), 0)
			mk.box(b + Vector3(0, 0.1, 0), Vector3(0.14, 0.2, 0.14), bins[(k + rng.randi()) % bins.size()])
	elif roll < 0.6:
		# a tree in a planter, or straight in the grass
		var c := Vector3(0, _ground(Vector3.ZERO, y, mk), 0)
		if tall:
			_patch(mk, p, y, Vector2(0.5, 0.5), PAVING, MeshKit.SLABS)
			mk.shadow = false
			mk.box_faces(c + Vector3(0, 0.08, 0), Vector3(0.42, 0.16, 0.42), Color(0.78, 0.74, 0.68), MeshKit.TOP | MeshKit.FRONT | MeshKit.BACK | MeshKit.LEFT | MeshKit.RIGHT)
			mk.shadow = true
			c.y += 0.16
		_tree(mk, rng, c, 0.85)
	elif roll < 0.8:
		# a bench under a lamp, on a little paved spot
		_patch(mk, p, y, Vector2(0.45, 0.35), PAVING, MeshKit.SLABS)
		CivicGen._bench(mk, Vector3(0, _ground(Vector3.ZERO, y, mk), 0), 0.0)
		CivicGen._lamp(mk, Vector3(0.38, _ground(Vector3(0.38, 0, -0.1), y, mk), -0.1))
	else:
		# shrubs and flowers
		for k in 3:
			var c := Vector3(rng.randf_range(-0.35, 0.35), 0, rng.randf_range(-0.35, 0.35))
			c.y = _ground(c, y, mk)
			mk.blob(c + Vector3(0, 0.12, 0), Vector3(0.17, 0.14, 0.17), Palette.LEAF[rng.randi() % Palette.LEAF.size()].darkened(0.1), 0.06)
		for k in 4:
			var c := Vector3(rng.randf_range(-0.4, 0.4), 0, rng.randf_range(-0.4, 0.4))
			mk.blob(c + Vector3(0, _ground(c, y, mk) + 0.05, 0), Vector3(0.05, 0.045, 0.05), Palette.FLOWERS[rng.randi() % Palette.FLOWERS.size()], 0.03)
	mk.pop()


# ------------------------------------------------------------------ ground

## A patch of ground cover laid over the lie of the land (yard-local, half
## size h), each corner at its own height so slopes never show a gap.
func _patch(mk: MeshKit, p: Vector2, y: float, h: Vector2, col: Color, e := 0.0) -> void:
	var xf := mk.xf
	var pts: Array[Vector3] = []
	for c in [Vector2(-h.x, h.y), Vector2(h.x, h.y), Vector2(h.x, -h.y), Vector2(-h.x, -h.y)]:
		var w := xf * Vector3(c.x, 0, c.y)
		pts.append(Vector3(c.x, world.land.height_at(w.x, w.z) - y + 0.025, c.y))
	var was := mk.shadow
	mk.shadow = false
	mk.quad(pts[0], pts[1], pts[2], pts[3], Vector3.UP, col, e)
	mk.shadow = was


func _ground(p: Vector3, y: float, mk: MeshKit) -> float:
	var w := mk.xf * Vector3(p.x, 0, p.z)
	return world.land.height_at(w.x, w.z) - y


# ------------------------------------------------------------------ yards

## A back garden: a lawn, a hedge or fence along one side, flowers, and one
## of a shed, a vegetable patch, washing, a trampoline or a paddling pool.
func _garden(mk: MeshKit, rng: RandomNumberGenerator, p: Vector2, y: float) -> void:
	var lawn: Color = Palette.LEAF[rng.randi() % Palette.LEAF.size()].lightened(0.08)
	_patch(mk, p, y, Vector2(0.92, 0.92), lawn)
	mk.shadow = false
	var hedge := rng.randf() < 0.5
	var fc: Color = Palette.LEAF[rng.randi() % Palette.LEAF.size()].darkened(0.25) if hedge else [Color(0.97, 0.97, 0.95), Color(0.62, 0.46, 0.33)][rng.randi() % 2]
	var fz := -0.92
	mk.box_faces(Vector3(0, _ground(Vector3(0, 0, fz), y, mk) + (0.09 if hedge else 0.065), fz), Vector3(1.84, 0.18 if hedge else 0.13, 0.1 if hedge else 0.03), fc,
		MeshKit.TOP | MeshKit.FRONT | MeshKit.BACK | MeshKit.LEFT | MeshKit.RIGHT)
	mk.shadow = true
	var roll := rng.randf()
	var side := -1.0 if rng.randf() < 0.5 else 1.0
	if roll < 0.24:
		# a garden shed
		var c := Vector3(side * 0.5, 0, -0.55)
		c.y = _ground(c, y, mk)
		var wall: Color = [Color("8a6a4f"), Color("6f8a6a"), Color("e8e2d4"), Color("5f7a94")][rng.randi() % 4]
		mk.box(c + Vector3(0, 0.22, 0), Vector3(0.56, 0.5, 0.44), wall)
		mk.box_faces(c + Vector3(0.1, 0.19, 0.225), Vector3(0.18, 0.34, 0.012), wall.darkened(0.3), MeshKit.FRONT)
		mk.window(c + Vector3(-0.15, 0.3, 0.222), Vector3.BACK, 0.12, 0.12, Palette.GLASS)
		mk.gable_roof(c + Vector3(0, 0.47, 0), 0.56, 0.44, 0.17, 0.05, Color("5a4a44"), wall, 0.03)
	elif roll < 0.44:
		# a vegetable patch in raised beds
		for k in 2:
			var c := Vector3(side * 0.35, 0, -0.45 + k * 0.5)
			c.y = _ground(c, y, mk)
			mk.shadow = false
			mk.box_faces(c + Vector3(0, 0.04, 0), Vector3(0.8, 0.08, 0.36), WOOD, MeshKit.TOP | MeshKit.FRONT | MeshKit.BACK | MeshKit.LEFT | MeshKit.RIGHT)
			mk.box_faces(c + Vector3(0, 0.085, 0), Vector3(0.74, 0.01, 0.3), Color(0.38, 0.27, 0.19), MeshKit.TOP)
			mk.shadow = true
			for j in 4:
				mk.blob(c + Vector3(-0.27 + j * 0.18, 0.13, 0), Vector3(0.07, 0.06, 0.07), Color("5e9e48").lightened(0.06 * ((j + k) % 3)), 0.02)
	elif roll < 0.62:
		# washing out on a line
		var za := 0.6
		var zc := -0.6
		var x := side * 0.55
		var ya := _ground(Vector3(x, 0, za), y, mk)
		var yb := _ground(Vector3(x, 0, zc), y, mk)
		mk.pole(Vector3(x, ya, za), 0.012, 0.62, 3, Color(0.85, 0.85, 0.85))
		mk.pole(Vector3(x, yb, zc), 0.012, 0.62, 3, Color(0.85, 0.85, 0.85))
		var top := (ya + yb) * 0.5 + 0.6
		mk.box_faces(Vector3(x, top, 0), Vector3(0.008, 0.008, za - zc), Color(0.9, 0.9, 0.9), MeshKit.TOP | MeshKit.LEFT)
		for k in 4:
			var z := lerpf(zc + 0.15, za - 0.15, (k + 0.5) / 4.0)
			var cw := rng.randf_range(0.14, 0.22)
			var ch := rng.randf_range(0.12, 0.2)
			mk.box_faces(Vector3(x, top - ch * 0.5, z), Vector3(0.01, ch, cw), Palette.LAUNDRY[rng.randi() % Palette.LAUNDRY.size()], MeshKit.LEFT | MeshKit.RIGHT)
	elif roll < 0.74:
		# a trampoline
		var c := Vector3(side * 0.35, 0, 0.1)
		c.y = _ground(c, y, mk)
		mk.cylinder(c + Vector3(0, 0.16, 0), 0.32, 0.03, 10, Color(0.3, 0.55, 0.8), true, Color(0.2, 0.26, 0.34))
		for k in 3:
			var a := TAU * k / 3.0
			mk.pole(c + Vector3(cos(a) * 0.34, 0, sin(a) * 0.34), 0.012, 0.16, 3, Color(0.3, 0.55, 0.8))
	elif roll < 0.84:
		# a paddling pool and a sun lounger
		var c := Vector3(side * 0.3, 0, 0.15)
		c.y = _ground(c, y, mk)
		mk.cylinder(c, 0.3, 0.07, 10, Color("4b86d6"), true, Color("8fd0ee"))
		mk.box_faces(c + Vector3(-side * 0.5, 0.06, -0.1), Vector3(0.18, 0.04, 0.5), Color(0.96, 0.96, 0.94), MeshKit.TOP | MeshKit.FRONT | MeshKit.LEFT | MeshKit.RIGHT)
	else:
		# a fruit tree
		var c := Vector3(side * 0.4, 0, 0.0)
		c.y = _ground(c, y, mk)
		_tree(mk, rng, c, 0.85)
		for k in 3:
			mk.blob(c + Vector3(rng.randf_range(-0.3, 0.3), 0.72, rng.randf_range(-0.3, 0.3)), Vector3(0.04, 0.04, 0.04), Color("e8503a") if rng.randf() < 0.6 else Color("f2b33d"))
	# flowers along the hedge
	for k in 4:
		var c := Vector3(-0.7 + k * 0.45 + rng.randf_range(-0.1, 0.1), 0, -0.75)
		mk.blob(c + Vector3(0, _ground(c, y, mk) + 0.06, 0), Vector3(0.06, 0.05, 0.06), Palette.FLOWERS[rng.randi() % Palette.FLOWERS.size()], 0.03)


## A paved courtyard among taller buildings: a tree in a raised planter,
## benches, bicycles and pots of flowers.
func _court(mk: MeshKit, rng: RandomNumberGenerator, p: Vector2, y: float) -> void:
	_patch(mk, p, y, Vector2(0.95, 0.95), PAVING if rng.randf() < 0.6 else COBBLES, MeshKit.SLABS)
	var c := Vector3(0, _ground(Vector3.ZERO, y, mk), 0)
	mk.shadow = false
	mk.box_faces(c + Vector3(0, 0.08, 0), Vector3(0.5, 0.16, 0.5), Color(0.78, 0.74, 0.68), MeshKit.TOP | MeshKit.FRONT | MeshKit.BACK | MeshKit.LEFT | MeshKit.RIGHT)
	mk.box_faces(c + Vector3(0, 0.165, 0), Vector3(0.42, 0.01, 0.42), Color(0.36, 0.27, 0.2), MeshKit.TOP)
	mk.shadow = true
	_tree(mk, rng, c + Vector3(0, 0.16, 0), 1.0)
	for sx: float in [-1.0, 1.0]:
		if rng.randf() < 0.7:
			var b := Vector3(sx * 0.6, 0, 0)
			CivicGen._bench(mk, b + Vector3(0, _ground(b, y, mk), 0), sx * PI * 0.5)
	if rng.randf() < 0.5:
		# a rack of bicycles
		var b := Vector3(0, 0, 0.7)
		b.y = _ground(b, y, mk)
		for k in 3:
			var bx := -0.25 + k * 0.25
			var bc: Color = [Color("e85d5d"), Color("4b86d6"), Color("3fae8c"), Color("1b1b1f")][rng.randi() % 4]
			mk.box_faces(b + Vector3(bx, 0.1, 0), Vector3(0.02, 0.1, 0.3), bc, MeshKit.LEFT | MeshKit.RIGHT | MeshKit.TOP)
			for wz: float in [-0.12, 0.12]:
				mk.cylinder(b + Vector3(bx - 0.01, 0.07, wz), 0.07, 0.02, 6, Color(0.15, 0.15, 0.17), false)
	for k in 2:
		var pc := Vector3((k * 2 - 1) * 0.75, 0, -0.75)
		pc.y = _ground(pc, y, mk)
		mk.cylinder(pc, 0.1, 0.14, 6, Color("c98a4b"), false)
		mk.blob(pc + Vector3(0, 0.2, 0), Vector3(0.11, 0.09, 0.11), Palette.FLOWERS[rng.randi() % Palette.FLOWERS.size()], 0.03)


## A service yard behind offices or a block: tarmac, bins, a parked van or
## car, and a stack of pallets.
func _service(mk: MeshKit, rng: RandomNumberGenerator, p: Vector2, y: float) -> void:
	_patch(mk, p, y, Vector2(0.95, 0.95), YARD_TAR, MeshKit.ASPHALT)
	# painted bay lines
	var g := _ground(Vector3.ZERO, y, mk)
	mk.shadow = false
	for sx: float in [-0.9, 0.0, 0.9]:
		mk.box_faces(Vector3(sx, g + 0.03, 0.2), Vector3(0.03, 0.0, 1.0), Color(0.95, 0.95, 0.92), MeshKit.TOP)
	mk.shadow = true
	# a car or a little van in one bay
	var bay := -0.45 if rng.randf() < 0.5 else 0.45
	var car: Color = Palette.AWNINGS[rng.randi() % Palette.AWNINGS.size()].lerp(Color(0.9, 0.9, 0.9), 0.25)
	var c := Vector3(bay, g, 0.2)
	if rng.randf() < 0.65:
		mk.rbox(c + Vector3(0, 0.15, 0), Vector3(0.38, 0.16, 0.8), 0.05, car)
		mk.rbox(c + Vector3(0, 0.29, -0.05), Vector3(0.34, 0.13, 0.42), 0.05, car.lightened(0.1))
		mk.box_faces(c + Vector3(0, 0.29, 0.165), Vector3(0.3, 0.1, 0.01), Palette.GLASS, MeshKit.FRONT)
	else:
		mk.rbox(c + Vector3(0, 0.24, 0), Vector3(0.4, 0.36, 0.86), 0.05, Color(0.95, 0.95, 0.93))
		mk.box_faces(c + Vector3(0, 0.33, 0.432), Vector3(0.34, 0.12, 0.01), Palette.GLASS, MeshKit.FRONT)
		mk.box_faces(c + Vector3(0.201, 0.22, -0.05), Vector3(0.01, 0.1, 0.5), car, MeshKit.RIGHT)
	for wz: float in [-0.25, 0.25]:
		for wx: float in [-0.2, 0.2]:
			mk.cylinder(c + Vector3(wx - 0.01, 0.07, wz), 0.07, 0.02, 6, Color(0.12, 0.12, 0.14), false)
	# a row of wheelie bins against the far side
	var bins := [Color("3d7a4a"), Color("5c6670"), Color("3d5f8f"), Color("8a6a3c")]
	for k in 3:
		var b := Vector3(-bay * 1.1 - 0.15 + k * 0.17, g, -0.8)
		mk.box(b + Vector3(0, 0.1, 0), Vector3(0.14, 0.2, 0.14), bins[(k + rng.randi()) % bins.size()])
	if rng.randf() < 0.6:
		# pallets and crates
		var b := Vector3(-bay * 1.1, g, 0.6)
		mk.box_faces(b + Vector3(0, 0.04, 0), Vector3(0.3, 0.08, 0.3), WOOD, MeshKit.TOP | MeshKit.FRONT | MeshKit.LEFT | MeshKit.RIGHT | MeshKit.BACK)
		mk.box_faces(b + Vector3(0.02, 0.15, -0.02), Vector3(0.22, 0.14, 0.22), Color("a87b50"), MeshKit.TOP | MeshKit.FRONT | MeshKit.LEFT | MeshKit.RIGHT | MeshKit.BACK)


## A café terrace: paving, tables under parasols with chairs round them,
## planters, and a string of lights overhead that glows at night.
func _terrace(mk: MeshKit, rng: RandomNumberGenerator, p: Vector2, y: float) -> void:
	_patch(mk, p, y, Vector2(0.95, 0.95), PAVING.lerp(Color(0.86, 0.7, 0.58), 0.35), MeshKit.SLABS)
	var g := _ground(Vector3.ZERO, y, mk)
	var awn: Color = Palette.AWNINGS[rng.randi() % Palette.AWNINGS.size()]
	for k in 3:
		var c := Vector3(-0.55 + k * 0.55, g, (k % 2) * 0.5 - 0.2)
		mk.box_faces(c + Vector3(0, 0.12, 0), Vector3(0.18, 0.02, 0.18), Color(0.96, 0.96, 0.94), MeshKit.TOP | MeshKit.FRONT | MeshKit.BACK | MeshKit.LEFT | MeshKit.RIGHT)
		mk.pole(c, 0.01, 0.4, 4, IRON)
		mk.cone(c + Vector3(0, 0.34, 0), 0.24, 0.1, 8, awn if k % 2 == 0 else Color(0.98, 0.97, 0.94))
		for sx: float in [-1.0, 1.0]:
			mk.box_faces(c + Vector3(sx * 0.17, 0.07, 0), Vector3(0.08, 0.02, 0.08), WOOD, MeshKit.TOP | MeshKit.FRONT | MeshKit.LEFT | MeshKit.RIGHT)
			mk.box_faces(c + Vector3(sx * 0.21, 0.12, 0), Vector3(0.01, 0.1, 0.08), WOOD, MeshKit.LEFT | MeshKit.RIGHT)
	# planters round the edge
	for k in 3:
		var c := Vector3(-0.7 + k * 0.7, g, -0.85)
		mk.box_faces(c + Vector3(0, 0.07, 0), Vector3(0.32, 0.14, 0.14), Color(0.42, 0.44, 0.47), MeshKit.TOP | MeshKit.FRONT | MeshKit.BACK | MeshKit.LEFT | MeshKit.RIGHT)
		mk.blob(c + Vector3(0, 0.18, 0), Vector3(0.15, 0.08, 0.08), Palette.LEAF[k % Palette.LEAF.size()], 0.03)
	# festoon lights between two posts
	for sx: float in [-1.0, 1.0]:
		mk.pole(Vector3(sx * 0.9, g, 0.85), 0.012, 0.62, 3, IRON)
	mk.shadow = false
	mk.box_faces(Vector3(0, g + 0.6, 0.85), Vector3(1.8, 0.006, 0.006), IRON, MeshKit.TOP | MeshKit.FRONT)
	for k in 6:
		mk.box(Vector3(-0.75 + k * 0.3, g + 0.585, 0.85), Vector3(0.03, 0.03, 0.03), Color(1.0, 0.86, 0.55), null, false, 2.0)
	mk.shadow = true


## A little green: grass, a tree or two, a bench and a round flower bed.
func _green(mk: MeshKit, rng: RandomNumberGenerator, p: Vector2, y: float) -> void:
	_patch(mk, p, y, Vector2(0.95, 0.95), Palette.LEAF[rng.randi() % Palette.LEAF.size()].lightened(0.12), MeshKit.MOWN_X)
	var t := Vector3(rng.randf_range(-0.4, 0.4), 0, -0.4)
	_tree(mk, rng, t + Vector3(0, _ground(t, y, mk), 0), 1.1)
	if rng.randf() < 0.5:
		var t2 := Vector3(-t.x - 0.2, 0, 0.5)
		_tree(mk, rng, t2 + Vector3(0, _ground(t2, y, mk), 0), 0.8)
	var b := Vector3(0.5, 0, 0.35)
	CivicGen._bench(mk, b + Vector3(0, _ground(b, y, mk), 0), -PI * 0.5)
	var f := Vector3(-0.35, 0, 0.3)
	f.y = _ground(f, y, mk)
	mk.shadow = false
	mk.cylinder(f, 0.28, 0.06, 10, Color(0.8, 0.76, 0.7), true, Color(0.36, 0.27, 0.2))
	mk.shadow = true
	for k in 6:
		var a := TAU * k / 6.0
		mk.blob(f + Vector3(cos(a) * 0.16, 0.1, sin(a) * 0.16), Vector3(0.06, 0.05, 0.06), Palette.FLOWERS[(k + rng.randi()) % Palette.FLOWERS.size()], 0.03)


func _tree(mk: MeshKit, rng: RandomNumberGenerator, at: Vector3, s: float) -> void:
	s *= lerpf(0.85, 1.2, rng.randf())
	var leaf: Color = Palette.LEAF[rng.randi() % Palette.LEAF.size()]
	if rng.randf() < 0.12:
		leaf = Palette.BLOSSOM[rng.randi() % Palette.BLOSSOM.size()]
	mk.pole(at, 0.05 * s, 0.55 * s, 5, Color(0.45, 0.33, 0.24))
	mk.blob(at + Vector3(0, 0.78 * s, 0), Vector3(0.44, 0.4, 0.44) * s, leaf, 0.1)
	mk.blob(at + Vector3(0.18 * s, 1.02 * s, -0.05), Vector3(0.3, 0.27, 0.3) * s, leaf.lightened(0.08), 0.1)
