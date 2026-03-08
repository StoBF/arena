extends Button

signal item_selected(item_id: String)

var _item_id: String = ""

func set_item_data(data: Dictionary) -> void:
	_item_id = str(data.get("id", ""))
	var name := str(data.get("name", ""))
	var quantity: int = int(data.get("quantity", 0))
	text = "%s x%d" % [name, quantity]
	disabled = quantity <= 0

func _pressed() -> void:
	if _item_id.is_empty() == false:
		item_selected.emit(_item_id)
