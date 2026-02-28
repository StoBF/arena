extends Control

@onready var general_log    = $TabContainer/General/GeneralLog
@onready var trade_log      = $TabContainer/Trade/TradeLog
@onready var system_log     = $TabContainer/System/SystemLog
@onready var private_log    = $TabContainer/Private/PrivateLog
@onready var message_input  = $BottomBar/MessageInput
@onready var send_button    = $BottomBar/SendButton
@onready var tab_container  = $TabContainer

# JWT токен для автентифікації
var token: String = ""
# Канали чату
const CHANNELS = ["general", "trade", "system", "private"]
# WebSocket-клієнти (WebSocketPeer для Godot 4)
var ws_clients: Dictionary = {}

# Оптимізація: кеш для повідомлень під час переподключення
var message_cache: Dictionary = {}
# Максимальна кількість повідомлень у кеші
const MAX_CACHE_SIZE = 50
# Максимальна кількість рядків у RichTextLabel (для продуктивності)
const MAX_LOG_LINES = 1000

# Змінна для відстеження стану підключення
var ws_connected_states: Dictionary = {}
# Лічильники спроб переподключення (для експоненційного backoff)
var reconnect_attempts: Dictionary = {}
# Максимальна затримка переподключення (секунди)
const MAX_RECONNECT_DELAY = 30.0

func _ready():
	token = AppState.token
	AppState.chat_message_received.connect(Callable(self, "_on_appstate_chat_message"))
	AppState.chat_connection_changed.connect(Callable(self, "_on_appstate_chat_connection_changed"))
	
	# Ініціалізація кешів
	for channel in CHANNELS:
		message_cache[channel] = []
		reconnect_attempts[channel] = 0

	for channel in CHANNELS:
		_init_ws(channel)

	if send_button:
		send_button.pressed.connect(_on_send_button_pressed)
	_connect_log_signals()
	set_process(true)

func _process(delta: float) -> void:
	for channel in ws_clients:
		var ws = ws_clients[channel]
		if ws:
			ws.poll()
			
			# Перевірка стану підключення
			var state = ws.get_ready_state()
			var was_connected = ws_connected_states.get(channel, false)
			
			if state == WebSocketPeer.STATE_OPEN:
				if not was_connected:
					# Тільки що підключилися
					ws_connected_states[channel] = true
					_on_ws_connected(channel)
				
				# Обробка вхідних повідомлень
				while ws.get_available_packet_count() > 0:
					var packet = ws.get_packet()
					var message = packet.get_string_from_utf8()
					_on_ws_text_received(message, channel)
			elif state == WebSocketPeer.STATE_CLOSED:
				if was_connected:
					# Тільки що відключилися
					ws_connected_states[channel] = false
					_on_ws_closed(channel)
					# Спробувати переподключитися через деякий час
					call_deferred("_reconnect_ws", channel)

func _init_ws(channel: String) -> void:
	var ws = WebSocketPeer.new()
	var config = ServerConfig.get_instance()
	var url = config.get_ws_endpoint(channel, token)
	
	# Підключення до WebSocket сервера
	var err = ws.connect_to_url(url)
	if err != OK:
		print("[Помилка] Не вдалося підключитись до %s (%s)" % [channel, err])
		return
	
	ws_clients[channel] = ws
	ws_connected_states[channel] = false
	# Підключення відбудеться асинхронно, стан перевіряється в _process()

func _reconnect_ws(channel: String) -> void:
	# Експоненційний backoff для переподключення
	var attempt = reconnect_attempts.get(channel, 0)
	var delay = min(pow(2, attempt), MAX_RECONNECT_DELAY)
	reconnect_attempts[channel] = attempt + 1
	
	print("[ChatBox] Переподключення до %s через %.1f секунд (спроба %d)" % [channel, delay, attempt + 1])
	
	var timer = get_tree().create_timer(delay)
	timer.timeout.connect(func():
		_init_ws(channel)
	)

func _on_ws_connected(channel: String) -> void:
	AppState.set_chat_connection_state(channel, true)
	
	# Скидаємо лічильник спроб при успішному підключенні
	reconnect_attempts[channel] = 0
	
	# Відновлюємо кешовані повідомлення
	_flush_message_cache(channel)

func _on_ws_text_received(message: String, channel: String) -> void:
	var formatted_message = ""
	var data = JSON.parse_string(message)
	if typeof(data) == TYPE_DICTIONARY:
		var user = str(data.get("user", "???"))
		var text = str(data.get("text", ""))
		var lot_id = int(data.get("lot_id", -1))
		if lot_id > 0:
			formatted_message = "[%s] %s [url=auction://lot/%d]Lot %d[/url]" % [user, text, lot_id, lot_id]
		else:
			formatted_message = "[%s] %s" % [user, text]
	else:
		# Якщо повідомлення не JSON, виводимо як є
		formatted_message = message
	
	# Додаємо через AppState
	AppState.push_chat_message(channel, formatted_message)
	
	# Якщо не підключені, кешуємо повідомлення
	if not ws_connected_states.get(channel, false):
		_cache_message(channel, formatted_message)

func _add_to_log(log: RichTextLabel, message: String) -> void:
	if message.find("[url=") != -1:
		log.append_bbcode(message + "\n")
	else:
		log.append_text(message + "\n")
	
	# Оптимізація: обмежуємо кількість рядків для продуктивності
	var lines = log.get_parsed_text().split("\n")
	if lines.size() > MAX_LOG_LINES:
		# Видаляємо старі рядки
		var new_text = "\n".join(lines.slice(-MAX_LOG_LINES))
		log.text = new_text

func _cache_message(channel: String, message: String) -> void:
	if not message_cache.has(channel):
		message_cache[channel] = []
	
	message_cache[channel].append(message)
	
	# Обмежуємо розмір кешу
	if message_cache[channel].size() > MAX_CACHE_SIZE:
		message_cache[channel].pop_front()

func _flush_message_cache(channel: String) -> void:
	if not message_cache.has(channel):
		return
	
	var cached = message_cache[channel]
	if cached.is_empty():
		return

	AppState.push_chat_message(channel, "[Система] Відновлено %d повідомлень" % cached.size())
	for msg in cached:
		AppState.push_chat_message(channel, msg)
	
	message_cache[channel].clear()

func _on_ws_closed(channel: String) -> void:
	AppState.set_chat_connection_state(channel, false)

func _on_send_button_pressed() -> void:
	if not message_input:
		return
		
	var text = message_input.text.strip_edges()
	if text == "":
		return

	if not tab_container:
		return
		
	var idx = tab_container.current_tab
	if idx < 0 or idx >= CHANNELS.size():
		return
		
	var channel = CHANNELS[idx]
	var ws = ws_clients.get(channel)
	
	if ws and ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		var error = ws.send_text(text)
		if error != OK:
			UIUtils.show_error("Не вдалося надіслати повідомлення: %s" % error)
		else:
			# Показуємо своє повідомлення одразу
			AppState.push_chat_message(channel, "[Ви] %s" % text)
	else:
		UIUtils.show_error("Не підключено до каналу %s" % channel)
		# Кешуємо повідомлення для відправки після переподключення
		var queued = "[Ви] %s (очікує відправки)" % text
		_cache_message(channel, queued)
		AppState.push_chat_message(channel, queued)

	message_input.clear()

func _get_log(channel: String) -> RichTextLabel:
	match channel:
		"general": return general_log
		"trade":   return trade_log
		"system":  return system_log
		"private": return private_log
	return general_log

# Метод для додавання повідомлення до чату (викликається з MainMenuScreen)
func AddLog(channel: String, message: String) -> void:
	AppState.push_chat_message(channel, message)

func _on_appstate_chat_message(channel: String, message: String) -> void:
	var log = _get_log(channel)
	if log:
		_add_to_log(log, message)

func _on_appstate_chat_connection_changed(channel: String, connected: bool) -> void:
	if connected:
		AppState.push_chat_message(channel, "[Система] Підключено до каналу %s" % channel)
	else:
		AppState.push_chat_message(channel, "[Система] Відключено від каналу %s" % channel)

func _connect_log_signals() -> void:
	var logs = [general_log, trade_log, system_log, private_log]
	for chat_log in logs:
		if chat_log:
			chat_log.bbcode_enabled = true
			chat_log.meta_clicked.connect(Callable(self, "_on_chat_meta_clicked"))

func _on_chat_meta_clicked(meta) -> void:
	var link = str(meta)
	if not link.begins_with("auction://lot/"):
		return
	var parts = link.split("/")
	if parts.size() < 4:
		return
	var lot_id = int(parts[3])
	if lot_id > 0:
		AppState.request_open_auction_lot(lot_id)

# Очищення ресурсів при виході
func _exit_tree() -> void:
	for channel in ws_clients:
		var ws = ws_clients[channel]
		if ws:
			ws.close()
	ws_clients.clear()
	message_cache.clear()
