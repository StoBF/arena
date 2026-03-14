extends Control

var _hero_id: int = -1

@onready var hero_id_label: Label = $VBox/HeroIdLabel

func set_hero(hero_id: int) -> void:
	_hero_id = hero_id
	hero_id_label.text = "Hero ID: %d" % _hero_id

func _ready() -> void:
	if has_node("/root/EventBus"):
		var bus := get_node("/root/EventBus") as UIEventBus
		if bus.hero_changed.is_connected(_on_hero_changed) == false:
			bus.hero_changed.connect(_on_hero_changed)
		if bus.inventory_updated.is_connected(_on_inventory_updated) == false:
			bus.inventory_updated.connect(_on_inventory_updated)
	if has_node("/root/AppState"):
		set_hero((get_node("/root/AppState") as UIAppState).selected_hero_id)
	_refresh_recipe_availability()

func _on_hero_changed(hero_id: int) -> void:
	set_hero(hero_id)
	_refresh_recipe_availability()

func _on_inventory_updated(hero_id: int) -> void:
	if hero_id != _hero_id:
		return
	_refresh_recipe_availability()

func _refresh_recipe_availability() -> void:
	if has_node("/root/AppState") == false:
		return
	var state := get_node("/root/AppState") as UIAppState
	var hero_items_variant: Variant = state.inventory.get(_hero_id, [])
	var hero_items: Array = hero_items_variant as Array if hero_items_variant is Array else []
	var available_count: int = mini(state.recipes.size(), hero_items.size())
	hero_id_label.text = "Hero ID: %d | Recipes: %d" % [_hero_id, available_count]
