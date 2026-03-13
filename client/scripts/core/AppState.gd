extends Node
class_name UIAppState

var selected_hero_id: int = -1
var heroes: Array = []
var inventory: Array = []
var auction_data: Array = []
var chat_messages: Array = []

func set_selected_hero(hero_id: int) -> void:
	selected_hero_id = hero_id

func set_heroes(data: Array) -> void:
	heroes = data.duplicate(true)

func set_inventory(data: Array) -> void:
	inventory = data.duplicate(true)

func set_auction_data(data: Array) -> void:
	auction_data = data.duplicate(true)

func push_chat_message(msg: Dictionary) -> void:
	chat_messages.append(msg.duplicate(true))
