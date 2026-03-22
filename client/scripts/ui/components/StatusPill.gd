## StatusPill — small colored tag showing hero/entity status.
## Usage: var pill = StatusPill.new(); pill.set_status("injured")
class_name StatusPill
extends PanelContainer

const STATUS_COLORS := {
	"healthy":   Color(0.25, 0.78, 0.35),
	"injured":   Color(0.95, 0.65, 0.15),
	"critical":  Color(0.95, 0.25, 0.2),
	"dead":      Color(0.55, 0.15, 0.15),
	"wounded":   Color(0.95, 0.65, 0.15),
	"severely_injured": Color(0.95, 0.35, 0.2),
	"crippled":  Color(0.85, 0.25, 0.2),
	"healing":   Color(0.45, 0.85, 0.75),
	"on_auction": Color(0.75, 0.65, 0.35),
	"in_queue":  Color(0.65, 0.55, 0.85),
	"idle":      Color(0.55, 0.58, 0.65),
}

var _label: Label
var _status: String = "idle"


func _ready() -> void:
	custom_minimum_size = Vector2(70, 24)
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 12)
	add_child(_label)
	_apply_style()


func set_status(status: String) -> void:
	_status = status.strip_edges().to_lower().replace(" ", "_")
	_apply_style()


func get_status() -> String:
	return _status


func _apply_style() -> void:
	if _label == null:
		return
	_label.text = _status.replace("_", " ").capitalize()
	var color: Color = STATUS_COLORS.get(_status, STATUS_COLORS["idle"])
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color.r, color.g, color.b, 0.18)
	style.border_color = color
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	add_theme_stylebox_override("panel", style)
	_label.add_theme_color_override("font_color", color)
