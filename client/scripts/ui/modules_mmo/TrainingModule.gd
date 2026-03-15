extends Control

## TrainingModule — assign heroes to training, pick duration, track progress,
## complete training when the timer finishes.

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
var _heroes: Array = []               # all fetched heroes
var _idle_heroes: Array = []          # heroes available to train
var _training_heroes: Array = []      # heroes currently training
var _selected_hero: Dictionary = {}
var _training_duration: int = 60      # minutes

# ---------------------------------------------------------------------------
# UI nodes (built in code)
# ---------------------------------------------------------------------------
var _loading_overlay: LoadingOverlay = null
var _empty_state: EmptyState = null
var _hero_list: ItemList = null
var _training_list: ItemList = null
var _duration_dropdown: OptionButton = null
var _start_button: Button = null
var _complete_button: Button = null
var _detail_panel: DetailPanel = null
var _status_label: Label = null

const DURATIONS := [30, 60, 120, 240]  # minutes

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
	header.set_title("Training Grounds")
	header.refresh_pressed.connect(_load_heroes)

	# --- Body: left hero lists | right detail + controls ---
	var body := HSplitContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.split_offset = 350
	root.add_child(body)

	# Left column — two lists: idle heroes + currently training
	var left_panel := PanelContainer.new()
	left_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(left_panel)
	var left_vbox := VBoxContainer.new()
	left_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_panel.add_child(left_vbox)

	var idle_title := Label.new()
	idle_title.text = "Available Heroes"
	idle_title.add_theme_font_size_override("font_size", 14)
	left_vbox.add_child(idle_title)

	_hero_list = ItemList.new()
	_hero_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hero_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_hero_list.item_selected.connect(_on_idle_hero_selected)
	left_vbox.add_child(_hero_list)

	var training_title := Label.new()
	training_title.text = "Currently Training"
	training_title.add_theme_font_size_override("font_size", 14)
	left_vbox.add_child(training_title)

	_training_list = ItemList.new()
	_training_list.custom_minimum_size = Vector2(0, 120)
	_training_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_training_list.item_selected.connect(_on_training_hero_selected)
	left_vbox.add_child(_training_list)

	_loading_overlay = LoadingOverlay.new()
	left_panel.add_child(_loading_overlay)
	_empty_state = EmptyState.new()
	_empty_state.visible = false
	left_vbox.add_child(_empty_state)

	# Right column — detail panel + controls
	var right_panel := PanelContainer.new()
	right_panel.custom_minimum_size = Vector2(320, 0)
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

	# Duration selector
	var dur_row := HBoxContainer.new()
	dur_row.add_theme_constant_override("separation", 8)
	right_vbox.add_child(dur_row)
	var dur_label := Label.new()
	dur_label.text = "Duration:"
	dur_row.add_child(dur_label)
	_duration_dropdown = OptionButton.new()
	for d in DURATIONS:
		if d < 60:
			_duration_dropdown.add_item("%d min" % d)
		else:
			_duration_dropdown.add_item("%dh" % int(d / 60))
	_duration_dropdown.select(1)  # default 60 min
	_duration_dropdown.item_selected.connect(func(idx: int) -> void:
		_training_duration = DURATIONS[idx])
	dur_row.add_child(_duration_dropdown)

	# Action buttons
	_start_button = Button.new()
	_start_button.text = "Start Training"
	_start_button.custom_minimum_size = Vector2(0, 40)
	_start_button.pressed.connect(_on_start_training)
	right_vbox.add_child(_start_button)

	_complete_button = Button.new()
	_complete_button.text = "Complete Training"
	_complete_button.custom_minimum_size = Vector2(0, 40)
	_complete_button.pressed.connect(_on_complete_training)
	_complete_button.visible = false
	right_vbox.add_child(_complete_button)

	# Footer status
	_status_label = Label.new()
	_status_label.text = ""
	root.add_child(_status_label)

# ---------------------------------------------------------------------------
# Data loading
# ---------------------------------------------------------------------------
func _load_heroes() -> void:
	_status_label.text = "Loading heroes..."
	_loading_overlay.show_loading()
	_empty_state.visible = false
	_hero_list.clear()
	_training_list.clear()
	_heroes.clear()
	_idle_heroes.clear()
	_training_heroes.clear()
	_selected_hero = {}

	var response: Dictionary = await ApiClient.get_heroes()
	_loading_overlay.hide_loading()
	if not bool(response.get("ok", false)):
		UIUtils.show_error("Failed to load heroes")
		_status_label.text = "Error"
		return

	_heroes = ResponseParser.extract_array(response.get("data", {}))
	AppState.set_heroes_data(_heroes)

	# Partition into idle vs training
	for h in _heroes:
		if not h is Dictionary:
			continue
		var hero := h as Dictionary
		var status: String = str(hero.get("status", "idle")).to_lower()
		if status == "training" or bool(hero.get("is_training", false)):
			_training_heroes.append(hero)
		elif status in ["idle", "healthy", ""]:
			_idle_heroes.append(hero)

	# Render idle list
	if _idle_heroes.is_empty() and _training_heroes.is_empty():
		_empty_state.visible = true
		_empty_state.set_content("No Heroes", "Create a hero first.")
		_status_label.text = ""
		return

	if _idle_heroes.is_empty():
		_empty_state.visible = true
		_empty_state.set_content("All Busy", "All heroes are training or unavailable.")
	else:
		_empty_state.visible = false

	for hero in _idle_heroes:
		_hero_list.add_item("%s  (Lv.%s)" % [
			str(hero.get("name", "?")),
			str(hero.get("level", "?")),
		])

	# Render training list
	for hero in _training_heroes:
		var train_until: String = str(hero.get("training_until", hero.get("train_until", "")))
		var suffix := " — training"
		if not train_until.is_empty():
			suffix = " — until %s" % train_until.substr(0, 16)
		_training_list.add_item("%s%s" % [str(hero.get("name", "?")), suffix])

	_status_label.text = "%d available · %d training" % [_idle_heroes.size(), _training_heroes.size()]
	_update_buttons()

# ---------------------------------------------------------------------------
# Selection handlers
# ---------------------------------------------------------------------------
func _on_idle_hero_selected(index: int) -> void:
	_training_list.deselect_all()
	if index < 0 or index >= _idle_heroes.size():
		return
	_selected_hero = _idle_heroes[index] as Dictionary
	_show_hero_detail(_selected_hero)
	_update_buttons()

func _on_training_hero_selected(index: int) -> void:
	_hero_list.deselect_all()
	if index < 0 or index >= _training_heroes.size():
		return
	_selected_hero = _training_heroes[index] as Dictionary
	_show_hero_detail(_selected_hero)
	_update_buttons()

func _show_hero_detail(hero: Dictionary) -> void:
	_detail_panel.set_title(str(hero.get("name", "Hero")))
	var attrs: Dictionary = hero.get("attributes", {}) as Dictionary if hero.get("attributes") is Dictionary else {}
	_detail_panel.set_fields({
		"Level": str(hero.get("level", "-")),
		"Status": str(hero.get("status", "idle")).capitalize(),
		"Strength": str(hero.get("strength", attrs.get("strength", "-"))),
		"Agility": str(hero.get("agility", attrs.get("agility", "-"))),
		"Intelligence": str(hero.get("intelligence", attrs.get("intelligence", "-"))),
		"Vitality": str(hero.get("vitality", attrs.get("vitality", "-"))),
	})

func _update_buttons() -> void:
	var is_training: bool = str(_selected_hero.get("status", "")).to_lower() == "training" \
		or bool(_selected_hero.get("is_training", false))
	_start_button.visible = not is_training
	_complete_button.visible = is_training

# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------
func _on_start_training() -> void:
	if _selected_hero.is_empty():
		UIUtils.show_warning("Select a hero first")
		return
	var hero_id: int = int(_selected_hero.get("id", -1))
	if hero_id < 0:
		return
	_status_label.text = "Starting training..."
	_start_button.disabled = true
	var response: Dictionary = await ApiClient.start_training(hero_id, _training_duration)
	_start_button.disabled = false
	if bool(response.get("ok", false)):
		UIUtils.show_success("%s is now training for %d min!" % [
			str(_selected_hero.get("name", "Hero")), _training_duration])
		_load_heroes()
	else:
		var msg: String = str(response.get("message", response.get("error", "Training failed")))
		UIUtils.show_error(msg)
		_status_label.text = msg

func _on_complete_training() -> void:
	if _selected_hero.is_empty():
		UIUtils.show_warning("Select a training hero first")
		return
	var hero_id: int = int(_selected_hero.get("id", -1))
	if hero_id < 0:
		return
	_status_label.text = "Completing training..."
	_complete_button.disabled = true
	var response: Dictionary = await ApiClient.complete_training(hero_id)
	_complete_button.disabled = false
	if bool(response.get("ok", false)):
		UIUtils.show_success("%s finished training!" % str(_selected_hero.get("name", "Hero")))
		_load_heroes()
	else:
		var msg: String = str(response.get("message", response.get("error", "Cannot complete yet")))
		UIUtils.show_error(msg)
		_status_label.text = msg
