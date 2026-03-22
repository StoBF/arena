extends Control

const REFRESH_INTERVAL_SECONDS: float = 3.0

@onready var refresh_button: Button = $VBox/Header/RefreshButton
@onready var hero_select: OptionButton = $VBox/Body/PlayerHeroPanel/PlayerHeroMargin/PlayerHeroVBox/HeroSelect
@onready var player_hero_label: Label = $VBox/Body/PlayerHeroPanel/PlayerHeroMargin/PlayerHeroVBox/PlayerHeroLabel
@onready var hero_stats: RichTextLabel = $VBox/Body/PlayerHeroPanel/PlayerHeroMargin/PlayerHeroVBox/HeroStats
@onready var lobby_state_label: Label = $VBox/Body/EnemyHeroPanel/EnemyHeroMargin/EnemyHeroVBox/LobbyStateLabel
@onready var queue_count_label: Label = $VBox/Body/EnemyHeroPanel/EnemyHeroMargin/EnemyHeroVBox/QueueCountLabel
@onready var queue_list: ItemList = $VBox/Body/EnemyHeroPanel/EnemyHeroMargin/EnemyHeroVBox/QueueList
@onready var enemy_hero_label: Label = $VBox/Body/EnemyHeroPanel/EnemyHeroMargin/EnemyHeroVBox/EnemyHeroLabel
@onready var start_button: Button = $VBox/Footer/ActionRow/StartBattleButton
@onready var leave_button: Button = $VBox/Footer/ActionRow/LeaveQueueButton
@onready var auto_refresh_toggle: CheckButton = $VBox/Footer/ActionRow/AutoRefreshToggle
@onready var title_label: Label = $VBox/Header/Title
@onready var status_label: Label = $VBox/Footer/Status

var _heroes: Array[Dictionary] = []
var _selected_hero_id: int = -1
var _refresh_cooldown: float = REFRESH_INTERVAL_SECONDS
var _is_refreshing_queue: bool = false
var _is_joining_queue: bool = false

func _ready() -> void:
	if start_button == null or hero_select == null or player_hero_label == null or enemy_hero_label == null or queue_list == null:
		push_warning("BattleRoom nodes are not ready; skipping initialization")
		return
	$VBox/Header/BackButton.pressed.connect(func() -> void: EventBus.navigate_to(EventBus.SCENE_PLAYER_HUB))
	refresh_button.pressed.connect(_on_refresh_pressed)
	hero_select.item_selected.connect(_on_hero_selected_index)
	start_button.pressed.connect(_on_start_pressed)
	leave_button.pressed.connect(_on_leave_pressed)
	auto_refresh_toggle.toggled.connect(_on_auto_refresh_toggled)
	if LocalizationManager.locale_changed.is_connected(_on_locale_changed) == false:
		LocalizationManager.locale_changed.connect(_on_locale_changed)
	if has_node("/root/EventBus") and EventBus.hero_selected.is_connected(_on_eventbus_hero_selected) == false:
		EventBus.hero_selected.connect(_on_eventbus_hero_selected)
	if HeroManager.heroes_updated.is_connected(_on_manager_heroes_updated) == false:
		HeroManager.heroes_updated.connect(_on_manager_heroes_updated)
	if AppState.battle_queue_updated.is_connected(_on_battle_queue_updated) == false:
		AppState.battle_queue_updated.connect(_on_battle_queue_updated)
	call_deferred("_apply_cabinet_visuals")
	_apply_translations()
	call_deferred("_bootstrap_room")

func _process(delta: float) -> void:
	if auto_refresh_toggle == null or auto_refresh_toggle.button_pressed == false:
		return
	if _is_refreshing_queue or _is_joining_queue:
		return
	_refresh_cooldown -= delta
	if _refresh_cooldown > 0.0:
		return
	_refresh_cooldown = REFRESH_INTERVAL_SECONDS
	_refresh_queue()

func _apply_cabinet_visuals() -> void:
	CabinetStyle.style_screen(self)
	CabinetStyle.style_header(title_label, refresh_button)
	CabinetStyle.style_button($VBox/Header/BackButton)
	CabinetStyle.style_button(start_button, 180)
	CabinetStyle.style_button(leave_button, 140)
	CabinetStyle.style_status_label(status_label)
	CabinetStyle.style_status_label(lobby_state_label)
	CabinetStyle.style_status_label(queue_count_label)

func _bootstrap_room() -> void:
	status_label.text = tr("ui.battle.loading")
	_apply_cached_queue()
	await HeroManager.load_heroes()
	_populate_hero_select(HeroManager.get_heroes())
	await _refresh_queue()
	status_label.text = ""

func _populate_hero_select(heroes: Array[Dictionary]) -> void:
	_heroes = heroes.duplicate(true)
	hero_select.clear()
	for hero: Dictionary in _heroes:
		var hero_id: int = int(hero.get("id", -1))
		if hero_id <= 0:
			continue
		var hero_name: String = str(hero.get("name", "Hero"))
		hero_select.add_item(hero_name)
		hero_select.set_item_metadata(hero_select.item_count - 1, hero_id)

	var target_id: int = _resolve_current_hero_id()
	if target_id > 0:
		_select_hero_in_dropdown(target_id)
	else:
		_on_hero_selected({})

func _select_hero_in_dropdown(hero_id: int) -> void:
	for idx: int in range(hero_select.item_count):
		if int(hero_select.get_item_metadata(idx)) == hero_id:
			hero_select.select(idx)
			_selected_hero_id = hero_id
			_on_hero_selected(_hero_by_id(hero_id))
			return
	_selected_hero_id = -1
	_on_hero_selected({})

func _hero_by_id(hero_id: int) -> Dictionary:
	for hero: Dictionary in _heroes:
		if int(hero.get("id", -1)) == hero_id:
			return hero.duplicate(true)
	return {}

func _resolve_current_hero_id() -> int:
	if AppState.selected_hero.has("id"):
		return int(AppState.selected_hero.get("id", -1))
	if HeroManager.get_active_hero_id() > 0:
		return HeroManager.get_active_hero_id()
	if int(AppState.current_hero_id) > 0:
		return int(AppState.current_hero_id)
	return -1

func _apply_cached_queue() -> void:
	_render_queue(AppState.battle_queue)

func _refresh_queue() -> void:
	if _is_refreshing_queue:
		return
	_is_refreshing_queue = true
	var response: Dictionary = await ApiClient.get_battle_queue()
	_is_refreshing_queue = false
	if bool(response.get("ok", false)) == false:
		_set_lobby_state(tr("ui.battle.state_error"))
		status_label.text = tr("ui.battle.queue_failed") % str(response.get("message", response.get("error", "Request failed")))
		return
	var queue: Array = _extract_queue_items(response.get("data", []))
	AppState.update_battle_queue(queue)
	status_label.text = ""

func _extract_queue_items(parsed: Variant) -> Array:
	if parsed is Array:
		return (parsed as Array).duplicate(true)
	if parsed is Dictionary:
		var data := parsed as Dictionary
		if data.has("result") and data["result"] is Array:
			return (data["result"] as Array).duplicate(true)
		if data.has("items") and data["items"] is Array:
			return (data["items"] as Array).duplicate(true)
	return []

func _set_lobby_state(text: String) -> void:
	if lobby_state_label != null:
		lobby_state_label.text = tr("ui.battle.lobby_state") % text

func _on_eventbus_hero_selected(_hero_id: int) -> void:
	var target_id: int = _resolve_current_hero_id()
	if target_id > 0:
		_select_hero_in_dropdown(target_id)
	else:
		_on_hero_selected({})

func _on_manager_heroes_updated(heroes: Array[Dictionary]) -> void:
	_populate_hero_select(heroes)

func _on_hero_selected_index(index: int) -> void:
	if index < 0 or index >= hero_select.item_count:
		return
	var hero_id: int = int(hero_select.get_item_metadata(index))
	if hero_id <= 0:
		return
	_selected_hero_id = hero_id
	var hero: Dictionary = _hero_by_id(hero_id)
	if hero.is_empty() == false:
		HeroManager.set_active_hero_id(hero_id)
		AppState.set_selected_hero(hero)
	_on_hero_selected(hero)

func _on_hero_selected(hero: Dictionary) -> void:
	if hero.is_empty():
		player_hero_label.text = tr("ui.battle.player_none")
		start_button.disabled = true
		hero_stats.text = tr("ui.battle.hero_stats_empty")
	else:
		player_hero_label.text = tr("ui.battle.player_name") % str(hero.get("name", "Hero"))
		start_button.disabled = false
		var stats: Dictionary = hero.get("stats", {})
		hero_stats.text = "Role: %s  HP: %s  RES: %s  REF: %s" % [
			str(hero.get("primary_role", "-")),
			str(hero.get("current_hp", "-")),
			str(stats.get("resilience", "-")),
			str(stats.get("reflex", "-")),
		]
	_update_waiting_label()

func _on_battle_queue_updated(queue: Array) -> void:
	_render_queue(queue)

func _render_queue(queue: Array) -> void:
	queue_list.clear()
	var queue_size: int = 0
	var selected_queued: bool = false
	var opponent_hero_id: int = -1
	for entry_variant in queue:
		if entry_variant is Dictionary == false:
			continue
		var entry := entry_variant as Dictionary
		var hero_id: int = int(entry.get("hero_id", -1))
		if hero_id <= 0:
			continue
		queue_size += 1
		var hero_name: String = _hero_name_by_id(hero_id)
		queue_list.add_item(tr("ui.battle.queued_entry") % [queue_size, hero_name])
		if hero_id == _selected_hero_id:
			selected_queued = true
		elif opponent_hero_id <= 0:
			opponent_hero_id = hero_id

	queue_count_label.text = tr("ui.battle.queue_count") % queue_size
	if queue_size <= 0:
		_set_lobby_state(tr("ui.battle.state_idle"))
	elif selected_queued and queue_size >= 2:
		_set_lobby_state(tr("ui.battle.state_filled"))
	elif selected_queued:
		_set_lobby_state(tr("ui.battle.state_waiting"))
	else:
		_set_lobby_state(tr("ui.battle.state_idle"))

	if selected_queued and opponent_hero_id > 0:
		enemy_hero_label.text = tr("ui.battle.opponent_name") % _hero_name_by_id(opponent_hero_id)
	elif selected_queued:
		enemy_hero_label.text = tr("ui.battle.no_opponent")
	else:
		enemy_hero_label.text = tr("ui.battle.no_opponent")

	leave_button.disabled = not selected_queued
	start_button.disabled = selected_queued or _selected_hero_id <= 0

func _hero_name_by_id(hero_id: int) -> String:
	for hero_variant in AppState.heroes:
		if hero_variant is Dictionary == false:
			continue
		var hero := hero_variant as Dictionary
		if int(hero.get("id", -1)) == hero_id:
			return str(hero.get("name", "Hero"))
	var fallback: Dictionary = _hero_by_id(hero_id)
	if fallback.is_empty() == false:
		return str(fallback.get("name", "Hero"))
	return "Hero #%d" % hero_id

func _update_waiting_label() -> void:
	if _selected_hero_id <= 0:
		enemy_hero_label.text = tr("ui.battle.no_opponent")
		return
	var selected_queued: bool = false
	for entry_variant in AppState.battle_queue:
		if entry_variant is Dictionary and int((entry_variant as Dictionary).get("hero_id", -1)) == _selected_hero_id:
			selected_queued = true
			break
	if selected_queued:
		enemy_hero_label.text = tr("ui.battle.no_opponent")
	else:
		enemy_hero_label.text = tr("ui.battle.no_opponent")

func _on_start_pressed() -> void:
	if _selected_hero_id <= 0:
		status_label.text = tr("ui.battle.select_hero_first")
		return
	if _is_joining_queue:
		return
	_is_joining_queue = true
	start_button.disabled = true
	status_label.text = tr("ui.battle.joining")
	var response: Dictionary = await ApiClient.submit_battle_queue(_selected_hero_id)
	_is_joining_queue = false
	if bool(response.get("ok", false)):
		AppState.set_battle_submit_result(true, tr("ui.battle.joined"))
		status_label.text = tr("ui.battle.joined")
		await _refresh_queue()
	else:
		var message: String = str(response.get("message", response.get("error", tr("ui.battle.join_failed"))))
		AppState.set_battle_submit_result(false, message)
		status_label.text = tr("ui.battle.join_failed") % message
		start_button.disabled = false

func _on_leave_pressed() -> void:
	AppState.set_battle_queue_error(tr("ui.battle.leave_not_supported"))
	status_label.text = tr("ui.battle.leave_not_supported")
	await _refresh_queue()

func _on_refresh_pressed() -> void:
	_refresh_cooldown = REFRESH_INTERVAL_SECONDS
	await HeroManager.load_heroes()
	_populate_hero_select(HeroManager.get_heroes())
	await _refresh_queue()

func _on_auto_refresh_toggled(enabled: bool) -> void:
	_refresh_cooldown = 0.0 if enabled else REFRESH_INTERVAL_SECONDS

func _on_locale_changed(_locale_code: String) -> void:
	_apply_translations()
	_on_hero_selected(_hero_by_id(_selected_hero_id))
	_render_queue(AppState.battle_queue)

func _apply_translations() -> void:
	$VBox/Header/BackButton.text = tr("ui.common.back")
	$VBox/Header/Title.text = tr("ui.battle.title")
	refresh_button.text = tr("ui.battle.refresh")
	$VBox/Body/PlayerHeroPanel/PlayerHeroMargin/PlayerHeroVBox/HeroSelectTitle.text = tr("ui.battle.choose_hero")
	$VBox/Body/EnemyHeroPanel/EnemyHeroMargin/EnemyHeroVBox/LobbyTitle.text = tr("ui.battle.lobby")
	start_button.text = tr("ui.battle.join_room")
	leave_button.text = tr("ui.battle.leave_queue")
	auto_refresh_toggle.text = tr("ui.battle.auto_refresh")
	if _selected_hero_id <= 0:
		hero_stats.text = tr("ui.battle.hero_stats_empty")

func _exit_tree() -> void:
	if LocalizationManager.locale_changed.is_connected(_on_locale_changed):
		LocalizationManager.locale_changed.disconnect(_on_locale_changed)
	if has_node("/root/EventBus") and EventBus.hero_selected.is_connected(_on_eventbus_hero_selected):
		EventBus.hero_selected.disconnect(_on_eventbus_hero_selected)
	if HeroManager.heroes_updated.is_connected(_on_manager_heroes_updated):
		HeroManager.heroes_updated.disconnect(_on_manager_heroes_updated)
	if AppState.battle_queue_updated.is_connected(_on_battle_queue_updated):
		AppState.battle_queue_updated.disconnect(_on_battle_queue_updated)
