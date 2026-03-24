extends Control

## CraftModule — recipe browser, resource requirements, craft action.

var _recipes: Array = []
var _craft_queue: Array = []
var _selected_recipe: Dictionary = {}
var _loading_overlay: Node = null
var _empty_state: Node = null

var _recipe_list: ItemList = null
var _detail_panel: Node = null
var _craft_button: Button = null
var _finish_button: Button = null
var _queue_list: ItemList = null
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
		header.set_title(CabinetStyle.text("ui.craft.title", "Crafting"))
	if header.has_signal("refresh_pressed"):
		header.refresh_pressed.connect(_load_recipes)

	# Body — left/right split
	var body := HSplitContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.split_offset = 400
	root.add_child(body)

	# ── Left: recipe list ──────────────────────────────────────────────────
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

	# ── Right: detail + craft + queue ──────────────────────────────────────
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
	_craft_button.disabled = true
	_craft_button.pressed.connect(_on_craft_pressed)
	right_vbox.add_child(_craft_button)

	# Craft queue section
	var queue_lbl := Label.new()
	queue_lbl.text = CabinetStyle.text("ui.craft.queue_title", "Craft Queue")
	queue_lbl.add_theme_font_size_override("font_size", 13)
	queue_lbl.add_theme_color_override("font_color", Color(0.7, 0.73, 0.82))
	right_vbox.add_child(queue_lbl)

	_queue_list = ItemList.new()
	_queue_list.custom_minimum_size = Vector2(0, 80)
	_queue_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_vbox.add_child(_queue_list)

	_finish_button = Button.new()
	_finish_button.text = CabinetStyle.text("ui.craft.finish_button", "Finish Crafting")
	_finish_button.custom_minimum_size = Vector2(0, 36)
	_finish_button.disabled = true
	_finish_button.pressed.connect(_on_finish_pressed)
	right_vbox.add_child(_finish_button)

	# Status bar
	_status_label = Label.new()
	_status_label.text = ""
	root.add_child(_status_label)


# ═══════════════════════════════════════════════════════════════════════════
#  LOADING
# ═══════════════════════════════════════════════════════════════════════════

func _load_recipes() -> void:
	_status_label.text = CabinetStyle.text("ui.craft.loading", "Loading recipes...")
	_loading_overlay.show_loading()
	_empty_state.visible = false
	_craft_button.disabled = true

	var response: Dictionary = await ApiClient.get_craft_recipes()
	_loading_overlay.hide_loading()

	if not bool(response.get("ok", false)):
		_recipes = []
		var err: String = str(response.get("error", response.get("message", "Request failed")))
		_status_label.text = "Failed to load recipes: " + err
		_render_recipes()
		return

	var raw: Variant = response.get("data", [])
	_recipes = raw if raw is Array else []
	_render_recipes()

	await _load_craft_queue()


func _load_craft_queue() -> void:
	var qr: Dictionary = await ApiClient.get_craft_queue()
	if bool(qr.get("ok", false)):
		var raw: Variant = qr.get("data", [])
		_craft_queue = raw if raw is Array else []
	else:
		_craft_queue = []
	_render_queue()


# ═══════════════════════════════════════════════════════════════════════════
#  RENDERING
# ═══════════════════════════════════════════════════════════════════════════

func _render_recipes() -> void:
	_recipe_list.clear()
	_selected_recipe = {}
	if _recipes.is_empty():
		_empty_state.visible = true
		if _empty_state.has_method("set_content"):
			_empty_state.set_content(
				CabinetStyle.text("ui.craft.empty_title", "No Recipes"),
				CabinetStyle.text("ui.craft.empty_hint", "No craft recipes available yet.")
			)
		_status_label.text = CabinetStyle.text("ui.craft.empty_status", "No recipes found")
		return
	_empty_state.visible = false
	for recipe_variant in _recipes:
		if not recipe_variant is Dictionary:
			continue
		var r := recipe_variant as Dictionary
		var label: String = "%s  [G%s]" % [str(r.get("name", "Unknown")), str(r.get("grade", "?"))]
		_recipe_list.add_item(label)
	_status_label.text = "%d recipes" % _recipes.size()


func _render_queue() -> void:
	if _queue_list == null:
		return
	_queue_list.clear()
	var now_unix: float = Time.get_unix_time_from_system()
	var has_ready: bool = false
	for entry_variant in _craft_queue:
		if not entry_variant is Dictionary:
			continue
		var entry := entry_variant as Dictionary
		var recipe_id: int = int(entry.get("recipe_id", -1))
		var ready_at_str: String = str(entry.get("ready_at", ""))
		var recipe_name: String = _recipe_name_by_id(recipe_id)
		var ready_unix: float = _parse_iso_to_unix(ready_at_str)
		var is_ready: bool = (ready_unix > 0.0 and now_unix >= ready_unix)
		var entry_text: String = "%s — %s" % [recipe_name, "Ready!" if is_ready else ready_at_str.left(16)]
		_queue_list.add_item(entry_text)
		if is_ready:
			has_ready = true
	_finish_button.disabled = not has_ready


# ═══════════════════════════════════════════════════════════════════════════
#  EVENT HANDLERS
# ═══════════════════════════════════════════════════════════════════════════

func _on_recipe_selected(index: int) -> void:
	if index < 0 or index >= _recipes.size():
		return
	_selected_recipe = _recipes[index] as Dictionary
	_craft_button.disabled = false

	if _detail_panel == null:
		return
	if _detail_panel.has_method("set_title"):
		_detail_panel.set_title(str(_selected_recipe.get("name", "Recipe")))
	if _detail_panel.has_method("set_fields"):
		var craft_secs: int = int(_selected_recipe.get("craft_time_sec", 0))
		var time_str: String = "%dm %ds" % [craft_secs / 60, craft_secs % 60]
		var resources: Array = _selected_recipe.get("resources", [])
		var res_parts: PackedStringArray = PackedStringArray()
		for rv in resources:
			if rv is Dictionary:
				var res := rv as Dictionary
				res_parts.append("ID %s ×%s" % [str(res.get("resource_id", "?")), str(res.get("quantity", "?"))])
		_detail_panel.set_fields({
			"Type": str(_selected_recipe.get("item_type", "-")),
			"Grade": str(_selected_recipe.get("grade", "-")),
			"Craft Time": time_str,
			"Drop Chance": "%.1f%%" % (float(_selected_recipe.get("drop_chance", 0.0)) * 100.0),
			"Resources": ", ".join(res_parts) if res_parts.size() > 0 else "None",
		})


func _on_craft_pressed() -> void:
	if _selected_recipe.is_empty():
		UIUtils.show_warning(CabinetStyle.text("ui.craft.select_recipe", "Select a recipe first"))
		return
	var recipe_id: int = int(_selected_recipe.get("id", -1))
	if recipe_id <= 0:
		UIUtils.show_error("Invalid recipe")
		return

	_craft_button.disabled = true
	_status_label.text = CabinetStyle.text("ui.craft.starting", "Starting craft...")

	var response: Dictionary = await ApiClient.start_craft(recipe_id)

	if bool(response.get("ok", false)):
		var data: Dictionary = response.get("data", {})
		var ready_at: String = str(data.get("ready_at", "")).left(16)
		UIUtils.show_success("Craft started! Ready at: " + ready_at)
		_status_label.text = "Crafting — ready at " + ready_at
		_craft_button.disabled = false
		await _load_craft_queue()
	else:
		var err: String = str(response.get("error", response.get("message", "Failed to start craft")))
		UIUtils.show_error(err)
		_status_label.text = "Craft failed: " + err
		_craft_button.disabled = false


func _on_finish_pressed() -> void:
	var now_unix: float = Time.get_unix_time_from_system()
	var queue_id: int = -1
	for entry_variant in _craft_queue:
		if not entry_variant is Dictionary:
			continue
		var entry := entry_variant as Dictionary
		var ready_unix: float = _parse_iso_to_unix(str(entry.get("ready_at", "")))
		if ready_unix > 0.0 and now_unix >= ready_unix:
			queue_id = int(entry.get("id", -1))
			break

	if queue_id <= 0:
		UIUtils.show_warning("No ready craft jobs found")
		return

	_finish_button.disabled = true
	_status_label.text = CabinetStyle.text("ui.craft.finishing", "Finishing craft...")

	var response: Dictionary = await ApiClient.finish_craft(queue_id)

	if bool(response.get("ok", false)):
		var data: Dictionary = response.get("data", {})
		var item_type: String = str(data.get("item_type", "item"))
		var grade: int = int(data.get("grade", 0))
		UIUtils.show_success("Crafted: %s (Grade %d)" % [item_type, grade])
		_status_label.text = "Craft complete!"
		await _load_craft_queue()
	else:
		var err: String = str(response.get("error", response.get("message", "Failed to finish craft")))
		UIUtils.show_error(err)
		_status_label.text = "Finish failed: " + err
		_finish_button.disabled = false


# ═══════════════════════════════════════════════════════════════════════════
#  HELPERS
# ═══════════════════════════════════════════════════════════════════════════

func _recipe_name_by_id(recipe_id: int) -> String:
	for r_var in _recipes:
		if r_var is Dictionary:
			var r := r_var as Dictionary
			if int(r.get("id", -1)) == recipe_id:
				return str(r.get("name", "Recipe #%d" % recipe_id))
	return "Recipe #%d" % recipe_id


func _parse_iso_to_unix(iso: String) -> float:
	## Parse an ISO-8601 datetime string and return Unix timestamp.
	## Returns 0.0 on parse failure.
	if iso.is_empty():
		return 0.0
	var dt: Dictionary = Time.get_datetime_dict_from_datetime_string(iso, false)
	if dt.is_empty():
		return 0.0
	return Time.get_unix_time_from_datetime_dict(dt)


func _apply_translations() -> void:
	var header: ModuleHeader = get_node_or_null("VBoxContainer/ModuleHeader") as ModuleHeader
	if header != null:
		header.set_title(CabinetStyle.text("ui.craft.title", "Crafting"))
	if _craft_button != null:
		_craft_button.text = CabinetStyle.text("ui.craft.craft_button", "Craft")
	if _finish_button != null:
		_finish_button.text = CabinetStyle.text("ui.craft.finish_button", "Finish Crafting")
	if _recipes.is_empty() and _empty_state != null and _empty_state.has_method("set_content"):
		_empty_state.set_content(
			CabinetStyle.text("ui.craft.empty_title", "No Recipes"),
			CabinetStyle.text("ui.craft.empty_hint", "No craft recipes available yet.")
		)
