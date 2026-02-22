extends Node
class_name NetworkManager

signal request_completed(result: int, code: int, headers: PackedStringArray, body_text: String)
signal server_status_checked(online: bool, latency_ms: float, error_message: String)
signal token_refreshed(success: bool)

# ====== Configuration ======
var default_headers: Array = []
var max_retries: int = 3
var retry_delay: float = 1.0  # seconds

const STATUS_TIMEOUT: float = 3.0
var _status_request: HTTPRequest = null
var _status_request_start_time: float = 0.0

# Active requests cache
var active_requests: Dictionary = {}

# Token refresh protection (prevent infinite loops)
var _token_refresh_in_progress: bool = false
var _failed_refresh_attempts: int = 0
var _max_refresh_attempts: int = 1  # Try refresh only once

# ====== Public methods ======
func set_auth_header(token: String) -> void:
	"""Legacy method for backwards compatibility"""
	AppState.access_token = token
	_update_default_headers()

func _update_default_headers() -> void:
	"""Update default headers with current access token"""
	default_headers.clear()
	if not AppState.access_token.is_empty():
		default_headers.append("Authorization: Bearer %s" % AppState.access_token)

func request(endpoint: String, method := HTTPClient.METHOD_GET, data := {}, headers := [], retry_count := 0) -> HTTPRequest:
	var config = ServerConfig.get_instance()
	var url = config.get_http_endpoint(endpoint)
	
	var http_request := HTTPRequest.new()
	add_child(http_request)

	var request_id = http_request.get_instance_id()
	active_requests[request_id] = {
		"endpoint": endpoint,
		"method": method,
		"data": data,
		"headers": headers,
		"retry_count": retry_count,
		"http_request": http_request
	}

	var final_headers := default_headers.duplicate()
	final_headers.append_array(headers)

	var json_data: String = ""
	if method != HTTPClient.METHOD_GET:
		json_data = JSON.stringify(data)
		final_headers.append("Content-Type: application/json")

	http_request.timeout = 10.0
	http_request.request_completed.connect(func(result, code, hdrs, body):
		_on_request_completed(request_id, result, code, hdrs, body)
	)

	var err = http_request.request(url, final_headers, method, json_data)
	if err != OK:
		print("HTTP request failed: ", err)
		_handle_request_error(request_id, err)

	return http_request

# ====== Internal callbacks ======
func _on_request_completed(request_id: int, result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	var request_info = active_requests.get(request_id, null)
	if request_info == null:
		return

	var body_text: String = body.get_string_from_utf8()

	# CRITICAL: Handle 401 Unauthorized - token may have expired
	# Try to refresh and retry request ONCE
	if response_code == 401 and not request_info.get("is_retry_after_refresh", false):
		print("[AUTH_REFRESH_NEEDED] endpoint=%s (401 response)" % request_info.endpoint)
		if await _handle_token_expiration(request_info):
			# Token refresh succeeded - don't emit signal, just clean up
			if request_info.http_request:
				request_info.http_request.queue_free()
			active_requests.erase(request_id)
			return
		# Token refresh failed - treat as normal 401
	
	# Retry if failed or server error (but not 401 - those are auth failures)
	if result != HTTPRequest.RESULT_SUCCESS or (response_code >= 500 and response_code != 401 and request_info.retry_count < max_retries):
		_retry_request(request_info)
	else:
		# Emit success or final failure
		emit_signal("request_completed", result, response_code, headers, body_text)

	# Cleanup
	if request_info.http_request:
		request_info.http_request.queue_free()
	active_requests.erase(request_id)

func _retry_request(request_info: Dictionary) -> void:
	request_info.retry_count += 1
	print("Retrying request (attempt %d/%d): %s" % [request_info.retry_count, max_retries, request_info.endpoint])

	await get_tree().create_timer(retry_delay * request_info.retry_count).timeout

	request(
		request_info.endpoint,
		request_info.method,
		request_info.data,
		request_info.headers,
		request_info.retry_count
	)

# ====== Token Refresh Logic ======
func _handle_token_expiration(original_request: Dictionary) -> bool:
	"""Handle 401 response by attempting token refresh and retry
	
	SAFEGUARD: Only try refresh ONCE to prevent infinite loops
	Returns: true if refresh succeeded and request was retried, false otherwise
	"""
	# SAFEGUARD 1: Prevent infinite refresh loops
	if _token_refresh_in_progress:
		print("[AUTH_REFRESH_LOOP_PREVENTED] refresh already in progress, aborting")
		return false
	
	if _failed_refresh_attempts >= _max_refresh_attempts:
		print("[AUTH_REFRESH_MAX_ATTEMPTS] reached max refresh attempts, giving up")
		return false
	
	_token_refresh_in_progress = true
	_failed_refresh_attempts += 1
	
	print("[AUTH_ATTEMPTING_REFRESH] attempt=%d/%d" % [_failed_refresh_attempts, _max_refresh_attempts])
	
	# Call refresh endpoint
	var refresh_success = await _refresh_access_token()
	
	if not refresh_success:
		print("[AUTH_REFRESH_FAILED] could not refresh token")
		_token_refresh_in_progress = false
		return false
	
	print("[AUTH_REFRESH_SUCCESS] retrying original request")
	
	# Mark request as retry-after-refresh to prevent another refresh attempt
	original_request["is_retry_after_refresh"] = true
	original_request.retry_count = 0  # Reset retry count for the retry
	
	# Retry original request with new token
	request(
		original_request.endpoint,
		original_request.method,
		original_request.data,
		original_request.headers,
		0  # Reset retry count
	)
	
	_token_refresh_in_progress = false
	return true

func _refresh_access_token() -> bool:
	"""Call /auth/refresh endpoint to get new access token
	
	Uses refresh token from HTTP-only cookie (sent automatically by Browser/HTTPClient).
	Sets new refresh token cookie (received in response).
	
	Returns: true if successful, false otherwise
	"""
	var config = ServerConfig.get_instance()
	var url = config.get_http_endpoint("/auth/refresh")
	
	var http_request := HTTPRequest.new()
	add_child(http_request)
	http_request.timeout = 10.0
	
	var refresh_completed = false
	var refresh_success = false
	
	http_request.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray):
		if result == HTTPRequest.RESULT_SUCCESS and code == 200:
			# Parse new access token from response
			var body_text = body.get_string_from_utf8()
			var json = JSON.new()
			if json.parse(body_text) == OK:
				var data = json.data
				if data and data.has("access_token"):
					AppState.access_token = data["access_token"]
					_update_default_headers()
					print("[AUTH_TOKEN_UPDATED] new access token obtained")
					refresh_success = true
				else:
					print("[AUTH_PARSE_ERROR] no access_token in refresh response")
			else:
				print("[AUTH_JSON_ERROR] failed to parse refresh response")
		else:
			print("[AUTH_REFRESH_HTTP_ERROR] response_code=%d result=%d" % [code, result])
		
		refresh_completed = true
	)
	
	# Request /refresh endpoint (refresh token in HTTP-only cookie sent automatically)
	var err = http_request.request(url, [], HTTPClient.METHOD_POST, "")
	if err != OK:
		print("[AUTH_REFRESH_REQUEST_ERROR] failed to send refresh request: %s" % err)
		http_request.queue_free()
		return false
	
	# Wait for response with timeout
	var timeout = 0.0
	while not refresh_completed and timeout < 10.0:
		await get_tree().process_frame
		timeout += 0.016  # ~60fps
	
	http_request.queue_free()
	
	if not refresh_completed:
		print("[AUTH_REFRESH_TIMEOUT] refresh request timed out")
		return false
	
	return refresh_success

func _handle_request_error(request_id: int, error: int) -> void:
	var request_info = active_requests.get(request_id, null)
	if request_info == null:
		return

	if request_info.retry_count < max_retries:
		_retry_request(request_info)
	else:
		emit_signal("request_completed", HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray())

	if request_info.http_request:
		request_info.http_request.queue_free()
	active_requests.erase(request_id)

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