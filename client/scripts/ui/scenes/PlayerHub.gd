extends Control

## PlayerHub — the central headquarters dashboard.
## Hosts the sidebar navigation, module container, quick-action bar,
## chat panel, and activity feed.

# ---------------------------------------------------------------------------
# Module registry — add new modules here
# ---------------------------------------------------------------------------
const MODULE_SCENES := {
	"heroes": preload("res://scenes/modules/HeroesModule.tscn"),
	"inventory": preload("res://scenes/modules/InventoryModule.tscn"),
	"auction": preload("res://scenes/modules/AuctionModule.tscn"),
	"craft": preload("res://scenes/modules/CraftModule.tscn"),
	"training": preload("res://scenes/modules/TrainingModule.tscn"),
	"healing": preload("res://scenes/modules/HealingModule.tscn"),
	"arena": preload("res://scenes/modules/ArenaModule.tscn"),
	"boss_raid": preload("res://scenes/modules/BossRaidModule.tscn"),
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
@onready var notification_badge: Node   = $RootMargin/RootVBox/TopBarPanel/TopBarMargin/TopBar/NotificationsButton/NotificationBadge

# ---------------------------------------------------------------------------
# Node references – Sidebar buttons
# ---------------------------------------------------------------------------
@onready var heroes_button: Button    = $RootMargin/RootVBox/BodyRow/LeftSidebarPanel/LeftMenuMargin/LeftMenu/HeroesButton
@onready var inventory_button: Button = $RootMargin/RootVBox/BodyRow/LeftSidebarPanel/LeftMenuMargin/LeftMenu/InventoryButton
@onready var craft_button: Button     = $RootMargin/RootVBox/BodyRow/LeftSidebarPanel/LeftMenuMargin/LeftMenu/CraftButton
@onready var auction_button: Button   = $RootMargin/RootVBox/BodyRow/LeftSidebarPanel/LeftMenuMargin/LeftMenu/AuctionButton
@onready var training_button: Button  = $RootMargin/RootVBox/BodyRow/LeftSidebarPanel/LeftMenuMargin/LeftMenu/TrainingButton
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

## Map sidebar button → module key for highlight tracking
var _sidebar_map: Dictionary = {}

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------
func _ready() -> void:
	_build_sidebar_map()
	_create_activity_feed()
	_connect_sidebar()
	_connect_bottom_bar()
	_connect_events()
	_apply_top_bar()
	_load_module("heroes")
	await _refresh_chat_histories()
	_apply_announcements()
	_update_quick_status()

# ---------------------------------------------------------------------------
# Sidebar map (button → module key) for highlighting
# ---------------------------------------------------------------------------
func _build_sidebar_map() -> void:
	_sidebar_map = {
		heroes_button: "heroes",
		inventory_button: "inventory",
		craft_button: "craft",
		auction_button: "auction",
		training_button: "training",
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
		btn.pressed.connect(_load_module.bind(key))
	settings_button.pressed.connect(func() -> void: EventBus.emit_scene_changed("Settings"))
	logout_button.pressed.connect(_on_logout_pressed)
	# Chat signals
	if chat_panel.has_signal("message_submitted"):
		chat_panel.message_submitted.connect(_on_chat_message_submitted)
	if chat_panel.has_signal("channel_changed"):
		chat_panel.channel_changed.connect(_on_chat_channel_changed)

func _connect_bottom_bar() -> void:
	action_create_hero.pressed.connect(func() -> void:
		EventBus.emit_scene_changed("HeroCreation"))
	action_queue_pvp.pressed.connect(func() -> void:
		_load_module("arena"))
	action_boss_raid.pressed.connect(func() -> void:
		_load_module("boss_raid"))
	action_market.pressed.connect(func() -> void:
		_load_module("auction"))

func _connect_events() -> void:
	if not has_node("/root/EventBus"):
		return
	if not EventBus.user_data_updated.is_connected(_on_user_data_updated):
		EventBus.user_data_updated.connect(_on_user_data_updated)
	if not EventBus.server_status_updated.is_connected(_on_server_status_updated):
		EventBus.server_status_updated.connect(_on_server_status_updated)
	if not EventBus.chat_updated.is_connected(_on_chat_updated):
		EventBus.chat_updated.connect(_on_chat_updated)

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
		UIUtils.show_warning("Module '%s' not available." % module_name)
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
		_activity_feed.add_entry("Opened %s" % module_name, "system")

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
	var hero_count: int = HeroManager.heroes.size() if HeroManager.heroes is Array else 0
	quick_status_label.text = "Heroes: %d" % hero_count

# ---------------------------------------------------------------------------
# Chat helpers
# ---------------------------------------------------------------------------
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
			"Server maintenance at 03:00 UTC",
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
	var response: Dictionary = await ApiClient.send_chat_message(normalized_channel, text)
	if not bool(response.get("ok", false)):
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
	elif _active_chat_channel == "system":
		if chat_panel.has_method("set_channel_messages"):
			chat_panel.set_channel_messages("system", ["No active alerts"])

func _on_logout_pressed() -> void:
	AuthManager.logout()
	if has_node("/root/EventBus"):
		EventBus.emit_scene_changed("LoginScene")

func _on_user_data_updated() -> void:
	_apply_top_bar()
	_update_quick_status()

func _on_server_status_updated() -> void:
	_apply_top_bar()
	if _activity_feed != null and _activity_feed.has_method("add_entry"):
		_activity_feed.add_entry("Server: %s" % AppState.server_status, "system")

func _on_chat_updated() -> void:
	var channel: String = str(EventBus.last_chat_channel)
	_update_chat_from_state(channel)
	if channel != _active_chat_channel:
		_notification_count += 1
	if notification_badge.has_method("set_count"):
		notification_badge.set_count(_notification_count)
