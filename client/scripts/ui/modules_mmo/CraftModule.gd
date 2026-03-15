extends Control

## CraftModule — recipe browser, resource requirements, craft action.

var _recipes: Array = []
var _selected_recipe: Dictionary = {}
var _loading_overlay: Node = null
var _empty_state: Node = null

# Programmatic UI nodes
var _recipe_list: ItemList = null
var _detail_panel: Node = null   # DetailPanel component
var _craft_button: Button = null
var _status_label: Label = null

func _ready() -> void:
	_build_ui()
	_load_recipes()

func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	# Header
	var header := ModuleHeader.new()
	root.add_child(header)
	if header.has_method("set_title"):
		header.set_title("Workshop")
	if header.has_signal("refresh_pressed"):
		header.refresh_pressed.connect(_load_recipes)

	# Body — split
	var body := HSplitContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.split_offset = 400
	root.add_child(body)

	# Left — recipe list
	var left_panel := PanelContainer.new()
	left_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(left_panel)

	var left_vbox := VBoxContainer.new()
	left_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_panel.add_child(left_vbox)

	_recipe_list = ItemList.new()
	_recipe_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_recipe_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_recipe_list.item_selected.connect(_on_recipe_selected)
	left_vbox.add_child(_recipe_list)

	_loading_overlay = LoadingOverlay.new()
	left_panel.add_child(_loading_overlay)

	_empty_state = EmptyState.new()
	_empty_state.visible = false
	left_vbox.add_child(_empty_state)

	# Right — detail + craft
	var right_panel := PanelContainer.new()
	right_panel.custom_minimum_size = Vector2(300, 0)
	right_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(right_panel)

	var right_vbox := VBoxContainer.new()
	right_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_vbox.add_theme_constant_override("separation", 10)
	right_panel.add_child(right_vbox)

	_detail_panel = DetailPanel.new()
	_detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_vbox.add_child(_detail_panel)

	_craft_button = Button.new()
	_craft_button.text = "Craft"
	_craft_button.custom_minimum_size = Vector2(0, 40)
	_craft_button.pressed.connect(_on_craft_pressed)
	right_vbox.add_child(_craft_button)

	# Status
	_status_label = Label.new()
	_status_label.text = ""
	root.add_child(_status_label)

func _load_recipes() -> void:
	_status_label.text = "Loading recipes..."
	_loading_overlay.show_loading()
	_empty_state.visible = false
	# Attempt to fetch recipes; API may not exist yet
	if ApiClient.has_method("get_recipes"):
		var response: Dictionary = await ApiClient.get_recipes()
		_loading_overlay.hide_loading()
		if bool(response.get("ok", false)):
			_recipes = ResponseParser.extract_array(response.get("data", {}))
		else:
			_recipes = []
	else:
		_loading_overlay.hide_loading()
		# Placeholder static data
		_recipes = [
			{"id": 1, "name": "Iron Sword", "materials": "Iron Ingot x3", "level_req": 1, "description": "A basic iron sword."},
			{"id": 2, "name": "Health Potion", "materials": "Herb x2, Water x1", "level_req": 1, "description": "Restores a small amount of HP."},
			{"id": 3, "name": "Steel Armor", "materials": "Steel Plate x4, Leather x2", "level_req": 5, "description": "Sturdy steel armor."},
		]
	_render_recipes()

func _render_recipes() -> void:
	_recipe_list.clear()
	if _recipes.is_empty():
		_empty_state.visible = true
		if _empty_state.has_method("set_content"):
			_empty_state.set_content("No Recipes", "No crafting recipes available.")
		_status_label.text = ""
		return
	_empty_state.visible = false
	for recipe_variant in _recipes:
		if not recipe_variant is Dictionary:
			continue
		var r := recipe_variant as Dictionary
		_recipe_list.add_item(str(r.get("name", "Unknown")))
	_status_label.text = "%d recipes" % _recipes.size()

func _on_recipe_selected(index: int) -> void:
	if index < 0 or index >= _recipes.size():
		return
	_selected_recipe = _recipes[index] as Dictionary
	if _detail_panel != null and _detail_panel.has_method("set_title"):
		_detail_panel.set_title(str(_selected_recipe.get("name", "Recipe")))
	if _detail_panel != null and _detail_panel.has_method("set_fields"):
		_detail_panel.set_fields({
			"Materials": str(_selected_recipe.get("materials", "-")),
			"Level Req": str(_selected_recipe.get("level_req", "-")),
			"Description": str(_selected_recipe.get("description", "")),
		})

func _on_craft_pressed() -> void:
	if _selected_recipe.is_empty():
		UIUtils.show_warning("Select a recipe first")
		return
	var recipe_id: int = int(_selected_recipe.get("id", -1))
	if recipe_id < 0:
		return
	_status_label.text = "Crafting..."
	if ApiClient.has_method("craft_item"):
		var response: Dictionary = await ApiClient.craft_item(recipe_id)
		if bool(response.get("ok", false)):
			UIUtils.show_success("Crafted %s!" % str(_selected_recipe.get("name", "item")))
		else:
			UIUtils.show_error(str(response.get("message", "Craft failed")))
	else:
		UIUtils.show_info("Crafting %s (API coming soon)" % str(_selected_recipe.get("name", "item")))
	_status_label.text = ""
