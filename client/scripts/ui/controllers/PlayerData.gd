extends Node

signal heroes_changed(heroes: Array)
signal hero_selected(hero: Dictionary)
signal resources_changed(resources: Dictionary)

const HERO_DATA_PATH := "res://Data/HeroData.json"
const MAX_HERO_SLOTS := 5

var heroes: Array = []
var selected_hero_id: String = ""
var resources: Dictionary = {}

func _ready() -> void:
	_load_data()
	_emit_all()

func _load_data() -> void:
	if FileAccess.file_exists(HERO_DATA_PATH) == false:
		heroes = []
		resources = {}
		return
	var file := FileAccess.open(HERO_DATA_PATH, FileAccess.READ)
	if file == null:
		heroes = []
		resources = {}
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		var data := parsed as Dictionary
		heroes = (data.get("heroes", []) as Array).duplicate(true)
		resources = (data.get("resources", {}) as Dictionary).duplicate(true)
	if heroes.size() > 0:
		selected_hero_id = str((heroes[0] as Dictionary).get("id", ""))

func _emit_all() -> void:
	heroes_changed.emit(get_heroes())
	resources_changed.emit(get_resources())
	hero_selected.emit(get_selected_hero())

func get_heroes() -> Array:
	return heroes.duplicate(true)

func get_resources() -> Dictionary:
	return resources.duplicate(true)

func get_selected_hero() -> Dictionary:
	for hero in heroes:
		var entry := hero as Dictionary
		if str(entry.get("id", "")) == selected_hero_id:
			return entry.duplicate(true)
	return {}

func get_hero_slots() -> Array:
	var slots: Array = []
	for i: int in range(MAX_HERO_SLOTS):
		if i < heroes.size():
			slots.append((heroes[i] as Dictionary).duplicate(true))
		else:
			slots.append({})
	return slots

func select_hero_by_index(index: int) -> void:
	if index < 0 or index >= heroes.size():
		selected_hero_id = ""
		hero_selected.emit({})
		return
	var hero := heroes[index] as Dictionary
	selected_hero_id = str(hero.get("id", ""))
	hero_selected.emit(hero.duplicate(true))

func create_hero(hero_name: String) -> bool:
	if hero_name.strip_edges().is_empty():
		return false
	if heroes.size() >= MAX_HERO_SLOTS:
		return false
	var id := "hero_%d" % Time.get_unix_time_from_system()
	var hero := {"id": id, "name": hero_name.strip_edges()}
	heroes.append(hero)
	selected_hero_id = id
	heroes_changed.emit(get_heroes())
	hero_selected.emit(hero.duplicate(true))
	return true

func delete_selected_hero() -> bool:
	if selected_hero_id.is_empty():
		return false
	for i: int in range(heroes.size()):
		var hero := heroes[i] as Dictionary
		if str(hero.get("id", "")) == selected_hero_id:
			heroes.remove_at(i)
			selected_hero_id = ""
			if heroes.size() > 0:
				selected_hero_id = str((heroes[0] as Dictionary).get("id", ""))
			heroes_changed.emit(get_heroes())
			hero_selected.emit(get_selected_hero())
			return true
	return false

func has_selected_hero() -> bool:
	return selected_hero_id.is_empty() == false

func can_consume_resources(requirements: Dictionary) -> bool:
	for key in requirements.keys():
		var needed: int = int(requirements[key])
		var available: int = int(resources.get(str(key), 0))
		if available < needed:
			return false
	return true

func consume_resources(requirements: Dictionary) -> bool:
	if can_consume_resources(requirements) == false:
		return false
	for key in requirements.keys():
		var k := str(key)
		resources[k] = int(resources.get(k, 0)) - int(requirements[key])
	resources_changed.emit(get_resources())
	return true
