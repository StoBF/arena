extends Button

signal item_selected(item_id: String)
signal item_dropped(item_id: String)

var _item_id: String = ""
var _item_name: String = ""
var _quantity: int = 0

@onready var icon_rect: TextureRect = $Content/Icon
@onready var name_label: Label = $Content/NameLabel
@onready var quantity_label: Label = $Content/QuantityLabel

const RARITY_COLORS := {
	"common": Color("#7e8590"),
	"rare": Color("#3f7ed8"),
	"epic": Color("#8a4fd4"),
	"legendary": Color("#f3b545"),
}

func set_item_data(data: Dictionary) -> void:
	_item_id = str(data.get("id", ""))
	_item_name = str(data.get("name", ""))
	_quantity = int(data.get("quantity", 0))
	name_label.text = _item_name
	quantity_label.text = "x%d" % _quantity
	disabled = _quantity <= 0

	var rarity: String = str(data.get("rarity", "common")).to_lower()
	_apply_rarity_style(rarity)

	var icon_path: String = str(data.get("icon", ""))
	if icon_path.is_empty() == false and ResourceLoader.exists(icon_path):
		icon_rect.texture = load(icon_path)
	else:
		icon_rect.texture = null

	var description: String = str(data.get("description", ""))
	tooltip_text = "%s\nRarity: %s\n%s" % [_item_name, rarity.capitalize(), description]

func _pressed() -> void:
	if _item_id.is_empty() == false:
		item_selected.emit(_item_id)

func _apply_rarity_style(rarity: String) -> void:
	var color: Color = RARITY_COLORS.get(rarity, RARITY_COLORS["common"])
	var stylebox := StyleBoxFlat.new()
	stylebox.bg_color = Color(0.12, 0.13, 0.15, 0.82)
	stylebox.border_color = color
	stylebox.set_border_width_all(2)
	stylebox.corner_radius_top_left = 8
	stylebox.corner_radius_top_right = 8
	stylebox.corner_radius_bottom_left = 8
	stylebox.corner_radius_bottom_right = 8
	add_theme_stylebox_override("normal", stylebox)
	add_theme_stylebox_override("hover", stylebox)
	add_theme_stylebox_override("pressed", stylebox)

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
