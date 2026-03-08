extends PanelContainer

@onready var label: Label = $Margin/Label

func set_item(item: Dictionary) -> void:
	if item.is_empty():
		label.text = ""
		visible = false
		return
	label.text = "%s\nQty: %d\nCategory: %s" % [
		str(item.get("name", "")),
		int(item.get("quantity", 0)),
		str(item.get("category", ""))
	]
	visible = true
