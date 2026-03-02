extends Button
class_name EquipmentSlot

signal stat_preview_requested(slot_type: String, item_id: int, global_pos: Vector2)
signal stat_preview_cleared

@export var slot_type: String = ""

var _is_request_pending: bool = false
var _hover_item_id: int = -1

func _ready() -> void:
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	set_drag_forwarding(_get_drag_data_fw, _can_drop_data_fw, _drop_data_fw)

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if _is_request_pending:
		_clear_hover_feedback()
		return false
	if typeof(data) != TYPE_DICTIONARY:
		_clear_hover_feedback()
		return false

	var payload: Dictionary = data
	if payload.get("type", "") != "item":
		_clear_hover_feedback()
		return false

	var item_id := int(payload.get("item_id", -1))
	if item_id <= 0:
		_clear_hover_feedback()
		return false

	var can_drop := InventoryManager.is_item_valid_for_slot(item_id, slot_type)
	if can_drop:
		modulate = Color(0.85, 1.0, 0.85, 1.0)
		if _hover_item_id != item_id:
			_hover_item_id = item_id
			stat_preview_requested.emit(slot_type, item_id, get_global_mouse_position())
	else:
		_clear_hover_feedback()
	return can_drop

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if _is_request_pending:
		return
	if typeof(data) != TYPE_DICTIONARY:
		return
	var payload: Dictionary = data
	if payload.get("type", "") != "item":
		return

	var item_id := int(payload.get("item_id", -1))
	if item_id <= 0:
		return

	if not InventoryManager.is_item_valid_for_slot(item_id, slot_type):
		_clear_hover_feedback()
		return

	var hero_id := HeroManager.get_active_hero_id()
	if hero_id <= 0:
		_clear_hover_feedback()
		return

	_is_request_pending = true
	disabled = true

	var rollback := InventoryManager.apply_optimistic_equip(hero_id, item_id, slot_type)
	_clear_hover_feedback()

	var success: bool = await InventoryManager.equip_item(hero_id, item_id, slot_type)
	if not success:
		InventoryManager.rollback_optimistic_equip(hero_id, slot_type, rollback)
		UIUtils.show_error("Failed to equip item")

	_is_request_pending = false
	disabled = false

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_clear_hover_feedback()

func _on_mouse_entered() -> void:
	if _hover_item_id > 0:
		stat_preview_requested.emit(slot_type, _hover_item_id, get_global_mouse_position())

func _on_mouse_exited() -> void:
	stat_preview_cleared.emit()

func _clear_hover_feedback() -> void:
	_hover_item_id = -1
	modulate = Color(1, 1, 1, 1)
	stat_preview_cleared.emit()

func _get_drag_data_fw(_position: Vector2) -> Variant:
	return null

func _can_drop_data_fw(position: Vector2, data: Variant) -> bool:
	return _can_drop_data(position, data)

func _drop_data_fw(position: Vector2, data: Variant) -> void:
	_drop_data(position, data)
