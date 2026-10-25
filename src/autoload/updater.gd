extends CanvasLayer
## In-game updates: checks the latest GitHub release a few seconds after
## start, and if it is newer than this build shows a small glass card. On
## Android tapping it downloads the signed APK and hands it to the system
## installer; on Windows it downloads the zip, unpacks it, and a little batch
## script swaps the files in once the game has quit, then starts it again.

const REPO := "jpcpais01/city-views"
const API := "https://api.github.com/repos/%s/releases/latest" % REPO
## the patch notes as they stand in a release's tagged source
const NOTES := "https://raw.githubusercontent.com/%s/%s/PATCH_NOTES.md"
const NOTES_MAX := 40
const RECHECK := 900.0  # the Windows zip lands a few minutes after the APK

const INK := Color("f5f7fb")
const SOFT := Color(0.92, 0.94, 0.98, 0.66)
const ACCENT := Color("ff7a6b")
const GLASS := Color(0.075, 0.09, 0.125)

enum State { IDLE, OFFER, DOWNLOADING, READY, FAILED }

## the answer to a check the player asked for (see check_now): "newer" (the
## card is showing), "latest", "pending" (a new version whose download isn't
## attached yet), "failed" or "unsupported" (a build that can't update itself)
signal checked(status: String, version: String)

var current := ""
var latest := ""
var _asset_url := ""
var _page_url := ""
var _state := State.IDLE
var _http: HTTPRequest
var _dl: HTTPRequest
var _file := ""
var _card: PanelContainer
var _title: Label
var _sub: Label
var _bar: ProgressBar
var _go: Button
var _close: Button
var _notes_http: HTTPRequest
# what the new version adds, as BBCode; empty until it has been fetched
var _notes := ""
var _notes_btn: Button
var _notes_box: ScrollContainer
var _notes_label: RichTextLabel
var _notes_open := false
var _dismissed := false
# a check the player asked for is under way, so its answer is reported
var _manual := false


func _ready() -> void:
	layer = 6
	current = str(ProjectSettings.get_setting("application/config/version", "0.1.0"))
	# local and editor builds carry the placeholder version and never update
	if OS.has_feature("editor") or current == "0.1.0" or not (_android() or _windows()):
		return
	_clean_old()
	_http = HTTPRequest.new()
	_http.timeout = 20.0
	_http.request_completed.connect(_on_release)
	add_child(_http)
	var t := Timer.new()
	t.wait_time = RECHECK
	t.timeout.connect(_check)
	add_child(t)
	t.start()
	get_tree().create_timer(6.0).timeout.connect(_check)


## Whether this build can update itself.
func supported() -> bool:
	return _http != null


## Looks for a newer version right now (the Settings button): the card shows
## if there is one, even if it was closed earlier; `checked` reports back.
func check_now() -> void:
	if not supported():
		checked.emit.call_deferred("unsupported", current)
		return
	if _state == State.DOWNLOADING or _state == State.READY or _state == State.FAILED:
		_dismissed = false
		_build_card()
		_pop_in()
		checked.emit.call_deferred("newer", latest)
		return
	_manual = true
	if _http.get_http_client_status() == HTTPClient.STATUS_DISCONNECTED:
		_check()


func _android() -> bool:
	return OS.get_name() == "Android"


func _windows() -> bool:
	return OS.get_name() == "Windows"


## "0.1.57" -> [0, 1, 57]; a leading "v" is ignored.
static func parse_version(v: String) -> PackedInt32Array:
	var out := PackedInt32Array()
	for p in v.trim_prefix("v").split("."):
		out.append(p.to_int())
	return out


static func is_newer(a: String, b: String) -> bool:
	var x := parse_version(a)
	var y := parse_version(b)
	for i in maxi(x.size(), y.size()):
		var xi := x[i] if i < x.size() else 0
		var yi := y[i] if i < y.size() else 0
		if xi != yi:
			return xi > yi
	return false


func _dir() -> String:
	return OS.get_user_data_dir().path_join("update")


## Drop leftovers from updates that are now installed.
func _clean_old() -> void:
	var d := _dir()
	if DirAccess.dir_exists_absolute(d):
		_remove_tree(d)


func _remove_tree(path: String) -> void:
	var da := DirAccess.open(path)
	if da == null:
		return
	for f in da.get_files():
		da.remove(f)
	for sub in da.get_directories():
		_remove_tree(path.path_join(sub))
	DirAccess.remove_absolute(path)


func _check() -> void:
	if _state != State.IDLE and _state != State.OFFER:
		return
	if _http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	_http.request(API, ["User-Agent: CityViews/" + current, "Accept: application/vnd.github+json"])


func _on_release(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var manual := _manual
	_manual = false
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		if manual:
			checked.emit("failed", current)
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if not (data is Dictionary):
		if manual:
			checked.emit("failed", current)
		return
	var tag := str(data.get("tag_name", ""))
	if tag == "" or not is_newer(tag, current):
		if manual:
			checked.emit("latest", current)
		return
	var want := ".apk" if _android() else "windows.zip"
	var url := ""
	for a in data.get("assets", []):
		if str(a.get("name", "")).to_lower().ends_with(want):
			url = str(a.get("browser_download_url", ""))
	if url == "":
		# not attached yet: the next check picks it up
		if manual:
			checked.emit("pending", tag.trim_prefix("v"))
		return
	var fresh := tag.trim_prefix("v") != latest
	latest = tag.trim_prefix("v")
	_asset_url = url
	_page_url = str(data.get("html_url", ""))
	_state = State.OFFER
	if fresh or _notes == "":
		_fetch_notes(tag)
	if fresh or manual:
		_dismissed = false
	if not _dismissed:
		_show_offer()
	if manual:
		checked.emit("newer", latest)


# ------------------------------------------------------------------ card

func _build_card() -> void:
	if _card:
		return
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_card = PanelContainer.new()
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://src/ui/glass.gdshader")
	mat.set_shader_parameter("tint", 0.7)
	_card.material = mat
	var sb := StyleBoxFlat.new()
	sb.bg_color = GLASS
	sb.set_corner_radius_all(22)
	sb.corner_detail = 5
	sb.content_margin_left = 16
	sb.content_margin_right = 10
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	sb.border_color = Color(1, 1, 1, 0.16)
	sb.border_width_top = 1
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_blend = true
	sb.anti_aliasing = true
	sb.shadow_color = Color(0.05, 0.1, 0.2, 0.14)
	sb.shadow_size = 14
	sb.shadow_offset = Vector2(0, 6)
	_card.add_theme_stylebox_override("panel", sb)
	# top centre, clear of the island card on the left and the buttons on the right
	_card.anchor_left = 0.5
	_card.anchor_right = 0.5
	_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_card.offset_top = 14
	_card.custom_minimum_size = Vector2(330, 0)
	root.add_child(_card)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	_card.add_child(outer)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	outer.add_child(row)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 2)
	row.add_child(col)
	var bold := FontVariation.new()
	bold.base_font = load("res://assets/fonts/Manrope.ttf")
	bold.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 800}
	_title = Label.new()
	_title.add_theme_font_override("font", bold)
	_title.add_theme_font_size_override("font_size", 19)
	_title.add_theme_color_override("font_color", INK)
	col.add_child(_title)
	_sub = Label.new()
	_sub.add_theme_font_size_override("font_size", 14)
	_sub.add_theme_color_override("font_color", SOFT)
	col.add_child(_sub)
	# "What's new" folds open a list of everything the update brings
	_notes_btn = Button.new()
	_notes_btn.flat = true
	_notes_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_notes_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_notes_btn.custom_minimum_size.y = 30
	_notes_btn.add_theme_font_override("font", bold)
	_notes_btn.add_theme_font_size_override("font_size", 15)
	for s in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		_notes_btn.add_theme_color_override(s, ACCENT)
	for s in ["normal", "hover", "pressed", "focus"]:
		_notes_btn.add_theme_stylebox_override(s, StyleBoxEmpty.new())
	_notes_btn.pressed.connect(func(): _set_notes_open(not _notes_open))
	_notes_btn.visible = false
	col.add_child(_notes_btn)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 6)
	_bar.max_value = 1.0
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.12)
	bg.set_corner_radius_all(3)
	var fg := StyleBoxFlat.new()
	fg.bg_color = ACCENT
	fg.set_corner_radius_all(3)
	_bar.add_theme_stylebox_override("background", bg)
	_bar.add_theme_stylebox_override("fill", fg)
	col.add_child(_bar)

	_go = Button.new()
	_go.custom_minimum_size = Vector2(104, 44)
	_go.add_theme_font_override("font", bold)
	_go.add_theme_font_size_override("font_size", 16)
	for s in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		_go.add_theme_color_override(s, Color.WHITE)
	for s in ["normal", "hover", "pressed", "focus"]:
		var b := StyleBoxFlat.new()
		b.bg_color = ACCENT.darkened(0.08) if s == "pressed" else ACCENT
		b.set_corner_radius_all(16)
		b.anti_aliasing = true
		_go.add_theme_stylebox_override(s, b)
	_go.pressed.connect(_on_go)
	_go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_go)

	_close = Button.new()
	_close.text = "×"
	_close.flat = true
	_close.custom_minimum_size = Vector2(36, 44)
	_close.add_theme_font_size_override("font_size", 24)
	_close.add_theme_color_override("font_color", SOFT)
	_close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_close.pressed.connect(_hide_card)
	row.add_child(_close)

	_notes_box = ScrollContainer.new()
	_notes_box.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_notes_box.visible = false
	outer.add_child(_notes_box)
	_notes_label = RichTextLabel.new()
	_notes_label.bbcode_enabled = true
	_notes_label.fit_content = true
	_notes_label.scroll_active = false
	_notes_label.mouse_filter = Control.MOUSE_FILTER_PASS
	_notes_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_notes_label.add_theme_font_override("normal_font", load("res://assets/fonts/Manrope.ttf"))
	_notes_label.add_theme_font_override("bold_font", bold)
	_notes_label.add_theme_font_size_override("normal_font_size", 15)
	_notes_label.add_theme_font_size_override("bold_font_size", 15)
	_notes_label.add_theme_color_override("default_color", INK)
	_notes_box.add_child(_notes_label)
	_refresh_notes()


func _pop_in() -> void:
	if _card.visible and _card.modulate.a > 0.99:
		return
	_card.visible = true
	_card.modulate.a = 0.0
	_card.pivot_offset = _card.size * Vector2(0.5, 0.0)
	_card.scale = Vector2(0.85, 0.85)
	var tw := create_tween().set_parallel()
	tw.tween_property(_card, "modulate:a", 1.0, 0.25)
	tw.tween_property(_card, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _hide_card() -> void:
	_dismissed = true
	if _state == State.DOWNLOADING:
		_dl.cancel_request()
		_state = State.OFFER
	var tw := create_tween()
	tw.tween_property(_card, "modulate:a", 0.0, 0.18)
	tw.tween_callback(func(): _card.visible = false)


func _show_offer() -> void:
	_build_card()
	_title.text = "Update available"
	_sub.text = "Version %s  ·  you have %s" % [latest, current]
	_bar.visible = false
	_go.text = "Update"
	_go.disabled = false
	_pop_in()


# ------------------------------------------------------------------ what's new

func _fetch_notes(tag: String) -> void:
	if _notes_http == null:
		_notes_http = HTTPRequest.new()
		_notes_http.timeout = 20.0
		_notes_http.request_completed.connect(_on_notes)
		add_child(_notes_http)
	if _notes_http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	_notes_http.request(NOTES % [REPO, tag], ["User-Agent: CityViews/" + current])


func _on_notes(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	var mine := ""
	if FileAccess.file_exists("res://PATCH_NOTES.md"):
		mine = FileAccess.get_file_as_string("res://PATCH_NOTES.md")
	_notes = new_notes(mine, body.get_string_from_utf8())
	_refresh_notes()


## The entries in the newer patch notes that this build's own notes don't
## have yet, kept under their hour headings, as BBCode (newest first).
static func new_notes(mine: String, theirs: String) -> String:
	var have := {}
	for line in mine.split("\n"):
		if line.begins_with("- "):
			have[line.strip_edges()] = true
	var out := ""
	var head := ""
	var count := 0
	for line in theirs.split("\n"):
		if line.begins_with("## "):
			head = line.substr(3).strip_edges()
		elif line.begins_with("- ") and not have.has(line.strip_edges()):
			if count >= NOTES_MAX:
				out += "[color=#6b7785]…and more[/color]\n"
				break
			if head != "":
				out += "%s[b]%s[/b]\n" % ["\n" if out != "" else "", head]
				head = ""
			out += "•  %s\n" % line.substr(2).strip_edges()
			count += 1
	return out.strip_edges()


func _refresh_notes() -> void:
	if _card == null:
		return
	_notes_label.text = _notes
	_notes_btn.visible = _notes != ""
	_set_notes_open(_notes_open and _notes != "")


func _set_notes_open(on: bool) -> void:
	_notes_open = on
	_notes_btn.text = "What's new  ▴" if on else "What's new  ▾"
	_notes_box.visible = on
	var view := get_viewport().get_visible_rect().size
	_notes_box.custom_minimum_size.y = minf(300.0, view.y * 0.5) if on else 0.0
	# wider while open so the notes read comfortably, never past the screen
	_card.custom_minimum_size.x = minf(480.0, view.x * 0.9) if on else 330.0
	_card.reset_size()


func _show_failed(msg: String) -> void:
	_state = State.FAILED
	_title.text = "Update didn't finish"
	_sub.text = msg
	_bar.visible = false
	_go.text = "Retry"
	_go.disabled = false


# ------------------------------------------------------------------ download

func _on_go() -> void:
	match _state:
		State.OFFER, State.FAILED:
			_download()
		State.READY:
			_install()


func _download() -> void:
	DirAccess.make_dir_recursive_absolute(_dir())
	_file = _dir().path_join("CityViews-%s.%s" % [latest, "apk" if _android() else "zip"])
	if _dl == null:
		_dl = HTTPRequest.new()
		_dl.download_chunk_size = 262144
		_dl.request_completed.connect(_on_downloaded)
		add_child(_dl)
	_dl.download_file = _file
	if _dl.request(_asset_url, ["User-Agent: CityViews/" + current]) != OK:
		_show_failed("Couldn't reach GitHub. Check your connection.")
		return
	_state = State.DOWNLOADING
	_title.text = "Downloading %s" % latest
	_sub.text = "Starting…"
	_bar.value = 0.0
	_bar.visible = true
	_go.text = "…"
	_go.disabled = true


func _process(_delta: float) -> void:
	if _state != State.DOWNLOADING:
		return
	var got := _dl.get_downloaded_bytes()
	var total := _dl.get_body_size()
	if total > 0:
		_bar.value = float(got) / total
		_sub.text = "%d%%  ·  %.1f of %.1f MB" % [roundi(100.0 * got / total), got / 1048576.0, total / 1048576.0]
	elif got > 0:
		_sub.text = "%.1f MB" % (got / 1048576.0)


func _on_downloaded(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	if _state != State.DOWNLOADING:
		return
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_show_failed("Download stopped (%s). Tap Retry." % (str(code) if code else "no connection"))
		return
	_bar.value = 1.0
	if _windows():
		_title.text = "Unpacking %s" % latest
		_sub.text = "Almost there…"
		await get_tree().process_frame
		var err := _unpack()
		if err != "":
			_show_failed(err)
			return
	_state = State.READY
	_title.text = "Update ready"
	_sub.text = "Tap Install, then confirm" if _android() else "The game restarts to finish"
	_go.text = "Install" if _android() else "Restart"
	_go.disabled = false
	_install()


func _install() -> void:
	if _android():
		# Godot hands a local path to its FileProvider, so the system package
		# installer opens on the APK. The first time Android asks to allow
		# installs from City Views; the card stays up to try again after that.
		if OS.shell_open(_file) != OK:
			_show_failed("Couldn't open the installer.")
	elif _windows():
		_restart_windows()


# ------------------------------------------------------------------ windows

func _staged() -> String:
	return _dir().path_join("staged")


func _unpack() -> String:
	var zip := ZIPReader.new()
	if zip.open(_file) != OK:
		return "The download was damaged. Tap Retry."
	var out := _staged()
	for f in zip.get_files():
		if f.ends_with("/"):
			continue
		var dest := out.path_join(f)
		DirAccess.make_dir_recursive_absolute(dest.get_base_dir())
		var fa := FileAccess.open(dest, FileAccess.WRITE)
		if fa == null:
			zip.close()
			return "Couldn't write the new files."
		fa.store_buffer(zip.read_file(f))
		fa.close()
	zip.close()
	DirAccess.remove_absolute(_file)
	return ""


func _restart_windows() -> void:
	var exe := OS.get_executable_path()
	var game_dir := exe.get_base_dir()
	# a game unzipped somewhere read-only can't replace itself: send them to the release page
	var probe := game_dir.path_join(".cv_write_test")
	var fa := FileAccess.open(probe, FileAccess.WRITE)
	if fa == null:
		OS.shell_open(_page_url)
		_show_failed("This folder is read-only, so the download page is open instead.")
		return
	fa.close()
	DirAccess.remove_absolute(probe)
	var pid := OS.get_process_id()
	var win := func(p: String) -> String: return p.replace("/", "\\")
	var bat := _dir().path_join("apply_update.bat")
	var lines := [
		"@echo off",
		":wait",
		"tasklist /FI \"PID eq %d\" 2>nul | find \" %d \" >nul" % [pid, pid],
		"if not errorlevel 1 (ping -n 2 127.0.0.1 >nul & goto wait)",
		"robocopy \"%s\" \"%s\" /E /MOVE /R:10 /W:1 >nul" % [win.call(_staged()), win.call(game_dir)],
		"start \"\" \"%s\"" % win.call(exe),
		"(goto) 2>nul & del \"%~f0\"",
	]
	var f := FileAccess.open(bat, FileAccess.WRITE)
	if f == null:
		_show_failed("Couldn't prepare the update.")
		return
	f.store_string("\r\n".join(PackedStringArray(lines)) + "\r\n")
	f.close()
	if OS.create_process("cmd.exe", ["/c", win.call(bat)]) <= 0:
		_show_failed("Couldn't start the updater.")
		return
	# save the island and settings before the files are swapped
	for n in get_tree().root.find_children("*", "", true, false):
		var sc = n.get_script()
		if sc and sc.get_global_name() == &"IslandWorld" and n.has_method("_save"):
			n.call("_save")
	get_tree().root.propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST)
	get_tree().quit()
