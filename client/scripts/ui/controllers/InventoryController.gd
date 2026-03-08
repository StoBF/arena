extends Node

signal items_changed(items: Array)
signal recipes_changed(recipes: Array)
signal equipment_changed(equipment: Dictionary)

const ITEM_DATA_PATH := "res://Data/ItemData.json"
const RECIPE_DATA_PATH := "res://Data/RecipeData.json"

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

func _load_data() -> void:
	_item_data = _read_json_dict(ITEM_DATA_PATH)
	var recipe_data: Dictionary = _read_json_dict(RECIPE_DATA_PATH)
	_recipes = (recipe_data.get("recipes", []) as Array).duplicate(true)

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
		_items.append({
			"id": "item_%s" % str(name).to_lower().replace(" ", "_"),
			"name": str(name),
			"quantity": 3,
			"category": str(data.get("ItemCategory", "")),
			"icon": str(data.get("Icon", ""))
		})

func _emit_all() -> void:
	items_changed.emit(get_items())
	recipes_changed.emit(get_recipes())
	equipment_changed.emit(get_selected_hero_equipment())

func get_items() -> Array:
	return _items.duplicate(true)

func get_recipes() -> Array:
	return _recipes.duplicate(true)

func get_selected_hero_equipment() -> Dictionary:
	if _selected_hero_id.is_empty():
		return {"shirt": {}, "pants": {}, "shoes": {}}
	if _equipment_by_hero.has(_selected_hero_id) == false:
		_equipment_by_hero[_selected_hero_id] = {"shirt": {}, "pants": {}, "shoes": {}}
	return (_equipment_by_hero[_selected_hero_id] as Dictionary).duplicate(true)

func equip_item_to_selected_hero(item_id: String, slot_name: String) -> bool:
	if _selected_hero_id.is_empty():
		return false
	var item := _find_item(item_id)
	if item.is_empty():
		return false
	if _is_valid_for_slot(item, slot_name) == false:
		return false
	if _equipment_by_hero.has(_selected_hero_id) == false:
		_equipment_by_hero[_selected_hero_id] = {"shirt": {}, "pants": {}, "shoes": {}}
	var equipment := _equipment_by_hero[_selected_hero_id] as Dictionary
	equipment[slot_name] = item.duplicate(true)
	equipment_changed.emit(get_selected_hero_equipment())
	return true

func add_item_by_name(item_name: String, amount: int) -> void:
	if amount <= 0:
		return
	for i: int in range(_items.size()):
		var item := _items[i] as Dictionary
		if str(item.get("name", "")) == item_name:
			item["quantity"] = int(item.get("quantity", 0)) + amount
			_items[i] = item
			items_changed.emit(get_items())
			return
	var data := _item_data.get(item_name, {}) as Dictionary
	_items.append({
		"id": "item_%s" % item_name.to_lower().replace(" ", "_"),
		"name": item_name,
		"quantity": amount,
		"category": str(data.get("ItemCategory", "")),
		"icon": str(data.get("Icon", ""))
	})
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
		_items[i] = item
		items_changed.emit(get_items())
		return true
	return false

func _find_item(item_id: String) -> Dictionary:
	for item in _items:
		var entry := item as Dictionary
		if str(entry.get("id", "")) == item_id:
			return entry.duplicate(true)
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
	equipment_changed.emit(get_selected_hero_equipment())
