class_name StreetWalk
extends RefCounted
## Moving along the new island's streets, for cars and for people on the
## pavements: on along a street, now and then turning into another where they
## meet, round again at a dead end. A mover is a Dictionary with the street
## `s`, the place along it `f` (in samples), the way it goes `dir` (+1 or -1)
## and `since`, the distance gone since its last turn.


## A new mover somewhere along a random street, longer streets more likely.
static func spawn(streets: Streets, rng: RandomNumberGenerator) -> Dictionary:
	var total := 0.0
	for s: Streets.Street in streets.streets:
		total += s.pts.size()
	var pick := rng.randf() * total
	for s: Streets.Street in streets.streets:
		pick -= s.pts.size()
		if pick <= 0.0:
			var n := s.pts.size()
			if n < 4:
				return {}
			return {"s": s, "f": rng.randf_range(1.0, n - 2.0), "dir": 1.0 if rng.randf() < 0.5 else -1.0, "since": 0.0}
	return {}


## Moves `m` on by `dist` metres. False if its street is gone.
## With `cars`, it never turns onto a walk.
static func advance(streets: Streets, graph: Dictionary, m: Dictionary, dist: float, turn_chance: float, rng: RandomNumberGenerator, cars := false) -> bool:
	var s: Streets.Street = m.s
	if not graph.has(s.id):
		return false
	var n := s.pts.size()
	var f: float = m.f
	var nf: float = f + m.dir * dist / Streets.SAMPLE
	var end := nf <= 0.0 or nf >= n - 1.0
	nf = clampf(nf, 0.0, n - 1.0)
	m.since += dist
	# junctions passed on the way
	if m.since > 1.5:
		for l in graph[s.id]:
			var jf: float = l[0]
			if (jf - f) * m.dir < 0.0 or (jf - nf) * m.dir > 0.0:
				continue
			var at_end := jf < 1.0 or jf > n - 2.0
			if cars and (l[1] as Streets.Street).kind == "walk":
				continue
			if rng.randf() < (0.85 if at_end and end else turn_chance):
				var o: Streets.Street = l[1]
				var of: float = l[2]
				var on := o.pts.size()
				m.s = o
				m.f = of
				if of < 1.0:
					m.dir = 1.0
				elif of > on - 2.0:
					m.dir = -1.0
				else:
					m.dir = 1.0 if rng.randf() < 0.5 else -1.0
				m.since = 0.0
				return true
	m.f = nf
	if end:
		# a dead end (or the turn was not taken): round again
		m.dir = -m.dir
		m.since = 0.0
	return true


## Where the mover is: (position, heading) at `off` to the right of the street.
static func place(streets: Streets, m: Dictionary, off: float) -> Array:
	var s: Streets.Street = m.s
	var f: float = m.f
	var p := streets._ptf(s, f) + streets._sidef(s, f) * off
	var i := clampi(int(f), 0, s.pts.size() - 2)
	var t: Vector2 = (s.pts[i + 1] - s.pts[i]).normalized() * m.dir
	var y := streets._yf(s, f) + 0.03
	return [Vector3(p.x, y, p.y), Vector3(t.x, 0, t.y), s.ys[i + 1] - s.ys[i]]
