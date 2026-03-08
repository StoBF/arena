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

func test_drag_inventory_item_to_hotbar_updates_player_inventory() -> void:
	var from_slot = _inventory_slot(0)
	var hotbar_slot = _hotbar_slot(2)
	var click := _left_click_event()

	_inventory_ui.handle_slot_left_click(from_slot, click)
	_inventory_ui.handle_slot_left_click(hotbar_slot, click)

	assert_eq(PlayerInventory.inventory[0], null, "Inventory source slot should be cleared")
	assert_true(PlayerInventory.hotbar[2] != null, "Hotbar target should contain item payload")
	assert_eq(str(PlayerInventory.hotbar[2].get("name", "")), "Tree Branch")

func test_invalid_equip_drop_rolls_back_to_origin() -> void:
	var from_slot = _inventory_slot(1)
	var pants_slot = _equip_slot(1)
	var click := _left_click_event()

	_inventory_ui.handle_slot_left_click(from_slot, click)
	_inventory_ui.handle_slot_left_click(pants_slot, click)

	assert_true(PlayerInventory.inventory[1] != null, "Invalid equip must return item to original inventory slot")
	assert_eq(str(PlayerInventory.inventory[1].get("name", "")), "Slime Potion")
	assert_eq(PlayerInventory.equips["pants"], null, "Invalid equip must not modify pants equipment slot")
	assert_eq(_inventory_ui.holding_item, null, "Holding item should be cleared after rollback")

func test_drag_valid_pants_item_to_equip_slot_updates_mapping() -> void:
	var from_slot = _inventory_slot(2)
	var pants_slot = _equip_slot(1)
	var click := _left_click_event()

	_inventory_ui.handle_slot_left_click(from_slot, click)
	_inventory_ui.handle_slot_left_click(pants_slot, click)

	assert_eq(PlayerInventory.inventory[2], null, "Inventory source should be emptied after successful equip")
	assert_true(PlayerInventory.equips["pants"] != null, "Pants equipment payload should be stored")
	assert_eq(str(PlayerInventory.equips["pants"].get("name", "")), "Blue Jeans")
	assert_true(PlayerInventory.equipment_slots.has(1), "Legacy equipment index mapping for pants should be index 1")

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

func _inventory_slot(index: int):
	return _inventory_ui.inventory_slots.get_child(index)

func _equip_slot(index: int):
	return _inventory_ui.equip_slots[index]

func _hotbar_slot(index: int):
	return _hotbar_ui.hotbar_slots.get_child(index)

func _left_click_event() -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
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
	PlayerInventory.inventory[2] = {"name": "Blue Jeans", "quantity": 1}
	PlayerInventory.hotbar[0] = {"name": "Iron Sword", "quantity": 1}
	PlayerInventory.active_item_slot = 0
	PlayerInventory._sync_legacy_views()
	PlayerInventory._emit_inventory_updated()
	PlayerInventory._emit_hotbar_updated()
	PlayerInventory._emit_equipment_updated()
