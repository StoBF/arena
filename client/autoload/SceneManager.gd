extends Node

var _ui_root: Node = null


func bind_ui_root(node: Node) -> void:
	_ui_root = node


func open_playerhub() -> void:
	_open_view("PlayerHub")


func open_auction() -> void:
	_open_view("Auction")


func open_inventory() -> void:
	_open_view("Storage")


func open_settings() -> void:
	_open_view("Settings")


func open_auth() -> void:
	_open_view("LoginScene")


func open_register() -> void:
	_open_view("RegisterScene")


func open_hero_creation() -> void:
	_open_view("HeroCreation")


func open_battle_room() -> void:
	_open_view("BattleRoom")


func _open_view(view_name: String) -> void:
	var target := _resolve_ui_root()
	if target == null:
		return
	if target.has_method("open_view"):
		target.call("open_view", view_name)
	if has_node("/root/EventBus"):
		EventBus.emit_scene_changed(view_name)


func _resolve_ui_root() -> Node:
	if _ui_root != null and is_instance_valid(_ui_root):
		return _ui_root
	var current_scene: Node = get_tree().current_scene
	if current_scene != null and current_scene.has_method("open_view"):
		_ui_root = current_scene
		return _ui_root
	return null
