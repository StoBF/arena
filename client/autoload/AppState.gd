# Autoload AppState.gd
extends Node

signal battle_queue_updated(queue)
signal battle_queue_error(message)
signal battle_submit_updated(success, detail)
signal battle_bet_updated(success, detail)
signal chat_message_received(channel, message)
signal chat_connection_changed(channel, connected)
signal auction_lot_requested(lot_id)
signal user_data_updated

# Authentication tokens
var access_token: String = ""
var refresh_token: String = ""
var token: String = ""

# User data (cached after /auth/me)
var user_id: int = -1
var username: String = ""
var balance: float = 0.0
var current_hero_id: int = -1
var last_created_hero: Dictionary = {}

# Battle lobby state (serializable only)
var battle_queue: Array = []
var battle_last_error: String = ""
var chat_messages: Dictionary = {}
var active_chat_channel: String = "general"
var selected_auction_lot_id: int = -1

# Token refresh state (prevent infinite refresh loops)
var is_refreshing_token: bool = false
var token_refresh_attempted: bool = false


func set_access_token(value: String) -> void:
	access_token = value
	token = value


## Cache user profile received from /auth/me. Emits user_data_updated.
func set_user_data(data: Dictionary) -> void:
	user_id = data.get("id", user_id)
	username = data.get("username", username)
	balance = float(data.get("balance", balance))
	print("[AppState] User data cached: username=%s balance=%.2f" % [username, balance])
	user_data_updated.emit()


func update_battle_queue(queue_data: Array) -> void:
	battle_queue = queue_data.duplicate(true)
	battle_last_error = ""
	emit_signal("battle_queue_updated", battle_queue)


func set_battle_queue_error(message: String) -> void:
	battle_last_error = message
	emit_signal("battle_queue_error", message)


func set_battle_submit_result(success: bool, detail: String) -> void:
	emit_signal("battle_submit_updated", success, detail)


func set_battle_bet_result(success: bool, detail: String) -> void:
	emit_signal("battle_bet_updated", success, detail)


func push_chat_message(channel: String, message: String) -> void:
	if not chat_messages.has(channel):
		chat_messages[channel] = []
	chat_messages[channel].append(message)
	emit_signal("chat_message_received", channel, message)


func set_chat_connection_state(channel: String, connected: bool) -> void:
	emit_signal("chat_connection_changed", channel, connected)


func request_open_auction_lot(lot_id: int) -> void:
	selected_auction_lot_id = lot_id
	emit_signal("auction_lot_requested", lot_id)
 
