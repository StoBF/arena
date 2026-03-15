extends Control

## InventoryModule — hero-scoped item grid with detail panel.

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
var _loading_overlay: Node = null
var _empty_state: Node = null

func _ready() -> void:
	refresh_button.pressed.connect(_load_inventory)
	if has_node("/root/EventBus") and not EventBus.hero_selected.is_connected(_on_hero_selected):
		EventBus.hero_selected.connect(_on_hero_selected)
	_create_overlays()
	_load_inventory()

func _create_overlays() -> void:
	_loading_overlay = LoadingOverlay.new()
	$Root/Body/GridPanel.add_child(_loading_overlay)
	_empty_state = EmptyState.new()
	_empty_state.visible = false
	$Root/Body/GridPanel/GridMargin.add_child(_empty_state)

func _on_hero_selected(_hero_id: int) -> void:
	_load_inventory()

func _load_inventory() -> void:
	for child in items_grid.get_children():
		child.queue_free()
	_items_by_id.clear()
	_clear_detail()
	_empty_state.visible = false
	var hero_id: int = _resolve_hero_id()
	if hero_id <= 0:
		hero_label.text = "Hero: -"
		_empty_state.visible = true
		if _empty_state.has_method("set_content"):
			_empty_state.set_content("No Hero Selected", "Select a hero to view their inventory.")
		status_label.text = ""
		return
	hero_label.text = "Hero: %d" % hero_id
	status_label.text = "Loading..."
	_loading_overlay.show_loading()
	var response: Dictionary = await ApiClient.get_inventory(hero_id)
	_loading_overlay.hide_loading()
	if not bool(response.get("ok", false)):
		status_label.text = "Failed to load inventory"
		UIUtils.show_error("Failed to load inventory")
		return
	var items: Array = ResponseParser.extract_array(response.get("data", {}))
	AppState.set_inventory_data(items)
	if items.is_empty():
		_empty_state.visible = true
		if _empty_state.has_method("set_content"):
			_empty_state.set_content("Empty Inventory", "This hero has no items.")
		status_label.text = ""
		return
	var index: int = 0
	for item_variant in items:
		if not item_variant is Dictionary:
			continue
		var item := (item_variant as Dictionary).duplicate(true)
		if str(item.get("id", "")).is_empty():
			item["id"] = "slot_%d" % index
		index += 1
		var item_id: String = str(item.get("id", ""))
		_items_by_id[item_id] = item
		var slot = ITEM_SLOT_SCENE.instantiate()
		slot.set_item_data(item)
		if slot.has_signal("item_selected") and not slot.item_selected.is_connected(_on_item_selected):
			slot.item_selected.connect(_on_item_selected)
		items_grid.add_child(slot)
	status_label.text = "%d items" % items.size()

func _on_item_selected(item_id: String) -> void:
	if not _items_by_id.has(item_id):
		return
	var item: Dictionary = _items_by_id[item_id] as Dictionary
	item_name.text = str(item.get("name", item.get("title", "-")))
	item_rarity.text = "Rarity: %s" % str(item.get("rarity", "common")).capitalize()
	item_quantity.text = "Qty: %s" % str(item.get("quantity", item.get("count", "-")))
	item_description.text = "[b]Description:[/b]\n%s" % str(item.get("description", "No description"))

func _clear_detail() -> void:
	item_name.text = "-"
	item_rarity.text = "Rarity: -"
	item_quantity.text = "Qty: -"
	item_description.text = "Select an item"

func _resolve_hero_id() -> int:
	if AppState.selected_hero.has("id"):
		return int(AppState.selected_hero.get("id", -1))
	if int(AppState.current_hero_id) > 0:
		return int(AppState.current_hero_id)
	return -1

