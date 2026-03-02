extends GutTest

const HERO_ID := 101
const SLOT := "Weapon"

var _saved_items_by_hero: Dictionary = {}
var _saved_equipment_by_hero: Dictionary = {}
var _saved_last_loaded_hero_id: int = -1

func before_each() -> void:
	_saved_items_by_hero = InventoryManager._items_by_hero.duplicate(true)
	_saved_equipment_by_hero = InventoryManager._equipment_by_hero.duplicate(true)
	_saved_last_loaded_hero_id = InventoryManager._last_loaded_hero_id

	InventoryManager._last_loaded_hero_id = HERO_ID
	InventoryManager._items_by_hero[HERO_ID] = [
		{"id": 1, "name": "Iron Sword", "type": "weapon", "slot": SLOT},
		{"id": 2, "name": "Steel Sword", "type": "weapon", "slot": SLOT}
	]
	InventoryManager._equipment_by_hero[HERO_ID] = {
		SLOT: {"id": 99, "name": "Old Sword", "type": "weapon", "slot": SLOT}
	}

func after_each() -> void:
	InventoryManager._items_by_hero = _saved_items_by_hero.duplicate(true)
	InventoryManager._equipment_by_hero = _saved_equipment_by_hero.duplicate(true)
	InventoryManager._last_loaded_hero_id = _saved_last_loaded_hero_id

func test_apply_optimistic_equip_swaps_equipment() -> void:
	var snapshot := InventoryManager.apply_optimistic_equip(HERO_ID, 1, SLOT)
	var eq := InventoryManager.get_equipment(HERO_ID)
	var items := InventoryManager.get_items_for_hero(HERO_ID)

	assert_eq(int(eq[SLOT].get("id", -1)), 1, "New item should be equipped")
	assert_true(bool(snapshot.get("used_swap", false)), "Swap flag should be true when slot had existing item")
	assert_eq(int(snapshot.get("previous_slot_item", {}).get("id", -1)), 99, "Snapshot should store previous slot item")
	assert_true(_contains_item(items, 99), "Previous equipped item should return to inventory")
	assert_false(_contains_item(items, 1), "Equipped item should be removed from inventory")

func test_rollback_optimistic_equip_restores_previous_state() -> void:
	var snapshot := InventoryManager.apply_optimistic_equip(HERO_ID, 2, SLOT)
	InventoryManager.rollback_optimistic_equip(HERO_ID, SLOT, snapshot)

	var eq := InventoryManager.get_equipment(HERO_ID)
	var items := InventoryManager.get_items_for_hero(HERO_ID)
	assert_eq(int(eq[SLOT].get("id", -1)), 99, "Rollback should restore previous equipped item")
	assert_true(_contains_item(items, 2), "Rollback should restore removed item to inventory")
	assert_false(_contains_item(items, 99), "Rollback should remove temporary swapped item from inventory")

func _contains_item(items: Array, item_id: int) -> bool:
	for item in items:
		if int(item.get("id", -1)) == item_id:
			return true
	return false
