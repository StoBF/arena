extends Node

signal data_loaded(item_data: Dictionary)

var item_data: Dictionary = {}
const ITEM_DATA_PATH := "res://Data/ItemData.json"

func _ready() -> void:
	item_data = load_data(ITEM_DATA_PATH)
	data_loaded.emit(item_data)

func load_data(file_path: String) -> Dictionary:
	if FileAccess.file_exists(file_path) == false:
		push_error("[JsonData] Missing data file: %s" % file_path)
		return {}

	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		push_error("[JsonData] Failed to open: %s" % file_path)
		return {}

	var text: String = file.get_as_text()
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed

	push_error("[JsonData] Invalid JSON format in %s" % file_path)
	return {}

func get_item_data(item_name: String) -> Dictionary:
	if item_data.has(item_name):
		return (item_data[item_name] as Dictionary).duplicate(true)
	return {}

func get_stack_size(item_name: String) -> int:
	var data: Dictionary = get_item_data(item_name)
	return maxi(1, int(data.get("StackSize", 1)))

func get_item_icon(item_name: String) -> String:
	var data: Dictionary = get_item_data(item_name)
	var icon_path: String = str(data.get("Icon", "res://item_icons/%s.png" % item_name))
	return icon_path

func LoadData(file_path: String):
	return load_data(file_path)
