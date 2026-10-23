class_name NatureGen
extends RefCounted
## Trees and meadows. Woods grow thicker and taller towards their middle, palms
## lean out to sea, pines stretch up on the hills.

const PINES := [Color("3f7f4f"), Color("4b8b55"), Color("36704a")]


static func build(mk: MeshKit, x: int, z: int) -> void:
	match Game.sub(x, z):
		Game.NATURE.BROADLEAF: _broadleaf(mk, x, z)
		Game.NATURE.PINE: _pines(mk, x, z)
		Game.NATURE.PALM: _palms(mk, x, z)
		Game.NATURE.BLOSSOM: _blossom(mk, x, z)
		Game.NATURE.FLOWERS: _meadow(mk, x, z)
		_: CityGen._trees(mk, x, z)


## How deep inside a wood this tile is: 0 on its own, 1 surrounded by trees.
static func _depth(x: int, z: int) -> float:
	return CityGen.around(x, z, Game.K.TREE) / 8.0


static func _spot(x: int, z: int, k: int, spread := 1.3) -> Vector3:
	return Vector3(Game.hashf(x, z, 60 + k) * spread - spread * 0.5, 0.0, Game.hashf(x, z, 70 + k) * spread - spread * 0.5)


static func _broadleaf(mk: MeshKit, x: int, z: int) -> void:
	var deep := _depth(x, z)
	var count := 2 + int(deep * 2.5)
	for k in count:
		var s := 0.55 + Game.hashf(x, z, 80 + k) * 0.3 + deep * 0.2
		var col: Color = CityGen.pick(CityGen.LEAF, x, z, 110 + k)
		if Game.hashf(x, z, 120 + k) > 0.9:
			col = CityGen.pick(CityGen.AUTUMN, x, z, 130 + k)
		CityGen._round_tree(mk, _spot(x, z, k), s, col)
	# the edge of a wood is scrubby
	if deep < 0.4:
		for k in 2:
			mk.blob(_spot(x, z, 20 + k, 1.6) + Vector3(0, 0.08, 0), Vector3(0.18, 0.12, 0.16), Color("5c9e4e").lerp(Color("82c063"), k * 0.5), 0.04)


static func _pines(mk: MeshKit, x: int, z: int) -> void:
	var l := Game.lvl(x, z)
	var deep := _depth(x, z)
	var count := 2 + int(deep * 2.0) + (1 if l >= 4 else 0)
	for k in count:
		var s := (1.0 + Game.hashf(x, z, 80 + k) * 0.35) * (1.0 + maxi(l - 2, 0) * 0.1)
		CityGen._pine(mk, _spot(x, z, k), s, CityGen.pick(PINES, x, z, 100 + k))
	if l >= 3 and Game.hashf(x, z, 140) > 0.5:
		mk.pebble(_spot(x, z, 30, 1.4) + Vector3(0, 0.04, 0), Vector3(0.14, 0.09, 0.12), Color(0.66, 0.64, 0.6))


static func _palms(mk: MeshKit, x: int, z: int) -> void:
	var sd := CityGen.sea_dir(x, z, 4)
	var count := 1 + Game.hash2(x, z, 81) % 2
	for k in count:
		var p := _spot(x, z, k, 1.1)
		var s := 0.62 + Game.hashf(x, z, 82 + k) * 0.25
		CityGen._palm(mk, p, s, Game.hash2(x, z, 90 + k) % 100, sd)
	if Game.lvl(x, z) == 1:
		# dune grass round their feet
		for k in 4:
			var p := _spot(x, z, 40 + k, 1.6)
			mk.cone(p, 0.06, 0.22, 4, Color("9fbf6a"))


static func _blossom(mk: MeshKit, x: int, z: int) -> void:
	var count := 1 + Game.hash2(x, z, 81) % 2 + (1 if _depth(x, z) > 0.3 else 0)
	for k in count:
		var p := _spot(x, z, k)
		var s := 0.5 + Game.hashf(x, z, 83 + k) * 0.25
		mk.pole(p, 0.05 * s / 0.6, 0.38 * s / 0.6, 4, Color(0.45, 0.32, 0.28))
		var col: Color = CityGen.pick(CityGen.BLOSSOM, x, z, 84 + k)
		mk.blob(p + Vector3(0, 0.58 * s / 0.6, 0), Vector3(0.34, 0.32, 0.34) * s / 0.6, col, 0.06)
		# fallen petals on the grass under each tree
		for j in 2:
			var q := p + Vector3(Game.hashf(x, z, 200 + k * 4 + j) - 0.5, 0.012, Game.hashf(x, z, 210 + k * 4 + j) - 0.5) * 0.5
			mk.box_faces(q, Vector3(0.22, 0.004, 0.18), col.lightened(0.15), MeshKit.TOP)


static func _meadow(mk: MeshKit, x: int, z: int) -> void:
	# tall grass tufts and a scatter of wildflowers, never two meadows alike
	for k in 6:
		var p := _spot(x, z, 50 + k, 1.7)
		mk.cone(p, 0.05, 0.16 + Game.hashf(x, z, 300 + k) * 0.1, 4, Color("7cb35a").lerp(Color("a9c46a"), Game.hashf(x, z, 301 + k)))
	for k in 16:
		var p := _spot(x, z, 80 + k, 1.8)
		var col: Color = CityGen.FLOWERS[(Game.hash2(x, z, 400 + k) + k / 4) % CityGen.FLOWERS.size()]
		mk.blob(p + Vector3(0, 0.07 + Game.hashf(x, z, 500 + k) * 0.05, 0), Vector3(0.035, 0.03, 0.035), col)
	if Game.hashf(x, z, 141) > 0.6:
		mk.blob(_spot(x, z, 99, 1.4) + Vector3(0, 0.08, 0), Vector3(0.16, 0.11, 0.15), Color("5c9e4e"), 0.04)
