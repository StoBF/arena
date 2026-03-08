extends Button

signal recipe_selected(recipe_id: String)

var _recipe_id: String = ""

func set_recipe_data(data: Dictionary) -> void:
	_recipe_id = str(data.get("id", ""))
	text = str(data.get("name", "Recipe"))

func _pressed() -> void:
	if _recipe_id.is_empty() == false:
		recipe_selected.emit(_recipe_id)
