extends RefCounted
class_name ServerConfig

# Server configuration
var ip: String = ""
var http_port: int = 0
var ws_port: int = 0
var status_endpoint: String = "/health"
var use_https: bool = false

# Singleton instance
static var _instance: ServerConfig

static func get_instance() -> ServerConfig:
	if _instance == null:
		_instance = ServerConfig.new()
		_load_config()
	return _instance

# Computed properties
func get_http_base_url() -> String:
	var protocol = "https://" if use_https else "http://"
	return "%s%s:%d" % [protocol, ip, http_port]

func get_ws_base_url() -> String:
	var protocol = "wss://" if use_https else "ws://"
	return "%s%s:%d" % [protocol, ip, ws_port]

func get_http_endpoint(path: String) -> String:
	# Normalize: ensure path starts with /
	# Do NOT auto-append trailing slash — FastAPI routes like /auth/me, /heroes/generate
	# are defined WITHOUT trailing slash; appending one causes 307 redirects that
	# Godot HTTPRequest cannot follow transparently.
	if not path.begins_with("/"):
		path = "/" + path
	return get_http_base_url() + path

func get_ws_endpoint(channel: String, token: String) -> String:
	return "%s/ws/%s?token=%s" % [get_ws_base_url(), channel, token]

# Load configuration from file
static func _load_config() -> void:
	var config = get_instance()
	# Decide environment (dev/prod) via ARENA_ENV environment variable, default to "dev"
	var env = OS.get_environment("ARENA_ENV")
	if env == "":
		env = "dev"

	var json_path = "res://config/%s.json" % env
	var f = FileAccess.open(json_path, FileAccess.READ)
	if f == null:
		print("[ServerConfig] WARNING: Could not open %s (FileAccess error %d). Using defaults/fallback." % [json_path, FileAccess.get_open_error()])
	if f != null:
		var text = f.get_as_text()
		var json = JSON.new()
		var err = json.parse(text)
		if err == OK:
			var data = json.data
			config.ip = str(data.get("ip", config.ip))
			config.http_port = int(data.get("http_port", config.http_port))
			config.ws_port = int(data.get("ws_port", config.ws_port))
			config.use_https = bool(data.get("use_https", config.use_https))
			config.status_endpoint = str(data.get("status_endpoint", config.status_endpoint))
			print("[ServerConfig] Loaded from %s → ip=%s http_port=%d ws_port=%d use_https=%s" % [json_path, config.ip, config.http_port, config.ws_port, config.use_https])
			print("[ServerConfig] HTTP base URL = %s" % config.get_http_base_url())
			return
		else:
			print("[ServerConfig] JSON parse error for %s" % json_path)

# Fallback: try existing user config (keeps previous behavior)
	var config_path = "user://server_config.cfg"
	var file = ConfigFile.new()
	var load_err = file.load(config_path)
	if load_err == OK:
		print("[ServerConfig] Falling back to user config: %s" % config_path)
		config.ip = file.get_value("server", "ip", config.ip)
		config.http_port = file.get_value("server", "http_port", config.http_port)
		config.ws_port = file.get_value("server", "ws_port", config.ws_port)
		config.use_https = file.get_value("server", "use_https", config.use_https)
		config.status_endpoint = file.get_value("server", "status_endpoint", config.status_endpoint)
		print("[ServerConfig] Fallback → ip=%s http_port=%d use_https=%s" % [config.ip, config.http_port, config.use_https])
		print("[ServerConfig] HTTP base URL = %s" % config.get_http_base_url())
	else:
		print("[ServerConfig] No user config found, saving defaults.")
		_save_config()

static func _save_config() -> void:
	var config = get_instance()
	var config_path = "user://server_config.cfg"
	var file = ConfigFile.new()
	file.set_value("server", "ip", config.ip)
	file.set_value("server", "http_port", config.http_port)
	file.set_value("server", "ws_port", config.ws_port)
	file.set_value("server", "use_https", config.use_https)
	file.set_value("server", "status_endpoint", config.status_endpoint)
	file.save(config_path)

static func update_config(ip: String, http_port_num: int, ws_port_num: int, secure: bool = false) -> void:
	var config = get_instance()
	config.ip = ip
	config.http_port = http_port_num
	config.ws_port = ws_port_num
	config.use_https = secure
	_save_config()

# ---------- HTTP Request helper ----------
# Використовувати так: ServerConfig.get_instance().check_server_status(self)
func check_server_status(parent_node: Node) -> void:
	var req = HTTPRequest.new()
	parent_node.add_child(req)
	req.request_completed.connect(parent_node._on_request_completed)
	var err = req.request(get_http_endpoint(status_endpoint))
	if err != OK:
		print("HTTP request error: ", err)

func _on_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	print("Result: ", result)
	print("Response Code: ", response_code)
	print("Body: ", body.get_string_from_utf8())
