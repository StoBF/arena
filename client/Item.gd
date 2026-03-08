extends Node2D

var item_name: String = ""
var item_quantity: int = 1

@onready var icon_rect: TextureRect = $TextureRect
@onready var quantity_label: Label = $Label

func set_item(nm: String, qt: int) -> void:
	item_name = nm
	item_quantity = maxi(1, qt)

	var data: Dictionary = JsonData.item_data.get(item_name, {})
	var stack_size: int = int(data.get("StackSize", 1))
	item_quantity = mini(item_quantity, stack_size)

	var icon_path: String = str(data.get("IconPath", "res://item_icons/%s.png" % item_name))
	if ResourceLoader.exists(icon_path):
		icon_rect.texture = load(icon_path)
	else:
		icon_rect.texture = null

	if stack_size <= 1:
		quantity_label.visible = false
	else:
		quantity_label.visible = true
		quantity_label.text = str(item_quantity)

func add_item_quantity(amount_to_add: int) -> void:
	if amount_to_add <= 0:
		return
	var stack_size: int = int(JsonData.item_data.get(item_name, {}).get("StackSize", 1))
	item_quantity = mini(item_quantity + amount_to_add, stack_size)
	if stack_size > 1:
		quantity_label.text = str(item_quantity)

func decrease_item_quantity(amount_to_remove: int) -> void:
	if amount_to_remove <= 0:
		return
	item_quantity = maxi(0, item_quantity - amount_to_remove)
	if item_quantity <= 0:
		queue_free()
		return

	var stack_size: int = int(JsonData.item_data.get(item_name, {}).get("StackSize", 1))
	if stack_size > 1:
		quantity_label.text = str(item_quantity)
