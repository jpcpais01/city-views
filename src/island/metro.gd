class_name Metro
extends Node3D
## The metro, once the city is big enough: station entrances on the
## pavements of the main streets and avenues where towers stand, each a
## stair going down under a glass canopy with railings round it and the
## metro's sign lit on a pole at the kerb. Worked out from the streets and
## the town alone, so every co-op builder sees the same stations.

## the residents a city needs before its metro opens
const NEED := 6000
## how far apart the entrances along one street are, in samples, and how
## far in the first is
const GAP := 110
const FIRST := 30
## half an entrance's length along the street, in samples
const HALF := 0.8
## how close to a tower (or a tall block) an entrance has to be
const NEAR := 7.0
const DARK := Color(0.09, 0.09, 0.11)
const STEP := Color(0.32, 0.32, 0.34)
const GLASS := Color(0.6, 0.72, 0.78)
const FRAME := Color(0.2, 0.26, 0.3)
const SIGN := Color(0.18, 0.42, 0.9)

var world: IslandWorld
## where the entrances stand (for tests and the city panel)
var spots := PackedVector3Array()
var _node: Node3D
var _seen := -1
var _check := 1.0
var _open := false


func _process(delta: float) -> void:
	_check -= delta
	if _check > 0.0:
		return
	_check = 1.5
	if world.town.is_busy() or not world.land.is_settled():
		return
	var open := world.progress.residents >= NEED
	var sig := hash([open, world.town.revision, world.town.lots.size(), world.streets.streets.size(), world.land.revision])
	if sig == _seen:
		return
	_seen = sig
	rebuild()
	if open and not _open and not spots.is_empty() and world.progress._hush <= 0.0:
		world.note.emit("The metro is open: stations along the downtown avenues", "title")
		Sfx.play("unlock", 0.9)
	_open = open and not spots.is_empty()


## Lays out every entrance again (a change to the town or the streets, a
## load, and tests).
func rebuild() -> void:
	if _node:
		_node.queue_free()
		_node = null
	spots.clear()
	if world.progress.residents < NEED:
		return
	# the towers and tall blocks, where the stations go
	var tall := PackedVector2Array()
	for l: Town.Lot in world.town.lots.values():
		if l.type == "house" and l.stage >= 5 and l.host == 0 and not l.arrays.is_empty():
			tall.append(l.origin)
	if tall.is_empty():
		return
	var mk := MeshKit.new(world.island_seed)
	mk.quiet_sprites = true
	var st := world.streets
	for s: Streets.Street in st.streets:
		if s.kind != "main" and s.kind != "avenue":
			continue
		var g := BridgeGen.Geo.new(st, s)
		var n := s.pts.size()
		for side: float in [1.0, -1.0]:
			var f := float(FIRST + (0 if side > 0.0 else GAP / 2))
			while f < n - FIRST:
				var off := side * (s.w() + Streets.PAVE * 0.5)
				var at := g.at(f, off, 0.0)
				if _clear(s, f, side) and _near(tall, Vector2(at.x, at.z)) and _off_others(s, Vector2(at.x, at.z)):
					_entrance(mk, g, s, f, side)
					spots.append(at)
					f += GAP
				else:
					f += 6.0
	if spots.is_empty():
		return
	_node = Node3D.new()
	add_child(_node)
	var body := MeshInstance3D.new()
	body.mesh = mk.commit(world.city_mat, false)
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_node.add_child(body)
	# the posts (thin enough to be drawn as poles), and the shadows
	for pair in [[mk.commit_blobs(), GeometryInstance3D.SHADOW_CASTING_SETTING_ON], [mk.commit_quiet(), GeometryInstance3D.SHADOW_CASTING_SETTING_OFF],
			[mk.commit_shadow(Palette.shadow_material()), GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY]]:
		if pair[0]:
			var mi := MeshInstance3D.new()
			mi.mesh = pair[0]
			mi.cast_shadow = pair[1]
			_node.add_child(mi)


## Whether the pavement at f on `side` is free: no junction corner, bridge,
## flyover, tunnel, quay or bus stop near it.
func _clear(s: Streets.Street, f: float, side: float) -> bool:
	var lists: Array[PackedVector2Array] = [s.spans, s.overs, s.tunnels]
	if s.cuts.has(side):
		lists.append(s.cuts[side])
	for list in lists:
		for c in list:
			if f > c.x - HALF - 4.0 and f < c.y + HALF + 4.0:
				return false
	for stop in s.stops:
		if stop.y == side and absf(stop.x - f) < 8.0:
			return false
	if not s.quay.is_empty():
		var q := s.quay[clampi(int(f), 0, s.quay.size() - 1)]
		if q & (1 if side < 0.0 else 2):
			return false
	return true


func _near(tall: PackedVector2Array, p: Vector2) -> bool:
	for q in tall:
		if q.distance_squared_to(p) < NEAR * NEAR:
			return true
	return false


## Not on another street's carriageway (where two run close or meet).
func _off_others(s: Streets.Street, p: Vector2) -> bool:
	for o: Streets.Street in world.streets.streets:
		if o == s or not o.near_box(p, 3.0):
			continue
		if o.closest(p).x < o.reach() + 0.3:
			return false
	return true


## One entrance: the stair going down into the pavement, glass railings
## round three sides, a glass canopy on two posts and the lit sign at the kerb.
func _entrance(mk: MeshKit, g: BridgeGen.Geo, s: Streets.Street, f: float, side: float) -> void:
	var walk := g.walk()
	var inner := side * (s.w() + 0.1)
	var outer := side * (s.w() + Streets.PAVE - 0.04)
	var f0 := f - HALF
	var f1 := f + HALF
	var up := Vector3.UP
	var along := (g.at(f1, 0.0, 0.0) - g.at(f0, 0.0, 0.0)).normalized()
	var out := (g.at(f, side, 0.0) - g.at(f, 0.0, 0.0)).normalized()
	# the stair: dark at the bottom, steps catching the light near the top
	mk.shadow = false
	mk.quad(g.at(f0, inner, walk + 0.004), g.at(f1, inner, walk + 0.004), g.at(f1, outer, walk + 0.004), g.at(f0, outer, walk + 0.004), up, DARK)
	for k in 3:
		var t0 := lerpf(f0, f1, 0.55 + k * 0.15)
		var t1 := t0 + (f1 - f0) * 0.06
		mk.quad(g.at(t0, inner, walk + 0.006), g.at(t1, inner, walk + 0.006), g.at(t1, outer, walk + 0.006), g.at(t0, outer, walk + 0.006), up, STEP.lightened(k * 0.12))
	mk.shadow = true
	# railings of glass along both sides and across the closed end
	var rh := 0.13
	for o: float in [inner, outer]:
		var face := -out * signf(o - (inner + outer) * 0.5) * side
		mk.quad(g.at(f0, o, walk), g.at(f1, o, walk), g.at(f1, o, walk + rh), g.at(f0, o, walk + rh), face, GLASS, 1.0)
		mk.quad(g.at(f1, o, walk), g.at(f0, o, walk), g.at(f0, o, walk + rh), g.at(f1, o, walk + rh), -face, GLASS, 1.0)
	mk.quad(g.at(f0, outer, walk), g.at(f0, inner, walk), g.at(f0, inner, walk + rh), g.at(f0, outer, walk + rh), -along, GLASS, 1.0)
	mk.quad(g.at(f0, inner, walk), g.at(f0, outer, walk), g.at(f0, outer, walk + rh), g.at(f0, inner, walk + rh), along, GLASS, 1.0)
	# the canopy, rising towards the open end, on posts at its corners
	var c0 := walk + 0.36
	var c1 := walk + 0.42
	mk.quad(g.at(f0, inner, c0), g.at(f1, inner, c1), g.at(f1, outer, c1), g.at(f0, outer, c0), up, GLASS, 1.0)
	mk.quad(g.at(f0, outer, c0), g.at(f1, outer, c1), g.at(f1, inner, c1), g.at(f0, inner, c0), -up, FRAME)
	for o: float in [inner, outer]:
		for fp: float in [f0 + 0.05, f1 - 0.05]:
			var b := g.at(fp, o, walk)
			var top := c0 + (c1 - c0) * (fp - f0) / (f1 - f0)
			mk.box(Vector3(b.x, b.y + (top - walk) * 0.5, b.z), Vector3(0.04, top - walk, 0.04), FRAME)
	# the canopy's edge, a dark frame round the glass
	mk.quad(g.at(f0, outer, c0 - 0.03), g.at(f1, outer, c1 - 0.03), g.at(f1, outer, c1), g.at(f0, outer, c0), out * side, FRAME)
	mk.quad(g.at(f1, inner, c1 - 0.03), g.at(f0, inner, c0 - 0.03), g.at(f0, inner, c0), g.at(f1, inner, c1), -out * side, FRAME)
	# the sign on its pole at the kerb, a little ahead of the stair, lit at night
	var fs := f1 + 0.6
	var kerb := g.at(fs, side * (s.w() + 0.08), walk)
	mk.box(kerb + Vector3(0, 0.27, 0), Vector3(0.04, 0.54, 0.04), FRAME)
	mk.box(kerb + Vector3(0, 0.6, 0), Vector3(0.11, 0.11, 0.11), SIGN, Color(0.95, 0.96, 0.98), false, 2.75)
