extends Node

signal auction_bid_update(event_data: Dictionary)
signal auction_lot_closed(event_data: Dictionary)
signal auction_lot_created(event_data: Dictionary)
signal auction_socket_state_changed(connected: bool)

const AUCTIONS_CHANNEL_PATH := "/ws/auctions"
const RECONNECT_BASE_DELAY := 1.0
const RECONNECT_MAX_DELAY := 20.0

var _auction_ws: WebSocketPeer = null
var _auction_connected: bool = false
var _auction_reconnect_attempts: int = 0
var _auction_should_run: bool = false

func _ready() -> void:
	set_process(true)

func ensure_auction_subscription() -> void:
	_auction_should_run = true
	if _auction_ws == null:
		_connect_auction_socket()

func stop_auction_subscription() -> void:
	_auction_should_run = false
	if _auction_ws != null:
		_auction_ws.close()
	_auction_ws = null
	if _auction_connected:
		_auction_connected = false
		auction_socket_state_changed.emit(false)

func _process(_delta: float) -> void:
	if _auction_ws == null:
		if _auction_should_run:
			_connect_auction_socket()
		return

	_auction_ws.poll()
	var state: int = _auction_ws.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		if not _auction_connected:
			_auction_connected = true
			_auction_reconnect_attempts = 0
			auction_socket_state_changed.emit(true)
		while _auction_ws.get_available_packet_count() > 0:
			var packet: String = _auction_ws.get_packet().get_string_from_utf8()
			_handle_auction_packet(packet)
	elif state == WebSocketPeer.STATE_CLOSED:
		_handle_auction_closed()

func _connect_auction_socket() -> void:
	var token: String = AppState.access_token if not AppState.access_token.is_empty() else AppState.token
	if token.is_empty():
		return
	var ws_url: String = "%s%s?token=%s" % [ServerConfig.get_instance().get_ws_base_url(), AUCTIONS_CHANNEL_PATH, token.uri_encode()]
	_auction_ws = WebSocketPeer.new()
	var err: int = _auction_ws.connect_to_url(ws_url)
	if err != OK:
		_auction_ws = null
		_schedule_auction_reconnect()

func _handle_auction_closed() -> void:
	if _auction_connected:
		_auction_connected = false
		auction_socket_state_changed.emit(false)
	_auction_ws = null
	if _auction_should_run:
		_schedule_auction_reconnect()

func _schedule_auction_reconnect() -> void:
	var delay: float = minf(RECONNECT_MAX_DELAY, RECONNECT_BASE_DELAY * pow(2.0, _auction_reconnect_attempts))
	_auction_reconnect_attempts += 1
	var timer: SceneTreeTimer = get_tree().create_timer(delay)
	timer.timeout.connect(func():
		if _auction_should_run and _auction_ws == null:
			_connect_auction_socket()
	)

func _handle_auction_packet(raw_packet: String) -> void:
	var parsed: Variant = JSON.parse_string(raw_packet)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var packet: Dictionary = parsed
	var event_name: String = str(packet.get("event", packet.get("type", ""))).strip_edges().to_lower()
	var payload: Dictionary = {}
	if packet.has("data") and packet["data"] is Dictionary:
		payload = (packet["data"] as Dictionary).duplicate(true)
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
