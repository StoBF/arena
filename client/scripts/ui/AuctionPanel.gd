extends Control
class_name AuctionPanel

# UI Elements
@onready var auctions_list = $AuctionsList
@onready var detail_container = $DetailContainer
@onready var auction_name = $DetailContainer/AuctionName
@onready var current_bid = $DetailContainer/CurrentBid
@onready var bid_amount = $BidAmount
@onready var bid_button = $BidButton
@onready var items_button = $ButtonContainer/ItemsButton
@onready var lots_button = $ButtonContainer/LotsButton

# Properties
var auctions_data: Array = []

func _ready():
	# Connect signals
	Localization.locale_changed.connect(Callable(self, "_localize_ui"))
	auctions_list.item_selected.connect(Callable(self, "_on_item_selected"))
	bid_button.pressed.connect(Callable(self, "_on_bid_button_pressed"))
	items_button.pressed.connect(Callable(self, "_on_items_button_pressed"))
	lots_button.pressed.connect(Callable(self, "_on_lots_button_pressed"))
	
	# Initialize UI
	_localize_ui()
	# default to items view
	_set_mode("items")

var mode = "items"  # "items" or "lots"

func _set_mode(new_mode: String):
	mode = new_mode
	# update button styles
	items_button.pressed = (mode == "items")
	lots_button.pressed = (mode == "lots")
	_load_auctions()

func _load_auctions():
	var path = "/auctions"
	if mode == "lots":
		path = "/auctions/lots"
	var req = Network.request(path, HTTPClient.METHOD_GET)
	req.request_completed.connect(Callable(self, "_on_auctions_response"))

func _on_auctions_response(result: int, code: int, headers, body: PackedByteArray):
	if code == 200:
		var parsed = JSON.parse_string(body.get_string_from_utf8())
		if parsed.error == OK:
			auctions_data = parsed.result
			_populate_auctions_list()
			return
	UIUtils.show_error(Localization.t("load_auctions_failed"))

func _on_items_button_pressed():
	_set_mode("items")

func _on_lots_button_pressed():
	_set_mode("lots")

func _populate_auctions_list():
	auctions_list.clear()
	for auction in auctions_data:
		var label = ""
		if mode == "items":
			# some responses may include item name
			label = "%s (%.2f)" % [auction.get("name", ""), auction.get("current_price", 0.0)]
		else:
			label = "Hero %s (%.2f)" % [str(auction.get("hero_id", "")), auction.get("current_price", 0.0)]
		var idx = auctions_list.add_item(label)
		auctions_list.set_item_metadata(idx, auction.get("id"))

func _on_item_selected(index: int):
	var auction = auctions_data[index]
	if mode == "items":
		auction_name.text = auction.get("name", "")
		current_bid.text = Localization.t("current_bid") + ": %.2f" % auction.get("current_price", 0.0)
	else:
		auction_name.text = Localization.t("hero") + " %s" % str(auction.get("hero_id", ""))
		current_bid.text = Localization.t("current_bid") + ": %.2f" % auction.get("current_price", 0.0)
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
		
		var path = "/auctions/%s/bids" % auction_id
		if mode == "lots":
			path = "/auctions/lots/%s/bids" % auction_id
		var req = Network.request(path, HTTPClient.METHOD_POST, data)
		req.request_completed.connect(Callable(self, "_on_bid_response"))

func _on_bid_response(result: int, code: int, headers, body: PackedByteArray):
	if code == 200:
		UIUtils.show_success(Localization.t("bid_success"))
		_load_auctions()  # Refresh auctions list
	else:
		UIUtils.show_error(Localization.t("bid_failed"))

	bid_amount.placeholder_text = Localization.t("amount")
	bid_button.text = Localization.t("bid")
	items_button.text = Localization.t("items")
	lots_button.text = Localization.t("lots")
	if selected.size() > 0:
		_on_item_selected(selected[0]) 
