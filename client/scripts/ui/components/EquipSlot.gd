extends Button

signal equip_slot_selected(slot_name: String)
signal item_dropped_to_slot(item_id: String, slot_name: String)

@export var slot_name: String = "shirt"

func set_equipped_item(data: Dictionary) -> void:
	if data.is_empty():
		text = "%s: Empty" % slot_name.capitalize()
	else:
		text = "%s: %s" % [slot_name.capitalize(), str(data.get("name", "Item"))]

func _pressed() -> void:
	equip_slot_selected.emit(slot_name)

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if data is Dictionary == false:
		return false
	var payload := data as Dictionary
	return str(payload.get("type", "")) == "inventory_item" and str(payload.get("item_id", "")).is_empty() == false

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if _can_drop_data(_at_position, data) == false:
		return
	var payload := data as Dictionary
	item_dropped_to_slot.emit(str(payload.get("item_id", "")), slot_name)
