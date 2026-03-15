## EmptyState — placeholder shown when a list/grid has no content.
## Shows icon, title, and optional description.
class_name EmptyState
extends VBoxContainer

var _icon_label: Label
var _title_label: Label
var _desc_label: Label


func _ready() -> void:
	alignment = BoxContainer.ALIGNMENT_CENTER
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)

	_icon_label = Label.new()
	_icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_icon_label.add_theme_font_size_override("font_size", 32)
	_icon_label.add_theme_color_override("font_color", Color(0.45, 0.48, 0.55))
	_icon_label.text = "—"
	add_child(_icon_label)

	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 16)
	_title_label.add_theme_color_override("font_color", Color(0.65, 0.68, 0.75))
	add_child(_title_label)

	_desc_label = Label.new()
	_desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_desc_label.add_theme_font_size_override("font_size", 13)
	_desc_label.add_theme_color_override("font_color", Color(0.5, 0.53, 0.6))
	_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_desc_label)


func configure(title: String, description: String = "", icon: String = "—") -> void:
	if _icon_label:
		_icon_label.text = icon
	if _title_label:
		_title_label.text = title
	if _desc_label:
		_desc_label.text = description
		_desc_label.visible = not description.is_empty()


## Alias used by modules.
func set_content(title: String, description: String = "") -> void:
	configure(title, description)
