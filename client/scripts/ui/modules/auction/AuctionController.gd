extends Control

@onready var lots_label: Label = $VBox/LotsLabel
@onready var refresh_button: Button = $VBox/RefreshButton
@onready var bid_button: Button = $VBox/BidButton

var _lots: Array = []

func _ready() -> void:
	refresh_button.pressed.connect(_load_auction)
	bid_button.pressed.connect(_place_bid)
	if has_node("/root/EventBus"):
		var bus := get_node("/root/EventBus") as UIEventBus
		if bus.auction_updated.is_connected(_on_auction_updated) == false:
			bus.auction_updated.connect(_on_auction_updated)
	_load_auction()

func _load_auction() -> void:
	if has_node("/root/AppState") == false:
		return
	var response: Dictionary = await ApiClient.get_auctions()
	if bool(response.get("ok", false)) == false:
		return
	var payload: Variant = response.get("data", [])
	if payload is Array:
		_lots = (payload as Array).duplicate(true)
	elif payload is Dictionary and (payload as Dictionary).has("items") and (payload as Dictionary).get("items") is Array:
		_lots = ((payload as Dictionary).get("items") as Array).duplicate(true)
	else:
		_lots = []
	(get_node("/root/AppState") as UIAppState).set_auction_lots(_lots)
	_apply_state_lots()

func _on_auction_updated() -> void:
	_apply_state_lots()

func _apply_state_lots() -> void:
	if has_node("/root/AppState") == false:
		lots_label.text = "Lots: 0"
		return
	_lots = (get_node("/root/AppState") as UIAppState).auction_lots.duplicate(true)
	lots_label.text = "Lots: %d" % _lots.size()

func _place_bid() -> void:
	if _lots.is_empty():
		return
	var lot: Dictionary = _lots[0] as Dictionary
	var lot_id: int = int(lot.get("id", lot.get("lot_id", -1)))
	var response: Dictionary = await ApiClient.place_bid(lot_id, 1)
	if bool(response.get("ok", false)):
		_load_auction()
