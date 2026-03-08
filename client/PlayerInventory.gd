extends Node

signal inventory_changed
signal hotbar_changed
signal equipment_changed
signal active_item_updated

const NUM_INVENTORY_SLOTS := 20
const NUM_HOTBAR_SLOTS := 8

var active_item_slot: int = 0

var inventory_slots: Dictionary = {
	0: ["Iron Sword", 1],
	1: ["Iron Sword", 1],
	2: ["Slime Potion", 20],
	3: ["Slime Potion", 12],
}

var hotbar_slots: Dictionary = {
	0: ["Iron Sword", 1],
	3: ["Slime Potion", 5],
}

var equipment_slots: Dictionary = {
	0: ["Brown Shirt", 1],
	1: ["Blue Jeans", 1],
	2: ["Brown Boots", 1],
}

var inventory: Dictionary = inventory_slots
var hotbar: Dictionary = hotbar_slots
var equips: Dictionary = equipment_slots

func _ready() -> void:
	_emit_all_changed()

func _emit_all_changed() -> void:
	inventory_changed.emit()
	hotbar_changed.emit()
	equipment_changed.emit()
	active_item_updated.emit()

func add_item(item_name: String, item_quantity: int) -> void:
	if item_quantity <= 0:
		return
	var stack_size: int = int(JsonData.item_data.get(item_name, {}).get("StackSize", 1))

	var slot_indices: Array = inventory_slots.keys()
	slot_indices.sort()
	for slot_index in slot_indices:
		if inventory_slots[slot_index][0] == item_name:
			var current_qt: int = int(inventory_slots[slot_index][1])
			var able_to_add: int = stack_size - current_qt
			if able_to_add <= 0:
				continue
			if able_to_add >= item_quantity:
				inventory_slots[slot_index][1] = current_qt + item_quantity
				inventory_changed.emit()
				return
			else:
				inventory_slots[slot_index][1] = current_qt + able_to_add
				item_quantity -= able_to_add

	for i: int in range(NUM_INVENTORY_SLOTS):
		if inventory_slots.has(i) == false:
			inventory_slots[i] = [item_name, item_quantity]
			inventory_changed.emit()
			return

func update_slot_visual(_slot_index: int, _item_name: String, _new_quantity: int) -> void:
	inventory_changed.emit()
	hotbar_changed.emit()
	equipment_changed.emit()

func remove_item(slot) -> void:
	match slot.slotType:
		slot.SlotType.HOTBAR:
			hotbar_slots.erase(slot.slot_index)
			hotbar_changed.emit()
		slot.SlotType.INVENTORY:
			inventory_slots.erase(slot.slot_index)
			inventory_changed.emit()
		_:
			equipment_slots.erase(slot.slot_index)
			equipment_changed.emit()

func add_item_to_empty_slot(item, slot) -> void:
	var payload := [item.item_name, item.item_quantity]
	match slot.slotType:
		slot.SlotType.HOTBAR:
			hotbar_slots[slot.slot_index] = payload
			hotbar_changed.emit()
		slot.SlotType.INVENTORY:
			inventory_slots[slot.slot_index] = payload
			inventory_changed.emit()
		_:
			equipment_slots[slot.slot_index] = payload
			equipment_changed.emit()

func add_item_quantity(slot, quantity_to_add: int) -> void:
	if quantity_to_add <= 0:
		return
	match slot.slotType:
		slot.SlotType.HOTBAR:
			hotbar_slots[slot.slot_index][1] += quantity_to_add
			hotbar_changed.emit()
		slot.SlotType.INVENTORY:
			inventory_slots[slot.slot_index][1] += quantity_to_add
			inventory_changed.emit()
		_:
			equipment_slots[slot.slot_index][1] += quantity_to_add
			equipment_changed.emit()

func active_item_scroll_up() -> void:
	active_item_slot = (active_item_slot + 1) % NUM_HOTBAR_SLOTS
	active_item_updated.emit()

func active_item_scroll_down() -> void:
	if active_item_slot == 0:
		active_item_slot = NUM_HOTBAR_SLOTS - 1
	else:
		active_item_slot -= 1
	active_item_updated.emit()
