extends Node

signal heroes_updated(heroes: Array[Dictionary])
signal heroes_load_failed(message: String)
signal active_hero_changed(hero_id: int)
signal manager_error(message: String)

var _heroes: Array[Dictionary] = []
var _active_hero_id: int = -1

func get_heroes() -> Array[Dictionary]:
	return _heroes.duplicate(true)

func get_active_hero_id() -> int:
	if _active_hero_id > 0:
		return _active_hero_id
	if AppState.current_hero_id > 0:
		_active_hero_id = AppState.current_hero_id
	return _active_hero_id

func set_active_hero_id(hero_id: int) -> void:
	if hero_id <= 0:
		return
	if _active_hero_id == hero_id:
		return
	_active_hero_id = hero_id
	AppState.current_hero_id = hero_id
	active_hero_changed.emit(hero_id)

func get_hero_by_id(hero_id: int) -> Dictionary:
	for hero: Dictionary in _heroes:
		if int(hero.get("id", -1)) == hero_id:
			return hero.duplicate(true)
	return {}

func load_heroes() -> void:
	var response: Dictionary = await _perform_request(HTTPClient.METHOD_GET, "/heroes")
	if not bool(response.get("ok", false)):
		var msg: String = str(response.get("error", "Failed to load heroes"))
		heroes_load_failed.emit(msg)
		manager_error.emit(msg)
		return

	var parsed: Variant = response.get("data", {})
	_heroes = _extract_heroes(parsed)

	if _active_hero_id <= 0 and AppState.current_hero_id > 0:
		_active_hero_id = AppState.current_hero_id
	if _active_hero_id <= 0 and _heroes.size() > 0:
		_active_hero_id = int(_heroes[0].get("id", -1))
		if _active_hero_id > 0:
			AppState.current_hero_id = _active_hero_id

	heroes_updated.emit(get_heroes())
	if _active_hero_id > 0:
		active_hero_changed.emit(_active_hero_id)

func _extract_heroes(parsed: Variant) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	if parsed is Dictionary:
		var data: Dictionary = parsed
		if data.has("result") and data["result"] is Array:
			for item: Variant in (data["result"] as Array):
				if item is Dictionary:
					output.append((item as Dictionary).duplicate(true))
			return output
		if data.has("items") and data["items"] is Array:
			for item: Variant in (data["items"] as Array):
				if item is Dictionary:
					output.append((item as Dictionary).duplicate(true))
			return output
	elif parsed is Array:
		for item: Variant in (parsed as Array):
			if item is Dictionary:
				output.append((item as Dictionary).duplicate(true))
	return output

func _perform_request(method: int, path: String, payload: Dictionary = {}) -> Dictionary:
	var http: HTTPRequest = HTTPRequest.new()
	add_child(http)
	http.timeout = 12.0

	var headers: PackedStringArray = PackedStringArray(["Accept: application/json"])
	if not AppState.access_token.is_empty():
		headers.append("Authorization: Bearer %s" % AppState.access_token)

	var body_text: String = ""
	if method != HTTPClient.METHOD_GET and method != HTTPClient.METHOD_DELETE:
		headers.append("Content-Type: application/json")
		body_text = JSON.stringify(payload)

	var err: int = http.request(ServerConfig.get_instance().get_http_endpoint(path), headers, method, body_text)
	if err != OK:
		http.queue_free()
		return {"ok": false, "error": "Failed to send request", "data": {}}

	var result: Array = await http.request_completed
	http.queue_free()
	if result.size() < 4:
		return {"ok": false, "error": "Unexpected response", "data": {}}

	var req_result: int = int(result[0])
	var code: int = int(result[1])
	var body: PackedByteArray = result[3]
	var parsed: Variant = _parse_json(body)
	if req_result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
		return {"ok": false, "error": _extract_error(parsed, "Request failed"), "data": parsed}
	return {"ok": true, "error": "", "data": parsed}

func _parse_json(body: PackedByteArray) -> Variant:
	var json: JSON = JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		return {}
	return json.data

func _extract_error(parsed: Variant, fallback: String) -> String:
	if parsed is Dictionary:
		var data: Dictionary = parsed
		if data.has("detail"):
			return str(data.get("detail", fallback))
		if data.has("message"):
			return str(data.get("message", fallback))
	return fallback
