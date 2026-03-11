extends GutTest

func test_player_data_normalizes_legacy_payload_without_schema() -> void:
	var player_data := preload("res://scripts/ui/controllers/PlayerData.gd").new()
	var legacy_payload := {
		"heroes": [
			{"id": "h1", "name": "LegacyHero"}
		],
		"resources": {"wood": 5, "ore": 3}
	}

	var normalized: Dictionary = player_data._normalize_hero_payload(legacy_payload)
	assert_eq(int(normalized.get("schema_version", -1)), 1)
	assert_eq((normalized.get("heroes", []) as Array).size(), 1)
	assert_eq(str(((normalized.get("heroes", []) as Array)[0] as Dictionary).get("id", "")), "h1")
	assert_eq(int((normalized.get("resources", {}) as Dictionary).get("wood", -1)), 5)

func test_player_data_handles_unsupported_schema_safely() -> void:
	var player_data := preload("res://scripts/ui/controllers/PlayerData.gd").new()
	var payload := {
		"schema_version": 99,
		"heroes": [{"id": "h2", "name": "FutureHero"}],
		"resources": {"herb": 7}
	}

	var normalized: Dictionary = player_data._normalize_hero_payload(payload)
	assert_eq(int(normalized.get("schema_version", -1)), 1)
	assert_eq((normalized.get("heroes", []) as Array).size(), 1)
	assert_eq(int((normalized.get("resources", {}) as Dictionary).get("herb", -1)), 7)

func test_inventory_controller_normalizes_single_recipe_legacy_shape() -> void:
	var inventory_controller := preload("res://scripts/ui/controllers/InventoryController.gd").new()
	var legacy_single := {
		"id": "legacy_recipe",
		"name": "Legacy Potion",
		"output_item": "Slime Potion",
		"output_quantity": 1,
		"requirements": {"herb": 2}
	}

	var normalized: Dictionary = inventory_controller._normalize_recipe_payload(legacy_single)
	assert_eq(int(normalized.get("schema_version", -1)), 1)
	var recipes := normalized.get("recipes", []) as Array
	assert_eq(recipes.size(), 1)
	assert_eq(str((recipes[0] as Dictionary).get("id", "")), "legacy_recipe")

func test_inventory_controller_normalizes_recipes_without_schema() -> void:
	var inventory_controller := preload("res://scripts/ui/controllers/InventoryController.gd").new()
	var payload := {
		"recipes": [
			{
				"id": "r1",
				"name": "Recipe One",
				"output_item": "Iron Sword",
				"output_quantity": 1,
				"requirements": {"ore": 2}
			}
		]
	}

	var normalized: Dictionary = inventory_controller._normalize_recipe_payload(payload)
	assert_eq(int(normalized.get("schema_version", -1)), 1)
	assert_eq((normalized.get("recipes", []) as Array).size(), 1)
	assert_eq(str(((normalized.get("recipes", []) as Array)[0] as Dictionary).get("id", "")), "r1")
