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
var _last_filters: Dictionary = {"type": "heroes", "page": 1, "page_size": DEFAULT_PAGE_SIZE}
var _last_error_code: String = ""
var _last_error_message: String = ""

func fetch_lots(filters: Dictionary) -> Array:
	var sanitized: Dictionary = _sanitize_filters(filters)
	_last_filters = sanitized.duplicate(true)
	var api_filters: Dictionary = _build_query_filter_dict(sanitized)
	var response: Dictionary = await ApiClient.get_auction_lots(api_filters)
	if bool(response.get("ok", false)) == false:
		_set_error("request_failed", str(response.get("message", "Request failed")))
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

func _build_query_filter_dict(filters: Dictionary) -> Dictionary:
	var query: Dictionary = {
		"page": int(filters.get("page", 1)),
		"page_size": int(filters.get("page_size", DEFAULT_PAGE_SIZE)),
	}
	var type_filter: String = str(filters.get("type", "heroes")).strip_edges()
	if type_filter.is_empty() == false and type_filter.to_lower() != "all":
		query["type"] = _map_category(type_filter)
	var rarity_filter: String = str(filters.get("rarity", "All")).strip_edges()
	if rarity_filter.is_empty() == false and rarity_filter.to_lower() != "all":
		query["rarity"] = rarity_filter.to_lower()
	var price_min: float = float(filters.get("price_min", 0.0))
	if price_min > 0.0:
		query["price_min"] = price_min
	var price_max: float = float(filters.get("price_max", 0.0))
	if price_max > 0.0:
		query["price_max"] = price_max
	var seller: String = str(filters.get("seller", "")).strip_edges()
	if seller.is_empty() == false:
		query["seller"] = seller
	var search: String = str(filters.get("search", "")).strip_edges()
	if search.is_empty() == false:
		query["search"] = search
	var sort_value: String = _sort_to_query(str(filters.get("sort", "Time Left")))
	if sort_value.is_empty() == false:
		query["sort"] = sort_value
	return query

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
		await _sync_after_auction_mutation(false)
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
		await _sync_after_auction_mutation(true)
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
	await _sync_after_auction_mutation(true)
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
	await _sync_after_auction_mutation(true)
	sig_lot_closed.emit(lot_id)
	return true

func _sync_after_auction_mutation(refresh_inventory: bool) -> void:
	await fetch_lots(_last_filters)
	await _refresh_user_profile()
	if refresh_inventory and has_node("/root/InventoryManager"):
		await InventoryManager.get_items()

func _sanitize_filters(filters: Dictionary) -> Dictionary:
	var page: int = maxi(1, int(filters.get("page", 1)))
	var page_size: int = maxi(1, mini(100, int(filters.get("page_size", DEFAULT_PAGE_SIZE))))
	return {
		"type": str(filters.get("type", "heroes")).strip_edges(),
		"rarity": str(filters.get("rarity", "All")).strip_edges(),
		"price_min": float(filters.get("price_min", 0.0)),
		"price_max": float(filters.get("price_max", 0.0)),
		"seller": str(filters.get("seller", "")).strip_edges(),
		"sort": str(filters.get("sort", "Time Left")).strip_edges(),
		"search": str(filters.get("search", "")).strip_edges(),
		"page": page,
		"page_size": page_size
	}

func _build_endpoint_candidates(filters: Dictionary) -> Array[String]:
	var queries: PackedStringArray = _build_query_parts(filters)
	return [
		"/auction/lots?%s" % "&".join(queries),
	]

func _build_query_parts(filters: Dictionary) -> PackedStringArray:
	var params: Array[String] = []
	var page: int = int(filters.get("page", 1))
	var page_size: int = int(filters.get("page_size", DEFAULT_PAGE_SIZE))
	params.append("page=%d" % page)
	params.append("page_size=%d" % page_size)
	params.append("limit=%d" % page_size)
	params.append("offset=%d" % maxi(0, (page - 1) * page_size))

	var type_filter: String = str(filters.get("type", "heroes"))
	if not type_filter.is_empty() and type_filter.to_lower() != "all":
		params.append("type=%s" % _url_encode(_map_category(type_filter)))

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

	return PackedStringArray(params)

func _map_category(value: String) -> String:
	match value.to_lower():
		"heroes":
			return "hero"
		"armor":
			return "armor"
		"helmets":
			return "helmet"
		"gloves":
			return "gloves"
		"artifacts":
			return "artifact"
		"recipes":
			return "recipe"
		"resources":
			return "resource"
		_:
			return value.to_lower()

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
	var has_prev: bool = page > 1
	if parsed is Dictionary:
		var data: Dictionary = parsed
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
				"has_prev": has_prev
			}
	return {
		"page": page,
		"page_size": page_size,
		"total": total,
		"has_next": has_next,
		"has_prev": has_prev
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

	var code: int = int(response.get("code", 0))
	var data: Variant = response.get("data", {})
	if bool(response.get("ok", false)) == false:
		var message: String = str(response.get("message", _extract_error_message(data, "Request failed")))
		_set_error(_classify_error(code, message), message)
		return {"ok": false, "code": code, "data": data, "headers": PackedStringArray(response.get("headers", PackedStringArray()))}

	return {"ok": true, "code": code, "data": data, "headers": PackedStringArray(response.get("headers", PackedStringArray()))}

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
