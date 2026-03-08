extends GutTest

var _saved_inventory: Dictionary = {}
var _saved_hotbar: Dictionary = {}
var _saved_equips: Dictionary = {}
var _saved_inventory_slots: Dictionary = {}
var _saved_hotbar_slots: Dictionary = {}
var _saved_equipment_slots: Dictionary = {}
var _saved_active_item_slot: int = 0

var _ui_root: Node2D
var _hotbar_ui: CanvasLayer

func before_each() -> void:
	_save_player_inventory_state()
	_seed_player_inventory_state()
	await _spawn_hotbar_ui()

func after_each() -> void:
	if _ui_root != null and _ui_root.is_inside_tree():
		_ui_root.queue_free()
	_restore_player_inventory_state()

func test_key_1_selects_hotbar_slot_0_and_updates_label() -> void:
	var event := _key_event(KEY_1)
	_hotbar_ui._unhandled_input(event)

	assert_eq(PlayerInventory.active_item_slot, 0)
	assert_eq(_hotbar_ui.active_item_label.text, "Iron Sword")

func test_key_3_selects_hotbar_slot_2_and_updates_label() -> void:
	var event := _key_event(KEY_3)
	_hotbar_ui._unhandled_input(event)

	assert_eq(PlayerInventory.active_item_slot, 2)
	assert_eq(_hotbar_ui.active_item_label.text, "Tree Branch")

func test_key_8_selects_hotbar_slot_7_and_updates_label() -> void:
	var event := _key_event(KEY_8)
	_hotbar_ui._unhandled_input(event)

	assert_eq(PlayerInventory.active_item_slot, 7)
	assert_eq(_hotbar_ui.active_item_label.text, "Slime Potion")

func test_non_hotbar_key_is_ignored() -> void:
	PlayerInventory.activate_hotbar_slot(2)
	_hotbar_ui.update_active_item_label()
	var event := _key_event(KEY_Q)
	_hotbar_ui._unhandled_input(event)

	assert_eq(PlayerInventory.active_item_slot, 2)
	assert_eq(_hotbar_ui.active_item_label.text, "Tree Branch")

func _spawn_hotbar_ui() -> void:
	_ui_root = Node2D.new()
	_ui_root.name = "UserInterface"
	get_tree().root.add_child(_ui_root)

	var hotbar_scene: PackedScene = preload("res://Hotbar.tscn")
	_hotbar_ui = hotbar_scene.instantiate()
	_ui_root.add_child(_hotbar_ui)

	await get_tree().process_frame
	await get_tree().process_frame

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

	PlayerInventory.hotbar[0] = {"name": "Iron Sword", "quantity": 1}
	PlayerInventory.hotbar[2] = {"name": "Tree Branch", "quantity": 4}
	PlayerInventory.hotbar[7] = {"name": "Slime Potion", "quantity": 5}
	PlayerInventory.active_item_slot = 0
	PlayerInventory._sync_legacy_views()
	PlayerInventory._emit_hotbar_updated()
