extends Node
## Firebase over REST: Auth (guest + email), Realtime Database reads/writes and
## server-sent-event streams. Config comes from res://config/firebase.json
## (written by CI from repository secrets) so the game still runs offline without it.

signal auth_changed
signal status(text: String)

const AUTH_FILE := "user://auth.json"

var api_key := ""
var db_url := ""
var enabled := false

var uid := ""
var id_token := ""
var refresh_token := ""
var email := ""
var is_guest := true
var signed_in := false
var _token_expiry := 0.0
var _refreshing := false


func _ready() -> void:
	_load_config()
	if not enabled:
		return
	_load_auth()
	if refresh_token != "":
		await refresh()
	else:
		await sign_in_guest()
	if signed_in:
		await _maybe_pull_cloud_save()


func _load_config() -> void:
	for path in ["user://firebase.json", "res://config/firebase.json"]:
		if FileAccess.file_exists(path):
			var cfg = JSON.parse_string(FileAccess.get_file_as_string(path))
			if cfg is Dictionary and str(cfg.get("api_key", "")) != "" and str(cfg.get("database_url", "")) != "":
				api_key = str(cfg.api_key)
				db_url = str(cfg.database_url).trim_suffix("/")
				enabled = true
				return


func _load_auth() -> void:
	if FileAccess.file_exists(AUTH_FILE):
		var d = JSON.parse_string(FileAccess.get_file_as_string(AUTH_FILE))
		if d is Dictionary:
			refresh_token = str(d.get("refresh", ""))
			email = str(d.get("email", ""))
			is_guest = email == ""


func _save_auth() -> void:
	var f := FileAccess.open(AUTH_FILE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"refresh": refresh_token, "email": email}))


# ------------------------------------------------------------------ http

## Performs a request and returns {"ok": bool, "code": int, "data": Variant}.
func request(method: int, url: String, body: Variant = null, form := false) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = 20.0
	add_child(http)
	var headers := PackedStringArray()
	var payload := ""
	if body != null:
		if form:
			headers.append("Content-Type: application/x-www-form-urlencoded")
			payload = str(body)
		else:
			headers.append("Content-Type: application/json")
			payload = JSON.stringify(body)
	var err := http.request(url, headers, method, payload)
	if err != OK:
		http.queue_free()
		return {"ok": false, "code": 0, "data": null}
	var res: Array = await http.request_completed
	http.queue_free()
	var code: int = res[1]
	var text: String = (res[3] as PackedByteArray).get_string_from_utf8()
	var data = JSON.parse_string(text) if text != "" else null
	return {"ok": res[0] == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300, "code": code, "data": data}


func _auth_url(endpoint: String) -> String:
	return "https://identitytoolkit.googleapis.com/v1/accounts:%s?key=%s" % [endpoint, api_key]


func _apply_auth(d: Variant) -> bool:
	if not d is Dictionary:
		return false
	id_token = str(d.get("idToken", d.get("id_token", "")))
	refresh_token = str(d.get("refreshToken", d.get("refresh_token", refresh_token)))
	uid = str(d.get("localId", d.get("user_id", uid)))
	if d.has("email") and str(d.email) != "":
		email = str(d.email)
	is_guest = email == ""
	_token_expiry = Time.get_unix_time_from_system() + float(d.get("expiresIn", d.get("expires_in", 3600))) - 120.0
	signed_in = id_token != "" and uid != ""
	_save_auth()
	auth_changed.emit()
	return signed_in


func _error_text(r: Dictionary) -> String:
	if r.data is Dictionary and r.data.has("error"):
		var msg := str(r.data.error.get("message", "Error")) if r.data.error is Dictionary else str(r.data.error)
		match msg:
			"EMAIL_EXISTS": return "That email already has an account"
			"EMAIL_NOT_FOUND", "INVALID_PASSWORD", "INVALID_LOGIN_CREDENTIALS": return "Wrong email or password"
			"WEAK_PASSWORD : Password should be at least 6 characters": return "Password needs 6+ characters"
			"INVALID_EMAIL": return "That email doesn't look right"
		return msg.capitalize()
	return "Can't reach the server"


func sign_in_guest() -> String:
	if not enabled:
		return "Online features are not configured"
	var r := await request(HTTPClient.METHOD_POST, _auth_url("signUp"), {"returnSecureToken": true})
	if r.ok and _apply_auth(r.data):
		return ""
	return _error_text(r)


func sign_in_email(mail: String, password: String) -> String:
	if not enabled:
		return "Online features are not configured"
	var r := await request(HTTPClient.METHOD_POST, _auth_url("signInWithPassword"), {"email": mail, "password": password, "returnSecureToken": true})
	if r.ok:
		email = mail
		_apply_auth(r.data)
		await _maybe_pull_cloud_save(true)
		return ""
	return _error_text(r)


## Creates an email account. If currently a guest, the guest account is upgraded (keeps the city).
func register_email(mail: String, password: String) -> String:
	if not enabled:
		return "Online features are not configured"
	var r: Dictionary
	if signed_in and is_guest:
		await ensure_token()
		r = await request(HTTPClient.METHOD_POST, _auth_url("update"), {"idToken": id_token, "email": mail, "password": password, "returnSecureToken": true})
	else:
		r = await request(HTTPClient.METHOD_POST, _auth_url("signUp"), {"email": mail, "password": password, "returnSecureToken": true})
	if r.ok:
		email = mail
		_apply_auth(r.data)
		save_city(Game.to_dict())
		return ""
	return _error_text(r)


func sign_out() -> void:
	uid = ""
	id_token = ""
	refresh_token = ""
	email = ""
	signed_in = false
	is_guest = true
	_save_auth()
	auth_changed.emit()
	await sign_in_guest()


func refresh() -> bool:
	if refresh_token == "" or _refreshing:
		return signed_in
	_refreshing = true
	var r := await request(HTTPClient.METHOD_POST, "https://securetoken.googleapis.com/v1/token?key=" + api_key,
		"grant_type=refresh_token&refresh_token=" + refresh_token.uri_encode(), true)
	_refreshing = false
	if r.ok:
		return _apply_auth(r.data)
	if r.code == 400:
		# refresh token revoked: start over as a guest
		refresh_token = ""
		await sign_in_guest()
	return signed_in


func ensure_token() -> bool:
	if not signed_in:
		return false
	if Time.get_unix_time_from_system() > _token_expiry:
		return await refresh()
	return true


# ------------------------------------------------------------------ database

func db_path_url(path: String, extra := "") -> String:
	return "%s/%s.json?auth=%s%s" % [db_url, path.trim_prefix("/"), id_token, extra]


func db_get(path: String) -> Dictionary:
	if not await ensure_token():
		return {"ok": false, "data": null, "code": 0}
	return await request(HTTPClient.METHOD_GET, db_path_url(path))


func db_put(path: String, value: Variant) -> Dictionary:
	if not await ensure_token():
		return {"ok": false, "data": null, "code": 0}
	return await request(HTTPClient.METHOD_PUT, db_path_url(path, "&print=silent"), value)


func db_patch(path: String, value: Dictionary) -> Dictionary:
	if not await ensure_token():
		return {"ok": false, "data": null, "code": 0}
	return await request(HTTPClient.METHOD_PATCH, db_path_url(path, "&print=silent"), value)


func db_delete(path: String) -> Dictionary:
	if not await ensure_token():
		return {"ok": false, "data": null, "code": 0}
	return await request(HTTPClient.METHOD_DELETE, db_path_url(path))


func open_stream(path: String) -> FirebaseStream:
	var s := FirebaseStream.new()
	s.path = path
	add_child(s)
	return s


# ------------------------------------------------------------------ saves

func save_city(d: Dictionary) -> void:
	if not signed_in:
		return
	db_put("users/%s/city" % uid, d)


func _maybe_pull_cloud_save(force := false) -> void:
	var r := await db_get("users/%s/city" % uid)
	if not r.ok or not r.data is Dictionary:
		return
	var cloud: Dictionary = r.data
	var local_time := float(Game.to_dict().get("time", 0.0)) if not force else 0.0
	if FileAccess.file_exists("user://city.json") and not force:
		var d = JSON.parse_string(FileAccess.get_file_as_string("user://city.json"))
		if d is Dictionary:
			local_time = float(d.get("time", 0.0))
	if force or float(cloud.get("time", 0.0)) > local_time + 5.0:
		if not Net.in_room():
			Game.from_dict(cloud)
			Game.toast.emit("Cloud save loaded", "info")
