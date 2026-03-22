extends Control

## ArenaModule — tactical PvP preparation room.
## Responsible for: mode selection (1v1 / 5v5), team building via hero grid,
## battle preview with power & warnings, queue management, transition to
## BattleRoom once a match is found.

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
const MODES := ["1v1", "5v5"]
const TEAM_SIZE := {"1v1": 1, "5v5": 5}

## Hero card size inside the selection grid
const HERO_CARD_MIN := Vector2(130, 160)

## Filter options
enum HeroFilter { ALL, HEALTHY, INJURED, HIGH_GEN, AVAILABLE_ONLY }
const FILTER_LABELS := {
	HeroFilter.ALL: "All",
	HeroFilter.HEALTHY: "Healthy",
	HeroFilter.INJURED: "Injured",
	HeroFilter.HIGH_GEN: "High Gen",
	HeroFilter.AVAILABLE_ONLY: "Available",
}

## Sort options
enum HeroSort { GEN_LEVEL, POWER, WINS }
const SORT_LABELS := {
	HeroSort.GEN_LEVEL: "Gen Level",
	HeroSort.POWER: "Power",
	HeroSort.WINS: "Wins",
}

## Queue states
enum QueueState { IDLE, SEARCHING, MATCH_FOUND, PREPARING }
const QUEUE_TEXTS := {
	QueueState.IDLE: "Not in queue",
	QueueState.SEARCHING: "Searching for opponent...",
	QueueState.MATCH_FOUND: "Match found!",
	QueueState.PREPARING: "Preparing battle...",
}
const QUEUE_COLORS := {
	QueueState.IDLE: Color(0.5, 0.53, 0.6),
	QueueState.SEARCHING: Color(0.85, 0.75, 0.3),
	QueueState.MATCH_FOUND: Color(0.3, 0.9, 0.4),
	QueueState.PREPARING: Color(0.4, 0.7, 0.95),
}

func _tx(key: String, fallback: String) -> String:
	return CabinetStyle.text(key, fallback)

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
var _all_heroes: Array = []          # raw from API
var _filtered_heroes: Array = []     # after filter + sort
var _mode: String = "1v1"
var _queue_state: int = QueueState.IDLE
var _active_filter: int = HeroFilter.ALL
var _active_sort: int = HeroSort.GEN_LEVEL
var _team_slots: Array = []          # TeamSlotCard refs
var _hero_cards: Array = []          # hero grid card panels
var _warnings: Array = []

# ---------------------------------------------------------------------------
# UI node references (built in _build_ui)
# ---------------------------------------------------------------------------
var _loading_overlay: LoadingOverlay = null

# Mode section
var _mode_buttons: Dictionary = {}   # mode_str → Button
var _mode_indicator: Label = null

# Team builder — left (slots) & right (hero grid)
var _team_container: VBoxContainer = null
var _hero_grid: GridContainer = null
var _filter_dropdown: OptionButton = null
var _sort_dropdown: OptionButton = null
var _autofill_button: Button = null

# Battle preview
var _preview_panel: PanelContainer = null
var _power_label: Label = null
var _hero_count_label: Label = null
var _warning_container: VBoxContainer = null

# Actions / queue
var _queue_button: Button = null
var _cancel_button: Button = null
var _queue_status_label: Label = null
var _status_label: Label = null

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------
func _ready() -> void:
	_build_ui()
	call_deferred("_apply_cabinet_visuals")
	_select_mode("1v1")
	_load_heroes()
	# React to global hero updates
	if AppState.heroes_updated.is_connected(_on_heroes_updated) == false:
		AppState.heroes_updated.connect(_on_heroes_updated)

func _apply_cabinet_visuals() -> void:
	CabinetStyle.style_screen(self)
	if _status_label != null:
		CabinetStyle.style_status_label(_status_label)


func _exit_tree() -> void:
	if AppState.heroes_updated.is_connected(_on_heroes_updated):
		AppState.heroes_updated.disconnect(_on_heroes_updated)

# ═══════════════════════════════════════════════════════════════════════════
#  UI CONSTRUCTION
# ═══════════════════════════════════════════════════════════════════════════

func _build_ui() -> void:
	# Root margin
	var root_margin := MarginContainer.new()
	root_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_margin.add_theme_constant_override("margin_left", 16)
	root_margin.add_theme_constant_override("margin_right", 16)
	root_margin.add_theme_constant_override("margin_top", 8)
	root_margin.add_theme_constant_override("margin_bottom", 8)
	add_child(root_margin)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 10)
	CabinetStyle.style_module_root(root_vbox)
	root_margin.add_child(root_vbox)

	# ── Header ──
	var header := ModuleHeader.new()
	root_vbox.add_child(header)
	header.set_title(_tx("ui.arena.title", "Arena"))
	header.set_status(_tx("ui.arena.prepare_team", "Prepare your team"))
	header.refresh_pressed.connect(_load_heroes)

	# ── Mode Section ──
	root_vbox.add_child(_build_mode_section())

	# ── Team Builder Section (main body) ──
	root_vbox.add_child(_build_team_builder_section())

	# ── Battle Preview Section ──
	root_vbox.add_child(_build_preview_section())

	# ── Actions Section ──
	root_vbox.add_child(_build_actions_section())

	# ── Footer status ──
	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 12)
	_status_label.add_theme_color_override("font_color", Color(0.5, 0.53, 0.6))
	root_vbox.add_child(_status_label)

	# Global loading overlay on top
	_loading_overlay = LoadingOverlay.new()
	add_child(_loading_overlay)


# ── 1. MODE SECTION ──────────────────────────────────────────────────────────

func _build_mode_section() -> PanelContainer:
	var panel := PanelContainer.new()
	var style := _section_style()
	panel.add_theme_stylebox_override("panel", style)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 6)
	panel.add_child(inner)

	var title_row := HBoxContainer.new()
	inner.add_child(title_row)
	var lbl := Label.new()
	lbl.text = "Battle Mode"
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.add_theme_color_override("font_color", Color(0.92, 0.88, 0.72))
	title_row.add_child(lbl)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(spacer)

	_mode_indicator = Label.new()
	_mode_indicator.add_theme_font_size_override("font_size", 13)
	_mode_indicator.add_theme_color_override("font_color", Color(0.6, 0.63, 0.7))
	title_row.add_child(_mode_indicator)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 10)
	inner.add_child(btn_row)

	for mode_str in MODES:
		var btn := Button.new()
		btn.text = mode_str
		btn.custom_minimum_size = Vector2(100, 40)
		btn.toggle_mode = true
		btn.pressed.connect(_on_mode_button_pressed.bind(mode_str))
		btn_row.add_child(btn)
		_mode_buttons[mode_str] = btn

	return panel


# ── 2. TEAM BUILDER SECTION ──────────────────────────────────────────────────

func _build_team_builder_section() -> HSplitContainer:
	var split := HSplitContainer.new()
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 200

	# ─ Left: Team Slots Panel ─
	var slots_panel := PanelContainer.new()
	slots_panel.custom_minimum_size = Vector2(160, 0)
	slots_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var slots_style := _section_style()
	slots_panel.add_theme_stylebox_override("panel", slots_style)
	split.add_child(slots_panel)

	var slots_vbox := VBoxContainer.new()
	slots_vbox.add_theme_constant_override("separation", 6)
	slots_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	slots_panel.add_child(slots_vbox)

	var slots_title := Label.new()
	slots_title.text = "Your Team"
	slots_title.add_theme_font_size_override("font_size", 14)
	slots_title.add_theme_color_override("font_color", Color(0.92, 0.88, 0.72))
	slots_vbox.add_child(slots_title)

	_team_container = VBoxContainer.new()
	_team_container.add_theme_constant_override("separation", 6)
	_team_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	slots_vbox.add_child(_team_container)

	# ─ Right: Hero Selection Grid Panel ─
	var grid_panel := PanelContainer.new()
	grid_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var grid_style := _section_style()
	grid_panel.add_theme_stylebox_override("panel", grid_style)
	split.add_child(grid_panel)

	var grid_vbox := VBoxContainer.new()
	grid_vbox.add_theme_constant_override("separation", 6)
	grid_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid_panel.add_child(grid_vbox)

	# Filter / sort toolbar
	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 8)
	grid_vbox.add_child(toolbar)

	var heroes_title := Label.new()
	heroes_title.text = "Select Heroes"
	heroes_title.add_theme_font_size_override("font_size", 14)
	heroes_title.add_theme_color_override("font_color", Color(0.92, 0.88, 0.72))
	toolbar.add_child(heroes_title)

	var tb_spacer := Control.new()
	tb_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(tb_spacer)

	_filter_dropdown = OptionButton.new()
	for key in FILTER_LABELS:
		_filter_dropdown.add_item(FILTER_LABELS[key], key)
	_filter_dropdown.item_selected.connect(_on_filter_changed)
	toolbar.add_child(_filter_dropdown)

	_sort_dropdown = OptionButton.new()
	for key in SORT_LABELS:
		_sort_dropdown.add_item(SORT_LABELS[key], key)
	_sort_dropdown.item_selected.connect(_on_sort_changed)
	toolbar.add_child(_sort_dropdown)

	_autofill_button = Button.new()
	_autofill_button.text = "Auto-fill"
	_autofill_button.custom_minimum_size = Vector2(80, 32)
	_autofill_button.tooltip_text = "Fill empty slots with strongest available heroes"
	_autofill_button.pressed.connect(_on_autofill_pressed)
	toolbar.add_child(_autofill_button)

	# Scrollable hero grid
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	grid_vbox.add_child(scroll)

	_hero_grid = GridContainer.new()
	_hero_grid.columns = 4
	_hero_grid.add_theme_constant_override("h_separation", 8)
	_hero_grid.add_theme_constant_override("v_separation", 8)
	_hero_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_hero_grid)

	return split


# ── 3. BATTLE PREVIEW SECTION ────────────────────────────────────────────────

func _build_preview_section() -> PanelContainer:
	_preview_panel = PanelContainer.new()
	var style := _section_style()
	style.border_color = Color(0.4, 0.45, 0.55, 0.6)
	_preview_panel.add_theme_stylebox_override("panel", style)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 4)
	_preview_panel.add_child(inner)

	# Title row with power
	var title_row := HBoxContainer.new()
	inner.add_child(title_row)

	var lbl := Label.new()
	lbl.text = "Battle Preview"
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color(0.92, 0.88, 0.72))
	title_row.add_child(lbl)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(spacer)

	_hero_count_label = Label.new()
	_hero_count_label.add_theme_font_size_override("font_size", 13)
	_hero_count_label.add_theme_color_override("font_color", Color(0.6, 0.63, 0.7))
	title_row.add_child(_hero_count_label)

	var spacer2 := Control.new()
	spacer2.custom_minimum_size = Vector2(20, 0)
	title_row.add_child(spacer2)

	_power_label = Label.new()
	_power_label.add_theme_font_size_override("font_size", 14)
	_power_label.add_theme_color_override("font_color", Color(0.85, 0.75, 0.3))
	title_row.add_child(_power_label)

	# Warnings container
	_warning_container = VBoxContainer.new()
	_warning_container.add_theme_constant_override("separation", 2)
	inner.add_child(_warning_container)

	return _preview_panel


# ── 4. ACTIONS / QUEUE SECTION ───────────────────────────────────────────────

func _build_actions_section() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	_queue_button = Button.new()
	_queue_button.text = "Enter Queue"
	_queue_button.custom_minimum_size = Vector2(140, 44)
	_queue_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_queue_button.pressed.connect(_on_queue_pressed)
	row.add_child(_queue_button)

	_cancel_button = Button.new()
	_cancel_button.text = "Cancel Queue"
	_cancel_button.custom_minimum_size = Vector2(140, 44)
	_cancel_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cancel_button.visible = false
	_cancel_button.pressed.connect(_on_cancel_queue)
	row.add_child(_cancel_button)

	_queue_status_label = Label.new()
	_queue_status_label.text = QUEUE_TEXTS[QueueState.IDLE]
	_queue_status_label.add_theme_font_size_override("font_size", 14)
	_queue_status_label.add_theme_color_override("font_color", QUEUE_COLORS[QueueState.IDLE])
	_queue_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_queue_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_queue_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_queue_status_label)

	return row

# ═══════════════════════════════════════════════════════════════════════════
#  MODE SELECTION
# ═══════════════════════════════════════════════════════════════════════════

func _select_mode(mode_str: String) -> void:
	_mode = mode_str
	# Update toggle buttons
	for m in _mode_buttons:
		var btn: Button = _mode_buttons[m]
		btn.button_pressed = (m == mode_str)
	# Indicator text
	var size: int = TEAM_SIZE.get(mode_str, 1)
	_mode_indicator.text = "%s — %d hero%s" % [mode_str, size, "" if size == 1 else "es"]
	_rebuild_team_slots()
	_update_preview()


func _on_mode_button_pressed(mode_str: String) -> void:
	if _queue_state != QueueState.IDLE:
		UIUtils.show_warning("Leave the queue before changing mode")
		# Reset button state
		for m in _mode_buttons:
			(_mode_buttons[m] as Button).button_pressed = (m == _mode)
		return
	_select_mode(mode_str)

# ═══════════════════════════════════════════════════════════════════════════
#  TEAM SLOTS
# ═══════════════════════════════════════════════════════════════════════════

func _rebuild_team_slots() -> void:
	# Free old
	for slot in _team_slots:
		if is_instance_valid(slot):
			slot.queue_free()
	_team_slots.clear()

	var count: int = TEAM_SIZE.get(_mode, 1)
	for i in range(count):
		var card := TeamSlotCard.new()
		card.set_slot_index(i)
		card.slot_pressed.connect(_on_slot_pressed.bind(i))
		card.hero_removed.connect(_on_hero_removed_from_slot.bind(i))
		_team_container.add_child(card)
		_team_slots.append(card)
	_refresh_hero_grid_availability()


func _on_slot_pressed(slot_index: int) -> void:
	# Highlight this slot so the user knows which slot they're filling
	for i in range(_team_slots.size()):
		(_team_slots[i] as TeamSlotCard).set_highlighted(i == slot_index)


func _on_hero_removed_from_slot(slot_index: int) -> void:
	if slot_index >= 0 and slot_index < _team_slots.size():
		(_team_slots[slot_index] as TeamSlotCard).clear_slot()
	_refresh_hero_grid_availability()
	_update_preview()

# ═══════════════════════════════════════════════════════════════════════════
#  DATA LOADING
# ═══════════════════════════════════════════════════════════════════════════

func _load_heroes() -> void:
	_loading_overlay.show_loading()
	_status_label.text = "Loading heroes..."
	# H8: Use HeroManager (cached, avoids redundant API calls and ResponseParser)
	await HeroManager.load_heroes()
	_loading_overlay.hide_loading()
	_all_heroes = HeroManager.get_heroes()
	_apply_filter_and_sort()
	_render_hero_grid()
	if _all_heroes.is_empty():
		_status_label.text = "No heroes found"
	else:
		_status_label.text = "%d heroes loaded" % _all_heroes.size()


func _on_heroes_updated(_heroes: Array) -> void:
	# Refresh if the global hero list changes (e.g. after healing)
	_all_heroes = _heroes.duplicate(true)
	_apply_filter_and_sort()
	_render_hero_grid()

# ═══════════════════════════════════════════════════════════════════════════
#  FILTER / SORT
# ═══════════════════════════════════════════════════════════════════════════

func _on_filter_changed(idx: int) -> void:
	_active_filter = _filter_dropdown.get_item_id(idx)
	_apply_filter_and_sort()
	_render_hero_grid()


func _on_sort_changed(idx: int) -> void:
	_active_sort = _sort_dropdown.get_item_id(idx)
	_apply_filter_and_sort()
	_render_hero_grid()


func _apply_filter_and_sort() -> void:
	# --- Filter ---
	_filtered_heroes = []
	for h_var in _all_heroes:
		if not h_var is Dictionary:
			continue
		var hero := h_var as Dictionary
		if _passes_filter(hero):
			_filtered_heroes.append(hero)

	# --- Sort ---
	match _active_sort:
		HeroSort.GEN_LEVEL:
			_filtered_heroes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return int(a.get("hero_generation_level", 0)) > int(b.get("hero_generation_level", 0)))
		HeroSort.POWER:
			_filtered_heroes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				var sa: Dictionary = a.get("stats", {})
				var sb: Dictionary = b.get("stats", {})
				return _stat_total(sa) > _stat_total(sb))
		HeroSort.WINS:
			_filtered_heroes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return int(a.get("total_kills", 0)) > int(b.get("total_kills", 0)))


func _passes_filter(hero: Dictionary) -> bool:
	var status: String = str(hero.get("status", "idle")).to_lower()
	var is_dead: bool = bool(hero.get("is_dead", false))
	var is_healing: bool = bool(hero.get("is_healing", false))
	var hp: int = int(hero.get("current_hp", hero.get("hp", 100)))
	var max_hp: int = int(hero.get("max_hp", 100))

	match _active_filter:
		HeroFilter.ALL:
			return true
		HeroFilter.HEALTHY:
			return not is_dead and not is_healing and hp > 0
		HeroFilter.INJURED:
			return (hp < max_hp and hp > 0) or status == "injured"
		HeroFilter.HIGH_GEN:
			return int(hero.get("hero_generation_level", 1)) >= 5
		HeroFilter.AVAILABLE_ONLY:
			return not is_dead and not is_healing \
				and status in ["idle", "healthy", ""] \
				and not _is_hero_in_team(int(hero.get("id", -1)))
	return true

# ═══════════════════════════════════════════════════════════════════════════
#  HERO SELECTION GRID
# ═══════════════════════════════════════════════════════════════════════════

func _render_hero_grid() -> void:
	# Clear previous cards
	for child in _hero_grid.get_children():
		child.queue_free()
	_hero_cards.clear()

	if _filtered_heroes.is_empty():
		var empty := Label.new()
		empty.text = "No heroes match the current filter"
		empty.add_theme_font_size_override("font_size", 13)
		empty.add_theme_color_override("font_color", Color(0.5, 0.53, 0.6))
		_hero_grid.add_child(empty)
		return

	for h_var in _filtered_heroes:
		if not h_var is Dictionary:
			continue
		var hero := h_var as Dictionary
		var card := _create_hero_card(hero)
		_hero_grid.add_child(card)
		_hero_cards.append(card)

	_refresh_hero_grid_availability()


func _create_hero_card(hero: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = HERO_CARD_MIN
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.set_meta("hero_id", int(hero.get("id", -1)))
	card.set_meta("hero_data", hero.duplicate(true))

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.11, 0.15, 0.9)
	style.border_color = Color(0.3, 0.33, 0.42, 0.7)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	card.add_theme_stylebox_override("panel", style)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(vb)

	# Portrait placeholder
	var portrait_center := CenterContainer.new()
	vb.add_child(portrait_center)
	var portrait := ColorRect.new()
	portrait.custom_minimum_size = Vector2(44, 44)
	var hero_name: String = str(hero.get("name", "?"))
	portrait.color = _hero_portrait_color(hero_name)
	portrait_center.add_child(portrait)
	var icon_label := Label.new()
	icon_label.text = hero_name.substr(0, 1).to_upper() if hero_name.length() > 0 else "?"
	icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon_label.add_theme_font_size_override("font_size", 20)
	icon_label.add_theme_color_override("font_color", Color(0.95, 0.92, 0.82))
	icon_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	portrait.add_child(icon_label)

	# Name
	var name_lbl := Label.new()
	name_lbl.text = hero_name
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.add_theme_color_override("font_color", Color(0.9, 0.88, 0.78))
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	vb.add_child(name_lbl)

	# Level
	var level_lbl := Label.new()
	level_lbl.text = "Gen %s" % str(hero.get("hero_generation_level", "?"))
	level_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level_lbl.add_theme_font_size_override("font_size", 11)
	level_lbl.add_theme_color_override("font_color", Color(0.6, 0.63, 0.72))
	vb.add_child(level_lbl)

	# Status line
	var status_str: String = str(hero.get("status", "idle")).to_lower()
	var is_dead: bool = bool(hero.get("is_dead", false))
	var is_healing: bool = bool(hero.get("is_healing", false))
	var display_status: String = ""
	var status_color := Color(0.5, 0.55, 0.62)
	if is_dead:
		display_status = "Dead"
		status_color = Color(0.85, 0.25, 0.25)
	elif is_healing:
		display_status = "Healing"
		status_color = Color(0.3, 0.85, 0.45)
	elif status_str == "injured":
		display_status = "Injured"
		status_color = Color(0.9, 0.6, 0.2)

	if display_status != "":
		var s_lbl := Label.new()
		s_lbl.text = display_status
		s_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		s_lbl.add_theme_font_size_override("font_size", 10)
		s_lbl.add_theme_color_override("font_color", status_color)
		vb.add_child(s_lbl)

	# Stats (power / wins)
	var stats_dict: Dictionary = hero.get("stats", {})
	var power: int = _stat_total(stats_dict)
	var wins: int = int(hero.get("total_kills", 0))
	var stats_lbl := Label.new()
	stats_lbl.text = "PWR %d  W %d" % [power, wins]
	stats_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats_lbl.add_theme_font_size_override("font_size", 10)
	stats_lbl.add_theme_color_override("font_color", Color(0.5, 0.53, 0.6))
	vb.add_child(stats_lbl)

	# Click handler
	card.gui_input.connect(_on_hero_card_input.bind(card))
	card.mouse_entered.connect(_on_hero_card_hover.bind(card, true))
	card.mouse_exited.connect(_on_hero_card_hover.bind(card, false))

	return card


func _on_hero_card_input(event: InputEvent, card: PanelContainer) -> void:
	if not (event is InputEventMouseButton and (event as InputEventMouseButton).pressed):
		return
	if not card.has_meta("hero_data"):
		return
	var hero: Dictionary = card.get_meta("hero_data")
	_assign_hero_to_team(hero)


func _on_hero_card_hover(card: PanelContainer, entered: bool) -> void:
	if not is_instance_valid(card):
		return
	var hero_id: int = int(card.get_meta("hero_id", -1))
	var unavailable: bool = _is_hero_unavailable(hero_id, card.get_meta("hero_data", {}))
	if unavailable:
		return
	var style: StyleBoxFlat = (card.get_theme_stylebox("panel") as StyleBoxFlat)
	if style == null:
		return
	if entered:
		var hover_style := style.duplicate() as StyleBoxFlat
		hover_style.border_color = Color(0.81, 0.71, 0.44, 0.8)
		card.add_theme_stylebox_override("panel", hover_style)
	else:
		_apply_card_availability(card)


func _refresh_hero_grid_availability() -> void:
	for card in _hero_cards:
		if is_instance_valid(card):
			_apply_card_availability(card)


func _apply_card_availability(card: PanelContainer) -> void:
	if not is_instance_valid(card):
		return
	var hero_id: int = int(card.get_meta("hero_id", -1))
	var hero: Dictionary = card.get_meta("hero_data", {})
	var unavailable: bool = _is_hero_unavailable(hero_id, hero)
	var in_team: bool = _is_hero_in_team(hero_id)

	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(6)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	style.set_border_width_all(1)

	if in_team:
		style.bg_color = Color(0.12, 0.15, 0.22, 0.95)
		style.border_color = Color(0.81, 0.71, 0.44, 0.7)
	elif unavailable:
		style.bg_color = Color(0.08, 0.08, 0.1, 0.6)
		style.border_color = Color(0.25, 0.25, 0.3, 0.4)
	else:
		style.bg_color = Color(0.1, 0.11, 0.15, 0.9)
		style.border_color = Color(0.3, 0.33, 0.42, 0.7)

	card.add_theme_stylebox_override("panel", style)
	card.modulate.a = 0.45 if unavailable else 1.0
	card.mouse_default_cursor_shape = Control.CURSOR_ARROW if unavailable else Control.CURSOR_POINTING_HAND


func _is_hero_unavailable(hero_id: int, hero: Dictionary) -> bool:
	if hero.is_empty():
		return true
	var is_dead: bool = bool(hero.get("is_dead", false))
	var is_healing: bool = bool(hero.get("is_healing", false))
	return is_dead or is_healing


func _is_hero_in_team(hero_id: int) -> bool:
	if hero_id <= 0:
		return false
	for slot in _team_slots:
		if is_instance_valid(slot) and (slot as TeamSlotCard).get_hero_id() == hero_id:
			return true
	return false

# ═══════════════════════════════════════════════════════════════════════════
#  ASSIGNING HEROES TO TEAM
# ═══════════════════════════════════════════════════════════════════════════

func _assign_hero_to_team(hero: Dictionary) -> void:
	var hero_id: int = int(hero.get("id", -1))
	if hero_id <= 0:
		return

	# Check if unavailable
	if _is_hero_unavailable(hero_id, hero):
		var reason: String = ""
		if bool(hero.get("is_dead", false)):
			reason = "dead"
		elif bool(hero.get("is_healing", false)):
			reason = "healing"
		UIUtils.show_warning("Hero is %s and cannot join the team" % reason)
		return

	# Check duplicate
	if _is_hero_in_team(hero_id):
		UIUtils.show_warning("Hero is already in your team")
		return

	# Find first empty slot (or highlighted slot)
	var target_slot: TeamSlotCard = null
	for slot in _team_slots:
		var s := slot as TeamSlotCard
		if s._is_highlighted and s.is_empty():
			target_slot = s
			break
	if target_slot == null:
		for slot in _team_slots:
			if (slot as TeamSlotCard).is_empty():
				target_slot = slot as TeamSlotCard
				break
	if target_slot == null:
		UIUtils.show_warning("Team is full — remove a hero first")
		return

	target_slot.set_hero(hero)
	target_slot.set_highlighted(false)
	_refresh_hero_grid_availability()
	_update_preview()


func _on_autofill_pressed() -> void:
	# Fill empty slots with the strongest available heroes sorted by power
	var available: Array = []
	for h_var in _all_heroes:
		if not h_var is Dictionary:
			continue
		var hero := h_var as Dictionary
		var hid := int(hero.get("id", -1))
		if _is_hero_unavailable(hid, hero):
			continue
		if _is_hero_in_team(hid):
			continue
		available.append(hero)

	available.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _stat_total(a.get("stats", {})) > _stat_total(b.get("stats", {})))

	var filled: int = 0
	for slot in _team_slots:
		var s := slot as TeamSlotCard
		if s.is_empty() and available.size() > 0:
			s.set_hero(available.pop_front())
			filled += 1

	if filled > 0:
		UIUtils.show_success("Auto-filled %d slot%s" % [filled, "" if filled == 1 else "s"])
		_refresh_hero_grid_availability()
		_update_preview()
	else:
		UIUtils.show_info("No empty slots or available heroes")

# ═══════════════════════════════════════════════════════════════════════════
#  BATTLE PREVIEW
# ═══════════════════════════════════════════════════════════════════════════

func _update_preview() -> void:
	var total_power: int = 0
	var filled_count: int = 0
	var required: int = TEAM_SIZE.get(_mode, 1)
	_warnings.clear()

	for slot in _team_slots:
		var s := slot as TeamSlotCard
		if s.is_empty():
			continue
		filled_count += 1
		var hd: Dictionary = s.get_hero_data()
		total_power += _stat_total(hd.get("stats", {}))
		# Check for warnings
		var hp: int = int(hd.get("current_hp", hd.get("hp", 100)))
		var max_hp: int = int(hd.get("max_hp", 100))
		var gen_level: int = int(hd.get("hero_generation_level", 1))
		if max_hp > 0 and hp < max_hp:
			_warnings.append("⚠ %s is injured (%d/%d HP)" % [str(hd.get("name", "Hero")), hp, max_hp])
		if gen_level < 5:
			_warnings.append("⚠ %s has low gen level (%d)" % [str(hd.get("name", "Hero")), gen_level])

	if filled_count < required:
		_warnings.insert(0, "⚠ Need %d more hero%s" % [required - filled_count, "" if (required - filled_count) == 1 else "es"])

	_hero_count_label.text = "Heroes: %d / %d" % [filled_count, required]
	_power_label.text = "Total Power: %d" % total_power

	# Rebuild warning labels
	for child in _warning_container.get_children():
		child.queue_free()

	if _warnings.is_empty():
		var ok_lbl := Label.new()
		ok_lbl.text = "✓ Team ready for battle"
		ok_lbl.add_theme_font_size_override("font_size", 12)
		ok_lbl.add_theme_color_override("font_color", Color(0.3, 0.85, 0.4))
		_warning_container.add_child(ok_lbl)
	else:
		for w in _warnings:
			var w_lbl := Label.new()
			w_lbl.text = w
			w_lbl.add_theme_font_size_override("font_size", 12)
			w_lbl.add_theme_color_override("font_color", Color(0.9, 0.7, 0.25))
			_warning_container.add_child(w_lbl)

	# Enable/disable queue button
	var can_queue: bool = (filled_count >= required) and (_queue_state == QueueState.IDLE)
	_queue_button.disabled = not can_queue

# ═══════════════════════════════════════════════════════════════════════════
#  QUEUE MANAGEMENT
# ═══════════════════════════════════════════════════════════════════════════

func _set_queue_state(state: int) -> void:
	_queue_state = state
	_queue_status_label.text = QUEUE_TEXTS.get(state, "Unknown")
	_queue_status_label.add_theme_color_override("font_color", QUEUE_COLORS.get(state, Color.WHITE))

	_queue_button.visible = (state == QueueState.IDLE)
	_cancel_button.visible = (state == QueueState.SEARCHING)
	_autofill_button.disabled = (state != QueueState.IDLE)

	# Lock mode buttons while in queue
	for m in _mode_buttons:
		(_mode_buttons[m] as Button).disabled = (state != QueueState.IDLE)

	_update_preview()


func _on_queue_pressed() -> void:
	var hero_ids: Array = _collect_team_ids()
	var required: int = TEAM_SIZE.get(_mode, 1)
	if hero_ids.size() < required:
		UIUtils.show_warning("Need %d heroes for %s" % [required, _mode])
		return

	# C4: Register the lead hero as active so BattleRoom can submit the queue
	HeroManager.set_active_hero_id(int(hero_ids[0]))

	# C3: Navigate to BattleRoom which handles the real server queue + WebSocket
	# matchmaking. The old ApiClient.queue_arena() + _simulate_match_found() are removed.
	var routed: bool = EventBus.navigate_to(EventBus.SCENE_BATTLE_ROOM)
	if routed == false:
		UIUtils.show_error("Failed to open BattleRoom route")


func _on_cancel_queue() -> void:
	_set_queue_state(QueueState.IDLE)
	UIUtils.show_info("Left the queue")


# ═══════════════════════════════════════════════════════════════════════════
#  HELPERS
# ═══════════════════════════════════════════════════════════════════════════

func _collect_team_ids() -> Array:
	var ids: Array = []
	for slot in _team_slots:
		var hid: int = (slot as TeamSlotCard).get_hero_id()
		if hid > 0:
			ids.append(hid)
	return ids


func _hero_portrait_color(hero_name: String) -> Color:
	## Deterministic color derived from hero name for the portrait placeholder.
	var h: int = hash(hero_name)
	var r: float = ((h & 0xFF) as float) / 255.0 * 0.3 + 0.12
	var g: float = (((h >> 8) & 0xFF) as float) / 255.0 * 0.3 + 0.12
	var b: float = (((h >> 16) & 0xFF) as float) / 255.0 * 0.3 + 0.15
	return Color(r, g, b, 0.85)


## Sum all 8 v2 core stats to produce a single power number.
static func _stat_total(stats: Dictionary) -> int:
	var total: int = 0
	for key: String in ["stamina", "strength", "willpower", "reflex", "resilience", "focus", "adaptability", "luck"]:
		total += int(stats.get(key, 0))
	return total


func _section_style() -> StyleBoxFlat:
	## Reusable section panel style consistent with GameTheme.tres.
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.07, 0.08, 0.1, 0.85)
	s.border_color = Color(0.3, 0.33, 0.42, 0.5)
	s.set_border_width_all(1)
	s.set_corner_radius_all(8)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s
