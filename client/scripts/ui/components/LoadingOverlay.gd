## LoadingOverlay — semi-transparent overlay with pulsing "Loading..." text.
## Add as child of any container and call show_loading() / hide_loading().
class_name LoadingOverlay
extends ColorRect

var _label: Label
var _tween: Tween


func _ready() -> void:
	color = Color(0.04, 0.05, 0.07, 0.75)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	_label = Label.new()
	_label.text = tr("ui.common.loading")
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.set_anchors_preset(Control.PRESET_CENTER)
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_color", Color(0.8, 0.78, 0.65))
	add_child(_label)


func show_loading(text: String = "") -> void:
	if not text.is_empty():
		_label.text = text
	else:
		_label.text = tr("ui.common.loading")
	visible = true
	_start_pulse()


func hide_loading() -> void:
	visible = false
	if _tween and _tween.is_valid():
		_tween.kill()


func _start_pulse() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_loops()
	_tween.tween_property(_label, "modulate:a", 0.4, 0.8)
	_tween.tween_property(_label, "modulate:a", 1.0, 0.8)
