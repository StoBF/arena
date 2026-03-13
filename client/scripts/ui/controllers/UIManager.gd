extends Control

signal view_changed(view_name: String)

const PLAYER_HUB_SCENE := preload("res://scenes/ui/PlayerHub.tscn")
const LOGIN_SCENE := preload("res://scenes/ui/LoginScene.tscn")
const REGISTER_SCENE := preload("res://scenes/ui/RegisterScene.tscn")
const HERO_CREATION_SCENE := preload("res://scenes/ui/HeroCreation.tscn")
const STORAGE_SCENE := preload("res://scenes/ui/Storage.tscn")
const AUCTION_SCENE := preload("res://scenes/ui/Auction.tscn")
const BATTLE_ROOM_SCENE := preload("res://scenes/ui/BattleRoom.tscn")
const SETTINGS_SCENE := preload("res://scenes/ui/Settings.tscn")

@onready var player_data = $PlayerData
@onready var inventory_controller = $InventoryController
@onready var craft_controller = $CraftController
@onready var current_view_root: Control = $UIRoot/CurrentView

var _current_view: Control = null
var _current_view_name: String = ""

func _ready() -> void:
	inventory_controller.bind_player_data(player_data)
	craft_controller.bind_controllers(player_data, inventory_controller)
	if has_node("/root/SceneManager"):
		SceneManager.bind_ui_root(self)
	if has_node("/root/EventBus") and EventBus.scene_changed.is_connected(_on_eventbus_scene_changed) == false:
		EventBus.scene_changed.connect(_on_eventbus_scene_changed)
	if AuthManager.is_authenticated():
		if has_node("/root/EventBus"):
			EventBus.emit_scene_changed("PlayerHub")
		else:
			open_view("PlayerHub")
	else:
		if has_node("/root/EventBus"):
			EventBus.emit_scene_changed("LoginScene")
		else:
			open_view("LoginScene")

func open_view(view_name: String) -> void:
	if view_name == _current_view_name and _current_view != null and _current_view.is_inside_tree():
		return
	if _current_view != null and _current_view.is_inside_tree():
		_current_view.queue_free()
		_current_view = null

	var scene: PackedScene = _scene_for_view(view_name)
	if scene == null:
		return
	_current_view = scene.instantiate()
	current_view_root.add_child(_current_view)
	_bind_view(_current_view)
	_current_view_name = view_name
	view_changed.emit(view_name)

func _scene_for_view(view_name: String) -> PackedScene:
	match view_name:
		"LoginScene":
			return LOGIN_SCENE
		"RegisterScene":
			return REGISTER_SCENE
		"PlayerHub":
			return PLAYER_HUB_SCENE
		"HeroCreation":
			return HERO_CREATION_SCENE
		"Storage":
			return STORAGE_SCENE
		"Auction":
			return AUCTION_SCENE
		"BattleRoom":
			return BATTLE_ROOM_SCENE
		"Settings":
			return SETTINGS_SCENE
		_:
			return null

func _bind_view(view: Node) -> void:
	if view.has_method("bind_controllers"):
		view.bind_controllers(player_data, inventory_controller, craft_controller)

func _on_eventbus_scene_changed() -> void:
	open_view(EventBus.last_scene_name)
