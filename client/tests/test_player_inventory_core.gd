extends GutTest

var _saved_inventory: Dictionary = {}
var _saved_hotbar: Dictionary = {}
var _saved_equips: Dictionary = {}
var _saved_inventory_slots: Dictionary = {}
var _saved_hotbar_slots: Dictionary = {}
var _saved_equipment_slots: Dictionary = {}
var _saved_active_item_slot: int = 0

func before_each() -> void:
	_saved_inventory = PlayerInventory.inventory.duplicate(true)
	_saved_hotbar = PlayerInventory.hotbar.duplicate(true)
	_saved_equips = PlayerInventory.equips.duplicate(true)
	_saved_inventory_slots = PlayerInventory.inventory_slots.duplicate(true)
	_saved_hotbar_slots = PlayerInventory.hotbar_slots.duplicate(true)
	_saved_equipment_slots = PlayerInventory.equipment_slots.duplicate(true)
	_saved_active_item_slot = PlayerInventory.active_item_slot

	for i: int in range(PlayerInventory.NUM_INVENTORY_SLOTS):
		PlayerInventory.inventory[i] = null
	for i: int in range(PlayerInventory.NUM_HOTBAR_SLOTS):
		PlayerInventory.hotbar[i] = null
	PlayerInventory.equips["shirt"] = null
	PlayerInventory.equips["pants"] = null
	PlayerInventory.equips["shoes"] = null

	PlayerInventory.inventory[0] = {"name": "Blue Jeans", "quantity": 1}
	PlayerInventory.inventory[1] = {"name": "Slime Potion", "quantity": 5}
	PlayerInventory.hotbar[0] = {"name": "Iron Sword", "quantity": 1}
	PlayerInventory.active_item_slot = 0
	PlayerInventory._sync_legacy_views()

func after_each() -> void:
	PlayerInventory.inventory = _saved_inventory.duplicate(true)
	PlayerInventory.hotbar = _saved_hotbar.duplicate(true)
	PlayerInventory.equips = _saved_equips.duplicate(true)
	PlayerInventory.inventory_slots = _saved_inventory_slots.duplicate(true)
	PlayerInventory.hotbar_slots = _saved_hotbar_slots.duplicate(true)
	PlayerInventory.equipment_slots = _saved_equipment_slots.duplicate(true)
	PlayerInventory.active_item_slot = _saved_active_item_slot

func test_remove_item_dispatch_supports_name_and_slot() -> void:
	var removed_by_name: int = PlayerInventory.remove_item("Slime Potion", 2)
	assert_eq(removed_by_name, 2, "Name-based remove should remove requested quantity")
	assert_eq(int(PlayerInventory.inventory[1].get("quantity", -1)), 3)

	var removed_by_slot: int = PlayerInventory.remove_item({"container": "inventory", "key": 1})
	assert_eq(removed_by_slot, 1, "Slot-based remove should return success flag 1")
	assert_eq(PlayerInventory.inventory[1], null, "Inventory slot should be cleared")

func test_move_item_blocks_invalid_equipment_category() -> void:
	var ok: bool = PlayerInventory.move_item("inventory:1", "equips:pants")
	assert_false(ok, "Consumable item should not be placeable in pants slot")
	assert_eq(str(PlayerInventory.inventory[1].get("name", "")), "Slime Potion")
	assert_eq(PlayerInventory.equips["pants"], null)

func test_move_item_allows_valid_equipment_category() -> void:
	var ok: bool = PlayerInventory.move_item("inventory:0", "equips:pants")
	assert_true(ok, "Pants item should be placeable in pants slot")
	assert_eq(PlayerInventory.inventory[0], null)
	assert_eq(str(PlayerInventory.equips["pants"].get("name", "")), "Blue Jeans")
	assert_true(PlayerInventory.equipment_slots.has(1), "Legacy equipment view should map pants to index 1")

func test_swap_updates_authoritative_and_legacy_views() -> void:
	PlayerInventory.inventory[2] = {"name": "Tree Branch", "quantity": 4}
	PlayerInventory.hotbar[2] = {"name": "Slime Potion", "quantity": 1}
	PlayerInventory._sync_legacy_views()

	var ok: bool = PlayerInventory.swap_items("inventory:2", "hotbar:2")
	assert_true(ok)
	assert_eq(str(PlayerInventory.inventory[2].get("name", "")), "Slime Potion")
	assert_eq(str(PlayerInventory.hotbar[2].get("name", "")), "Tree Branch")
	assert_true(PlayerInventory.inventory_slots.has(2), "Legacy inventory view should stay in sync")
	assert_true(PlayerInventory.hotbar_slots.has(2), "Legacy hotbar view should stay in sync")

func test_activate_hotbar_slot_bounds() -> void:
	PlayerInventory.activate_hotbar_slot(7)
	assert_eq(PlayerInventory.active_item_slot, 7)
	PlayerInventory.activate_hotbar_slot(99)
	assert_eq(PlayerInventory.active_item_slot, 7, "Out-of-range activation should be ignored")
