## ModuleHeader — standard header bar for every module.
## Shows breadcrumb-style title, optional refresh button, optional status text.
class_name ModuleHeader
extends PanelContainer

signal refresh_pressed

var _title_label: Label
var _status_label: Label
var _refresh_button: Button
var _content: HBoxContainer


func _ready() -> void:
	custom_minimum_size = Vector2(0, 48)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.12, 0.9)
	style.border_color = Color(0.43, 0.47, 0.58, 0.85)
	style.border_width_bottom = 1
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	add_theme_stylebox_override("panel", style)

	_content = HBoxContainer.new()
	_content.add_theme_constant_override("separation", 12)
	add_child(_content)

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 19)
	_title_label.add_theme_color_override("font_color", Color(0.92, 0.88, 0.72))
	_content.add_child(_title_label)

	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 13)
	_status_label.add_theme_color_override("font_color", Color(0.6, 0.63, 0.7))
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(_status_label)

	_refresh_button = Button.new()
	_refresh_button.text = CabinetStyle.text("ui.common.refresh", "Refresh")
	_refresh_button.custom_minimum_size = Vector2(100, 34)
	_refresh_button.pressed.connect(func() -> void: refresh_pressed.emit())
	_content.add_child(_refresh_button)

	if LocalizationManager.locale_changed.is_connected(_on_locale_changed) == false:
		LocalizationManager.locale_changed.connect(_on_locale_changed)
	_apply_translations()

func _exit_tree() -> void:
	if LocalizationManager.locale_changed.is_connected(_on_locale_changed):
		LocalizationManager.locale_changed.disconnect(_on_locale_changed)

func _on_locale_changed(_locale_code: String) -> void:
	_apply_translations()

func _apply_translations() -> void:
	if _refresh_button != null:
		_refresh_button.text = CabinetStyle.text("ui.common.refresh", "Refresh")


func set_title(text: String) -> void:
	if _title_label:
		_title_label.text = text


func set_status(text: String) -> void:
	if _status_label:
		_status_label.text = text


func set_refresh_visible(visible: bool) -> void:
	if _refresh_button:
		_refresh_button.visible = visible
