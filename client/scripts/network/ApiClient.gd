extends Node

## Thin centralized HTTP facade over Network autoload.
## Safe migration path: existing scripts can continue using Network directly,
## while new/updated services move to ApiClient incrementally.

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