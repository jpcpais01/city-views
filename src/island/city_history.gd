class_name CityHistory
extends Node
## The city's story in numbers: every little while it notes the residents,
## jobs, coins and income, for the graphs in the stats panel. It keeps at most
## KEEP points: when full, neighbouring points are averaged in pairs and the
## gap between notes doubles, so the whole life of the city always fits. Kept
## on this device in its own file, for the city it was noted on.

signal sampled

const PATH := "user://city_history.json"
## seconds between notes at first
const EVERY := 10.0
const KEEP := 160

var world: IslandWorld
## seconds between notes now
var every := EVERY
## [residents, jobs, coins, income per minute], oldest first
var points: Array = []
var _t := 0.0
var _seed := -1
var _saves := true


func _init(w: IslandWorld = null, saves := true) -> void:
	world = w
	_saves = saves


func _ready() -> void:
	if _saves:
		_load()


func _process(delta: float) -> void:
	if world == null or world.progress == null:
		return
	if world.island_seed != _seed:
		# a new city (or a co-op room's): its own story
		_seed = world.island_seed
		points.clear()
		every = EVERY
		_t = 0.0
		sample()
		return
	_t += delta
	if _t >= every:
		_t = 0.0
		sample()


func sample() -> void:
	var pr := world.progress
	points.append([pr.residents, pr.jobs, snappedf(pr.coins, 0.1), snappedf(pr.income() * 60.0 / IslandProgress.PAY_EVERY, 0.1)])
	if points.size() > KEEP:
		_halve()
	sampled.emit()
	if _saves:
		_save()


## Averages neighbouring points in pairs (keeping the newest as it is).
func _halve() -> void:
	var out: Array = []
	var n := points.size()
	var start := n % 2
	if start == 1:
		out.append(points[0])
	for i in range(start, n - 1, 2):
		var a: Array = points[i]
		var b: Array = points[i + 1]
		var m: Array = []
		for k in a.size():
			m.append(snappedf((float(a[k]) + float(b[k])) * 0.5, 0.1))
		out.append(m)
	out[out.size() - 1] = points[n - 1]
	points = out
	every *= 2.0


## One measure (0 residents, 1 jobs, 2 coins, 3 income) over time.
func series(k: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for p in points:
		out.append(float(p[k]) if k < p.size() else 0.0)
	return out


## How long the history covers, in seconds.
func span() -> float:
	return maxf(points.size() - 1, 0) * every


func _save() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"seed": _seed, "every": every, "points": points}))


func _load() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not d is Dictionary or not (d.get("points") is Array):
		return
	_seed = int(d.get("seed", -1))
	every = maxf(float(d.get("every", EVERY)), EVERY)
	points.clear()
	for p in d.points:
		if p is Array and p.size() >= 4:
			points.append(p)
