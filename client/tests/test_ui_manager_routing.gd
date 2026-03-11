extends GutTest

var _main_instance: Control = null

func before_each() -> void:
	var main_scene: PackedScene = preload("res://Main.tscn")
	_main_instance = main_scene.instantiate() as Control
	get_tree().root.add_child(_main_instance)
	await get_tree().process_frame
	await get_tree().process_frame

func after_each() -> void:
	if _main_instance != null and _main_instance.is_inside_tree():
		_main_instance.queue_free()

func test_main_opens_player_hub_by_default() -> void:
	var current_view_root: Control = _main_instance.get_node("UIRoot/CurrentView") as Control
	assert_not_null(current_view_root, "CurrentView root should exist")
	assert_eq(current_view_root.get_child_count(), 1, "One default view should be loaded")
	assert_eq(current_view_root.get_child(0).name, "PlayerHub", "Default view should be PlayerHub")

func test_ui_manager_can_route_to_storage() -> void:
	_main_instance.call("open_view", "Storage")
	await get_tree().process_frame
	await get_tree().process_frame

	var current_view_root: Control = _main_instance.get_node("UIRoot/CurrentView") as Control
	assert_eq(current_view_root.get_child_count(), 1, "One routed view should be loaded")
	assert_eq(current_view_root.get_child(0).name, "Storage", "Routed view should be Storage")
