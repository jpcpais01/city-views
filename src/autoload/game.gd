extends Node
## What the player keeps from island to island: their name and their settings.

var player_name := "Mayor"
var settings := {"music": true, "sfx": true, "shadows": true, "fps": true}
## true while the pause menu covers the city: the camera keys stand still
var menu_open := false

const SETTINGS_PATH := "user://settings.json"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		save_settings()


## Rounds up to a number that reads well on a goal: 37 -> 40, 212 -> 220.
static func _nice(n: float) -> int:
	var step := 5.0 if n < 100 else (10.0 if n < 500 else (50.0 if n < 2000 else 100.0))
	return int(ceilf(n / step) * step)


func save_settings() -> void:
	var s := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if s:
		s.store_string(JSON.stringify({"settings": settings, "player": player_name}))


func load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var s: Variant = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS_PATH))
	if s is Dictionary:
		var st: Variant = s.get("settings", {})
		if st is Dictionary:
			settings.merge(st, true)
		player_name = str(s.get("player", player_name))
