## BodyPartStatusRow — shows a body part with its current damage/status.
## Used in hero detail panel for future combat injury tracking.
class_name BodyPartStatusRow
extends HBoxContainer

const CONDITION_COLORS := {
	"healthy":  Color(0.25, 0.78, 0.35),
	"bruised":  Color(0.75, 0.75, 0.3),
	"wounded":  Color(0.95, 0.55, 0.2),
	"broken":   Color(0.95, 0.3, 0.2),
	"severed":  Color(0.65, 0.15, 0.15),
}

var _name_label: Label
var _status_label: Label
var _bar: ProgressBar


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	custom_minimum_size = Vector2(0, 22)

	_name_label = Label.new()
	_name_label.custom_minimum_size = Vector2(80, 0)
	_name_label.add_theme_font_size_override("font_size", 13)
	_name_label.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
	add_child(_name_label)

	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(60, 14)
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bar.show_percentage = false
	_bar.max_value = 100.0
	_bar.value = 100.0
	add_child(_bar)

	_status_label = Label.new()
	_status_label.custom_minimum_size = Vector2(65, 0)
	_status_label.add_theme_font_size_override("font_size", 12)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_status_label)


## Accepts either (name, hp_percent, condition) or (name, current_hp, max_hp, condition).
func set_data(part_name: String, current_hp: float, max_hp_or_condition: Variant = "healthy", condition: String = "") -> void:
	var hp_percent: float
	var cond: String
	if max_hp_or_condition is String:
		# 3-arg form: set_data(name, percent, condition)
		hp_percent = clampf(current_hp, 0.0, 100.0)
		cond = max_hp_or_condition as String
	else:
		# 4-arg form: set_data(name, current_hp, max_hp, condition)
		var max_hp: float = float(max_hp_or_condition)
		hp_percent = (current_hp / maxf(max_hp, 1.0)) * 100.0
		cond = condition if not condition.is_empty() else "healthy"
	if _name_label:
		_name_label.text = part_name.capitalize()
	if _bar:
		_bar.value = clampf(hp_percent, 0.0, 100.0)
	var color: Color = CONDITION_COLORS.get(cond.to_lower(), CONDITION_COLORS["healthy"])
	if _status_label:
		_status_label.text = cond.capitalize()
		_status_label.add_theme_color_override("font_color", color)
