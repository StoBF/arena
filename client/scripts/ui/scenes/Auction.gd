extends Control

signal open_player_hub

@onready var item_list: ItemList = $VBox/Body/ItemList
@onready var filter_option: OptionButton = $VBox/Body/Controls/FilterOption

var _inventory_controller: Node = null
var _items: Array = []

func _ready() -> void:
	$VBox/Header/BackButton.pressed.connect(func(): open_player_hub.emit())
	$VBox/Body/Controls/SellButton.pressed.connect(_on_sell_pressed)
	filter_option.item_selected.connect(_on_filter_selected)
	item_list.item_selected.connect(_on_item_selected)
	filter_option.add_item("All")
	filter_option.add_item("Consumable")
	filter_option.add_item("Shirt")
	filter_option.add_item("Pants")
	filter_option.add_item("Shoes")

func bind_controllers(_player_data: Node, inventory_controller: Node, _craft_controller: Node) -> void:
	_inventory_controller = inventory_controller
	if _inventory_controller.items_changed.is_connected(_refresh_items) == false:
		_inventory_controller.items_changed.connect(_refresh_items)
	_refresh_items(_inventory_controller.get_items())

func _refresh_items(items: Array) -> void:
	_items = items.duplicate(true)
	_apply_filter(filter_option.get_item_text(filter_option.selected))

func _apply_filter(filter_name: String) -> void:
	item_list.clear()
	for item_variant in _items:
		var item := item_variant as Dictionary
		if filter_name != "All" and str(item.get("category", "")) != filter_name:
			continue
		item_list.add_item("%s x%d" % [str(item.get("name", "")), int(item.get("quantity", 0))])

func _on_filter_selected(index: int) -> void:
	_apply_filter(filter_option.get_item_text(index))

func _on_item_selected(_index: int) -> void:
	pass

func _on_sell_pressed() -> void:
	var selected := item_list.get_selected_items()
	if selected.is_empty():
		return
	var selected_visual_index: int = int(selected[0])
	var filter_name := filter_option.get_item_text(filter_option.selected)
	var visible_items: Array = []
	for item_variant in _items:
		var item := item_variant as Dictionary
		if filter_name != "All" and str(item.get("category", "")) != filter_name:
			continue
		visible_items.append(item)
	if selected_visual_index < 0 or selected_visual_index >= visible_items.size():
		return
	var target := visible_items[selected_visual_index] as Dictionary
	_inventory_controller.list_item_for_sale(str(target.get("id", "")))
