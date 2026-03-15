extends Control

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

func _ready() -> void:
	refresh_button.pressed.connect(_load_heroes)
	promote_button.pressed.connect(_on_promote_pressed)
	manage_gear_button.pressed.connect(_on_manage_gear_pressed)
	_load_heroes()

func bind_controllers(_player_data: Node, _inventory_controller: Node, _craft_controller: Node) -> void:
	return

func _load_heroes() -> void:
	status_label.text = "Loading heroes..."
	var response: Dictionary = await ApiClient.get_heroes()
	if bool(response.get("ok", false)) == false:
		status_label.text = "Failed to load heroes"
		return
	var heroes: Array = _extract_heroes(response.get("data", {}))
	AppState.set_heroes_data(heroes)
	_render_heroes(heroes)

func _render_heroes(heroes: Array) -> void:
	for child in cards_grid.get_children():
		child.queue_free()
	if heroes.is_empty():
		status_label.text = "No heroes available"
		return
	for hero_variant in heroes:
		if hero_variant is Dictionary == false:
			continue
		var card: Control = HERO_CARD_SCENE.instantiate()
		cards_grid.add_child(card)
		if card.has_method("set_hero"):
			card.set_hero(hero_variant as Dictionary)
		if card.has_signal("selected") and card.selected.is_connected(_on_card_selected) == false:
			card.selected.connect(_on_card_selected)
	if heroes.is_empty() == false and heroes[0] is Dictionary:
		_apply_hero_details(heroes[0] as Dictionary)
	status_label.text = "Loaded %d heroes" % heroes.size()

func _on_card_selected(hero_id: int) -> void:
	for hero_variant in AppState.heroes:
		if hero_variant is Dictionary == false:
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
	detail_name.text = "Name: %s" % str(hero.get("name", "-"))
	detail_stats.text = "[b]Level:[/b] %s\n[b]Generation:[/b] %s\n[b]Wins:[/b] %s\n[b]Losses:[/b] %s\n\n[b]Stats[/b]\n%s" % [
		str(hero.get("level", "-")),
		str(hero.get("generation", hero.get("gen", "-"))),
		str(hero.get("wins", hero.get("victories", "-"))),
		str(hero.get("losses", hero.get("defeats", "-"))),
		_stat_block(hero),
	]
	equipment_list.clear()
	var equipment: Dictionary = {}
	if hero.has("equipment") and hero["equipment"] is Dictionary:
		equipment = hero["equipment"] as Dictionary
	for key_variant in equipment.keys():
		equipment_list.add_item("%s: %s" % [str(key_variant).capitalize(), str(equipment[key_variant])])
	if equipment_list.item_count == 0:
		equipment_list.add_item("No equipment equipped")

func _stat_block(hero: Dictionary) -> String:
	if hero.has("attributes") and hero["attributes"] is Dictionary:
		var attributes := hero["attributes"] as Dictionary
		var lines: PackedStringArray = []
		for key_variant in attributes.keys():
			lines.append("%s: %s" % [str(key_variant).capitalize(), str(attributes[key_variant])])
		return "\n".join(lines)
	return "Strength: %s\nAgility: %s\nIntelligence: %s\nVitality: %s" % [
		str(hero.get("strength", "-")),
		str(hero.get("agility", "-")),
		str(hero.get("intelligence", "-")),
		str(hero.get("vitality", "-")),
	]

func _on_promote_pressed() -> void:
	if _selected_hero.is_empty():
		status_label.text = "Select a hero first"
		return
	status_label.text = "Hero %s is ready for promotion flow" % str(_selected_hero.get("name", "-"))

func _on_manage_gear_pressed() -> void:
	if _selected_hero.is_empty():
		status_label.text = "Select a hero first"
		return
	if has_node("/root/EventBus"):
		EventBus.emit_scene_changed("Storage")

func _extract_heroes(parsed: Variant) -> Array:
	if parsed is Array:
		return (parsed as Array).duplicate(true)
	if parsed is Dictionary:
		var data := parsed as Dictionary
		if data.has("result") and data["result"] is Array:
			return (data["result"] as Array).duplicate(true)
		if data.has("items") and data["items"] is Array:
			return (data["items"] as Array).duplicate(true)
	return []
