## DetailPanel — reusable right-side detail view with key/value rows.
## Usage: panel.set_title("Excalibur"); panel.set_fields([["Rarity","Legendary"],["Damage","45"]])
class_name DetailPanel
extends PanelContainer

var _content: VBoxContainer
var _title_label: Label
var _fields_container: VBoxContainer
var _action_row: HBoxContainer


func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.09, 0.9)
	style.border_color = Color(0.3, 0.33, 0.4, 0.5)
	style.border_width_left = 1
	style.set_corner_radius_all(8)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	add_theme_stylebox_override("panel", style)

	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 6)
	add_child(_content)

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 18)
	_title_label.add_theme_color_override("font_color", Color(0.92, 0.88, 0.72))
	_title_label.text = "-"
	_content.add_child(_title_label)

	var separator := HSeparator.new()
	_content.add_child(separator)

	_fields_container = VBoxContainer.new()
	_fields_container.add_theme_constant_override("separation", 3)
	_fields_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_child(_fields_container)

	_action_row = HBoxContainer.new()
	_action_row.add_theme_constant_override("separation", 8)
	_content.add_child(_action_row)


func set_title(text: String) -> void:
	if _title_label:
		_title_label.text = text


## Set key-value fields.
## Accepts either Array of [key, value] pairs OR a Dictionary {key: value}.
func set_fields(fields: Variant) -> void:
	if _fields_container == null:
		return
	for child in _fields_container.get_children():
		child.queue_free()
	var pairs: Array = []
	if fields is Dictionary:
		for key in (fields as Dictionary).keys():
			pairs.append([str(key), str((fields as Dictionary)[key])])
	elif fields is Array:
		pairs = fields as Array
	for field in pairs:
		if field is Array == false or (field as Array).size() < 2:
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)

		var key_label := Label.new()
		key_label.text = str(field[0]) + ":"
		key_label.custom_minimum_size = Vector2(100, 0)
		key_label.add_theme_font_size_override("font_size", 14)
		key_label.add_theme_color_override("font_color", Color(0.6, 0.63, 0.7))
		row.add_child(key_label)

		var val_label := Label.new()
		val_label.text = str(field[1])
		val_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		val_label.add_theme_font_size_override("font_size", 14)
		val_label.add_theme_color_override("font_color", Color(0.88, 0.9, 0.95))
		row.add_child(val_label)

		_fields_container.add_child(row)


## Clear all action buttons and add new ones. buttons: Array of [text: String, callback: Callable].
func set_actions(buttons: Array) -> void:
	if _action_row == null:
		return
	for child in _action_row.get_children():
		child.queue_free()
	for entry in buttons:
		if entry is Array == false or (entry as Array).size() < 2:
			continue
		var btn := Button.new()
		btn.text = str(entry[0])
		btn.custom_minimum_size = Vector2(90, 32)
		if entry[1] is Callable:
			btn.pressed.connect(entry[1] as Callable)
		_action_row.add_child(btn)


func clear_panel() -> void:
	set_title("-")
	set_fields([])
	set_actions([])
