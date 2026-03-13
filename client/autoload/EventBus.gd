extends Node

signal hero_selected(hero_id: int)
signal heroes_updated
signal user_data_updated
signal inventory_updated
signal auction_updated
signal chat_message_received
signal chat_updated
signal server_status_updated
signal scene_changed

var last_hero_id: int = -1
var last_scene_name: String = ""
var last_chat_channel: String = "global"
var last_chat_message: String = ""
var last_chat_messages: Array = []
var last_server_status: String = "offline"
var last_online_players: int = 0

func emit_hero_selected(hero_id: int) -> void:
	if hero_id <= 0:
		return
	last_hero_id = hero_id
	hero_selected.emit(hero_id)

func emit_heroes_updated() -> void:
	heroes_updated.emit()

func emit_user_data_updated() -> void:
	user_data_updated.emit()

func emit_inventory_updated() -> void:
	inventory_updated.emit()

func emit_auction_updated() -> void:
	auction_updated.emit()

func emit_chat_message_received(channel: String, message: String) -> void:
	last_chat_channel = channel
	last_chat_message = message
	chat_message_received.emit()

func emit_chat_updated(channel: String, messages: Array) -> void:
	last_chat_channel = channel
	last_chat_messages = messages.duplicate(true)
	chat_updated.emit()

func emit_server_status_updated(status: String, online_players: int) -> void:
	last_server_status = status
	last_online_players = maxi(0, online_players)
	server_status_updated.emit()

func emit_scene_changed(scene_name: String) -> void:
	if scene_name.is_empty():
		return
	last_scene_name = scene_name
	scene_changed.emit()
