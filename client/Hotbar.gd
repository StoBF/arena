extends Node2D

const SlotClass = preload("res://Slot.gd")

@onready var hotbar_slots: GridContainer = $HotbarSlots
@onready var active_item_label: Label = $ActiveItemLabel
@onready var slots: Array = hotbar_slots.get_children()

func _ready() -> void:
	if PlayerInventory.active_item_updated.is_connected(update_active_item_label) == false:
		PlayerInventory.active_item_updated.connect(update_active_item_label)
	if PlayerInventory.hotbar_changed.is_connected(initialize_hotbar) == false:
		PlayerInventory.hotbar_changed.connect(initialize_hotbar)

	for i: int in range(slots.size()):
		var slot := slots[i] as SlotClass
		if slot == null:
			continue
		slot.slotType = SlotClass.SlotType.HOTBAR
		slot.slot_index = i
		if slot.gui_input.is_connected(_on_slot_gui_input.bind(slot)) == false:
			slot.gui_input.connect(_on_slot_gui_input.bind(slot))
		if PlayerInventory.active_item_updated.is_connected(slot.refresh_style) == false:
			PlayerInventory.active_item_updated.connect(slot.refresh_style)

	initialize_hotbar()
	update_active_item_label()

func initialize_hotbar() -> void:
	for i: int in range(slots.size()):
		var slot := slots[i] as SlotClass
		if slot == null:
			continue
		if PlayerInventory.hotbar_slots.has(i):
			var data: Array = PlayerInventory.hotbar_slots[i]
			slot.initialize_item(str(data[0]), int(data[1]))
		elif slot.is_empty() == false:
			var orphan = slot.pickFromSlot()
			if orphan != null:
				orphan.queue_free()
		slot.refresh_style()

func update_active_item_label() -> void:
	if PlayerInventory.active_item_slot < 0 or PlayerInventory.active_item_slot >= slots.size():
		active_item_label.text = ""
		return
	var active_slot := slots[PlayerInventory.active_item_slot] as SlotClass
	if active_slot != null and active_slot.item != null:
		active_item_label.text = str(active_slot.item.item_name)
	else:
		active_item_label.text = ""

func _input(_event: InputEvent) -> void:
	pass

func _on_slot_gui_input(event: InputEvent, slot: SlotClass) -> void:
	if event is InputEventMouseButton == false:
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event.button_index != MOUSE_BUTTON_LEFT or mouse_event.pressed == false:
		return
	var inventory_controller = _get_inventory_controller()
	if inventory_controller != null and inventory_controller.has_method("handle_slot_left_click"):
		inventory_controller.handle_slot_left_click(slot, mouse_event)

	update_active_item_label()

func _get_ui_root() -> Node:
	var current: Node = self
	while current != null:
		if current.name == "UserInterface":
			return current
		current = current.get_parent()
	return null

func _get_inventory_controller():
	var ui_root = _get_ui_root()
	if ui_root == null:
		return null
	return ui_root.get_node_or_null("Inventory")
