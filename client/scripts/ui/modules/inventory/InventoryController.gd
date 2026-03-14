extends Control

var _hero_id: int = -1

@onready var hero_id_label: Label = $VBox/HeroIdLabel
@onready var count_label: Label = $VBox/InventoryCountLabel
@onready var refresh_button: Button = $VBox/RefreshButton

func set_hero(hero_id: int) -> void:
	_hero_id = hero_id
	hero_id_label.text = "Hero ID: %d" % _hero_id

func _ready() -> void:
	refresh_button.pressed.connect(_refresh_inventory)
	if has_node("/root/EventBus"):
		var bus := get_node("/root/EventBus") as UIEventBus
		if bus.hero_changed.is_connected(_on_hero_changed) == false:
			bus.hero_changed.connect(_on_hero_changed)
		if bus.inventory_updated.is_connected(_on_inventory_updated) == false:
			bus.inventory_updated.connect(_on_inventory_updated)
	if has_node("/root/AppState"):
		set_hero((get_node("/root/AppState") as UIAppState).selected_hero_id)
	_refresh_inventory()

func _on_hero_changed(hero_id: int) -> void:
	set_hero(hero_id)
	_refresh_inventory()

func _on_inventory_updated(hero_id: int) -> void:
	if hero_id != _hero_id:
		return
	_refresh_item_grid()

func _refresh_inventory() -> void:
	if _hero_id <= 0:
		count_label.text = "Items: 0"
		return
	if has_node("/root/AppState") == false:
		return
	var response: Dictionary = await ApiClient.get_inventory(_hero_id)
	if bool(response.get("ok", false)) == false:
		return

func _refresh_item_grid() -> void:
	if _hero_id <= 0 or has_node("/root/AppState") == false:
		count_label.text = "Items: 0"
		return
	var state := get_node("/root/AppState") as UIAppState
	var items_variant: Variant = state.inventory.get(_hero_id, [])
	var items: Array = items_variant as Array if items_variant is Array else []
	count_label.text = "Items: %d" % items.size()
