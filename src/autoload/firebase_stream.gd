class_name FirebaseStream
extends Node
## Listens to a Realtime Database location with the REST streaming API (server-sent events).

signal changed(event: String, path: String, data: Variant)

var path := ""
var _client := HTTPClient.new()
var _host := ""
var _req_path := ""
var _requested := false
var _headers_done := false
var _buf := PackedByteArray()
var _retry := 0.0
var _closed := false
var _redirect := ""
var _connecting := false


func _ready() -> void:
	_connect()


func close() -> void:
	_closed = true
	_client.close()
	queue_free()


func _connect() -> void:
	_client.close()
	_requested = false
	_headers_done = false
	_buf.clear()
	_connecting = true
	var ok: bool = await Firebase.ensure_token()
	_connecting = false
	if _closed:
		return
	if not ok:
		_retry = 3.0
		return
	var url := _redirect if _redirect != "" else Firebase.db_path_url(path)
	_redirect = ""
	var rest := url.trim_prefix("https://")
	var slash := rest.find("/")
	_host = rest.substr(0, slash)
	_req_path = rest.substr(slash)
	var err := _client.connect_to_host(_host, 443, TLSOptions.client())
	if err != OK:
		_retry = 3.0


func _process(delta: float) -> void:
	if _closed or _connecting:
		return
	if _retry > 0.0:
		_retry -= delta
		if _retry <= 0.0:
			_connect()
		return
	_client.poll()
	match _client.get_status():
		HTTPClient.STATUS_CONNECTED:
			if not _requested:
				_requested = true
				_client.request(HTTPClient.METHOD_GET, _req_path, ["Accept: text/event-stream"])
			elif _headers_done:
				_retry = 1.0  # server ended the stream, reconnect
		HTTPClient.STATUS_BODY:
			if not _headers_done:
				_headers_done = true
				var code := _client.get_response_code()
				if code == 307 or code == 302:
					var h := _client.get_response_headers_as_dictionary()
					_redirect = str(h.get("Location", h.get("location", "")))
					_retry = 0.05
					return
				if code != 200:
					_retry = 5.0
					return
			var chunk := _client.read_response_body_chunk()
			if chunk.size() > 0:
				_buf.append_array(chunk)
				_parse()
		HTTPClient.STATUS_DISCONNECTED, HTTPClient.STATUS_CONNECTION_ERROR, HTTPClient.STATUS_CANT_CONNECT, HTTPClient.STATUS_CANT_RESOLVE, HTTPClient.STATUS_TLS_HANDSHAKE_ERROR:
			_retry = 3.0


func _parse() -> void:
	while true:
		var cut := -1
		for i in range(_buf.size() - 1):
			if _buf[i] == 10 and _buf[i + 1] == 10:
				cut = i
				break
		if cut < 0:
			return
		var block := _buf.slice(0, cut).get_string_from_utf8()
		_buf = _buf.slice(cut + 2)
		var ev := ""
		var data := ""
		for line in block.split("\n"):
			if line.begins_with("event:"):
				ev = line.substr(6).strip_edges()
			elif line.begins_with("data:"):
				data += line.substr(5).strip_edges()
		match ev:
			"put", "patch":
				var parsed = JSON.parse_string(data)
				if parsed is Dictionary:
					changed.emit(ev, str(parsed.get("path", "/")), parsed.get("data"))
			"auth_revoked", "cancel":
				await Firebase.refresh()
				_retry = 0.5
