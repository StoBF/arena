extends Control

const PAGE_SIZE := 10
const REFRESH_INTERVAL_SECONDS := 8.0
const CATEGORIES: PackedStringArray = [
	"heroes",
	"armor",
	"helmets",
	"gloves",
	"artifacts",
	"recipes",
	"resources",
]

@onready var category_option: OptionButton = $Margin/VBox/FilterMenu/CategoryOption
@onready var auction_table = $Margin/VBox/AuctionTable
@onready var prev_button: Button = $Margin/VBox/Pagination/PrevButton
@onready var next_button: Button = $Margin/VBox/Pagination/NextButton
@onready var page_label: Label = $Margin/VBox/Pagination/PageLabel
@onready var live_status_label: Label = $Margin/VBox/Header/LiveStatus
@onready var selected_lot_label: Label = $Margin/VBox/LotActions/SelectedLotLabel
@onready var bid_amount: SpinBox = $Margin/VBox/LotActions/BidAmount
@onready var place_bid_button: Button = $Margin/VBox/LotActions/PlaceBidButton
@onready var buyout_button: Button = $Margin/VBox/LotActions/BuyoutButton
@onready var action_status_label: Label = $Margin/VBox/LotActions/ActionStatus
@onready var buyout_confirm_dialog = $BuyoutConfirmDialog

var _current_page: int = 1
var _page_size: int = PAGE_SIZE
var _has_next: bool = false
var _has_prev: bool = false
var _total: int = 0
var _selected_lot: Dictionary = {}
var _poll_time_left: float = REFRESH_INTERVAL_SECONDS
var _pending_buyout_lot_id: int = -1
var _is_live_connected: bool = false

func _ready() -> void:
	$Margin/VBox/Header/BackButton.pressed.connect(func(): EventBus.emit_scene_changed("PlayerHub"))
	$Margin/VBox/FilterMenu/RefreshButton.pressed.connect(_request_lots)
	category_option.item_selected.connect(_on_category_changed)
	prev_button.pressed.connect(_on_prev_page)
	next_button.pressed.connect(_on_next_page)
	place_bid_button.pressed.connect(_on_place_bid_pressed)
	buyout_button.pressed.connect(_on_buyout_pressed)
	if buyout_confirm_dialog.action_confirmed.is_connected(_on_buyout_confirmed) == false:
		buyout_confirm_dialog.action_confirmed.connect(_on_buyout_confirmed)
	if auction_table.lot_selected.is_connected(_on_lot_selected) == false:
		auction_table.lot_selected.connect(_on_lot_selected)

	for category in CATEGORIES:
		category_option.add_item(category)
	category_option.select(0)

	if AuctionManager.lots_fetch_failed.is_connected(_on_lots_failed) == false:
		AuctionManager.lots_fetch_failed.connect(_on_lots_failed)
	if has_node("/root/EventBus") and EventBus.auction_updated.is_connected(_on_eventbus_auction_updated) == false:
		EventBus.auction_updated.connect(_on_eventbus_auction_updated)

	if WebSocketManager.auction_socket_state_changed.is_connected(_on_auction_socket_state_changed) == false:
		WebSocketManager.auction_socket_state_changed.connect(_on_auction_socket_state_changed)
	if WebSocketManager.auction_bid_update.is_connected(_on_realtime_event) == false:
		WebSocketManager.auction_bid_update.connect(_on_realtime_event)
	if WebSocketManager.auction_lot_created.is_connected(_on_realtime_event) == false:
		WebSocketManager.auction_lot_created.connect(_on_realtime_event)
	if WebSocketManager.auction_lot_closed.is_connected(_on_realtime_event) == false:
		WebSocketManager.auction_lot_closed.connect(_on_realtime_event)
	if LocalizationManager.locale_changed.is_connected(_on_locale_changed) == false:
		LocalizationManager.locale_changed.connect(_on_locale_changed)

	_apply_translations()
	WebSocketManager.ensure_auction_subscription()
	set_process(true)
	_update_selected_lot_ui()
	_request_lots()

func _process(delta: float) -> void:
	if _selected_lot.is_empty() == false and _lot_is_expired(_selected_lot):
		_clear_selected_lot(tr("ui.auction.lot_expired"))
		return

	_poll_time_left -= delta
	if _poll_time_left <= 0.0:
		_poll_time_left = REFRESH_INTERVAL_SECONDS
		_request_lots()

func _request_lots() -> void:
	var filters := {
		"type": category_option.get_item_text(category_option.selected),
		"page": _current_page,
		"page_size": _page_size,
	}
	AuctionManager.fetch_lots(filters)

func _on_category_changed(_index: int) -> void:
	_current_page = 1
	_request_lots()

func _on_prev_page() -> void:
	if _has_prev == false:
		return
	_current_page = maxi(1, _current_page - 1)
	_request_lots()

func _on_next_page() -> void:
	if _has_next == false:
		return
	_current_page += 1
	_request_lots()

func _on_lots_updated(items: Array, pagination: Dictionary) -> void:
	auction_table.set_lots(items)
	_current_page = int(pagination.get("page", _current_page))
	_has_next = bool(pagination.get("has_next", false))
	_has_prev = bool(pagination.get("has_prev", _current_page > 1))
	_total = int(pagination.get("total", items.size()))
	page_label.text = tr("ui.auction.page_total") % [_current_page, _total]
	prev_button.disabled = _has_prev == false
	next_button.disabled = _has_next == false

	if _selected_lot.is_empty() == false:
		var selected_id: int = int(_selected_lot.get("id", -1))
		var still_exists: bool = false
		for item_variant in items:
			if item_variant is Dictionary and int((item_variant as Dictionary).get("id", -1)) == selected_id:
				still_exists = true
				break
		if still_exists == false:
			_clear_selected_lot(tr("ui.auction.selected_removed"))
			return
	_update_selected_lot_ui()

func _on_eventbus_auction_updated() -> void:
	_on_lots_updated(AppState.auction_lots, AppState.auction_pagination)

func _on_lots_failed(message: String) -> void:
	page_label.text = tr("ui.auction.load_failed")
	live_status_label.text = tr("ui.auction.live_error")
	push_warning("[Auction] %s" % message)

func _on_lot_selected(lot: Dictionary) -> void:
	_selected_lot = lot.duplicate(true)
	action_status_label.text = ""
	_refresh_selected_lot_details()
	_update_selected_lot_ui()

func _on_auction_socket_state_changed(connected: bool) -> void:
	_is_live_connected = connected
	live_status_label.text = tr("ui.auction.live_on") if connected else tr("ui.auction.live_off")

func _on_realtime_event(_payload: Dictionary) -> void:
	_request_lots()

func _on_place_bid_pressed() -> void:
	if _selected_lot.is_empty():
		return
	if _lot_is_expired(_selected_lot):
		action_status_label.text = tr("ui.auction.lot_expired")
		return
	var lot_id: int = int(_selected_lot.get("id", -1))
	if lot_id <= 0:
		action_status_label.text = tr("ui.auction.lot_invalid")
		return
	var detailed_lot: Dictionary = await AuctionManager.fetch_lot_details(lot_id, _selected_lot)
	if detailed_lot.is_empty() == false:
		_selected_lot = detailed_lot
	_update_selected_lot_ui()
	var min_required: int = int(_compute_min_bid(_selected_lot))
	var amount: int = int(bid_amount.value)
	if amount < min_required:
		action_status_label.text = tr("ui.auction.bid_min_required") % min_required
		bid_amount.value = min_required
		return
	var ok: bool = await AuctionManager.place_bid(lot_id, amount)
	if ok:
		action_status_label.text = tr("ui.auction.bid_placed")
	else:
		action_status_label.text = tr("ui.auction.bid_failed") % AuctionManager.get_last_error_message()

func _on_buyout_pressed() -> void:
	if _selected_lot.is_empty():
		return
	if _lot_is_expired(_selected_lot):
		action_status_label.text = tr("ui.auction.lot_expired")
		return
	var lot_id: int = int(_selected_lot.get("id", -1))
	if lot_id <= 0:
		action_status_label.text = tr("ui.auction.lot_invalid")
		return
	_pending_buyout_lot_id = lot_id
	buyout_confirm_dialog.dialog_text = tr("ui.auction.confirm_buyout") % _lot_display_name(_selected_lot)
	buyout_confirm_dialog.popup_centered()

func _on_buyout_confirmed() -> void:
	if _pending_buyout_lot_id <= 0:
		return
	var lot_id: int = _pending_buyout_lot_id
	_pending_buyout_lot_id = -1
	var ok: bool = await AuctionManager.buy_now(lot_id)
	if ok:
		action_status_label.text = tr("ui.auction.buyout_success")
		_clear_selected_lot(tr("ui.auction.buyout_success"))
	else:
		action_status_label.text = tr("ui.auction.buyout_failed") % AuctionManager.get_last_error_message()

func _update_selected_lot_ui() -> void:
	if _selected_lot.is_empty():
		if auction_table.has_method("clear_selection"):
			auction_table.clear_selection()
		selected_lot_label.text = tr("ui.auction.selected_none")
		place_bid_button.disabled = true
		buyout_button.disabled = true
		bid_amount.editable = false
		return

	bid_amount.editable = true
	place_bid_button.disabled = false
	buyout_button.disabled = false
	selected_lot_label.text = tr("ui.auction.selected_item") % _lot_display_name(_selected_lot)
	if _lot_is_expired(_selected_lot):
		_clear_selected_lot(tr("ui.auction.lot_expired"))
		return

	bid_amount.min_value = _compute_min_bid(_selected_lot)
	bid_amount.value = bid_amount.min_value

func _lot_display_name(lot: Dictionary) -> String:
	if lot.has("item_name"):
		return str(lot.get("item_name", "lot"))
	if lot.has("name"):
		return str(lot.get("name", "lot"))
	if lot.has("hero_name"):
		return str(lot.get("hero_name", "lot"))
	return "lot #%d" % int(lot.get("id", 0))

func _extract_price(lot: Dictionary, keys: Array, default_value: float) -> float:
	for key_variant in keys:
		var key := str(key_variant)
		if lot.has(key):
			return float(lot.get(key, default_value))
	return default_value

func _compute_min_bid(lot: Dictionary) -> float:
	var explicit_min: float = _extract_price(lot, ["min_next_bid", "minimum_bid"], -1.0)
	if explicit_min > 0.0:
		return explicit_min
	var current_value: float = _extract_price(lot, ["current_price", "current_bid", "starting_price"], 1.0)
	return maxi(1.0, current_value + 1.0)

func _refresh_selected_lot_details() -> void:
	if _selected_lot.is_empty():
		return
	var lot_id: int = int(_selected_lot.get("id", -1))
	if lot_id <= 0:
		return
	var detailed_lot: Dictionary = await AuctionManager.fetch_lot_details(lot_id, _selected_lot)
	if detailed_lot.is_empty() == false:
		_selected_lot = detailed_lot

func _lot_is_expired(lot: Dictionary) -> bool:
	if lot.has("remaining_seconds"):
		return int(lot.get("remaining_seconds", 0)) <= 0
	if lot.has("expires_in"):
		return int(lot.get("expires_in", 0)) <= 0
	if lot.has("time_left") and (typeof(lot.get("time_left")) == TYPE_INT or typeof(lot.get("time_left")) == TYPE_FLOAT):
		return int(lot.get("time_left", 0)) <= 0

	var expires_raw: String = str(lot.get("expires_at", lot.get("end_time", lot.get("ends_at", ""))))
	if expires_raw.is_empty():
		return false
	var normalized: String = _normalize_datetime_string(expires_raw)
	var end_unix: int = int(Time.get_unix_time_from_datetime_string(normalized))
	if end_unix <= 0:
		return false
	return int(Time.get_unix_time_from_system()) >= end_unix

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

func _clear_selected_lot(status_text: String = "") -> void:
	_selected_lot = {}
	_pending_buyout_lot_id = -1
	_update_selected_lot_ui()
	if status_text.is_empty() == false:
		action_status_label.text = status_text

func _exit_tree() -> void:
	if has_node("/root/EventBus") and EventBus.auction_updated.is_connected(_on_eventbus_auction_updated):
		EventBus.auction_updated.disconnect(_on_eventbus_auction_updated)
	WebSocketManager.stop_auction_subscription()

func _on_locale_changed(_locale_code: String) -> void:
	_apply_translations()
	_update_selected_lot_ui()
	page_label.text = tr("ui.auction.page_total") % [_current_page, _total]

func _apply_translations() -> void:
	$Margin/VBox/Header/BackButton.text = tr("ui.common.back")
	$Margin/VBox/Header/Title.text = tr("ui.auction.title")
	$Margin/VBox/Header/LiveStatus.text = tr("ui.auction.live_on") if _is_live_connected else tr("ui.auction.live_off")
	$Margin/VBox/FilterMenu/CategoryLabel.text = tr("ui.auction.category")
	$Margin/VBox/FilterMenu/RefreshButton.text = tr("ui.common.refresh")
	$Margin/VBox/LotActions/PlaceBidButton.text = tr("ui.auction.place_bid")
	$Margin/VBox/LotActions/BuyoutButton.text = tr("ui.auction.buyout")
	$Margin/VBox/Pagination/PrevButton.text = tr("ui.auction.prev")
	$Margin/VBox/Pagination/NextButton.text = tr("ui.auction.next")
