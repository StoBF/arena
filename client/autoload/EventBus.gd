extends Node

const SCENE_LOGIN := "LoginScene"
const SCENE_REGISTER := "RegisterScene"
const SCENE_PLAYER_HUB := "PlayerHub"
const SCENE_HERO_CREATION := "HeroCreation"
const SCENE_STORAGE := "Storage"
const SCENE_AUCTION := "Auction"
const SCENE_BATTLE_ROOM := "BattleRoom"
const SCENE_SETTINGS := "Settings"

const VALID_SCENES: PackedStringArray = [
	SCENE_LOGIN,
	SCENE_REGISTER,
	SCENE_PLAYER_HUB,
	SCENE_HERO_CREATION,
	SCENE_STORAGE,
	SCENE_AUCTION,
	SCENE_BATTLE_ROOM,
	SCENE_SETTINGS,
]

signal hero_selected(hero_id: int)
signal heroes_updated
signal user_data_updated
signal inventory_updated
signal auction_updated
signal chat_message_received
signal chat_updated
signal server_status_updated
signal scene_changed
signal network_error(message: String)

var last_hero_id: int = -1
var last_scene_name: String = ""
var last_chat_channel: String = "global"
var last_chat_message: String = ""
var last_chat_messages: Array = []
var last_server_status: String = "offline"
var last_online_players: int = 0

## H14: AppState is the single emitter; EventBus subscribes and re-emits so
## that consumers of either AppState or EventBus each receive exactly one call.
func _ready() -> void:
	if not has_node("/root/AppState"):
		return
	AppState.user_data_updated.connect(func() -> void:
		emit_user_data_updated())
	AppState.heroes_updated.connect(func(_h: Array) -> void:
		emit_heroes_updated())
	AppState.inventory_updated.connect(func(_i: Array) -> void:
		emit_inventory_updated())
	AppState.auction_updated.connect(func(_i: Array, _p: Dictionary) -> void:
		emit_auction_updated())
	AppState.server_status_updated.connect(func(s: String, p: int) -> void:
		emit_server_status_updated(s, p))
	AppState.chat_updated.connect(func(ch: String, msgs: Array) -> void:
		emit_chat_updated(ch, msgs))
	AppState.chat_message_received.connect(func(ch: String, msg: String) -> void:
		emit_chat_message_received(ch, msg))
	AppState.selected_hero_changed.connect(func(h: Dictionary) -> void:
		var hid: int = int(h.get("id", -1))
		if hid > 0:
			emit_hero_selected(hid))

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
		_report_invalid_route(scene_name, "emit_scene_changed")
		return
	if VALID_SCENES.has(scene_name) == false:
		_report_invalid_route(scene_name, "emit_scene_changed")
		return
	last_scene_name = scene_name
	scene_changed.emit()

func navigate_to(scene_name: String) -> bool:
	if scene_name.is_empty() or VALID_SCENES.has(scene_name) == false:
		_report_invalid_route(scene_name, "navigate_to")
		return false
	emit_scene_changed(scene_name)
	return true

func _report_invalid_route(scene_name: String, source: String) -> void:
	var route_name: String = scene_name if scene_name.is_empty() == false else "<empty>"
	var message: String = "Invalid scene route (%s): %s" % [source, route_name]
	push_warning("[EventBus] %s" % message)
	network_error.emit(message)
	if has_node("/root/UIUtils"):
		UIUtils.show_error(message)
