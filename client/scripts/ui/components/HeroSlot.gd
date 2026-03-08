extends Button

signal hero_slot_selected(index: int)

@export var slot_index: int = -1

func set_hero_data(data: Dictionary, selected: bool) -> void:
	if data.is_empty():
		text = "Empty"
		disabled = true
	else:
		text = str(data.get("name", "Hero"))
		disabled = false
	modulate = Color(0.8, 1.0, 0.8, 1.0) if selected else Color(1, 1, 1, 1)

func _pressed() -> void:
	hero_slot_selected.emit(slot_index)
