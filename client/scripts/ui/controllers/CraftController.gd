extends Node

signal recipe_preview_changed(recipe: Dictionary, can_craft: bool)
signal craft_result(success: bool, message: String)

var _player_data: Node = null
var _inventory_controller: Node = null

func bind_controllers(player_data: Node, inventory_controller: Node) -> void:
	_player_data = player_data
	_inventory_controller = inventory_controller

func preview_recipe(recipe: Dictionary) -> void:
	var normalized := UIModels.recipe(recipe)
	var can: bool = can_craft(normalized)
	recipe_preview_changed.emit(normalized, can)

func can_craft(recipe: Dictionary) -> bool:
	if _inventory_controller == null:
		return false
	var requirements := recipe.get("requirements", {}) as Dictionary
	var available: Dictionary = _collect_available_resources()
	for key in requirements.keys():
		var needed: int = int(requirements.get(key, 0))
		if int(available.get(str(key), 0)) < needed:
			return false
	return true

func craft_recipe(recipe_id: String) -> void:
	if _player_data == null or _inventory_controller == null:
		craft_result.emit(false, "Controllers are not bound")
		return
	var endpoint: String = "/workshop/craft/%s" % recipe_id
	var response: Dictionary = await ApiClient.request_post(endpoint, {})
	if bool(response.get("ok", false)) == false:
		craft_result.emit(false, str(response.get("message", "Craft failed")))
		return

	await InventoryManager.get_items()
	await HeroManager.load_heroes()
	await _refresh_profile_from_server()
	if _inventory_controller.has_method("refresh_items_from_server"):
		await _inventory_controller.refresh_items_from_server()
	craft_result.emit(true, "Craft completed")

func _refresh_profile_from_server() -> void:
	var profile_response: Dictionary = await ApiClient.get_user()
	if bool(profile_response.get("ok", false)) == false:
		return
	var parsed: Variant = profile_response.get("data", {})
	if parsed is Dictionary:
		var profile := parsed as Dictionary
		if profile.has("result") and profile["result"] is Dictionary:
			AppState.set_user_data((profile["result"] as Dictionary).duplicate(true))
			return
		AppState.set_user_data(profile.duplicate(true))

func _collect_available_resources() -> Dictionary:
	var resources: Dictionary = {}
	if _inventory_controller == null:
		return resources
	if _inventory_controller.has_method("get_items") == false:
		return resources
	var items: Array = _inventory_controller.get_items()
	for item_variant in items:
		if item_variant is Dictionary == false:
			continue
		var item := item_variant as Dictionary
		var key: String = str(item.get("resource_key", item.get("key", item.get("name", "")))).strip_edges()
		if key.is_empty():
			continue
		resources[key] = int(item.get("quantity", item.get("count", 0)))
	return resources
