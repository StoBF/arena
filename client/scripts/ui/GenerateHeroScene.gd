extends Control

@onready var name_input = $VBoxContainer/HeroNameInput
@onready var blessing_input = $VBoxContainer/BlessingAmountInput
@onready var create_button = $VBoxContainer/CreateButton
@onready var error_label = $VBoxContainer/ErrorLabel

func _ready():
	# Back to dashboard button
	var back_btn = BackToDashboardButton.new()
	add_child(back_btn)
	move_child(back_btn, 0)
	# Connect the create button signal
	create_button.pressed.connect(Callable(self, "_on_create_pressed"))

func _on_create_pressed():
	var hero_name = name_input.text.strip_edges()
	var blessing = blessing_input.text.to_float()
	if hero_name == "":
		error_label.text = "Введіть ім'я героя."
		error_label.visible = true
		return

	# Backend expects HeroGenerateRequest: {generation, currency, locale}
	# POST /heroes/generate (not /heroes/create which returns 405)
	var payload = {
		"generation": int(blessing) if blessing >= 1 else 1,
		"currency": blessing,
		"locale": Localization.locale if Localization.locale in ["en", "pl", "uk"] else "en"
	}

	print("[HeroGen] POST /heroes/generate payload=%s" % JSON.stringify(payload))
	var req = Network.request("/heroes/generate", HTTPClient.METHOD_POST, payload)
	req.request_completed.connect(Callable(self, "_on_hero_created"))

func _on_hero_created(result: int, code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	var body_text = body.get_string_from_utf8()
	print("[HeroGen] response code=%d body=%s" % [code, body_text.left(200)])
	if result != HTTPRequest.RESULT_SUCCESS or (code != 200 and code != 201):
		var detail = ""
		var parsed_err = JSON.parse_string(body_text)
		if typeof(parsed_err) == TYPE_DICTIONARY and parsed_err.has("detail"):
			detail = str(parsed_err["detail"])
		error_label.text = "Не вдалося створити героя: %s" % detail if detail else "Не вдалося створити героя (HTTP %d)." % code
		error_label.visible = true
		return

	var hero = JSON.parse_string(body_text)
	if typeof(hero) != TYPE_DICTIONARY:
		error_label.text = "Помилка відповіді сервера."
		error_label.visible = true
		return
	# Save new hero for main menu
	AppState.last_created_hero = hero
	Nav.go_main_menu() 
