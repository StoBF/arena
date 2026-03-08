extends Node

signal inventory_updated
signal hotbar_updated
signal equipment_updated

signal inventory_changed
signal hotbar_changed
signal equipment_changed
signal active_item_updated

const NUM_INVENTORY_SLOTS := 20
const NUM_HOTBAR_SLOTS := 8
const EQUIP_KEYS := ["shirt", "pants", "shoes"]

var active_item_slot: int = 0

var inventory: Dictionary = {}
var hotbar: Dictionary = {}
var equips: Dictionary = {"shirt": null, "pants": null, "shoes": null}

var inventory_slots: Dictionary = {}
var hotbar_slots: Dictionary = {}
var equipment_slots: Dictionary = {}

func _ready() -> void:
	_initialize_empty_slots()
	inventory[2] = {"name": "Potion", "quantity": 3}
	hotbar[1] = {"name": "Potion", "quantity": 1}
	_sync_legacy_views()
	_emit_inventory_updated()
	_emit_hotbar_updated()
	_emit_equipment_updated()
	active_item_updated.emit()

func _initialize_empty_slots() -> void:
	for i: int in range(NUM_INVENTORY_SLOTS):
		inventory[i] = null
	for i: int in range(NUM_HOTBAR_SLOTS):
		hotbar[i] = null
	for key: String in EQUIP_KEYS:
		equips[key] = null

func add_item(item_name: String, amount: int) -> void:
	if amount <= 0:
		return
	var remaining: int = amount
	var stack_size: int = _stack_size_for(item_name)

	for index: int in range(NUM_INVENTORY_SLOTS):
		var slot_item = inventory.get(index, null)
		if slot_item == null:
			continue
		if _item_name(slot_item) != item_name:
			continue
		var current_qty: int = _item_quantity(slot_item)
		var free_space: int = stack_size - current_qty
		if free_space <= 0:
			continue
		var delta: int = mini(free_space, remaining)
		inventory[index] = {"name": item_name, "quantity": current_qty + delta}
		remaining -= delta
		if remaining <= 0:
			_sync_legacy_views()
			_emit_inventory_updated()
			return

	for index: int in range(NUM_INVENTORY_SLOTS):
		if inventory.get(index, null) != null:
			continue
		var delta: int = mini(stack_size, remaining)
		inventory[index] = {"name": item_name, "quantity": delta}
		remaining -= delta
		if remaining <= 0:
			_sync_legacy_views()
			_emit_inventory_updated()
			return

	_sync_legacy_views()
	_emit_inventory_updated()

func remove_item(item_or_slot, amount: int = 1) -> int:
	if item_or_slot is String:
		return _remove_item_by_name(str(item_or_slot), amount)
	return _remove_item_from_slot(item_or_slot)

func _remove_item_by_name(item_name: String, amount: int = 1) -> int:
	if amount <= 0:
		return 0
	var remaining: int = amount

	for index: int in range(NUM_HOTBAR_SLOTS):
		if remaining <= 0:
			break
		var slot_item = hotbar.get(index, null)
		if slot_item == null or _item_name(slot_item) != item_name:
			continue
		var current_qty: int = _item_quantity(slot_item)
		var delta: int = mini(current_qty, remaining)
		current_qty -= delta
		remaining -= delta
		hotbar[index] = null if current_qty <= 0 else {"name": item_name, "quantity": current_qty}

	for index: int in range(NUM_INVENTORY_SLOTS):
		if remaining <= 0:
			break
		var slot_item = inventory.get(index, null)
		if slot_item == null or _item_name(slot_item) != item_name:
			continue
		var current_qty: int = _item_quantity(slot_item)
		var delta: int = mini(current_qty, remaining)
		current_qty -= delta
		remaining -= delta
		inventory[index] = null if current_qty <= 0 else {"name": item_name, "quantity": current_qty}

	_sync_legacy_views()
	_emit_inventory_updated()
	_emit_hotbar_updated()
	return amount - remaining

func move_item(from_slot, to_slot) -> bool:
	var from_ref: Dictionary = _parse_slot_ref(from_slot)
	var to_ref: Dictionary = _parse_slot_ref(to_slot)
	if from_ref.is_empty() or to_ref.is_empty():
		return false

	var from_item = _get_container_value(from_ref)
	if from_item == null:
		return false

	var to_item = _get_container_value(to_ref)
	if to_item != null:
		return swap_items(from_ref, to_ref)

	if not _can_place_in_slot(from_item, to_ref):
		return false

	_set_container_value(to_ref, from_item)
	_set_container_value(from_ref, null)
	_sync_legacy_views()
	_emit_for_container(from_ref.get("container", ""))
	_emit_for_container(to_ref.get("container", ""))
	return true

func swap_items(slot_a, slot_b) -> bool:
	var a_ref: Dictionary = _parse_slot_ref(slot_a)
	var b_ref: Dictionary = _parse_slot_ref(slot_b)
	if a_ref.is_empty() or b_ref.is_empty():
		return false

	var a_item = _get_container_value(a_ref)
	var b_item = _get_container_value(b_ref)
	if a_item == null and b_item == null:
		return true

	if a_item != null and not _can_place_in_slot(a_item, b_ref):
		return false
	if b_item != null and not _can_place_in_slot(b_item, a_ref):
		return false

	_set_container_value(a_ref, b_item)
	_set_container_value(b_ref, a_item)
	_sync_legacy_views()
	_emit_for_container(a_ref.get("container", ""))
	_emit_for_container(b_ref.get("container", ""))
	return true

func _remove_item_from_slot(slot) -> int:
	var ref := _parse_slot_ref(slot)
	if ref.is_empty():
		return 0
	_set_container_value(ref, null)
	_sync_legacy_views()
	_emit_for_container(ref.get("container", ""))
	return 1

func add_item_to_empty_slot(item, slot) -> void:
	if item == null:
		return
	var ref := _parse_slot_ref(slot)
	if ref.is_empty():
		return
	var payload := {"name": str(item.item_name), "quantity": int(item.item_quantity)}
	_set_container_value(ref, payload)
	_sync_legacy_views()
	_emit_for_container(ref.get("container", ""))

func add_item_quantity(slot, quantity_to_add: int) -> void:
	if quantity_to_add <= 0:
		return
	var ref := _parse_slot_ref(slot)
	if ref.is_empty():
		return
	var current = _get_container_value(ref)
	if current == null:
		return
	var item_name: String = _item_name(current)
	var current_qty: int = _item_quantity(current)
	var stack_size: int = _stack_size_for(item_name)
	var next_qty: int = mini(stack_size, current_qty + quantity_to_add)
	_set_container_value(ref, {"name": item_name, "quantity": next_qty})
	_sync_legacy_views()
	_emit_for_container(ref.get("container", ""))

func update_slot_visual(_slot_index, _item_name, _new_quantity) -> void:
	_sync_legacy_views()
	_emit_inventory_updated()
	_emit_hotbar_updated()
	_emit_equipment_updated()

func active_item_scroll_up() -> void:
	activate_hotbar_slot((active_item_slot + 1) % NUM_HOTBAR_SLOTS)

func active_item_scroll_down() -> void:
	if active_item_slot == 0:
		activate_hotbar_slot(NUM_HOTBAR_SLOTS - 1)
	else:
		activate_hotbar_slot(active_item_slot - 1)

func activate_hotbar_slot(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= NUM_HOTBAR_SLOTS:
		return
	active_item_slot = slot_index
	active_item_updated.emit()

func _stack_size_for(item_name: String) -> int:
	return JsonData.get_stack_size(item_name)

func _item_name(item_value) -> String:
	if item_value is Dictionary:
		return str((item_value as Dictionary).get("name", ""))
	if item_value is String:
		return str(item_value)
	return ""

func _item_quantity(item_value) -> int:
	if item_value is Dictionary:
		return maxi(1, int((item_value as Dictionary).get("quantity", 1)))
	return 1

func _can_place_in_slot(item_value, slot_ref: Dictionary) -> bool:
	var container: String = str(slot_ref.get("container", ""))
	if container != "equips":
		return true
	var equip_key: String = str(slot_ref.get("key", ""))
	var item_name: String = _item_name(item_value)
	var category: String = str(JsonData.get_item_data(item_name).get("ItemCategory", ""))
	if equip_key == "shirt":
		return category == "Shirt"
	if equip_key == "pants":
		return category == "Pants"
	if equip_key == "shoes":
		return category == "Shoes"
	return true

func _parse_slot_ref(slot_ref) -> Dictionary:
	if slot_ref is Dictionary:
		return {"container": str((slot_ref as Dictionary).get("container", "")), "key": (slot_ref as Dictionary).get("key", null)}
	if slot_ref is String:
		var parts: PackedStringArray = str(slot_ref).split(":")
		if parts.size() != 2:
			return {}
		var container := parts[0]
		var key: Variant = parts[1]
		if container == "inventory" or container == "hotbar":
			key = int(parts[1])
		return {"container": container, "key": key}
	if slot_ref != null and slot_ref.has_method("get"):
		if slot_ref.has_variable("slotType") and slot_ref.has_variable("slot_index"):
			var slot_type: int = int(slot_ref.slotType)
			if slot_type == 0:
				return {"container": "hotbar", "key": int(slot_ref.slot_index)}
			if slot_type == 1:
				return {"container": "inventory", "key": int(slot_ref.slot_index)}
			if slot_type == 2:
				return {"container": "equips", "key": "shirt"}
			if slot_type == 3:
				return {"container": "equips", "key": "pants"}
			if slot_type == 4:
				return {"container": "equips", "key": "shoes"}
	return {}

func _get_container_value(ref: Dictionary):
	var container: String = str(ref.get("container", ""))
	var key: Variant = ref.get("key", null)
	if container == "inventory":
		return inventory.get(int(key), null)
	if container == "hotbar":
		return hotbar.get(int(key), null)
	if container == "equips":
		return equips.get(str(key), null)
	return null

func _set_container_value(ref: Dictionary, value) -> void:
	var container: String = str(ref.get("container", ""))
	var key: Variant = ref.get("key", null)
	if container == "inventory":
		inventory[int(key)] = value
	elif container == "hotbar":
		hotbar[int(key)] = value
	elif container == "equips":
		equips[str(key)] = value

func _sync_legacy_views() -> void:
	inventory_slots.clear()
	for i: int in range(NUM_INVENTORY_SLOTS):
		var value = inventory.get(i, null)
		if value == null:
			continue
		inventory_slots[i] = [_item_name(value), _item_quantity(value)]

	hotbar_slots.clear()
	for i: int in range(NUM_HOTBAR_SLOTS):
		var value = hotbar.get(i, null)
		if value == null:
			continue
		hotbar_slots[i] = [_item_name(value), _item_quantity(value)]

	equipment_slots.clear()
	if equips.get("shirt", null) != null:
		equipment_slots[0] = [_item_name(equips["shirt"]), _item_quantity(equips["shirt"])]
	if equips.get("pants", null) != null:
		equipment_slots[1] = [_item_name(equips["pants"]), _item_quantity(equips["pants"])]
	if equips.get("shoes", null) != null:
		equipment_slots[2] = [_item_name(equips["shoes"]), _item_quantity(equips["shoes"])]

func _emit_inventory_updated() -> void:
	inventory_updated.emit()
	inventory_changed.emit()

func _emit_hotbar_updated() -> void:
	hotbar_updated.emit()
	hotbar_changed.emit()

func _emit_equipment_updated() -> void:
	equipment_updated.emit()
	equipment_changed.emit()

func _emit_for_container(container: String) -> void:
	if container == "inventory":
		_emit_inventory_updated()
	elif container == "hotbar":
		_emit_hotbar_updated()
	elif container == "equips":
		_emit_equipment_updated()
