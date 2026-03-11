extends Button

signal item_selected(item_id: String)
signal item_dropped(item_id: String)

var _item_id: String = ""
var _item_name: String = ""
var _quantity: int = 0

func set_item_data(data: Dictionary) -> void:
	_item_id = str(data.get("id", ""))
	_item_name = str(data.get("name", ""))
	_quantity = int(data.get("quantity", 0))
	text = "%s x%d" % [_item_name, _quantity]
	disabled = _quantity <= 0

func _pressed() -> void:
	if _item_id.is_empty() == false:
		item_selected.emit(_item_id)

func _get_drag_data(_at_position: Vector2) -> Variant:
	if _item_id.is_empty() or _quantity <= 0:
		return null
	var preview := Label.new()
	preview.text = _item_name
	set_drag_preview(preview)
	return {
		"type": "inventory_item",
		"item_id": _item_id,
		"item_name": _item_name,
	}

func _can_drop_data(_at_position: Vector2, _data: Variant) -> bool:
	return false

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if data is Dictionary == false:
		return
	var payload := data as Dictionary
	if payload.get("type", "") != "inventory_item":
		return
	var item_id: String = str(payload.get("item_id", ""))
	if item_id.is_empty():
		return
	item_dropped.emit(item_id)
