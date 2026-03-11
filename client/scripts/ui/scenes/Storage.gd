extends Control

signal open_player_hub

const ITEM_SLOT_SCENE := preload("res://scenes/ui/components/ItemSlot.tscn")
const RECIPE_SLOT_SCENE := preload("res://scenes/ui/components/RecipeSlot.tscn")
const HERO_SLOT_SCENE := preload("res://scenes/ui/components/HeroSlot.tscn")
const MAX_HERO_SLOTS := 5

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
var _heroes: Array = []
var _selected_hero_id: int = -1

func _ready() -> void:
	$VBox/Header/BackButton.pressed.connect(func(): open_player_hub.emit())
	delete_hero_button.pressed.connect(_on_delete_hero)
	equip_shirt.equip_slot_selected.connect(_on_equip_slot_selected)
	equip_pants.equip_slot_selected.connect(_on_equip_slot_selected)
	equip_shoes.equip_slot_selected.connect(_on_equip_slot_selected)
	popup_recipe.craft_requested.connect(_on_popup_craft_requested)
	if LocalizationManager.locale_changed.is_connected(_on_locale_changed) == false:
		LocalizationManager.locale_changed.connect(_on_locale_changed)
	_apply_translations()

func bind_controllers(player_data: Node, inventory_controller: Node, craft_controller: Node) -> void:
	_player_data = player_data
	_inventory_controller = inventory_controller
	_craft_controller = craft_controller

	_connect_if_needed(_inventory_controller.items_changed, _refresh_items)
	_connect_if_needed(_inventory_controller.recipes_changed, _refresh_recipes)
	_connect_if_needed(_inventory_controller.equipment_changed, _refresh_equipment)
	_connect_if_needed(_craft_controller.recipe_preview_changed, _on_recipe_preview)
	_connect_if_needed(_craft_controller.craft_result, _on_craft_result)
	_connect_if_needed(HeroManager.heroes_updated, _on_heroes_updated)
	_connect_if_needed(HeroManager.active_hero_changed, _on_active_hero_changed)
	_connect_if_needed(AppState.heroes_updated, _on_appstate_heroes_updated)

	_refresh_items(_inventory_controller.get_items())
	_refresh_recipes(_inventory_controller.get_recipes())
	_refresh_heroes(_heroes_from_state())
	_refresh_equipment(_inventory_controller.get_selected_hero_equipment())
	_on_active_hero_changed(HeroManager.get_active_hero_id())
	_on_resources_changed({})
	call_deferred("_refresh_from_server")

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

func _refresh_heroes(heroes_list: Array) -> void:
	self._heroes = []
	for hero_variant in heroes_list:
		if hero_variant is Dictionary:
			self._heroes.append((hero_variant as Dictionary).duplicate(true))
	_clear_children(heroes_grid)
	var slots: Array = _hero_slots_from_state(self._heroes)
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
	popup_recipe.set_recipe(recipe, _resources_from_inventory(), can_craft)

func _on_resources_changed(_resources: Dictionary) -> void:
	if _selected_recipe.is_empty() == false:
		_craft_controller.preview_recipe(_selected_recipe)

func _on_popup_craft_requested(recipe_id: String) -> void:
	await _craft_controller.craft_recipe(recipe_id)
	await _refresh_from_server()

func _on_craft_result(_success: bool, _message: String) -> void:
	_refresh_items(_inventory_controller.get_items())

func _on_equip_slot_selected(slot_name: String) -> void:
	if _selected_item_id.is_empty():
		return
	await _inventory_controller.equip_item_to_selected_hero(_selected_item_id, slot_name)
	await _refresh_from_server()
	_refresh_equipment(_inventory_controller.get_selected_hero_equipment())

func _on_hero_slot_selected(index: int) -> void:
	if index < 0 or index >= _heroes.size():
		return
	var hero := _heroes[index] as Dictionary
	var hero_id: int = int(hero.get("id", -1))
	if hero_id <= 0:
		return
	HeroManager.set_active_hero_id(hero_id)

func _on_hero_selected(hero: Dictionary) -> void:
	delete_hero_button.disabled = hero.is_empty()
	_refresh_heroes(self._heroes)
	_refresh_equipment(_inventory_controller.get_selected_hero_equipment())

func _on_delete_hero() -> void:
	delete_hero_button.disabled = true

func _is_selected_hero(hero: Dictionary) -> bool:
	if hero.is_empty():
		return false
	if _selected_hero_id <= 0:
		return false
	return int(hero.get("id", -1)) == _selected_hero_id

func _clear_children(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()

func _on_locale_changed(_locale_code: String) -> void:
	_apply_translations()

func _apply_translations() -> void:
	$VBox/Header/BackButton.text = tr("ui.common.back")
	$VBox/Header/Title.text = tr("ui.storage.title")
	$VBox/Body/EquipmentPanel/EquipmentTitle.text = tr("ui.storage.equipment")
	delete_hero_button.text = tr("ui.storage.delete_hero")
	var tabs: TabContainer = $VBox/Body/Tabs
	tabs.set_tab_title(0, tr("ui.storage.items"))
	tabs.set_tab_title(1, tr("ui.storage.recipes"))
	tabs.set_tab_title(2, tr("ui.storage.heroes"))

func _refresh_from_server() -> void:
	await HeroManager.load_heroes()
	_refresh_heroes(_heroes_from_state())
	_on_active_hero_changed(HeroManager.get_active_hero_id())
	if _inventory_controller != null and _inventory_controller.has_method("refresh_items_from_server"):
		await _inventory_controller.refresh_items_from_server()
	_refresh_items(_inventory_controller.get_items())
	_refresh_equipment(_inventory_controller.get_selected_hero_equipment())

func _on_heroes_updated(heroes: Array[Dictionary]) -> void:
	var normalized: Array = []
	for hero in heroes:
		normalized.append((hero as Dictionary).duplicate(true))
	_refresh_heroes(normalized)

func _on_appstate_heroes_updated(heroes: Array) -> void:
	_refresh_heroes(heroes)

func _on_active_hero_changed(hero_id: int) -> void:
	_selected_hero_id = hero_id
	delete_hero_button.disabled = hero_id <= 0
	if _inventory_controller != null and _inventory_controller.has_method("refresh_items_from_server"):
		call_deferred("_refresh_inventory_after_hero_change")
	_refresh_heroes(self._heroes)

func _refresh_inventory_after_hero_change() -> void:
	await _inventory_controller.refresh_items_from_server()
	_refresh_items(_inventory_controller.get_items())
	_refresh_equipment(_inventory_controller.get_selected_hero_equipment())

func _heroes_from_state() -> Array:
	var result: Array = []
	for hero_variant in AppState.heroes:
		if hero_variant is Dictionary:
			result.append((hero_variant as Dictionary).duplicate(true))
	return result

func _hero_slots_from_state(heroes_source: Array) -> Array:
	var slots: Array = []
	for i: int in range(MAX_HERO_SLOTS):
		if i < heroes_source.size() and heroes_source[i] is Dictionary:
			slots.append((heroes_source[i] as Dictionary).duplicate(true))
		else:
			slots.append({})
	return slots

func _resources_from_inventory() -> Dictionary:
	var resources: Dictionary = {}
	if _inventory_controller == null:
		return resources
	for item_variant in _inventory_controller.get_items():
		if item_variant is Dictionary == false:
			continue
		var item := item_variant as Dictionary
		var key: String = str(item.get("resource_key", item.get("key", item.get("name", "")))).strip_edges()
		if key.is_empty():
			continue
		resources[key] = int(item.get("quantity", item.get("count", 0)))
	return resources
