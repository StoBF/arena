extends Control
class_name HeroEquipmentPanel

# UI Elements
@onready var equipment_grid = $EquipmentGrid
@onready var inventory_grid = $InventoryGrid
@onready var hero_panel = $HeroPanel
@onready var hero_stats = $HeroPanel/HeroStats
@onready var generate_hero_button = $HeroPanel/GenerateHeroButton

# Properties
var slot_nodes: Dictionary = {}

func _ready():
	# TopBar
	TopBar.add_to(self, true, true)
	print("[HeroEquip] _ready() START")

	# Initialize slot nodes (with null safety)
	slot_nodes = {}
	for slot_name in ["head", "chest", "weapon", "offhand"]:
		var node_name = "Slot_%s" % slot_name.capitalize()
		var slot = equipment_grid.get_node_or_null(node_name) if equipment_grid else null
		if slot:
			slot_nodes[slot_name] = slot
		else:
			print("[HeroEquip] WARN: slot node '%s' not found" % node_name)

	# Connect signals
	if generate_hero_button:
		generate_hero_button.pressed.connect(Callable(self, "_on_generate_hero_pressed"))

	# Load data
	_load_data()

func _load_data():
	var hero_id = AppState.current_hero_id
	if hero_id <= 0:
		print("[HeroEquip] No hero selected")
		UIUtils.show_error(Localization.t("no_hero_selected") if Localization.has_key("no_hero_selected") else "Select a hero first")
		return

	print("[HeroEquip] Loading hero %d data" % hero_id)
	# Load hero stats
	var hero_req = Network.request("/heroes/%d" % hero_id, HTTPClient.METHOD_GET)
	hero_req.request_completed.connect(Callable(self, "_on_hero_loaded"))

	# Load equipment
	var eq_req = Network.request("/heroes/%d/equipment" % hero_id, HTTPClient.METHOD_GET)
	eq_req.request_completed.connect(Callable(self, "_on_equipment_loaded"))

func _on_hero_loaded(result: int, code: int, headers, body: PackedByteArray):
	print("[HeroEquip] _on_hero_loaded code=%d" % code)
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		var json = JSON.new()
		var err = json.parse(body.get_string_from_utf8())
		if err == OK and typeof(json.data) == TYPE_DICTIONARY:
			var hero = json.data
			if hero_stats:
				hero_stats.text = "STR: %s  AGI: %s  HP: %s" % [
					str(hero.get("strength", 0)),
					str(hero.get("agility", 0)),
					str(hero.get("health", 0))
				]
			return
	UIUtils.show_error(Localization.t("load_hero_failed") if Localization.has_key("load_hero_failed") else "Failed to load hero")

func _on_equipment_loaded(result: int, code: int, headers, body: PackedByteArray):
	print("[HeroEquip] _on_equipment_loaded code=%d" % code)
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		var json = JSON.new()
		var err = json.parse(body.get_string_from_utf8())
		if err == OK:
			var parsed = json.data
			var items_arr: Array = []
			if typeof(parsed) == TYPE_DICTIONARY and parsed.has("result"):
				items_arr = parsed["result"]
			elif typeof(parsed) == TYPE_ARRAY:
				items_arr = parsed
			_populate_equipment(items_arr)
			return
	UIUtils.show_error(Localization.t("load_equipment_failed") if Localization.has_key("load_equipment_failed") else "Failed to load equipment")

func _populate_equipment(equipment: Array):
	for eq_item in equipment:
		var slot_name = eq_item.get("slot", "")
		if slot_nodes.has(slot_name):
			var slot = slot_nodes[slot_name]
			var icon_path = eq_item.get("icon_path", "")
			if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
				slot.texture = load(icon_path)
			slot.visible = true
			print("[HeroEquip] Equipped '%s' in slot '%s'" % [eq_item.get("name", "?"), slot_name])

func _on_generate_hero_pressed():
	Nav.go("GenerateHero")
