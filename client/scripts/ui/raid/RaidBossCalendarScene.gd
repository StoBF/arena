extends Control
## RaidBossCalendarScene.gd
## Shows upcoming raid boss spawns grouped by category.
## Fetches /raid-bosses/calendar and /raid-bosses/ (active spawns).

signal boss_selected(template_id: int, spawn_id: int)

@onready var hourly_list:   VBoxContainer = $MarginContainer/VBox/Categories/Hourly/List
@onready var halfday_list:  VBoxContainer = $MarginContainer/VBox/Categories/HalfDay/List
@onready var weekly_list:   VBoxContainer = $MarginContainer/VBox/Categories/Weekly/List
@onready var monthly_list:  VBoxContainer = $MarginContainer/VBox/Categories/Monthly/List
@onready var status_label:  Label         = $MarginContainer/VBox/StatusLabel
@onready var refresh_btn:   Button        = $MarginContainer/VBox/TopBar/RefreshBtn

var _calendar_data: Array = []
var _active_spawns: Dictionary = {}   # template_id -> spawn data

const CATEGORY_MAP: Dictionary = {
	"hourly":   "Hourly",
	"half_day": "HalfDay",
	"weekly":   "Weekly",
	"monthly":  "Monthly",
}

const CATEGORY_COLORS: Dictionary = {
	"hourly":   Color(0.4, 0.8, 0.4),
	"half_day": Color(0.4, 0.6, 1.0),
	"weekly":   Color(0.9, 0.5, 0.2),
	"monthly":  Color(0.9, 0.2, 0.2),
}

func _ready() -> void:
	refresh_btn.pressed.connect(_on_refresh_pressed)
	_load_data()

func _load_data() -> void:
	status_label.text = "Loading..."
	_clear_lists()
	var api: ApiClient = ApiClient.new()
	add_child(api)
	# Fetch calendar and active spawns in parallel
	var cal_result = await api.get_raid_calendar()
	var spawn_result = await api.get_active_raid_spawns()
	api.queue_free()

	if cal_result.has("error"):
		status_label.text = "Error: " + str(cal_result.get("error", ""))
		return

	_calendar_data = cal_result if cal_result is Array else []

	# Build active spawn lookup
	_active_spawns.clear()
	if spawn_result is Array:
		for sp in spawn_result:
			_active_spawns[sp.get("template_id", -1)] = sp

	_build_ui()
	status_label.text = "Tap a boss to see details."

func _clear_lists() -> void:
	for list in [hourly_list, halfday_list, weekly_list, monthly_list]:
		if list:
			for ch in list.get_children():
				ch.queue_free()

func _build_ui() -> void:
	for boss in _calendar_data:
		var category: String = boss.get("category", "hourly")
		var list = _get_list_for_category(category)
		if not list:
			continue
		list.add_child(_make_boss_card(boss))

func _make_boss_card(data: Dictionary) -> PanelContainer:
	var panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	var cat   = data.get("category", "hourly")
	style.bg_color = CATEGORY_COLORS.get(cat, Color(0.3, 0.3, 0.3))
	style.corner_radius_top_left     = 6
	style.corner_radius_top_right    = 6
	style.corner_radius_bottom_left  = 6
	style.corner_radius_bottom_right = 6
	panel.add_theme_stylebox_override("panel", style)

	var hbox = HBoxContainer.new()
	panel.add_child(hbox)
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Boss info
	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(vbox)

	var name_lbl = Label.new()
	name_lbl.text = data.get("name", "Unknown Boss")
	name_lbl.add_theme_font_size_override("font_size", 16)
	vbox.add_child(name_lbl)

	var info_lbl = Label.new()
	var interval = data.get("interval_hours", 1)
	var window   = data.get("window_minutes", 15)
	info_lbl.text = "Every %dh · %d min window · %d clans · %d heroes" % [
		interval, window, data.get("max_clans", 1), data.get("max_heroes", 5)
	]
	info_lbl.add_theme_font_size_override("font_size", 12)
	vbox.add_child(info_lbl)

	var template_id = data.get("template_id", -1)
	if _active_spawns.has(template_id):
		var spawn = _active_spawns[template_id]
		var badge = Label.new()
		badge.text = "🔴 LIVE"
		badge.add_theme_color_override("font_color", Color.RED)
		vbox.add_child(badge)

	if data.get("requires_qualification", false):
		var qual_lbl = Label.new()
		qual_lbl.text = "⭐ Requires %d RAP" % data.get("min_access_points", 0)
		qual_lbl.add_theme_font_size_override("font_size", 11)
		vbox.add_child(qual_lbl)

	# Enter button
	var btn = Button.new()
	btn.text = "View"
	btn.custom_minimum_size = Vector2(70, 0)
	btn.pressed.connect(func():
		var spawn_id = -1
		if _active_spawns.has(template_id):
			spawn_id = _active_spawns[template_id].get("id", -1)
		emit_signal("boss_selected", template_id, spawn_id)
	)
	hbox.add_child(btn)

	return panel

func _get_list_for_category(category: String) -> VBoxContainer:
	match category:
		"hourly":   return hourly_list
		"half_day": return halfday_list
		"weekly":   return weekly_list
		"monthly":  return monthly_list
	return hourly_list

func _on_refresh_pressed() -> void:
	_load_data()
