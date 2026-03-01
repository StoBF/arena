extends Control
class_name InventoryPanelQuantum

signal recipe_selected(recipe_id)
signal craft_pressed(recipe_id)

# node references
@onready var resources_grid = $ResourcesGrid
@onready var recipes_grid = $RecipesGrid
@onready var craft_button = $CraftButton
@onready var tooltip = $Tooltip

# data containers
var resources := {}            # name -> quantity
var recipes := []              # list of dicts representing recipes
var selected_recipe = null
var crafted_equipment := []     # list of generated equipment dictionaries

func _ready():
    # TopBar replaces the old BackToDashboardButton
    TopBar.add_to(self, true, true)
    print("[InventoryQuantum] _ready() START")

    craft_button.disabled = true
    craft_button.pressed.connect(Callable(self, "_on_craft_pressed"))

    # example placeholder data
    resources = {"Quantum Dust": 10, "Nano Gel": 5}
    recipes = [
        {"id": 1, "name": "Dusty Helmet", "short_desc": "A simple helmet.",
         "output_slot": "Helmet", "mutation_chance": 0.2,
         "requirements": {"Quantum Dust": 3},
         "icon": null},
        {"id": 2, "name": "Nano Boots", "short_desc": "Sturdy boots.",
         "output_slot": "Boots", "mutation_chance": 0.0,
         "requirements": {"Nano Gel": 2},
         "icon": null}
    ]

    _populate_resources()
    _populate_recipes()

func _clear_grid(grid: GridContainer) -> void:
    for child in grid.get_children():
        child.queue_free()

func _populate_resources():
    _clear_grid(resources_grid)
    for res_name in resources.keys():
        var qty = resources[res_name]
        var h = HBoxContainer.new()
        var icon = TextureRect.new()
        icon.custom_minimum_size = Vector2(32, 32)
        h.add_child(icon)
        var l = Label.new()
        l.text = "%s: %d" % [res_name, qty]
        h.add_child(l)
        h.mouse_entered.connect(_on_resource_hover.bind(res_name))
        h.mouse_exited.connect(_on_tooltip_hide)
        resources_grid.add_child(h)

func _populate_recipes():
    _clear_grid(recipes_grid)
    for recipe in recipes:
        var v = VBoxContainer.new()
        v.name = str(recipe.id)
        var icon = TextureRect.new()
        if recipe.icon:
            icon.texture = recipe.icon
        icon.custom_minimum_size = Vector2(48, 48)
        v.add_child(icon)
        var nlabel = Label.new()
        nlabel.text = recipe.name
        v.add_child(nlabel)
        var dlabel = Label.new()
        dlabel.text = recipe.short_desc
        v.add_child(dlabel)
        v.mouse_filter = Control.MOUSE_FILTER_STOP
        v.gui_input.connect(_on_recipe_gui_input.bind(recipe))
        v.mouse_entered.connect(_on_recipe_hover.bind(recipe))
        v.mouse_exited.connect(_on_tooltip_hide)
        recipes_grid.add_child(v)

func _on_recipe_gui_input(event: InputEvent, recipe: Dictionary) -> void:
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        selected_recipe = recipe
        recipe_selected.emit(recipe.id)
        _update_craft_button()

func _update_craft_button():
    if selected_recipe == null:
        craft_button.disabled = true
        return
    craft_button.disabled = not _has_resources_for_recipe(selected_recipe)

func _has_resources_for_recipe(recipe: Dictionary) -> bool:
    for res_name in recipe.requirements.keys():
        if resources.get(res_name, 0) < recipe.requirements[res_name]:
            return false
    return true

func _on_craft_pressed():
    if not selected_recipe:
        return
    if not _has_resources_for_recipe(selected_recipe):
        return

    # deduct resources
    for res_name in selected_recipe.requirements.keys():
        resources[res_name] -= selected_recipe.requirements[res_name]
    _populate_resources()

    # create equipment dict
    var equipment = {
        "slot": selected_recipe.output_slot,
        "stability": 0,
        "energy": 0,
        "durability": 0,
        "mutation_chance": selected_recipe.mutation_chance,
        "effects": []
    }
    # apply mutation if chance succeeds
    if equipment.mutation_chance > 0 and randf() < equipment.mutation_chance:
        var choices = ["Photon Surge", "Quantum Shield", "Temporal Boost"]
        var eff = choices[randi() % choices.size()]
        equipment.effects.append({"name": eff})
    crafted_equipment.append(equipment)

    craft_pressed.emit(selected_recipe.id)
    _update_craft_button()

func _on_recipe_hover(recipe: Dictionary) -> void:
    var text = "%s\nRequirements:" % recipe.name
    for res_name in recipe.requirements.keys():
        text += "\n - %s x%d" % [res_name, recipe.requirements[res_name]]
    _show_tooltip(text)

func _on_resource_hover(res_name: String) -> void:
    var qty = resources.get(res_name, 0)
    _show_tooltip("%s: %d in warehouse" % [res_name, qty])

func _show_tooltip(text: String) -> void:
    if tooltip:
        tooltip.get_node("Label").text = text
        tooltip.popup()

func _on_tooltip_hide() -> void:
    if tooltip:
        tooltip.hide()
