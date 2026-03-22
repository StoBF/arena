extends Node

## Thin centralized HTTP facade over Network autoload.
## Safe migration path: existing scripts can continue using Network directly,
## while new/updated services move to ApiClient incrementally.

const HERO_COLLECTION_PATH := "/heroes/"

func get_hero_collection_path() -> String:
	return HERO_COLLECTION_PATH

func login(email: String, password: String) -> Dictionary:
	var response: Dictionary = await request_post("/auth/login", {
		"login": email,
		"password": password,
	})
	if bool(response.get("ok", false)):
		var payload: Dictionary = _extract_dict(response.get("data", {}))
		var access: String = str(payload.get("access_token", ""))
		var refresh: String = str(payload.get("refresh_token", ""))
		if not access.is_empty():
			AppState.set_access_token(access)
		if not refresh.is_empty():
			AppState.refresh_token = refresh
	return response

func register(email: String, username: String, password: String) -> Dictionary:
	return await request_post("/auth/register", {
		"email": email,
		"username": username,
		"password": password,
	})

func get_user() -> Dictionary:
	return await request_get("/auth/me")

func get_heroes() -> Dictionary:
	return await request_get(get_hero_collection_path())

func create_hero(hero_name: String, _investment: int = 0) -> Dictionary:
	return await request_post("/heroes/generate", {
		"locale": _resolve_locale(),
	})

func get_auction_lots(filters: Dictionary = {}) -> Dictionary:
	var normalized: Dictionary = _normalize_auction_filters(filters)
	var query: String = _build_query_string(normalized)
	var path := "/auctions/lots"
	if query.is_empty() == false:
		path = "%s?%s" % [path, query]
	var response: Dictionary = await request_get(path)
	if bool(response.get("ok", false)):
		_sync_auction_to_appstate(response.get("data", {}), normalized)
	return response

func get_chat_messages(channel: String = "global", limit: int = 50, offset: int = 0) -> Dictionary:
	var query := {
		"channel": _legacy_chat_channel(channel),
		"limit": maxi(1, limit),
		"offset": maxi(0, offset),
	}
	var response_variant: Variant = await request_get("/chat/history?%s" % _build_query_string(query))
	if response_variant is Dictionary:
		var response: Dictionary = (response_variant as Dictionary)
		if bool(response.get("ok", false)):
			_sync_chat_to_appstate(channel, response.get("data", {}))
		return response
	return {
		"ok": false,
		"code": 0,
		"result": HTTPRequest.RESULT_CANT_CONNECT,
		"headers": PackedStringArray(),
		"data": {},
		"message": "Unexpected chat response"
	}

func send_chat_message(channel: String, message: String) -> Dictionary:
	return {
		"ok": false,
		"code": 401,
		"result": HTTPRequest.RESULT_SUCCESS,
		"headers": PackedStringArray(),
		"data": {},
		"message": "Chat send is websocket-only on this backend"
	}

func _legacy_chat_channel(channel: String) -> String:
	var normalized: String = channel.strip_edges().to_lower()
	if normalized == "global":
		return "general"
	return normalized

func get_server_status() -> Dictionary:
	return await request_get("/server/status")

func get_account() -> Dictionary:
	return await get_user()

func get_inventory(hero_id: int) -> Dictionary:
	return await request_get("/inventory/%d" % hero_id)

func get_auctions() -> Dictionary:
	return await request_get("/auction")

func place_bid(lot_id: int, amount: int) -> Dictionary:
	return await request_post("/auction/bid", {
		"lot_id": lot_id,
		"amount": amount,
	})

func buyout(lot_id: int) -> Dictionary:
	return await request_post("/auction/buy", {
		"lot_id": lot_id,
	})

# ---------------------------------------------------------------------------
# Healing (no dedicated server endpoint yet — uses hero status)
# ---------------------------------------------------------------------------

func start_healing(hero_id: int) -> Dictionary:
	# C5: No server endpoint exists yet. Return a clear failure so callers
	# show an "unavailable" message instead of false success.
	return {
		"ok": false,
		"code": 501,
		"result": HTTPRequest.RESULT_SUCCESS,
		"headers": PackedStringArray(),
		"data": {"hero_id": hero_id},
		"message": "Healing endpoint not yet available"
	}

# ---------------------------------------------------------------------------
# PvP / Arena
# ---------------------------------------------------------------------------

func get_leaderboard() -> Dictionary:
	return await request_get("/pvp/leaderboard")

func pvp_match(player1_id: int, player2_id: int) -> Dictionary:
	return await request_post("/pvp/match", {
		"player1_id": player1_id,
		"player2_id": player2_id,
	})

func team_battle(hero_ids: Array, enemy_ids: Array) -> Dictionary:
	return await request_post("/battle/team", {
		"hero_ids": hero_ids,
		"enemy_ids": enemy_ids,
	})

func queue_arena(mode: String, hero_ids: Array) -> Dictionary:
	# Arena queue is client-side concept; matchmaking finds an opponent then
	# calls pvp_match or team_battle. For now mock the queue step.
	return {
		"ok": true,
		"code": 200,
		"result": HTTPRequest.RESULT_SUCCESS,
		"headers": PackedStringArray(),
		"data": {"mode": mode, "hero_ids": hero_ids, "status": "queued"},
		"message": "Entered %s queue" % mode
	}

func submit_battle_queue(hero_id: int) -> Dictionary:
	if hero_id <= 0:
		return {
			"ok": false,
			"code": 400,
			"result": HTTPRequest.RESULT_SUCCESS,
			"headers": PackedStringArray(),
			"data": {},
			"message": "Invalid hero id"
		}
	return await request_post("/battle/queue/submit", {"hero_id": hero_id})

func get_battle_queue() -> Dictionary:
	return await request_get("/battle/queue")

# ---------------------------------------------------------------------------
# Boss Raids
# ---------------------------------------------------------------------------

func get_bosses() -> Dictionary:
	return await request_get("/raid/bosses")

func start_boss_raid(boss_id: int, hero_ids: Array) -> Dictionary:
	return await request_post("/raid/start", {
		"boss_id": boss_id,
		"hero_ids": hero_ids,
	})

func raid_battle(instance_id: int) -> Dictionary:
	return await request_post("/raid/battle/%d" % instance_id)

func raid_rewards(instance_id: int) -> Dictionary:
	return await request_post("/raid/rewards/%d" % instance_id)

func connect_chat() -> Dictionary:
	return {
		"ok": true,
		"code": 200,
		"result": HTTPRequest.RESULT_SUCCESS,
		"headers": PackedStringArray(),
		"data": {},
		"message": "Chat connection managed by scene websocket flow"
	}

func request_get(path: String, headers: PackedStringArray = PackedStringArray()) -> Dictionary:
	return await request_json(path, HTTPClient.METHOD_GET, {}, headers)

func request_post(path: String, payload: Dictionary = {}, headers: PackedStringArray = PackedStringArray()) -> Dictionary:
	return await request_json(path, HTTPClient.METHOD_POST, payload, headers)

func request_patch(path: String, payload: Dictionary = {}, headers: PackedStringArray = PackedStringArray()) -> Dictionary:
	return await request_json(path, HTTPClient.METHOD_PATCH, payload, headers)

func request_delete(path: String, headers: PackedStringArray = PackedStringArray()) -> Dictionary:
	return await request_json(path, HTTPClient.METHOD_DELETE, {}, headers)

func request_json(path: String, method: int, payload: Dictionary = {}, headers: PackedStringArray = PackedStringArray()) -> Dictionary:
	if not has_node("/root/Network"):
		return {
			"ok": false,
			"code": 0,
			"result": HTTPRequest.RESULT_CANT_CONNECT,
			"headers": PackedStringArray(),
			"data": {},
			"message": "Network autoload is not available"
		}

	return await Network.request_json(path, method, payload, headers)

func _extract_dict(data: Variant) -> Dictionary:
	if data is Dictionary:
		return (data as Dictionary).duplicate(true)
	return {}

func _resolve_locale() -> String:
	if has_node("/root/LocalizationManager") and LocalizationManager.has_method("get_current_locale"):
		var locale: String = str(LocalizationManager.get_current_locale()).strip_edges().to_lower()
		if locale in ["en", "pl", "uk"]:
			return locale
	return "en"

func _build_query_string(params: Dictionary) -> String:
	if params.is_empty():
		return ""
	var parts: PackedStringArray = []
	for key_variant in params.keys():
		var key: String = str(key_variant)
		var value: Variant = params[key_variant]
		if value == null:
			continue
		parts.append("%s=%s" % [key.uri_encode(), str(value).uri_encode()])
	return "&".join(parts)

func _normalize_auction_filters(filters: Dictionary) -> Dictionary:
	var page: int = maxi(1, int(filters.get("page", 1)))
	var page_size: int = maxi(1, int(filters.get("page_size", filters.get("limit", 20))))
	var offset: int = maxi(0, int(filters.get("offset", (page - 1) * page_size)))
	return {
		"limit": page_size,
		"offset": offset
	}

func _sync_chat_to_appstate(channel: String, parsed: Variant) -> void:
	if has_node("/root/AppState") == false:
		return
	var lines: Array = _extract_chat_lines(parsed)
	if lines.is_empty():
		return
	AppState.set_chat_messages(channel, lines)

func _extract_chat_lines(parsed: Variant) -> Array:
	var items: Array = []
	if parsed is Array:
		items = (parsed as Array).duplicate(true)
	elif parsed is Dictionary:
		var data := parsed as Dictionary
		if data.has("result") and data["result"] is Array:
			items = (data["result"] as Array).duplicate(true)
		elif data.has("items") and data["items"] is Array:
			items = (data["items"] as Array).duplicate(true)
	var lines: Array = []
	for message_variant in items:
		if message_variant is Dictionary == false:
			continue
		var message := message_variant as Dictionary
		var player: String = str(message.get("player", message.get("username", message.get("user", "Player %s" % str(message.get("sender_id", "?"))))))
		var text: String = str(message.get("message", message.get("text", "")))
		if text.is_empty():
			continue
		lines.append("[%s] %s" % [player, text])
	return lines

func _sync_auction_to_appstate(parsed: Variant, fallback_filters: Dictionary) -> void:
	if has_node("/root/AppState") == false:
		return
	var items: Array = _extract_auction_items(parsed)
	var pagination: Dictionary = _extract_auction_pagination(parsed, fallback_filters, items.size())
	AppState.set_auction_data(items, pagination)

func _extract_auction_items(parsed: Variant) -> Array:
	if parsed is Array:
		return (parsed as Array).duplicate(true)
	if parsed is Dictionary:
		var data := parsed as Dictionary
		if data.has("result") and data["result"] is Array:
			return (data["result"] as Array).duplicate(true)
		if data.has("items") and data["items"] is Array:
			return (data["items"] as Array).duplicate(true)
	return []

func _extract_auction_pagination(parsed: Variant, filters: Dictionary, item_count: int) -> Dictionary:
	var page: int = maxi(1, int(filters.get("page", 1)))
	var page_size: int = maxi(1, int(filters.get("page_size", 20)))
	var total: int = item_count
	var has_next: bool = item_count >= page_size
	var has_prev: bool = page > 1
	if parsed is Dictionary:
		var data := parsed as Dictionary
		if data.has("limit") and data.has("offset"):
			var limit: int = maxi(1, int(data.get("limit", page_size)))
			var offset: int = maxi(0, int(data.get("offset", 0)))
			page = int(offset / limit) + 1
			page_size = limit
		if data.has("total"):
			total = int(data.get("total", total))
			has_next = page * page_size < total
			has_prev = page > 1
		if data.has("has_next"):
			has_next = bool(data.get("has_next", has_next))
		if data.has("has_prev"):
			has_prev = bool(data.get("has_prev", has_prev))
	return {
		"page": page,
		"page_size": page_size,
		"total": total,
		"has_next": has_next,
		"has_prev": has_prev,
	}