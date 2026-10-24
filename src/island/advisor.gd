class_name Advisor
extends RefCounted
## Pip, the city advisor: looks the town over and says where it would help to
## paint what. Nothing is guessed: the town is laid on a grid of cells, each
## cell adds up who lives and works there, its shops, works, parks, painted
## green and streets, and summed tables give any cell's neighbourhood at once.
## A handful of rules (shops within a walk of homes, work for the residents,
## workers for the jobs, works kept away from houses, a park within a walk,
## room to grow taller, painted land a street can reach) each score the places
## they would change, and the best few, kept apart, become Pip's tips: what to
## paint (district and level, or green, or a street), where, and why.

const CELL := 8.0
const N := int(Land.SIZE / CELL)
## a short walk, in cells either way (about 25 m)
const WALK := 3
## how far people will travel to work, in cells
const COMMUTE := 7
## the most tips Pip gives at once, and how far apart they stand (further
## for two of the same kind)
const MAX_TIPS := 3
const APART := 16.0
const APART_SAME := 28.0
## one shop for about this many residents (as IslandProgress wants them)
const SHOP_PER := 0.06
const WORKERS := 0.55
## what Pip calls each district (Land.USES), with its icon
const DISTRICTS := {"homes": ["Homes", "house"], "shops": ["Shops", "shop"], "offices": ["Offices", "office"],
	"industry": ["Industry", "factory"], "entertainment": ["Entertainment", "ferris"]}
const GREEN_TINT := Color("4cc46a")
const STREET_TINT := Color("8f9aab")

var island: IslandWorld
var _g := {}
var _sat := {}
# street samples per cell: [point, kind]
var _streets := {}
var _home := -1
var _shop := -1
var _office := -1
var _works := -1
var _fun := -1
var _cands: Array = []
var _zone_n := 0
var _unreached := 0
var _res_total := 0.0
var _res_shops := 0.0
var _res_green := 0.0
var _homes_total := 0.0
var _homes_smoky := 0.0


## Looks the city over. Returns {score 0..100, headline, line, meters
## [[name, 0..1, colour]], tips [{key, kind, title, text, pos, radius,
## colour, icon, action {brush, use, level}}]}.
static func analyse(world: IslandWorld) -> Dictionary:
	var a := Advisor.new()
	a.island = world
	return a._run()


func _run() -> Dictionary:
	_home = Land.USES.find("homes")
	_shop = Land.USES.find("shops")
	_office = Land.USES.find("offices")
	_works = Land.USES.find("industry")
	_fun = Land.USES.find("entertainment")
	var pr := island.progress
	if island.streets.streets.is_empty():
		return _empty("Every city starts with one street. Draw a Street, then paint Homes beside it with Grow, and I'll watch it come to life.")
	_gather()
	if pr.residents < 8:
		_bare(1.0)
		var r := _report()
		r.headline = "A fresh start!"
		r.line = "Paint Homes along your street with the Grow brush and the first families will move in."
		return r
	_rule_shops()
	_rule_jobs()
	_rule_workers()
	_rule_smoke()
	_rule_parks()
	_rule_taller()
	_rule_reach()
	_rule_fun()
	_bare(0.25)
	return _report()


func _empty(text: String) -> Dictionary:
	return {"score": 0, "headline": "Hello, Mayor!", "line": text, "meters": [], "tips": []}


# ------------------------------------------------------------------ the grid

static func cell_of(p: Vector2) -> int:
	var i := clampi(int((p.x + Land.HALF) / CELL), 0, N - 1)
	var j := clampi(int((p.y + Land.HALF) / CELL), 0, N - 1)
	return j * N + i


static func cell_mid(k: int) -> Vector2:
	return Vector2((k % N + 0.5) * CELL - Land.HALF, (k / N + 0.5) * CELL - Land.HALF)


func _layer(name: String) -> PackedFloat32Array:
	if not _g.has(name):
		var a := PackedFloat32Array()
		a.resize(N * N)
		_g[name] = a
	return _g[name]


func _add(name: String, k: int, v: float) -> void:
	if not _g.has(name):
		_layer(name)
	_g[name][k] += v


## Sum of a layer over the cells within `r` of cell k (a square of them),
## from a summed table built the first time it is asked for.
func _sum(name: String, k: int, r: int) -> float:
	if not _g.has(name):
		return 0.0
	if not _sat.has(name):
		var src: PackedFloat32Array = _g[name]
		var t := PackedFloat32Array()
		t.resize((N + 1) * (N + 1))
		for j in N:
			var run := 0.0
			for i in N:
				run += src[j * N + i]
				t[(j + 1) * (N + 1) + i + 1] = t[j * (N + 1) + i + 1] + run
		_sat[name] = t
	var s: PackedFloat32Array = _sat[name]
	var i0 := maxi(k % N - r, 0)
	var j0 := maxi(k / N - r, 0)
	var i1 := mini(k % N + r + 1, N)
	var j1 := mini(k / N + r + 1, N)
	var w := N + 1
	return s[j1 * w + i1] - s[j0 * w + i1] - s[j1 * w + i0] + s[j0 * w + i0]


func _gather() -> void:
	for l: Town.Lot in island.town.lots.values():
		var p := l.origin
		var k := cell_of(p)
		_add("lots", k, 1.0)
		if _fun >= 0 and l.district == _fun:
			_add("fun", k, 1.0)
		if l.type == "park":
			_add("parks", k, 1.0)
			continue
		if l.type != "house":
			continue
		# a plot repainted as industry counts as the works it is about to become
		if l.use == "industry" or (l.district == _works and _works >= 0):
			_add("works", k, 1.0)
			_add("wx", k, p.x)
			_add("wz", k, p.y)
		if l.use == "home" and l.district != _works:
			var r := maxi(1, l.floors * 2 - int(l.shop))
			_add("res", k, r)
			_add("homes", k, 1.0)
			_add("hx", k, p.x)
			_add("hz", k, p.y)
			_add("stage", k, l.stage)
			_add("full", k, 1.0 if l.stage >= l.cap else 0.0)
		elif l.use != "home":
			var w := Town.workers(l)
			_add("jobs", k, w)
			if l.use == "office":
				_add("office", k, w)
		if l.shop or l.use == "retail":
			_add("shops", k, 1.0)
	for s: Streets.Street in island.streets.streets:
		var step := 8
		for i in range(0, s.pts.size(), step):
			var p := s.pts[i]
			var k := cell_of(p)
			if not _streets.has(k):
				_streets[k] = []
			_streets[k].append([p, s.kind])
			_add("street", k, 1.0)
			if s.kind == "highway":
				_add("highway", k, 1.0)
			elif s.kind == "avenue" or s.kind == "main":
				_add("major", k, 1.0)
	# painted ground: green, and town no street can reach
	var land := island.land
	const EVERY := 3
	for j in range(0, Land.SIDE, EVERY):
		for i in range(0, Land.SIDE, EVERY):
			var q := j * Land.SIDE + i
			if land.zone[q] < 0.5 or land.heights[q] < 0.1:
				continue
			var p := Vector2(i * Land.STEP - Land.HALF, j * Land.STEP - Land.HALF)
			var k := cell_of(p)
			if land.green[q] > 0.5:
				_add("green", k, 1.0)
				continue
			_zone_n += 1
			if _sum("street", k, 2) <= 0.0:
				_unreached += 1
				_add("lost", k, 1.0)


func _at(name: String, k: int) -> float:
	return _g[name][k] if _g.has(name) else 0.0


## Where the homes around cell k are, on average.
func _homes_mid(k: int, r := 1) -> Vector2:
	var n := _sum("homes", k, r)
	if n <= 0.0:
		return cell_mid(k)
	return Vector2(_sum("hx", k, r), _sum("hz", k, r)) / n


## The nearest place on a street to p (within `reach`), preferring main
## streets and avenues a little; highways only when `highway`. INF if none.
func _street_near(p: Vector2, reach := 16.0, highway := false) -> Vector2:
	var best := Vector2.INF
	var bd := INF
	var c := cell_of(p)
	var r := int(ceil(reach / CELL))
	for dj in range(-r, r + 1):
		for di in range(-r, r + 1):
			var i := c % N + di
			var j := c / N + dj
			if i < 0 or j < 0 or i >= N or j >= N:
				continue
			for e in _streets.get(j * N + i, []):
				if e[1] == "highway" and not highway:
					continue
				var d: float = p.distance_to(e[0]) * (0.8 if e[1] == "main" or e[1] == "avenue" else 1.0)
				if d < bd and d < reach:
					bd = d
					best = e[0]
	return best


func _can(use: int) -> bool:
	return use >= 0 and island.progress.can_use(Land.USES[use])


func _level_ok(lv: int) -> bool:
	return lv >= 1 and lv <= int(Land.LEVEL_MAX) and island.progress.can_use("level%d" % lv)


## The highest level that may be painted, at most `lv`.
func _cap_level(lv: int) -> int:
	lv = clampi(lv, 1, int(Land.LEVEL_MAX))
	while lv > 1 and not _level_ok(lv):
		lv -= 1
	return lv


static func level_name(lv: int) -> String:
	return Hud.LEVELS[lv - 1] if lv >= 1 and lv <= Hud.LEVELS.size() else "Level %d" % lv


static func district_name(use: int) -> String:
	if use < 0 or use >= Land.USES.size():
		return "Homes"
	return DISTRICTS.get(Land.USES[use], [str(Land.USES[use]).capitalize()])[0]


static func district_icon(use: int) -> String:
	if use < 0 or use >= Land.USES.size():
		return "house"
	return DISTRICTS.get(Land.USES[use], ["", "star"])[1]


static func district_tint(use: int) -> Color:
	return Land.USE_TINTS[use] if use >= 0 and use < Land.USE_TINTS.size() else Color("c86bff")


## The same words for the same place every time, with a little variety between places.
static func _pick(key: String, options: Array) -> String:
	return options[absi(hash(key)) % options.size()]


func _grow_tip(kind: String, score: float, at: Vector2, use: int, lv: int, title: String, text: String, radius := 9.0) -> void:
	_cands.append({"key": "%s:%d" % [kind, cell_of(at)], "kind": kind, "score": score, "pos": at, "radius": radius,
		"title": title, "text": text, "colour": district_tint(use), "icon": district_icon(use),
		"tag": "%s · %s" % [district_name(use), level_name(lv)], "action": {"brush": "grow", "use": use, "level": lv}})


func _green_tip(kind: String, score: float, at: Vector2, title: String, text: String, radius := 7.0) -> void:
	if not island.progress.can_use("green"):
		return
	_cands.append({"key": "%s:%d" % [kind, cell_of(at)], "kind": kind, "score": score, "pos": at, "radius": radius,
		"title": title, "text": text, "colour": GREEN_TINT, "icon": "park", "tag": "Green", "action": {"brush": "green"}})


# ------------------------------------------------------------------ rules

## Homes with too few shops within a walk.
func _rule_shops() -> void:
	var open := _can(_shop)
	for k in N * N:
		var res := _at("res", k)
		if res <= 0.0:
			continue
		var near := _sum("res", k, WALK)
		var shops := _sum("shops", k, WALK)
		var need := near * SHOP_PER
		_res_total += res
		if shops >= need * 0.5 or near < 30.0:
			_res_shops += res
			continue
		if not open or _at("homes", k) < 2.0:
			continue
		var at := _street_near(_homes_mid(k, 1))
		if at == Vector2.INF or island.land.use_at(at.x, at.y) == _shop:
			continue
		var lv := _cap_level(clampi(int(round(_sum("stage", k, 1) / maxf(_sum("homes", k, 1), 1.0))) + 2, 2, 4))
		var score := (1.0 - shops / maxf(need, 1.0)) * clampf(near / 160.0, 0.35, 1.0)
		_grow_tip("shops", score, at, _shop, lv, "Shops for these homes",
			_pick("shops%d" % k, [
				"%d people live around here with %s close by. Paint Shops along this street so they can pop out for bread.",
				"These %d residents walk a long way to the shops (%s nearby). A row of Shops on this street would fix that.",
			]) % [int(near), "no shop" if shops < 1.0 else "only %d shop%s" % [int(shops), "" if shops < 1.5 else "s"]])


## Too few jobs for the people: offices near the busy middle, industry out by
## the big roads and away from the homes.
func _rule_jobs() -> void:
	var pr := island.progress
	var workers := pr.residents * WORKERS
	if pr.residents < 40 or pr.jobs >= workers * 0.8:
		return
	var short := workers - pr.jobs
	var u := clampf(short / maxf(workers, 1.0), 0.0, 1.0)
	var want_works := 0.5 + pr.demand[_works] if _works >= 0 and _works < pr.demand.size() else 1.0
	var want_office := 0.5 + pr.demand[_office] if _office >= 0 and _office < pr.demand.size() else 1.0
	var best_w := [0.0, Vector2.INF, 0]
	var best_o := [0.0, Vector2.INF, 0]
	for k in _streets:
		if _sum("street", k, 0) <= _at("highway", k):
			continue
		var commute := _sum("res", k, COMMUTE)
		if commute < 15.0:
			continue
		var reach := 0.6 + 0.4 * clampf(commute / 250.0, 0.0, 1.0)
		var big := _sum("major", k, 1) > 0.0 or _sum("highway", k, 2) > 0.0
		if _can(_works):
			var homes := _sum("homes", k, 1)
			var s := u * want_works * reach * (1.0 - clampf(homes / 5.0, 0.0, 0.85))
			s *= (1.25 if big else 1.0) * (1.15 if _sum("works", k, 2) > 0.0 else 1.0)
			if s > best_w[0]:
				best_w = [s, cell_mid(k), k]
		if _can(_office):
			var hn := _sum("homes", k, 2)
			var tall := _sum("stage", k, 2) / maxf(hn, 1.0) if hn > 0.0 else 0.0
			var s := u * want_office * reach * clampf(tall / 4.0, 0.3, 1.0) * clampf(hn / 12.0, 0.3, 1.0)
			s *= (1.2 if big else 1.0) * (0.4 if _sum("works", k, 1) > 0.0 else 1.0)
			if s > best_o[0]:
				best_o = [s, cell_mid(k), k]
	if best_w[0] > 0.0:
		var at := _street_near(best_w[1], 12.0)
		if at != Vector2.INF and island.land.use_at(at.x, at.y) != _works:
			_grow_tip("jobs", 0.45 + 0.6 * minf(best_w[0], 1.2), at, _works, _cap_level(3), "Work for your people",
				_pick("works%d" % best_w[2], [
					"About %d people can't find work. Paint Industry here, by the big road and clear of the houses.",
					"%d residents are out of work. Workshops and factories here would hire them without bothering the homes.",
				]) % int(short))
	if best_o[0] > 0.0:
		var at := _street_near(best_o[1], 12.0)
		if at != Vector2.INF and island.land.use_at(at.x, at.y) != _office:
			var lv := _cap_level(maxi(4, int(round(_sum("stage", best_o[2], 2) / maxf(_sum("homes", best_o[2], 2), 1.0))) + 2))
			var why := "%d people need jobs. Paint Offices at %s in this busy middle and they can walk to work." % [int(short), level_name(lv)]
			if hash("offices%d" % best_o[2]) % 2 != 0:
				why = "Your busiest streets have no desks. Offices here at %s would employ %d people." % [level_name(lv), int(short)]
			_grow_tip("offices", 0.4 + 0.6 * minf(best_o[0], 1.2), at, _office, lv, "Offices downtown", why)


## More jobs than workers: homes near the jobs, but not beside the works.
func _rule_workers() -> void:
	var pr := island.progress
	var workers := pr.residents * WORKERS
	var spare := pr.jobs - workers
	if pr.jobs < 20 or spare < workers * 0.2 + 10.0:
		return
	var best := [0.0, Vector2.INF, 0]
	for k in _streets:
		if _sum("street", k, 0) <= _at("highway", k):
			continue
		var jobs := _sum("jobs", k, WALK + 1)
		if jobs <= 0.0:
			continue
		var s := clampf(jobs / 60.0, 0.2, 1.0) * (1.0 - clampf(_sum("works", k, 1) / 2.0, 0.0, 1.0))
		s *= 1.0 - clampf(_sum("lots", k, 0) / 6.0, 0.0, 0.6)
		if s > best[0]:
			best = [s, cell_mid(k), k]
	if best[0] <= 0.0:
		return
	var at := _street_near(best[1], 12.0)
	if at == Vector2.INF:
		return
	var score: float = 0.35 + 0.6 * clampf(spare / maxf(workers, 20.0), 0.0, 1.0) * best[0]
	_grow_tip("homes", score, at, _home, _cap_level(3), "Homes for the workers",
		_pick("workers%d" % best[2], [
			"Businesses have %d jobs nobody can fill. Paint Homes here so workers can live close by.",
			"%d jobs are going spare. New Homes on this street would bring the workers in.",
		]) % int(spare))


## Works right beside homes: a green strip between them.
func _rule_smoke() -> void:
	for k in N * N:
		var homes := _at("homes", k)
		if homes <= 0.0:
			continue
		_homes_total += homes
		var works := _sum("works", k, 1)
		if works <= 0.0:
			continue
		_homes_smoky += homes
		var near := _sum("homes", k, 1)
		if _at("works", k) <= 0.0 or near < 3.0:
			continue
		var w := Vector2(_sum("wx", k, 1), _sum("wz", k, 1)) / works
		var h := _homes_mid(k, 1)
		var at := w.lerp(h, 0.45)
		_green_tip("smoke", clampf(near / 14.0, 0.3, 0.9), at, "Keep the smoke off the homes",
			_pick("smoke%d" % k, [
				"%d homes sit right beside the works. Plant a strip of Green between them as a buffer.",
				"Factories and houses are rubbing shoulders here (%d homes). A band of Green between them would calm things down.",
			]) % int(near), 5.5)


## Homes with no park or green within a walk.
func _rule_parks() -> void:
	for k in N * N:
		var res := _at("res", k)
		if res <= 0.0:
			continue
		var green := _sum("parks", k, WALK) + _sum("green", k, WALK) / 6.0
		if green >= 0.5:
			_res_green += res
			continue
		var near := _sum("res", k, WALK)
		if near < 50.0 or _at("homes", k) < 2.0:
			continue
		_green_tip("park", clampf(near / 300.0, 0.2, 0.6), _homes_mid(k, 1), "A park within a walk",
			_pick("park%d" % k, [
				"%d people here have no park nearby. Paint a little Green and they'll have somewhere to sit in the sun.",
				"Not a tree in sight for %d residents. A small Green patch here would make the neighbourhood.",
			]) % int(near))


## Homes that have grown as tall as their level lets them, while the city
## wants more homes: a level up.
func _rule_taller() -> void:
	var pr := island.progress
	var want: float = pr.demand[_home] if _home >= 0 and _home < pr.demand.size() else 0.5
	if want < 0.5:
		return
	for k in N * N:
		if _at("homes", k) < 3.0:
			continue
		var homes := _sum("homes", k, 1)
		var full := _sum("full", k, 1) / homes
		if full < 0.75:
			continue
		var mid := _homes_mid(k, 1)
		var now := int(round(island.land.level_at(mid.x, mid.y)))
		var next := now + 1
		if not _level_ok(next):
			continue
		var at := _street_near(mid, 10.0)
		if at == Vector2.INF:
			continue
		var use := island.land.use_at(at.x, at.y)
		if use == _works:
			continue
		var score := full * want * clampf(homes / 12.0, 0.3, 1.0) * (0.75 + 0.25 * clampf(_sum("major", k, 1), 0.0, 1.0)) * 0.75
		_grow_tip("taller", score, at, use, next, "Room to grow taller",
			_pick("taller%d" % k, [
				"These homes are as tall as %s allows and the city wants more. Paint %s here and they'll climb higher.",
				"Every house here has topped out at %s. Repaint it as %s to let the street grow up.",
			]) % [level_name(now), level_name(next)])


## Painted town that no street reaches.
func _rule_reach() -> void:
	if _unreached < 6:
		return
	var best := 0.0
	var bk := -1
	for k in N * N:
		var n := _sum("lost", k, 1)
		if n > best:
			best = n
			bk = k
	if bk < 0:
		return
	_cands.append({"key": "reach:%d" % bk, "kind": "reach", "score": clampf(best / 24.0, 0.3, 0.8), "pos": cell_mid(bk), "radius": 10.0,
		"title": "No way in",
		"text": "You've painted land here, but no street reaches it. Draw a Street in from the town and houses will follow.",
		"colour": STREET_TINT, "icon": "road", "tag": "Street", "action": {"brush": "street"}})


## Lots of people and nowhere to go out (once Entertainment opens).
func _rule_fun() -> void:
	if not _can(_fun):
		return
	for k in N * N:
		if _at("homes", k) < 2.0:
			continue
		var near := _sum("res", k, 5)
		if near < 150.0 or _sum("fun", k, 5) > 0.0:
			continue
		var at := _street_near(_homes_mid(k, 2), 14.0)
		if at == Vector2.INF:
			continue
		_grow_tip("fun", clampf(near / 600.0, 0.3, 0.75), at, _fun, _cap_level(3), "Somewhere to go out",
			"%d people live nearby with nothing to do of an evening. Paint Entertainment here." % int(near), 10.0)


## Bare streets, for whatever the city wants most.
func _bare(weight: float) -> void:
	var pr := island.progress
	var best_use := _home
	var best_want := -1.0
	for u in Land.USES.size():
		if u >= pr.demand.size() or not _can(u) or u == _fun:
			continue
		if pr.demand[u] > best_want:
			best_want = pr.demand[u]
			best_use = u
	var best := [0.0, Vector2.INF, 0]
	for k in _streets:
		if _sum("lots", k, 1) > 0.0 or _sum("street", k, 0) <= _at("highway", k):
			continue
		var p: Vector2 = _streets[k][0][0]
		if island.land.zone_at(p.x, p.y) > 0.3 or island.land.height_at(p.x, p.y) < 0.15:
			continue
		var town := _sum("lots", k, COMMUTE)
		var s := (0.5 + 0.5 * clampf(town / 40.0, 0.0, 1.0)) * (1.0 if best_use != _works else 1.0 - clampf(_sum("homes", k, 2) / 4.0, 0.0, 0.9))
		if s > best[0]:
			best = [s, p, k]
	if best[0] <= 0.0:
		return
	var name := district_name(best_use)
	_grow_tip("bare", weight * best[0] * (0.5 + maxf(best_want, 0.0)), best[1], best_use, _cap_level(2), "An empty street",
		"This street is still bare, and the city wants %s most. Paint %s along it." % [name.to_lower(), name])


# ------------------------------------------------------------------ report

func _report() -> Dictionary:
	_cands.sort_custom(func(a, b): return a.score > b.score)
	var tips: Array = []
	var per := {}
	for c in _cands:
		if tips.size() >= MAX_TIPS:
			break
		if int(per.get(c.kind, 0)) >= 2:
			continue
		var clash := false
		for t in tips:
			clash = clash or (t.pos as Vector2).distance_to(c.pos) < (APART_SAME if t.kind == c.kind else APART)
		if clash:
			continue
		per[c.kind] = int(per.get(c.kind, 0)) + 1
		tips.append(c)
	var pr := island.progress
	var workers := pr.residents * WORKERS
	var jobs := 1.0
	if pr.residents >= 40 and (_can(_works) or _can(_office)):
		jobs = 1.0 - clampf(absf(1.0 - pr.jobs / maxf(workers, 1.0)) * 1.2, 0.0, 1.0)
	var shops := _res_shops / _res_total if _res_total > 0.0 else 1.0
	var green := _res_green / _res_total if _res_total > 0.0 else 1.0
	var calm := 1.0 - _homes_smoky / _homes_total if _homes_total > 0.0 else 1.0
	var reach := 1.0 - float(_unreached) / maxf(_zone_n, 1.0) if _zone_n > 0 else 1.0
	var score := int(round(100.0 * (0.3 * jobs + 0.25 * shops + 0.2 * green + 0.15 * calm + 0.1 * reach)))
	var headline := "Your city is thriving!"
	if score < 50:
		headline = "Your city could use some care."
	elif score < 70:
		headline = "Not bad, Mayor!"
	elif score < 85:
		headline = "Looking lovely!"
	var line := "%s residents and %s jobs" % [_count(pr.residents), _count(pr.jobs)]
	if pr.residents >= 40 and workers > pr.jobs * 1.05:
		line += ", %d%% looking for work." % int(round(pr.unemployment() * 100.0))
	elif pr.residents >= 40 and pr.jobs > workers * 1.2:
		line += ", more jobs than workers."
	else:
		line += "."
	if tips.is_empty():
		line += " Nothing needs fixing: keep growing and I'll keep an eye out."
	elif tips.size() == 1:
		line += " One idea:"
	else:
		line += " %s ideas, best first:" % ["", "", "Two", "Three"][tips.size()]
	return {"score": score, "headline": headline, "line": line, "tips": tips,
		"meters": [["Jobs", jobs, Color("22b5b5")], ["Shops", shops, Color("3f8cff")], ["Green", green, GREEN_TINT], ["Calm", calm, Color("e8a21a")]]}


static func _count(n: int) -> String:
	if n >= 10000:
		return "%.1fk" % (n / 1000.0)
	return str(n)
