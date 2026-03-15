extends VBoxContainer

## AuctionTable — scrollable row-based auction lot listing with live countdown timers.

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

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------
func _ready() -> void:
	set_process(true)
	if not LocalizationManager.locale_changed.is_connected(_on_locale_changed):
		LocalizationManager.locale_changed.connect(_on_locale_changed)
	_apply_translations()

func _process(delta: float) -> void:
	_time_tick_accumulator += delta
	if _time_tick_accumulator < 1.0:
		return
	_time_tick_accumulator = 0.0
	_refresh_time_cells()

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------
func set_lots(lots: Array) -> void:
	_time_cells.clear()

	if lots.is_empty():
		# Hide all rows, show empty label
		for row in _row_pool:
			if row is Control:
				(row as Control).visible = false
		_set_empty_visible(true)
		return

	_set_empty_visible(false)

	for i: int in range(lots.size()):
		var lot_variant = lots[i]
		if not lot_variant is Dictionary:
			continue
		var lot := lot_variant as Dictionary
		var row = _ensure_row(i)
		row.visible = true
		if row is Button:
			(row as Button).disabled = false
		if row.has_method("set_auction_lot"):
			row.set_auction_lot(lot)
		if row.has_method("set_selected"):
			row.set_selected(int(lot.get("id", -1)) == _selected_lot_id)
		var meta: Dictionary = _build_time_meta(lot)
		_time_cells.append({"row": row, "meta": meta})
		_update_row_time(row, meta)

	# Hide remaining pooled rows
	for i: int in range(lots.size(), _row_pool.size()):
		if _row_pool[i] is Control:
			(_row_pool[i] as Control).visible = false

# ---------------------------------------------------------------------------
# Time metadata builders
# ---------------------------------------------------------------------------
func _build_time_meta(lot: Dictionary) -> Dictionary:
	# Relative seconds sources
	for key in ["remaining_seconds", "expires_in"]:
		if lot.has(key):
			return {
				"mode": "relative",
				"start_seconds": maxi(0, int(lot.get(key, 0))),
				"captured_unix": int(Time.get_unix_time_from_system()),
			}
	if lot.has("time_left") and (typeof(lot.get("time_left")) == TYPE_INT or typeof(lot.get("time_left")) == TYPE_FLOAT):
		return {
			"mode": "relative",
			"start_seconds": maxi(0, int(lot.get("time_left", 0))),
			"captured_unix": int(Time.get_unix_time_from_system()),
		}

	# Absolute datetime sources
	var expires_raw: String = str(lot.get("expires_at", lot.get("end_time", lot.get("ends_at", ""))))
	if not expires_raw.is_empty():
		var normalized: String = DateTimeUtils.normalize_datetime(expires_raw)
		var end_unix: int = int(Time.get_unix_time_from_datetime_string(normalized))
		if end_unix > 0:
			return {"mode": "absolute", "end_unix": end_unix}

	# Static text fallback
	if lot.has("remaining_time"):
		return {"mode": "static", "text": str(lot.get("remaining_time", "-"))}

	return {"mode": "static", "text": "-"}

# ---------------------------------------------------------------------------
# Timer tick
# ---------------------------------------------------------------------------
func _refresh_time_cells() -> void:
	for entry_variant in _time_cells:
		if not entry_variant is Dictionary:
			continue
		var entry := entry_variant as Dictionary
		if not entry.has("row") or not entry.has("meta"):
			continue
		var row_variant: Variant = entry["row"]
		if not row_variant is Control:
			continue
		if not (row_variant as Control).visible:
			continue
		var meta := entry["meta"] as Dictionary
		_update_row_time(row_variant, meta)
		var left_seconds: int = _seconds_left_from_meta(meta)
		if row_variant is Button:
			(row_variant as Button).disabled = left_seconds == 0 and _is_countdown_meta(meta)

func _update_row_time(row: Object, meta: Dictionary) -> void:
	var mode: String = str(meta.get("mode", "static"))
	if mode == "absolute":
		var left: int = maxi(0, int(meta.get("end_unix", 0)) - int(Time.get_unix_time_from_system()))
		if row.has_method("set_time_text"):
			row.set_time_text(tr("ui.auction_table.expired") if left == 0 else DateTimeUtils.format_countdown_urgent(left))
		return
	if mode == "relative":
		var start_seconds: int = int(meta.get("start_seconds", 0))
		var captured_unix: int = int(meta.get("captured_unix", int(Time.get_unix_time_from_system())))
		var elapsed: int = maxi(0, int(Time.get_unix_time_from_system()) - captured_unix)
		var left: int = maxi(0, start_seconds - elapsed)
		if row.has_method("set_time_text"):
			row.set_time_text(tr("ui.auction_table.expired") if left == 0 else DateTimeUtils.format_countdown_urgent(left))
		return
	if row.has_method("set_time_text"):
		row.set_time_text(str(meta.get("text", "-")))

func _seconds_left_from_meta(meta: Dictionary) -> int:
	var mode: String = str(meta.get("mode", "static"))
	if mode == "absolute":
		return maxi(0, int(meta.get("end_unix", 0)) - int(Time.get_unix_time_from_system()))
	if mode == "relative":
		var start_seconds: int = int(meta.get("start_seconds", 0))
		var captured_unix: int = int(meta.get("captured_unix", int(Time.get_unix_time_from_system())))
		return maxi(0, start_seconds - maxi(0, int(Time.get_unix_time_from_system()) - captured_unix))
	return -1

func _is_countdown_meta(meta: Dictionary) -> bool:
	var mode: String = str(meta.get("mode", "static"))
	return mode == "absolute" or mode == "relative"

# ---------------------------------------------------------------------------
# Row pool + selection
# ---------------------------------------------------------------------------
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
	if row.has_signal("row_selected") and not row.row_selected.is_connected(_on_row_pressed):
		row.row_selected.connect(_on_row_pressed)
	rows_container.add_child(row)
	_row_pool.append(row)
	return row

func _set_empty_visible(show: bool) -> void:
	if _empty_label == null:
		_empty_label = Label.new()
		_empty_label.text = tr("ui.auction_table.empty")
		rows_container.add_child(_empty_label)
	_empty_label.text = tr("ui.auction_table.empty")
	_empty_label.visible = show

# ---------------------------------------------------------------------------
# Localisation
# ---------------------------------------------------------------------------
func _on_locale_changed(_locale_code: String) -> void:
	_apply_translations()
	_refresh_time_cells()

func _apply_translations() -> void:
	item_header.text = tr("ui.auction_table.item")
	seller_header.text = tr("ui.auction_table.seller")
	current_header.text = tr("ui.auction_table.current")
	buyout_header.text = tr("ui.auction_table.buyout")
	time_header.text = tr("ui.auction_table.remaining")
