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

func _ready() -> void:
	refresh_button.pressed.connect(_load_heroes)
	promote_button.pressed.connect(_on_promote_pressed)
	manage_gear_button.pressed.connect(_on_manage_gear_pressed)
	_create_overlays()
	_load_heroes()

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
	bp_title.text = tr("HEROES_BODY_PARTS") if TranslationServer.get_locale() != "" else "Body Parts"
	_body_parts_container.add_child(bp_title)
	detail_vbox.add_child(_body_parts_container)

func _load_heroes() -> void:
	status_label.text = tr("HEROES_LOADING") if TranslationServer.get_locale() != "" else "Loading heroes..."
	_loading_overlay.show_loading()
	_empty_state.visible = false
	var response: Dictionary = await ApiClient.get_heroes()
	_loading_overlay.hide_loading()
	if not bool(response.get("ok", false)):
		status_label.text = tr("HEROES_LOAD_FAILED") if TranslationServer.get_locale() != "" else "Failed to load heroes"
		UIUtils.show_error("Failed to load heroes")
		return
	var heroes: Array = ResponseParser.extract_array(response.get("data", {}))
	AppState.set_heroes_data(heroes)
	_render_heroes(heroes)

func _render_heroes(heroes: Array) -> void:
	for child in cards_grid.get_children():
		child.queue_free()
	if heroes.is_empty():
		_empty_state.visible = true
		if _empty_state.has_method("set_content"):
			_empty_state.set_content("No Heroes", "Recruit or create a hero to begin.")
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
	if not heroes.is_empty() and heroes[0] is Dictionary:
		_apply_hero_details(heroes[0] as Dictionary)
	status_label.text = "%d heroes" % heroes.size()

func _on_card_selected(hero_id: int) -> void:
	for hero_variant in AppState.heroes:
		if not hero_variant is Dictionary:
			continue
		var hero := hero_variant as Dictionary
		if int(hero.get("id", -1)) != hero_id:
			continue
		_apply_hero_details(hero)
		AppState.set_selected_hero(hero)
		if has_node("/root/EventBus"):
			EventBus.emit_hero_selected(hero_id)
		break

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
	for key_variant in equipment.keys():
		equipment_list.add_item("%s: %s" % [str(key_variant).capitalize(), str(equipment[key_variant])])
	if equipment_list.item_count == 0:
		equipment_list.add_item("No equipment equipped")
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
				row.set_data(
					str(bp.get("name", "?")),
					float(bp.get("current_hp", 100)),
					float(bp.get("max_hp", 100)),
					str(bp.get("condition", "healthy"))
				)

func _stat_block(hero: Dictionary) -> String:
	if hero.has("attributes") and hero["attributes"] is Dictionary:
		var attributes := hero["attributes"] as Dictionary
		var lines: PackedStringArray = []
		for key_variant in attributes.keys():
			lines.append("[b]%s:[/b] %s" % [str(key_variant).capitalize(), str(attributes[key_variant])])
		return "\n".join(lines)
	return "[b]Strength:[/b] %s\n[b]Agility:[/b] %s\n[b]Intelligence:[/b] %s\n[b]Vitality:[/b] %s" % [
		str(hero.get("strength", "-")),
		str(hero.get("agility", "-")),
		str(hero.get("intelligence", "-")),
		str(hero.get("vitality", "-")),
	]

func _on_promote_pressed() -> void:
	if _selected_hero.is_empty():
		UIUtils.show_warning("Select a hero first")
		return
	UIUtils.show_info("Hero %s is ready for promotion" % str(_selected_hero.get("name", "-")))

func _on_manage_gear_pressed() -> void:
	if _selected_hero.is_empty():
		UIUtils.show_warning("Select a hero first")
		return
	if has_node("/root/EventBus"):
		EventBus.emit_scene_changed("Storage")
