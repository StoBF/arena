## TeamSlotCard — represents a hero slot in a team composition.
## Used in ArenaModule and BossRaidModule for team building.
## Layout: SlotLabel → HeroPortrait → HeroName + Level → RemoveButton
class_name TeamSlotCard
extends PanelContainer

signal slot_pressed(slot_index: int)
signal hero_removed(slot_index: int)

var _slot_index: int = 0
var _hero_data: Dictionary = {}
var _is_highlighted: bool = false

# Internal nodes
var _content: VBoxContainer
var _slot_label: Label
var _portrait_rect: ColorRect       # placeholder portrait
var _portrait_icon: Label           # emoji / letter fallback centred on portrait
var _name_label: Label
var _level_label: Label
var _stats_label: Label
var _empty_label: Label
var _remove_button: Button
var _style_normal: StyleBoxFlat
var _style_highlight: StyleBoxFlat

const PORTRAIT_SIZE := Vector2(52, 52)


func _ready() -> void:
	custom_minimum_size = Vector2(120, 150)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	# --- Normal style ---
	_style_normal = StyleBoxFlat.new()
	_style_normal.bg_color = Color(0.09, 0.1, 0.13, 0.92)
	_style_normal.border_color = Color(0.35, 0.38, 0.48, 0.7)
	_style_normal.set_border_width_all(1)
	_style_normal.set_corner_radius_all(8)
	_style_normal.content_margin_left = 8
	_style_normal.content_margin_right = 8
	_style_normal.content_margin_top = 8
	_style_normal.content_margin_bottom = 8

	# --- Highlight style (slot selected / hovered fill) ---
	_style_highlight = StyleBoxFlat.new()
	_style_highlight.bg_color = Color(0.14, 0.16, 0.22, 0.95)
	_style_highlight.border_color = Color(0.81, 0.71, 0.44, 0.9)
	_style_highlight.set_border_width_all(2)
	_style_highlight.set_corner_radius_all(8)
	_style_highlight.content_margin_left = 7
	_style_highlight.content_margin_right = 7
	_style_highlight.content_margin_top = 7
	_style_highlight.content_margin_bottom = 7

	add_theme_stylebox_override("panel", _style_normal)

	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 4)
	_content.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(_content)

	# Slot label (e.g. "Slot 1")
	_slot_label = Label.new()
	_slot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_slot_label.add_theme_font_size_override("font_size", 11)
	_slot_label.add_theme_color_override("font_color", Color(0.5, 0.53, 0.6))
	_content.add_child(_slot_label)

	# Portrait placeholder
	var portrait_center := CenterContainer.new()
	_content.add_child(portrait_center)
	_portrait_rect = ColorRect.new()
	_portrait_rect.custom_minimum_size = PORTRAIT_SIZE
	_portrait_rect.color = Color(0.15, 0.16, 0.2, 0.8)
	portrait_center.add_child(_portrait_rect)
	_portrait_icon = Label.new()
	_portrait_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_portrait_icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_portrait_icon.add_theme_font_size_override("font_size", 22)
	_portrait_icon.add_theme_color_override("font_color", Color(0.4, 0.42, 0.5))
	_portrait_icon.text = "?"
	_portrait_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	_portrait_rect.add_child(_portrait_icon)

	# Hero name
	_name_label = Label.new()
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override("font_size", 13)
	_name_label.add_theme_color_override("font_color", Color(0.92, 0.88, 0.72))
	_name_label.visible = false
	_content.add_child(_name_label)

	# Level label
	_level_label = Label.new()
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level_label.add_theme_font_size_override("font_size", 11)
	_level_label.add_theme_color_override("font_color", Color(0.6, 0.63, 0.72))
	_level_label.visible = false
	_content.add_child(_level_label)

	# Stats label (power / wins)
	_stats_label = Label.new()
	_stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stats_label.add_theme_font_size_override("font_size", 10)
	_stats_label.add_theme_color_override("font_color", Color(0.5, 0.55, 0.65))
	_stats_label.visible = false
	_content.add_child(_stats_label)

	# Empty label
	_empty_label = Label.new()
	_empty_label.text = tr("ui.team_slot.empty")
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.add_theme_font_size_override("font_size", 12)
	_empty_label.add_theme_color_override("font_color", Color(0.4, 0.43, 0.5))
	_content.add_child(_empty_label)

	# Remove button
	_remove_button = Button.new()
	_remove_button.text = tr("ui.common.remove")
	_remove_button.custom_minimum_size = Vector2(0, 26)
	_remove_button.visible = false
	_remove_button.pressed.connect(func() -> void: hero_removed.emit(_slot_index))
	_content.add_child(_remove_button)

	gui_input.connect(_on_gui_input)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func set_slot_index(index: int) -> void:
	_slot_index = index
	if _slot_label:
		_slot_label.text = "Slot %d" % (index + 1)


func set_hero(hero: Dictionary) -> void:
	_hero_data = hero.duplicate(true)
	var hero_name: String = str(hero.get("name", "Hero"))
	_name_label.text = hero_name
	_name_label.visible = true
	_level_label.text = "Lv. %s" % str(hero.get("level", "?"))
	_level_label.visible = true
	_empty_label.visible = false
	_remove_button.visible = true
	# Portrait: first letter of name
	_portrait_icon.text = hero_name.substr(0, 1).to_upper() if hero_name.length() > 0 else "?"
	_portrait_icon.add_theme_color_override("font_color", Color(0.92, 0.88, 0.72))
	_portrait_rect.color = Color(0.18, 0.2, 0.28, 0.9)
	# Stats line
	var power: int = int(hero.get("power", hero.get("strength", 0)))
	var wins: int = int(hero.get("wins", 0))
	if power > 0 or wins > 0:
		_stats_label.text = "PWR %d  W %d" % [power, wins]
		_stats_label.visible = true
	else:
		_stats_label.visible = false


func clear_slot() -> void:
	_hero_data = {}
	_name_label.visible = false
	_level_label.visible = false
	_stats_label.visible = false
	_empty_label.visible = true
	_remove_button.visible = false
	_portrait_icon.text = "?"
	_portrait_icon.add_theme_color_override("font_color", Color(0.4, 0.42, 0.5))
	_portrait_rect.color = Color(0.15, 0.16, 0.2, 0.8)
	set_highlighted(false)


func is_empty() -> bool:
	return _hero_data.is_empty()


## Alias used by modules.
func is_empty_slot() -> bool:
	return is_empty()


func get_hero_data() -> Dictionary:
	return _hero_data.duplicate(true)


## Return hero id (int). Returns -1 if slot is empty.
func get_hero_id() -> int:
	return int(_hero_data.get("id", -1))


func set_highlighted(value: bool) -> void:
	_is_highlighted = value
	add_theme_stylebox_override("panel", _style_highlight if value else _style_normal)


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		slot_pressed.emit(_slot_index)


func _on_mouse_entered() -> void:
	if is_empty():
		add_theme_stylebox_override("panel", _style_highlight)


func _on_mouse_exited() -> void:
	if not _is_highlighted:
		add_theme_stylebox_override("panel", _style_normal)
