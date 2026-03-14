extends Node
class_name UIAppState

var selected_hero_id: int = -1
var heroes: Array = []
var inventory: Dictionary = {}
var auction_lots: Array = []
var recipes: Array = []
var chat_messages: Array = []

func set_selected_hero(hero_id: int) -> void:
	if selected_hero_id == hero_id:
		return
	selected_hero_id = hero_id
	if has_node("/root/EventBus"):
		(get_node("/root/EventBus") as UIEventBus).hero_changed.emit(hero_id)

func set_heroes(data: Array) -> void:
	heroes = data.duplicate(true)
	if has_node("/root/EventBus"):
		(get_node("/root/EventBus") as UIEventBus).heroes_updated.emit()

func set_inventory(hero_id: int, items: Array) -> void:
	inventory[hero_id] = items.duplicate(true)
	if has_node("/root/EventBus"):
		(get_node("/root/EventBus") as UIEventBus).inventory_updated.emit(hero_id)

func set_auction_lots(data: Array) -> void:
	auction_lots = data.duplicate(true)
	if has_node("/root/EventBus"):
		(get_node("/root/EventBus") as UIEventBus).auction_updated.emit()

func set_recipes(data: Array) -> void:
	recipes = data.duplicate(true)

func add_chat_message(msg: Dictionary) -> void:
	chat_messages.append(msg.duplicate(true))
	if has_node("/root/EventBus"):
		(get_node("/root/EventBus") as UIEventBus).chat_updated.emit()
