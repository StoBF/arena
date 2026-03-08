extends PanelContainer

signal craft_requested(recipe_id: String)
signal popup_closed

@onready var title_label: Label = $Margin/VBox/Title
@onready var requirements_label: Label = $Margin/VBox/Requirements
@onready var craft_button: Button = $Margin/VBox/Buttons/CraftButton

var _recipe_id: String = ""

func set_recipe(recipe: Dictionary, resources: Dictionary, can_craft: bool) -> void:
	_recipe_id = str(recipe.get("id", ""))
	title_label.text = str(recipe.get("name", "Recipe"))
	var requirements := recipe.get("requirements", {}) as Dictionary
	var lines: PackedStringArray = []
	for key in requirements.keys():
		var needed: int = int(requirements[key])
		var owned: int = int(resources.get(str(key), 0))
		lines.append("%s: %d / %d" % [str(key), owned, needed])
	requirements_label.text = "\n".join(lines)
	craft_button.disabled = can_craft == false
	visible = true

func _on_craft_button_pressed() -> void:
	if _recipe_id.is_empty() == false:
		craft_requested.emit(_recipe_id)

func _on_close_button_pressed() -> void:
	visible = false
	popup_closed.emit()
