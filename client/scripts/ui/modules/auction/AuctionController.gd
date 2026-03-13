extends Control

@onready var lots_label: Label = $VBox/LotsLabel
@onready var refresh_button: Button = $VBox/RefreshButton
@onready var bid_button: Button = $VBox/BidButton

var _lots: Array = []

func _ready() -> void:
	refresh_button.pressed.connect(_load_auction)
	bid_button.pressed.connect(_place_bid)
	_load_auction()

func _load_auction() -> void:
	if has_node("/root/ApiClient") == false or has_node("/root/AppState") == false:
		return
	var response: Dictionary = await (get_node("/root/ApiClient") as UIApiClient).get_auction_lots()
	if bool(response.get("ok", false)) == false:
		return
	_lots = response.get("data", []) as Array
	(get_node("/root/AppState") as UIAppState).set_auction_data(_lots)
	lots_label.text = "Lots: %d" % _lots.size()
	if has_node("/root/EventBus"):
		(get_node("/root/EventBus") as UIEventBus).auction_updated.emit()

func _place_bid() -> void:
	if _lots.is_empty() or has_node("/root/ApiClient") == false:
		return
	var lot: Dictionary = _lots[0] as Dictionary
	var lot_id: int = int(lot.get("lot_id", -1))
	var response: Dictionary = await (get_node("/root/ApiClient") as UIApiClient).place_bid(lot_id, 1)
	if bool(response.get("ok", false)):
		_load_auction()
