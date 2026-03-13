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
		if bus.hero_selected.is_connected(_on_hero_selected) == false:
			bus.hero_selected.connect(_on_hero_selected)
	if has_node("/root/AppState"):
		set_hero((get_node("/root/AppState") as UIAppState).selected_hero_id)
	_refresh_inventory()

func _on_hero_selected(hero_id: int) -> void:
	set_hero(hero_id)
	_refresh_inventory()

func _refresh_inventory() -> void:
	if _hero_id <= 0:
		count_label.text = "Items: 0"
		return
	if has_node("/root/ApiClient") == false or has_node("/root/AppState") == false:
		return
	var response: Dictionary = await (get_node("/root/ApiClient") as UIApiClient).get_inventory(_hero_id)
	if bool(response.get("ok", false)) == false:
		return
	var items: Array = response.get("data", []) as Array
	(get_node("/root/AppState") as UIAppState).set_inventory(items)
	count_label.text = "Items: %d" % items.size()
	if has_node("/root/EventBus"):
		(get_node("/root/EventBus") as UIEventBus).inventory_updated.emit()
