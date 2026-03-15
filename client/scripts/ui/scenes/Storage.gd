extends Control

const ITEM_SLOT_SCENE := preload("res://scenes/ui/components/ItemSlot.tscn")

@onready var items_grid: GridContainer = $VBox/InventoryPanel/InventoryMargin/InventoryVBox/ItemsScroll/ItemsGrid
@onready var hero_preview_label: Label = $VBox/Body/HeroPreviewPanel/HeroPreviewMargin/HeroPreviewVBox/HeroPreviewBody/HeroPreviewBodyMargin/HeroPreviewLabel
@onready var selected_hero_label: Label = $VBox/Header/SelectedHeroLabel
@onready var equip_helmet = $VBox/Body/LeftSlotsPanel/LeftMargin/LeftSlots/HelmetSlot
@onready var equip_armor = $VBox/Body/LeftSlotsPanel/LeftMargin/LeftSlots/ArmorSlot
@onready var equip_gloves = $VBox/Body/LeftSlotsPanel/LeftMargin/LeftSlots/GlovesSlot
@onready var equip_weapon = $VBox/Body/LeftSlotsPanel/LeftMargin/LeftSlots/WeaponSlot
@onready var equip_artifact = $VBox/Body/RightSlotsPanel/RightMargin/RightSlots/ArtifactSlot
@onready var equip_ring = $VBox/Body/RightSlotsPanel/RightMargin/RightSlots/RingSlot
@onready var equip_belt = $VBox/Body/RightSlotsPanel/RightMargin/RightSlots/BeltSlot
@onready var equip_boots = $VBox/Body/RightSlotsPanel/RightMargin/RightSlots/BootsSlot
@onready var delete_hero_button: Button = $VBox/Footer/DeleteHeroButton

var _player_data: Node = null
var _inventory_controller: Node = null
var _craft_controller: Node = null
var _selected_item_id: String = ""
var _selected_hero_id: int = -1

func _ready() -> void:
	$VBox/Header/BackButton.pressed.connect(func(): EventBus.emit_scene_changed("PlayerHub"))
	delete_hero_button.pressed.connect(_on_delete_hero)
	_connect_slot_signals(equip_helmet)
	_connect_slot_signals(equip_armor)
	_connect_slot_signals(equip_gloves)
	_connect_slot_signals(equip_weapon)
	_connect_slot_signals(equip_artifact)
	_connect_slot_signals(equip_ring)
	_connect_slot_signals(equip_belt)
	_connect_slot_signals(equip_boots)
	if LocalizationManager.locale_changed.is_connected(_on_locale_changed) == false:
		LocalizationManager.locale_changed.connect(_on_locale_changed)
	if has_node("/root/EventBus") and EventBus.inventory_updated.is_connected(_on_eventbus_inventory_updated) == false:
		EventBus.inventory_updated.connect(_on_eventbus_inventory_updated)
	_apply_translations()

func bind_controllers(player_data: Node, inventory_controller: Node, craft_controller: Node) -> void:
	_player_data = player_data
	_inventory_controller = inventory_controller
	_craft_controller = craft_controller

	_connect_if_needed(_inventory_controller.equipment_changed, _refresh_equipment)
	_connect_if_needed(HeroManager.active_hero_changed, _on_active_hero_changed)

	_refresh_items(AppState.inventory)
	_refresh_equipment(_inventory_controller.get_selected_hero_equipment())
	_on_active_hero_changed(HeroManager.get_active_hero_id())
	call_deferred("_refresh_from_server")

func _connect_if_needed(signal_ref: Signal, callback: Callable) -> void:
	if signal_ref.is_connected(callback) == false:
		signal_ref.connect(callback)

func _refresh_items(items: Array) -> void:
	_clear_children(items_grid)
	for item_variant in items:
		var item := item_variant as Dictionary
		var slot = ITEM_SLOT_SCENE.instantiate()
		slot.set_item_data(item)
		slot.item_selected.connect(_on_item_selected)
		if slot.has_signal("item_dropped"):
			slot.item_dropped.connect(_on_item_selected)
		items_grid.add_child(slot)

func _refresh_equipment(equipment: Dictionary) -> void:
	equip_helmet.set_equipped_item(_equipment_for_slot(equipment, ["helmet", "Helmet"]))
	equip_armor.set_equipped_item(_equipment_for_slot(equipment, ["armor", "Armor"]))
	equip_gloves.set_equipped_item(_equipment_for_slot(equipment, ["gloves", "Gloves"]))
	equip_weapon.set_equipped_item(_equipment_for_slot(equipment, ["weapon", "Weapon"]))
	equip_artifact.set_equipped_item(_equipment_for_slot(equipment, ["artifact", "Artifact", "amulet", "Amulet"]))
	equip_ring.set_equipped_item(_equipment_for_slot(equipment, ["ring", "Ring"]))
	equip_belt.set_equipped_item(_equipment_for_slot(equipment, ["belt", "Belt"]))
	equip_boots.set_equipped_item(_equipment_for_slot(equipment, ["boots", "Boots"]))

func _on_item_selected(item_id: String) -> void:
	_selected_item_id = item_id

func _on_equip_slot_selected(slot_name: String) -> void:
	if _selected_item_id.is_empty():
		return
	var equipped: bool = await _inventory_controller.equip_item_to_selected_hero(_selected_item_id, slot_name)
	if equipped == false:
		return
	_refresh_equipment(_inventory_controller.get_selected_hero_equipment())

func _on_delete_hero() -> void:
	delete_hero_button.disabled = true

func _clear_children(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()

func _on_locale_changed(_locale_code: String) -> void:
	_apply_translations()

func _apply_translations() -> void:
	$VBox/Header/BackButton.text = tr("ui.common.back")
	$VBox/Header/Title.text = tr("ui.storage.title")
	$VBox/Body/HeroPreviewPanel/HeroPreviewMargin/HeroPreviewVBox/HeroPreviewTitle.text = tr("ui.storage.hero_preview")
	$VBox/InventoryPanel/InventoryMargin/InventoryVBox/InventoryTitle.text = tr("ui.storage.items")
	delete_hero_button.text = tr("ui.storage.delete_hero")
	selected_hero_label.text = tr("ui.storage.selected_hero") % _selected_hero_name()
	if _selected_hero_id <= 0:
		hero_preview_label.text = tr("ui.storage.no_hero_selected")

func _refresh_from_server() -> void:
	await HeroManager.load_heroes()
	_on_active_hero_changed(HeroManager.get_active_hero_id())
	if _inventory_controller != null and _inventory_controller.has_method("refresh_items_from_server"):
		await _inventory_controller.refresh_items_from_server()

func _on_active_hero_changed(hero_id: int) -> void:
	_selected_hero_id = hero_id
	delete_hero_button.disabled = hero_id <= 0
	selected_hero_label.text = tr("ui.storage.selected_hero") % _selected_hero_name()
	hero_preview_label.text = _hero_preview_text()
	if _inventory_controller != null and _inventory_controller.has_method("refresh_items_from_server"):
		call_deferred("_refresh_inventory_after_hero_change")

func _refresh_inventory_after_hero_change() -> void:
	await _inventory_controller.refresh_items_from_server()

func _on_eventbus_inventory_updated() -> void:
	_refresh_items(AppState.inventory)

func _connect_slot_signals(slot: Node) -> void:
	if slot == null:
		return
	if slot.has_signal("equip_slot_selected") and slot.equip_slot_selected.is_connected(_on_equip_slot_selected) == false:
		slot.equip_slot_selected.connect(_on_equip_slot_selected)
	if slot.has_signal("item_dropped_to_slot") and slot.item_dropped_to_slot.is_connected(_on_item_dropped_to_slot) == false:
		slot.item_dropped_to_slot.connect(_on_item_dropped_to_slot)

func _on_item_dropped_to_slot(item_id: String, slot_name: String) -> void:
	_selected_item_id = item_id
	await _on_equip_slot_selected(slot_name)

func _equipment_for_slot(equipment: Dictionary, keys: Array[String]) -> Dictionary:
	for key in keys:
		if equipment.has(key) and equipment[key] is Dictionary:
			return (equipment[key] as Dictionary).duplicate(true)
	return {}

func _selected_hero_name() -> String:
	for hero_variant in AppState.heroes:
		if hero_variant is Dictionary == false:
			continue
		var hero := hero_variant as Dictionary
		if int(hero.get("id", -1)) == _selected_hero_id:
			return str(hero.get("name", "-"))
	return "-"

func _hero_preview_text() -> String:
	for hero_variant in AppState.heroes:
		if hero_variant is Dictionary == false:
			continue
		var hero := hero_variant as Dictionary
		if int(hero.get("id", -1)) != _selected_hero_id:
			continue
		return "%s\nGen %s | Lv %s\nW:%s L:%s" % [
			str(hero.get("name", "-")),
			str(hero.get("generation", hero.get("gen", "-"))),
			str(hero.get("level", "-")),
			str(hero.get("wins", hero.get("victories", "-"))),
			str(hero.get("losses", hero.get("defeats", "-"))),
		]
	return tr("ui.storage.no_hero_selected")
