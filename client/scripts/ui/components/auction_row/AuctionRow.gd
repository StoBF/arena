extends Button
class_name AuctionRow

signal row_selected(lot: Dictionary)

const DEFAULT_ICON: Texture2D = preload("res://icon.svg")

var _lot: Dictionary = {}

var _icon: TextureRect
var _item_label: Label
var _seller_label: Label
var _current_label: Label
var _buyout_label: Label
var _time_label: Label

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flat = true
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	toggle_mode = true
	custom_minimum_size = Vector2(0, 34)
	if is_connected("pressed", _on_pressed) == false:
		pressed.connect(_on_pressed)
	if get_child_count() == 0:
		_build_ui()

func set_auction_lot(lot: Dictionary) -> void:
	_lot = lot.duplicate(true)
	_item_label.text = _lot_item_name(_lot)
	_seller_label.text = str(_lot.get("seller", _lot.get("seller_name", "-")))
	_current_label.text = _price_value(_lot, ["current_price", "current_bid", "starting_price"])
	_buyout_label.text = _price_value(_lot, ["buyout", "buyout_price"])
	_time_label.text = "-"

func set_selected(selected: bool) -> void:
	button_pressed = selected

func get_lot_id() -> int:
	return int(_lot.get("id", -1))

func set_time_text(value: String) -> void:
	_time_label.text = value

func _on_pressed() -> void:
	if _lot.is_empty() == false:
		row_selected.emit(_lot.duplicate(true))

func _build_ui() -> void:
	var content := HBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 8)

	_icon = TextureRect.new()
	_icon.texture = DEFAULT_ICON
	_icon.custom_minimum_size = Vector2(24, 24)
	_icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	content.add_child(_icon)

	_item_label = _cell(180)
	content.add_child(_item_label)
	_seller_label = _cell(130)
	content.add_child(_seller_label)
	_current_label = _cell(110)
	content.add_child(_current_label)
	_buyout_label = _cell(110)
	content.add_child(_buyout_label)
	_time_label = _cell(130)
	content.add_child(_time_label)

	add_child(content)

func _cell(width: int) -> Label:
	var label := Label.new()
	label.custom_minimum_size = Vector2(width, 0)
	label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	return label

func _lot_item_name(lot: Dictionary) -> String:
	if lot.has("item_name"):
		return str(lot.get("item_name", "-"))
	if lot.has("name"):
		return str(lot.get("name", "-"))
	if lot.has("hero_name"):
		return str(lot.get("hero_name", "-"))
	if lot.has("hero") and lot["hero"] is Dictionary:
		var hero := lot["hero"] as Dictionary
		if hero.has("name"):
			return str(hero.get("name", "-"))
	return "-"

func _price_value(lot: Dictionary, keys: Array) -> String:
	for key_variant in keys:
		var key := str(key_variant)
		if lot.has(key):
			return "%.2f" % float(lot.get(key, 0.0))
	return "-"
