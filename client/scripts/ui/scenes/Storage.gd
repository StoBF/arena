extends Control

const ITEM_SLOT_SCENE := preload("res://scenes/ui/components/ItemSlot.tscn")
const _SLOT_KEYS: PackedStringArray = ["Helmet", "Armor", "Weapon", "Boots", "Ring", "Amulet"]

@onready var items_grid: GridContainer = $VBox/InventoryPanel/InventoryMargin/InventoryVBox/ItemsScroll/ItemsGrid
@onready var hero_preview_label: Label = $VBox/Body/HeroPreviewPanel/HeroPreviewMargin/HeroPreviewVBox/HeroPreviewBody/HeroPreviewBodyMargin/HeroPreviewLabel
@onready var selected_hero_label: Label = $VBox/Header/SelectedHeroLabel
@onready var equip_helmet: Node = $VBox/Body/LeftSlotsPanel/LeftMargin/LeftSlots/HelmetSlot
@onready var equip_armor: Node = $VBox/Body/LeftSlotsPanel/LeftMargin/LeftSlots/ArmorSlot
@onready var equip_gloves: Node = $VBox/Body/LeftSlotsPanel/LeftMargin/LeftSlots/GlovesSlot
@onready var equip_weapon: Node = $VBox/Body/LeftSlotsPanel/LeftMargin/LeftSlots/WeaponSlot
@onready var equip_artifact: Node = $VBox/Body/RightSlotsPanel/RightMargin/RightSlots/ArtifactSlot
@onready var equip_ring: Node = $VBox/Body/RightSlotsPanel/RightMargin/RightSlots/RingSlot
@onready var equip_belt: Node = $VBox/Body/RightSlotsPanel/RightMargin/RightSlots/BeltSlot
@onready var equip_boots: Node = $VBox/Body/RightSlotsPanel/RightMargin/RightSlots/BootsSlot
@onready var delete_hero_button: Button = $VBox/Footer/DeleteHeroButton

var _selected_item_id: String = ""
var _selected_hero_id: int = -1
var _is_refreshing: bool = false
var _is_equipping: bool = false

func _ready() -> void:
	if items_grid == null or delete_hero_button == null:
		push_warning("Storage scene nodes are not ready; skipping initialization")
		return
	$VBox/Header/BackButton.pressed.connect(func(): EventBus.navigate_to(EventBus.SCENE_PLAYER_HUB))
	delete_hero_button.pressed.connect(_on_delete_hero)
	_connect_slot_signals(equip_helmet)
	_connect_slot_signals(equip_armor)
	_connect_slot_signals(equip_gloves)
	_connect_slot_signals(equip_weapon)
	_connect_slot_signals(equip_artifact)
	_connect_slot_signals(equip_ring)
	_connect_slot_signals(equip_belt)
	_connect_slot_signals(equip_boots)
	_connect_inventory_signals()
	if LocalizationManager.locale_changed.is_connected(_on_locale_changed) == false:
		LocalizationManager.locale_changed.connect(_on_locale_changed)
	if HeroManager.active_hero_changed.is_connected(_on_active_hero_changed) == false:
		HeroManager.active_hero_changed.connect(_on_active_hero_changed)
	_apply_translations()
	_refresh_items(AppState.inventory)
	_refresh_equipment(_equipment_from_manager())
	_on_active_hero_changed(_resolve_active_hero_id())
	call_deferred("_apply_cabinet_visuals")
	call_deferred("_refresh_from_server")

func _apply_cabinet_visuals() -> void:
	CabinetStyle.style_screen(self)
	CabinetStyle.style_button(delete_hero_button)

func _refresh_items(items: Array) -> void:
	_clear_children(items_grid)
	_selected_item_id = ""
	for item_variant in items:
		if item_variant is Dictionary == false:
			continue
		var item := (item_variant as Dictionary).duplicate(true)
		var slot = ITEM_SLOT_SCENE.instantiate()
		slot.set_item_data(item)
		if slot.item_selected.is_connected(_on_item_selected) == false:
			slot.item_selected.connect(_on_item_selected)
		# H5: item_dropped (fired when data is dropped ON an inventory slot) must not
		# trigger equip — equip drag is handled by EquipSlot.item_dropped_to_slot.
		# The previous connection to _on_item_selected was both wrong handler and
		# wrong purpose. Remove it entirely.
		items_grid.add_child(slot)

func _refresh_equipment(equipment: Dictionary) -> void:
	_safe_set_equipped(equip_helmet, _equipment_for_backend_slot(equipment, "Helmet"))
	_safe_set_equipped(equip_armor, _equipment_for_backend_slot(equipment, "Armor"))
	# C1: gloves has no distinct backend slot — show empty to avoid mirroring Armor item
	_safe_set_equipped(equip_gloves, {})
	_safe_set_equipped(equip_weapon, _equipment_for_backend_slot(equipment, "Weapon"))
	_safe_set_equipped(equip_artifact, _equipment_for_backend_slot(equipment, "Amulet"))
	_safe_set_equipped(equip_ring, _equipment_for_backend_slot(equipment, "Ring"))
	# C1: belt has no distinct backend slot — show empty to avoid mirroring Ring item
	_safe_set_equipped(equip_belt, {})
	_safe_set_equipped(equip_boots, _equipment_for_backend_slot(equipment, "Boots"))

func _safe_set_equipped(slot_node: Node, item_data: Dictionary) -> void:
	if slot_node == null:
		return
	if slot_node.has_method("set_equipped_item"):
		slot_node.set_equipped_item(item_data)

func _on_item_selected(item_id: String) -> void:
	_selected_item_id = item_id

func _on_equip_slot_selected(slot_name: String) -> void:
	if _selected_item_id.is_empty() or _selected_hero_id <= 0 or _is_equipping:
		return
	var item_id: int = int(_selected_item_id)
	if item_id <= 0:
		UIUtils.show_warning("Invalid item selection")
		return
	var slot_type: String = InventoryManager.normalize_slot(slot_name)  # H4: canonical mapping
	if not _SLOT_KEYS.has(slot_type):
		UIUtils.show_warning("Unsupported equipment slot")
		return
	_is_equipping = true
	var equipped: bool = await InventoryManager.equip_item(_selected_hero_id, item_id, slot_type)
	_is_equipping = false
	if equipped:
		await _refresh_from_server()
	else:
		UIUtils.show_error(str(InventoryManager.get_last_error_message()))

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
	if _is_refreshing:
		return
	_is_refreshing = true
	var hero_id: int = _resolve_active_hero_id()
	if hero_id > 0:
		var response: Dictionary = await InventoryManager.refresh_inventory(hero_id)
		if bool(response.get("ok", false)) == false:
			var message: String = str(response.get("error", "Failed to refresh inventory"))
			if message.is_empty() == false:
				UIUtils.show_warning(message)
	_refresh_items(AppState.inventory)
	_refresh_equipment(_equipment_from_manager())
	_is_refreshing = false


func _on_active_hero_changed(hero_id: int) -> void:
	_selected_hero_id = hero_id
	delete_hero_button.disabled = hero_id <= 0
	selected_hero_label.text = tr("ui.storage.selected_hero") % _selected_hero_name()
	hero_preview_label.text = _hero_preview_text()
	_refresh_equipment(_equipment_from_manager())
	call_deferred("_refresh_from_server")

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

func _exit_tree() -> void:
	if LocalizationManager.locale_changed.is_connected(_on_locale_changed):
		LocalizationManager.locale_changed.disconnect(_on_locale_changed)
	if HeroManager.active_hero_changed.is_connected(_on_active_hero_changed):
		HeroManager.active_hero_changed.disconnect(_on_active_hero_changed)
	if InventoryManager.items_updated.is_connected(_on_manager_items_updated):
		InventoryManager.items_updated.disconnect(_on_manager_items_updated)
	if InventoryManager.manager_error.is_connected(_on_manager_error):
		InventoryManager.manager_error.disconnect(_on_manager_error)
	if InventoryManager.sig_item_equipped.is_connected(_on_manager_item_equipped):
		InventoryManager.sig_item_equipped.disconnect(_on_manager_item_equipped)
	if has_node("/root/EventBus") and EventBus.inventory_updated.is_connected(_on_eventbus_inventory_updated):
		EventBus.inventory_updated.disconnect(_on_eventbus_inventory_updated)

func _equipment_for_backend_slot(equipment: Dictionary, backend_slot: String) -> Dictionary:
	if equipment.has(backend_slot) and equipment[backend_slot] is Dictionary:
		return (equipment[backend_slot] as Dictionary).duplicate(true)
	return {}


func _connect_inventory_signals() -> void:
	if InventoryManager.items_updated.is_connected(_on_manager_items_updated) == false:
		InventoryManager.items_updated.connect(_on_manager_items_updated)
	if InventoryManager.manager_error.is_connected(_on_manager_error) == false:
		InventoryManager.manager_error.connect(_on_manager_error)
	if InventoryManager.sig_item_equipped.is_connected(_on_manager_item_equipped) == false:
		InventoryManager.sig_item_equipped.connect(_on_manager_item_equipped)
	if has_node("/root/EventBus") and EventBus.inventory_updated.is_connected(_on_eventbus_inventory_updated) == false:
		EventBus.inventory_updated.connect(_on_eventbus_inventory_updated)

func _on_manager_items_updated(items: Array[Dictionary]) -> void:
	_refresh_items(items)

func _on_manager_error(_message: String) -> void:
	_refresh_items(AppState.inventory)

func _on_manager_item_equipped(hero_id: int) -> void:
	if hero_id != _selected_hero_id:
		return
	_refresh_equipment(_equipment_from_manager())

func _equipment_from_manager() -> Dictionary:
	if _selected_hero_id <= 0:
		return {}
	return InventoryManager.get_equipment(_selected_hero_id)

func _resolve_active_hero_id() -> int:
	var hero_id: int = HeroManager.get_active_hero_id()
	if hero_id > 0:
		return hero_id
	if AppState.selected_hero.has("id"):
		return int(AppState.selected_hero.get("id", -1))
	if int(AppState.current_hero_id) > 0:
		return int(AppState.current_hero_id)
	return -1

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
