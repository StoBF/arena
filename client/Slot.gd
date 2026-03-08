extends Panel

signal slot_item_changed(slot_index: int, slot_type: int)
signal item_picked(slot: Slot, picked_item)
signal item_dropped(slot: Slot, dropped_item)
signal item_swapped(from_slot: Slot, to_slot: Slot)

var default_tex = preload("res://item_slot_default_background.png")
var empty_tex = preload("res://item_slot_empty_background.png")
var selected_tex = preload("res://images/item_slot_selected_background.png")

var default_style: StyleBoxTexture
var empty_style: StyleBoxTexture
var selected_style: StyleBoxTexture

var ItemClass = preload("res://Item.tscn")
var item = null
var slot_index: int = -1

enum SlotType {
	HOTBAR = 0,
	INVENTORY,
	SHIRT,
	PANTS,
	SHOES,
}

var slotType: int = SlotType.INVENTORY
var _normal_modulate: Color = Color(1, 1, 1, 1)
var _valid_drop_modulate: Color = Color(0.82, 1.0, 0.82, 1)
var _invalid_drop_modulate: Color = Color(1.0, 0.78, 0.78, 1)

func _ready() -> void:
	default_style = StyleBoxTexture.new()
	empty_style = StyleBoxTexture.new()
	selected_style = StyleBoxTexture.new()
	default_style.texture = default_tex
	empty_style.texture = empty_tex
	selected_style.texture = selected_tex
	modulate = _normal_modulate
	refresh_style()

func refresh_style() -> void:
	if slotType == SlotType.HOTBAR and PlayerInventory.active_item_slot == slot_index:
		set("theme_override_styles/panel", selected_style)
	elif item == null:
		set("theme_override_styles/panel", empty_style)
	else:
		set("theme_override_styles/panel", default_style)

func is_empty() -> bool:
	return item == null

func pickFromSlot():
	if item == null:
		return null
	var picked = item
	remove_child(picked)
	item = null
	refresh_style()
	item_picked.emit(self, picked)
	slot_item_changed.emit(slot_index, slotType)
	return picked

func putIntoSlot(new_item) -> void:
	if new_item == null:
		return
	item = new_item
	item.position = Vector2.ZERO
	if item.get_parent() != null:
		item.get_parent().remove_child(item)
	add_child(item)
	refresh_style()
	item_dropped.emit(self, item)
	slot_item_changed.emit(slot_index, slotType)

func initialize_item(item_name: String, item_quantity: int) -> void:
	if item == null:
		item = ItemClass.instantiate()
		add_child(item)
	item.set_item(item_name, item_quantity)
	refresh_style()
	item_dropped.emit(self, item)
	slot_item_changed.emit(slot_index, slotType)

func notify_swapped(other_slot: Slot) -> void:
	item_swapped.emit(self, other_slot)

func show_drag_feedback(is_valid: bool) -> void:
	modulate = _valid_drop_modulate if is_valid else _invalid_drop_modulate

func clear_drag_feedback() -> void:
	modulate = _normal_modulate
