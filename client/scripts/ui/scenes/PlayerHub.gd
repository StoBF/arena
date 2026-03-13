extends Control

const HERO_CARD_SCRIPT := preload("res://scripts/ui/components/hero_card/HeroCard.gd")
const CHAT_MESSAGE_SCRIPT := preload("res://scripts/ui/components/chat_message/ChatMessage.gd")
const CHAT_CHANNELS: PackedStringArray = ["global", "trade"]
const CHAT_SOCKET_PATH_BY_UI_CHANNEL := {
	"global": "general",
	"trade": "trade",
}
const CHAT_API_CHANNEL_BY_UI_CHANNEL := {
	"global": "global",
	"trade": "trade",
}

@onready var hero_slots_container: HBoxContainer = $Margin/VBox/TopRow/HeroBarPanel/HeroBarMargin/HeroBarScroll/HeroSlots
@onready var currency_label: Label = $Margin/VBox/TopRow/CurrencyPanel/CurrencyMargin/CurrencyLabel
@onready var title_label: Label = $Margin/VBox/CenterRow/MainContentPanel/MainContentMargin/MainContentVBox/MainContentTitle
@onready var details_title_label: Label = $Margin/VBox/CenterRow/HeroDetailsPanel/DetailsMargin/DetailsVBox/DetailsTitle
@onready var attributes_title_label: Label = $Margin/VBox/CenterRow/HeroDetailsPanel/DetailsMargin/DetailsVBox/AttributesTitle
@onready var chat_panel: PanelContainer = $ChatPanel
@onready var hero_name_label: Label = $Margin/VBox/CenterRow/HeroDetailsPanel/DetailsMargin/DetailsVBox/HeroName
@onready var hero_generation_label: Label = $Margin/VBox/CenterRow/HeroDetailsPanel/DetailsMargin/DetailsVBox/HeroGeneration
@onready var hero_level_label: Label = $Margin/VBox/CenterRow/HeroDetailsPanel/DetailsMargin/DetailsVBox/HeroLevel
@onready var hero_wins_label: Label = $Margin/VBox/CenterRow/HeroDetailsPanel/DetailsMargin/DetailsVBox/HeroWins
@onready var hero_losses_label: Label = $Margin/VBox/CenterRow/HeroDetailsPanel/DetailsMargin/DetailsVBox/HeroLosses
@onready var hero_attributes_label: RichTextLabel = $Margin/VBox/CenterRow/HeroDetailsPanel/DetailsMargin/DetailsVBox/HeroAttributes
@onready var chat_tabs: TabContainer = $ChatPanel/VBox/Tabs
@onready var messages_scroll: ScrollContainer = $ChatPanel/VBox/Messages
@onready var message_list: VBoxContainer = $ChatPanel/VBox/Messages/MessageList
@onready var message_input: LineEdit = $ChatPanel/VBox/InputBar/MessageInput
@onready var send_button: Button = $ChatPanel/VBox/InputBar/SendButton

var _player_data: Node = null
var _heroes: Array = []
var _selected_hero_index: int = -1
var _hero_card_pool: Array = []
var _hero_empty_label: Label = null
var _chat_message_pool: Array = []
var _chat_ws: Dictionary = {}
var _chat_ws_connected: Dictionary = {}
var _chat_ws_reconnect_timers: Dictionary = {}

func _ready() -> void:
	$Margin/VBox/CenterRow/MainContentPanel/MainContentMargin/MainContentVBox/Buttons/StorageButton.pressed.connect(func(): EventBus.emit_scene_changed("Storage"))
	$Margin/VBox/CenterRow/MainContentPanel/MainContentMargin/MainContentVBox/Buttons/AuctionButton.pressed.connect(func(): EventBus.emit_scene_changed("Auction"))
	$Margin/VBox/CenterRow/MainContentPanel/MainContentMargin/MainContentVBox/Buttons/BattleButton.pressed.connect(func(): EventBus.emit_scene_changed("BattleRoom"))
	$Margin/VBox/CenterRow/MainContentPanel/MainContentMargin/MainContentVBox/Buttons/SettingsButton.pressed.connect(func(): EventBus.emit_scene_changed("Settings"))
	$Margin/VBox/CenterRow/MainContentPanel/MainContentMargin/MainContentVBox/Buttons/HeroCreationButton.pressed.connect(func(): EventBus.emit_scene_changed("HeroCreation"))

	_setup_chat_ui()
	_apply_translations()
	_update_server_status_ui()
	_render_currency(AppState.balance)
	if has_node("/root/EventBus"):
		if EventBus.user_data_updated.is_connected(_on_user_data_updated) == false:
			EventBus.user_data_updated.connect(_on_user_data_updated)
		if EventBus.heroes_updated.is_connected(_on_eventbus_heroes_updated) == false:
			EventBus.heroes_updated.connect(_on_eventbus_heroes_updated)
		if EventBus.chat_message_received.is_connected(_on_eventbus_chat_message_received) == false:
			EventBus.chat_message_received.connect(_on_eventbus_chat_message_received)
		if EventBus.chat_updated.is_connected(_on_eventbus_chat_updated) == false:
			EventBus.chat_updated.connect(_on_eventbus_chat_updated)
		if EventBus.hero_selected.is_connected(_on_hero_selected_signal) == false:
			EventBus.hero_selected.connect(_on_hero_selected_signal)
		if EventBus.server_status_updated.is_connected(_on_eventbus_server_status_updated) == false:
			EventBus.server_status_updated.connect(_on_eventbus_server_status_updated)
	if LocalizationManager.locale_changed.is_connected(_on_locale_changed) == false:
		LocalizationManager.locale_changed.connect(_on_locale_changed)
	set_process(true)

func bind_controllers(player_data: Node, _inventory_controller: Node, _craft_controller: Node) -> void:
	_player_data = player_data
	if _player_data != null:
		if _player_data.heroes_changed.is_connected(_on_local_heroes_changed) == false:
			_player_data.heroes_changed.connect(_on_local_heroes_changed)
		if _player_data.hero_selected.is_connected(_on_local_hero_selected) == false:
			_player_data.hero_selected.connect(_on_local_hero_selected)

	_refresh_hub_data()

func _refresh_hub_data() -> void:
	_load_profile_from_api()
	_load_heroes_from_api()

func _load_profile_from_api() -> void:
	var response: Dictionary = await ApiClient.get_user()
	if bool(response.get("ok", false)) == false:
		_render_currency(AppState.balance)
		return

	var parsed: Variant = response.get("data", {})
	var profile: Dictionary = _extract_profile(parsed)
	if profile.is_empty():
		_render_currency(AppState.balance)
		return

	AppState.set_user_data(profile)
	_render_currency(float(profile.get("balance", AppState.balance)))

func _extract_profile(parsed: Variant) -> Dictionary:
	if parsed is Dictionary:
		var data := parsed as Dictionary
		if data.has("result") and data["result"] is Dictionary:
			return (data["result"] as Dictionary).duplicate(true)
		return data.duplicate(true)
	return {}

func _load_heroes_from_api() -> void:
	var response: Dictionary = await ApiClient.get_heroes()
	if bool(response.get("ok", false)):
		var parsed: Variant = response.get("data", {})
		var extracted: Array = _extract_heroes(parsed)
		AppState.set_heroes_data(extracted)
		if extracted.is_empty() == false:
			return

	_on_eventbus_heroes_updated()
	if _heroes.is_empty() == false:
		return

	_apply_local_heroes_fallback()

func _on_appstate_heroes_updated(heroes: Array) -> void:
	_heroes.clear()
	for hero_variant in heroes:
		if hero_variant is Dictionary:
			_heroes.append((hero_variant as Dictionary).duplicate(true))

	if _heroes.is_empty():
		_selected_hero_index = -1
		_render_hero_bar()
		_render_empty_details()
		return

	if _selected_hero_index < 0 or _selected_hero_index >= _heroes.size():
		_selected_hero_index = 0
	_render_hero_bar()
	_render_hero_details(_heroes[_selected_hero_index] as Dictionary)

func _on_eventbus_heroes_updated() -> void:
	_on_appstate_heroes_updated(AppState.heroes)

func _extract_heroes(parsed: Variant) -> Array:
	var output: Array = []
	if parsed is Array:
		for item in parsed:
			if item is Dictionary:
				output.append((item as Dictionary).duplicate(true))
		return output
	if parsed is Dictionary:
		var data := parsed as Dictionary
		if data.has("result") and data["result"] is Array:
			for item in (data["result"] as Array):
				if item is Dictionary:
					output.append((item as Dictionary).duplicate(true))
			return output
		if data.has("items") and data["items"] is Array:
			for item in (data["items"] as Array):
				if item is Dictionary:
					output.append((item as Dictionary).duplicate(true))
			return output
	return output

func _apply_local_heroes_fallback() -> void:
	if _player_data == null:
		_heroes = []
		_selected_hero_index = -1
		_render_hero_bar()
		_render_empty_details()
		return

	var local_heroes: Array = _player_data.get_heroes()
	_heroes.clear()
	for hero_variant in local_heroes:
		if hero_variant is Dictionary:
			_heroes.append((hero_variant as Dictionary).duplicate(true))

	if _heroes.is_empty():
		_selected_hero_index = -1
		_render_hero_bar()
		_render_empty_details()
		return

	if _selected_hero_index < 0 or _selected_hero_index >= _heroes.size():
		_selected_hero_index = 0
	_render_hero_bar()
	_render_hero_details(_heroes[_selected_hero_index] as Dictionary)

func _render_hero_bar() -> void:
	if _heroes.is_empty():
		_set_hero_empty_visible(true)
		for card in _hero_card_pool:
			if card is Control:
				(card as Control).visible = false
		return

	_set_hero_empty_visible(false)
	for i: int in range(_heroes.size()):
		var hero := _heroes[i] as Dictionary
		var card = _ensure_hero_card(i)
		card.visible = true
		card.set_hero_data(hero, i == _selected_hero_index)

	for i: int in range(_heroes.size(), _hero_card_pool.size()):
		if _hero_card_pool[i] is Control:
			(_hero_card_pool[i] as Control).visible = false

func _on_hero_card_selected(hero_id: int) -> void:
	if has_node("/root/EventBus"):
		EventBus.emit_hero_selected(hero_id)

func _on_hero_icon_pressed(index: int) -> void:
	if index < 0 or index >= _heroes.size():
		return
	if index == _selected_hero_index:
		return
	_selected_hero_index = index
	_render_hero_bar()
	var hero := _heroes[index] as Dictionary
	_render_hero_details(hero)
	_sync_selected_hero_to_state(hero)

func _on_hero_selected_signal(hero_id: int) -> void:
	for i: int in range(_heroes.size()):
		var hero := _heroes[i] as Dictionary
		if int(hero.get("id", -1)) != hero_id:
			continue
		if i == _selected_hero_index:
			return
		_selected_hero_index = i
		_render_hero_bar()
		_render_hero_details(hero)
		_sync_selected_hero_to_state(hero)
		return

func _sync_selected_hero_to_state(hero: Dictionary) -> void:
	var hero_id_variant: Variant = hero.get("id", -1)
	if typeof(hero_id_variant) == TYPE_INT:
		HeroManager.set_active_hero_id(int(hero_id_variant))

func _render_hero_details(hero: Dictionary) -> void:
	if hero.is_empty():
		_render_empty_details()
		return

	hero_name_label.text = tr("ui.playerhub.name") % str(hero.get("name", "-"))
	hero_generation_label.text = tr("ui.playerhub.generation") % str(hero.get("generation", hero.get("gen", "-")))
	hero_level_label.text = tr("ui.playerhub.level") % str(hero.get("level", "-"))
	hero_wins_label.text = tr("ui.playerhub.wins") % str(hero.get("wins", hero.get("victories", "-")))
	hero_losses_label.text = tr("ui.playerhub.losses") % str(hero.get("losses", hero.get("defeats", "-")))
	hero_attributes_label.text = _format_attributes(hero)

func _render_empty_details() -> void:
	hero_name_label.text = tr("ui.playerhub.name") % "-"
	hero_generation_label.text = tr("ui.playerhub.generation") % "-"
	hero_level_label.text = tr("ui.playerhub.level") % "-"
	hero_wins_label.text = tr("ui.playerhub.wins") % "-"
	hero_losses_label.text = tr("ui.playerhub.losses") % "-"
	hero_attributes_label.text = "-"

func _format_attributes(hero: Dictionary) -> String:
	var attributes: Dictionary = {}
	if hero.has("attributes") and hero["attributes"] is Dictionary:
		attributes = (hero["attributes"] as Dictionary).duplicate(true)
	else:
		var inferred_keys: Array[String] = ["strength", "agility", "intelligence", "vitality", "luck", "speed"]
		for key in inferred_keys:
			if hero.has(key):
				attributes[key] = hero[key]

	if attributes.is_empty():
		return "-"

	var lines: PackedStringArray = []
	for key in attributes.keys():
		lines.append("%s: %s" % [str(key).capitalize(), str(attributes[key])])
	return "\n".join(lines)

func _render_currency(amount: float) -> void:
	currency_label.text = tr("ui.playerhub.currency") % amount

func _setup_chat_ui() -> void:
	chat_tabs.set_tab_title(0, tr("ui.playerhub.chat_global"))
	chat_tabs.set_tab_title(1, tr("ui.playerhub.chat_trade"))
	chat_tabs.current_tab = 0
	send_button.pressed.connect(_on_chat_send_pressed)
	message_input.text_submitted.connect(func(_v: String): _on_chat_send_pressed())
	chat_tabs.tab_changed.connect(_on_chat_tab_changed)
	_load_existing_chat_messages()
	for channel in CHAT_CHANNELS:
		_load_chat_history_from_api(channel)
	_connect_chat_sockets()

func _process(_delta: float) -> void:
	for channel in CHAT_CHANNELS:
		_poll_chat_socket(channel)

func _load_existing_chat_messages() -> void:
	_refresh_message_list()

func _on_chat_tab_changed(index: int) -> void:
	chat_tabs.current_tab = index
	_load_chat_history_from_api(_current_chat_channel())
	_refresh_message_list()

func _on_chat_send_pressed() -> void:
	var text: String = message_input.text.strip_edges()
	if text.is_empty():
		return

	var channel: String = _current_chat_channel()
	if _send_ws_message(channel, text):
		pass
	else:
		var sent: Dictionary = await ApiClient.send_chat_message(channel, text)
		if bool(sent.get("ok", false)):
			var username := AppState.username if AppState.username.is_empty() == false else tr("ui.playerhub.you")
			var payload := "[%s] %s" % [username, text]
			AppState.push_chat_message(channel, payload)
		else:
			AppState.push_chat_message(channel, "[System] %s" % tr("ui.playerhub.chat_unavailable"))
	message_input.clear()

func _append_chat_line(channel: String, message: String) -> void:
	if channel != _current_chat_channel():
		return
	_refresh_message_list()
	_scroll_chat_to_bottom()

func _on_chat_message_received(channel: String, message: String) -> void:
	if channel != "trade" and channel != "global":
		return
	_append_chat_line(channel, message)

func _on_eventbus_chat_message_received() -> void:
	_on_chat_message_received(EventBus.last_chat_channel, EventBus.last_chat_message)

func _on_chat_updated(channel: String, _messages: Array) -> void:
	if channel != _current_chat_channel():
		return
	_refresh_message_list()

func _on_eventbus_chat_updated() -> void:
	_on_chat_updated(EventBus.last_chat_channel, EventBus.last_chat_messages)

func _on_local_heroes_changed(_new_heroes: Array) -> void:
	if _heroes.is_empty():
		_apply_local_heroes_fallback()

func _on_local_hero_selected(hero: Dictionary) -> void:
	if _heroes.is_empty() == false:
		return
	_render_hero_details(hero)

func _on_user_data_updated() -> void:
	_render_currency(AppState.balance)

func _connect_chat_sockets() -> void:
	for channel in CHAT_CHANNELS:
		_open_chat_socket(channel)

func _open_chat_socket(channel: String) -> void:
	if _chat_ws.has(channel):
		var existing: Variant = _chat_ws[channel]
		if existing is WebSocketPeer:
			var current := existing as WebSocketPeer
			if current.get_ready_state() != WebSocketPeer.STATE_CLOSED:
				return

	var token: String = AppState.access_token
	if token.is_empty():
		token = AppState.token
	if token.is_empty():
		AppState.push_chat_message(channel, tr("ui.playerhub.chat_unavailable"))
		return

	var ws := WebSocketPeer.new()
	var socket_channel: String = str(CHAT_SOCKET_PATH_BY_UI_CHANNEL.get(channel, channel))
	var ws_url: String = ServerConfig.get_instance().get_ws_endpoint(socket_channel, token)
	var err: int = ws.connect_to_url(ws_url)
	if err != OK:
		AppState.push_chat_message(channel, tr("ui.playerhub.chat_connect_failed") % str(err))
		_schedule_chat_reconnect(channel)
		return

	_chat_ws[channel] = ws
	_chat_ws_connected[channel] = false

func _poll_chat_socket(channel: String) -> void:
	if _chat_ws.has(channel) == false:
		return
	var peer_variant: Variant = _chat_ws[channel]
	if peer_variant is WebSocketPeer == false:
		return
	var ws := peer_variant as WebSocketPeer
	ws.poll()
	var state: int = ws.get_ready_state()

	if state == WebSocketPeer.STATE_OPEN:
		if bool(_chat_ws_connected.get(channel, false)) == false:
			_chat_ws_connected[channel] = true
			AppState.push_chat_message(channel, "[System] %s" % tr("ui.playerhub.chat_connected"))
		while ws.get_available_packet_count() > 0:
			var packet_text: String = ws.get_packet().get_string_from_utf8()
			var rendered: String = _parse_chat_packet(packet_text)
			AppState.push_chat_message(channel, rendered)
	elif state == WebSocketPeer.STATE_CLOSED:
		if bool(_chat_ws_connected.get(channel, false)):
			AppState.push_chat_message(channel, "[System] %s" % tr("ui.playerhub.chat_disconnected"))
		_chat_ws_connected[channel] = false
		_chat_ws.erase(channel)
		_schedule_chat_reconnect(channel)

func _on_locale_changed(_locale_code: String) -> void:
	_apply_translations()
	_render_currency(AppState.balance)
	_update_server_status_ui()
	if _selected_hero_index >= 0 and _selected_hero_index < _heroes.size():
		_render_hero_details(_heroes[_selected_hero_index] as Dictionary)
	else:
		_render_empty_details()
	_render_hero_bar()

func _on_eventbus_server_status_updated() -> void:
	_update_server_status_ui()

func _apply_translations() -> void:
	title_label.text = tr("ui.playerhub.title")
	$Margin/VBox/CenterRow/MainContentPanel/MainContentMargin/MainContentVBox/Buttons/StorageButton.text = tr("ui.playerhub.storage")
	$Margin/VBox/CenterRow/MainContentPanel/MainContentMargin/MainContentVBox/Buttons/AuctionButton.text = tr("ui.playerhub.auction")
	$Margin/VBox/CenterRow/MainContentPanel/MainContentMargin/MainContentVBox/Buttons/BattleButton.text = tr("ui.playerhub.battle")
	$Margin/VBox/CenterRow/MainContentPanel/MainContentMargin/MainContentVBox/Buttons/SettingsButton.text = tr("ui.playerhub.settings")
	$Margin/VBox/CenterRow/MainContentPanel/MainContentMargin/MainContentVBox/Buttons/HeroCreationButton.text = tr("ui.playerhub.hero_creation")
	message_input.placeholder_text = tr("ui.playerhub.chat_placeholder")
	send_button.text = tr("ui.playerhub.send")
	chat_tabs.set_tab_title(0, tr("ui.playerhub.chat_global"))
	chat_tabs.set_tab_title(1, tr("ui.playerhub.chat_trade"))
	details_title_label.text = tr("ui.playerhub.hero_details")
	attributes_title_label.text = tr("ui.playerhub.attributes")
	_update_server_status_ui()
	_refresh_message_list()

func _update_server_status_ui() -> void:
	var status_text: String = AppState.server_status.to_upper()
	title_label.text = "%s (%s: %d)" % [
		tr("ui.playerhub.title"),
		status_text,
		AppState.online_players,
	]

func _send_ws_message(channel: String, text: String) -> bool:
	if _chat_ws.has(channel) == false:
		return false
	var peer_variant: Variant = _chat_ws[channel]
	if peer_variant is WebSocketPeer == false:
		return false
	var ws := peer_variant as WebSocketPeer
	if ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return false
	var err: int = ws.send_text(text)
	return err == OK

func _parse_chat_packet(packet_text: String) -> String:
	var parsed: Variant = JSON.parse_string(packet_text)
	if parsed is Dictionary:
		var data := parsed as Dictionary
		var user: String = str(data.get("user", data.get("username", "Server")))
		var text: String = str(data.get("text", data.get("message", "")))
		if text.is_empty():
			text = packet_text
		return "[%s] %s" % [user, text]
	if parsed is String:
		return parsed as String
	return packet_text

func _load_chat_history_from_api(channel: String) -> void:
	var api_channel: String = str(CHAT_API_CHANNEL_BY_UI_CHANNEL.get(channel, channel))
	await ApiClient.get_chat_messages(api_channel, 200, 0)

func _schedule_chat_reconnect(channel: String) -> void:
	if _chat_ws_reconnect_timers.has(channel):
		return
	var timer: SceneTreeTimer = get_tree().create_timer(2.0)
	_chat_ws_reconnect_timers[channel] = timer
	timer.timeout.connect(func():
		_chat_ws_reconnect_timers.erase(channel)
		_open_chat_socket(channel)
	)

func _exit_tree() -> void:
	for value in _chat_ws.values():
		if value is WebSocketPeer:
			(value as WebSocketPeer).close()
	_chat_ws.clear()
	_chat_ws_connected.clear()
	_chat_ws_reconnect_timers.clear()
	if has_node("/root/EventBus"):
		if EventBus.user_data_updated.is_connected(_on_user_data_updated):
			EventBus.user_data_updated.disconnect(_on_user_data_updated)
		if EventBus.heroes_updated.is_connected(_on_eventbus_heroes_updated):
			EventBus.heroes_updated.disconnect(_on_eventbus_heroes_updated)
		if EventBus.chat_message_received.is_connected(_on_eventbus_chat_message_received):
			EventBus.chat_message_received.disconnect(_on_eventbus_chat_message_received)
		if EventBus.chat_updated.is_connected(_on_eventbus_chat_updated):
			EventBus.chat_updated.disconnect(_on_eventbus_chat_updated)
		if EventBus.hero_selected.is_connected(_on_hero_selected_signal):
			EventBus.hero_selected.disconnect(_on_hero_selected_signal)
		if EventBus.server_status_updated.is_connected(_on_eventbus_server_status_updated):
			EventBus.server_status_updated.disconnect(_on_eventbus_server_status_updated)

func _current_chat_channel() -> String:
	var index: int = chat_tabs.current_tab
	if index < 0 or index >= CHAT_CHANNELS.size():
		return "global"
	return CHAT_CHANNELS[index]

func _refresh_message_list() -> void:
	var channel: String = _current_chat_channel()
	var messages: Array = AppState.chat_messages.get(channel, [])
	for i: int in range(messages.size()):
		var entry: String = str(messages[i])
		var msg_node = _ensure_chat_message(i)
		msg_node.visible = true
		msg_node.set_chat_message(entry, channel)

	for i: int in range(messages.size(), _chat_message_pool.size()):
		if _chat_message_pool[i] is Control:
			(_chat_message_pool[i] as Control).visible = false

	_scroll_chat_to_bottom()

func _scroll_chat_to_bottom() -> void:
	call_deferred("_apply_scroll_to_bottom")

func _apply_scroll_to_bottom() -> void:
	messages_scroll.scroll_vertical = int(messages_scroll.get_v_scroll_bar().max_value)

func _ensure_hero_card(index: int) -> Object:
	if index < _hero_card_pool.size():
		return _hero_card_pool[index]
	var card = HERO_CARD_SCRIPT.new()
	if card.has_signal("hero_selected") and card.hero_selected.is_connected(_on_hero_card_selected) == false:
		card.hero_selected.connect(_on_hero_card_selected)
	hero_slots_container.add_child(card)
	_hero_card_pool.append(card)
	return card

func _set_hero_empty_visible(visible: bool) -> void:
	if _hero_empty_label == null:
		_hero_empty_label = Label.new()
		_hero_empty_label.text = tr("ui.playerhub.no_heroes")
		hero_slots_container.add_child(_hero_empty_label)
	_hero_empty_label.text = tr("ui.playerhub.no_heroes")
	_hero_empty_label.visible = visible

func _ensure_chat_message(index: int) -> Object:
	if index < _chat_message_pool.size():
		return _chat_message_pool[index]
	var message_node = CHAT_MESSAGE_SCRIPT.new()
	message_list.add_child(message_node)
	_chat_message_pool.append(message_node)
	return message_node

