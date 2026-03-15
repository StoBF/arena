## ErrorBanner — inline error/warning banner that sits at the top of a module.
## Usage: banner.show_error("Failed to load"); banner.show_retry("Retry?", callable)
extends PanelContainer

signal retry_pressed

var _label: Label
var _retry_button: Button
var _content: HBoxContainer


func _ready() -> void:
	visible = false
	custom_minimum_size = Vector2(0, 36)

	_content = HBoxContainer.new()
	_content.add_theme_constant_override("separation", 10)
	add_child(_content)

	_label = Label.new()
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label.add_theme_font_size_override("font_size", 14)
	_content.add_child(_label)

	_retry_button = Button.new()
	_retry_button.text = tr("ui.common.retry")
	_retry_button.custom_minimum_size = Vector2(70, 28)
	_retry_button.visible = false
	_retry_button.pressed.connect(func() -> void: retry_pressed.emit())
	_content.add_child(_retry_button)


func show_error(message: String, show_retry: bool = false) -> void:
	_apply_style(Color(0.95, 0.25, 0.25))
	_label.text = message
	_retry_button.visible = show_retry
	visible = true


func show_warning(message: String) -> void:
	_apply_style(Color(0.95, 0.75, 0.2))
	_label.text = message
	_retry_button.visible = false
	visible = true


func hide_banner() -> void:
	visible = false


func _apply_style(color: Color) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color.r, color.g, color.b, 0.12)
	style.border_color = Color(color.r, color.g, color.b, 0.6)
	style.border_width_left = 3
	style.border_width_top = 0
	style.border_width_right = 0
	style.border_width_bottom = 0
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	add_theme_stylebox_override("panel", style)
	_label.add_theme_color_override("font_color", color)
