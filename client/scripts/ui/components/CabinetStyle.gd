class_name CabinetStyle
extends RefCounted

const PANEL_TITLE_COLOR := Color(0.92, 0.88, 0.72)
const PANEL_MUTED_COLOR := Color(0.6, 0.63, 0.7)
const PANEL_ACCENT_COLOR := Color(0.45, 0.5, 0.62)

static func text(key: String, fallback: String) -> String:
	var value: String = tr(key)
	if value == key:
		return fallback
	return value

static func textf(key: String, fallback: String, args: Array = []) -> String:
	var base: String = text(key, fallback)
	if args.is_empty():
		return base
	return base % args

static func style_screen(root: Control) -> void:
	if root == null:
		return
	_style_tree(root)

static func style_header(title_label: Label, refresh_button: Button = null) -> void:
	if title_label != null:
		title_label.add_theme_font_size_override("font_size", 20)
		title_label.add_theme_color_override("font_color", PANEL_TITLE_COLOR)
	if refresh_button != null:
		style_button(refresh_button)

static func style_button(button: Button, min_width: int = 0) -> void:
	if button == null:
		return
	button.custom_minimum_size = Vector2(maxf(button.custom_minimum_size.x, float(min_width)), maxf(button.custom_minimum_size.y, 38.0))

static func style_status_label(status_label: Label) -> void:
	if status_label == null:
		return
	status_label.add_theme_font_size_override("font_size", 13)
	status_label.add_theme_color_override("font_color", PANEL_MUTED_COLOR)

static func style_section_label(section_label: Label) -> void:
	if section_label == null:
		return
	section_label.add_theme_font_size_override("font_size", 14)
	section_label.add_theme_color_override("font_color", PANEL_TITLE_COLOR)

static func style_module_root(root_vbox: VBoxContainer) -> void:
	if root_vbox == null:
		return
	root_vbox.add_theme_constant_override("separation", 10)

static func _style_tree(node: Node) -> void:
	if node is Button:
		style_button(node as Button)
	elif node is Label:
		_style_label_by_name(node as Label)
	elif node is LineEdit:
		var line_edit := node as LineEdit
		line_edit.custom_minimum_size = Vector2(maxf(line_edit.custom_minimum_size.x, 120.0), maxf(line_edit.custom_minimum_size.y, 36.0))
	elif node is OptionButton:
		var option_button := node as OptionButton
		option_button.custom_minimum_size = Vector2(maxf(option_button.custom_minimum_size.x, 120.0), maxf(option_button.custom_minimum_size.y, 36.0))
	elif node is MarginContainer:
		_style_margin_container(node as MarginContainer)

	for child in node.get_children():
		_style_tree(child)

static func _style_label_by_name(label: Label) -> void:
	var lower_name: String = label.name.to_lower()
	if lower_name.contains("title"):
		label.add_theme_font_size_override("font_size", 18)
		label.add_theme_color_override("font_color", PANEL_TITLE_COLOR)
	elif lower_name.contains("status"):
		style_status_label(label)
	elif lower_name.contains("header"):
		label.add_theme_font_size_override("font_size", 15)

static func _style_margin_container(margin: MarginContainer) -> void:
	var left: int = int(margin.get("theme_override_constants/margin_left"))
	var top: int = int(margin.get("theme_override_constants/margin_top"))
	var right: int = int(margin.get("theme_override_constants/margin_right"))
	var bottom: int = int(margin.get("theme_override_constants/margin_bottom"))
	if left < 10:
		margin.add_theme_constant_override("margin_left", 10)
	if top < 10:
		margin.add_theme_constant_override("margin_top", 10)
	if right < 10:
		margin.add_theme_constant_override("margin_right", 10)
	if bottom < 10:
		margin.add_theme_constant_override("margin_bottom", 10)
