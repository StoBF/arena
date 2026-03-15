extends Control

const MODULE_SCENES := {
	"heroes": preload("res://scenes/modules/HeroesModule.tscn"),
	"inventory": preload("res://scenes/modules/InventoryModule.tscn"),
	"auction": preload("res://scenes/modules/AuctionModule.tscn"),
	"craft": preload("res://scenes/modules/CraftModule.tscn"),
	"raid": preload("res://scenes/modules/RaidModule.tscn"),
}

@onready var username_label: Label = $RootMargin/RootVBox/TopBarPanel/TopBarMargin/TopBar/PlayerInfo/UsernameLabel
@onready var status_label: Label = $RootMargin/RootVBox/TopBarPanel/TopBarMargin/TopBar/PlayerInfo/StatusLabel
@onready var currency_bar: Node = $RootMargin/RootVBox/TopBarPanel/TopBarMargin/TopBar/CurrencyBar
@onready var notification_badge: Node = $RootMargin/RootVBox/TopBarPanel/TopBarMargin/TopBar/NotificationsButton/NotificationBadge
@onready var module_container: Control = $RootMargin/RootVBox/BodyRow/CenterArea/MainPanel/MainMargin/ModuleContainer
@onready var chat_panel: Node = $RootMargin/RootVBox/BodyRow/RightSidebarPanel/RightSidebarMargin/ChatPanel
@onready var heroes_button: Button = $RootMargin/RootVBox/BodyRow/LeftSidebarPanel/LeftMenuMargin/LeftMenu/HeroesButton
@onready var inventory_button: Button = $RootMargin/RootVBox/BodyRow/LeftSidebarPanel/LeftMenuMargin/LeftMenu/InventoryButton
@onready var auction_button: Button = $RootMargin/RootVBox/BodyRow/LeftSidebarPanel/LeftMenuMargin/LeftMenu/AuctionButton
@onready var craft_button: Button = $RootMargin/RootVBox/BodyRow/LeftSidebarPanel/LeftMenuMargin/LeftMenu/CraftButton
@onready var raid_button: Button = $RootMargin/RootVBox/BodyRow/LeftSidebarPanel/LeftMenuMargin/LeftMenu/RaidButton
@onready var settings_button: Button = $RootMargin/RootVBox/BodyRow/LeftSidebarPanel/LeftMenuMargin/LeftMenu/SettingsButton
@onready var logout_button: Button = $RootMargin/RootVBox/BodyRow/LeftSidebarPanel/LeftMenuMargin/LeftMenu/LogoutButton

var _current_module_instance: Node = null
var _player_data: Node = null
var _inventory_controller: Node = null
var _craft_controller: Node = null
var _active_chat_channel: String = "global"
var _notification_count: int = 0

func _ready() -> void:
	_connect_navigation()
	_connect_events()
	_apply_top_bar()
	_load_module("heroes")
	await _refresh_chat_histories()
	_apply_announcements()

func bind_controllers(player_data: Node, inventory_controller: Node, craft_controller: Node) -> void:
	_player_data = player_data
	_inventory_controller = inventory_controller
	_craft_controller = craft_controller
	if _current_module_instance != null and _current_module_instance.has_method("bind_controllers"):
		_current_module_instance.bind_controllers(_player_data, _inventory_controller, _craft_controller)

func _connect_navigation() -> void:
	heroes_button.pressed.connect(func() -> void: _load_module("heroes"))
	inventory_button.pressed.connect(func() -> void: _load_module("inventory"))
	auction_button.pressed.connect(func() -> void: _load_module("auction"))
	craft_button.pressed.connect(func() -> void: _load_module("craft"))
	raid_button.pressed.connect(func() -> void: _load_module("raid"))
	settings_button.pressed.connect(func() -> void: EventBus.emit_scene_changed("Settings"))
	logout_button.pressed.connect(_on_logout_pressed)
	if chat_panel.has_signal("message_submitted"):
		chat_panel.message_submitted.connect(_on_chat_message_submitted)
	if chat_panel.has_signal("channel_changed"):
		chat_panel.channel_changed.connect(_on_chat_channel_changed)

func _connect_events() -> void:
	if has_node("/root/EventBus") == false:
		return
	if EventBus.user_data_updated.is_connected(_on_user_data_updated) == false:
		EventBus.user_data_updated.connect(_on_user_data_updated)
	if EventBus.server_status_updated.is_connected(_on_server_status_updated) == false:
		EventBus.server_status_updated.connect(_on_server_status_updated)
	if EventBus.chat_updated.is_connected(_on_chat_updated) == false:
		EventBus.chat_updated.connect(_on_chat_updated)

func _apply_top_bar() -> void:
	var player_name: String = str(AppState.username)
	if player_name.is_empty():
		player_name = "-"
	username_label.text = "Player: %s" % player_name
	status_label.text = "Server: %s (%d)" % [str(AppState.server_status), int(AppState.online_players)]
	if currency_bar.has_method("set_amount"):
		currency_bar.set_amount(float(AppState.balance))
	if notification_badge.has_method("set_count"):
		notification_badge.set_count(_notification_count)

func _load_module(module_name: String) -> void:
	if MODULE_SCENES.has(module_name) == false:
		return
	if _current_module_instance != null and _current_module_instance.is_inside_tree():
		_current_module_instance.queue_free()
		_current_module_instance = null
	var scene: PackedScene = MODULE_SCENES[module_name]
	_current_module_instance = scene.instantiate()
	module_container.add_child(_current_module_instance)
	if _current_module_instance is Control:
		var module_control := _current_module_instance as Control
		module_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	if _current_module_instance.has_method("bind_controllers"):
		_current_module_instance.bind_controllers(_player_data, _inventory_controller, _craft_controller)

func _refresh_chat_histories() -> void:
	await ApiClient.get_chat_messages("global", 50, 0)
	await ApiClient.get_chat_messages("trade", 50, 0)
	_update_chat_from_state("global")
	_update_chat_from_state("trade")
	if chat_panel.has_method("set_channel_messages"):
		chat_panel.set_channel_messages("system", ["System initialized", "Welcome to Arena"])

func _apply_announcements() -> void:
	if chat_panel.has_method("set_announcements"):
		chat_panel.set_announcements([
			"Double XP weekend starts Friday",
			"Auction taxes reduced for 24h",
			"Server maintenance at 03:00 UTC"
		])

func _update_chat_from_state(channel: String) -> void:
	if chat_panel.has_method("set_channel_messages") == false:
		return
	var entries: Array = []
	if AppState.chat_messages.has(channel):
		entries = AppState.chat_messages[channel] as Array
	chat_panel.set_channel_messages(channel, entries)

func _on_chat_message_submitted(channel: String, text: String) -> void:
	var normalized_channel: String = channel.strip_edges().to_lower()
	var response: Dictionary = await ApiClient.send_chat_message(normalized_channel, text)
	if bool(response.get("ok", false)) == false:
		var sender: String = AppState.username
		if sender.is_empty():
			sender = "You"
		AppState.push_chat_message(normalized_channel, "[%s] %s" % [sender, text])
	_update_chat_from_state(normalized_channel)

func _on_chat_channel_changed(channel: String) -> void:
	_active_chat_channel = channel
	if _active_chat_channel == "global" or _active_chat_channel == "trade":
		await ApiClient.get_chat_messages(_active_chat_channel, 50, 0)
		_update_chat_from_state(_active_chat_channel)
	if _active_chat_channel == "system":
		if chat_panel.has_method("set_channel_messages"):
			chat_panel.set_channel_messages("system", ["No active alerts"])

func _on_logout_pressed() -> void:
	AuthManager.logout()
	if has_node("/root/EventBus"):
		EventBus.emit_scene_changed("LoginScene")

func _on_user_data_updated() -> void:
	_apply_top_bar()

func _on_server_status_updated() -> void:
	_apply_top_bar()
	if chat_panel.has_method("set_system_messages"):
		chat_panel.set_system_messages([
			"Server status: %s" % AppState.server_status,
			"Online players: %d" % int(AppState.online_players)
		])

func _on_chat_updated() -> void:
	var channel: String = str(EventBus.last_chat_channel)
	_update_chat_from_state(channel)
	if channel != _active_chat_channel:
		_notification_count += 1
	if notification_badge.has_method("set_count"):
		notification_badge.set_count(_notification_count)
