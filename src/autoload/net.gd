extends Node
## Online co-op rooms (up to 4 builders) synced through the Firebase Realtime Database.
## Each builder's changes to the island are PATCHed to rooms/<code>/island
## (see IslandSync), and everyone streams that node.

signal room_changed
signal players_changed
signal message(text: String)

const MAX_PLAYERS := 4
const COLORS: Array[Color] = [Color("ff7a6b"), Color("5fb8ff"), Color("ffc94d"), Color("7be08f"), Color("c08bff"), Color("ff9bd2")]
const CODE_CHARS := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

var room_code := ""
var players := {}
var my_color := COLORS[0]

var _beat_timer := 0.0
var _edit_stream: FirebaseStream
var _player_stream: FirebaseStream
var _busy := false
## the island that is open, which rooms build on
var island: IslandWorld


func in_room() -> bool:
	return room_code != ""


func _process(delta: float) -> void:
	if not in_room():
		return
	_beat_timer += delta
	if _beat_timer > 5.0:
		_beat_timer = 0.0
		Firebase.db_patch("rooms/%s/players/%s" % [room_code, Firebase.uid], _me())


func _me() -> Dictionary:
	return {"name": Game.player_name, "color": my_color.to_html(false), "ts": {".sv": "timestamp"}}


func _now_ms() -> float:
	return Time.get_unix_time_from_system() * 1000.0


func _active(p: Variant) -> bool:
	return p is Dictionary and _now_ms() - float(p.get("ts", 0)) < 60000.0


func _ensure_online() -> String:
	if not Firebase.enabled:
		return "Online play isn't configured in this build yet"
	if not Firebase.signed_in:
		var e: String = await Firebase.sign_in_guest()
		if e != "":
			return e
	return ""


func create_room() -> String:
	if _busy or island == null:
		return "Busy"
	_busy = true
	var err := await _ensure_online()
	if err != "":
		_busy = false
		return err
	island._save()
	var code := ""
	for attempt in 5:
		code = ""
		for i in 5:
			code += CODE_CHARS[randi() % CODE_CHARS.length()]
		var probe := await Firebase.db_get("rooms/%s/meta" % code)
		if probe.ok and probe.data == null:
			break
	my_color = COLORS[0]
	var room := {
		"meta": {"seed": island.island_seed, "kind": "island", "name": "Shared island", "host": Firebase.uid, "created": {".sv": "timestamp"}, "v": 2},
		"island": island.sync.full_state(),
		"players": {Firebase.uid: _me()},
	}
	var r := await Firebase.db_put("rooms/%s" % code, room)
	_busy = false
	if not r.ok:
		return "Couldn't create the room (%d)" % r.code
	island.sync.begin()
	_enter(code)
	return ""


func join_room(code: String) -> String:
	code = code.strip_edges().to_upper()
	if code.length() < 4:
		return "Enter a room code"
	if _busy or island == null:
		return "Busy"
	_busy = true
	var err := await _ensure_online()
	if err != "":
		_busy = false
		return err
	var meta := await Firebase.db_get("rooms/%s/meta" % code)
	if not meta.ok or not meta.data is Dictionary:
		_busy = false
		return "No room with code %s" % code
	if meta.data.get("kind", "") != "island":
		_busy = false
		return "That room was building a tile town, which is gone now: start a new room"
	var pl := await Firebase.db_get("rooms/%s/players" % code)
	var taken := []
	var count := 0
	if pl.ok and pl.data is Dictionary:
		for id in pl.data:
			if id != Firebase.uid and _active(pl.data[id]):
				count += 1
				taken.append(str(pl.data[id].get("color", "")))
	if count >= MAX_PLAYERS:
		_busy = false
		return "Room is full (4 builders max)"
	for c in COLORS:
		if not taken.has(c.to_html(false)):
			my_color = c
			break
	var state := await Firebase.db_get("rooms/%s/island" % code)
	if not in_room():
		island._save()
	if in_room():
		_leave_quietly()
	island.load_room(int(meta.data.get("seed", 1)), state.data)
	await Firebase.db_patch("rooms/%s/players/%s" % [code, Firebase.uid], _me())
	_busy = false
	_enter(code)
	return ""


func _enter(code: String) -> void:
	room_code = code
	players.clear()
	_edit_stream = Firebase.open_stream("rooms/%s/island" % code)
	var world := island
	_edit_stream.changed.connect(func(_ev: String, path: String, data: Variant):
		if is_instance_valid(world):
			world.sync.apply(path, data))
	_player_stream = Firebase.open_stream("rooms/%s/players" % code)
	_player_stream.changed.connect(_on_players)
	room_changed.emit()
	message.emit("Joined room %s" % code)


func leave_room() -> void:
	if not in_room():
		return
	var code := room_code
	_leave_quietly()
	Firebase.db_delete("rooms/%s/players/%s" % [code, Firebase.uid])
	if island:
		island.load_own()
	room_changed.emit()


func _leave_quietly() -> void:
	if _edit_stream:
		_edit_stream.close()
	if _player_stream:
		_player_stream.close()
	_edit_stream = null
	_player_stream = null
	room_code = ""
	players.clear()
	players_changed.emit()


func _on_players(ev: String, path: String, data: Variant) -> void:
	if path == "/":
		if ev == "put":
			players = data if data is Dictionary else {}
		elif data is Dictionary:
			for k in data:
				players[k] = data[k]
	else:
		var parts := path.trim_prefix("/").split("/")
		var id := parts[0]
		if parts.size() == 1:
			if data == null:
				players.erase(id)
			elif ev == "patch" and data is Dictionary and players.get(id) is Dictionary:
				players[id].merge(data, true)
			else:
				players[id] = data
		elif players.get(id) is Dictionary:
			players[id][parts[1]] = data
	players_changed.emit()


func active_players() -> Array:
	var out := []
	for id in players:
		if _active(players[id]) or id == Firebase.uid:
			var p: Dictionary = players[id].duplicate() if players[id] is Dictionary else {}
			p["id"] = id
			out.append(p)
	return out
