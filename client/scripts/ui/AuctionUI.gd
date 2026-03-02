extends Control
class_name AuctionUI

const DEFAULT_PAGE_SIZE := 20
const RARITIES := ["All", "Common", "Rare", "Epic", "Legendary"]
const TYPES := ["Hero", "Equipment", "Recipe"]
const SORTS := ["Time Left", "Price Asc", "Price Desc", "Bids Count"]

@onready var type_dropdown: OptionButton = $Root/Top/FiltersBar/TypeDropdown
@onready var rarity_dropdown: OptionButton = $Root/Top/FiltersBar/RarityDropdown
@onready var price_min: SpinBox = $Root/Top/FiltersBar/PriceMinSpin
@onready var price_max: SpinBox = $Root/Top/FiltersBar/PriceMaxSpin
@onready var seller_filter: LineEdit = $Root/Top/FiltersBar/SellerLineEdit
@onready var sort_dropdown: OptionButton = $Root/Top/FiltersBar/SortDropdown
@onready var search_filter: LineEdit = $Root/Top/FiltersBar/SearchLineEdit

@onready var lots_table: VBoxContainer = $Root/Center/LotsScroll/LotsTable
@onready var page_label: Label = $Root/Bottom/Pagination/PageLabel
@onready var prev_button: Button = $Root/Bottom/Pagination/PrevButton
@onready var next_button: Button = $Root/Bottom/Pagination/NextButton
@onready var lot_details_modal: LotDetailsModal = $LotDetailsModal

var _lot_row_scene: PackedScene = preload("res://scenes/ui/LotRow.tscn")
var _current_page: int = 1
var _page_size: int = DEFAULT_PAGE_SIZE
var _current_items: Array = []
var _current_pagination: Dictionary = {}
var _lot_rows_by_id: Dictionary = {}

func _ready() -> void:
	TopBar.add_to(self, true, true)
	_setup_filters()
	_connect_signals()
	WebSocketManager.ensure_auction_subscription()
	_load_lots()

func _setup_filters() -> void:
	_populate_dropdown(type_dropdown, TYPES)
	_populate_dropdown(rarity_dropdown, RARITIES)
	_populate_dropdown(sort_dropdown, SORTS)
	price_min.min_value = 0
	price_max.min_value = 0
	price_min.step = 1
	price_max.step = 1

func _connect_signals() -> void:
	type_dropdown.item_selected.connect(_on_filter_changed)
	rarity_dropdown.item_selected.connect(_on_filter_changed)
	sort_dropdown.item_selected.connect(_on_filter_changed)
	price_min.value_changed.connect(_on_price_changed)
	price_max.value_changed.connect(_on_price_changed)
	seller_filter.text_changed.connect(_on_filter_text_changed)
	search_filter.text_changed.connect(_on_filter_text_changed)
	prev_button.pressed.connect(_on_prev_page)
	next_button.pressed.connect(_on_next_page)
	lot_details_modal.action_succeeded.connect(_on_modal_action_succeeded)
	if not AuctionManager.lots_fetch_failed.is_connected(_on_lots_failed):
		AuctionManager.lots_fetch_failed.connect(_on_lots_failed)
	if not AuctionManager.bid_received.is_connected(_on_bid_received):
		AuctionManager.bid_received.connect(_on_bid_received)
	if not WebSocketManager.auction_bid_update.is_connected(_on_ws_bid_update):
		WebSocketManager.auction_bid_update.connect(_on_ws_bid_update)
	if not WebSocketManager.auction_lot_closed.is_connected(_on_ws_lot_closed):
		WebSocketManager.auction_lot_closed.connect(_on_ws_lot_closed)
	if not WebSocketManager.auction_lot_created.is_connected(_on_ws_lot_created):
		WebSocketManager.auction_lot_created.connect(_on_ws_lot_created)

func _on_filter_changed(_index: int) -> void:
	_current_page = 1
	_load_lots()

func _on_price_changed(_value: float) -> void:
	_current_page = 1
	_load_lots()

func _on_filter_text_changed(_text: String) -> void:
	_current_page = 1
	_load_lots()

func _on_prev_page() -> void:
	if _current_page <= 1:
		return
	_current_page -= 1
	_load_lots()

func _on_next_page() -> void:
	if not bool(_current_pagination.get("has_next", false)):
		return
	_current_page += 1
	_load_lots()

func _load_lots() -> void:
	var filters: Dictionary = {
		"type": type_dropdown.get_item_text(type_dropdown.selected),
		"rarity": rarity_dropdown.get_item_text(rarity_dropdown.selected),
		"price_min": price_min.value,
		"price_max": price_max.value,
		"seller": seller_filter.text,
		"sort": sort_dropdown.get_item_text(sort_dropdown.selected),
		"search": search_filter.text,
		"page": _current_page,
		"page_size": _page_size
	}
	_current_items = await AuctionManager.fetch_lots(filters)
	_current_pagination = AuctionManager.get_last_pagination()
	_rebuild_lots_table()
	_refresh_pagination()

func _rebuild_lots_table() -> void:
	for child in lots_table.get_children():
		if child.name != "HeaderRow":
			child.queue_free()

	_lot_rows_by_id.clear()
	for lot: Dictionary in _current_items:
		var row: LotRow = _lot_row_scene.instantiate()
		row.set_lot_data(lot)
		row.bid_requested.connect(_on_row_bid_requested)
		row.buy_now_requested.connect(_on_row_buy_now_requested)
		row.details_requested.connect(_on_row_details_requested)
		lots_table.add_child(row)
		var lot_id: int = int(lot.get("id", -1))
		if lot_id > 0:
			_lot_rows_by_id[lot_id] = row

func _refresh_pagination() -> void:
	var total: int = int(_current_pagination.get("total", _current_items.size()))
	var page: int = int(_current_pagination.get("page", _current_page))
	var has_prev: bool = bool(_current_pagination.get("has_prev", page > 1))
	var has_next: bool = bool(_current_pagination.get("has_next", false))
	page_label.text = "Page %d | Total %d" % [page, total]
	prev_button.disabled = not has_prev
	next_button.disabled = not has_next

func _on_row_bid_requested(lot_data: Dictionary) -> void:
	lot_details_modal.open_for_lot(lot_data)

func _on_row_buy_now_requested(lot_data: Dictionary) -> void:
	lot_details_modal.open_for_lot(lot_data)

func _on_row_details_requested(lot_data: Dictionary) -> void:
	lot_details_modal.open_for_lot(lot_data)

func _on_bid_received(lot_id: int, amount: float) -> void:
	if not _lot_rows_by_id.has(lot_id):
		return
	var row: LotRow = _lot_rows_by_id[lot_id]
	row.refresh_bid(amount)

func _on_lots_failed(message: String) -> void:
	UIUtils.show_error(message)

func _on_modal_action_succeeded(_lot_id: int) -> void:
	_load_lots()

func _on_ws_bid_update(event_data: Dictionary) -> void:
	var lot_id: int = int(event_data.get("lot_id", event_data.get("id", -1)))
	if lot_id <= 0:
		return
	if _lot_rows_by_id.has(lot_id):
		var row: LotRow = _lot_rows_by_id[lot_id]
		row.apply_bid_update(event_data)
	_update_local_lot_data(lot_id, event_data)
	lot_details_modal.apply_live_bid_update(event_data)

func _on_ws_lot_closed(event_data: Dictionary) -> void:
	var lot_id: int = int(event_data.get("lot_id", event_data.get("id", -1)))
	if lot_id <= 0:
		return
	if _lot_rows_by_id.has(lot_id):
		var row: LotRow = _lot_rows_by_id[lot_id]
		row.mark_closed()
	_update_local_lot_data(lot_id, {"is_closed": true})
	lot_details_modal.apply_lot_closed(event_data)

func _on_ws_lot_created(event_data: Dictionary) -> void:
	var lot: Dictionary = event_data.duplicate(true)
	if lot.is_empty() and event_data.has("lot") and event_data["lot"] is Dictionary:
		lot = (event_data["lot"] as Dictionary).duplicate(true)
	var lot_id: int = int(lot.get("id", lot.get("lot_id", -1)))
	if lot_id <= 0:
		return
	if _lot_rows_by_id.has(lot_id):
		_update_local_lot_data(lot_id, lot)
		var existing_row: LotRow = _lot_rows_by_id[lot_id]
		existing_row.set_lot_data(_get_local_lot(lot_id))
		return

	_current_items.insert(0, lot.duplicate(true))
	var row: LotRow = _lot_row_scene.instantiate()
	row.set_lot_data(lot)
	row.bid_requested.connect(_on_row_bid_requested)
	row.buy_now_requested.connect(_on_row_buy_now_requested)
	row.details_requested.connect(_on_row_details_requested)
	lots_table.add_child(row)
	lots_table.move_child(row, 1)
	_lot_rows_by_id[lot_id] = row
	_refresh_pagination()

func _populate_dropdown(dropdown: OptionButton, values: Array) -> void:
	dropdown.clear()
	for value in values:
		dropdown.add_item(str(value))
	if dropdown.item_count > 0:
		dropdown.select(0)

func _update_local_lot_data(lot_id: int, patch: Dictionary) -> void:
	for idx in range(_current_items.size()):
		if int(_current_items[idx].get("id", -1)) == lot_id:
			for key in patch.keys():
				_current_items[idx][key] = patch[key]
			return

func _get_local_lot(lot_id: int) -> Dictionary:
	for lot in _current_items:
		if int(lot.get("id", -1)) == lot_id:
			return lot.duplicate(true)
	return {}

func _exit_tree() -> void:
	if WebSocketManager.auction_bid_update.is_connected(_on_ws_bid_update):
		WebSocketManager.auction_bid_update.disconnect(_on_ws_bid_update)
	if WebSocketManager.auction_lot_closed.is_connected(_on_ws_lot_closed):
		WebSocketManager.auction_lot_closed.disconnect(_on_ws_lot_closed)
	if WebSocketManager.auction_lot_created.is_connected(_on_ws_lot_created):
		WebSocketManager.auction_lot_created.disconnect(_on_ws_lot_created)

