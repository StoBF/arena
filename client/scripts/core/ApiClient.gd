extends Node
class_name UIApiClient

func get_account() -> Dictionary:
	return {"ok": true, "data": {}}

func get_heroes() -> Dictionary:
	return {
		"ok": true,
		"data": [
			{"id": 1, "name": "Astra", "level": 7},
			{"id": 2, "name": "Brakk", "level": 11},
		]
	}

func get_inventory(hero_id: int) -> Dictionary:
	return {
		"ok": true,
		"hero_id": hero_id,
		"data": [
			{"id": 101, "name": "Iron Sword", "qty": 1},
			{"id": 102, "name": "Health Potion", "qty": 5},
		]
	}

func get_auction_lots() -> Dictionary:
	return {
		"ok": true,
		"data": [
			{"lot_id": 5001, "item": "Epic Helm", "current_bid": 120},
			{"lot_id": 5002, "item": "Rare Ring", "current_bid": 80},
		]
	}

func place_bid(lot_id: int, amount: int) -> Dictionary:
	if lot_id <= 0 or amount <= 0:
		return {"ok": false}
	return {"ok": true, "lot_id": lot_id, "amount": amount}

func get_recipes() -> Dictionary:
	return {"ok": true, "data": []}

func get_raid_bosses() -> Dictionary:
	return {"ok": true, "data": []}

func get_chat_messages(channel: String = "global") -> Dictionary:
	return {
		"ok": true,
		"channel": channel,
		"data": [
			{"channel": channel, "author": "System", "text": "Welcome to chat"},
		]
	}

func poll_chat_messages(channel: String = "global") -> Dictionary:
	return {
		"ok": true,
		"data": [
			{"channel": channel, "author": "Server", "text": "Heartbeat"},
		]
	}

func subscribe_chat_socket(channel: String = "global") -> Dictionary:
	return {"ok": true, "channel": channel}
