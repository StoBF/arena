extends Node
class_name HeroManager

signal heroes_updated(heroes: Array)
signal heroes_load_failed(message: String)
signal active_hero_changed(hero_id: int)

var _heroes: Array = []
var _active_hero_id: int = -1

func get_heroes() -> Array:
	return _heroes.duplicate(true)

func load_heroes() -> void:
	var req = Network.request("/heroes/", HTTPClient.METHOD_GET)
	req.request_completed.connect(_on_heroes_response)

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
	for hero in _heroes:
		if int(hero.get("id", -1)) == hero_id:
			return hero
	return {}

func _on_heroes_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		heroes_load_failed.emit("Failed to load heroes")
		return

	var parsed = _parse_json(body)
	var heroes: Array = []
	if typeof(parsed) == TYPE_DICTIONARY and parsed.has("result") and parsed["result"] is Array:
		heroes = parsed["result"]
	elif parsed is Array:
		heroes = parsed

	_heroes = heroes.duplicate(true)
	if _active_hero_id <= 0 and AppState.current_hero_id > 0:
		_active_hero_id = AppState.current_hero_id
	if _active_hero_id <= 0 and not _heroes.is_empty():
		_active_hero_id = int(_heroes[0].get("id", -1))
		if _active_hero_id > 0:
			AppState.current_hero_id = _active_hero_id

	heroes_updated.emit(get_heroes())
	if _active_hero_id > 0:
		active_hero_changed.emit(_active_hero_id)

func _parse_json(body: PackedByteArray) -> Variant:
	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		return []
	return json.data
