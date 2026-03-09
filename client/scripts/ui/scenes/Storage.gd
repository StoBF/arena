extends Control

signal open_player_hub

const ITEM_SLOT_SCENE := preload("res://scenes/ui/components/ItemSlot.tscn")
const RECIPE_SLOT_SCENE := preload("res://scenes/ui/components/RecipeSlot.tscn")
const HERO_SLOT_SCENE := preload("res://scenes/ui/components/HeroSlot.tscn")

@onready var items_grid: GridContainer = $VBox/Body/Tabs/Items/ItemsGrid
@onready var recipes_grid: GridContainer = $VBox/Body/Tabs/Recipes/RecipesGrid
@onready var heroes_grid: GridContainer = $VBox/Body/Tabs/Heroes/HeroesGrid
@onready var popup_recipe = $PopupRecipe
@onready var equip_shirt = $VBox/Body/EquipmentPanel/EquipGrid/ShirtSlot
@onready var equip_pants = $VBox/Body/EquipmentPanel/EquipGrid/PantsSlot
@onready var equip_shoes = $VBox/Body/EquipmentPanel/EquipGrid/ShoesSlot
@onready var delete_hero_button: Button = $VBox/Footer/DeleteHeroButton

var _player_data: Node = null
var _inventory_controller: Node = null
var _craft_controller: Node = null
var _selected_item_id: String = ""
var _selected_recipe: Dictionary = {}

func _ready() -> void:
	$VBox/Header/BackButton.pressed.connect(func(): open_player_hub.emit())
	delete_hero_button.pressed.connect(_on_delete_hero)
	equip_shirt.equip_slot_selected.connect(_on_equip_slot_selected)
	equip_pants.equip_slot_selected.connect(_on_equip_slot_selected)
	equip_shoes.equip_slot_selected.connect(_on_equip_slot_selected)
	popup_recipe.craft_requested.connect(_on_popup_craft_requested)

func bind_controllers(player_data: Node, inventory_controller: Node, craft_controller: Node) -> void:
	_player_data = player_data
	_inventory_controller = inventory_controller
	_craft_controller = craft_controller

	_connect_if_needed(_inventory_controller.items_changed, _refresh_items)
	_connect_if_needed(_inventory_controller.recipes_changed, _refresh_recipes)
	_connect_if_needed(_inventory_controller.equipment_changed, _refresh_equipment)
	_connect_if_needed(_player_data.heroes_changed, _refresh_heroes)
	_connect_if_needed(_player_data.hero_selected, _on_hero_selected)
	_connect_if_needed(_player_data.resources_changed, _on_resources_changed)
	_connect_if_needed(_craft_controller.recipe_preview_changed, _on_recipe_preview)
	_connect_if_needed(_craft_controller.craft_result, _on_craft_result)

	_refresh_items(_inventory_controller.get_items())
	_refresh_recipes(_inventory_controller.get_recipes())
	_refresh_heroes(_player_data.get_heroes())
	_refresh_equipment(_inventory_controller.get_selected_hero_equipment())
	_on_hero_selected(_player_data.get_selected_hero())
	_on_resources_changed(_player_data.get_resources())

func _connect_if_needed(signal_ref: Signal, callback: Callable) -> void:
	if signal_ref.is_connected(callback) == false:
		signal_ref.connect(callback)

func _refresh_items(items: Array) -> void:
	_clear_children(items_grid)
	for item_variant in items:
		var item := item_variant as Dictionary
		var slot = ITEM_SLOT_SCENE.instantiate()
		slot.set_item_data(item)
		slot.item_selected.connect(_on_item_selected)
		items_grid.add_child(slot)

func _refresh_recipes(recipes: Array) -> void:
	_clear_children(recipes_grid)
	for recipe_variant in recipes:
		var recipe := recipe_variant as Dictionary
		var slot = RECIPE_SLOT_SCENE.instantiate()
		slot.set_recipe_data(recipe)
		slot.recipe_selected.connect(_on_recipe_selected)
		recipes_grid.add_child(slot)

func _refresh_heroes(_heroes: Array) -> void:
	_clear_children(heroes_grid)
	var slots: Array = _player_data.get_hero_slots()
	for i: int in range(slots.size()):
		var hero_data := slots[i] as Dictionary
		var slot = HERO_SLOT_SCENE.instantiate()
		slot.slot_index = i
		slot.set_hero_data(hero_data, _is_selected_hero(hero_data))
		slot.hero_slot_selected.connect(_on_hero_slot_selected)
		heroes_grid.add_child(slot)

func _refresh_equipment(equipment: Dictionary) -> void:
	equip_shirt.set_equipped_item(equipment.get("shirt", {}) as Dictionary)
	equip_pants.set_equipped_item(equipment.get("pants", {}) as Dictionary)
	equip_shoes.set_equipped_item(equipment.get("shoes", {}) as Dictionary)

func _on_item_selected(item_id: String) -> void:
	_selected_item_id = item_id

func _on_recipe_selected(recipe_id: String) -> void:
	for recipe_variant in _inventory_controller.get_recipes():
		var recipe := recipe_variant as Dictionary
		if str(recipe.get("id", "")) == recipe_id:
			_selected_recipe = recipe
			_craft_controller.preview_recipe(recipe)
			return

func _on_recipe_preview(recipe: Dictionary, can_craft: bool) -> void:
	popup_recipe.set_recipe(recipe, _player_data.get_resources(), can_craft)

func _on_resources_changed(_resources: Dictionary) -> void:
	if _selected_recipe.is_empty() == false:
		_craft_controller.preview_recipe(_selected_recipe)

func _on_popup_craft_requested(recipe_id: String) -> void:
	_craft_controller.craft_recipe(recipe_id)

func _on_craft_result(_success: bool, _message: String) -> void:
	_refresh_items(_inventory_controller.get_items())

func _on_equip_slot_selected(slot_name: String) -> void:
	if _selected_item_id.is_empty():
		return
	_inventory_controller.equip_item_to_selected_hero(_selected_item_id, slot_name)
	_refresh_equipment(_inventory_controller.get_selected_hero_equipment())

func _on_hero_slot_selected(index: int) -> void:
	_player_data.select_hero_by_index(index)

func _on_hero_selected(hero: Dictionary) -> void:
	delete_hero_button.disabled = hero.is_empty()
	_refresh_heroes(_player_data.get_heroes())
	_refresh_equipment(_inventory_controller.get_selected_hero_equipment())

func _on_delete_hero() -> void:
	_player_data.delete_selected_hero()

func _is_selected_hero(hero: Dictionary) -> bool:
	if hero.is_empty():
		return false
	var selected := _player_data.get_selected_hero()
	if selected.is_empty():
		return false
	return str(hero.get("id", "")) == str(selected.get("id", ""))

func _clear_children(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()
