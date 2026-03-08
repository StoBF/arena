extends Node

signal data_loaded(item_data: Dictionary)

var item_data: Dictionary = {}

func _ready() -> void:
	item_data = load_data("res://Data/ItemData.json")
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

func LoadData(file_path: String):
	return load_data(file_path)
