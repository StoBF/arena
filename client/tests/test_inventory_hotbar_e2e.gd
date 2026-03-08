extends GutTest

var _saved_inventory: Dictionary = {}
var _saved_hotbar: Dictionary = {}
var _saved_equips: Dictionary = {}
var _saved_inventory_slots: Dictionary = {}
var _saved_hotbar_slots: Dictionary = {}
var _saved_equipment_slots: Dictionary = {}
var _saved_active_item_slot: int = 0

var _ui_root: Node2D
var _inventory_ui: Node
var _hotbar_ui: CanvasLayer

func before_each() -> void:
	_save_player_inventory_state()
	_seed_player_inventory_state()
	await _spawn_ui()

func after_each() -> void:
	if _ui_root != null and _ui_root.is_inside_tree():
		_ui_root.queue_free()
	_restore_player_inventory_state()

func test_drag_inventory_to_hotbar_then_activate_key_updates_label() -> void:
	var from_slot = _inventory_ui.inventory_slots.get_child(0)
	var to_hotbar_slot = _hotbar_ui.hotbar_slots.get_child(4)
	var click := _left_click_event()

	_inventory_ui.handle_slot_left_click(from_slot, click)
	_inventory_ui.handle_slot_left_click(to_hotbar_slot, click)

	assert_eq(PlayerInventory.inventory[0], null, "Source inventory slot should be empty after drag")
	assert_true(PlayerInventory.hotbar[4] != null, "Target hotbar slot should receive item")
	assert_eq(str(PlayerInventory.hotbar[4].get("name", "")), "Tree Branch")

	_hotbar_ui._unhandled_input(_key_event(KEY_5))

	assert_eq(PlayerInventory.active_item_slot, 4, "Key 5 should activate hotbar index 4")
	assert_eq(_hotbar_ui.active_item_label.text, "Tree Branch", "Active label should show newly assigned hotbar item")

func test_invalid_equip_rolls_back_then_hotbar_activation_still_works() -> void:
	var invalid_item_slot = _inventory_ui.inventory_slots.get_child(1)
	var pants_slot = _inventory_ui.equip_slots[1]
	var click := _left_click_event()

	_inventory_ui.handle_slot_left_click(invalid_item_slot, click)
	_inventory_ui.handle_slot_left_click(pants_slot, click)

	assert_true(PlayerInventory.inventory[1] != null, "Invalid equip should restore item to original slot")
	assert_eq(str(PlayerInventory.inventory[1].get("name", "")), "Slime Potion")
	assert_eq(PlayerInventory.equips["pants"], null, "Pants slot must remain unchanged on invalid drop")

	var valid_item_slot = _inventory_ui.inventory_slots.get_child(0)
	var to_hotbar_slot = _hotbar_ui.hotbar_slots.get_child(4)
	_inventory_ui.handle_slot_left_click(valid_item_slot, click)
	_inventory_ui.handle_slot_left_click(to_hotbar_slot, click)

	_hotbar_ui._unhandled_input(_key_event(KEY_5))
	assert_eq(PlayerInventory.active_item_slot, 4)
	assert_eq(_hotbar_ui.active_item_label.text, "Tree Branch")

func _spawn_ui() -> void:
	_ui_root = Node2D.new()
	_ui_root.name = "UserInterface"
	get_tree().root.add_child(_ui_root)

	var inventory_scene: PackedScene = preload("res://Inventory.tscn")
	_inventory_ui = inventory_scene.instantiate()
	_ui_root.add_child(_inventory_ui)

	var hotbar_scene: PackedScene = preload("res://Hotbar.tscn")
	_hotbar_ui = hotbar_scene.instantiate()
	_ui_root.add_child(_hotbar_ui)

	await get_tree().process_frame
	await get_tree().process_frame

func _left_click_event() -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	return event

func _key_event(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	event.echo = false
	return event

func _save_player_inventory_state() -> void:
	_saved_inventory = PlayerInventory.inventory.duplicate(true)
	_saved_hotbar = PlayerInventory.hotbar.duplicate(true)
	_saved_equips = PlayerInventory.equips.duplicate(true)
	_saved_inventory_slots = PlayerInventory.inventory_slots.duplicate(true)
	_saved_hotbar_slots = PlayerInventory.hotbar_slots.duplicate(true)
	_saved_equipment_slots = PlayerInventory.equipment_slots.duplicate(true)
	_saved_active_item_slot = PlayerInventory.active_item_slot

func _restore_player_inventory_state() -> void:
	PlayerInventory.inventory = _saved_inventory.duplicate(true)
	PlayerInventory.hotbar = _saved_hotbar.duplicate(true)
	PlayerInventory.equips = _saved_equips.duplicate(true)
	PlayerInventory.inventory_slots = _saved_inventory_slots.duplicate(true)
	PlayerInventory.hotbar_slots = _saved_hotbar_slots.duplicate(true)
	PlayerInventory.equipment_slots = _saved_equipment_slots.duplicate(true)
	PlayerInventory.active_item_slot = _saved_active_item_slot

func _seed_player_inventory_state() -> void:
	for i: int in range(PlayerInventory.NUM_INVENTORY_SLOTS):
		PlayerInventory.inventory[i] = null
	for i: int in range(PlayerInventory.NUM_HOTBAR_SLOTS):
		PlayerInventory.hotbar[i] = null
	PlayerInventory.equips["shirt"] = null
	PlayerInventory.equips["pants"] = null
	PlayerInventory.equips["shoes"] = null

	PlayerInventory.inventory[0] = {"name": "Tree Branch", "quantity": 4}
	PlayerInventory.inventory[1] = {"name": "Slime Potion", "quantity": 5}
	PlayerInventory.hotbar[0] = {"name": "Iron Sword", "quantity": 1}
	PlayerInventory.active_item_slot = 0
	PlayerInventory._sync_legacy_views()
	PlayerInventory._emit_inventory_updated()
	PlayerInventory._emit_hotbar_updated()
	PlayerInventory._emit_equipment_updated()
