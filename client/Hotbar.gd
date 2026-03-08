extends CanvasLayer

const SlotClass = preload("res://Slot.gd")

@onready var hotbar_slots: GridContainer = $Panel/HotbarGrid
@onready var active_item_label: Label = $Panel/ActiveItemLabel
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

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey == false:
		return
	var key_event := event as InputEventKey
	if key_event.pressed == false or key_event.echo:
		return

	var slot_index := _hotbar_index_from_key_event(key_event)
	if slot_index < 0 or slot_index >= slots.size():
		return

	PlayerInventory.activate_hotbar_slot(slot_index)
	update_active_item_label()
	get_viewport().set_input_as_handled()

func _hotbar_index_from_key_event(event: InputEventKey) -> int:
	match event.keycode:
		KEY_1, KEY_KP_1:
			return 0
		KEY_2, KEY_KP_2:
			return 1
		KEY_3, KEY_KP_3:
			return 2
		KEY_4, KEY_KP_4:
			return 3
		KEY_5, KEY_KP_5:
			return 4
		KEY_6, KEY_KP_6:
			return 5
		KEY_7, KEY_KP_7:
			return 6
		KEY_8, KEY_KP_8:
			return 7
		_:
			return -1

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
