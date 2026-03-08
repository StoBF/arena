extends CanvasLayer

const SlotClass = preload("res://Slot.gd")

@onready var inventory_grid: GridContainer = $Panel/InventoryGrid
@onready var equipment_grid: GridContainer = $Panel/EquipmentGrid

func _ready() -> void:
	_setup_slots()
	if PlayerInventory.inventory_changed.is_connected(_refresh_inventory_slots) == false:
		PlayerInventory.inventory_changed.connect(_refresh_inventory_slots)
	if PlayerInventory.equipment_changed.is_connected(_refresh_equipment_slots) == false:
		PlayerInventory.equipment_changed.connect(_refresh_equipment_slots)
	_refresh_inventory_slots()
	_refresh_equipment_slots()

func _setup_slots() -> void:
	var inventory_slots: Array = inventory_grid.get_children()
	for index: int in range(inventory_slots.size()):
		var slot := inventory_slots[index] as SlotClass
		if slot == null:
			continue
		slot.slot_index = index
		slot.slotType = SlotClass.SlotType.INVENTORY
		slot.refresh_style()

	var shirt_slot := equipment_grid.get_node_or_null("ShirtSlot") as SlotClass
	var pants_slot := equipment_grid.get_node_or_null("PantsSlot") as SlotClass
	var shoes_slot := equipment_grid.get_node_or_null("ShoesSlot") as SlotClass
	if shirt_slot:
		shirt_slot.slot_index = 0
		shirt_slot.slotType = SlotClass.SlotType.SHIRT
		shirt_slot.refresh_style()
	if pants_slot:
		pants_slot.slot_index = 1
		pants_slot.slotType = SlotClass.SlotType.PANTS
		pants_slot.refresh_style()
	if shoes_slot:
		shoes_slot.slot_index = 2
		shoes_slot.slotType = SlotClass.SlotType.SHOES
		shoes_slot.refresh_style()

func _refresh_inventory_slots() -> void:
	var slots: Array = inventory_grid.get_children()
	for index: int in range(slots.size()):
		var slot := slots[index] as SlotClass
		if slot == null:
			continue
		if PlayerInventory.inventory_slots.has(index):
			var entry: Array = PlayerInventory.inventory_slots[index]
			slot.initialize_item(str(entry[0]), int(entry[1]))
		else:
			if slot.is_empty() == false:
				var item = slot.pickFromSlot()
				if item != null:
					item.queue_free()
			slot.refresh_style()

func _refresh_equipment_slots() -> void:
	for index: int in range(3):
		var slot_name := "ShirtSlot" if index == 0 else "PantsSlot" if index == 1 else "ShoesSlot"
		var slot := equipment_grid.get_node_or_null(slot_name) as SlotClass
		if slot == null:
			continue
		if PlayerInventory.equipment_slots.has(index):
			var entry: Array = PlayerInventory.equipment_slots[index]
			slot.initialize_item(str(entry[0]), int(entry[1]))
		else:
			if slot.is_empty() == false:
				var item = slot.pickFromSlot()
				if item != null:
					item.queue_free()
			slot.refresh_style()
