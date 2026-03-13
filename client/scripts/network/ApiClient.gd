extends Node

## Thin centralized HTTP facade over Network autoload.
## Safe migration path: existing scripts can continue using Network directly,
## while new/updated services move to ApiClient incrementally.

func login(email: String, password: String) -> Dictionary:
	return await request_post("/auth/login", {
		"login": email,
		"password": password,
	})

func register(email: String, username: String, password: String) -> Dictionary:
	return await request_post("/auth/register", {
		"email": email,
		"username": username,
		"password": password,
	})

func get_user() -> Dictionary:
	return await request_get("/auth/me")

func get_heroes() -> Dictionary:
	return await request_get("/heroes")

func create_hero(hero_name: String, investment: int) -> Dictionary:
	return await request_post("/heroes/create", {
		"name": hero_name,
		"investment": investment,
	})

func get_auction_lots(filters: Dictionary = {}) -> Dictionary:
	var query: String = _build_query_string(filters)
	var path := "/auction/lots"
	if query.is_empty() == false:
		path = "%s?%s" % [path, query]
	var response: Dictionary = await request_get(path)
	if bool(response.get("ok", false)):
		_sync_auction_to_appstate(response.get("data", {}), filters)
	return response

func get_chat_messages(channel: String = "global", limit: int = 50, offset: int = 0) -> Dictionary:
	var query := {
		"channel": channel,
		"limit": maxi(1, limit),
		"offset": maxi(0, offset),
	}
	var primary: Dictionary = await request_get("/chat/messages?%s" % _build_query_string(query))
	if bool(primary.get("ok", false)):
		_sync_chat_to_appstate(channel, primary.get("data", {}))
		return primary

	var legacy_channel := _legacy_chat_channel(channel)
	var legacy_query := {
		"channel": legacy_channel,
		"limit": maxi(1, limit),
	}
	var fallback: Dictionary = await request_get("/chat/history?%s" % _build_query_string(legacy_query))
	if bool(fallback.get("ok", false)):
		_sync_chat_to_appstate(channel, fallback.get("data", {}))
	return fallback

func send_chat_message(channel: String, message: String) -> Dictionary:
	return await request_post("/chat/send", {
		"channel": channel,
		"message": message,
	})

func _legacy_chat_channel(channel: String) -> String:
	var normalized: String = channel.strip_edges().to_lower()
	if normalized == "global":
		return "general"
	return normalized

func get_server_status() -> Dictionary:
	return await request_get("/server/status")

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

	var req_headers: Array = []
	for h: String in headers:
		req_headers.append(h)

	var req: HTTPRequest = Network.request(path, method, payload, req_headers)
	if req == null:
		return {
			"ok": false,
			"code": 0,
			"result": HTTPRequest.RESULT_CANT_CONNECT,
			"headers": PackedStringArray(),
			"data": {},
			"message": "Failed to create request"
		}

	var response: Array = await req.request_completed
	if response.size() < 4:
		return {
			"ok": false,
			"code": 0,
			"result": HTTPRequest.RESULT_CANT_CONNECT,
			"headers": PackedStringArray(),
			"data": {},
			"message": "Unexpected response"
		}

	var result: int = int(response[0])
	var code: int = int(response[1])
	var response_headers: PackedStringArray = response[2]
	var body: PackedByteArray = response[3]
	var body_text: String = body.get_string_from_utf8()
	var parsed: Variant = _parse_json(body_text)
	var ok: bool = result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300

	return {
		"ok": ok,
		"code": code,
		"result": result,
		"headers": response_headers,
		"data": parsed,
		"message": "" if ok else _extract_error_message(parsed, body_text, code, result)
	}

func _parse_json(body_text: String) -> Variant:
	if body_text.is_empty():
		return {}
	var json: JSON = JSON.new()
	if json.parse(body_text) != OK:
		return {}
	return json.data

func _extract_error_message(parsed: Variant, raw_body: String, code: int, result: int) -> String:
	if parsed is Dictionary:
		var data: Dictionary = parsed
		if data.has("detail"):
			return str(data.get("detail", "Request failed"))
		if data.has("message"):
			return str(data.get("message", "Request failed"))
	if not raw_body.is_empty():
		return raw_body.left(200)
	if result != HTTPRequest.RESULT_SUCCESS:
		return "Request failed (result=%d)" % result
	return "HTTP %d" % code

func _build_query_string(params: Dictionary) -> String:
	if params.is_empty():
		return ""
	var parts: PackedStringArray = []
	for key_variant in params.keys():
		var key: String = str(key_variant)
		var value: Variant = params[key_variant]
		parts.append("%s=%s" % [key.uri_encode(), str(value).uri_encode()])
	return "&".join(parts)

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