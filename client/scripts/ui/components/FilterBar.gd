## FilterBar — reusable horizontal filter row with search, dropdown, and apply.
## Emits filters_applied with a Dictionary of current filter values.
extends PanelContainer

signal filters_applied(filters: Dictionary)

var _content: HBoxContainer
var _search_input: LineEdit
var _dropdown: OptionButton
var _extra_input: LineEdit
var _apply_button: Button


func _ready() -> void:
	custom_minimum_size = Vector2(0, 40)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.08, 0.1, 0.7)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	add_theme_stylebox_override("panel", style)

	_content = HBoxContainer.new()
	_content.add_theme_constant_override("separation", 8)
	add_child(_content)

	_search_input = LineEdit.new()
	_search_input.placeholder_text = tr("ui.filter.search_placeholder")
	_search_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_input.custom_minimum_size = Vector2(120, 30)
	_search_input.text_submitted.connect(func(_v: String) -> void: _emit_filters())
	_content.add_child(_search_input)

	_dropdown = OptionButton.new()
	_dropdown.custom_minimum_size = Vector2(100, 30)
	_content.add_child(_dropdown)

	_extra_input = LineEdit.new()
	_extra_input.placeholder_text = tr("ui.filter.min_price")
	_extra_input.custom_minimum_size = Vector2(80, 30)
	_extra_input.visible = false
	_extra_input.text_submitted.connect(func(_v: String) -> void: _emit_filters())
	_content.add_child(_extra_input)

	_apply_button = Button.new()
	_apply_button.text = tr("ui.common.apply")
	_apply_button.custom_minimum_size = Vector2(70, 30)
	_apply_button.pressed.connect(_emit_filters)
	_content.add_child(_apply_button)


## Configure dropdown options. Items: Array of Strings.
func set_dropdown_items(items: Array, include_all: bool = true) -> void:
	_dropdown.clear()
	if include_all:
		_dropdown.add_item(tr("ui.filter.all"), 0)
	var idx := 1 if include_all else 0
	for item in items:
		_dropdown.add_item(str(item), idx)
		idx += 1


## Show or hide the extra input field (e.g., min price).
func set_extra_input_visible(vis: bool, placeholder: String = "") -> void:
	_extra_input.visible = vis
	if not placeholder.is_empty():
		_extra_input.placeholder_text = placeholder


func get_filters() -> Dictionary:
	return {
		"search": _search_input.text.strip_edges().to_lower(),
		"dropdown": _dropdown.get_item_text(_dropdown.selected).to_lower() if _dropdown.item_count > 0 else "",
		"dropdown_index": _dropdown.selected,
		"extra": _extra_input.text.strip_edges(),
	}


func _emit_filters() -> void:
	filters_applied.emit(get_filters())
