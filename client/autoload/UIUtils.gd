extends Node

## Visible toast notification system.
## UIUtils is an autoload — it creates a CanvasLayer so toasts render on top of everything.

const ERROR_COLOR := Color(0.95, 0.25, 0.25)
const SUCCESS_COLOR := Color(0.25, 0.85, 0.35)
const WARNING_COLOR := Color(0.95, 0.75, 0.2)
const INFO_COLOR := Color(0.6, 0.75, 0.95)

const TOAST_DURATION := 3.5
const TOAST_MAX := 5

var _canvas_layer: CanvasLayer
var _toast_container: VBoxContainer
var _active_toasts: Array = []


func _ready() -> void:
	# CanvasLayer ensures toasts appear above all UI
	_canvas_layer = CanvasLayer.new()
	_canvas_layer.layer = 100
	add_child(_canvas_layer)

	# Anchor container to top-center of screen
	var anchor := Control.new()
	anchor.set_anchors_preset(Control.PRESET_FULL_RECT)
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas_layer.add_child(anchor)

	_toast_container = VBoxContainer.new()
	_toast_container.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast_container.offset_top = 20
	_toast_container.offset_left = -200
	_toast_container.offset_right = 200
	_toast_container.custom_minimum_size = Vector2(400, 0)
	_toast_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_container.add_theme_constant_override("separation", 6)
	anchor.add_child(_toast_container)


func show_error(message: String) -> void:
	_show_toast(message, ERROR_COLOR)


func show_success(message: String) -> void:
	_show_toast(message, SUCCESS_COLOR)


func show_warning(message: String) -> void:
	_show_toast(message, WARNING_COLOR)


func show_info(message: String) -> void:
	_show_toast(message, INFO_COLOR)


func _show_toast(message: String, color: Color) -> void:
	# Enforce max visible toasts
	while _active_toasts.size() >= TOAST_MAX:
		var old: Control = _active_toasts.pop_front()
		if is_instance_valid(old):
			old.queue_free()

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.12, 0.95)
	style.border_color = color
	style.border_width_left = 3
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var label := Label.new()
	label.text = message
	label.add_theme_color_override("font_color", Color(0.92, 0.93, 0.96))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(label)

	_toast_container.add_child(panel)
	_active_toasts.append(panel)

	# Fade in
	panel.modulate = Color(1, 1, 1, 0)
	var tween := create_tween()
	tween.tween_property(panel, "modulate", Color(1, 1, 1, 1), 0.2)
	tween.tween_interval(TOAST_DURATION)
	tween.tween_property(panel, "modulate", Color(1, 1, 1, 0), 0.3)
	tween.tween_callback(func() -> void:
		_active_toasts.erase(panel)
		if is_instance_valid(panel):
			panel.queue_free()
	)
