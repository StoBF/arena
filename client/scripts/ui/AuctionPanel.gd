extends Control
class_name AuctionPanel

# UI Elements
@onready var auctions_list = $AuctionsList
@onready var detail_container = $DetailContainer
@onready var auction_name = $DetailContainer/AuctionName
@onready var current_bid = $DetailContainer/CurrentBid
@onready var bid_amount = $BidAmount
@onready var bid_button = $BidButton

# Properties
var auctions_data: Array = []

func _ready():
	# Connect signals
	Localization.locale_changed.connect(Callable(self, "_localize_ui"))
	auctions_list.item_selected.connect(Callable(self, "_on_item_selected"))
	bid_button.pressed.connect(Callable(self, "_on_bid_button_pressed"))
	
	# Initialize UI
	_localize_ui()
	_load_auctions()

func _load_auctions():
	var req = Network.request("/auctions", HTTPClient.METHOD_GET)
	req.request_completed.connect(Callable(self, "_on_auctions_response"))

func _on_auctions_response(result: int, code: int, headers, body: PackedByteArray):
	if code == 200:
		var parsed = JSON.parse_string(body.get_string_from_utf8())
		if parsed.error == OK:
			auctions_data = parsed.result
			_populate_auctions_list()
			return
	UIUtils.show_error(Localization.t("load_auctions_failed"))

func _populate_auctions_list():
	auctions_list.clear()
	for auction in auctions_data:
		var label = "%s (%.2f)" % [auction.get("name", ""), auction.get("current_bid", 0.0)]
		var idx = auctions_list.add_item(label)
		auctions_list.set_item_metadata(idx, auction.get("id"))

func _on_item_selected(index: int):
	var auction = auctions_data[index]
	auction_name.text = auction.get("name", "")
	current_bid.text = Localization.t("current_bid") + ": %.2f" % auction.get("current_bid", 0.0)
	bid_amount.text = ""

func _on_bid_button_pressed():
	var selected = auctions_list.get_selected_items()
	if selected.size() > 0:
		var idx = selected[0]
		var auction_id = auctions_list.get_item_metadata(idx)
		
		if bid_amount.text.is_empty():
			UIUtils.show_error(Localization.t("enter_bid_amount"))
			return
			
		var amount = float(bid_amount.text)
		var data = {"amount": amount}
		
		var req = Network.request("/auctions/%s/bids" % auction_id, HTTPClient.METHOD_POST, data)
		req.request_completed.connect(Callable(self, "_on_bid_response"))

func _on_bid_response(result: int, code: int, headers, body: PackedByteArray):
	if code == 200:
		UIUtils.show_success(Localization.t("bid_success"))
		_load_auctions()  # Refresh auctions list
	else:
		UIUtils.show_error(Localization.t("bid_failed"))

func _localize_ui():
	bid_amount.placeholder_text = Localization.t("amount")
	bid_button.text = Localization.t("bid")
	
	# Refresh auction details if an item is selected
	var selected = auctions_list.get_selected_items()
	if selected.size() > 0:
		_on_item_selected(selected[0]) 
