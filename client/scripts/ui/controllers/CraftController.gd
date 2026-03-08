extends Node

signal recipe_preview_changed(recipe: Dictionary, can_craft: bool)
signal craft_result(success: bool, message: String)

var _player_data: Node = null
var _inventory_controller: Node = null

func bind_controllers(player_data: Node, inventory_controller: Node) -> void:
	_player_data = player_data
	_inventory_controller = inventory_controller

func preview_recipe(recipe: Dictionary) -> void:
	var can: bool = can_craft(recipe)
	recipe_preview_changed.emit(recipe.duplicate(true), can)

func can_craft(recipe: Dictionary) -> bool:
	if _player_data == null:
		return false
	var requirements := recipe.get("requirements", {}) as Dictionary
	return _player_data.can_consume_resources(requirements)

func craft_recipe(recipe_id: String) -> void:
	if _player_data == null or _inventory_controller == null:
		craft_result.emit(false, "Controllers are not bound")
		return
	var recipes: Array = _inventory_controller.get_recipes()
	for recipe_variant in recipes:
		var recipe := recipe_variant as Dictionary
		if str(recipe.get("id", "")) != recipe_id:
			continue
		if can_craft(recipe) == false:
			craft_result.emit(false, "Not enough resources")
			return
		var requirements := recipe.get("requirements", {}) as Dictionary
		if _player_data.consume_resources(requirements) == false:
			craft_result.emit(false, "Resource consume failed")
			return
		_inventory_controller.add_item_by_name(str(recipe.get("output_item", "")), int(recipe.get("output_quantity", 1)))
		craft_result.emit(true, "Crafted %s" % str(recipe.get("name", "Item")))
		return
	craft_result.emit(false, "Recipe not found")
