extends Node
class_name InventoryManager

signal sig_inventory_updated
signal sig_item_equipped(hero_id: int)
signal sig_item_removed(item_id: int)

signal items_updated(items: Array)
signal items_load_failed(message: String)
signal equipment_changed(hero_id: int, slot_name: String, item_data: Dictionary)
signal item_lock_changed(item_id: int, locked: bool)

const EQUIPMENT_SLOTS := ["Helmet", "Armor", "Weapon", "Boots", "Ring", "Amulet"]

var _items: Array = []
var _items_by_hero: Dictionary = {}
var _equipment_by_hero: Dictionary = {}
var _last_loaded_hero_id: int = -1
var _last_error_code: String = ""
var _last_error_message: String = ""

func get_last_error_code() -> String:
	return _last_error_code

func get_last_error_message() -> String:
	return _last_error_message

func clear_error() -> void:
	_last_error_code = ""
	_last_error_message = ""

func get_items_for_hero(hero_id: int) -> Array:
	if hero_id <= 0:
		return []
	if _items_by_hero.has(hero_id):
		return (_items_by_hero[hero_id] as Array).duplicate(true)
	return []

func get_items_cached() -> Array:
	if _last_loaded_hero_id > 0 and _items_by_hero.has(_last_loaded_hero_id):
		return (_items_by_hero[_last_loaded_hero_id] as Array).duplicate(true)
	return _items.duplicate(true)

func get_items() -> Array:
	var hero_id := _last_loaded_hero_id
	if hero_id <= 0:
		hero_id = AppState.current_hero_id

	var path := "/inventory"
	if hero_id > 0:
		path = "%s?hero_id=%d" % [path, hero_id]

	var response := await _perform_request(HTTPClient.METHOD_GET, path)
	if not bool(response.get("ok", false)):
		items_load_failed.emit(_last_error_message)
		return get_items_cached()

	var parsed: Variant = response.get("data", {})
	_items = _extract_items(parsed)
	if hero_id > 0:
		_items_by_hero[hero_id] = _items.duplicate(true)
		_last_loaded_hero_id = hero_id
	_emit_inventory_changed()
	return _items.duplicate(true)

func load_items(hero_id: int = -1) -> void:
	if hero_id <= 0:
		hero_id = AppState.current_hero_id
	if hero_id <= 0:
		items_load_failed.emit("No active hero selected")
		return
	_last_loaded_hero_id = hero_id
	call_deferred("_load_items_async")

func _load_items_async() -> void:
	var _items_result: Array = await get_items()

func get_equipment(hero_id: int) -> Dictionary:
	if hero_id <= 0:
		return {}
	if not _equipment_by_hero.has(hero_id):
		_equipment_by_hero[hero_id] = {}
	return (_equipment_by_hero[hero_id] as Dictionary).duplicate(true)

func get_item_by_id(item_id: int, hero_id: int = -1) -> Dictionary:
	if item_id <= 0:
		return {}
	if hero_id <= 0:
		hero_id = _last_loaded_hero_id
	var source_items: Array = get_items_for_hero(hero_id)
	if source_items.is_empty() and hero_id == _last_loaded_hero_id:
		source_items = _items.duplicate(true)
	for item in source_items:
		if int(item.get("id", -1)) == item_id:
			return item.duplicate(true)
	return {}

func inspect_item(item_id: int, hero_id: int = -1) -> Dictionary:
	var local_item := get_item_by_id(item_id, hero_id)
	if item_id <= 0:
		return {}
	var response := await _perform_request(HTTPClient.METHOD_GET, "/items/%d" % item_id)
	if not bool(response.get("ok", false)):
		return local_item
	var parsed: Variant = response.get("data", {})
	if parsed is Dictionary and (parsed as Dictionary).has("result") and (parsed as Dictionary)["result"] is Dictionary:
		return ((parsed as Dictionary)["result"] as Dictionary).duplicate(true)
	if parsed is Dictionary:
		return (parsed as Dictionary).duplicate(true)
	return local_item

func equip_item_for_active_hero(item_id: int) -> bool:
	var hero_id := HeroManager.get_active_hero_id()
	if hero_id <= 0:
		return false
	var item := get_item_by_id(item_id, hero_id)
	if item.is_empty():
		return false
	var slot_type := resolve_slot_from_item(item)
	if slot_type.is_empty():
		return false
	return await equip_item(hero_id, item_id, slot_type)

func equip_item(hero_id: int, item_id: int, slot_type: String) -> bool:
	if hero_id <= 0 or item_id <= 0 or not EQUIPMENT_SLOTS.has(slot_type):
		return false

	var rollback := apply_optimistic_equip(hero_id, item_id, slot_type)
	var response := await _perform_request(HTTPClient.METHOD_PATCH, "/heroes/%d/equip" % hero_id, {
		"item_id": item_id,
		"slot_type": slot_type
	})
	if not bool(response.get("ok", false)):
		rollback_optimistic_equip(hero_id, slot_type, rollback)
		return false

	sig_item_equipped.emit(hero_id)
	return true

func unequip_item(hero_id: int, slot_type: String) -> bool:
	if hero_id <= 0 or slot_type.is_empty() or not EQUIPMENT_SLOTS.has(slot_type):
		return false

	if not _equipment_by_hero.has(hero_id):
		_equipment_by_hero[hero_id] = {}
	if not _items_by_hero.has(hero_id):
		_items_by_hero[hero_id] = []

	var eq: Dictionary = _equipment_by_hero[hero_id]
	var prev_item: Dictionary = {}
	if eq.has(slot_type):
		prev_item = (eq[slot_type] as Dictionary).duplicate(true)
		eq.erase(slot_type)
		(_items_by_hero[hero_id] as Array).append(prev_item)

	equipment_changed.emit(hero_id, slot_type, {})
	_emit_inventory_changed()

	var response := await _perform_request(HTTPClient.METHOD_PATCH, "/heroes/%d/equip" % hero_id, {
		"item_id": null,
		"slot_type": slot_type
	})
	if bool(response.get("ok", false)):
		return true

	if not prev_item.is_empty():
		eq[slot_type] = prev_item
		_remove_item_from_list(_items_by_hero[hero_id], int(prev_item.get("id", -1)))
	equipment_changed.emit(hero_id, slot_type, eq.get(slot_type, {}))
	_emit_inventory_changed()
	return false

func dismantle_item(item_id: int) -> bool:
	var hero_id := HeroManager.get_active_hero_id()
	if hero_id <= 0 or item_id <= 0:
		return false

	var snapshot := _remove_item_optimistic(hero_id, item_id)
	var response := await _perform_request(HTTPClient.METHOD_POST, "/inventory/%d/dismantle" % item_id, {})
	if not bool(response.get("ok", false)):
		_restore_removed_item(hero_id, snapshot)
		_emit_inventory_changed()
		return false

	sig_item_removed.emit(item_id)
	_emit_inventory_changed()
	return true

func lock_item(item_id: int, locked: bool) -> bool:
	var hero_id := HeroManager.get_active_hero_id()
	if hero_id <= 0 or item_id <= 0:
		return false

	var previous := bool(get_item_by_id(item_id, hero_id).get("is_locked", false))
	_update_item_in_cache(hero_id, item_id, {"is_locked": locked})
	item_lock_changed.emit(item_id, locked)
	_emit_inventory_changed()

	var response := await _perform_request(HTTPClient.METHOD_PATCH, "/inventory/%d/lock" % item_id, {"locked": locked})
	if not bool(response.get("ok", false)):
		_update_item_in_cache(hero_id, item_id, {"is_locked": previous})
		item_lock_changed.emit(item_id, previous)
		_emit_inventory_changed()
		return false
	return true

func set_item_lock(item_id: int, locked: bool) -> bool:
	return await lock_item(item_id, locked)

func toggle_item_lock(item_id: int) -> bool:
	var hero_id := HeroManager.get_active_hero_id()
	if hero_id <= 0 or item_id <= 0:
		return false
	var item := get_item_by_id(item_id, hero_id)
	if item.is_empty():
		return false
	return await lock_item(item_id, not bool(item.get("is_locked", false)))

func sell_item_on_auction(item_id: int, price: float = -1.0) -> bool:
	var hero_id := HeroManager.get_active_hero_id()
	if hero_id <= 0 or item_id <= 0:
		return false

	var item := get_item_by_id(item_id, hero_id)
	if item.is_empty():
		return false

	if price <= 0.0:
		price = float(item.get("sell_price", item.get("price", 1.0)))
	if price <= 0.0:
		price = 1.0

	var response := await _perform_request(HTTPClient.METHOD_POST, "/auctions/", {"item_id": item_id, "price": price})
	if not bool(response.get("ok", false)):
		return false

	_remove_item_from_cache(hero_id, item_id)
	sig_item_removed.emit(item_id)
	_emit_inventory_changed()
	return true

func is_item_valid_for_slot(item_id: int, slot_type: String, hero_id: int = -1) -> bool:
	if slot_type.is_empty() or not EQUIPMENT_SLOTS.has(slot_type):
		return false
	var item := get_item_by_id(item_id, hero_id)
	if item.is_empty():
		return false
	return resolve_slot_from_item(item) == slot_type

func apply_optimistic_equip(hero_id: int, item_id: int, slot_type: String) -> Dictionary:
	var snapshot := {
		"previous_slot_item": {},
		"item_removed": {},
		"used_swap": false
	}
	if hero_id <= 0 or not EQUIPMENT_SLOTS.has(slot_type):
		return snapshot

	if not _equipment_by_hero.has(hero_id):
		_equipment_by_hero[hero_id] = {}
	if not _items_by_hero.has(hero_id):
		_items_by_hero[hero_id] = []

	var eq: Dictionary = _equipment_by_hero[hero_id]
	var items: Array = _items_by_hero[hero_id]
	var new_item := get_item_by_id(item_id, hero_id)
	if new_item.is_empty():
		return snapshot

	if eq.has(slot_type):
		snapshot["previous_slot_item"] = (eq[slot_type] as Dictionary).duplicate(true)
		snapshot["used_swap"] = true
		items.append((snapshot["previous_slot_item"] as Dictionary).duplicate(true))

	eq[slot_type] = new_item.duplicate(true)

	for idx in range(items.size() - 1, -1, -1):
		if int(items[idx].get("id", -1)) == item_id:
			snapshot["item_removed"] = items[idx].duplicate(true)
			items.remove_at(idx)
			break

	_items_by_hero[hero_id] = items
	if _last_loaded_hero_id == hero_id:
		_items = items.duplicate(true)

	equipment_changed.emit(hero_id, slot_type, new_item.duplicate(true))
	_emit_inventory_changed()
	return snapshot

func rollback_optimistic_equip(hero_id: int, slot_type: String, snapshot: Dictionary) -> void:
	if hero_id <= 0 or not _equipment_by_hero.has(hero_id) or not _items_by_hero.has(hero_id):
		return

	var eq: Dictionary = _equipment_by_hero[hero_id]
	var items: Array = _items_by_hero[hero_id]

	if snapshot.has("item_removed") and snapshot["item_removed"] is Dictionary and not (snapshot["item_removed"] as Dictionary).is_empty():
		items.append((snapshot["item_removed"] as Dictionary).duplicate(true))

	if snapshot.has("used_swap") and bool(snapshot["used_swap"]):
		if snapshot.has("previous_slot_item") and snapshot["previous_slot_item"] is Dictionary:
			var previous_item: Dictionary = (snapshot["previous_slot_item"] as Dictionary).duplicate(true)
			eq[slot_type] = previous_item
			_remove_item_from_list(items, int(previous_item.get("id", -1)))
	else:
		eq.erase(slot_type)

	_items_by_hero[hero_id] = items
	if _last_loaded_hero_id == hero_id:
		_items = items.duplicate(true)

	equipment_changed.emit(hero_id, slot_type, eq.get(slot_type, {}))
	_emit_inventory_changed()

func calculate_hero_preview_stats(hero_data: Dictionary, equipment: Dictionary) -> Dictionary:
	var stats := {
		"name": hero_data.get("name", "Unknown Hero"),
		"level": int(hero_data.get("level", 1)),
		"power": int(hero_data.get("power", 0)),
		"strength": int(hero_data.get("strength", 0)),
		"agility": int(hero_data.get("agility", 0)),
		"health": int(hero_data.get("health", 0))
	}

	for slot_name in equipment.keys():
		var item: Dictionary = equipment[slot_name]
		stats["power"] += _item_power(item)
		stats["strength"] += int(item.get("strength_bonus", 0))
		stats["agility"] += int(item.get("agility_bonus", 0))
		stats["health"] += int(item.get("health_bonus", 0))

	return stats

func resolve_slot_from_item(item_data: Dictionary) -> String:
	var slot = str(item_data.get("slot", "")).strip_edges()
	if EQUIPMENT_SLOTS.has(slot):
		return slot

	var item_type := str(item_data.get("type", "")).to_lower()
	if item_type == "weapon":
		return "Weapon"
	if item_type == "armor":
		return "Armor"
	if item_type == "helmet":
		return "Helmet"
	if item_type == "boots":
		return "Boots"
	if item_type == "ring":
		return "Ring"
	if item_type == "amulet":
		return "Amulet"
	return ""

func calculate_stat_delta_for_equip(hero_id: int, item_id: int, slot_type: String) -> Dictionary:
	var hero_data := HeroManager.get_hero_by_id(hero_id)
	var current_equipment := get_equipment(hero_id)
	var before_stats := calculate_hero_preview_stats(hero_data, current_equipment)

	var next_equipment := current_equipment.duplicate(true)
	var item := get_item_by_id(item_id, hero_id)
	if item.is_empty():
		return {
			"power": 0,
			"strength": 0,
			"agility": 0,
			"health": 0
		}
	next_equipment[slot_type] = item
	var after_stats := calculate_hero_preview_stats(hero_data, next_equipment)

	return {
		"power": int(after_stats.get("power", 0)) - int(before_stats.get("power", 0)),
		"strength": int(after_stats.get("strength", 0)) - int(before_stats.get("strength", 0)),
		"agility": int(after_stats.get("agility", 0)) - int(before_stats.get("agility", 0)),
		"health": int(after_stats.get("health", 0)) - int(before_stats.get("health", 0))
	}

func _extract_items(parsed: Variant) -> Array:
	if parsed is Array:
		return (parsed as Array).duplicate(true)
	if parsed is Dictionary:
		var data: Dictionary = parsed
		if data.has("result") and data["result"] is Array:
			return (data["result"] as Array).duplicate(true)
		if data.has("items") and data["items"] is Array:
			return (data["items"] as Array).duplicate(true)
	return []

func _item_power(item: Dictionary) -> int:
	if item.has("power"):
		return int(item.get("power", 0))
	return int(item.get("attack", 0)) + int(item.get("defense", 0)) + int(item.get("stability", 0)) + int(item.get("energy", 0)) + int(item.get("durability", 0))

func _parse_json(body: PackedByteArray) -> Variant:
	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		return {}
	return json.data

func _perform_request(method: int, path: String, payload: Dictionary = {}, extra_headers: PackedStringArray = PackedStringArray()) -> Dictionary:
	clear_error()
	var http := HTTPRequest.new()
	add_child(http)
	http.timeout = 12.0

	var headers := PackedStringArray(["Accept: application/json"])
	for header in extra_headers:
		headers.append(header)
	if not AppState.access_token.is_empty():
		headers.append("Authorization: Bearer %s" % AppState.access_token)

	var body_text := ""
	if method != HTTPClient.METHOD_GET and method != HTTPClient.METHOD_DELETE:
		headers.append("Content-Type: application/json")
		body_text = JSON.stringify(payload)

	var url := ServerConfig.get_instance().get_http_endpoint(path)
	var err := http.request(url, headers, method, body_text)
	if err != OK:
		http.queue_free()
		_set_error("request_failed", "Failed to send request")
		return {"ok": false, "code": 0, "data": {}}

	var result: Array = await http.request_completed
	http.queue_free()
	if result.size() < 4:
		_set_error("request_failed", "Unexpected response")
		return {"ok": false, "code": 0, "data": {}}

	var req_result := int(result[0])
	var code := int(result[1])
	var body: PackedByteArray = result[3]
	var parsed := _parse_json(body)
	if req_result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
		var msg := _extract_error_message(parsed, "Request failed")
		_set_error(_classify_error(code, msg), msg)
		return {"ok": false, "code": code, "data": parsed}

	return {"ok": true, "code": code, "data": parsed}

func _extract_error_message(data: Variant, fallback: String) -> String:
	if data is Dictionary:
		var parsed: Dictionary = data
		if parsed.has("detail"):
			return str(parsed.get("detail", fallback))
		if parsed.has("message"):
			return str(parsed.get("message", fallback))
	return fallback

func _classify_error(code: int, message: String) -> String:
	var m := message.to_lower()
	if m.contains("insufficient") or m.contains("balance"):
		return "insufficient_funds"
	if m.contains("closed") or m.contains("not found"):
		return "not_available"
	if code == 401 or code == 403:
		return "unauthorized"
	return "request_failed"

func _set_error(error_code: String, message: String) -> void:
	_last_error_code = error_code
	_last_error_message = message

func _emit_inventory_changed() -> void:
	items_updated.emit(get_items_cached())
	sig_inventory_updated.emit()

func _remove_item_from_list(items: Array, item_id: int) -> void:
	if item_id <= 0:
		return
	for idx in range(items.size() - 1, -1, -1):
		if int(items[idx].get("id", -1)) == item_id:
			items.remove_at(idx)
			return

func _remove_item_from_cache(hero_id: int, item_id: int) -> void:
	if not _items_by_hero.has(hero_id):
		return
	var items: Array = _items_by_hero[hero_id]
	_remove_item_from_list(items, item_id)
	_items_by_hero[hero_id] = items
	if _last_loaded_hero_id == hero_id:
		_items = items.duplicate(true)

func _remove_item_optimistic(hero_id: int, item_id: int) -> Dictionary:
	var snapshot := {"hero_id": hero_id, "item": {}, "index": -1}
	if not _items_by_hero.has(hero_id):
		return snapshot
	var items: Array = _items_by_hero[hero_id]
	for idx in range(items.size()):
		if int(items[idx].get("id", -1)) == item_id:
			snapshot["item"] = items[idx].duplicate(true)
			snapshot["index"] = idx
			items.remove_at(idx)
			break
	_items_by_hero[hero_id] = items
	if _last_loaded_hero_id == hero_id:
		_items = items.duplicate(true)
	return snapshot

func _restore_removed_item(hero_id: int, snapshot: Dictionary) -> void:
	if snapshot.is_empty() or not snapshot.has("item"):
		return
	if not _items_by_hero.has(hero_id):
		_items_by_hero[hero_id] = []
	var item: Dictionary = snapshot.get("item", {})
	if item.is_empty():
		return
	var idx := int(snapshot.get("index", -1))
	var items: Array = _items_by_hero[hero_id]
	if idx >= 0 and idx <= items.size():
		items.insert(idx, item)
	else:
		items.append(item)
	_items_by_hero[hero_id] = items
	if _last_loaded_hero_id == hero_id:
		_items = items.duplicate(true)

func _update_item_in_cache(hero_id: int, item_id: int, updates: Dictionary) -> void:
	if not _items_by_hero.has(hero_id):
		return
	var items: Array = _items_by_hero[hero_id]
	for idx in range(items.size()):
		if int(items[idx].get("id", -1)) == item_id:
			for key in updates.keys():
				items[idx][key] = updates[key]
			break
	_items_by_hero[hero_id] = items
	if _last_loaded_hero_id == hero_id:
		_items = items.duplicate(true)
