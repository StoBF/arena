extends GutTest

var panel

func before_each():
    panel = preload("res://scripts/ui/InventoryQuantum.gd").new()
    # configure simple resources/recipes
    panel.resources = {"Quantum Dust": 5, "Nano Gel": 2}
    panel.recipes = [
        {"id": 1, "name": "Headgear", "short_desc": "Nice headgear.",
         "output_slot": "Helmet", "mutation_chance": 0.0,
         "requirements": {"Quantum Dust": 3},
         "icon": preload("res://assets/icons/helmet.png")},
        {"id": 2, "name": "Boots", "short_desc": "Fast boots.",
         "output_slot": "Boots", "mutation_chance": 0.0,
         "requirements": {"Nano Gel": 5},
         "icon": preload("res://assets/icons/boots.png")}
    ]
    panel._populate_resources()
    panel._populate_recipes()
    panel.selected_recipe = null
    panel.crafted_equipment.clear()

func test_resources_shown():
    assert_eq(panel.resources_grid.get_child_count(), 2, "Should display two resources")

func test_recipes_shown():
    assert_eq(panel.recipes_grid.get_child_count(), 2, "Should display two recipes")

func test_craft_button_disables_by_default():
    assert_true(panel.craft_button.disabled)

func test_selecting_recipe_updates_button():
    panel._on_recipe_gui_input(InputEventMouseButton.new().set_button_index(BUTTON_LEFT).set_pressed(true), panel.recipes[0])
    assert_false(panel.craft_button.disabled, "Should enable craft button when resources are sufficient")

func test_craft_deducts_resources_and_adds_equipment():
    panel.selected_recipe = panel.recipes[0]
    panel._update_craft_button()
    panel._on_craft_pressed()
    # resources reduced by 3
    assert_eq(panel.resources["Quantum Dust"], 2)
    # crafted_equipment should contain one entry
    assert_eq(panel.crafted_equipment.size(), 1)
    var eq = panel.crafted_equipment[0]
    assert_eq(eq["slot"], "Helmet")
    assert_eq(eq["stability"], 0)

func test_craft_button_disables_when_insufficient():
    panel.selected_recipe = panel.recipes[1]
    panel._update_craft_button()
    assert_true(panel.craft_button.disabled, "Requires 5 Nano Gel but only 2 available")

func test_tooltip_shows_info():
    panel._on_recipe_hover(panel.recipes[0])
    assert_true(panel.tooltip.visible, "Tooltip should popup on hover")
    assert_match("Headgear", panel.tooltip.get_node("Label").text)
    panel._on_tooltip_hide()
    assert_false(panel.tooltip.visible)
