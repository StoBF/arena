extends Control
class_name Register

@onready var back_button = $"BackButton"
@onready var email_field = $"Register#Email"
@onready var password_field = $"Register#Password"
@onready var register_button = $"Register#RegisterButton"
@onready var language_option = $LanguageContainer/LanguageOption
@onready var language_label = $LanguageContainer/LanguageLabel

const LOCALE_ORDER = ["en", "uk", "pl"]

func _ready() -> void:
	_setup_language_selector()
	_localize_ui()
	if LocalizationManager.locale_changed.is_connected(_on_locale_changed) == false:
		LocalizationManager.locale_changed.connect(_on_locale_changed)
	back_button.pressed.connect(on_back_pressed)
	register_button.pressed.connect(on_register_pressed)

func _setup_language_selector() -> void:
	if not language_option:
		return
	language_option.clear()
	for code in LOCALE_ORDER:
		language_option.add_item(LocalizationManager.get_language_label(code), LOCALE_ORDER.find(code))
	var idx = LOCALE_ORDER.find(LocalizationManager.get_locale())
	if idx >= 0:
		language_option.selected = idx
	language_option.item_selected.connect(_on_language_selected)

func _on_language_selected(index: int) -> void:
	if index >= 0 and index < LOCALE_ORDER.size():
		LocalizationManager.set_locale(LOCALE_ORDER[index])

func _on_locale_changed(_locale_code: String) -> void:
	_localize_ui()

func _localize_ui() -> void:
	back_button.text = tr("ui.common.back")
	email_field.placeholder_text = tr("ui.common.email")
	password_field.placeholder_text = tr("ui.common.password")
	register_button.text = tr("ui.common.register")
	if language_label:
		language_label.text = tr("ui.settings.language")
	if language_option and language_option.item_count >= 3:
		language_option.set_item_text(0, LocalizationManager.get_language_label("en"))
		language_option.set_item_text(1, LocalizationManager.get_language_label("uk"))
		language_option.set_item_text(2, LocalizationManager.get_language_label("pl"))

func on_back_pressed():
	print("Натиснуто кнопку 'Назад'")
	get_tree().change_scene_to_file("res://scenes/login_screen.tscn")

func on_register_pressed():
	print("Натиснуто кнопку реєстрації")

	var email = email_field.text.strip_edges()
	var password = password_field.text.strip_edges()

	if email.is_empty() or password.is_empty():
		UIUtils.show_error(tr("ui.register.status.fill_all"))
		return

	var data = {
		"email": email,
		"password": password
	}

	print("Дані для запиту:", data)
	call_deferred("_register_via_api", data)

func _on_register_response(_result: int, code: int, _headers, body: PackedByteArray):
	print("Отримано відповідь:", code)
	var body_text = body.get_string_from_utf8()
	print("Тіло:", body_text)

	if code == 200 or code == 201:
		UIUtils.show_success(tr("ui.register.status.success"))
		get_tree().change_scene_to_file("res://scenes/login_screen.tscn")
	else:
		UIUtils.show_error(tr("ui.register.status.failed") + ": " + body_text)

func _register_via_api(data: Dictionary) -> void:
	var response: Dictionary = await ApiClient.request_post("/auth/register", data)
	if bool(response.get("ok", false)):
		UIUtils.show_success(tr("ui.register.status.success"))
		get_tree().change_scene_to_file("res://scenes/login_screen.tscn")
		return
	UIUtils.show_error(tr("ui.register.status.failed") + ": " + str(response.get("message", "")))
