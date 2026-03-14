extends Node
class_name NetworkManager

signal request_completed(request_id: int, result: int, code: int, headers: PackedStringArray, body_text: String)
signal server_status_checked(online: bool, latency_ms: float, error_message: String)
signal token_refreshed(success: bool)

const STATUS_TIMEOUT: float = 3.0
const REQUEST_TIMEOUT: float = 10.0

var default_headers: PackedStringArray = PackedStringArray()
var max_retries: int = 2
var retry_delay: float = 0.35

var _status_request: HTTPRequest = null
var _status_request_start_time: float = 0.0
var _token_refresh_in_progress: bool = false


func _ready() -> void:
	_update_default_headers()


func set_auth_header(token: String) -> void:
	AppState.set_access_token(token)
	_update_default_headers()


func request(endpoint: String, method := HTTPClient.METHOD_GET, data := {}, headers := [], _retry_count := 0) -> HTTPRequest:
	var req := HTTPRequest.new()
	add_child(req)
	req.timeout = REQUEST_TIMEOUT

	var final_headers: PackedStringArray = _build_headers(method, _headers_to_packed(headers), true)
	var body: String = ""
	if method != HTTPClient.METHOD_GET and method != HTTPClient.METHOD_DELETE:
		body = JSON.stringify(data)

	var url: String = ServerConfig.get_instance().get_http_endpoint(endpoint)
	var request_id: int = req.get_instance_id()
	req.request_completed.connect(func(result: int, code: int, response_headers: PackedStringArray, response_body: PackedByteArray):
		emit_signal("request_completed", request_id, result, code, response_headers, response_body.get_string_from_utf8())
		req.queue_free()
	)

	var err: int = req.request(url, final_headers, method, body)
	if err != OK:
		emit_signal("request_completed", request_id, HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), "")
		req.queue_free()
		return null
	return req


func request_json(
	endpoint: String,
	method: int,
	payload: Dictionary = {},
	headers: PackedStringArray = PackedStringArray(),
	options: Dictionary = {}
) -> Dictionary:
	var retries: int = maxi(0, int(options.get("max_retries", max_retries)))
	var allow_refresh: bool = bool(options.get("allow_refresh", true))
	var include_auth: bool = bool(options.get("include_auth", true))
	var refresh_attempted: bool = false
	var attempt: int = 0

	while true:
		var response: Dictionary = await _send_once(endpoint, method, payload, headers, include_auth)

		if int(response.get("code", 0)) == 401 and allow_refresh and not refresh_attempted and _should_attempt_refresh(endpoint):
			refresh_attempted = true
			if await _refresh_access_token_single_flight():
				continue

		if _should_retry(response) and attempt < retries:
			attempt += 1
			await get_tree().create_timer(retry_delay * attempt).timeout
			continue

		return response


func _send_once(endpoint: String, method: int, payload: Dictionary, headers: PackedStringArray, include_auth: bool) -> Dictionary:
	var req := HTTPRequest.new()
	add_child(req)
	req.timeout = REQUEST_TIMEOUT

	var final_headers: PackedStringArray = _build_headers(method, headers, include_auth)
	var body: String = ""
	if method != HTTPClient.METHOD_GET and method != HTTPClient.METHOD_DELETE:
		body = JSON.stringify(payload)

	var url: String = ServerConfig.get_instance().get_http_endpoint(endpoint)
	var err: int = req.request(url, final_headers, method, body)
	if err != OK:
		req.queue_free()
		return {
			"ok": false,
			"result": HTTPRequest.RESULT_CANT_CONNECT,
			"code": 0,
			"headers": PackedStringArray(),
			"data": {},
			"raw_body": "",
			"message": "Failed to start request"
		}

	var result_data: Array = await req.request_completed
	req.queue_free()
	if result_data.size() < 4:
		return {
			"ok": false,
			"result": HTTPRequest.RESULT_CANT_CONNECT,
			"code": 0,
			"headers": PackedStringArray(),
			"data": {},
			"raw_body": "",
			"message": "Invalid response"
		}

	var result: int = int(result_data[0])
	var code: int = int(result_data[1])
	var response_headers: PackedStringArray = result_data[2]
	var response_body: PackedByteArray = result_data[3]
	var body_text: String = response_body.get_string_from_utf8()
	var parsed: Variant = _parse_json(body_text)
	var ok: bool = result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300

	return {
		"ok": ok,
		"result": result,
		"code": code,
		"headers": response_headers,
		"data": parsed,
		"raw_body": body_text,
		"message": "" if ok else _extract_error_message(parsed, body_text, code, result)
	}


func _build_headers(method: int, headers: PackedStringArray, include_auth: bool) -> PackedStringArray:
	var final_headers: PackedStringArray = PackedStringArray()
	final_headers.append("Accept: application/json")
	if include_auth and not AppState.access_token.is_empty():
		final_headers.append("Authorization: Bearer %s" % AppState.access_token)
	for h: String in default_headers:
		if not final_headers.has(h):
			final_headers.append(h)
	for h: String in headers:
		if not final_headers.has(h):
			final_headers.append(h)
	if method != HTTPClient.METHOD_GET and method != HTTPClient.METHOD_DELETE and not _has_header(final_headers, "Content-Type"):
		final_headers.append("Content-Type: application/json")
	return final_headers


func _update_default_headers() -> void:
	default_headers = PackedStringArray()


func _headers_to_packed(headers: Array) -> PackedStringArray:
	var packed: PackedStringArray = PackedStringArray()
	for h: Variant in headers:
		packed.append(str(h))
	return packed


func _has_header(headers: PackedStringArray, key: String) -> bool:
	var lower_key: String = key.to_lower()
	for h: String in headers:
		if h.to_lower().begins_with(lower_key + ":"):
			return true
	return false


func _should_retry(response: Dictionary) -> bool:
	var result: int = int(response.get("result", HTTPRequest.RESULT_CANT_CONNECT))
	var code: int = int(response.get("code", 0))
	if result != HTTPRequest.RESULT_SUCCESS:
		return true
	return code >= 500


func _should_attempt_refresh(endpoint: String) -> bool:
	return not endpoint.begins_with("/auth/login") \
		and not endpoint.begins_with("/auth/register") \
		and not endpoint.begins_with("/auth/refresh")


func _refresh_access_token_single_flight() -> bool:
	if _token_refresh_in_progress:
		var wait_result: Array = await token_refreshed
		if wait_result.is_empty():
			return false
		return bool(wait_result[0])

	_token_refresh_in_progress = true
	var refresh_payload: Dictionary = {}
	if not AppState.refresh_token.is_empty():
		refresh_payload["refresh_token"] = AppState.refresh_token

	var response: Dictionary = await _send_once("/auth/refresh", HTTPClient.METHOD_POST, refresh_payload, PackedStringArray(), false)
	var success: bool = false
	if bool(response.get("ok", false)):
		var data: Dictionary = _as_dict(response.get("data", {}))
		var new_access: String = str(data.get("access_token", ""))
		if not new_access.is_empty():
			AppState.set_access_token(new_access)
			var rotated_refresh: String = str(data.get("refresh_token", ""))
			if not rotated_refresh.is_empty():
				AppState.refresh_token = rotated_refresh
			success = true

	_token_refresh_in_progress = false
	token_refreshed.emit(success)
	return success


func _as_dict(value: Variant) -> Dictionary:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return {}


func _parse_json(body_text: String) -> Variant:
	if body_text.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(body_text)
	if parsed == null:
		return {}
	return parsed


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

# ====== Server status check ======
func check_server_status() -> void:
	if _status_request != null and is_instance_valid(_status_request):
		return

	var config = ServerConfig.get_instance()
	var path = config.status_endpoint if config.status_endpoint else "/"
	var url = config.get_http_endpoint(path)

	_status_request = HTTPRequest.new()
	add_child(_status_request)
	_status_request.timeout = STATUS_TIMEOUT
	_status_request_start_time = Time.get_ticks_msec()
	_status_request.request_completed.connect(_on_status_request_completed)

	var err = _status_request.request(url, [], HTTPClient.METHOD_GET)
	if err != OK:
		_emit_status_result(false, 0.0, "Request failed: %s" % err)
		_cleanup_status_request()

func _on_status_request_completed(_result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	var latency_ms = float(Time.get_ticks_msec() - _status_request_start_time)
	var online = _result == HTTPRequest.RESULT_SUCCESS and response_code >= 200 and response_code < 300
	var err_msg: String = ""
	if not online:
		if _result != HTTPRequest.RESULT_SUCCESS:
			err_msg = _get_result_error_string(_result)
		else:
			err_msg = "HTTP %d" % response_code
	_emit_status_result(online, latency_ms, err_msg)
	_cleanup_status_request()

func _get_result_error_string(result: int) -> String:
	match result:
		HTTPRequest.RESULT_CANT_CONNECT: return "CANT_CONNECT"
		HTTPRequest.RESULT_CANT_RESOLVE: return "CANT_RESOLVE"
		HTTPRequest.RESULT_CONNECTION_ERROR: return "CONNECTION_ERROR"
		HTTPRequest.RESULT_TIMEOUT: return "TIMEOUT"
		_: return "ERROR_%d" % result

func _emit_status_result(online: bool, latency_ms: float, error_message: String) -> void:
	emit_signal("server_status_checked", online, latency_ms, error_message)

func _cleanup_status_request() -> void:
	if _status_request != null and is_instance_valid(_status_request):
		_status_request.queue_free()
		_status_request = null