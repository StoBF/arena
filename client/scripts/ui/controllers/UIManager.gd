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

## Views that require authentication
const AUTH_REQUIRED := [
	EventBus.SCENE_PLAYER_HUB,
	EventBus.SCENE_HERO_CREATION,
	EventBus.SCENE_STORAGE,
	EventBus.SCENE_AUCTION,
	EventBus.SCENE_BATTLE_ROOM,
	EventBus.SCENE_SETTINGS,
]

## Views that require an active hero
const HERO_REQUIRED := [
	EventBus.SCENE_BATTLE_ROOM,
	EventBus.SCENE_STORAGE,
]

@onready var current_view_root: Control = $UIRoot/CurrentView

var _current_view: Control = null
var _current_view_name: String = ""

func _ready() -> void:
	if has_node("/root/EventBus") and EventBus.scene_changed.is_connected(_on_eventbus_scene_changed) == false:
		EventBus.scene_changed.connect(_on_eventbus_scene_changed)
	if AuthManager.is_authenticated():
		if has_node("/root/EventBus"):
			EventBus.navigate_to(EventBus.SCENE_PLAYER_HUB)
		else:
			open_view(EventBus.SCENE_PLAYER_HUB)
	else:
		if has_node("/root/EventBus"):
			EventBus.navigate_to(EventBus.SCENE_LOGIN)
		else:
			open_view(EventBus.SCENE_LOGIN)

func open_view(view_name: String) -> void:
	# Dedup
	if view_name == _current_view_name and _current_view != null and _current_view.is_inside_tree():
		return

	# Auth guard
	if view_name in AUTH_REQUIRED and not AuthManager.is_authenticated():
		open_view(EventBus.SCENE_LOGIN)
		return

	# Hero guard — use HeroManager as canonical source; AppState.current_hero_id
	# may be stale if HeroManager loaded heroes but set_selected_hero was not yet called.
	if view_name in HERO_REQUIRED and HeroManager.get_active_hero_id() <= 0:
		open_view(EventBus.SCENE_PLAYER_HUB)
		return

	var scene: PackedScene = _scene_for_view(view_name)
	if scene == null:
		push_warning("[UIManager] Unknown scene route: %s" % view_name)
		if AuthManager.is_authenticated():
			if view_name != EventBus.SCENE_PLAYER_HUB:
				open_view(EventBus.SCENE_PLAYER_HUB)
		else:
			if view_name != EventBus.SCENE_LOGIN:
				open_view(EventBus.SCENE_LOGIN)
		return
	var next_view: Node = scene.instantiate()
	if next_view == null or not (next_view is Control):
		var message: String = "[UIManager] Failed to instantiate scene: %s" % view_name
		push_warning(message)
		if has_node("/root/UIUtils"):
			UIUtils.show_error(message)
		return

	if _current_view != null and _current_view.is_inside_tree():
		_current_view.queue_free()

	_current_view = next_view as Control
	current_view_root.add_child(_current_view)
	_current_view_name = view_name
	view_changed.emit(view_name)

func _scene_for_view(view_name: String) -> PackedScene:
	match view_name:
		EventBus.SCENE_LOGIN:
			return LOGIN_SCENE
		EventBus.SCENE_REGISTER:
			return REGISTER_SCENE
		EventBus.SCENE_PLAYER_HUB:
			return PLAYER_HUB_SCENE
		EventBus.SCENE_HERO_CREATION:
			return HERO_CREATION_SCENE
		EventBus.SCENE_STORAGE:
			return STORAGE_SCENE
		EventBus.SCENE_AUCTION:
			return AUCTION_SCENE
		EventBus.SCENE_BATTLE_ROOM:
			return BATTLE_ROOM_SCENE
		EventBus.SCENE_SETTINGS:
			return SETTINGS_SCENE
		_:
			return null

func _on_eventbus_scene_changed() -> void:
	open_view(EventBus.last_scene_name)
