extends Node2D

const SlotClass = preload("res://Slot.gd")
const INVENTORY_DEBUG_SIGNALS := true

@onready var inventory_slots: GridContainer = $GridContainer
@onready var equip_slots: Array = $EquipSlots.get_children()

var holding_item = null
var holding_from_slot: SlotClass = null

func _ready() -> void:
	_setup_slots()
	if PlayerInventory.inventory_changed.is_connected(initialize_inventory) == false:
		PlayerInventory.inventory_changed.connect(initialize_inventory)
	if PlayerInventory.equipment_changed.is_connected(initialize_equips) == false:
		PlayerInventory.equipment_changed.connect(initialize_equips)
	initialize_inventory()
	initialize_equips()

func _setup_slots() -> void:
	var slots: Array = inventory_slots.get_children()
	for i: int in range(slots.size()):
		var slot := slots[i] as SlotClass
		if slot == null:
			continue
		slot.slot_index = i
		slot.slotType = SlotClass.SlotType.INVENTORY
		if slot.gui_input.is_connected(_on_slot_gui_input.bind(slot)) == false:
			slot.gui_input.connect(_on_slot_gui_input.bind(slot))
		_connect_slot_debug_signals(slot)

	for i: int in range(equip_slots.size()):
		var equip_slot := equip_slots[i] as SlotClass
		if equip_slot == null:
			continue
		equip_slot.slot_index = i
		if equip_slot.gui_input.is_connected(_on_slot_gui_input.bind(equip_slot)) == false:
			equip_slot.gui_input.connect(_on_slot_gui_input.bind(equip_slot))
		_connect_slot_debug_signals(equip_slot)

	if equip_slots.size() >= 3:
		(equip_slots[0] as SlotClass).slotType = SlotClass.SlotType.SHIRT
		(equip_slots[1] as SlotClass).slotType = SlotClass.SlotType.PANTS
		(equip_slots[2] as SlotClass).slotType = SlotClass.SlotType.SHOES

func initialize_inventory() -> void:
	var slots: Array = inventory_slots.get_children()
	for i: int in range(slots.size()):
		var slot := slots[i] as SlotClass
		if slot == null:
			continue
		if PlayerInventory.inventory_slots.has(i):
			var data: Array = PlayerInventory.inventory_slots[i]
			slot.initialize_item(str(data[0]), int(data[1]))
		elif slot.is_empty() == false:
			var orphan = slot.pickFromSlot()
			if orphan != null:
				orphan.queue_free()

func initialize_equips() -> void:
	for i: int in range(equip_slots.size()):
		var slot := equip_slots[i] as SlotClass
		if slot == null:
			continue
		if PlayerInventory.equipment_slots.has(i):
			var data: Array = PlayerInventory.equipment_slots[i]
			slot.initialize_item(str(data[0]), int(data[1]))
		elif slot.is_empty() == false:
			var orphan = slot.pickFromSlot()
			if orphan != null:
				orphan.queue_free()

func _input(_event: InputEvent) -> void:
	if holding_item != null:
		holding_item.global_position = get_global_mouse_position()

func _on_slot_gui_input(event: InputEvent, slot: SlotClass) -> void:
	if event is InputEventMouseButton == false:
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event.button_index != MOUSE_BUTTON_LEFT or mouse_event.pressed == false:
		return
	handle_slot_left_click(slot, mouse_event)

func handle_slot_left_click(slot: SlotClass, mouse_event: InputEventMouseButton) -> void:
	if holding_item != null:
		if not _is_valid_for_slot(slot, holding_item):
			_return_holding_to_origin()
			return

		if slot.is_empty():
			_place_holding_into_empty(slot)
		elif str(holding_item.item_name) == str(slot.item.item_name):
			_merge_holding_with_slot(slot)
		else:
			_swap_with_slot(slot, mouse_event)
		return

	if slot.is_empty() == false:
		_pick_from_slot(slot)

func _is_valid_for_slot(slot: SlotClass, dragged_item) -> bool:
	if dragged_item == null:
		return true
	if JsonData.item_data.has(dragged_item.item_name) == false:
		return true

	var category: String = str(JsonData.item_data[dragged_item.item_name].get("ItemCategory", ""))
	match slot.slotType:
		SlotClass.SlotType.SHIRT:
			return category == "Shirt"
		SlotClass.SlotType.PANTS:
			return category == "Pants"
		SlotClass.SlotType.SHOES:
			return category == "Shoes"
		_:
			return true

func _pick_from_slot(slot: SlotClass) -> void:
	PlayerInventory.remove_item(slot)
	holding_item = slot.pickFromSlot()
	holding_from_slot = slot
	if holding_item != null:
		holding_item.global_position = get_global_mouse_position()

func _place_holding_into_empty(slot: SlotClass) -> void:
	if holding_item == null:
		return
	PlayerInventory.add_item_to_empty_slot(holding_item, slot)
	slot.putIntoSlot(holding_item)
	holding_item = null
	holding_from_slot = null

func _merge_holding_with_slot(slot: SlotClass) -> void:
	if holding_item == null:
		return
	if holding_item == null or slot.item == null:
		return

	var stack_size: int = int(JsonData.item_data[slot.item.item_name].get("StackSize", 1))
	var able_to_add: int = stack_size - int(slot.item.item_quantity)
	if able_to_add <= 0:
		return

	if able_to_add >= int(holding_item.item_quantity):
		PlayerInventory.add_item_quantity(slot, int(holding_item.item_quantity))
		slot.item.add_item_quantity(int(holding_item.item_quantity))
		holding_item.queue_free()
		holding_item = null
		holding_from_slot = null
	else:
		PlayerInventory.add_item_quantity(slot, able_to_add)
		slot.item.add_item_quantity(able_to_add)
		holding_item.decrease_item_quantity(able_to_add)

	if holding_item == null:
		holding_from_slot = null

func _swap_with_slot(slot: SlotClass, event: InputEventMouseButton) -> void:
	if holding_item == null:
		return
	if holding_from_slot == null:
		return

	PlayerInventory.remove_item(slot)
	var target_item = slot.pickFromSlot()
	if target_item == null:
		return

	PlayerInventory.add_item_to_empty_slot(holding_item, slot)
	slot.putIntoSlot(holding_item)

	if holding_from_slot.is_inside_tree():
		PlayerInventory.add_item_to_empty_slot(target_item, holding_from_slot)
		holding_from_slot.putIntoSlot(target_item)
		holding_from_slot.notify_swapped(slot)
		slot.notify_swapped(holding_from_slot)
		holding_item = null
		holding_from_slot = null
	else:
		holding_item = target_item
		holding_item.global_position = event.global_position

func _return_holding_to_origin() -> void:
	if holding_item == null:
		return
	if holding_from_slot == null or holding_from_slot.is_inside_tree() == false:
		return

	if holding_from_slot.is_empty():
		PlayerInventory.add_item_to_empty_slot(holding_item, holding_from_slot)
		holding_from_slot.putIntoSlot(holding_item)
	else:
		holding_item.queue_free()
	holding_item = null
	holding_from_slot = null

func _connect_slot_debug_signals(slot: SlotClass) -> void:
	if INVENTORY_DEBUG_SIGNALS == false:
		return
	if slot.item_picked.is_connected(_on_slot_item_picked) == false:
		slot.item_picked.connect(_on_slot_item_picked)
	if slot.item_dropped.is_connected(_on_slot_item_dropped) == false:
		slot.item_dropped.connect(_on_slot_item_dropped)
	if slot.item_swapped.is_connected(_on_slot_item_swapped) == false:
		slot.item_swapped.connect(_on_slot_item_swapped)

func _slot_type_name(slot_type: int) -> String:
	match slot_type:
		SlotClass.SlotType.HOTBAR:
			return "HOTBAR"
		SlotClass.SlotType.INVENTORY:
			return "INVENTORY"
		SlotClass.SlotType.SHIRT:
			return "SHIRT"
		SlotClass.SlotType.PANTS:
			return "PANTS"
		SlotClass.SlotType.SHOES:
			return "SHOES"
		_:
			return "UNKNOWN"

func _on_slot_item_picked(slot: SlotClass, picked_item) -> void:
	if INVENTORY_DEBUG_SIGNALS:
		print("[Inventory][Signal] item_picked slot=%s[%d] item=%s" % [_slot_type_name(slot.slotType), slot.slot_index, str(picked_item.item_name)])

func _on_slot_item_dropped(slot: SlotClass, dropped_item) -> void:
	if INVENTORY_DEBUG_SIGNALS:
		print("[Inventory][Signal] item_dropped slot=%s[%d] item=%s" % [_slot_type_name(slot.slotType), slot.slot_index, str(dropped_item.item_name)])

func _on_slot_item_swapped(from_slot: SlotClass, to_slot: SlotClass) -> void:
	if INVENTORY_DEBUG_SIGNALS:
		print("[Inventory][Signal] item_swapped from=%s[%d] to=%s[%d]" % [_slot_type_name(from_slot.slotType), from_slot.slot_index, _slot_type_name(to_slot.slotType), to_slot.slot_index])
