extends Node

signal sig_inventory_updated
signal sig_item_equipped(hero_id: int)
signal sig_item_removed(item_id: int)

signal items_updated(items: Array[Dictionary])
signal items_load_failed(message: String)
signal equipment_changed(hero_id: int, slot_name: String, item_data: Dictionary)
signal item_lock_changed(item_id: int, locked: bool)
signal manager_error(message: String)

const EQUIPMENT_SLOTS: PackedStringArray = ["Helmet", "Armor", "Weapon", "Boots", "Ring", "Amulet"]

const _SLOT_ALIASES: Dictionary = {
	"helmet": "Helmet",
	"head": "Helmet",
	"armor": "Armor",
	"spacesuit": "Armor",
	"chest": "Armor",
	"gloves": "Armor",
	"weapon": "Weapon",
	"boots": "Boots",
	"ring": "Ring",
	"belt": "Ring",
	"utility_belt": "Ring",
	"artifact": "Amulet",
	"amulet": "Amulet",
	"gadget": "Amulet",
	"implant": "Amulet",
}

var _items: Array[Dictionary] = []
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

func get_items_for_hero(hero_id: int) -> Array[Dictionary]:
	if hero_id <= 0:
		return []
	if _items_by_hero.has(hero_id):
		return (_items_by_hero[hero_id] as Array[Dictionary]).duplicate(true)
	return []

func get_items_cached() -> Array[Dictionary]:
	if _last_loaded_hero_id > 0 and _items_by_hero.has(_last_loaded_hero_id):
		return (_items_by_hero[_last_loaded_hero_id] as Array[Dictionary]).duplicate(true)
	return _items.duplicate(true)

func get_items() -> Array[Dictionary]:
	var hero_id: int = _last_loaded_hero_id
	if hero_id <= 0:
		hero_id = AppState.current_hero_id
	var path: String = "/inventory/"
	var query: String = ""
	if hero_id > 0:
		query = "?hero_id=%d" % hero_id
	var response: Dictionary = await _perform_request(HTTPClient.METHOD_GET, path + query)
	if not bool(response.get("ok", false)):
		items_load_failed.emit(_last_error_message)
		manager_error.emit(_last_error_message)
		return get_items_cached()

	var parsed: Variant = response.get("data", {})
	_items = _extract_items(parsed)
	if hero_id > 0:
		_items_by_hero[hero_id] = _items.duplicate(true)
		_last_loaded_hero_id = hero_id
	AppState.set_inventory_data(_items)
	_emit_inventory_changed()
	return _items.duplicate(true)

func refresh_inventory(hero_id: int = -1) -> Dictionary:
	if hero_id <= 0:
		hero_id = HeroManager.get_active_hero_id()
	if hero_id <= 0:
		hero_id = AppState.current_hero_id
	if hero_id <= 0:
		_set_error("invalid_input", "No active hero selected")
		items_load_failed.emit("No active hero selected")
		return {"ok": false, "error": _last_error_message, "items": [], "equipment": {}}

	_last_loaded_hero_id = hero_id
	await HeroManager.load_heroes()
	_sync_equipment_cache_from_heroes(HeroManager.get_heroes())
	var items: Array[Dictionary] = await get_items()
	return {
		"ok": _last_error_message.is_empty(),
		"error": _last_error_message,
		"items": items.duplicate(true),
		"equipment": get_equipment(hero_id)
	}

func load_items(hero_id: int = -1) -> void:
	if hero_id <= 0:
		hero_id = AppState.current_hero_id
	if hero_id <= 0:
		items_load_failed.emit("No active hero selected")
		manager_error.emit("No active hero selected")
		return
	_last_loaded_hero_id = hero_id
	call_deferred("_load_items_async")

func _load_items_async() -> void:
	var _data: Array[Dictionary] = await get_items()

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
	var source_items: Array[Dictionary] = get_items_for_hero(hero_id)
	if source_items.is_empty() and hero_id == _last_loaded_hero_id:
		source_items = _items.duplicate(true)
	for item: Dictionary in source_items:
		if int(item.get("id", -1)) == item_id:
			return item.duplicate(true)
	return {}

func inspect_item(item_id: int, hero_id: int = -1) -> Dictionary:
	var local_item: Dictionary = get_item_by_id(item_id, hero_id)
	if item_id <= 0:
		return {}
	var response: Dictionary = await _perform_request(HTTPClient.METHOD_GET, "/items/%d" % item_id)
	if not bool(response.get("ok", false)):
		return local_item
	var parsed: Variant = response.get("data", {})
	if parsed is Dictionary and (parsed as Dictionary).has("result") and (parsed as Dictionary)["result"] is Dictionary:
		return ((parsed as Dictionary)["result"] as Dictionary).duplicate(true)
	if parsed is Dictionary:
		return (parsed as Dictionary).duplicate(true)
	return local_item

func equip_item_for_active_hero(item_id: int) -> bool:
	var hero_id: int = HeroManager.get_active_hero_id()
	if hero_id <= 0:
		return false
	var item: Dictionary = get_item_by_id(item_id, hero_id)
	if item.is_empty():
		return false
	var slot_type: String = resolve_slot_from_item(item)
	if slot_type.is_empty():
		return false
	return await equip_item(hero_id, item_id, slot_type)

func equip_item(hero_id: int, item_id: int, slot_type: String) -> bool:
	slot_type = _normalize_slot_name(slot_type)
	if hero_id <= 0 or item_id <= 0 or not EQUIPMENT_SLOTS.has(slot_type):
		_set_error("invalid_input", "Invalid equip request")
		return false

	var response: Dictionary = await _perform_request(HTTPClient.METHOD_PATCH, "/heroes/%d/equip" % hero_id, {
		"item_id": item_id,
		"slot_type": slot_type
	})
	if not bool(response.get("ok", false)):
		return false

	await get_items()
	await HeroManager.load_heroes()
	_sync_equipment_cache_from_heroes(HeroManager.get_heroes())
	sig_item_equipped.emit(hero_id)
	return true

func unequip_item(hero_id: int, slot_type: String) -> bool:
	slot_type = _normalize_slot_name(slot_type)
	if hero_id <= 0 or slot_type.is_empty() or not EQUIPMENT_SLOTS.has(slot_type):
		_set_error("invalid_input", "Invalid unequip request")
		return false

	var response: Dictionary = await _perform_request(HTTPClient.METHOD_PATCH, "/heroes/%d/equip" % hero_id, {
		"item_id": null,
		"slot_type": slot_type
	})
	if bool(response.get("ok", false)):
		await get_items()
		await HeroManager.load_heroes()
		_sync_equipment_cache_from_heroes(HeroManager.get_heroes())
		return true
	return false

func dismantle_item(item_id: int) -> bool:
	var hero_id: int = HeroManager.get_active_hero_id()
	if hero_id <= 0 or item_id <= 0:
		_set_error("invalid_input", "Invalid dismantle request")
		return false

	var response: Dictionary = await _perform_request(HTTPClient.METHOD_POST, "/inventory/%d/dismantle" % item_id, {})
	if not bool(response.get("ok", false)):
		return false

	await get_items()
	await _refresh_user_profile()
	sig_item_removed.emit(item_id)
	return true

func lock_item(item_id: int, locked: bool) -> bool:
	var hero_id: int = HeroManager.get_active_hero_id()
	if hero_id <= 0 or item_id <= 0:
		_set_error("invalid_input", "Invalid lock request")
		return false

	var response: Dictionary = await _perform_request(HTTPClient.METHOD_PATCH, "/inventory/%d/lock" % item_id, {"locked": locked})
	if not bool(response.get("ok", false)):
		return false
	await get_items()
	item_lock_changed.emit(item_id, locked)
	return true

func set_item_lock(item_id: int, locked: bool) -> bool:
	return await lock_item(item_id, locked)

func toggle_item_lock(item_id: int) -> bool:
	var hero_id: int = HeroManager.get_active_hero_id()
	if hero_id <= 0 or item_id <= 0:
		return false
	var item: Dictionary = get_item_by_id(item_id, hero_id)
	if item.is_empty():
		return false
	return await lock_item(item_id, not bool(item.get("is_locked", false)))

func sell_item_on_auction(item_id: int, price: float = -1.0) -> bool:
	var hero_id: int = HeroManager.get_active_hero_id()
	if hero_id <= 0 or item_id <= 0:
		return false

	var item: Dictionary = get_item_by_id(item_id, hero_id)
	if item.is_empty():
		return false

	if price <= 0.0:
		price = float(item.get("sell_price", item.get("price", 1.0)))
	if price <= 0.0:
		price = 1.0

	var response: Dictionary = await _perform_request(HTTPClient.METHOD_POST, "/auctions/", {"item_id": item_id, "price": price})
	if not bool(response.get("ok", false)):
		return false
	await get_items()
	await _refresh_user_profile()
	sig_item_removed.emit(item_id)
	return true

func _refresh_user_profile() -> void:
	var profile_response: Dictionary = await ApiClient.get_user()
	if bool(profile_response.get("ok", false)) == false:
		return
	var parsed: Variant = profile_response.get("data", {})
	if parsed is Dictionary:
		var data := parsed as Dictionary
		if data.has("result") and data["result"] is Dictionary:
			AppState.set_user_data((data["result"] as Dictionary).duplicate(true))
			return
		AppState.set_user_data(data.duplicate(true))

func is_item_valid_for_slot(item_id: int, slot_type: String, hero_id: int = -1) -> bool:
	if slot_type.is_empty() or not EQUIPMENT_SLOTS.has(slot_type):
		return false
	var item: Dictionary = get_item_by_id(item_id, hero_id)
	if item.is_empty():
		return false
	return resolve_slot_from_item(item) == slot_type

func apply_optimistic_equip(hero_id: int, item_id: int, slot_type: String) -> Dictionary:
	var snapshot: Dictionary = {
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
	var new_item: Dictionary = get_item_by_id(item_id, hero_id)
	if new_item.is_empty():
		return snapshot

	if eq.has(slot_type) and eq[slot_type] is Dictionary:
		snapshot["previous_slot_item"] = (eq[slot_type] as Dictionary).duplicate(true)
		snapshot["used_swap"] = true
		items.append((snapshot["previous_slot_item"] as Dictionary).duplicate(true))

	eq[slot_type] = new_item.duplicate(true)

	for idx: int in range(items.size() - 1, -1, -1):
		var item: Variant = items[idx]
		if item is Dictionary and int((item as Dictionary).get("id", -1)) == item_id:
			snapshot["item_removed"] = (item as Dictionary).duplicate(true)
			items.remove_at(idx)
			break

	_items_by_hero[hero_id] = items
	if _last_loaded_hero_id == hero_id:
		_items = (items as Array[Dictionary]).duplicate(true)

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
		_items = (items as Array[Dictionary]).duplicate(true)

	equipment_changed.emit(hero_id, slot_type, eq.get(slot_type, {}))
	_emit_inventory_changed()

func calculate_hero_preview_stats(hero_data: Dictionary, equipment: Dictionary) -> Dictionary:
	# V2: extract core stats from the nested "stats" object
	var core: Dictionary = hero_data.get("stats", {})
	var stats: Dictionary = {
		"name": hero_data.get("name", "Unknown Hero"),
		"hero_generation_level": int(hero_data.get("hero_generation_level", 1)),
		"stamina": int(core.get("stamina", 0)),
		"strength": int(core.get("strength", 0)),
		"willpower": int(core.get("willpower", 0)),
		"reflex": int(core.get("reflex", 0)),
		"resilience": int(core.get("resilience", 0)),
		"focus": int(core.get("focus", 0)),
		"adaptability": int(core.get("adaptability", 0)),
		"luck": int(core.get("luck", 0)),
	}

	# Item bonuses map v1 item columns → v2 stat keys
	var _bonus_map: Dictionary = {
		"bonus_strength": "stamina",
		"bonus_agility": "reflex",
		"bonus_intelligence": "willpower",
		"bonus_endurance": "resilience",
		"bonus_speed": "adaptability",
		"bonus_health": "strength",
		"bonus_defense": "focus",
		"bonus_luck": "luck",
	}

	for slot_name: Variant in equipment.keys():
		if not (equipment[slot_name] is Dictionary):
			continue
		var item: Dictionary = equipment[slot_name]
		for bonus_key: String in _bonus_map.keys():
			var stat_key: String = _bonus_map[bonus_key]
			stats[stat_key] = int(stats.get(stat_key, 0)) + int(item.get(bonus_key, 0))

	return stats

func resolve_slot_from_item(item_data: Dictionary) -> String:
	var slot: String = str(item_data.get("slot", "")).strip_edges()
	if EQUIPMENT_SLOTS.has(slot):
		return slot
	if item_data.has("slot_type"):
		slot = str(item_data.get("slot_type", "")).strip_edges()
	if not slot.is_empty():
		var normalized: String = _normalize_slot_name(slot)
		if EQUIPMENT_SLOTS.has(normalized):
			return normalized

	var item_type: String = str(item_data.get("type", "")).to_lower()
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
	if item_type == "artifact":
		return "Amulet"
	if item_type == "spacesuit" or item_type == "shield":
		return "Armor"
	return ""

func _sync_equipment_cache_from_heroes(heroes: Array[Dictionary]) -> void:
	for hero: Dictionary in heroes:
		var hero_id: int = int(hero.get("id", -1))
		if hero_id <= 0:
			continue
		var equipment: Dictionary = _extract_equipment_from_hero(hero)
		_equipment_by_hero[hero_id] = equipment.duplicate(true)

func _extract_equipment_from_hero(hero: Dictionary) -> Dictionary:
	var equipment: Dictionary = {}
	if hero.has("equipment") and hero["equipment"] is Dictionary:
		var source := hero["equipment"] as Dictionary
		for slot_key_variant: Variant in source.keys():
			var slot_name: String = _normalize_slot_name(str(slot_key_variant))
			if not EQUIPMENT_SLOTS.has(slot_name):
				continue
			var value: Variant = source[slot_key_variant]
			if value is Dictionary:
				equipment[slot_name] = (value as Dictionary).duplicate(true)
			else:
				equipment[slot_name] = {"name": str(value)}

	if hero.has("equipment_items") and hero["equipment_items"] is Array:
		for entry_variant: Variant in (hero["equipment_items"] as Array):
			if entry_variant is Dictionary == false:
				continue
			var entry := entry_variant as Dictionary
			var slot_name: String = _normalize_slot_name(str(entry.get("slot", entry.get("slot_type", ""))))
			if not EQUIPMENT_SLOTS.has(slot_name):
				continue
			if entry.has("item") and entry["item"] is Dictionary:
				equipment[slot_name] = (entry["item"] as Dictionary).duplicate(true)
			else:
				equipment[slot_name] = {
					"id": int(entry.get("item_id", -1)),
					"name": str(entry.get("item_name", entry.get("item", "-"))),
				}

	return equipment

## H4: Public wrapper so external callers (e.g. Storage.gd) use the canonical
## slot-name mapping instead of maintaining their own divergent copy.
func normalize_slot(slot_name: String) -> String:
	return _normalize_slot_name(slot_name)

func _normalize_slot_name(slot_name: String) -> String:
	var normalized: String = slot_name.strip_edges()
	if normalized.is_empty():
		return ""
	if EQUIPMENT_SLOTS.has(normalized):
		return normalized
	var lowered: String = normalized.to_lower()
	if _SLOT_ALIASES.has(lowered):
		return str(_SLOT_ALIASES[lowered])
	return normalized.capitalize()

func calculate_stat_delta_for_equip(hero_id: int, item_id: int, slot_type: String) -> Dictionary:
	var hero_data: Dictionary = HeroManager.get_hero_by_id(hero_id)
	var current_equipment: Dictionary = get_equipment(hero_id)
	var before_stats: Dictionary = calculate_hero_preview_stats(hero_data, current_equipment)

	var next_equipment: Dictionary = current_equipment.duplicate(true)
	var item: Dictionary = get_item_by_id(item_id, hero_id)
	if item.is_empty():
		return {"stamina": 0, "strength": 0, "willpower": 0, "reflex": 0, "resilience": 0, "focus": 0, "adaptability": 0, "luck": 0}
	next_equipment[slot_type] = item
	var after_stats: Dictionary = calculate_hero_preview_stats(hero_data, next_equipment)

	var delta: Dictionary = {}
	for key: String in ["stamina", "strength", "willpower", "reflex", "resilience", "focus", "adaptability", "luck"]:
		delta[key] = int(after_stats.get(key, 0)) - int(before_stats.get(key, 0))
	return delta

func _extract_items(parsed: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if parsed is Dictionary:
		var data: Dictionary = parsed
		if data.has("result") and data["result"] is Array:
			for item: Variant in (data["result"] as Array):
				if item is Dictionary:
					out.append((item as Dictionary).duplicate(true))
			return out
		if data.has("items") and data["items"] is Array:
			for item: Variant in (data["items"] as Array):
				if item is Dictionary:
					out.append((item as Dictionary).duplicate(true))
			return out
	elif parsed is Array:
		for item: Variant in (parsed as Array):
			if item is Dictionary:
				out.append((item as Dictionary).duplicate(true))
	return out

func _item_power(item: Dictionary) -> int:
	if item.has("power"):
		return int(item.get("power", 0))
	return int(item.get("attack", 0)) + int(item.get("defense", 0)) + int(item.get("stability", 0)) + int(item.get("energy", 0)) + int(item.get("durability", 0))

func _perform_request(method: int, path: String, payload: Dictionary = {}, extra_headers: PackedStringArray = PackedStringArray()) -> Dictionary:
	clear_error()
	var headers: PackedStringArray = PackedStringArray(["Accept: application/json"])
	for header: String in extra_headers:
		headers.append(header)

	var response: Dictionary = {}
	match method:
		HTTPClient.METHOD_GET:
			response = await ApiClient.request_get(path, headers)
		HTTPClient.METHOD_POST:
			response = await ApiClient.request_post(path, payload, headers)
		HTTPClient.METHOD_PATCH:
			response = await ApiClient.request_patch(path, payload, headers)
		HTTPClient.METHOD_DELETE:
			response = await ApiClient.request_delete(path, headers)
		_:
			response = await ApiClient.request_json(path, method, payload, headers)

	var ok: bool = bool(response.get("ok", false))
	var status: int = int(response.get("status", response.get("code", 0)))
	var data: Variant = response.get("data", {})
	var msg: String = str(response.get("error", response.get("message", "Request failed")))

	if not ok:
		if msg.is_empty():
			msg = "Request failed"
		_set_error(_classify_error(status, msg), msg)
		print("[InventoryManager] request failed method=%d path=%s status=%d message=%s" % [method, path, status, msg])
		return {"ok": false, "status": status, "error": msg, "data": data}

	return {"ok": true, "status": status, "error": "", "data": data}

func _classify_error(code: int, message: String) -> String:
	var m: String = message.to_lower()
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
	manager_error.emit(message)

func _emit_inventory_changed() -> void:
	items_updated.emit(get_items_cached())
	sig_inventory_updated.emit()

func _remove_item_from_list(items: Array, item_id: int) -> void:
	if item_id <= 0:
		return
	for idx: int in range(items.size() - 1, -1, -1):
		var value: Variant = items[idx]
		if value is Dictionary and int((value as Dictionary).get("id", -1)) == item_id:
			items.remove_at(idx)
			return

func _remove_item_from_cache(hero_id: int, item_id: int) -> void:
	if not _items_by_hero.has(hero_id):
		return
	var items: Array = _items_by_hero[hero_id]
	_remove_item_from_list(items, item_id)
	_items_by_hero[hero_id] = items
	if _last_loaded_hero_id == hero_id:
		_items = (items as Array[Dictionary]).duplicate(true)

func _remove_item_optimistic(hero_id: int, item_id: int) -> Dictionary:
	var snapshot: Dictionary = {"hero_id": hero_id, "item": {}, "index": -1}
	if not _items_by_hero.has(hero_id):
		return snapshot
	var items: Array = _items_by_hero[hero_id]
	for idx: int in range(items.size()):
		var value: Variant = items[idx]
		if value is Dictionary and int((value as Dictionary).get("id", -1)) == item_id:
			snapshot["item"] = (value as Dictionary).duplicate(true)
			snapshot["index"] = idx
			items.remove_at(idx)
			break
	_items_by_hero[hero_id] = items
	if _last_loaded_hero_id == hero_id:
		_items = (items as Array[Dictionary]).duplicate(true)
	return snapshot

func _restore_removed_item(hero_id: int, snapshot: Dictionary) -> void:
	if snapshot.is_empty() or not snapshot.has("item"):
		return
	if not _items_by_hero.has(hero_id):
		_items_by_hero[hero_id] = []
	var item: Dictionary = snapshot.get("item", {})
	if item.is_empty():
		return
	var idx: int = int(snapshot.get("index", -1))
	var items: Array = _items_by_hero[hero_id]
	if idx >= 0 and idx <= items.size():
		items.insert(idx, item)
	else:
		items.append(item)
	_items_by_hero[hero_id] = items
	if _last_loaded_hero_id == hero_id:
		_items = (items as Array[Dictionary]).duplicate(true)

func _update_item_in_cache(hero_id: int, item_id: int, updates: Dictionary) -> void:
	if not _items_by_hero.has(hero_id):
		return
	var items: Array = _items_by_hero[hero_id]
	for idx: int in range(items.size()):
		var value: Variant = items[idx]
		if value is Dictionary and int((value as Dictionary).get("id", -1)) == item_id:
			for key: Variant in updates.keys():
				(value as Dictionary)[key] = updates[key]
			items[idx] = value
			break
	_items_by_hero[hero_id] = items
	if _last_loaded_hero_id == hero_id:
		_items = (items as Array[Dictionary]).duplicate(true)
