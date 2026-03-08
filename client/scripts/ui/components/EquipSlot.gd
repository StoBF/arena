extends Button

signal equip_slot_selected(slot_name: String)

@export var slot_name: String = "shirt"

func set_equipped_item(data: Dictionary) -> void:
	if data.is_empty():
		text = "%s: Empty" % slot_name.capitalize()
	else:
		text = "%s: %s" % [slot_name.capitalize(), str(data.get("name", "Item"))]

func _pressed() -> void:
	equip_slot_selected.emit(slot_name)
