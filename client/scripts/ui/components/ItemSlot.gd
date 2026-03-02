extends Button
class_name ItemSlot

signal slot_pressed(item_data: Dictionary)

enum ContextAction {
	INSPECT = 0,
	EQUIP = 1,
	SELL = 2,
	DISMANTLE = 3,
	LOCK_TOGGLE = 4,
}

var item_data: Dictionary = {}

@onready var name_label: Label = $VBox/NameLabel
@onready var type_label: Label = $VBox/TypeLabel
@onready var rarity_label: Label = $VBox/RarityLabel
@onready var power_label: Label = $VBox/PowerLabel
@onready var context_menu: PopupMenu = $ContextMenu
@onready var dismantle_confirm: ConfirmationDialog = $DismantleConfirm
@onready var item_details_modal: ItemDetailsModal = $ItemDetailsModal

func _ready() -> void:
	pressed.connect(_on_pressed)
	mouse_filter = Control.MOUSE_FILTER_STOP
	context_menu.id_pressed.connect(_on_context_menu_id_pressed)
	dismantle_confirm.confirmed.connect(_on_dismantle_confirmed)

func set_item(data: Dictionary) -> void:
	item_data = data.duplicate(true)
	if not is_inside_tree():
		return
	_apply_item()

func _enter_tree() -> void:
	if not item_data.is_empty():
		call_deferred("_apply_item")

func _apply_item() -> void:
	name_label.text = str(item_data.get("name", "Unnamed Item"))
	type_label.text = "Type: %s" % str(item_data.get("type", "Unknown"))
	rarity_label.text = "Rarity: %s" % str(item_data.get("rarity", "Common"))
	power_label.text = "Power: %d" % _item_power(item_data)

func _on_pressed() -> void:
	slot_pressed.emit(item_data.duplicate(true))

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_open_context_menu()
		accept_event()

func _get_drag_data(_at_position: Vector2) -> Variant:
	if item_data.is_empty():
		return null
	var item_id := int(item_data.get("id", -1))
	if item_id <= 0:
		return null

	var preview := PanelContainer.new()
	preview.custom_minimum_size = Vector2(140, 56)
	var label := Label.new()
	label.text = str(item_data.get("name", "Item"))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	preview.add_child(label)
	set_drag_preview(preview)

	return {
		"type": "item",
		"item_id": item_id
	}

func _item_power(item: Dictionary) -> int:
	if item.has("power"):
		return int(item.get("power", 0))
	return int(item.get("attack", 0)) + int(item.get("defense", 0)) + int(item.get("stability", 0)) + int(item.get("energy", 0)) + int(item.get("durability", 0))

func _open_context_menu() -> void:
	if item_data.is_empty():
		return
	context_menu.clear()
	context_menu.add_item("Inspect", ContextAction.INSPECT)
	context_menu.add_item("Equip", ContextAction.EQUIP)
	context_menu.add_item("Sell on Auction", ContextAction.SELL)
	context_menu.add_item("Dismantle", ContextAction.DISMANTLE)
	context_menu.add_item(_lock_menu_label(), ContextAction.LOCK_TOGGLE)

	var equip_idx := context_menu.get_item_index(ContextAction.EQUIP)
	context_menu.set_item_disabled(equip_idx, HeroManager.get_active_hero_id() <= 0)

	context_menu.position = Vector2i(get_global_mouse_position())
	context_menu.popup()

func _on_context_menu_id_pressed(id: int) -> void:
	match id:
		ContextAction.INSPECT:
			_inspect_item()
		ContextAction.EQUIP:
			_equip_item()
		ContextAction.SELL:
			_sell_item()
		ContextAction.DISMANTLE:
			_request_dismantle_confirmation()
		ContextAction.LOCK_TOGGLE:
			_toggle_lock_state()

func _inspect_item() -> void:
	if item_data.is_empty():
		return
	item_details_modal.open_for_item(item_data)

func _equip_item() -> void:
	var item_id := int(item_data.get("id", -1))
	if item_id <= 0:
		return
	var equipped := await InventoryManager.equip_item_for_active_hero(item_id)
	if not equipped:
		UIUtils.show_error("Failed to equip item")

func _sell_item() -> void:
	var item_id := int(item_data.get("id", -1))
	if item_id <= 0:
		return
	var sold := await InventoryManager.sell_item_on_auction(item_id)
	if sold:
		UIUtils.show_success("Item listed on auction")
	else:
		UIUtils.show_error("Failed to list item on auction")

func _request_dismantle_confirmation() -> void:
	dismantle_confirm.popup_centered()

func _on_dismantle_confirmed() -> void:
	var item_id := int(item_data.get("id", -1))
	if item_id <= 0:
		return
	var dismantled := await InventoryManager.dismantle_item(item_id)
	if dismantled:
		UIUtils.show_success("Item dismantled")
	else:
		UIUtils.show_error("Failed to dismantle item")

func _toggle_lock_state() -> void:
	var item_id := int(item_data.get("id", -1))
	if item_id <= 0:
		return
	var success := await InventoryManager.toggle_item_lock(item_id)
	if not success:
		UIUtils.show_error("Failed to update lock state")
		return
	var refreshed := InventoryManager.get_item_by_id(item_id)
	if not refreshed.is_empty():
		item_data = refreshed
		_apply_item()

func _lock_menu_label() -> String:
	if bool(item_data.get("is_locked", false)):
		return "Unlock"
	return "Lock"
