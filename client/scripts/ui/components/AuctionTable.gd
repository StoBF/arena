extends VBoxContainer

signal lot_selected(lot: Dictionary)

const DEFAULT_ICON: Texture2D = preload("res://icon.svg")

@onready var rows_container: VBoxContainer = $Rows
@onready var item_header: Label = $Header/ItemNameHeader
@onready var seller_header: Label = $Header/SellerHeader
@onready var current_header: Label = $Header/CurrentPriceHeader
@onready var buyout_header: Label = $Header/BuyoutHeader
@onready var time_header: Label = $Header/TimeHeader

var _selected_lot_id: int = -1
var _time_cells: Array = []
var _time_tick_accumulator: float = 0.0

func _ready() -> void:
	set_process(true)
	if LocalizationManager.locale_changed.is_connected(_on_locale_changed) == false:
		LocalizationManager.locale_changed.connect(_on_locale_changed)
	_apply_translations()

func _process(delta: float) -> void:
	_time_tick_accumulator += delta
	if _time_tick_accumulator < 1.0:
		return
	_time_tick_accumulator = 0.0
	_refresh_time_cells()

func set_lots(lots: Array) -> void:
	for child in rows_container.get_children():
		child.queue_free()
	_time_cells.clear()

	if lots.is_empty():
		var empty_label := Label.new()
		empty_label.text = tr("ui.auction_table.empty")
		rows_container.add_child(empty_label)
		_selected_lot_id = -1
		return

	for lot_variant in lots:
		if lot_variant is Dictionary:
			var lot := lot_variant as Dictionary
			rows_container.add_child(_create_row(lot))

func clear_selection() -> void:
	_selected_lot_id = -1
	for child in rows_container.get_children():
		if child is Button:
			(child as Button).button_pressed = false

func _create_row(lot: Dictionary) -> Control:
	var row := Button.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.flat = true
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.toggle_mode = true
	row.button_pressed = int(lot.get("id", -1)) == _selected_lot_id
	row.custom_minimum_size = Vector2(0, 34)
	row.pressed.connect(func(): _on_row_pressed(lot))

	var content := HBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 8)

	var icon := TextureRect.new()
	icon.texture = DEFAULT_ICON
	icon.custom_minimum_size = Vector2(24, 24)
	icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	content.add_child(icon)

	content.add_child(_cell(_lot_item_name(lot), 180))
	content.add_child(_cell(str(lot.get("seller", lot.get("seller_name", "-"))), 130))
	content.add_child(_cell(_price_value(lot, ["current_price", "current_bid", "starting_price"]), 110))
	content.add_child(_cell(_price_value(lot, ["buyout", "buyout_price"]), 110))
	var time_label := _cell("-", 130)
	content.add_child(time_label)
	_time_cells.append({
		"row": row,
		"label": time_label,
		"meta": _build_time_meta(lot),
	})
	_update_time_label(time_label, _time_cells[_time_cells.size() - 1]["meta"] as Dictionary)

	row.add_child(content)
	return row

func _cell(text_value: String, width: int) -> Label:
	var label := Label.new()
	label.text = text_value
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

func _time_left_text(lot: Dictionary) -> String:
	if lot.has("remaining_time"):
		return str(lot.get("remaining_time", "-"))
	if lot.has("time_left"):
		return str(lot.get("time_left", "-"))
	if lot.has("expires_in"):
		return str(lot.get("expires_in", "-"))

	var expires_raw: String = str(lot.get("expires_at", lot.get("end_time", lot.get("ends_at", ""))))
	if expires_raw.is_empty():
		return "-"
	return expires_raw

func _build_time_meta(lot: Dictionary) -> Dictionary:
	if lot.has("remaining_seconds"):
		return {
			"mode": "relative",
			"start_seconds": maxi(0, int(lot.get("remaining_seconds", 0))),
			"captured_unix": int(Time.get_unix_time_from_system()),
		}
	if lot.has("expires_in"):
		return {
			"mode": "relative",
			"start_seconds": maxi(0, int(lot.get("expires_in", 0))),
			"captured_unix": int(Time.get_unix_time_from_system()),
		}
	if lot.has("time_left") and (typeof(lot.get("time_left")) == TYPE_INT or typeof(lot.get("time_left")) == TYPE_FLOAT):
		return {
			"mode": "relative",
			"start_seconds": maxi(0, int(lot.get("time_left", 0))),
			"captured_unix": int(Time.get_unix_time_from_system()),
		}

	var expires_raw: String = str(lot.get("expires_at", lot.get("end_time", lot.get("ends_at", ""))))
	if expires_raw.is_empty() == false:
		var normalized: String = _normalize_datetime_string(expires_raw)
		var end_unix: int = int(Time.get_unix_time_from_datetime_string(normalized))
		if end_unix > 0:
			return {
				"mode": "absolute",
				"end_unix": end_unix,
			}

	if lot.has("remaining_time"):
		return {
			"mode": "static",
			"text": str(lot.get("remaining_time", "-")),
		}

	return {
		"mode": "static",
		"text": _time_left_text(lot),
	}

func _refresh_time_cells() -> void:
	for entry_variant in _time_cells:
		if entry_variant is Dictionary == false:
			continue
		var entry := entry_variant as Dictionary
		if entry.has("label") == false or entry.has("meta") == false:
			continue
		var label_variant: Variant = entry["label"]
		if label_variant is Label == false:
			continue
		var left_seconds: int = _seconds_left_from_meta(entry["meta"] as Dictionary)
		_update_time_label(label_variant as Label, entry["meta"] as Dictionary)
		if entry.has("row") and entry["row"] is Button:
			var row_button := entry["row"] as Button
			var expired: bool = left_seconds == 0 and _is_countdown_meta(entry["meta"] as Dictionary)
			row_button.disabled = expired

func _update_time_label(label: Label, meta: Dictionary) -> void:
	var mode: String = str(meta.get("mode", "static"))
	if mode == "absolute":
		var end_unix: int = int(meta.get("end_unix", 0))
		var now_unix: int = int(Time.get_unix_time_from_system())
		var left_absolute: int = maxi(0, end_unix - now_unix)
		label.text = tr("ui.auction_table.expired") if left_absolute == 0 else _format_remaining_with_urgency(left_absolute)
		return
	if mode == "relative":
		var start_seconds: int = int(meta.get("start_seconds", 0))
		var captured_unix: int = int(meta.get("captured_unix", int(Time.get_unix_time_from_system())))
		var now_unix: int = int(Time.get_unix_time_from_system())
		var left_relative: int = maxi(0, start_seconds - maxi(0, now_unix - captured_unix))
		label.text = tr("ui.auction_table.expired") if left_relative == 0 else _format_remaining_with_urgency(left_relative)
		return
	label.text = str(meta.get("text", "-"))

func _format_remaining(seconds_left: int) -> String:
	if seconds_left <= 0:
		return "00:00"
	var hours: int = int(seconds_left / 3600)
	var minutes: int = int((seconds_left % 3600) / 60)
	var seconds: int = int(seconds_left % 60)
	if hours > 0:
		return "%02d:%02d:%02d" % [hours, minutes, seconds]
	return "%02d:%02d" % [minutes, seconds]

func _format_remaining_with_urgency(seconds_left: int) -> String:
	var base: String = _format_remaining(seconds_left)
	if seconds_left <= 10:
		return "‼ %s" % base
	if seconds_left <= 60:
		return "⚠ %s" % base
	return base

func _seconds_left_from_meta(meta: Dictionary) -> int:
	var mode: String = str(meta.get("mode", "static"))
	if mode == "absolute":
		var end_unix: int = int(meta.get("end_unix", 0))
		return maxi(0, end_unix - int(Time.get_unix_time_from_system()))
	if mode == "relative":
		var start_seconds: int = int(meta.get("start_seconds", 0))
		var captured_unix: int = int(meta.get("captured_unix", int(Time.get_unix_time_from_system())))
		return maxi(0, start_seconds - maxi(0, int(Time.get_unix_time_from_system()) - captured_unix))
	return -1

func _is_countdown_meta(meta: Dictionary) -> bool:
	var mode: String = str(meta.get("mode", "static"))
	return mode == "absolute" or mode == "relative"

func _normalize_datetime_string(value: String) -> String:
	var text: String = value.strip_edges()
	if text.is_empty():
		return text

	if text.find(" ") != -1 and text.find("T") == -1:
		text = text.replace(" ", "T")

	if text.ends_with("Z"):
		text = text.substr(0, text.length() - 1) + "+00:00"

	var plus_idx: int = text.rfind("+")
	var minus_idx: int = text.rfind("-")
	var tz_idx: int = maxi(plus_idx, minus_idx)
	if tz_idx <= 10:
		tz_idx = -1

	var main_part: String = text
	var tz_part: String = ""
	if tz_idx != -1:
		main_part = text.substr(0, tz_idx)
		tz_part = text.substr(tz_idx)

	var dot_idx: int = main_part.find(".")
	if dot_idx != -1:
		main_part = main_part.substr(0, dot_idx)

	if tz_part.length() == 5 and (tz_part.begins_with("+") or tz_part.begins_with("-")):
		tz_part = tz_part.substr(0, 3) + ":" + tz_part.substr(3, 2)

	if tz_part.is_empty() == false and tz_part.length() > 6:
		tz_part = tz_part.substr(0, 6)

	return main_part + tz_part

func _on_row_pressed(lot: Dictionary) -> void:
	_selected_lot_id = int(lot.get("id", -1))
	lot_selected.emit(lot.duplicate(true))

func _on_locale_changed(_locale_code: String) -> void:
	_apply_translations()
	_refresh_time_cells()

func _apply_translations() -> void:
	item_header.text = tr("ui.auction_table.item")
	seller_header.text = tr("ui.auction_table.seller")
	current_header.text = tr("ui.auction_table.current")
	buyout_header.text = tr("ui.auction_table.buyout")
	time_header.text = tr("ui.auction_table.remaining")
