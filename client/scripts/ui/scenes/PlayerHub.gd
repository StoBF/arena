extends Control

## PlayerHub — the central headquarters dashboard.
## Hosts the sidebar navigation, module container, quick-action bar,
## chat panel, and activity feed.

# ---------------------------------------------------------------------------
# Module registry — add new modules here
# ---------------------------------------------------------------------------
const MODULE_SCENES := {
	"heroes": preload("res://scenes/ui/modules_mmo/HeroesModule.tscn"),
	"inventory": preload("res://scenes/ui/modules_mmo/InventoryModule.tscn"),
	"auction": preload("res://scenes/ui/modules_mmo/AuctionModule.tscn"),
	"craft": preload("res://scenes/ui/modules_mmo/CraftModule.tscn"),
	"healing": preload("res://scenes/ui/modules_mmo/HealingModule.tscn"),
	"arena": preload("res://scenes/ui/modules_mmo/ArenaModule.tscn"),
	"boss_raid": preload("res://scenes/ui/modules_mmo/BossRaidModule.tscn"),
	"hero_creation": preload("res://scenes/ui/modules_mmo/HeroCreationModule.tscn"),
}

const ACTIVE_BUTTON_COLOR := Color(0.85, 0.72, 0.35, 0.35)   # gold highlight
const INACTIVE_BUTTON_COLOR := Color(0, 0, 0, 0)              # transparent

# ---------------------------------------------------------------------------
# Node references – TopBar
# ---------------------------------------------------------------------------
@onready var username_label: Label      = $RootMargin/RootVBox/TopBarPanel/TopBarMargin/TopBar/PlayerInfo/UsernameLabel
@onready var status_label: Label        = $RootMargin/RootVBox/TopBarPanel/TopBarMargin/TopBar/PlayerInfo/StatusLabel
@onready var server_indicator: ColorRect = $RootMargin/RootVBox/TopBarPanel/TopBarMargin/TopBar/PlayerInfo/ServerStatusIndicator
@onready var currency_bar: Node         = $RootMargin/RootVBox/TopBarPanel/TopBarMargin/TopBar/CurrencyBar
@onready var notifications_button: Button = $RootMargin/RootVBox/TopBarPanel/TopBarMargin/TopBar/NotificationsButton
@onready var notification_badge: Node   = $RootMargin/RootVBox/TopBarPanel/TopBarMargin/TopBar/NotificationsButton/NotificationBadge

# ---------------------------------------------------------------------------
# Node references – Sidebar buttons
# ---------------------------------------------------------------------------
@onready var heroes_button: Button    = $RootMargin/RootVBox/BodyRow/LeftSidebarPanel/LeftMenuMargin/LeftMenu/HeroesButton
@onready var inventory_button: Button = $RootMargin/RootVBox/BodyRow/LeftSidebarPanel/LeftMenuMargin/LeftMenu/InventoryButton
@onready var craft_button: Button     = $RootMargin/RootVBox/BodyRow/LeftSidebarPanel/LeftMenuMargin/LeftMenu/CraftButton
@onready var auction_button: Button   = $RootMargin/RootVBox/BodyRow/LeftSidebarPanel/LeftMenuMargin/LeftMenu/AuctionButton
@onready var healing_button: Button   = $RootMargin/RootVBox/BodyRow/LeftSidebarPanel/LeftMenuMargin/LeftMenu/HealingButton
@onready var arena_button: Button     = $RootMargin/RootVBox/BodyRow/LeftSidebarPanel/LeftMenuMargin/LeftMenu/ArenaButton
@onready var boss_raid_button: Button = $RootMargin/RootVBox/BodyRow/LeftSidebarPanel/LeftMenuMargin/LeftMenu/BossRaidButton
@onready var settings_button: Button  = $RootMargin/RootVBox/BodyRow/LeftSidebarPanel/LeftMenuMargin/LeftMenu/SettingsButton
@onready var logout_button: Button    = $RootMargin/RootVBox/BodyRow/LeftSidebarPanel/LeftMenuMargin/LeftMenu/LogoutButton

# ---------------------------------------------------------------------------
# Node references – Centre + Bottom bar
# ---------------------------------------------------------------------------
@onready var module_container: Control = $RootMargin/RootVBox/BodyRow/CenterArea/MainPanel/MainMargin/ModuleContainer
@onready var action_create_hero: Button = $RootMargin/RootVBox/BodyRow/CenterArea/BottomBarPanel/BottomBarMargin/QuickActions/ActionCreateHero
@onready var action_queue_pvp: Button   = $RootMargin/RootVBox/BodyRow/CenterArea/BottomBarPanel/BottomBarMargin/QuickActions/ActionQueuePvP
@onready var action_boss_raid: Button   = $RootMargin/RootVBox/BodyRow/CenterArea/BottomBarPanel/BottomBarMargin/QuickActions/ActionBossRaid
@onready var action_market: Button      = $RootMargin/RootVBox/BodyRow/CenterArea/BottomBarPanel/BottomBarMargin/QuickActions/ActionMarket
@onready var quick_status_label: Label  = $RootMargin/RootVBox/BodyRow/CenterArea/BottomBarPanel/BottomBarMargin/QuickActions/QuickStatus

# ---------------------------------------------------------------------------
# Node references – Right sidebar
# ---------------------------------------------------------------------------
@onready var chat_panel: Node          = $RootMargin/RootVBox/BodyRow/RightSidebarPanel/RightSidebarMargin/RightSidebarVBox/ChatPanel
@onready var activity_placeholder: VBoxContainer = $RootMargin/RootVBox/BodyRow/RightSidebarPanel/RightSidebarMargin/RightSidebarVBox/ActivityFeedPlaceholder

# ---------------------------------------------------------------------------
# Internal state
# ---------------------------------------------------------------------------
var _current_module_key: String = ""
var _current_module_instance: Node = null
var _active_chat_channel: String = "global"
var _notification_count: int = 0
var _activity_feed: Node = null   # ActivityFeed component (added dynamically)

func _tx(key: String, fallback: String) -> String:
	return CabinetStyle.text(key, fallback)

## Map sidebar button → module key for highlight tracking
var _sidebar_map: Dictionary = {}

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------
func _ready() -> void:
	call_deferred("_apply_cabinet_visuals")
	_build_sidebar_map()
	_connect_top_bar()
	_create_activity_feed()
	_connect_sidebar()
	_connect_bottom_bar()
	_connect_events()
	_apply_top_bar()
	_load_module("heroes")
	await _refresh_chat_histories()
	_apply_announcements()
	_update_quick_status()

func _exit_tree() -> void:
	_disconnect_top_bar()
	_disconnect_sidebar()
	_disconnect_bottom_bar()
	_disconnect_events()

func _apply_cabinet_visuals() -> void:
	CabinetStyle.style_screen(self)
	CabinetStyle.style_status_label(status_label)
	CabinetStyle.style_status_label(quick_status_label)
	CabinetStyle.style_button(action_create_hero, 140)
	CabinetStyle.style_button(action_queue_pvp, 140)
	CabinetStyle.style_button(action_boss_raid, 140)
	CabinetStyle.style_button(action_market, 140)

# ---------------------------------------------------------------------------
# Sidebar map (button → module key) for highlighting
# ---------------------------------------------------------------------------
func _build_sidebar_map() -> void:
	_sidebar_map = {
		heroes_button: "heroes",
		inventory_button: "inventory",
		craft_button: "craft",
		auction_button: "auction",
		healing_button: "healing",
		arena_button: "arena",
		boss_raid_button: "boss_raid",
	}

# ---------------------------------------------------------------------------
# Activity feed component – inserted into the right sidebar placeholder
# ---------------------------------------------------------------------------
func _create_activity_feed() -> void:
	_activity_feed = ActivityFeed.new()
	_activity_feed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_activity_feed.size_flags_vertical = Control.SIZE_EXPAND_FILL
	activity_placeholder.add_child(_activity_feed)

# ---------------------------------------------------------------------------
# Connection helpers
# ---------------------------------------------------------------------------
func _connect_sidebar() -> void:
	for btn: Button in _sidebar_map.keys():
		var key: String = _sidebar_map[btn]
		var cb: Callable = Callable(self, "_on_sidebar_module_pressed").bind(key)
		if not btn.pressed.is_connected(cb):
			btn.pressed.connect(cb)
	if not settings_button.pressed.is_connected(_on_settings_pressed):
		settings_button.pressed.connect(_on_settings_pressed)
	if not logout_button.pressed.is_connected(_on_logout_pressed):
		logout_button.pressed.connect(_on_logout_pressed)
	# Chat signals
	   if chat_panel.has_signal("message_submitted"):
		   if not chat_panel.message_submitted.is_connected(_on_chat_message_submitted):
			   chat_panel.message_submitted.connect(_on_chat_message_submitted)
	   if chat_panel.has_signal("channel_changed"):
		   if not chat_panel.channel_changed.is_connected(_on_chat_channel_changed):
			   chat_panel.channel_changed.connect(_on_chat_channel_changed)
	   # Subscribe to default chat channel
	   WebSocketManager.ensure_chat_subscription("general")
	   WebSocketManager.chat_message_received.connect(_on_chat_message_received)

func _disconnect_sidebar() -> void:
	for btn: Button in _sidebar_map.keys():
		var key: String = _sidebar_map[btn]
		var cb: Callable = Callable(self, "_on_sidebar_module_pressed").bind(key)
		if btn.pressed.is_connected(cb):
			btn.pressed.disconnect(cb)
	if settings_button != null and settings_button.pressed.is_connected(_on_settings_pressed):
		settings_button.pressed.disconnect(_on_settings_pressed)
	if logout_button != null and logout_button.pressed.is_connected(_on_logout_pressed):
		logout_button.pressed.disconnect(_on_logout_pressed)
	   if chat_panel != null and chat_panel.has_signal("message_submitted") and chat_panel.message_submitted.is_connected(_on_chat_message_submitted):
		   chat_panel.message_submitted.disconnect(_on_chat_message_submitted)
	   if chat_panel != null and chat_panel.has_signal("channel_changed") and chat_panel.channel_changed.is_connected(_on_chat_channel_changed):
		   chat_panel.channel_changed.disconnect(_on_chat_channel_changed)
	   # Unsubscribe from all chat channels
	   for channel in ["general", "trade", "system"]:
		   WebSocketManager.stop_chat_subscription(channel)
	   if WebSocketManager.chat_message_received.is_connected(_on_chat_message_received):
		   WebSocketManager.chat_message_received.disconnect(_on_chat_message_received)

func _connect_top_bar() -> void:
	if notifications_button != null and notifications_button.pressed.is_connected(_on_notifications_pressed) == false:
		notifications_button.pressed.connect(_on_notifications_pressed)

func _disconnect_top_bar() -> void:
	if notifications_button != null and notifications_button.pressed.is_connected(_on_notifications_pressed):
		notifications_button.pressed.disconnect(_on_notifications_pressed)

func _connect_bottom_bar() -> void:
	if action_create_hero != null and not action_create_hero.pressed.is_connected(_on_action_create_hero_pressed):
		action_create_hero.pressed.connect(_on_action_create_hero_pressed)
	if action_queue_pvp != null and not action_queue_pvp.pressed.is_connected(_on_action_queue_pvp_pressed):
		action_queue_pvp.pressed.connect(_on_action_queue_pvp_pressed)
	if action_boss_raid != null and not action_boss_raid.pressed.is_connected(_on_action_boss_raid_pressed):
		action_boss_raid.pressed.connect(_on_action_boss_raid_pressed)
	if action_market != null and not action_market.pressed.is_connected(_on_action_market_pressed):
		action_market.pressed.connect(_on_action_market_pressed)

func _disconnect_bottom_bar() -> void:
	if action_create_hero != null and action_create_hero.pressed.is_connected(_on_action_create_hero_pressed):
		action_create_hero.pressed.disconnect(_on_action_create_hero_pressed)
	if action_queue_pvp != null and action_queue_pvp.pressed.is_connected(_on_action_queue_pvp_pressed):
		action_queue_pvp.pressed.disconnect(_on_action_queue_pvp_pressed)
	if action_boss_raid != null and action_boss_raid.pressed.is_connected(_on_action_boss_raid_pressed):
		action_boss_raid.pressed.disconnect(_on_action_boss_raid_pressed)
	if action_market != null and action_market.pressed.is_connected(_on_action_market_pressed):
		action_market.pressed.disconnect(_on_action_market_pressed)

func _connect_events() -> void:
	if not has_node("/root/EventBus"):
		return
	if not EventBus.user_data_updated.is_connected(_on_user_data_updated):
		EventBus.user_data_updated.connect(_on_user_data_updated)
	if not EventBus.server_status_updated.is_connected(_on_server_status_updated):
		EventBus.server_status_updated.connect(_on_server_status_updated)
	if not EventBus.chat_updated.is_connected(_on_chat_updated):
		EventBus.chat_updated.connect(_on_chat_updated)

func _disconnect_events() -> void:
	if not has_node("/root/EventBus"):
		return
	if EventBus.user_data_updated.is_connected(_on_user_data_updated):
		EventBus.user_data_updated.disconnect(_on_user_data_updated)
	if EventBus.server_status_updated.is_connected(_on_server_status_updated):
		EventBus.server_status_updated.disconnect(_on_server_status_updated)
	if EventBus.chat_updated.is_connected(_on_chat_updated):
		EventBus.chat_updated.disconnect(_on_chat_updated)

# ---------------------------------------------------------------------------
# Top bar
# ---------------------------------------------------------------------------
func _apply_top_bar() -> void:
	var player_name: String = str(AppState.username)
	if player_name.is_empty():
		player_name = "-"
	username_label.text = tr("HUB_PLAYER").replace("{name}", player_name) if TranslationServer.get_locale() != "" else "Player: %s" % player_name
	var srv_status: String = str(AppState.server_status)
	var online_count: int = int(AppState.online_players)
	status_label.text = "Server: %s (%d)" % [srv_status, online_count]
	# Color the indicator dot
	match srv_status.to_lower():
		"online":
			server_indicator.color = Color(0.2, 0.85, 0.3, 1)
		"degraded":
			server_indicator.color = Color(0.95, 0.75, 0.15, 1)
		_:
			server_indicator.color = Color(0.6, 0.6, 0.6, 1)
	if currency_bar.has_method("set_amount"):
		currency_bar.set_amount(float(AppState.balance))
	if notification_badge.has_method("set_count"):
		notification_badge.set_count(_notification_count)

# ---------------------------------------------------------------------------
# Module loading
# ---------------------------------------------------------------------------
func _load_module(module_name: String) -> void:
	if not MODULE_SCENES.has(module_name):
		UIUtils.show_warning(_tx("ui.module.not_available", "Module '%s' not available.") % module_name)
		return
	if module_name == _current_module_key and _current_module_instance != null:
		return  # already showing this module
	# Tear down previous module
	if _current_module_instance != null and _current_module_instance.is_inside_tree():
		_current_module_instance.queue_free()
		_current_module_instance = null
	_current_module_key = module_name
	# Instantiate new module
	var scene: PackedScene = MODULE_SCENES[module_name]
	_current_module_instance = scene.instantiate()
	module_container.add_child(_current_module_instance)
	if _current_module_instance is Control:
		(_current_module_instance as Control).set_anchors_preset(Control.PRESET_FULL_RECT)
	# Update sidebar highlight
	_highlight_sidebar_button(module_name)
	# Log to activity feed
	if _activity_feed != null and _activity_feed.has_method("add_entry"):
		_activity_feed.add_entry(_tx("ui.module.opened", "Opened %s") % module_name, "system")

# ---------------------------------------------------------------------------
# Sidebar active-state highlighting
# ---------------------------------------------------------------------------
func _highlight_sidebar_button(active_key: String) -> void:
	for btn: Button in _sidebar_map.keys():
		var key: String = _sidebar_map[btn]
		if key == active_key:
			btn.add_theme_color_override("font_color", Color(0.95, 0.85, 0.45))
			btn.add_theme_stylebox_override("normal", _make_highlight_stylebox())
		else:
			btn.remove_theme_color_override("font_color")
			btn.remove_theme_stylebox_override("normal")

func _make_highlight_stylebox() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = ACTIVE_BUTTON_COLOR
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb

# ---------------------------------------------------------------------------
# Quick status (bottom bar right label)
# ---------------------------------------------------------------------------
func _update_quick_status() -> void:
	# Show a brief roster summary
	# H16: HeroManager has no public `heroes` property — use get_heroes() instead
	var hero_count: int = HeroManager.get_heroes().size()
	quick_status_label.text = _tx("ui.playerhub.quick_heroes", "Heroes: %d") % hero_count

# ---------------------------------------------------------------------------
# Chat helpers
# ---------------------------------------------------------------------------
func _refresh_chat_histories() -> void:
	await ApiClient.get_chat_messages("global", 50, 0)
	await ApiClient.get_chat_messages("trade", 50, 0)
	_update_chat_from_state("global")
	_update_chat_from_state("trade")
	if chat_panel.has_method("set_channel_messages"):
		chat_panel.set_channel_messages("system", [
			_tx("ui.playerhub.system_initialized", "System initialized"),
			_tx("ui.playerhub.welcome", "Welcome to Arena"),
		])

func _apply_announcements() -> void:
	if chat_panel.has_method("set_announcements"):
		chat_panel.set_announcements([
			_tx("ui.playerhub.announce_event", "New hero generation event this weekend"),
			_tx("ui.playerhub.announce_tax", "Auction taxes reduced for 24h"),
			_tx("ui.playerhub.announce_maintenance", "Server maintenance at 03:00 UTC"),
		])

func _update_chat_from_state(channel: String) -> void:
	if not chat_panel.has_method("set_channel_messages"):
		return
	var entries: Array = []
	if AppState.chat_messages.has(channel):
		entries = AppState.chat_messages[channel] as Array
	chat_panel.set_channel_messages(channel, entries)

# ---------------------------------------------------------------------------
# Signal callbacks
# ---------------------------------------------------------------------------
func _on_chat_message_submitted(channel: String, text: String) -> void:
	   var normalized_channel: String = channel.strip_edges().to_lower()
	   WebSocketManager.send_chat_message(normalized_channel, text)
func _on_chat_message_received(channel: String, message: Dictionary) -> void:
   # Add message to AppState and update chat panel
   if not AppState.chat_messages.has(channel):
	   AppState.chat_messages[channel] = []
   AppState.chat_messages[channel].append(message)
   _update_chat_from_state(channel)

func _on_chat_channel_changed(channel: String) -> void:
	   _active_chat_channel = channel
	   var normalized_channel = channel.strip_edges().to_lower()
	   for ch in ["general", "trade", "system"]:
		   if ch == normalized_channel:
			   WebSocketManager.ensure_chat_subscription(ch)
		   else:
			   WebSocketManager.stop_chat_subscription(ch)
	   # Clear and update chat panel
	   _update_chat_from_state(normalized_channel)
	   if normalized_channel == "system":
		   if chat_panel.has_method("set_channel_messages"):
			   chat_panel.set_channel_messages("system", [_tx("ui.playerhub.no_alerts", "No active alerts")])

func _on_logout_pressed() -> void:
	AuthManager.logout()
	if has_node("/root/EventBus"):
		var routed: bool = EventBus.navigate_to(EventBus.SCENE_LOGIN)
		if routed == false:
			UIUtils.show_error("Failed to navigate to login after logout")

func _on_notifications_pressed() -> void:
	_notification_count = 0
	if notification_badge.has_method("set_count"):
		notification_badge.set_count(_notification_count)
	if _activity_feed != null and _activity_feed.has_method("add_entry"):
		_activity_feed.add_entry(_tx("ui.playerhub.notifications_cleared", "Notifications cleared"), "system")

func _on_sidebar_module_pressed(module_name: String) -> void:
	_load_module(module_name)

func _on_settings_pressed() -> void:
	EventBus.navigate_to(EventBus.SCENE_SETTINGS)

func _on_action_create_hero_pressed() -> void:
	_load_module("hero_creation")

func _on_action_queue_pvp_pressed() -> void:
	_load_module("arena")

func _on_action_boss_raid_pressed() -> void:
	_load_module("boss_raid")

func _on_action_market_pressed() -> void:
	_load_module("auction")

func _on_user_data_updated() -> void:
	_apply_top_bar()
	_update_quick_status()

func _on_server_status_updated() -> void:
	_apply_top_bar()
	if _activity_feed != null and _activity_feed.has_method("add_entry"):
		_activity_feed.add_entry(_tx("ui.playerhub.server_status_entry", "Server: %s") % AppState.server_status, "system")

func _on_chat_updated() -> void:
	var channel: String = str(EventBus.last_chat_channel)
	_update_chat_from_state(channel)
	if channel != _active_chat_channel:
		_notification_count += 1
	if notification_badge.has_method("set_count"):
		notification_badge.set_count(_notification_count)
