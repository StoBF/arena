extends Control
class_name InventoryUI

const MAX_HERO_ICONS := 5
const EQUIPMENT_SLOTS := ["Helmet", "Armor", "Weapon", "Boots", "Ring", "Amulet"]
const RARITY_ORDER := {
	"common": 1,
	"rare": 2,
	"epic": 3,
	"legendary": 4
}

@onready var hero_selector: VBoxContainer = $MainLayout/LeftPanel/HeroSelector
@onready var equipment_panel: GridContainer = $MainLayout/CenterPanel/EquipmentPanel
@onready var hero_stats_preview: VBoxContainer = $MainLayout/CenterPanel/HeroStatsPreview
@onready var type_dropdown: OptionButton = $MainLayout/RightPanel/FiltersBar/TypeDropdown
@onready var rarity_dropdown: OptionButton = $MainLayout/RightPanel/FiltersBar/RarityDropdown
@onready var search_line_edit: LineEdit = $MainLayout/RightPanel/FiltersBar/SearchLineEdit
@onready var sort_dropdown: OptionButton = $MainLayout/RightPanel/FiltersBar/SortDropdown
@onready var items_grid: GridContainer = $MainLayout/RightPanel/ItemsScroll/ItemsGrid
@onready var stat_delta_tooltip: PopupPanel = $StatDeltaTooltip
@onready var stat_delta_label: Label = $StatDeltaTooltip/Margin/DeltaLabel

@onready var stats_name: Label = $MainLayout/CenterPanel/HeroStatsPreview/StatsName
@onready var stats_level: Label = $MainLayout/CenterPanel/HeroStatsPreview/StatsLevel
@onready var stats_power: Label = $MainLayout/CenterPanel/HeroStatsPreview/StatsPower
@onready var stats_strength: Label = $MainLayout/CenterPanel/HeroStatsPreview/StatsStrength
@onready var stats_agility: Label = $MainLayout/CenterPanel/HeroStatsPreview/StatsAgility
@onready var stats_health: Label = $MainLayout/CenterPanel/HeroStatsPreview/StatsHealth

var _item_slot_scene: PackedScene = preload("res://scenes/ui/ItemSlot.tscn")
var _heroes: Array = []
var _all_items: Array = []
var _active_hero_id: int = -1

var _type_filter: String = "All"
var _rarity_filter: String = "All"
var _search_filter: String = ""
var _sort_mode: String = "Newest"

func _ready() -> void:
	_setup_filters()
	_connect_signals()
	_load_heroes()

func _setup_filters() -> void:
	_populate_dropdown(type_dropdown, ["All", "Weapon", "Armor", "Recipe", "Resource"])
	_populate_dropdown(rarity_dropdown, ["All", "Common", "Rare", "Epic", "Legendary"])
	_populate_dropdown(sort_dropdown, ["Newest", "Rarity", "Power"])

func _connect_signals() -> void:
	type_dropdown.item_selected.connect(_on_type_filter_changed)
	rarity_dropdown.item_selected.connect(_on_rarity_filter_changed)
	sort_dropdown.item_selected.connect(_on_sort_mode_changed)
	search_line_edit.text_changed.connect(_on_search_changed)
	for slot_name in EQUIPMENT_SLOTS:
		var slot_button: EquipmentSlot = equipment_panel.get_node_or_null("Slot%s" % slot_name)
		if slot_button != null:
			slot_button.pressed.connect(_on_equipment_slot_pressed.bind(slot_name))
			slot_button.stat_preview_requested.connect(_on_stat_preview_requested)
			slot_button.stat_preview_cleared.connect(_on_stat_preview_cleared)

	if not HeroManager.heroes_updated.is_connected(_on_heroes_updated):
		HeroManager.heroes_updated.connect(_on_heroes_updated)
	if not HeroManager.active_hero_changed.is_connected(_on_active_hero_changed):
		HeroManager.active_hero_changed.connect(_on_active_hero_changed)
	if not HeroManager.heroes_load_failed.is_connected(_on_heroes_load_failed):
		HeroManager.heroes_load_failed.connect(_on_heroes_load_failed)
	if not InventoryManager.items_updated.is_connected(_on_items_updated):
		InventoryManager.items_updated.connect(_on_items_updated)
	if not InventoryManager.equipment_changed.is_connected(_on_equipment_changed):
		InventoryManager.equipment_changed.connect(_on_equipment_changed)
	if not InventoryManager.items_load_failed.is_connected(_on_items_load_failed):
		InventoryManager.items_load_failed.connect(_on_items_load_failed)

func _load_heroes() -> void:
	_heroes = HeroManager.get_heroes()
	if _heroes.is_empty():
		HeroManager.load_heroes()
		return
	_on_heroes_updated(_heroes)

func _on_heroes_updated(heroes: Array) -> void:
	_heroes = heroes.duplicate(true)
	_rebuild_hero_selector()
	var selected_id := HeroManager.get_active_hero_id()
	if selected_id <= 0 and not _heroes.is_empty():
		selected_id = int(_heroes[0].get("id", -1))
	if selected_id > 0:
		_set_active_hero(selected_id)

func _rebuild_hero_selector() -> void:
	for child in hero_selector.get_children():
		child.queue_free()

	var count := mini(MAX_HERO_ICONS, _heroes.size())
	for i in range(count):
		var hero: Dictionary = _heroes[i]
		var button := Button.new()
		button.text = "%s (Lvl %d)" % [str(hero.get("name", "Hero")), int(hero.get("level", 1))]
		button.pressed.connect(_on_hero_button_pressed.bind(int(hero.get("id", -1))))
		hero_selector.add_child(button)

func _on_hero_button_pressed(hero_id: int) -> void:
	_set_active_hero(hero_id)

func _set_active_hero(hero_id: int) -> void:
	if hero_id <= 0:
		return
	_active_hero_id = hero_id
	HeroManager.set_active_hero_id(hero_id)
	_all_items = InventoryManager.get_items_cached()
	_refresh_items_grid()
	InventoryManager.load_items(hero_id)
	_refresh_equipment_panel()
	_refresh_hero_stats_preview()

func _on_active_hero_changed(hero_id: int) -> void:
	if hero_id <= 0:
		return
	_active_hero_id = hero_id
	_refresh_equipment_panel()
	_refresh_hero_stats_preview()

func _on_items_updated(_items: Array) -> void:
	_all_items = InventoryManager.get_items_cached()
	_refresh_items_grid()

func _on_heroes_load_failed(message: String) -> void:
	UIUtils.show_error(message)

func _on_items_load_failed(message: String) -> void:
	UIUtils.show_error(message)

func _on_equipment_changed(hero_id: int, _slot_name: String, _item_data: Dictionary) -> void:
	if hero_id != _active_hero_id:
		return
	_refresh_equipment_panel()
	_refresh_hero_stats_preview()

func _on_type_filter_changed(index: int) -> void:
	_type_filter = type_dropdown.get_item_text(index)
	_refresh_items_grid()

func _on_rarity_filter_changed(index: int) -> void:
	_rarity_filter = rarity_dropdown.get_item_text(index)
	_refresh_items_grid()

func _on_sort_mode_changed(index: int) -> void:
	_sort_mode = sort_dropdown.get_item_text(index)
	_refresh_items_grid()

func _on_search_changed(value: String) -> void:
	_search_filter = value.strip_edges().to_lower()
	_refresh_items_grid()

func _refresh_items_grid() -> void:
	for child in items_grid.get_children():
		child.queue_free()

	var items_to_show := _filtered_sorted_items()
	for item in items_to_show:
		var slot: ItemSlot = _item_slot_scene.instantiate()
		slot.set_item(item)
		slot.slot_pressed.connect(_on_item_slot_pressed)
		items_grid.add_child(slot)

func _on_item_slot_pressed(item_data: Dictionary) -> void:
	if _active_hero_id <= 0:
		return
	var item_id := int(item_data.get("id", -1))
	if item_id <= 0:
		return
	var slot_name := InventoryManager.resolve_slot_from_item(item_data)
	if slot_name.is_empty():
		return
	var rollback := InventoryManager.apply_optimistic_equip(_active_hero_id, item_id, slot_name)
	var success: bool = await InventoryManager.equip_item(_active_hero_id, item_id, slot_name)
	if not success:
		InventoryManager.rollback_optimistic_equip(_active_hero_id, slot_name, rollback)
		UIUtils.show_error("Failed to equip item")

func _on_equipment_slot_pressed(slot_name: String) -> void:
	if _active_hero_id <= 0:
		return
	var equipment := InventoryManager.get_equipment(_active_hero_id)
	if not equipment.has(slot_name):
		return
	var ok := await InventoryManager.unequip_item(_active_hero_id, slot_name)
	if not ok:
		UIUtils.show_error("Failed to unequip item")

func _on_stat_preview_requested(slot_type: String, item_id: int, global_pos: Vector2) -> void:
	if _active_hero_id <= 0:
		return
	var delta := InventoryManager.calculate_stat_delta_for_equip(_active_hero_id, item_id, slot_type)
	stat_delta_label.text = "Power %s%d\nSTR %s%d\nAGI %s%d\nHP %s%d" % [
		_format_delta_sign(int(delta.get("power", 0))), int(delta.get("power", 0)),
		_format_delta_sign(int(delta.get("strength", 0))), int(delta.get("strength", 0)),
		_format_delta_sign(int(delta.get("agility", 0))), int(delta.get("agility", 0)),
		_format_delta_sign(int(delta.get("health", 0))), int(delta.get("health", 0))
	]
	stat_delta_tooltip.position = Vector2i(global_pos.x + 12, global_pos.y + 12)
	stat_delta_tooltip.popup()

func _on_stat_preview_cleared() -> void:
	stat_delta_tooltip.hide()

func _refresh_equipment_panel() -> void:
	var equipment: Dictionary = InventoryManager.get_equipment(_active_hero_id)
	for slot_name in EQUIPMENT_SLOTS:
		var slot_button: Button = equipment_panel.get_node_or_null("Slot%s" % slot_name)
		if slot_button == null:
			continue
		if equipment.has(slot_name):
			var item_data: Dictionary = equipment[slot_name]
			slot_button.text = "%s\n%s" % [slot_name, str(item_data.get("name", "Equipped"))]
		else:
			slot_button.text = "%s\nEmpty" % slot_name

func _refresh_hero_stats_preview() -> void:
	var hero_data := HeroManager.get_hero_by_id(_active_hero_id)
	var equipment := InventoryManager.get_equipment(_active_hero_id)
	var stats := InventoryManager.calculate_hero_preview_stats(hero_data, equipment)

	stats_name.text = "Hero: %s" % str(stats.get("name", "Unknown Hero"))
	stats_level.text = "Level: %d" % int(stats.get("level", 1))
	stats_power.text = "Power: %d" % int(stats.get("power", 0))
	stats_strength.text = "Strength: %d" % int(stats.get("strength", 0))
	stats_agility.text = "Agility: %d" % int(stats.get("agility", 0))
	stats_health.text = "Health: %d" % int(stats.get("health", 0))

func _filtered_sorted_items() -> Array:
	var filtered: Array = []
	for item in _all_items:
		if not _matches_filters(item):
			continue
		filtered.append(item)

	filtered.sort_custom(_compare_items)
	return filtered

func _matches_filters(item: Dictionary) -> bool:
	var item_type := str(item.get("type", "All"))
	var item_rarity := str(item.get("rarity", "Common"))
	var item_name := str(item.get("name", "")).to_lower()

	if _type_filter != "All" and item_type.to_lower() != _type_filter.to_lower():
		return false
	if _rarity_filter != "All" and item_rarity.to_lower() != _rarity_filter.to_lower():
		return false
	if not _search_filter.is_empty() and not item_name.contains(_search_filter):
		return false
	return true

func _compare_items(a: Dictionary, b: Dictionary) -> bool:
	if _sort_mode == "Power":
		return _item_power(a) > _item_power(b)
	if _sort_mode == "Rarity":
		return _rarity_rank(a) > _rarity_rank(b)
	return _item_newest_rank(a) > _item_newest_rank(b)

func _item_power(item: Dictionary) -> int:
	if item.has("power"):
		return int(item.get("power", 0))
	return int(item.get("attack", 0)) + int(item.get("defense", 0)) + int(item.get("stability", 0)) + int(item.get("energy", 0)) + int(item.get("durability", 0))

func _rarity_rank(item: Dictionary) -> int:
	var rarity := str(item.get("rarity", "Common")).to_lower()
	return int(RARITY_ORDER.get(rarity, 0))

func _item_newest_rank(item: Dictionary) -> int:
	if item.has("created_at"):
		return int(item.get("created_at", 0))
	if item.has("updated_at"):
		return int(item.get("updated_at", 0))
	return int(item.get("id", 0))

func _populate_dropdown(dropdown: OptionButton, options: Array) -> void:
	dropdown.clear()
	for option in options:
		dropdown.add_item(str(option))

func _format_delta_sign(value: int) -> String:
	if value >= 0:
		return "+"
	return ""
