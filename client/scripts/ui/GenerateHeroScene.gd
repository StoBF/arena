extends Control

@onready var name_input = $VBoxContainer/HeroNameInput
@onready var blessing_input = $VBoxContainer/BlessingAmountInput
@onready var create_button = $VBoxContainer/CreateButton
@onready var error_label = $VBoxContainer/ErrorLabel

func _ready():
	# Connect the create button signal
	create_button.pressed.connect(Callable(self, "_on_create_pressed"))

func _on_create_pressed():
	var name = name_input.text.strip_edges()
	var blessing = blessing_input.text.to_float()
	if name == "":
		error_label.text = "Введіть ім'я героя."
		error_label.visible = true
		return

	var payload = {
		"name": name,
		"blessing": blessing
	}

	var req = Network.request("/heroes/create", HTTPClient.METHOD_POST, payload)
	req.request_completed.connect(Callable(self, "_on_hero_created"))

func _on_hero_created(result: int, code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != OK or code != 201:
		error_label.text = "Не вдалося створити героя."
		error_label.visible = true
		return

	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if parsed.error != OK:
		error_label.text = "Помилка відповіді сервера."
		error_label.visible = true
		return

	var hero = parsed.result
	# Save new hero for main menu
	AppState.last_created_hero = hero
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn") 
