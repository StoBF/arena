extends Node

# Unified WebSocket manager for:
# - chat channels
# - auction events
#
# Godot 4.5
# Autoload usage:
#   WebSocketManager.ensure_chat_subscription("general")
#   WebSocketManager.ensure_auction_subscription()

signal chat_message_received(channel: String, message: Dictionary)
signal chat_socket_state_changed(channel: String, connected: bool)

signal auction_bid_update(event_data: Dictionary)
signal auction_lot_closed(event_data: Dictionary)
signal auction_lot_created(event_data: Dictionary)
signal auction_socket_state_changed(connected: bool)

const CHAT_CHANNELS: PackedStringArray = ["general", "trade", "system"]

const CHAT_WS_PATH_TEMPLATE: String = "/ws/%s"
const AUCTION_WS_PATH: String = "/ws/auctions"

const CHAT_RECONNECT_BASE_DELAY: float = 2.0
const AUCTION_RECONNECT_BASE_DELAY: float = 1.0
const RECONNECT_MAX_DELAY: float = 20.0


# -----------------------------
# Chat state
# -----------------------------
var _chat_sockets: Dictionary = {}               # channel -> WebSocketPeer
var _chat_connected: Dictionary = {}             # channel -> bool
var _chat_should_run: Dictionary = {}            # channel -> bool
var _chat_reconnect_attempts: Dictionary = {}    # channel -> int
var _chat_reconnect_scheduled: Dictionary = {}   # channel -> bool


# -----------------------------
# Auction state
# -----------------------------
var _auction_socket: WebSocketPeer = null
var _auction_connected: bool = false
var _auction_should_run: bool = false
var _auction_reconnect_attempts: int = 0
var _auction_reconnect_scheduled: bool = false


func _ready() -> void:
	_initialize_chat_state()
	set_process(true)


func _process(_delta: float) -> void:
	_poll_chat_connections()
	_poll_auction_connection()


# =========================================================
# Public API — Chat
# =========================================================
func ensure_chat_subscription(channel: String) -> void:
	if not _is_valid_chat_channel(channel):
		push_warning("WebSocketManager.ensure_chat_subscription(): invalid channel '%s'" % channel)
		return

	_chat_should_run[channel] = true
	_chat_reconnect_scheduled[channel] = false

	if _get_chat_socket(channel) == null:
		_connect_chat_socket(channel)


func stop_chat_subscription(channel: String) -> void:
	if not _is_valid_chat_channel(channel):
		push_warning("WebSocketManager.stop_chat_subscription(): invalid channel '%s'" % channel)
		return

	_chat_should_run[channel] = false
	_chat_reconnect_scheduled[channel] = false
	_close_chat_socket(channel)

	if _get_chat_connected(channel):
		_set_chat_connected(channel, false)


func send_chat_message(channel: String, text: String) -> void:
	if not _is_valid_chat_channel(channel):
		push_warning("WebSocketManager.send_chat_message(): invalid channel '%s'" % channel)
		return

	var trimmed_text: String = text.strip_edges()
	if trimmed_text.is_empty():
		return

	var socket: WebSocketPeer = _get_chat_socket(channel)
	if socket == null:
		return

	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return

	var payload: Dictionary = {
		"text": trimmed_text
	}
	var json_text: String = JSON.stringify(payload)
	var packet: PackedByteArray = json_text.to_utf8_buffer()
	var err: int = socket.put_packet(packet)
	if err != OK:
		push_warning("WebSocketManager.send_chat_message(): put_packet failed for channel '%s' with error %d" % [channel, err])


# =========================================================
# Public API — Auction
# =========================================================
func ensure_auction_subscription() -> void:
	_auction_should_run = true
	_auction_reconnect_scheduled = false

	if _auction_socket == null:
		_connect_auction_socket()


func stop_auction_subscription() -> void:
	_auction_should_run = false
	_auction_reconnect_scheduled = false

	if _auction_socket != null:
		_auction_socket.close()
		_auction_socket = null

	if _auction_connected:
		_set_auction_connected(false)


# For tests or manual simulation only.
func process_auction_raw_packet(raw_packet: String) -> void:
	_dispatch_auction_packet(raw_packet)


# =========================================================
# Chat internals
# =========================================================
func _initialize_chat_state() -> void:
	for channel: String in CHAT_CHANNELS:
		_chat_sockets[channel] = null
		_chat_connected[channel] = false
		_chat_should_run[channel] = false
		_chat_reconnect_attempts[channel] = 0
		_chat_reconnect_scheduled[channel] = false


func _poll_chat_connections() -> void:
	for channel: String in CHAT_CHANNELS:
		var socket: WebSocketPeer = _get_chat_socket(channel)

		if socket == null:
			if _get_chat_should_run(channel) and not _is_chat_reconnect_scheduled(channel):
				_connect_chat_socket(channel)
			continue

		socket.poll()
		var state: int = socket.get_ready_state()

		match state:
			WebSocketPeer.STATE_OPEN:
				if not _get_chat_connected(channel):
					_chat_reconnect_attempts[channel] = 0
					_chat_reconnect_scheduled[channel] = false
					_set_chat_connected(channel, true)

				_process_chat_packets(channel, socket)

			WebSocketPeer.STATE_CLOSED:
				_handle_chat_closed(channel)

			_:
				pass


func _connect_chat_socket(channel: String) -> void:
	if not _get_chat_should_run(channel):
		return

	var token: String = _get_auth_token()
	if token.is_empty():
		return

	var path: String = CHAT_WS_PATH_TEMPLATE % channel
	var url: String = _build_ws_url(path, token)

	var socket: WebSocketPeer = WebSocketPeer.new()
	var err: int = socket.connect_to_url(url)
	if err != OK:
		_chat_sockets[channel] = null
		_schedule_chat_reconnect(channel)
		return

	_chat_sockets[channel] = socket
	_chat_reconnect_scheduled[channel] = false


func _handle_chat_closed(channel: String) -> void:
	if _get_chat_connected(channel):
		_set_chat_connected(channel, false)

	_close_chat_socket(channel)

	if _get_chat_should_run(channel):
		_schedule_chat_reconnect(channel)


func _process_chat_packets(channel: String, socket: WebSocketPeer) -> void:
	while socket.get_available_packet_count() > 0:
		var raw_packet: PackedByteArray = socket.get_packet()
		var text: String = raw_packet.get_string_from_utf8()

		if text.is_empty():
			continue

		var parsed: Variant = _parse_json_packet(text)
		if typeof(parsed) != TYPE_DICTIONARY:
			continue

		var message: Dictionary = parsed.duplicate(true)
		chat_message_received.emit(channel, message)


func _schedule_chat_reconnect(channel: String) -> void:
	if not _get_chat_should_run(channel):
		return

	if _is_chat_reconnect_scheduled(channel):
		return

	_chat_reconnect_scheduled[channel] = true

	var attempts: int = int(_chat_reconnect_attempts.get(channel, 0))
	var delay: float = minf(
		RECONNECT_MAX_DELAY,
		CHAT_RECONNECT_BASE_DELAY * pow(2.0, float(attempts))
	)

	_chat_reconnect_attempts[channel] = attempts + 1

	var timer: SceneTreeTimer = get_tree().create_timer(delay)
	timer.timeout.connect(_on_chat_reconnect_timeout.bind(channel))


func _on_chat_reconnect_timeout(channel: String) -> void:
	_chat_reconnect_scheduled[channel] = false

	if not _is_valid_chat_channel(channel):
		return

	if not _get_chat_should_run(channel):
		return

	if _get_chat_socket(channel) != null:
		return

	_connect_chat_socket(channel)


func _close_chat_socket(channel: String) -> void:
	var socket: WebSocketPeer = _get_chat_socket(channel)
	if socket != null:
		socket.close()

	_chat_sockets[channel] = null


func _get_chat_socket(channel: String) -> WebSocketPeer:
	if not _chat_sockets.has(channel):
		return null

	var value: Variant = _chat_sockets[channel]
	if value is WebSocketPeer:
		return value

	return null


func _get_chat_connected(channel: String) -> bool:
	return bool(_chat_connected.get(channel, false))


func _set_chat_connected(channel: String, connected: bool) -> void:
	var old_value: bool = bool(_chat_connected.get(channel, false))
	_chat_connected[channel] = connected

	if old_value != connected:
		chat_socket_state_changed.emit(channel, connected)


func _get_chat_should_run(channel: String) -> bool:
	return bool(_chat_should_run.get(channel, false))


func _is_chat_reconnect_scheduled(channel: String) -> bool:
	return bool(_chat_reconnect_scheduled.get(channel, false))


func _is_valid_chat_channel(channel: String) -> bool:
	return CHAT_CHANNELS.has(channel)


# =========================================================
# Auction internals
# =========================================================
func _poll_auction_connection() -> void:
	if _auction_socket == null:
		if _auction_should_run and not _auction_reconnect_scheduled:
			_connect_auction_socket()
		return

	_auction_socket.poll()
	var state: int = _auction_socket.get_ready_state()

	match state:
		WebSocketPeer.STATE_OPEN:
			if not _auction_connected:
				_auction_reconnect_attempts = 0
				_auction_reconnect_scheduled = false
				_set_auction_connected(true)

			_process_auction_packets()

		WebSocketPeer.STATE_CLOSED:
			_handle_auction_closed()

		_:
			pass


func _connect_auction_socket() -> void:
	if not _auction_should_run:
		return

	var token: String = _get_auth_token()
	if token.is_empty():
		return

	var url: String = _build_ws_url(AUCTION_WS_PATH, token)

	var socket: WebSocketPeer = WebSocketPeer.new()
	var err: int = socket.connect_to_url(url)
	if err != OK:
		_auction_socket = null
		_schedule_auction_reconnect()
		return

	_auction_socket = socket
	_auction_reconnect_scheduled = false


func _handle_auction_closed() -> void:
	if _auction_connected:
		_set_auction_connected(false)

	if _auction_socket != null:
		_auction_socket.close()
		_auction_socket = null

	if _auction_should_run:
		_schedule_auction_reconnect()


func _process_auction_packets() -> void:
	if _auction_socket == null:
		return

	while _auction_socket.get_available_packet_count() > 0:
		var raw_packet: PackedByteArray = _auction_socket.get_packet()
		var text: String = raw_packet.get_string_from_utf8()

		if text.is_empty():
			continue

		_dispatch_auction_packet(text)


func _dispatch_auction_packet(raw_packet: String) -> void:
	var parsed: Variant = _parse_json_packet(raw_packet)
	if typeof(parsed) != TYPE_DICTIONARY:
		return

	var packet: Dictionary = parsed
	var event_name: String = str(packet.get("event", packet.get("type", ""))).strip_edges().to_lower()

	var payload: Dictionary = {}
	if packet.get("data", null) is Dictionary:
		payload = packet["data"].duplicate(true)
	else:
		payload = packet.duplicate(true)

	payload["event"] = event_name

	match event_name:
		"bid_update":
			auction_bid_update.emit(payload)
		"lot_closed":
			auction_lot_closed.emit(payload)
		"lot_created":
			auction_lot_created.emit(payload)
		_:
			pass


func _schedule_auction_reconnect() -> void:
	if not _auction_should_run:
		return

	if _auction_reconnect_scheduled:
		return

	_auction_reconnect_scheduled = true

	var delay: float = minf(
		RECONNECT_MAX_DELAY,
		AUCTION_RECONNECT_BASE_DELAY * pow(2.0, float(_auction_reconnect_attempts))
	)

	_auction_reconnect_attempts += 1

	var timer: SceneTreeTimer = get_tree().create_timer(delay)
	timer.timeout.connect(_on_auction_reconnect_timeout)


func _on_auction_reconnect_timeout() -> void:
	_auction_reconnect_scheduled = false

	if not _auction_should_run:
		return

	if _auction_socket != null:
		return

	_connect_auction_socket()


func _set_auction_connected(connected: bool) -> void:
	var old_value: bool = _auction_connected
	_auction_connected = connected

	if old_value != connected:
		auction_socket_state_changed.emit(connected)


# =========================================================
# Shared helpers
# =========================================================
func _get_auth_token() -> String:
	if AppState == null:
		return ""

	if "access_token" in AppState and not String(AppState.access_token).is_empty():
		return String(AppState.access_token)

	if "token" in AppState and not String(AppState.token).is_empty():
		return String(AppState.token)

	return ""


func _build_ws_url(path: String, token: String) -> String:
	var normalized_path: String = path
	if not normalized_path.begins_with("/"):
		normalized_path = "/" + normalized_path

	var base_url: String = ServerConfig.get_instance().get_ws_base_url()
	return "%s%s?token=%s" % [base_url, normalized_path, token.uri_encode()]


func _parse_json_packet(raw: String) -> Variant:
	if raw.is_empty():
		return null

	return JSON.parse_string(raw)
