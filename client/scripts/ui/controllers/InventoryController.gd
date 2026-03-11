extends Node

signal items_changed(items: Array)
signal recipes_changed(recipes: Array)
signal equipment_changed(equipment: Dictionary)

const ITEM_DATA_PATH := "res://Data/ItemData.json"
const RECIPE_DATA_PATH := "res://Data/RecipeData.json"
const SUPPORTED_RECIPE_SCHEMA_VERSION := 1

var _item_data: Dictionary = {}
var _recipes: Array = []
var _items: Array = []
var _equipment_by_hero: Dictionary = {}
var _selected_hero_id: String = ""
var _player_data: Node = null

func _ready() -> void:
	_load_data()
	_seed_items()
	_emit_all()

func bind_player_data(player_data: Node) -> void:
	_player_data = player_data
	if _player_data != null:
		if _player_data.hero_selected.is_connected(_on_hero_selected) == false:
			_player_data.hero_selected.connect(_on_hero_selected)
		var hero: Dictionary = _player_data.get_selected_hero()
		_on_hero_selected(hero)
		call_deferred("_sync_from_server")

func _load_data() -> void:
	_item_data = _read_json_dict(ITEM_DATA_PATH)
	var recipe_data: Dictionary = _normalize_recipe_payload(_read_json_dict(RECIPE_DATA_PATH))
	_recipes.clear()
	for recipe_variant in (recipe_data.get("recipes", []) as Array):
		_recipes.append(UIModels.recipe(recipe_variant as Dictionary))

func _read_json_dict(path: String) -> Dictionary:
	if FileAccess.file_exists(path) == false:
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		return (parsed as Dictionary).duplicate(true)
	return {}

func _seed_items() -> void:
	_items.clear()
	for name in _item_data.keys():
		var data := _item_data[name] as Dictionary
		_items.append(UIModels.item({
			"id": "item_%s" % str(name).to_lower().replace(" ", "_"),
			"name": str(name),
			"quantity": 3,
			"category": str(data.get("ItemCategory", "")),
			"icon": str(data.get("Icon", ""))
		}))

func _emit_all() -> void:
	items_changed.emit(get_items())
	recipes_changed.emit(get_recipes())
	equipment_changed.emit(get_selected_hero_equipment())

func get_items() -> Array:
	var result: Array = []
	for item in _items:
		result.append(UIModels.item(item as Dictionary))
	return result

func get_recipes() -> Array:
	var result: Array = []
	for recipe in _recipes:
		result.append(UIModels.recipe(recipe as Dictionary))
	return result

func get_selected_hero_equipment() -> Dictionary:
	if AppState.current_hero_id <= 0:
		return UIModels.equipment({})
	return UIModels.equipment(InventoryManager.get_equipment(AppState.current_hero_id))

func equip_item_to_selected_hero(item_id: String, _slot_name: String) -> bool:
	var parsed_item_id: int = int(item_id)
	if parsed_item_id <= 0:
		return false
	var ok: bool = await InventoryManager.equip_item_for_active_hero(parsed_item_id)
	if ok == false:
		return false
	await refresh_items_from_server()
	equipment_changed.emit(get_selected_hero_equipment())
	return true

func add_item_by_name(item_name: String, amount: int) -> void:
	if amount <= 0:
		return
	for i: int in range(_items.size()):
		var item := _items[i] as Dictionary
		if str(item.get("name", "")) == item_name:
			item["quantity"] = int(item.get("quantity", 0)) + amount
			_items[i] = UIModels.item(item)
			items_changed.emit(get_items())
			return
	var data := _item_data.get(item_name, {}) as Dictionary
	_items.append(UIModels.item({
		"id": "item_%s" % item_name.to_lower().replace(" ", "_"),
		"name": item_name,
		"quantity": amount,
		"category": str(data.get("ItemCategory", "")),
		"icon": str(data.get("Icon", ""))
	}))
	items_changed.emit(get_items())

func list_item_for_sale(item_id: String) -> bool:
	for i: int in range(_items.size()):
		var item := _items[i] as Dictionary
		if str(item.get("id", "")) != item_id:
			continue
		var qty: int = int(item.get("quantity", 0))
		if qty <= 0:
			return false
		item["quantity"] = qty - 1
		_items[i] = UIModels.item(item)
		items_changed.emit(get_items())
		return true
	return false

func _find_item(item_id: String) -> Dictionary:
	for item in _items:
		var entry := item as Dictionary
		if str(entry.get("id", "")) == item_id:
			return UIModels.item(entry)
	return {}

func _is_valid_for_slot(item: Dictionary, slot_name: String) -> bool:
	var category: String = str(item.get("category", ""))
	if slot_name == "shirt":
		return category == "Shirt"
	if slot_name == "pants":
		return category == "Pants"
	if slot_name == "shoes":
		return category == "Shoes"
	return false

func _on_hero_selected(hero: Dictionary) -> void:
	_selected_hero_id = str(hero.get("id", ""))
	if hero.has("id"):
		HeroManager.set_active_hero_id(int(hero.get("id", AppState.current_hero_id)))
	equipment_changed.emit(get_selected_hero_equipment())

func refresh_items_from_server() -> void:
	await _sync_from_server()

func _sync_from_server() -> void:
	var server_items: Array = await InventoryManager.get_items()
	_items.clear()
	for item_variant in server_items:
		if item_variant is Dictionary:
			_items.append(UIModels.item(item_variant as Dictionary))
	items_changed.emit(get_items())
	equipment_changed.emit(get_selected_hero_equipment())

func _normalize_recipe_payload(payload: Dictionary) -> Dictionary:
	if payload.has("schema_version") == false and payload.has("recipes") == false and payload.has("id"):
		return {
			"schema_version": SUPPORTED_RECIPE_SCHEMA_VERSION,
			"recipes": [payload.duplicate(true)],
		}

	var schema_version: int = int(payload.get("schema_version", 0))
	if schema_version <= 0:
		return {
			"schema_version": SUPPORTED_RECIPE_SCHEMA_VERSION,
			"recipes": (payload.get("recipes", []) as Array).duplicate(true),
		}

	if schema_version != SUPPORTED_RECIPE_SCHEMA_VERSION:
		push_warning("[InventoryController] Unsupported recipe schema_version=%d. Applying safe defaults." % schema_version)

	return {
		"schema_version": SUPPORTED_RECIPE_SCHEMA_VERSION,
		"recipes": (payload.get("recipes", []) as Array).duplicate(true),
	}
