extends Control

const ITEM_SLOT_SCENE := preload("res://scenes/ui/components/ItemSlot.tscn")

@onready var hero_label: Label = $Root/Header/HeroLabel
@onready var refresh_button: Button = $Root/Header/RefreshButton
@onready var items_grid: GridContainer = $Root/Body/GridPanel/GridMargin/GridScroll/ItemsGrid
@onready var item_name: Label = $Root/Body/DetailPanel/DetailMargin/DetailVBox/ItemName
@onready var item_rarity: Label = $Root/Body/DetailPanel/DetailMargin/DetailVBox/ItemRarity
@onready var item_quantity: Label = $Root/Body/DetailPanel/DetailMargin/DetailVBox/ItemQuantity
@onready var item_description: RichTextLabel = $Root/Body/DetailPanel/DetailMargin/DetailVBox/ItemDescription
@onready var status_label: Label = $Root/StatusLabel

var _items_by_id: Dictionary = {}

func _ready() -> void:
	refresh_button.pressed.connect(_load_inventory)
	if has_node("/root/EventBus") and EventBus.hero_selected.is_connected(_on_hero_selected) == false:
		EventBus.hero_selected.connect(_on_hero_selected)
	_load_inventory()

func bind_controllers(_player_data: Node, _inventory_controller: Node, _craft_controller: Node) -> void:
	return

func _on_hero_selected(_hero_id: int) -> void:
	_load_inventory()

func _load_inventory() -> void:
	for child in items_grid.get_children():
		child.queue_free()
	_items_by_id.clear()
	_clear_detail()
	var hero_id: int = _resolve_hero_id()
	if hero_id <= 0:
		hero_label.text = "Hero: -"
		status_label.text = "Select a hero to view inventory"
		return
	hero_label.text = "Hero: %d" % hero_id
	status_label.text = "Loading inventory..."
	var response: Dictionary = await ApiClient.get_inventory(hero_id)
	if bool(response.get("ok", false)) == false:
		status_label.text = "Failed to load inventory"
		return
	var items: Array = _extract_items(response.get("data", {}))
	AppState.set_inventory_data(items)
	var index: int = 0
	for item_variant in items:
		if item_variant is Dictionary == false:
			continue
		var item := (item_variant as Dictionary).duplicate(true)
		if str(item.get("id", "")).is_empty():
			item["id"] = "slot_%d" % index
		index += 1
		var item_id: String = str(item.get("id", ""))
		_items_by_id[item_id] = item
		var slot = ITEM_SLOT_SCENE.instantiate()
		slot.set_item_data(item)
		if slot.has_signal("item_selected") and slot.item_selected.is_connected(_on_item_selected) == false:
			slot.item_selected.connect(_on_item_selected)
		items_grid.add_child(slot)
	status_label.text = "Loaded %d items" % items.size()

func _on_item_selected(item_id: String) -> void:
	if _items_by_id.has(item_id) == false:
		return
	var item: Dictionary = _items_by_id[item_id] as Dictionary
	item_name.text = "Name: %s" % str(item.get("name", item.get("title", "-")))
	item_rarity.text = "Rarity: %s" % str(item.get("rarity", "common")).capitalize()
	item_quantity.text = "Quantity: %s" % str(item.get("quantity", item.get("count", "-")))
	item_description.text = "[b]Description:[/b]\n%s" % str(item.get("description", "No description"))

func _clear_detail() -> void:
	item_name.text = "Name: -"
	item_rarity.text = "Rarity: -"
	item_quantity.text = "Quantity: -"
	item_description.text = "Select an item"

func _resolve_hero_id() -> int:
	if AppState.selected_hero.has("id"):
		return int(AppState.selected_hero.get("id", -1))
	if int(AppState.current_hero_id) > 0:
		return int(AppState.current_hero_id)
	return -1

func _extract_items(parsed: Variant) -> Array:
	if parsed is Array:
		return (parsed as Array).duplicate(true)
	if parsed is Dictionary:
		var data := parsed as Dictionary
		if data.has("result") and data["result"] is Array:
			return (data["result"] as Array).duplicate(true)
		if data.has("items") and data["items"] is Array:
			return (data["items"] as Array).duplicate(true)
	return []

