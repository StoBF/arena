extends Control

## PlayerHub — headquarters dashboard: left nav, module area, hero bar, chat dock.


func _update_overlay_layout() -> void:
	var hero_dock: Control = $OverlayDockLayer/HeroBottomDock
	var chat_dock: Control = $OverlayDockLayer/ChatDock

	var viewport_size: Vector2 = get_viewport_rect().size

	var bottom_margin: float = 12.0
	var right_margin: float = 12.0
	var gap: float = 14.0

	var chat_size: Vector2 = chat_dock.custom_minimum_size
	var hero_size: Vector2 = hero_dock.custom_minimum_size

	chat_dock.position = Vector2(
		viewport_size.x - chat_size.x - right_margin,
		viewport_size.y - chat_size.y - bottom_margin
	)
	chat_dock.size = chat_size

	var hero_x: float = chat_dock.position.x - gap - hero_size.x
	if hero_x < 240.0:
		hero_x = 240.0

	hero_dock.position = Vector2(
		hero_x,
		viewport_size.y - hero_size.y - bottom_margin
	)
	hero_dock.size = hero_size


const MODULE_SCENES := {
	"heroes": preload("res://scenes/modules/HeroesModule.tscn"),
	"inventory": preload("res://scenes/modules/InventoryModule.tscn"),
	"auction": preload("res://scenes/modules/AuctionModule.tscn"),
	"craft": preload("res://scenes/modules/CraftModule.tscn"),
	"healing": preload("res://scenes/modules/HealingModule.tscn"),
	"arena": preload("res://scenes/modules/ArenaModule.tscn"),
	"boss_raid": preload("res://scenes/modules/BossRaidModule.tscn"),
	"hero_creation": preload("res://scenes/ui/modules_mmo/HeroCreationModule.tscn"),
}

const ACTIVE_BUTTON_COLOR := Color(0.85, 0.72, 0.35, 0.35)

@onready var username_label: Label = $RootMargin/RootVBox/TopBarPanel/TopBarMargin/TopBar/PlayerInfo/InfoLabels/UsernameLabel
@onready var status_label: Label = $RootMargin/RootVBox/TopBarPanel/TopBarMargin/TopBar/PlayerInfo/InfoLabels/StatusLabel
@onready var server_indicator: ColorRect = $RootMargin/RootVBox/TopBarPanel/TopBarMargin/TopBar/PlayerInfo/ServerStatusIndicator
@onready var currency_bar: Node = $RootMargin/RootVBox/TopBarPanel/TopBarMargin/TopBar/CurrencyBar
@onready var notifications_button: Button = $RootMargin/RootVBox/TopBarPanel/TopBarMargin/TopBar/NotificationsButton
@onready var notification_badge: Node = $RootMargin/RootVBox/TopBarPanel/TopBarMargin/TopBar/NotificationsButton/NotificationBadge

@onready var heroes_button: Button = $RootMargin/RootVBox/MainRow/LeftSidebarPanel/LeftMenuMargin/LeftMenu/HeroesButton
@onready var inventory_button: Button = $RootMargin/RootVBox/MainRow/LeftSidebarPanel/LeftMenuMargin/LeftMenu/InventoryButton
@onready var craft_button: Button = $RootMargin/RootVBox/MainRow/LeftSidebarPanel/LeftMenuMargin/LeftMenu/CraftButton
@onready var auction_button: Button = $RootMargin/RootVBox/MainRow/LeftSidebarPanel/LeftMenuMargin/LeftMenu/AuctionButton
@onready var healing_button: Button = $RootMargin/RootVBox/MainRow/LeftSidebarPanel/LeftMenuMargin/LeftMenu/HealingButton
@onready var arena_button: Button = $RootMargin/RootVBox/MainRow/LeftSidebarPanel/LeftMenuMargin/LeftMenu/ArenaButton
@onready var boss_raid_button: Button = $RootMargin/RootVBox/MainRow/LeftSidebarPanel/LeftMenuMargin/LeftMenu/BossRaidButton
@onready var settings_button: Button = $RootMargin/RootVBox/MainRow/LeftSidebarPanel/LeftMenuMargin/LeftMenu/SettingsButton
@onready var logout_button: Button = $RootMargin/RootVBox/MainRow/LeftSidebarPanel/LeftMenuMargin/LeftMenu/LogoutButton

@onready var module_container: Control = $RootMargin/RootVBox/MainRow/CenterColumn/StackArea/ModulePanel/MainMargin/ModuleContainer
@onready var module_panel: PanelContainer = $RootMargin/RootVBox/MainRow/CenterColumn/StackArea/ModulePanel
@onready var hero_detail_panel: PanelContainer = $RootMargin/RootVBox/MainRow/CenterColumn/StackArea/HeroDetailPanel
@onready var hero_info_panel: Node = $RootMargin/RootVBox/MainRow/CenterColumn/StackArea/HeroDetailPanel/DetailMargin/DetailVBox/HeroSplit/HeroInfoPanel
@onready var hero_display_panel: Node = $RootMargin/RootVBox/MainRow/CenterColumn/StackArea/HeroDetailPanel/DetailMargin/DetailVBox/HeroSplit/HeroDisplayPanel
@onready var close_hero_detail_button: Button = $RootMargin/RootVBox/MainRow/CenterColumn/StackArea/HeroDetailPanel/DetailMargin/DetailVBox/CloseHeroDetailButton

@onready var action_create_hero: Button = $RootMargin/RootVBox/MainRow/CenterColumn/HubHeader/GenerateHeroButton
@onready var action_queue_pvp: Button = $RootMargin/RootVBox/MainRow/CenterColumn/HubActionsRow/ActionQueuePvP
@onready var action_boss_raid: Button = $RootMargin/RootVBox/MainRow/CenterColumn/HubActionsRow/ActionBossRaid
@onready var action_market: Button = $RootMargin/RootVBox/MainRow/CenterColumn/HubActionsRow/ActionMarket
@onready var quick_status_label: Label = $RootMargin/RootVBox/MainRow/CenterColumn/HubActionsRow/QuickStatus

@onready var chat_panel: Node = $RootMargin/RootVBox/BottomStrip/ChatDock/ChatDockMargin/ChatPanel
@onready var hero_bottom_bar: Node = $RootMargin/RootVBox/BottomStrip/HeroBottomBar

var _current_module_key: String = ""
var _current_module_instance: Node = null
var _active_chat_channel: String = "global"
var _notification_count: int = 0
var _selected_hero_slot: int = -1

var _sidebar_map: Dictionary = {}

func _tx(key: String, fallback: String) -> String:
	return CabinetStyle.text(key, fallback)

func _ready() -> void:
	call_deferred("_apply_cabinet_visuals")
	_build_sidebar_map()
	_connect_top_bar()
	_connect_sidebar()
	_connect_bottom_bar()
	_connect_hero_ui()
	_connect_events()
	_apply_top_bar()
	if HeroManager != null and HeroManager.get_heroes().is_empty():
		await HeroManager.load_heroes()
	_load_module("heroes")
	await _refresh_chat_histories()
	_apply_announcements()
	_update_quick_status()
	_refresh_hero_bar()
	if HeroManager != null and not HeroManager.heroes_updated.is_connected(_on_heroes_updated_hub):
		HeroManager.heroes_updated.connect(_on_heroes_updated_hub)
	_update_overlay_layout()
	if not get_viewport().size_changed.is_connected(_on_viewport_size_changed):
		get_viewport().size_changed.connect(_on_viewport_size_changed)
		

func _on_viewport_size_changed() -> void:
	_update_overlay_layout()		
		
func _exit_tree() -> void:
	_disconnect_top_bar()
	_disconnect_sidebar()
	_disconnect_bottom_bar()
	_disconnect_events()
	if HeroManager != null and HeroManager.heroes_updated.is_connected(_on_heroes_updated_hub):
		HeroManager.heroes_updated.disconnect(_on_heroes_updated_hub)

func _on_heroes_updated_hub(_heroes: Array[Dictionary]) -> void:
	_refresh_hero_bar()

func _connect_hero_ui() -> void:
	if close_hero_detail_button != null and not close_hero_detail_button.pressed.is_connected(_on_close_hero_detail_pressed):
		close_hero_detail_button.pressed.connect(_on_close_hero_detail_pressed)
	if hero_bottom_bar != null and hero_bottom_bar.has_signal("hero_slot_selected"):
		if not hero_bottom_bar.hero_slot_selected.is_connected(_on_hero_slot_selected):
			hero_bottom_bar.hero_slot_selected.connect(_on_hero_slot_selected)
	if hero_info_panel != null:
		if hero_info_panel.has_signal("inventory_pressed") and not hero_info_panel.inventory_pressed.is_connected(_on_hero_info_inventory):
			hero_info_panel.inventory_pressed.connect(_on_hero_info_inventory)
		if hero_info_panel.has_signal("auction_pressed") and not hero_info_panel.auction_pressed.is_connected(_on_hero_info_auction):
			hero_info_panel.auction_pressed.connect(_on_hero_info_auction)
		if hero_info_panel.has_signal("battle_prep_pressed") and not hero_info_panel.battle_prep_pressed.is_connected(_on_hero_info_battle):
			hero_info_panel.battle_prep_pressed.connect(_on_hero_info_battle)

func _on_close_hero_detail_pressed() -> void:
	_hide_hero_detail()

func _on_hero_info_inventory() -> void:
	_hide_hero_detail()
	_load_module("inventory")

func _on_hero_info_auction() -> void:
	_hide_hero_detail()
	_load_module("auction")

func _on_hero_info_battle() -> void:
	_hide_hero_detail()
	_load_module("arena")

func _on_hero_slot_selected(slot_index: int) -> void:
	var heroes: Array = HeroManager.get_heroes()
	if slot_index < 0 or slot_index >= heroes.size():
		return
	var hero: Dictionary = heroes[slot_index] as Dictionary
	if hero.is_empty():
		return
	_selected_hero_slot = slot_index
	if hero_bottom_bar != null and hero_bottom_bar.has_method("set_selected"):
		hero_bottom_bar.set_selected(slot_index)
	var hid: int = int(hero.get("id", -1))
	if hid > 0:
		HeroManager.set_active_hero_id(hid)
	if hero_info_panel != null and hero_info_panel.has_method("set_hero"):
		hero_info_panel.set_hero(hero)
	if hero_display_panel != null and hero_display_panel.has_method("set_hero_name"):
		hero_display_panel.set_hero_name(str(hero.get("name", "Hero")))
	_show_hero_detail()

func _show_hero_detail() -> void:
	if module_panel != null:
		module_panel.visible = false
	if hero_detail_panel != null:
		hero_detail_panel.visible = true

func _hide_hero_detail() -> void:
	if hero_detail_panel != null:
		hero_detail_panel.visible = false
	if module_panel != null:
		module_panel.visible = true

func _refresh_hero_bar() -> void:
	if hero_bottom_bar == null or not hero_bottom_bar.has_method("populate"):
		return
	var heroes: Array = HeroManager.get_heroes()
	hero_bottom_bar.populate(heroes)
	var active_id: int = HeroManager.get_active_hero_id()
	var idx: int = -1
	for i in range(heroes.size()):
		if heroes[i] is Dictionary and int((heroes[i] as Dictionary).get("id", -1)) == active_id:
			idx = i
			break
	if idx >= 0 and hero_bottom_bar.has_method("set_selected"):
		hero_bottom_bar.set_selected(idx)

func _apply_cabinet_visuals() -> void:
	CabinetStyle.style_screen(self)
	CabinetStyle.style_status_label(status_label)
	CabinetStyle.style_status_label(quick_status_label)
	CabinetStyle.style_button(action_queue_pvp, 120)
	CabinetStyle.style_button(action_boss_raid, 120)
	CabinetStyle.style_button(action_market, 120)

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
	if chat_panel.has_signal("message_submitted"):
		if not chat_panel.message_submitted.is_connected(_on_chat_message_submitted):
			chat_panel.message_submitted.connect(_on_chat_message_submitted)
	if chat_panel.has_signal("channel_changed"):
		if not chat_panel.channel_changed.is_connected(_on_chat_channel_changed):
			chat_panel.channel_changed.connect(_on_chat_channel_changed)
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

func _apply_top_bar() -> void:
	var player_name: String = str(AppState.username)
	if player_name.is_empty():
		player_name = "—"
	username_label.text = tr("HUB_PLAYER").replace("{name}", player_name) if TranslationServer.get_locale() != "" else "Player: %s" % player_name
	var srv_status: String = str(AppState.server_status)
	var online_count: int = int(AppState.online_players)
	status_label.text = "Server: %s  ·  %d online" % [srv_status, online_count]
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

func _load_module(module_name: String) -> void:
	if not MODULE_SCENES.has(module_name):
		UIUtils.show_warning(_tx("ui.module.not_available", "Module '%s' not available.") % module_name)
		return
	if module_name == _current_module_key and _current_module_instance != null:
		return
	if _current_module_instance != null and _current_module_instance.is_inside_tree():
		_current_module_instance.queue_free()
		_current_module_instance = null
	_current_module_key = module_name
	var scene: PackedScene = MODULE_SCENES[module_name]
	_current_module_instance = scene.instantiate()
	module_container.add_child(_current_module_instance)
	if _current_module_instance is Control:
		(_current_module_instance as Control).set_anchors_preset(Control.PRESET_FULL_RECT)
	_highlight_sidebar_button(module_name)
	_hide_hero_detail()

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

func _update_quick_status() -> void:
	var hero_count: int = HeroManager.get_heroes().size()
	quick_status_label.text = _tx("ui.playerhub.quick_heroes", "Heroes: %d") % hero_count

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

func _ws_channel_for_ui(ui_ch: String) -> String:
	var c: String = ui_ch.strip_edges().to_lower()
	if c == "global":
		return "general"
	return c

func _on_chat_message_submitted(channel: String, text: String) -> void:
	var ws_ch: String = _ws_channel_for_ui(channel)
	WebSocketManager.send_chat_message(ws_ch, text)

func _on_chat_message_received(channel: String, message: Dictionary) -> void:
	var ui_ch: String = channel
	if channel == "general":
		ui_ch = "global"
	if not AppState.chat_messages.has(ui_ch):
		AppState.chat_messages[ui_ch] = []
	AppState.chat_messages[ui_ch].append(message)
	_update_chat_from_state(ui_ch)

func _on_chat_channel_changed(channel: String) -> void:
	_active_chat_channel = channel
	var ws_target: String = _ws_channel_for_ui(channel)
	for ch in ["general", "trade", "system"]:
		if ch == ws_target:
			WebSocketManager.ensure_chat_subscription(ch)
		else:
			WebSocketManager.stop_chat_subscription(ch)
	var ui_ch: String = channel.strip_edges().to_lower()
	_update_chat_from_state(ui_ch)
	if ui_ch == "system":
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

func _on_chat_updated() -> void:
	var channel: String = str(EventBus.last_chat_channel)
	var ui_ch: String = channel
	if channel == "general":
		ui_ch = "global"
	_update_chat_from_state(ui_ch)
	if ui_ch != _active_chat_channel:
		_notification_count += 1
	if notification_badge.has_method("set_count"):
		notification_badge.set_count(_notification_count)
