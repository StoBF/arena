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
		var status: int = int(response.get("status", 0))
		print("[HeroManager] load_heroes failed (status=%d): %s" % [status, msg])
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
	var response: Dictionary = {}
	match method:
		HTTPClient.METHOD_GET:
			response = await ApiClient.get(path)
		HTTPClient.METHOD_POST:
			response = await ApiClient.post(path, payload)
		HTTPClient.METHOD_PATCH:
			response = await ApiClient.patch(path, payload)
		HTTPClient.METHOD_DELETE:
			response = await ApiClient.delete(path)
		_:
			response = await ApiClient.request_json(path, method, payload)

	var ok: bool = bool(response.get("ok", false))
	var status: int = int(response.get("status", response.get("code", 0)))
	var data: Variant = response.get("data", {})
	var error_message: String = str(response.get("error", response.get("message", "Request failed")))

	if ok:
		error_message = ""
	elif error_message.is_empty():
		error_message = "Request failed"

	return {
		"ok": ok,
		"status": status,
		"error": error_message,
		"data": data
	}
