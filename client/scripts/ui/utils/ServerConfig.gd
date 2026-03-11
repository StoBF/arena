extends RefCounted
class_name ServerConfig

# ===============================
# Server configuration fields
# ===============================

var ip: String = ""
var http_port: int = 8000
var ws_port: int = 8000
var status_endpoint: String = "/health"
var use_https: bool = false

# ===============================
# Singleton instance
# ===============================

static var _instance: ServerConfig = null

static func get_instance() -> ServerConfig:
	if _instance == null:
		_instance = ServerConfig.new()
		_instance._load_config()
	return _instance


# ===============================
# URL builders
# ===============================

func get_http_base_url() -> String:
	var protocol := "https://" if use_https else "http://"
	return "%s%s:%d" % [protocol, ip, http_port]

func get_ws_base_url() -> String:
	var protocol := "wss://" if use_https else "ws://"
	return "%s%s:%d" % [protocol, ip, ws_port]

func get_http_endpoint(path: String) -> String:
	return get_http_base_url() + path

func get_ws_endpoint(channel: String, token: String) -> String:
	return "%s/ws/%s?token=%s" % [get_ws_base_url(), channel, token]


# ===============================
# Load configuration (Godot 4)
# ===============================

func _load_config() -> void:
	var env_name := OS.get_environment("ARENA_ENV")
	if env_name == "":
		env_name = "dev"

	var json_path := "res://config/%s.json" % env_name

	# ---- Try JSON config ----
	if FileAccess.file_exists(json_path):
		var file := FileAccess.open(json_path, FileAccess.READ)
		if file:
			var text := file.get_as_text()
			file.close()

			var parsed: Variant = JSON.parse_string(text)
			if typeof(parsed) == TYPE_DICTIONARY:
				var data: Dictionary = parsed
				ip = str(data.get("ip", ip))
				http_port = int(data.get("http_port", http_port))
				ws_port = int(data.get("ws_port", ws_port))
				use_https = bool(data.get("use_https", use_https))
				status_endpoint = str(data.get("status_endpoint", status_endpoint))
				return
				ip = str(data.get("ip", ip))
				http_port = int(data.get("http_port", http_port))
				ws_port = int(data.get("ws_port", ws_port))
				use_https = bool(data.get("use_https", use_https))
				status_endpoint = str(data.get("status_endpoint", status_endpoint))
				print("Loaded config from JSON:", json_path)
				return

	# ---- Fallback to user config ----
	var user_path := "user://server_config.cfg"
	var cfg := ConfigFile.new()
	var err := cfg.load(user_path)

	if err == OK:
		ip = cfg.get_value("server", "ip", ip)
		http_port = cfg.get_value("server", "http_port", http_port)
		ws_port = cfg.get_value("server", "ws_port", ws_port)
		use_https = cfg.get_value("server", "use_https", use_https)
		status_endpoint = cfg.get_value("server", "status_endpoint", status_endpoint)
		print("Loaded config from user://")
	else:
		_save_config()


# ===============================
# Save configuration
# ===============================

func _save_config() -> void:
	var user_path := "user://server_config.cfg"
	var cfg := ConfigFile.new()

	cfg.set_value("server", "ip", ip)
	cfg.set_value("server", "http_port", http_port)
	cfg.set_value("server", "ws_port", ws_port)
	cfg.set_value("server", "use_https", use_https)
	cfg.set_value("server", "status_endpoint", status_endpoint)

	cfg.save(user_path)


# ===============================
# Update config runtime
# ===============================

static func update_config(new_ip: String, http_port_num: int, ws_port_num: int, secure: bool = false) -> void:
	var instance := get_instance()
	instance.ip = new_ip
	instance.http_port = http_port_num
	instance.ws_port = ws_port_num
	instance.use_https = secure
	instance._save_config()


# ===============================
# Simple HTTP status check
# ===============================

func check_server_status(parent_node: Node) -> void:
	var req := HTTPRequest.new()
	parent_node.add_child(req)
	req.request_completed.connect(parent_node._on_request_completed)

	var err := req.request(get_http_endpoint(status_endpoint))
	if err != OK:
		print("HTTP request error:", err)
