extends Window
class_name ItemDetailsModal

@onready var icon_rect: TextureRect = $Root/Margin/Content/Icon
@onready var name_label: Label = $Root/Margin/Content/Info/NameLabel
@onready var rarity_label: Label = $Root/Margin/Content/Info/RarityLabel
@onready var stats_label: Label = $Root/Margin/Content/Info/StatsLabel
@onready var description_label: Label = $Root/Margin/Content/Info/DescriptionLabel
@onready var sell_button: Button = $Root/Margin/Actions/SellButton
@onready var close_button: Button = $Root/Margin/Actions/CloseButton

var _item_id: int = -1
var _item_data: Dictionary = {}

func _ready() -> void:
	sell_button.pressed.connect(_on_sell_pressed)
	close_button.pressed.connect(_on_close_pressed)
	close_requested.connect(_on_close_pressed)

func open_for_item(item_data: Dictionary) -> void:
	_item_data = item_data.duplicate(true)
	_item_id = int(_item_data.get("id", -1))
	var details := await InventoryManager.inspect_item(_item_id)
	if details.is_empty():
		details = _item_data
	_apply_details(details)
	popup_centered_ratio(0.42)

func _apply_details(details: Dictionary) -> void:
	var rarity := str(details.get("rarity", "Common"))
	name_label.text = str(details.get("name", "Unknown Item"))
	rarity_label.text = "Rarity: %s" % rarity
	rarity_label.modulate = _rarity_color(rarity)
	stats_label.text = _build_stats_text(details)
	description_label.text = str(details.get("description", "No description."))

	var icon_path := str(details.get("icon_path", "")).strip_edges()
	if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
		icon_rect.texture = load(icon_path)
	else:
		icon_rect.texture = null

func _on_sell_pressed() -> void:
	if _item_id <= 0:
		return
	var listed := await InventoryManager.sell_item_on_auction(_item_id)
	if listed:
		UIUtils.show_success("Item listed on auction")
		hide()
	else:
		UIUtils.show_error("Failed to list item on auction")

func _on_close_pressed() -> void:
	hide()

func _build_stats_text(details: Dictionary) -> String:
	var lines: Array[String] = []
	lines.append("Type: %s" % str(details.get("type", "Unknown")))
	lines.append("Power: %d" % _stat_value(details, ["power", "attack", "defense", "stability", "energy", "durability"]))
	lines.append("Strength Bonus: %d" % int(details.get("strength_bonus", 0)))
	lines.append("Agility Bonus: %d" % int(details.get("agility_bonus", 0)))
	lines.append("Health Bonus: %d" % int(details.get("health_bonus", 0)))
	if details.has("slot"):
		lines.append("Slot: %s" % str(details.get("slot", "")))
	if details.has("is_locked"):
		lines.append("Locked: %s" % ("Yes" if bool(details.get("is_locked", false)) else "No"))
	return "\n".join(lines)

func _stat_value(details: Dictionary, keys: Array) -> int:
	if details.has("power"):
		return int(details.get("power", 0))
	var total := 0
	for key in keys:
		total += int(details.get(str(key), 0))
	return total

func _rarity_color(rarity: String) -> Color:
	match rarity.to_lower():
		"common":
			return Color(0.85, 0.85, 0.85, 1.0)
		"rare":
			return Color(0.35, 0.65, 1.0, 1.0)
		"epic":
			return Color(0.75, 0.45, 1.0, 1.0)
		"legendary":
			return Color(1.0, 0.75, 0.25, 1.0)
		_:
			return Color(1, 1, 1, 1)
