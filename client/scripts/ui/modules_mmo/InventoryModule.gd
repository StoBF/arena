extends Control

## InventoryModule — hero-scoped item grid with detail panel.

const ITEM_SLOT_SCENE := preload("res://scenes/ui/components/ItemSlot.tscn")

@onready var hero_label: Label = $Root/Header/HeroLabel
@onready var refresh_button: Button = $Root/Header/RefreshButton
@onready var items_grid: GridContainer = $Root/Body/GridPanel/GridMargin/GridScroll/ItemsGrid
@onready var item_name: Label = $Root/Body/DetailPanel/DetailMargin/DetailVBox/ItemName
@onready var item_rarity: Label = $Root/Body/DetailPanel/DetailMargin/DetailVBox/ItemRarity
@onready var item_quantity: Label = $Root/Body/DetailPanel/DetailMargin/DetailVBox/ItemQuantity
@onready var item_description: RichTextLabel = $Root/Body/DetailPanel/DetailMargin/DetailVBox/ItemDescription
@onready var status_label: Label = $Root/StatusLabel

var _items_by_id: Dictionary = {}
var _loading_overlay: Node = null
var _empty_state: Node = null
var _is_loading: bool = false

func _tx(key: String, fallback: String) -> String:
	return CabinetStyle.text(key, fallback)

func _ready() -> void:
	if refresh_button == null or status_label == null or items_grid == null:
		push_warning("InventoryModule nodes are not ready; skipping initialization")
		return
	refresh_button.pressed.connect(_load_inventory)
	if InventoryManager.items_updated.is_connected(_on_manager_items_updated) == false:
		InventoryManager.items_updated.connect(_on_manager_items_updated)
	if InventoryManager.items_load_failed.is_connected(_on_items_load_failed) == false:
		InventoryManager.items_load_failed.connect(_on_items_load_failed)
	if HeroManager.active_hero_changed.is_connected(_on_hero_selected) == false:
		HeroManager.active_hero_changed.connect(_on_hero_selected)
	_create_overlays()
	call_deferred("_apply_cabinet_visuals")
	call_deferred("_load_inventory")

func _exit_tree() -> void:
	if InventoryManager.items_updated.is_connected(_on_manager_items_updated):
		InventoryManager.items_updated.disconnect(_on_manager_items_updated)
	if InventoryManager.items_load_failed.is_connected(_on_items_load_failed):
		InventoryManager.items_load_failed.disconnect(_on_items_load_failed)
	if HeroManager.active_hero_changed.is_connected(_on_hero_selected):
		HeroManager.active_hero_changed.disconnect(_on_hero_selected)

func _apply_cabinet_visuals() -> void:
	CabinetStyle.style_screen(self)
	CabinetStyle.style_header($Root/Header/Title, refresh_button)
	CabinetStyle.style_status_label(status_label)

func _create_overlays() -> void:
	_loading_overlay = LoadingOverlay.new()
	$Root/Body/GridPanel.add_child(_loading_overlay)
	_empty_state = EmptyState.new()
	_empty_state.visible = false
	$Root/Body/GridPanel/GridMargin.add_child(_empty_state)

func _on_hero_selected(_hero_id: int) -> void:
	call_deferred("_load_inventory")

func _load_inventory() -> void:
	if _is_loading:
		return
	for child in items_grid.get_children():
		child.queue_free()
	_items_by_id.clear()
	_clear_detail()
	if _empty_state != null:
		_empty_state.visible = false
	var hero_id: int = _resolve_hero_id()
	if hero_id <= 0:
		hero_label.text = _tx("ui.inventory.hero_none", "Hero: -")
		if _empty_state != null:
			_empty_state.visible = true
		if _empty_state != null and _empty_state.has_method("set_content"):
			_empty_state.set_content(_tx("ui.inventory.no_hero_title", "No Hero Selected"), _tx("ui.inventory.no_hero_hint", "Select a hero to view their inventory."))
		status_label.text = _tx("ui.inventory.no_hero_status", "Select a hero to view inventory")
		return
	hero_label.text = _tx("ui.inventory.hero_id", "Hero: %d") % hero_id
	status_label.text = _tx("ui.inventory.loading", "Loading...")
	_is_loading = true
	if _loading_overlay != null:
		_loading_overlay.show_loading()
	var response: Dictionary = await InventoryManager.refresh_inventory(hero_id)
	if _loading_overlay != null:
		_loading_overlay.hide_loading()
	_is_loading = false
	if bool(response.get("ok", false)) == false:
		status_label.text = _tx("ui.inventory.load_failed", "Failed to load inventory")
		UIUtils.show_error(str(response.get("error", _tx("ui.inventory.load_failed", "Failed to load inventory"))))
		return
	var items: Array = AppState.inventory.duplicate(true)
	_render_items(items)

func _render_items(items: Array) -> void:
	for child in items_grid.get_children():
		child.queue_free()
	_items_by_id.clear()
	if items.is_empty():
		if _empty_state != null:
			_empty_state.visible = true
		if _empty_state != null and _empty_state.has_method("set_content"):
			_empty_state.set_content(_tx("ui.inventory.empty_title", "Empty Inventory"), _tx("ui.inventory.empty_hint", "This hero has no items."))
		status_label.text = _tx("ui.inventory.empty_status", "No items")
		return
	if _empty_state != null:
		_empty_state.visible = false
	var index: int = 0
	for item_variant in items:
		if not item_variant is Dictionary:
			continue
		var item := (item_variant as Dictionary).duplicate(true)
		if str(item.get("id", "")).is_empty():
			item["id"] = "slot_%d" % index
		index += 1
		var item_id: String = str(item.get("id", ""))
		_items_by_id[item_id] = item
		var slot = ITEM_SLOT_SCENE.instantiate()
		slot.set_item_data(item)
		if slot.has_signal("item_selected") and not slot.item_selected.is_connected(_on_item_selected):
			slot.item_selected.connect(_on_item_selected)
		items_grid.add_child(slot)
	status_label.text = "%d items" % items.size()

func _on_item_selected(item_id: String) -> void:
	if not _items_by_id.has(item_id):
		return
	var item: Dictionary = _items_by_id[item_id] as Dictionary
	item_name.text = "Name: %s" % str(item.get("name", item.get("title", "-")))
	item_rarity.text = "Rarity: %s" % str(item.get("rarity", "common")).capitalize()
	item_quantity.text = "Qty: %s" % str(item.get("quantity", item.get("count", "-")))
	item_description.text = "[b]Description:[/b]\n%s" % str(item.get("description", "No description"))

func _on_manager_items_updated(items: Array[Dictionary]) -> void:
	if _is_loading:
		return
	_render_items(items)

func _on_items_load_failed(message: String) -> void:
	status_label.text = _tx("ui.inventory.load_failed", "Failed to load inventory")
	if not message.is_empty():
		UIUtils.show_warning(message)

func _clear_detail() -> void:
	item_name.text = _tx("ui.inventory.item_name_placeholder", "Name: -")
	item_rarity.text = _tx("ui.inventory.item_rarity_placeholder", "Rarity: -")
	item_quantity.text = _tx("ui.inventory.item_qty_placeholder", "Qty: -")
	item_description.text = _tx("ui.inventory.select_item", "Select an item")

func _resolve_hero_id() -> int:
	if HeroManager.get_active_hero_id() > 0:
		return HeroManager.get_active_hero_id()
	if AppState.selected_hero.has("id"):
		return int(AppState.selected_hero.get("id", -1))
	if int(AppState.current_hero_id) > 0:
		return int(AppState.current_hero_id)
	return -1

