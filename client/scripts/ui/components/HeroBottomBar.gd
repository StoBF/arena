extends PanelContainer

signal hero_slot_selected(slot_index: int)

const SLOT_COUNT := 5

var _slots: Array[Button] = []
var _selected_index: int = -1

func _ready() -> void:
	for i in range(SLOT_COUNT):
		var slot: Button = get_node_or_null("Margin/SlotsRow/Slot%d" % i)
		if slot != null:
			_slots.append(slot)
			slot.pressed.connect(_on_slot_pressed.bind(i))
			slot.expand_icon = true

func populate(heroes: Array) -> void:
	for i in range(_slots.size()):
		var slot: Button = _slots[i]
		if i < heroes.size() and heroes[i] is Dictionary:
			var hero: Dictionary = heroes[i]
			var name_str: String = str(hero.get("name", "Hero"))
			slot.text = name_str
			slot.disabled = false
			slot.tooltip_text = name_str
			var portrait_path: String = str(hero.get("portrait", ""))
			if not portrait_path.is_empty() and ResourceLoader.exists(portrait_path):
				slot.icon = load(portrait_path)
			else:
				slot.icon = null
		else:
			slot.text = "Empty"
			slot.icon = null
			slot.disabled = true
			slot.tooltip_text = ""
		_update_slot_style(i)

func set_selected(slot_index: int) -> void:
	_selected_index = slot_index
	for i in range(_slots.size()):
		_update_slot_style(i)

func _update_slot_style(index: int) -> void:
	if index >= _slots.size():
		return
	var slot: Button = _slots[index]
	if index == _selected_index:
		slot.modulate = Color(1.0, 0.95, 0.7, 1.0)
		slot.add_theme_stylebox_override("normal", _make_selected_stylebox())
	else:
		slot.modulate = Color(1, 1, 1, 1)
		slot.remove_theme_stylebox_override("normal")

func _make_selected_stylebox() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.85, 0.72, 0.35, 0.4)
	sb.border_color = Color(0.95, 0.85, 0.45, 1)
	sb.set_border_width_all(2)
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_left = 6
	sb.corner_radius_bottom_right = 6
	return sb

func _on_slot_pressed(slot_index: int) -> void:
	hero_slot_selected.emit(slot_index)
