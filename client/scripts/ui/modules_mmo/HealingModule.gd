extends Control

## HealingModule — display injured heroes, inspect body-part damage,
## and start the healing process.

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
var _heroes: Array = []                # all heroes
var _injured_heroes: Array = []        # heroes with injured/wounded/critical status
var _healing_heroes: Array = []        # heroes currently healing
var _selected_hero: Dictionary = {}

# ---------------------------------------------------------------------------
# UI nodes (built in code)
# ---------------------------------------------------------------------------
var _loading_overlay: LoadingOverlay = null
var _empty_state: EmptyState = null
var _hero_list: ItemList = null
var _healing_list: ItemList = null
var _detail_panel: DetailPanel = null
var _heal_button: Button = null
var _status_label: Label = null
var _body_parts_container: VBoxContainer = null

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------
func _ready() -> void:
	_build_ui()
	_load_heroes()

# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------
func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	# --- Header ---
	var header := ModuleHeader.new()
	root.add_child(header)
	header.set_title("Healing Ward")
	header.refresh_pressed.connect(_load_heroes)

	# --- Body: left hero lists | right detail + body parts ---
	var body := HSplitContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.split_offset = 350
	root.add_child(body)

	# Left column
	var left_panel := PanelContainer.new()
	left_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(left_panel)
	var left_vbox := VBoxContainer.new()
	left_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_panel.add_child(left_vbox)

	var injured_title := Label.new()
	injured_title.text = "Injured Heroes"
	injured_title.add_theme_font_size_override("font_size", 14)
	left_vbox.add_child(injured_title)

	_hero_list = ItemList.new()
	_hero_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hero_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_hero_list.item_selected.connect(_on_injured_hero_selected)
	left_vbox.add_child(_hero_list)

	var healing_title := Label.new()
	healing_title.text = "Currently Healing"
	healing_title.add_theme_font_size_override("font_size", 14)
	left_vbox.add_child(healing_title)

	_healing_list = ItemList.new()
	_healing_list.custom_minimum_size = Vector2(0, 110)
	_healing_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_healing_list.item_selected.connect(_on_healing_hero_selected)
	left_vbox.add_child(_healing_list)

	_loading_overlay = LoadingOverlay.new()
	left_panel.add_child(_loading_overlay)
	_empty_state = EmptyState.new()
	_empty_state.visible = false
	left_vbox.add_child(_empty_state)

	# Right column — detail + body parts + heal button
	var right_panel := PanelContainer.new()
	right_panel.custom_minimum_size = Vector2(340, 0)
	right_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(right_panel)
	var right_scroll := ScrollContainer.new()
	right_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_panel.add_child(right_scroll)
	var right_vbox := VBoxContainer.new()
	right_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_vbox.add_theme_constant_override("separation", 10)
	right_scroll.add_child(right_vbox)

	_detail_panel = DetailPanel.new()
	_detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_vbox.add_child(_detail_panel)

	# Body-parts injury breakdown
	_body_parts_container = VBoxContainer.new()
	_body_parts_container.add_theme_constant_override("separation", 4)
	var bp_title := Label.new()
	bp_title.text = "Body Part Injuries"
	bp_title.add_theme_font_size_override("font_size", 14)
	_body_parts_container.add_child(bp_title)
	right_vbox.add_child(_body_parts_container)

	# Heal button
	_heal_button = Button.new()
	_heal_button.text = "Begin Healing"
	_heal_button.custom_minimum_size = Vector2(0, 40)
	_heal_button.pressed.connect(_on_heal_pressed)
	right_vbox.add_child(_heal_button)

	# Footer status
	_status_label = Label.new()
	_status_label.text = ""
	root.add_child(_status_label)

# ---------------------------------------------------------------------------
# Data loading
# ---------------------------------------------------------------------------
func _load_heroes() -> void:
	_status_label.text = "Loading..."
	_loading_overlay.show_loading()
	_empty_state.visible = false
	_hero_list.clear()
	_healing_list.clear()
	_heroes.clear()
	_injured_heroes.clear()
	_healing_heroes.clear()
	_selected_hero = {}

	var response: Dictionary = await ApiClient.get_heroes()
	_loading_overlay.hide_loading()
	if not bool(response.get("ok", false)):
		UIUtils.show_error("Failed to load heroes")
		_status_label.text = "Error"
		return

	_heroes = ResponseParser.extract_array(response.get("data", {}))
	AppState.set_heroes_data(_heroes)

	# Partition heroes by health status
	for h in _heroes:
		if not h is Dictionary:
			continue
		var hero := h as Dictionary
		var status: String = str(hero.get("status", "idle")).to_lower()
		if status == "healing":
			_healing_heroes.append(hero)
		elif status in ["injured", "critical", "wounded"]:
			_injured_heroes.append(hero)

	# Render
	if _injured_heroes.is_empty() and _healing_heroes.is_empty():
		_empty_state.visible = true
		_empty_state.set_content("All Healthy", "No heroes need healing right now.")
		_status_label.text = ""
		return

	_empty_state.visible = false

	for hero in _injured_heroes:
		_hero_list.add_item("%s — %s" % [
			str(hero.get("name", "?")),
			str(hero.get("status", "?")).capitalize(),
		])

	for hero in _healing_heroes:
		_healing_list.add_item("%s — healing" % str(hero.get("name", "?")))

	_status_label.text = "%d injured · %d healing" % [_injured_heroes.size(), _healing_heroes.size()]

# ---------------------------------------------------------------------------
# Selection
# ---------------------------------------------------------------------------
func _on_injured_hero_selected(index: int) -> void:
	_healing_list.deselect_all()
	if index < 0 or index >= _injured_heroes.size():
		return
	_selected_hero = _injured_heroes[index] as Dictionary
	_show_hero_detail()
	_heal_button.visible = true

func _on_healing_hero_selected(index: int) -> void:
	_hero_list.deselect_all()
	if index < 0 or index >= _healing_heroes.size():
		return
	_selected_hero = _healing_heroes[index] as Dictionary
	_show_hero_detail()
	_heal_button.visible = false

func _show_hero_detail() -> void:
	_detail_panel.set_title(str(_selected_hero.get("name", "Hero")))
	_detail_panel.set_fields({
		"Level": str(_selected_hero.get("level", "-")),
		"Status": str(_selected_hero.get("status", "-")).capitalize(),
		"Overall HP": "%s / %s" % [
			str(_selected_hero.get("current_hp", "?")),
			str(_selected_hero.get("max_hp", "?")),
		],
	})
	_render_body_parts()

# ---------------------------------------------------------------------------
# Body parts
# ---------------------------------------------------------------------------
func _render_body_parts() -> void:
	# Remove old rows (keep title label at index 0)
	while _body_parts_container.get_child_count() > 1:
		_body_parts_container.get_child(_body_parts_container.get_child_count() - 1).queue_free()

	var body_parts: Array = []
	if _selected_hero.has("body_parts") and _selected_hero["body_parts"] is Array:
		body_parts = _selected_hero["body_parts"] as Array

	if body_parts.is_empty():
		var note := Label.new()
		note.text = "No body part data available"
		note.add_theme_color_override("font_color", Color(0.5, 0.53, 0.6))
		_body_parts_container.add_child(note)
		return

	for bp_variant in body_parts:
		if not bp_variant is Dictionary:
			continue
		var bp := bp_variant as Dictionary
		var row := BodyPartStatusRow.new()
		_body_parts_container.add_child(row)
		row.set_data(
			str(bp.get("name", "?")),
			float(bp.get("current_hp", 100)),
			float(bp.get("max_hp", 100)),
			str(bp.get("condition", "healthy"))
		)

# ---------------------------------------------------------------------------
# Heal action
# ---------------------------------------------------------------------------
func _on_heal_pressed() -> void:
	if _selected_hero.is_empty():
		UIUtils.show_warning("Select an injured hero first")
		return
	var hero_id: int = int(_selected_hero.get("id", -1))
	if hero_id < 0:
		return
	_status_label.text = "Starting healing..."
	_heal_button.disabled = true
	var response: Dictionary = await ApiClient.start_healing(hero_id)
	_heal_button.disabled = false
	if bool(response.get("ok", false)):
		UIUtils.show_success("%s is now healing!" % str(_selected_hero.get("name", "Hero")))
		_load_heroes()
	else:
		var msg: String = str(response.get("message", response.get("error", "Healing failed")))
		UIUtils.show_error(msg)
		_status_label.text = msg
