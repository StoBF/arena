extends Node
class_name UIApiClient

var base_url: String = "http://127.0.0.1:8000"
var auth_token: String = ""

var _http_request: HTTPRequest = null
var _request_busy: bool = false
var _chat_socket: WebSocketPeer = null
var _chat_connected: bool = false

func _ready() -> void:
	_ensure_http_request()
	set_process(true)

func _exit_tree() -> void:
	if _chat_socket != null:
		_chat_socket.close()
		_chat_socket = null
		_chat_connected = false

func _process(_delta: float) -> void:
	_poll_chat_socket()

func _ensure_http_request() -> void:
	if _http_request != null and is_instance_valid(_http_request):
		return
	_http_request = HTTPRequest.new()
	_http_request.name = "ApiClientHttpRequest"
	add_child(_http_request)

func login(username: String, password: String) -> Dictionary:
	var response: Dictionary = await _request_json(
		"/auth/login",
		HTTPClient.METHOD_POST,
		{"username": username, "password": password}
	)
	if bool(response.get("ok", false)):
		var data: Variant = response.get("data", {})
		auth_token = _extract_token(data)
	return response

func register(username: String, password: String) -> Dictionary:
	return await _request_json(
		"/auth/register",
		HTTPClient.METHOD_POST,
		{"username": username, "password": password}
	)

func get_heroes() -> Dictionary:
	var response: Dictionary = await _request_json("/heroes", HTTPClient.METHOD_GET)
	if bool(response.get("ok", false)) and has_node("/root/AppState"):
		var payload: Variant = response.get("data", [])
		var heroes_data: Array = []
		if payload is Array:
			heroes_data = (payload as Array).duplicate(true)
		elif payload is Dictionary and (payload as Dictionary).has("items") and (payload as Dictionary).get("items") is Array:
			heroes_data = ((payload as Dictionary).get("items") as Array).duplicate(true)
		(get_node("/root/AppState") as UIAppState).set_heroes(heroes_data)
	return response

func create_hero(name: String) -> Dictionary:
	return await _request_json("/heroes", HTTPClient.METHOD_POST, {"name": name})

func delete_hero(hero_id: int) -> Dictionary:
	return await _request_json("/heroes/%d" % hero_id, HTTPClient.METHOD_DELETE)

func get_inventory(hero_id: int) -> Dictionary:
	var response: Dictionary = await _request_json("/inventory/%d" % hero_id, HTTPClient.METHOD_GET)
	if bool(response.get("ok", false)) and has_node("/root/AppState"):
		var payload: Variant = response.get("data", [])
		var items: Array = payload as Array if payload is Array else []
		(get_node("/root/AppState") as UIAppState).set_inventory(hero_id, items)
	return response

func equip_item(hero_id: int, item_id: int) -> Dictionary:
	return await _request_json(
		"/inventory/equip",
		HTTPClient.METHOD_POST,
		{"hero_id": hero_id, "item_id": item_id}
	)

func unequip_item(hero_id: int, item_id: int) -> Dictionary:
	return await _request_json(
		"/inventory/unequip",
		HTTPClient.METHOD_POST,
		{"hero_id": hero_id, "item_id": item_id}
	)

func get_auctions() -> Dictionary:
	var response: Dictionary = await _request_json("/auction", HTTPClient.METHOD_GET)
	if bool(response.get("ok", false)) and has_node("/root/AppState"):
		var payload: Variant = response.get("data", [])
		var lots: Array = []
		if payload is Array:
			lots = (payload as Array).duplicate(true)
		elif payload is Dictionary and (payload as Dictionary).has("items") and (payload as Dictionary).get("items") is Array:
			lots = ((payload as Dictionary).get("items") as Array).duplicate(true)
		(get_node("/root/AppState") as UIAppState).set_auction_lots(lots)
	return response

func place_bid(lot_id: int, amount: int) -> Dictionary:
	return await _request_json(
		"/auction/bid",
		HTTPClient.METHOD_POST,
		{"lot_id": lot_id, "amount": amount}
	)

func buyout(lot_id: int) -> Dictionary:
	return await _request_json(
		"/auction/buy",
		HTTPClient.METHOD_POST,
		{"lot_id": lot_id}
	)

func connect_chat() -> Dictionary:
	if _chat_socket != null and _chat_socket.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		return {"ok": true, "message": "Chat already connected"}

	if auth_token.is_empty():
		_emit_network_error("Missing auth token for chat connection")
		return {"ok": false, "message": "Missing auth token"}

	_chat_socket = WebSocketPeer.new()
	_chat_connected = false
	var ws_url: String = _build_chat_ws_url()
	var err: int = _chat_socket.connect_to_url(ws_url)
	if err != OK:
		_chat_socket = null
		_emit_network_error("Chat connection failed")
		return {"ok": false, "message": "Chat connection failed", "error": err}

	return {"ok": true, "message": "Chat connecting"}

func send_message(text: String) -> Dictionary:
	if _chat_socket == null or _chat_socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		_emit_network_error("Chat socket is not connected")
		return {"ok": false, "message": "Chat socket is not connected"}
	if text.strip_edges().is_empty():
		return {"ok": false, "message": "Message is empty"}
	var payload: String = JSON.stringify({"text": text})
	var err: int = _chat_socket.send_text(payload)
	if err != OK:
		_emit_network_error("Failed to send chat message")
		return {"ok": false, "message": "Failed to send chat message", "error": err}
	return {"ok": true}

func _request_json(path: String, method: int, payload: Dictionary = {}) -> Dictionary:
	_ensure_http_request()
	if _request_busy:
		_emit_network_error("Another request is in progress")
		return {"ok": false, "code": 0, "data": {}, "message": "Request busy"}

	var url: String = "%s%s" % [base_url.trim_suffix("/"), path]
	var headers: PackedStringArray = _build_headers(method)
	var body: String = ""
	if method != HTTPClient.METHOD_GET and method != HTTPClient.METHOD_DELETE:
		body = JSON.stringify(payload)

	_request_busy = true
	var err: int = _http_request.request(url, headers, method, body)
	if err != OK:
		_request_busy = false
		_emit_network_error("Failed to start request")
		return {"ok": false, "code": 0, "data": {}, "message": "Failed to start request", "error": err}

	var result_data: Array = await _http_request.request_completed
	_request_busy = false

	if result_data.size() < 4:
		_emit_network_error("Invalid network response")
		return {"ok": false, "code": 0, "data": {}, "message": "Invalid network response"}

	var result: int = int(result_data[0])
	var code: int = int(result_data[1])
	var response_headers: PackedStringArray = result_data[2]
	var response_body: PackedByteArray = result_data[3]
	var body_text: String = response_body.get_string_from_utf8()
	var parsed: Variant = _parse_json(body_text)
	var ok: bool = result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300
	if ok == false:
		_emit_network_error(_extract_error_message(parsed, body_text, code, result))

	return {
		"ok": ok,
		"result": result,
		"code": code,
		"headers": response_headers,
		"data": parsed,
		"message": "" if ok else _extract_error_message(parsed, body_text, code, result)
	}

func _build_headers(method: int) -> PackedStringArray:
	var headers := PackedStringArray()
	headers.append("Accept: application/json")
	if auth_token.is_empty() == false:
		headers.append("Authorization: Bearer %s" % auth_token)
	if method != HTTPClient.METHOD_GET and method != HTTPClient.METHOD_DELETE:
		headers.append("Content-Type: application/json")
	return headers

func _parse_json(body_text: String) -> Variant:
	if body_text.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(body_text)
	if parsed == null:
		return {}
	return parsed

func _extract_error_message(parsed: Variant, raw_body: String, code: int, result: int) -> String:
	if parsed is Dictionary:
		var data := parsed as Dictionary
		if data.has("detail"):
			return str(data.get("detail", "Request failed"))
		if data.has("message"):
			return str(data.get("message", "Request failed"))
	if raw_body.is_empty() == false:
		return raw_body.left(200)
	if result != HTTPRequest.RESULT_SUCCESS:
		return "Request failed (result=%d)" % result
	return "HTTP %d" % code

func _extract_token(data: Variant) -> String:
	if data is Dictionary:
		var payload := data as Dictionary
		if payload.has("access_token"):
			return str(payload.get("access_token", ""))
		if payload.has("token"):
			return str(payload.get("token", ""))
		if payload.has("jwt"):
			return str(payload.get("jwt", ""))
		if payload.has("auth_token"):
			return str(payload.get("auth_token", ""))
	return ""

func _build_chat_ws_url() -> String:
	var host: String = base_url.strip_edges()
	if host.begins_with("http://"):
		host = "ws://" + host.substr(7)
	elif host.begins_with("https://"):
		host = "wss://" + host.substr(8)
	return "%s/chat/ws?token=%s" % [host.trim_suffix("/"), auth_token.uri_encode()]

func _poll_chat_socket() -> void:
	if _chat_socket == null:
		return

	_chat_socket.poll()
	var state: int = _chat_socket.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		_chat_connected = true
		while _chat_socket.get_available_packet_count() > 0:
			var payload_text: String = _chat_socket.get_packet().get_string_from_utf8()
			var payload: Variant = _parse_json(payload_text)
			_emit_chat_message(payload)
	elif state == WebSocketPeer.STATE_CLOSED:
		if _chat_connected:
			_emit_network_error("Chat disconnected")
		_chat_connected = false
		_chat_socket = null

func _emit_chat_message(payload: Variant) -> void:
	if has_node("/root/AppState") == false:
		return
	var message: Dictionary = {}
	if payload is Dictionary:
		message = (payload as Dictionary).duplicate(true)
	else:
		message = {"text": str(payload)}
	(get_node("/root/AppState") as UIAppState).add_chat_message(message)

func _emit_network_error(message: String) -> void:
	if has_node("/root/EventBus"):
		var bus: Node = get_node("/root/EventBus")
		if bus.has_signal("network_error"):
			bus.emit_signal("network_error", message)

func get_account() -> Dictionary:
	return await _request_json("/account", HTTPClient.METHOD_GET)

func get_auction_lots() -> Dictionary:
	return await get_auctions()

func poll_chat_messages(_channel: String = "global") -> Dictionary:
	return {"ok": true, "data": []}

func subscribe_chat_socket(_channel: String = "global") -> Dictionary:
	return await connect_chat()

func get_recipes() -> Dictionary:
	var response: Dictionary = await _request_json("/recipes", HTTPClient.METHOD_GET)
	if bool(response.get("ok", false)) and has_node("/root/AppState"):
		var payload: Variant = response.get("data", [])
		var recipes: Array = payload as Array if payload is Array else []
		(get_node("/root/AppState") as UIAppState).set_recipes(recipes)
	return response

func get_raid_bosses() -> Dictionary:
	return await _request_json("/raid/bosses", HTTPClient.METHOD_GET)
