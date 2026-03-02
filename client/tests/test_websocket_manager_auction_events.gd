extends GutTest

var _manager: WebSocketManager
var _received_bid := false
var _received_closed := false
var _received_created := false

func before_each() -> void:
	_manager = WebSocketManager.new()
	_manager.auction_bid_update.connect(_on_bid)
	_manager.auction_lot_closed.connect(_on_closed)
	_manager.auction_lot_created.connect(_on_created)

func after_each() -> void:
	if _manager != null:
		_manager.queue_free()

func test_emits_bid_update_event() -> void:
	_received_bid = false
	_manager._handle_auction_packet('{"event":"bid_update","data":{"lot_id":42,"current_bid":123.5}}')
	assert_true(_received_bid, "bid_update event should be emitted")

func test_emits_lot_closed_event() -> void:
	_received_closed = false
	_manager._handle_auction_packet('{"event":"lot_closed","data":{"lot_id":42}}')
	assert_true(_received_closed, "lot_closed event should be emitted")

func test_emits_lot_created_event() -> void:
	_received_created = false
	_manager._handle_auction_packet('{"event":"lot_created","data":{"lot_id":77,"name":"New Lot"}}')
	assert_true(_received_created, "lot_created event should be emitted")

func _on_bid(_data: Dictionary) -> void:
	_received_bid = true

func _on_closed(_data: Dictionary) -> void:
	_received_closed = true

func _on_created(_data: Dictionary) -> void:
	_received_created = true
