extends Control
class_name HeroEquipmentPanel

# UI Elements
@onready var equipment_grid = $EquipmentGrid
@onready var inventory_grid = $InventoryGrid
@onready var hero_panel = $HeroPanel
@onready var hero_stats = $HeroPanel/HeroStats
@onready var generate_hero_button = $HeroPanel/GenerateHeroButton

# Properties
var slot_nodes: Dictionary = {}  # Maps slot names to nodes

func _ready():
	# Initialize slot nodes
	slot_nodes = {
		"head": $EquipmentGrid/Slot_Head,
		"chest": $EquipmentGrid/Slot_Chest,
		"weapon": $EquipmentGrid/Slot_Weapon,
		"offhand": $EquipmentGrid/Slot_Offhand
	}
	
	# Setup drag and drop
	_setup_drag_and_drop()
	
	# Connect signals
	generate_hero_button.pressed.connect(Callable(self, "_on_generate_hero_pressed"))
	
	# Load data
	_load_data()

func _setup_drag_and_drop():
	# Enable drag and drop on slots
	for slot_name in slot_nodes:
		var slot = slot_nodes[slot_name]
		slot.slot_name = slot_name
		slot.gui_input.connect(Callable(self, "_on_slot_gui_input").bind(slot_name))
		slot.drop_data.connect(Callable(self, "_on_slot_drop").bind(slot_name))
	
	# Enable drag and drop on inventory grid
	inventory_grid.drop_data.connect(Callable(self, "_on_inventory_drop"))

func _load_data():
	var hero_id = AppState.current_hero_id
	if hero_id == -1:
		UIUtils.show_error(Localization.t("no_hero_selected"))
		return
		
	# Load hero stats
	var hero_req = Network.get_hero(hero_id)
	hero_req.request_completed.connect(Callable(self, "_on_hero_loaded"))
	
	# Load inventory and equipment
	var inv_req = Network.get_inventory(hero_id)
	inv_req.request_completed.connect(Callable(self, "_on_inventory_loaded"))
	
	var eq_req = Network.get_equipment(hero_id)
	eq_req.request_completed.connect(Callable(self, "_on_equipment_loaded"))

func _on_hero_loaded(result: int, code: int, headers, body: PackedByteArray):
	if code == 200:
		var parsed = JSON.parse_string(body.get_string_from_utf8())
		if parsed.error == OK:
			var hero = parsed.result
			hero_stats.text = "STR: %d  AGI: %d  INT: %d" % [hero.strength, hero.agility, hero.intelligence]
			return
	UIUtils.show_error(Localization.t("load_hero_failed"))

func _on_inventory_loaded(result: int, code: int, headers, body: PackedByteArray):
	if code == 200:
		var parsed = JSON.parse_string(body.get_string_from_utf8())
		if parsed.error == OK:
			_populate_inventory(parsed.result)
			return
	UIUtils.show_error(Localization.t("load_inventory_failed"))

func _on_equipment_loaded(result: int, code: int, headers, body: PackedByteArray):
	if code == 200:
		var parsed = JSON.parse_string(body.get_string_from_utf8())
		if parsed.error == OK:
			_populate_equipment(parsed.result)
			return
	UIUtils.show_error(Localization.t("load_equipment_failed"))

func _populate_inventory(items: Array):
	inventory_grid.clear()
	for item in items:
		var icon = preload("res://scenes/InventoryItemIcon.tscn").instantiate()
		icon.item_id = item.id
		icon.item_name = item.name
		icon.slot_type = item.slot_type
		icon.texture = load(item.icon_path)
		inventory_grid.add_child(icon)

func _populate_equipment(equipment: Array):
	for eq in equipment:
		var slot = slot_nodes[eq.slot]
		slot.texture = load(eq.icon_path)
		slot.equipped_item_id = eq.item_id
		slot.visible = true

func _on_slot_gui_input(event: InputEvent, slot_name: String):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var slot = slot_nodes[slot_name]
		if slot.has_meta("equipped_item_id") or slot.equipped_item_id:
			var drag_data = {
				"item_id": slot.equipped_item_id,
				"slot_type": slot_name,
				"origin_slot": slot_name
			}
			var preview = Sprite2D.new()
			preview.texture = slot.texture
			slot.set_drag_preview(preview)
			slot.start_drag(drag_data)

func _on_slot_drop(position: Vector2, data: Dictionary, slot_name: String):
	if data.has("slot_type") and data.slot_type == slot_name:
		var req = Network.equip_item(AppState.current_hero_id, data.item_id, slot_name)
		req.request_completed.connect(Callable(self, "_on_equip_response"))

func _on_inventory_drop(position: Vector2, data: Dictionary):
	if data.has("slot_type") and data.has("item_id"):
		var req = Network.unequip_item(AppState.current_hero_id, data.origin_slot)
		req.request_completed.connect(Callable(self, "_on_unequip_response"))

func _on_equip_response(result: int, code: int, headers, body: PackedByteArray):
	if code == 200:
		UIUtils.show_success(Localization.t("equip_success"))
		_load_data()  # Refresh equipment and inventory
	else:
		UIUtils.show_error(Localization.t("equip_failed"))

func _on_unequip_response(result: int, code: int, headers, body: PackedByteArray):
	if code == 200:
		UIUtils.show_success(Localization.t("unequip_success"))
		_load_data()  # Refresh equipment and inventory
	else:
		UIUtils.show_error(Localization.t("unequip_failed"))

func _on_generate_hero_pressed():
	var dialog = preload("res://scenes/GenerateDialog.tscn").instantiate()
	add_child(dialog)
	dialog.generate_requested.connect(Callable(self, "_on_generate_hero_response"))
	dialog.popup_centered()

func _on_generate_hero_response(generation: int, currency: int):
	var data = {
		"generation": generation,
		"currency": currency
	}
	var req = Network.request("/heroes/generate", HTTPClient.METHOD_POST, data)
	req.request_completed.connect(Callable(self, "_on_generate_hero_completed"))

func _on_generate_hero_completed(result: int, code: int, headers, body: PackedByteArray):
	if code == 200:
		var parsed = JSON.parse_string(body.get_string_from_utf8())
		if parsed.error == OK:
			var hero = parsed.result
			AppState.current_hero_id = hero.id
			_load_data()
			return
	UIUtils.show_error(Localization.t("generate_hero_failed")) 
