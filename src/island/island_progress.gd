class_name IslandProgress
extends Node
## How the island's town is coming along: its homes and residents, its title,
## the coins it earns, three goals at a time to collect, and the brushes that
## open up as more people move in. Streets and reshaping the land cost a few
## coins; growing and greening are free, and the town pays its way in taxes.

signal stats_changed
signal coins_changed
signal goals_changed
signal goal_ready(i: int)
signal unlocked(brush: String)
signal title_changed(title: String)

## milestones: residents, title, and the coins the city is given on reaching it
const TITLES := [[0, "Hamlet", 0], [30, "Village", 60], [120, "Town", 150], [300, "Small City", 300], [600, "City", 500],
	[1200, "Big City", 900], [2500, "Large City", 1500], [5000, "Metropolis", 2500], [10000, "Megalopolis", 4000]]
## residents needed before a brush, road, district or Grow level can be used
const UNLOCK := {"green": 12, "smooth": 30, "flatten": 60, "shops": 60, "industry": 120, "avenue": 150,
	"offices": 300, "highway": 400, "level5": 600, "level6": 1200}
## the districts, in Land.USES order, and what unlocks each (homes always open)
const USE_KEYS := ["homes", "shops", "offices", "industry"]
const START_COINS := 300.0
const STREET_COST := 0.5 # per metre
const SHAPE_COST := 4.0 # per second of sculpting
const PAY_EVERY := 5.0

var world: IslandWorld
var coins := START_COINS
var residents := 0
## workplaces: offices and industry
var jobs := 0
var office_jobs := 0
var works := 0
## how much the city wants more of each district (Land.USES order), 0..1
var demand: Array[float] = [0.6, 0.4, 0.0, 0.0]
var homes := 0
var shops := 0
var parks := 0
var squares := 0
var churches := 0
var styles := 0
var harbour := 0
var street_m := 0.0
var title := "Hamlet"
var best := 0
var goals: Array = []
var goals_done := 0
var opened := {}
var _count_timer := 0.0
var _pay_timer := PAY_EVERY
var _rng := RandomNumberGenerator.new()
# quiet while a loaded island's town builds back up
var _hush := 0.0


func _ready() -> void:
	_rng.randomize()
	recount(true)


func _process(delta: float) -> void:
	if not world.town.is_busy():
		_hush -= delta
	_count_timer -= delta
	if _count_timer <= 0.0:
		_count_timer = 1.0
		recount(_hush > 0.0)
	_pay_timer -= delta
	if _pay_timer <= 0.0:
		_pay_timer = PAY_EVERY
		var pay := income()
		if pay > 0.0:
			add_coins(pay)


## Coins the town pays every few seconds.
func income() -> float:
	return snappedf(residents * 0.02 + jobs * 0.03 + shops * 0.15, 0.1)


func add_coins(amount: float) -> void:
	coins = maxf(0.0, coins + amount)
	coins_changed.emit()


## Takes `amount` coins if there are enough.
func spend(amount: float) -> bool:
	if coins < amount:
		return false
	add_coins(-amount)
	return true


## No unlock or title news for a little while, as a loaded town fills back in.
func hush() -> void:
	_hush = 6.0


func can_use(brush: String) -> bool:
	return opened.has(brush) or not UNLOCK.has(brush)


func unlock_text(brush: String) -> String:
	return "Unlocks at %d residents" % int(UNLOCK.get(brush, 0))


## Counts up the town as it stands; quietly (no toasts) when `silent`.
func recount(silent: bool) -> void:
	if world == null or world.town == null:
		return
	var r := 0
	var j := 0
	var oj := 0
	var wk := 0
	var h := 0
	var sh := 0
	var pk := 0
	var sq := 0
	var ch := 0
	var hb := 0
	var kits := {}
	for l: Town.Lot in world.town.lots.values():
		match l.type:
			"house":
				h += 1
				# offices and industry bring jobs rather than residents
				if l.use == "office" or l.use == "industry" or l.use == "retail":
					j += Town.workers(l)
					if l.use == "office":
						oj += Town.workers(l)
					elif l.use == "industry":
						wk += 1
				else:
					r += maxi(1, l.floors * 2 - int(l.shop))
				sh += int(l.shop)
				kits[l.kit] = true
				hb += int(l.kit == HouseGen.HARBOUR)
			"park": pk += 1
			"square": sq += 1
			"church": ch += 1
	var m := 0.0
	for s: Streets.Street in world.streets.streets:
		m += maxf(0.0, s.pts.size() - 1.0) * Streets.SAMPLE
	var changed := r != residents or j != jobs or h != homes or pk != parks or sq != squares or ch != churches or absf(m - street_m) > 0.5
	residents = r
	jobs = j
	office_jobs = oj
	works = wk
	homes = h
	shops = sh
	parks = pk
	squares = sq
	churches = ch
	styles = kits.size()
	harbour = hb
	street_m = m
	_work_out_demand()
	best = maxi(best, residents)
	for b in UNLOCK:
		if not opened.has(b) and best >= int(UNLOCK[b]):
			opened[b] = true
			if not silent:
				unlocked.emit(b)
	var t := _title_for(best)
	if t != title:
		title = t
		if not silent:
			add_coins(milestone_reward(t))
			title_changed.emit(t)
	# new goals wait while the town is still laying out, so they start from what is really there
	if not world.town.is_busy():
		_fill_goals()
	_check_goals()
	if changed:
		stats_changed.emit()


## What the city wants: homes when there are more jobs than workers, shops
## for its residents, offices and industry to employ them. A district in
## demand grows faster (Town._delay).
func _work_out_demand() -> void:
	var workers := residents * 0.55
	var ind_jobs := jobs - office_jobs
	demand[0] = clampf(0.45 + (jobs - workers) / maxf(workers, 30.0), 0.1, 1.0)
	var want_shops := residents * 0.06
	demand[1] = clampf(0.3 + (want_shops - shops) / maxf(want_shops, 4.0), 0.0, 1.0) if can_use("shops") else 0.0
	var want_off := workers * 0.45
	demand[2] = clampf(0.25 + (want_off - office_jobs) / maxf(want_off, 15.0), 0.0, 1.0) if can_use("offices") else 0.0
	var want_ind := workers * 0.35
	demand[3] = clampf(0.25 + (want_ind - ind_jobs) / maxf(want_ind, 15.0), 0.0, 1.0) if can_use("industry") else 0.0
	if world and world.town:
		world.town.demand = demand


## People out of work: workers the city's jobs don't cover, 0..1.
func unemployment() -> float:
	var workers := residents * 0.55
	return clampf((workers - jobs) / maxf(workers, 1.0), 0.0, 1.0)


func milestone_reward(t: String) -> float:
	for e in TITLES:
		if e[1] == t:
			return float(e[2])
	return 0.0


## What reaching `n` residents opens up, for the stats panel.
static func unlocks_at(n: int) -> Array:
	var out: Array = []
	for k in UNLOCK:
		if int(UNLOCK[k]) == n:
			out.append(k)
	return out


func _title_for(n: int) -> String:
	var t: String = TITLES[0][1]
	for e in TITLES:
		if n >= int(e[0]):
			t = e[1]
	return t


## The next title and how far along the way to it, 0..1; "" past the last.
func next_title() -> Array:
	for i in TITLES.size():
		if best < int(TITLES[i][0]):
			var lo := float(TITLES[i - 1][0])
			return [TITLES[i][1], clampf((best - lo) / (float(TITLES[i][0]) - lo), 0.0, 1.0), int(TITLES[i][0])]
	return ["", 1.0, 0]


# ------------------------------------------------------------------ goals

func goal_value(g: Dictionary) -> float:
	match str(g.type):
		"residents": return residents
		"homes": return homes
		"shops": return shops
		"parks": return parks
		"squares": return squares
		"churches": return churches
		"styles": return styles
		"harbour": return harbour
		"streets": return street_m
	return 0.0


func goal_progress(g: Dictionary) -> float:
	if g.get("ready", false):
		return 1.0
	var base := float(g.get("base", 0))
	return clampf((goal_value(g) - base) / maxf(float(g.target) - base, 1.0), 0.0, 1.0)


func _make_goal() -> Dictionary:
	var taken := {}
	for g in goals:
		taken[str(g.type)] = true
	var pay := 25.0 + best * 0.6
	var opts: Array = []
	var r := Game._nice(maxf(residents + 10, residents * 1.35))
	opts.append([3.0, {"type": "residents", "target": r, "icon": "people", "text": "Grow to %d residents" % r, "reward": Game._nice(pay * 1.6)}])
	var h := 3 + mini(goals_done, 12) * 2
	opts.append([2.0, {"type": "homes", "base": homes, "target": homes + h, "icon": "house", "text": "Build %d more homes" % h, "reward": Game._nice(pay * 1.2)}])
	var m := 40 + mini(goals_done, 10) * 15
	opts.append([1.5, {"type": "streets", "base": int(street_m), "target": int(street_m) + m, "icon": "road",
		"text": "Lay %d m more of streets" % m, "reward": Game._nice(pay + m * 0.4)}])
	if can_use("green"):
		var n := 1 + mini(goals_done / 4, 3)
		opts.append([1.5, {"type": "parks", "base": parks, "target": parks + n, "icon": "park",
			"text": "Plant %d more park%s" % [n, "" if n == 1 else "s"], "reward": Game._nice(pay * 1.1)}])
	if homes >= 12:
		opts.append([1.2, {"type": "shops", "base": shops, "target": shops + 2, "icon": "shop",
			"text": "Open 2 more shops on a main street", "reward": Game._nice(pay * 1.3)}])
		opts.append([1.0, {"type": "squares", "base": squares, "target": squares + 1, "icon": "plaza",
			"text": "Grow a town square on a busy street", "reward": Game._nice(pay * 1.5)}])
	if homes >= 20:
		opts.append([1.0, {"type": "churches", "base": churches, "target": churches + 1, "icon": "clocktower",
			"text": "Grow a church in a new quarter", "reward": Game._nice(pay * 1.6)}])
	if styles < 4:
		opts.append([1.0, {"type": "styles", "target": styles + 1, "icon": "star",
			"text": "Build in %d different styles" % (styles + 1), "reward": Game._nice(pay * 1.4)}])
	opts.append([0.8, {"type": "harbour", "base": harbour, "target": harbour + 4, "icon": "lighthouse",
		"text": "Build 4 more homes by the water", "reward": Game._nice(pay * 1.3)}])
	var pool: Array = []
	var total := 0.0
	for o in opts:
		var g: Dictionary = o[1]
		if taken.has(str(g.type)) or goal_value(g) >= float(g.target):
			continue
		pool.append(o)
		total += o[0]
	var pick := _rng.randf() * total
	for o in pool:
		pick -= o[0]
		if pick <= 0.0:
			return o[1]
	return pool[-1][1] if not pool.is_empty() else {}


func _fill_goals() -> void:
	var added := false
	while goals.size() < 3:
		var g := _make_goal()
		if g.is_empty():
			break
		goals.append(g)
		added = true
	if added:
		goals_changed.emit()


func _check_goals() -> void:
	for i in goals.size():
		var g: Dictionary = goals[i]
		if not g.get("ready", false) and goal_value(g) >= float(g.target):
			g["ready"] = true
			goal_ready.emit(i)


## Pays out a finished goal and draws a fresh one in its place. Returns the coins paid.
func claim_goal(i: int) -> float:
	if i < 0 or i >= goals.size() or not goals[i].get("ready", false):
		return 0.0
	var reward := float(goals[i].reward)
	add_coins(reward)
	goals_done += 1
	goals.remove_at(i)
	var g := _make_goal()
	if not g.is_empty():
		goals.insert(i, g)
	goals_changed.emit()
	_check_goals()
	return reward


# ------------------------------------------------------------------ saving

func to_dict() -> Dictionary:
	return {"coins": snappedf(coins, 0.1), "best": best, "done": goals_done, "goals": goals, "open": opened.keys()}


func from_dict(d: Dictionary) -> void:
	coins = float(d.get("coins", START_COINS))
	best = int(d.get("best", 0))
	goals_done = int(d.get("done", 0))
	goals.clear()
	var gs: Variant = d.get("goals", [])
	if gs is Array:
		for g in gs:
			if g is Dictionary and g.has("type") and g.has("target"):
				goals.append(g)
	opened.clear()
	var op: Variant = d.get("open", [])
	if op is Array:
		for b in op:
			opened[str(b)] = true
	title = _title_for(best)
	hush()
	coins_changed.emit()
	goals_changed.emit()
	recount(true)
