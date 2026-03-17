extends Control

## HeroesModule — roster management, hero inspection, status, body parts.

const HERO_CARD_SCENE := preload("res://scenes/ui/components/HeroCard.tscn")

@onready var cards_grid: GridContainer = $Root/Body/RosterPanel/RosterMargin/CardsScroll/CardsGrid
@onready var refresh_button: Button = $Root/Header/RefreshButton
@onready var detail_name: Label = $Root/Body/DetailPanel/DetailMargin/DetailVBox/DetailName
@onready var detail_stats: RichTextLabel = $Root/Body/DetailPanel/DetailMargin/DetailVBox/DetailStats
@onready var equipment_list: ItemList = $Root/Body/DetailPanel/DetailMargin/DetailVBox/EquipmentList
@onready var promote_button: Button = $Root/Body/DetailPanel/DetailMargin/DetailVBox/ActionRow/PromoteButton
@onready var manage_gear_button: Button = $Root/Body/DetailPanel/DetailMargin/DetailVBox/ActionRow/ManageGearButton
@onready var status_label: Label = $Root/StatusLabel

var _selected_hero: Dictionary = {}
var _loading_overlay: Node = null
var _empty_state: Node = null
var _status_pill: Node = null
var _body_parts_container: VBoxContainer = null
var _is_loading: bool = false

func _tx(key: String, fallback: String) -> String:
	return CabinetStyle.text(key, fallback)

func _ready() -> void:
	if refresh_button == null or status_label == null:
		push_warning("HeroesModule nodes are not ready; skipping initialization")
		return
	if not refresh_button.pressed.is_connected(_on_refresh_pressed):
		refresh_button.pressed.connect(_on_refresh_pressed)
	promote_button.pressed.connect(_on_promote_pressed)
	manage_gear_button.pressed.connect(_on_manage_gear_pressed)
	promote_button.disabled = true
	promote_button.tooltip_text = _tx("ui.heroes.promote_unavailable", "Promotion is not available on this backend")
	_create_overlays()
	_connect_hero_signals()
	call_deferred("_apply_cabinet_visuals")
	call_deferred("_bootstrap_heroes")

func _exit_tree() -> void:
	_disconnect_hero_signals()

func _apply_cabinet_visuals() -> void:
	CabinetStyle.style_screen(self)
	CabinetStyle.style_header($Root/Header/Title, refresh_button)
	CabinetStyle.style_status_label(status_label)

func _create_overlays() -> void:
	# Loading overlay on roster panel
	_loading_overlay = LoadingOverlay.new()
	$Root/Body/RosterPanel.add_child(_loading_overlay)
	# Empty state inside roster scroll area
	_empty_state = EmptyState.new()
	_empty_state.visible = false
	$Root/Body/RosterPanel/RosterMargin.add_child(_empty_state)
	# Status pill in detail panel (under name)
	_status_pill = StatusPill.new()
	var detail_vbox: VBoxContainer = $Root/Body/DetailPanel/DetailMargin/DetailVBox
	detail_vbox.add_child(_status_pill)
	detail_vbox.move_child(_status_pill, 1)  # right after DetailName
	# Body parts section
	_body_parts_container = VBoxContainer.new()
	_body_parts_container.name = "BodyPartsSection"
	var bp_title := Label.new()
	bp_title.text = _tx("ui.heroes.body_parts", _tx("HEROES_BODY_PARTS", "Body Parts"))
	_body_parts_container.add_child(bp_title)
	detail_vbox.add_child(_body_parts_container)

func _connect_hero_signals() -> void:
	if HeroManager != null:
		if HeroManager.heroes_updated.is_connected(_on_heroes_updated) == false:
			HeroManager.heroes_updated.connect(_on_heroes_updated)
		if HeroManager.heroes_load_failed.is_connected(_on_heroes_load_failed) == false:
			HeroManager.heroes_load_failed.connect(_on_heroes_load_failed)

func _disconnect_hero_signals() -> void:
	if HeroManager == null:
		return
	if HeroManager.heroes_updated.is_connected(_on_heroes_updated):
		HeroManager.heroes_updated.disconnect(_on_heroes_updated)
	if HeroManager.heroes_load_failed.is_connected(_on_heroes_load_failed):
		HeroManager.heroes_load_failed.disconnect(_on_heroes_load_failed)

func _bootstrap_heroes() -> void:
	if cards_grid == null:
		return
	var cached_heroes: Array = HeroManager.get_heroes()
	if cached_heroes.is_empty() == false:
		_render_heroes(cached_heroes)
	status_label.text = _tx("ui.heroes.loading", _tx("HEROES_LOADING", "Loading heroes..."))
	_load_heroes(true)

func _on_refresh_pressed() -> void:
	_load_heroes(true)

func _load_heroes(force_refresh: bool = false) -> void:
	if _is_loading:
		return
	_is_loading = true
	status_label.text = _tx("ui.heroes.loading", _tx("HEROES_LOADING", "Loading heroes..."))
	if _loading_overlay != null:
		_loading_overlay.show_loading()
	_empty_state.visible = false
	if force_refresh or HeroManager.get_heroes().is_empty():
		await HeroManager.load_heroes()
	else:
		_on_heroes_updated(HeroManager.get_heroes())
	if _loading_overlay != null:
		_loading_overlay.hide_loading()
	_is_loading = false

func _on_heroes_updated(heroes: Array[Dictionary]) -> void:
	var normalized: Array = []
	for hero in heroes:
		normalized.append(hero.duplicate(true))
	_render_heroes(normalized)

func _on_heroes_load_failed(message: String) -> void:
	if _loading_overlay != null:
		_loading_overlay.hide_loading()
	_is_loading = false
	status_label.text = _tx("ui.heroes.load_failed", _tx("HEROES_LOAD_FAILED", "Failed to load heroes"))
	if message.is_empty() == false:
		UIUtils.show_error(message)

func _render_heroes(heroes: Array) -> void:
	for child in cards_grid.get_children():
		child.queue_free()
	if heroes.is_empty():
		_empty_state.visible = true
		if _empty_state.has_method("set_content"):
			_empty_state.set_content(
				_tx("ui.heroes.empty_title", _tx("HEROES_NO_HEROES", "No Heroes")),
				_tx("ui.heroes.empty_hint", _tx("HEROES_RECRUIT_HINT", "Recruit or create a hero to begin."))
			)
		status_label.text = ""
		return
	_empty_state.visible = false
	for hero_variant in heroes:
		if not hero_variant is Dictionary:
			continue
		var card: Control = HERO_CARD_SCENE.instantiate()
		cards_grid.add_child(card)
		if card.has_method("set_hero"):
			card.set_hero(hero_variant as Dictionary)
		if card.has_signal("selected") and not card.selected.is_connected(_on_card_selected):
			card.selected.connect(_on_card_selected)
	var selected_id: int = int(AppState.selected_hero.get("id", HeroManager.get_active_hero_id()))
	var selected_from_list: Dictionary = _find_hero_by_id(heroes, selected_id)
	if selected_from_list.is_empty() and not heroes.is_empty() and heroes[0] is Dictionary:
		selected_from_list = (heroes[0] as Dictionary).duplicate(true)
	if selected_from_list.is_empty() == false:
		_apply_hero_details(selected_from_list)
		HeroManager.set_active_hero_id(int(selected_from_list.get("id", -1)))
	status_label.text = "%d heroes" % heroes.size()

func _on_card_selected(hero_id: int) -> void:
	var hero: Dictionary = HeroManager.get_hero_by_id(hero_id)
	if hero.is_empty():
		UIUtils.show_warning(_tx("ui.heroes.select_first", _tx("HEROES_SELECT_FIRST", "Select a hero first")))
		return
	_apply_hero_details(hero)
	HeroManager.set_active_hero_id(hero_id)

func _apply_hero_details(hero: Dictionary) -> void:
	_selected_hero = hero.duplicate(true)
	detail_name.text = str(hero.get("name", "-"))
	# Status pill
	var hero_status: String = str(hero.get("status", "idle")).to_lower()
	if _status_pill != null and _status_pill.has_method("set_status"):
		_status_pill.set_status(hero_status)
	# Stats block
	detail_stats.text = "[b]Level:[/b] %s  [b]Gen:[/b] %s\n[b]Wins:[/b] %s  [b]Losses:[/b] %s\n\n%s" % [
		str(hero.get("level", "-")),
		str(hero.get("generation", hero.get("gen", "-"))),
		str(hero.get("wins", hero.get("victories", "-"))),
		str(hero.get("losses", hero.get("defeats", "-"))),
		_stat_block(hero),
	]
	# Equipment
	equipment_list.clear()
	var equipment: Dictionary = {}
	if hero.has("equipment") and hero["equipment"] is Dictionary:
		equipment = hero["equipment"] as Dictionary
	elif hero.has("equipment_items") and hero["equipment_items"] is Array:
		for entry_variant in (hero["equipment_items"] as Array):
			if entry_variant is Dictionary == false:
				continue
			var entry := entry_variant as Dictionary
			var slot_key: String = str(entry.get("slot", "slot"))
			if entry.has("item") and entry["item"] is Dictionary:
				var item_data := entry["item"] as Dictionary
				equipment[slot_key] = str(item_data.get("name", "-"))
			else:
				equipment[slot_key] = str(entry.get("item_name", entry.get("item_id", "-")))
	for key_variant in equipment.keys():
		equipment_list.add_item("%s: %s" % [str(key_variant).capitalize(), str(equipment[key_variant])])
	if equipment_list.item_count == 0:
		equipment_list.add_item(_tx("ui.heroes.no_equipment", "No equipment equipped"))
	# Body parts
	_render_body_parts(hero)

func _render_body_parts(hero: Dictionary) -> void:
	if _body_parts_container == null:
		return
	# Remove old rows (keep the title label at index 0)
	while _body_parts_container.get_child_count() > 1:
		_body_parts_container.get_child(_body_parts_container.get_child_count() - 1).queue_free()
	var body_parts: Array = []
	if hero.has("body_parts") and hero["body_parts"] is Array:
		body_parts = hero["body_parts"] as Array
	if body_parts.is_empty():
		# Default 6 body parts with placeholder data
		for part_name in ["Head", "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg"]:
			var row := BodyPartStatusRow.new()
			_body_parts_container.add_child(row)
			if row.has_method("set_data"):
				row.set_data(part_name, 100.0, 100.0, "healthy")
	else:
		for bp_variant in body_parts:
			if not bp_variant is Dictionary:
				continue
			var bp := bp_variant as Dictionary
			var row := BodyPartStatusRow.new()
			_body_parts_container.add_child(row)
			if row.has_method("set_data"):
				var part_name: String = str(bp.get("part_name", bp.get("name", "?")))
				# H11: server sends "condition" field; "status" is the legacy/fallback key
				var part_status: String = str(bp.get("condition", bp.get("status", "healthy")))
				row.set_data(
					part_name,
					float(bp.get("current_hp", 100)),
					float(bp.get("max_hp", 100)),
					part_status
				)

func _stat_block(hero: Dictionary) -> String:
	if hero.has("attributes") and hero["attributes"] is Dictionary:
		var attributes := hero["attributes"] as Dictionary
		var lines: PackedStringArray = []
		for key_variant in attributes.keys():
			lines.append("[b]%s:[/b] %s" % [str(key_variant).capitalize(), str(attributes[key_variant])])
		return "\n".join(lines)
	return "[b]Strength:[/b] %s\n[b]Perception:[/b] %s\n[b]Endurance:[/b] %s\n[b]Intelligence:[/b] %s\n[b]Agility:[/b] %s\n[b]Luck:[/b] %s\n[b]Willpower:[/b] %s" % [
		str(hero.get("strength", "-")),
		str(hero.get("perception", "-")),
		str(hero.get("endurance", "-")),
		str(hero.get("intelligence", "-")),
		str(hero.get("agility", "-")),
		str(hero.get("luck", "-")),
		str(hero.get("willpower", "-")),
	]

func _find_hero_by_id(heroes: Array, hero_id: int) -> Dictionary:
	if hero_id <= 0:
		return {}
	for hero_variant in heroes:
		if hero_variant is Dictionary == false:
			continue
		var hero := hero_variant as Dictionary
		if int(hero.get("id", -1)) == hero_id:
			return hero.duplicate(true)
	return {}

func _on_promote_pressed() -> void:
	UIUtils.show_error(_tx("ui.heroes.promote_unavailable", "Promotion is not available on this backend"))

func _on_manage_gear_pressed() -> void:
	if _selected_hero.is_empty():
		UIUtils.show_warning(_tx("ui.heroes.select_first", _tx("HEROES_SELECT_FIRST", "Select a hero first")))
		return
	if has_node("/root/EventBus"):
		EventBus.navigate_to(EventBus.SCENE_STORAGE)
