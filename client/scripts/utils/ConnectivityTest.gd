## Temporary connectivity diagnostic script.
## Attach to any Node and call run_test() or autoload it.
## Tests a direct HTTP GET to the /health endpoint, bypassing NetworkManager entirely.
## If this succeeds but NetworkManager fails → bug is in the NetworkManager abstraction.
## If this also fails → problem is network / firewall / wrong IP.
extends Node
class_name ConnectivityTest

const TEST_ENDPOINTS: Array[String] = [
	"http://127.0.0.1:8081/health/",   # loopback (same machine)
	"http://127.0.0.1:8081/",          # root fallback
]

var _pending_tests: int = 0

func _ready() -> void:
	run_test()

func run_test() -> void:
	# 1. Print resolved config for comparison
	var cfg = ServerConfig.get_instance()
	print("===== CONNECTIVITY TEST =====")
	print("[DIAG] ServerConfig  ip        = %s" % cfg.ip)
	print("[DIAG] ServerConfig  http_port = %d" % cfg.http_port)
	print("[DIAG] ServerConfig  use_https = %s" % cfg.use_https)
	print("[DIAG] ServerConfig  base_url  = %s" % cfg.get_http_base_url())

	# 2. Fire direct HTTP requests to known-good local endpoints
	for url in TEST_ENDPOINTS:
		_fire_test(url)

	# 3. Also test the URL that NetworkManager would actually build
	var nm_url = cfg.get_http_endpoint(cfg.status_endpoint)
	if nm_url not in TEST_ENDPOINTS:
		_fire_test(nm_url)

func _fire_test(url: String) -> void:
	_pending_tests += 1
	var http := HTTPRequest.new()
	add_child(http)
	http.timeout = 5.0
	var start_ms := Time.get_ticks_msec()

	http.request_completed.connect(func(result: int, code: int, headers: PackedStringArray, body: PackedByteArray):
		var latency := Time.get_ticks_msec() - start_ms
		var body_text := body.get_string_from_utf8().left(200)
		if result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 400:
			print("[DIAG OK]   %s → HTTP %d  (%d ms)  body=%s" % [url, code, latency, body_text])
		else:
			print("[DIAG FAIL] %s → result=%d  HTTP %d  (%d ms)  body=%s" % [url, result, code, latency, body_text])
			_print_result_hint(result)
		http.queue_free()
		_pending_tests -= 1
		if _pending_tests <= 0:
			print("===== CONNECTIVITY TEST DONE =====")
	)

	print("[DIAG SEND] GET %s (timeout=%.1fs)" % [url, http.timeout])
	var err = http.request(url, [], HTTPClient.METHOD_GET)
	if err != OK:
		print("[DIAG REQUEST_ERR] %s → request() err=%d" % [url, err])
		http.queue_free()
		_pending_tests -= 1

func _print_result_hint(result: int) -> void:
	match result:
		HTTPRequest.RESULT_CANT_CONNECT:
			print("  ↳ CANT_CONNECT – TCP refused or unreachable. Check IP/port/firewall.")
		HTTPRequest.RESULT_CANT_RESOLVE:
			print("  ↳ CANT_RESOLVE – DNS lookup failed. Check hostname.")
		HTTPRequest.RESULT_TIMEOUT:
			print("  ↳ TIMEOUT – No response within timeout. Server down or port blocked.")
		HTTPRequest.RESULT_CONNECTION_ERROR:
			print("  ↳ CONNECTION_ERROR – Connection dropped mid-request.")
		_:
			print("  ↳ Unknown result code %d" % result)
