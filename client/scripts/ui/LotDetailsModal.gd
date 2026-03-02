extends Window
class_name LotDetailsModal

signal action_succeeded(lot_id: int)

@onready var title_label: Label = $Root/Header/TitleLabel
@onready var seller_label: Label = $Root/Body/Meta/SellerLabel
@onready var reputation_label: Label = $Root/Body/Meta/ReputationLabel
@onready var current_bid_label: Label = $Root/Body/BidSummary/CurrentBidLabel
@onready var bid_step_label: Label = $Root/Body/BidSummary/BidStepLabel
@onready var stats_text: RichTextLabel = $Root/Body/Stats/StatsText
@onready var bid_history_list: ItemList = $Root/Body/BidHistory/BidHistoryList
@onready var bid_amount_spin: SpinBox = $Root/Footer/BidControls/BidAmountSpin
@onready var auto_bid_check: CheckBox = $Root/Footer/BidControls/AutoBidCheck
@onready var auto_bid_max_spin: SpinBox = $Root/Footer/BidControls/AutoBidMaxSpin
@onready var place_bid_button: Button = $Root/Footer/Actions/PlaceBidButton
@onready var buy_now_button: Button = $Root/Footer/Actions/BuyNowButton
@onready var close_button: Button = $Root/Footer/Actions/CloseButton
@onready var error_popup: AcceptDialog = $ErrorPopup

var _lot_data: Dictionary = {}
var _lot_id: int = -1
var _pending: bool = false
var _is_closed: bool = false

func _ready() -> void:
	place_bid_button.pressed.connect(_on_place_bid_pressed)
	buy_now_button.pressed.connect(_on_buy_now_pressed)
	close_button.pressed.connect(_on_close_pressed)
	auto_bid_check.toggled.connect(_on_auto_bid_toggled)
	close_requested.connect(_on_close_pressed)
	auto_bid_max_spin.editable = false

func open_for_lot(lot_data: Dictionary) -> void:
	_lot_data = lot_data.duplicate(true)
	_lot_id = int(_lot_data.get("id", -1))
	if _lot_id <= 0:
		return
	var fetched := await AuctionManager.fetch_lot_details(_lot_id, _lot_data)
	if not fetched.is_empty():
		_lot_data = fetched
	_refresh_ui()
	popup_centered_ratio(0.62)

func _refresh_ui() -> void:
	_is_closed = bool(_lot_data.get("is_closed", false))
	title_label.text = str(_lot_data.get("name", _lot_data.get("title", "Lot Details")))
	seller_label.text = "Seller: %s" % str(_lot_data.get("seller", _lot_data.get("seller_name", "Unknown")))
	reputation_label.text = "Reputation: %s" % str(_lot_data.get("seller_reputation", _lot_data.get("reputation", "N/A")))

	var current_bid := float(_lot_data.get("current_price", _lot_data.get("current_bid", 0.0)))
	var bid_step := maxf(0.01, float(_lot_data.get("bid_step", 1.0)))
	current_bid_label.text = "Current Bid: %.2f" % current_bid
	bid_step_label.text = "Bid Step: %.2f" % bid_step

	bid_amount_spin.min_value = current_bid + bid_step
	bid_amount_spin.step = bid_step
	bid_amount_spin.value = current_bid + bid_step

	var buy_now_value := float(_lot_data.get("buy_now", _lot_data.get("buy_now_price", 0.0)))
	buy_now_button.visible = buy_now_value > 0.0
	if buy_now_value > 0.0:
		buy_now_button.text = "Buy Now (%.2f)" % buy_now_value

	auto_bid_check.button_pressed = false
	auto_bid_max_spin.editable = false
	auto_bid_max_spin.min_value = bid_amount_spin.min_value
	auto_bid_max_spin.step = bid_step
	auto_bid_max_spin.value = bid_amount_spin.value

	stats_text.text = _build_stats_block(_lot_data)
	_refresh_bid_history(_lot_data)
	_set_pending(false)
	if _is_closed:
		_apply_closed_state()

func _refresh_bid_history(data: Dictionary) -> void:
	bid_history_list.clear()
	var history: Array = []
	if data.has("bid_history") and data["bid_history"] is Array:
		history = data["bid_history"]
	elif data.has("bids") and data["bids"] is Array:
		history = data["bids"]

	if history.is_empty():
		bid_history_list.add_item("No bids yet")
		return

	for bid in history:
		var bidder := str(bid.get("bidder", bid.get("username", "unknown")))
		var amount := float(bid.get("amount", 0.0))
		var time_text := str(bid.get("time", bid.get("created_at", "")))
		bid_history_list.add_item("%s | %.2f | %s" % [bidder, amount, time_text])

func _build_stats_block(data: Dictionary) -> String:
	var lines: Array[String] = []
	lines.append("Type: %s" % str(data.get("type", "Unknown")))
	if bool(data.get("is_hero", false)):
		lines.append("Level: %d" % int(data.get("level", 1)))
		lines.append("Strength: %d" % int(data.get("strength", 0)))
		lines.append("Agility: %d" % int(data.get("agility", 0)))
		lines.append("Health: %d" % int(data.get("health", 0)))
	else:
		lines.append("Rarity: %s" % str(data.get("rarity", "Common")))
		lines.append("Power: %d" % int(data.get("power", 0)))
		lines.append("Attack: %d" % int(data.get("attack", 0)))
		lines.append("Defense: %d" % int(data.get("defense", 0)))
	if data.has("description"):
		lines.append("Description: %s" % str(data.get("description", "")))
	return "\n".join(lines)

func _on_auto_bid_toggled(pressed: bool) -> void:
	auto_bid_max_spin.editable = pressed

func _on_place_bid_pressed() -> void:
	if _pending or _lot_id <= 0 or _is_closed:
		return
	var amount := bid_amount_spin.value
	if auto_bid_check.button_pressed:
		amount = auto_bid_max_spin.value
	if amount < bid_amount_spin.min_value:
		_show_error("Bid must be at least %.2f" % bid_amount_spin.min_value)
		return

	_set_pending(true)
	var result_ok: bool = await AuctionManager.place_bid(_lot_id, int(round(amount)))
	_set_pending(false)
	if result_ok:
		action_succeeded.emit(_lot_id)
		hide()
		return
	_show_error(_error_message_for_manager())

func _on_buy_now_pressed() -> void:
	if _pending or _lot_id <= 0 or _is_closed:
		return
	_set_pending(true)
	var result_ok: bool = await AuctionManager.buy_now(_lot_id)
	_set_pending(false)
	if result_ok:
		action_succeeded.emit(_lot_id)
		hide()
		return
	_show_error(_error_message_for_manager())

func _set_pending(value: bool) -> void:
	_pending = value
	place_bid_button.disabled = value or _is_closed
	buy_now_button.disabled = value or not buy_now_button.visible or _is_closed
	close_button.disabled = value
	bid_amount_spin.editable = not value and not _is_closed
	auto_bid_check.disabled = value or _is_closed
	auto_bid_max_spin.editable = auto_bid_check.button_pressed and not value and not _is_closed

func is_showing_lot(lot_id: int) -> bool:
	return visible and _lot_id == lot_id

func apply_live_bid_update(event_data: Dictionary) -> void:
	var event_lot_id := int(event_data.get("lot_id", event_data.get("id", -1)))
	if not is_showing_lot(event_lot_id):
		return
	var current_bid := float(event_data.get("current_bid", event_data.get("current_price", -1.0)))
	if current_bid >= 0.0:
		_lot_data["current_price"] = current_bid
		_lot_data["current_bid"] = current_bid
	current_bid_label.text = "Current Bid: %.2f" % float(_lot_data.get("current_price", _lot_data.get("current_bid", 0.0)))
	if event_data.has("bid_step"):
		_lot_data["bid_step"] = float(event_data.get("bid_step", _lot_data.get("bid_step", 1.0)))
	bid_step_label.text = "Bid Step: %.2f" % float(_lot_data.get("bid_step", 1.0))
	bid_amount_spin.min_value = float(_lot_data.get("current_price", _lot_data.get("current_bid", 0.0))) + float(_lot_data.get("bid_step", 1.0))
	bid_amount_spin.value = maxf(bid_amount_spin.value, bid_amount_spin.min_value)

	var bidder := str(event_data.get("bidder", event_data.get("username", "unknown")))
	var amount := float(event_data.get("amount", current_bid))
	var time_text := str(event_data.get("time", event_data.get("created_at", Time.get_datetime_string_from_system())))
	bid_history_list.add_item("%s | %.2f | %s" % [bidder, amount, time_text])

func apply_lot_closed(event_data: Dictionary) -> void:
	var event_lot_id := int(event_data.get("lot_id", event_data.get("id", -1)))
	if not is_showing_lot(event_lot_id):
		return
	_lot_data["is_closed"] = true
	_is_closed = true
	_apply_closed_state()

func _apply_closed_state() -> void:
	place_bid_button.disabled = true
	buy_now_button.disabled = true
	bid_amount_spin.editable = false
	auto_bid_check.disabled = true
	auto_bid_max_spin.editable = false

func _error_message_for_manager() -> String:
	var code := AuctionManager.get_last_error_code()
	if code == "insufficient_funds":
		return "Insufficient funds"
	if code == "outbid":
		return "You have been outbid"
	if code == "lot_closed":
		return "This lot is closed"
	var fallback := AuctionManager.get_last_error_message()
	if fallback.is_empty():
		fallback = "Request failed"
	return fallback

func _show_error(message: String) -> void:
	error_popup.dialog_text = message
	error_popup.popup_centered()

func _on_close_pressed() -> void:
	if _pending:
		return
	hide()
