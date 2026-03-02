extends Node

signal sig_lot_updated(lot_id: int)
signal sig_lot_closed(lot_id: int)
signal sig_new_lot(lot_data: Dictionary)

signal lots_updated(items: Array, pagination: Dictionary)
signal lots_fetch_failed(message: String)
signal bid_received(lot_id: int, bid_value: float)

const DEFAULT_PAGE_SIZE := 20

var _last_items: Array = []
var _last_pagination: Dictionary = {"page": 1, "page_size": DEFAULT_PAGE_SIZE, "total": 0, "has_next": false, "has_prev": false}
var _last_error_code: String = ""
var _last_error_message: String = ""

func fetch_lots(filters: Dictionary) -> Array:
	var sanitized: Dictionary = _sanitize_filters(filters)
	var response: Dictionary = await _perform_request(HTTPClient.METHOD_GET, _build_endpoint(sanitized))
	if not bool(response.get("ok", false)):
		lots_fetch_failed.emit(_last_error_message)
		return []

	var parsed: Variant = response.get("data", {})
	var items: Array = _extract_items(parsed)
	var pagination: Dictionary = _extract_pagination(parsed, sanitized, items.size())
	_last_items = items.duplicate(true)
	_last_pagination = pagination.duplicate(true)
	lots_updated.emit(_last_items.duplicate(true), _last_pagination.duplicate(true))
	return _last_items.duplicate(true)

func get_last_items() -> Array:
	return _last_items.duplicate(true)

func get_last_pagination() -> Dictionary:
	return _last_pagination.duplicate(true)

func get_last_error_code() -> String:
	return _last_error_code

func get_last_error_message() -> String:
	return _last_error_message

func clear_error() -> void:
	_last_error_code = ""
	_last_error_message = ""

func fetch_lot_details(lot_id: int, lot_data: Dictionary = {}) -> Dictionary:
	if lot_id <= 0:
		return {}
	var response: Dictionary = await _perform_request(HTTPClient.METHOD_GET, _details_path(lot_data, lot_id))
	if not bool(response.get("ok", false)):
		return lot_data.duplicate(true)
	var parsed: Variant = response.get("data", {})
	if parsed is Dictionary:
		var data: Dictionary = parsed
		if data.has("result") and data["result"] is Dictionary:
			return (data["result"] as Dictionary).duplicate(true)
		return data.duplicate(true)
	return lot_data.duplicate(true)

func place_bid(lot_id: int, amount: int) -> bool:
	if lot_id <= 0 or amount <= 0:
		_set_error("invalid_input", "Invalid bid amount")
		return false
	var response: Dictionary = await _perform_request(HTTPClient.METHOD_POST, "/auctions/%d/bid" % lot_id, {"amount": amount})
	if bool(response.get("ok", false)):
		sig_lot_updated.emit(lot_id)
		bid_received.emit(lot_id, float(amount))
		return true
	if _last_error_code == "lot_closed":
		sig_lot_closed.emit(lot_id)
	return false

func buy_now(lot_id: int) -> bool:
	if lot_id <= 0:
		_set_error("invalid_input", "Invalid lot id")
		return false
	var response: Dictionary = await _perform_request(HTTPClient.METHOD_POST, "/auctions/%d/buy" % lot_id, {})
	if bool(response.get("ok", false)):
		sig_lot_closed.emit(lot_id)
		return true
	if _last_error_code == "lot_closed":
		sig_lot_closed.emit(lot_id)
	return false

func create_lot(data: Dictionary) -> bool:
	var payload: Dictionary = data.duplicate(true)
	if payload.is_empty():
		_set_error("invalid_input", "Lot payload is empty")
		return false
	var response: Dictionary = await _perform_request(HTTPClient.METHOD_POST, "/auctions", payload)
	if not bool(response.get("ok", false)):
		return false
	var created_lot: Dictionary = _extract_lot_from_response(response.get("data", {}), payload)
	sig_new_lot.emit(created_lot)
	return true

func cancel_lot(lot_id: int) -> bool:
	if lot_id <= 0:
		_set_error("invalid_input", "Invalid lot id")
		return false
	var response: Dictionary = await _perform_request(HTTPClient.METHOD_DELETE, "/auctions/%d" % lot_id)
	if not bool(response.get("ok", false)):
		return false
	sig_lot_closed.emit(lot_id)
	return true

func _sanitize_filters(filters: Dictionary) -> Dictionary:
	var page: int = maxi(1, int(filters.get("page", 1)))
	var page_size: int = maxi(1, mini(100, int(filters.get("page_size", DEFAULT_PAGE_SIZE))))
	return {
		"type": str(filters.get("type", "Hero")).strip_edges(),
		"rarity": str(filters.get("rarity", "All")).strip_edges(),
		"price_min": float(filters.get("price_min", 0.0)),
		"price_max": float(filters.get("price_max", 0.0)),
		"seller": str(filters.get("seller", "")).strip_edges(),
		"sort": str(filters.get("sort", "Time Left")).strip_edges(),
		"search": str(filters.get("search", "")).strip_edges(),
		"page": page,
		"page_size": page_size
	}

func _build_endpoint(filters: Dictionary) -> String:
	var params: Array[String] = []
	params.append("page=%d" % int(filters.get("page", 1)))
	params.append("page_size=%d" % int(filters.get("page_size", DEFAULT_PAGE_SIZE)))

	var type_filter: String = str(filters.get("type", "Hero"))
	if not type_filter.is_empty() and type_filter.to_lower() != "all":
		params.append("type=%s" % _url_encode(type_filter.to_lower()))

	var rarity_filter: String = str(filters.get("rarity", "All"))
	if rarity_filter.to_lower() != "all":
		params.append("rarity=%s" % _url_encode(rarity_filter.to_lower()))

	var price_min: float = float(filters.get("price_min", 0.0))
	if price_min > 0.0:
		params.append("price_min=%s" % str(price_min))

	var price_max: float = float(filters.get("price_max", 0.0))
	if price_max > 0.0:
		params.append("price_max=%s" % str(price_max))

	var seller: String = str(filters.get("seller", ""))
	if not seller.is_empty():
		params.append("seller=%s" % _url_encode(seller))

	var search: String = str(filters.get("search", ""))
	if not search.is_empty():
		params.append("search=%s" % _url_encode(search))

	var sort_value: String = _sort_to_query(str(filters.get("sort", "Time Left")))
	if not sort_value.is_empty():
		params.append("sort=%s" % _url_encode(sort_value))

	return "/auctions/lots?%s" % "&".join(params)

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

func _extract_pagination(parsed: Variant, filters: Dictionary, item_count: int) -> Dictionary:
	var page: int = int(filters.get("page", 1))
	var page_size: int = int(filters.get("page_size", DEFAULT_PAGE_SIZE))
	var total: int = item_count
	var has_next: bool = item_count >= page_size
	if parsed is Dictionary:
		var data: Dictionary = parsed
		if data.has("total"):
			total = int(data.get("total", total))
		if data.has("has_next"):
			has_next = bool(data.get("has_next", has_next))
		if data.has("has_prev"):
			return {
				"page": page,
				"page_size": page_size,
				"total": total,
				"has_next": has_next,
				"has_prev": bool(data.get("has_prev", page > 1))
			}
	return {
		"page": page,
		"page_size": page_size,
		"total": total,
		"has_next": has_next,
		"has_prev": page > 1
	}

func _sort_to_query(value: String) -> String:
	match value.to_lower():
		"time left":
			return "time_left"
		"price asc":
			return "price_asc"
		"price desc":
			return "price_desc"
		"bids count":
			return "bids_count"
		_:
			return ""

func _details_path(_lot_data: Dictionary, lot_id: int) -> String:
	return "/auctions/%d" % lot_id

func _parse_json(body: PackedByteArray) -> Variant:
	var json: JSON = JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		return {}
	return json.data

func _perform_request(method: int, path: String, payload: Dictionary = {}, extra_headers: PackedStringArray = PackedStringArray()) -> Dictionary:
	clear_error()
	var http: HTTPRequest = HTTPRequest.new()
	add_child(http)
	http.timeout = 12.0

	var headers: PackedStringArray = PackedStringArray(["Accept: application/json"])
	for header: String in extra_headers:
		headers.append(header)
	if not AppState.access_token.is_empty():
		headers.append("Authorization: Bearer %s" % AppState.access_token)

	var body_text: String = ""
	if method != HTTPClient.METHOD_GET and method != HTTPClient.METHOD_DELETE:
		headers.append("Content-Type: application/json")
		body_text = JSON.stringify(payload)

	var url: String = ServerConfig.get_instance().get_http_endpoint(path)
	var err: int = http.request(url, headers, method, body_text)
	if err != OK:
		http.queue_free()
		_set_error("request_failed", "Failed to send request")
		return {"ok": false, "code": 0, "data": {}, "headers": PackedStringArray()}

	var response: Array = await http.request_completed
	http.queue_free()
	if response.size() < 4:
		_set_error("request_failed", "Unexpected response")
		return {"ok": false, "code": 0, "data": {}, "headers": PackedStringArray()}

	var result: int = int(response[0])
	var code: int = int(response[1])
	var headers_out: PackedStringArray = response[2]
	var body: PackedByteArray = response[3]
	var data: Variant = _parse_json(body)
	if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
		var message: String = _extract_error_message(data, "Request failed")
		_set_error(_classify_error(code, message), message)
		return {"ok": false, "code": code, "data": data, "headers": headers_out}

	return {"ok": true, "code": code, "data": data, "headers": headers_out}

func _extract_error_message(data: Variant, fallback: String) -> String:
	if data is Dictionary:
		var parsed: Dictionary = data
		if parsed.has("detail"):
			return str(parsed.get("detail", fallback))
		if parsed.has("message"):
			return str(parsed.get("message", fallback))
	return fallback

func _classify_error(code: int, message: String) -> String:
	var m: String = message.to_lower()
	if m.contains("insufficient") or m.contains("not enough") or m.contains("balance"):
		return "insufficient_funds"
	if m.contains("outbid") or m.contains("higher bid") or m.contains("too low"):
		return "outbid"
	if m.contains("closed") or m.contains("finished") or m.contains("expired"):
		return "lot_closed"
	if code == 409:
		return "outbid"
	if code == 410:
		return "lot_closed"
	if code == 402 or code == 403:
		return "insufficient_funds"
	return "request_failed"

func _set_error(error_code: String, message: String) -> void:
	_last_error_code = error_code
	_last_error_message = message

func _extract_lot_from_response(data: Variant, fallback: Dictionary) -> Dictionary:
	if data is Dictionary:
		var parsed: Dictionary = data
		if parsed.has("result") and parsed["result"] is Dictionary:
			return (parsed["result"] as Dictionary).duplicate(true)
		return parsed.duplicate(true)
	return fallback.duplicate(true)

func _url_encode(value: String) -> String:
	return value.uri_encode()
