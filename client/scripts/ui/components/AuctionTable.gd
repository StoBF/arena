extends VBoxContainer

signal lot_selected(lot: Dictionary)

const AUCTION_ROW_SCRIPT := preload("res://scripts/ui/components/auction_row/AuctionRow.gd")

@onready var rows_container: VBoxContainer = $Rows
@onready var item_header: Label = $Header/ItemNameHeader
@onready var seller_header: Label = $Header/SellerHeader
@onready var current_header: Label = $Header/CurrentPriceHeader
@onready var buyout_header: Label = $Header/BuyoutHeader
@onready var time_header: Label = $Header/TimeHeader

var _selected_lot_id: int = -1
var _time_cells: Array = []
var _time_tick_accumulator: float = 0.0
var _row_pool: Array = []
var _empty_label: Label = null

func _ready() -> void:
	set_process(true)
	if LocalizationManager.locale_changed.is_connected(_on_locale_changed) == false:
		LocalizationManager.locale_changed.connect(_on_locale_changed)
	_apply_translations()

func _process(delta: float) -> void:
	_time_tick_accumulator += delta
	if _time_tick_accumulator < 1.0:
	_refresh_time_cells()

func set_lots(lots: Array) -> void:
			_set_empty_visible(true)
			for row in _row_pool:
				if row is Control:
					(row as Control).visible = false

	if lots.is_empty():
		_set_empty_visible(false)
		var empty_label := Label.new()
		for i: int in range(lots.size()):
			var row = _ensure_row(i)
			row.visible = true
			row.disabled = false
			var lot_variant = lots[i]
		rows_container.add_child(empty_label)
		_selected_lot_id = -1
				row.set_auction_lot(lot)
				row.set_selected(int(lot.get("id", -1)) == _selected_lot_id)
				_time_cells.append({
					"row": row,
					"meta": _build_time_meta(lot),
				})
				_update_row_time(row, _time_cells[_time_cells.size() - 1]["meta"] as Dictionary)

		for i: int in range(lots.size(), _row_pool.size()):
			if _row_pool[i] is Control:
				(_row_pool[i] as Control).visible = false

	for lot_variant in lots:
		if lot_variant is Dictionary:
		for row in _row_pool:
			if row.has_method("set_selected"):
				row.set_selected(false)
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
		if entry.has("row") == false or entry.has("meta") == false:
			continue
		var row_variant: Variant = entry["row"]
		if row_variant is Control == false:
			continue
		if (row_variant as Control).visible == false:
			continue
		var left_seconds: int = _seconds_left_from_meta(entry["meta"] as Dictionary)
		_update_row_time(row_variant, entry["meta"] as Dictionary)
		if row_variant is Button:
			var row_button := row_variant as Button
			var expired: bool = left_seconds == 0 and _is_countdown_meta(entry["meta"] as Dictionary)
			row_button.disabled = expired

func _update_row_time(row: Object, meta: Dictionary) -> void:
	var mode: String = str(meta.get("mode", "static"))
	if mode == "absolute":
		var end_unix: int = int(meta.get("end_unix", 0))
		var now_unix: int = int(Time.get_unix_time_from_system())
		var left_absolute: int = maxi(0, end_unix - now_unix)
		if row.has_method("set_time_text"):
			row.set_time_text(tr("ui.auction_table.expired") if left_absolute == 0 else _format_remaining_with_urgency(left_absolute))
		return
	if mode == "relative":
		var start_seconds: int = int(meta.get("start_seconds", 0))
		var captured_unix: int = int(meta.get("captured_unix", int(Time.get_unix_time_from_system())))
		var now_unix: int = int(Time.get_unix_time_from_system())
		var left_relative: int = maxi(0, start_seconds - maxi(0, now_unix - captured_unix))
		if row.has_method("set_time_text"):
			row.set_time_text(tr("ui.auction_table.expired") if left_relative == 0 else _format_remaining_with_urgency(left_relative))
		return
	if row.has_method("set_time_text"):
		row.set_time_text(str(meta.get("text", "-")))

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
	for row in _row_pool:
		if row.has_method("get_lot_id") and row.has_method("set_selected"):
			row.set_selected(row.get_lot_id() == _selected_lot_id)
	lot_selected.emit(lot.duplicate(true))

func _ensure_row(index: int) -> Object:
	if index < _row_pool.size():
		return _row_pool[index]
	var row = AUCTION_ROW_SCRIPT.new()
	if row.has_signal("row_selected") and row.row_selected.is_connected(_on_row_pressed) == false:
		row.row_selected.connect(_on_row_pressed)
	rows_container.add_child(row)
	_row_pool.append(row)
	return row

func _set_empty_visible(visible: bool) -> void:
	if _empty_label == null:
		_empty_label = Label.new()
		_empty_label.text = tr("ui.auction_table.empty")
		rows_container.add_child(_empty_label)
	_empty_label.text = tr("ui.auction_table.empty")
	_empty_label.visible = visible

func _on_locale_changed(_locale_code: String) -> void:
	_apply_translations()
	_refresh_time_cells()

func _apply_translations() -> void:
	item_header.text = tr("ui.auction_table.item")
	seller_header.text = tr("ui.auction_table.seller")
	current_header.text = tr("ui.auction_table.current")
	buyout_header.text = tr("ui.auction_table.buyout")
	time_header.text = tr("ui.auction_table.remaining")
