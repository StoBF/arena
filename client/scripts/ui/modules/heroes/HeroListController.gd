extends Control

@onready var hero_one_button: Button = $VBox/HeroButtons/HeroOneButton
@onready var hero_two_button: Button = $VBox/HeroButtons/HeroTwoButton
@onready var selected_label: Label = $VBox/SelectedLabel

func _ready() -> void:
	hero_one_button.pressed.connect(func(): select_hero(1))
	hero_two_button.pressed.connect(func(): select_hero(2))
	_load_heroes()

func select_hero(hero_id: int) -> void:
	if has_node("/root/AppState"):
		(get_node("/root/AppState") as UIAppState).set_selected_hero(hero_id)
	selected_label.text = "Selected Hero ID: %d" % hero_id

func _load_heroes() -> void:
	if has_node("/root/AppState") == false:
		return
	var response: Dictionary = await ApiClient.get_heroes()
	if bool(response.get("ok", false)):
		(get_node("/root/AppState") as UIAppState).set_heroes(response.get("data", []) as Array)
