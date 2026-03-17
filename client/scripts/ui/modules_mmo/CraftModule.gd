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
	if LocalizationManager.locale_changed.is_connected(_on_locale_changed) == false:
		LocalizationManager.locale_changed.connect(_on_locale_changed)
	call_deferred("_apply_cabinet_visuals")
	call_deferred("_apply_translations")
	_load_recipes()

func _exit_tree() -> void:
	if LocalizationManager.locale_changed.is_connected(_on_locale_changed):
		LocalizationManager.locale_changed.disconnect(_on_locale_changed)

func _on_locale_changed(_locale_code: String) -> void:
	_apply_translations()

func _apply_cabinet_visuals() -> void:
	CabinetStyle.style_screen(self)
	if _status_label != null:
		CabinetStyle.style_status_label(_status_label)

func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	CabinetStyle.style_module_root(root)
	add_child(root)

	# Header
	var header := ModuleHeader.new()
	header.name = "ModuleHeader"
	root.add_child(header)
	if header.has_method("set_title"):
		header.set_title(CabinetStyle.text("ui.craft.title", "Workshop"))
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
	_craft_button.text = CabinetStyle.text("ui.craft.craft_button", "Craft")
	_craft_button.custom_minimum_size = Vector2(0, 40)
	_craft_button.pressed.connect(_on_craft_pressed)
	right_vbox.add_child(_craft_button)

	# Status
	_status_label = Label.new()
	_status_label.text = ""
	root.add_child(_status_label)

func _load_recipes() -> void:
	_status_label.text = CabinetStyle.text("ui.craft.loading", "Loading recipes...")
	_loading_overlay.show_loading()
	_empty_state.visible = false
	_loading_overlay.hide_loading()
	# Craft API is not implemented in this client/backend contract yet.
	# Keep failure explicit and testable; do not fake recipe availability.
	_recipes = []
	_render_recipes()

func _render_recipes() -> void:
	_recipe_list.clear()
	if _recipes.is_empty():
		_empty_state.visible = true
		if _empty_state.has_method("set_content"):
			_empty_state.set_content(
				CabinetStyle.text("ui.craft.unavailable_title", "Crafting Unavailable"),
				CabinetStyle.text("ui.craft.unavailable_hint", "Crafting is not available on this backend yet.")
			)
		_status_label.text = CabinetStyle.text("ui.craft.unavailable_status", "Crafting is currently unavailable")
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
	UIUtils.show_error(CabinetStyle.text("ui.craft.unavailable_action", "Crafting is not available on this backend"))
	_status_label.text = CabinetStyle.text("ui.craft.unavailable_status", "Crafting is currently unavailable")

func _apply_translations() -> void:
	var header: ModuleHeader = get_node_or_null("VBoxContainer/ModuleHeader") as ModuleHeader
	if header != null:
		header.set_title(CabinetStyle.text("ui.craft.title", "Workshop"))
	if _craft_button != null:
		_craft_button.text = CabinetStyle.text("ui.craft.craft_button", "Craft")
	if _recipes.is_empty() and _empty_state != null and _empty_state.has_method("set_content"):
		_empty_state.set_content(
			CabinetStyle.text("ui.craft.unavailable_title", "Crafting Unavailable"),
			CabinetStyle.text("ui.craft.unavailable_hint", "Crafting is not available on this backend yet.")
		)
