extends Control
class_name Register

@onready var back_button = $"BackButton"
@onready var email_field = $"Register#Email"
@onready var nickname_field = $"Register#Nickname"
@onready var password_field = $"Register#Password"
@onready var register_button = $"Register#RegisterButton"
@onready var language_option = $LanguageContainer/LanguageOption
@onready var language_label = $LanguageContainer/LanguageLabel

const LOCALE_ORDER = ["en", "uk", "pl"]

func _ready() -> void:
	_setup_language_selector()
	_localize_ui()
	Localization.locale_changed.connect(_localize_ui)
	back_button.pressed.connect(on_back_pressed)
	register_button.pressed.connect(on_register_pressed)

func _setup_language_selector() -> void:
	if not language_option:
		return
	language_option.clear()
	for code in LOCALE_ORDER:
		var name_key = "english" if code == "en" else "ukrainian" if code == "uk" else "polish"
		language_option.add_item(Localization.t(name_key), LOCALE_ORDER.find(code))
	var idx = LOCALE_ORDER.find(Localization.locale)
	if idx >= 0:
		language_option.selected = idx
	language_option.item_selected.connect(_on_language_selected)

func _on_language_selected(index: int) -> void:
	if index >= 0 and index < LOCALE_ORDER.size():
		Localization.load_locale(LOCALE_ORDER[index])

func _localize_ui() -> void:
	back_button.text = Localization.t("back")
	email_field.placeholder_text = Localization.t("email")
	nickname_field.placeholder_text = Localization.t("nickname") if Localization.has_key("nickname") else "Nickname"
	password_field.placeholder_text = Localization.t("password")
	register_button.text = Localization.t("register_button")
	if language_label:
		language_label.text = Localization.t("language")
	if language_option and language_option.item_count >= 3:
		language_option.set_item_text(0, Localization.t("english"))
		language_option.set_item_text(1, Localization.t("ukrainian"))
		language_option.set_item_text(2, Localization.t("polish"))

func on_back_pressed():
	print("Натиснуто кнопку 'Назад'")
	Nav.go("Login")

func on_register_pressed():
	print("Натиснуто кнопку реєстрації")

	var email = email_field.text.strip_edges()
	var nickname = nickname_field.text.strip_edges()
	var password = password_field.text.strip_edges()

	if email.is_empty() or password.is_empty() or nickname.is_empty():
		UIUtils.show_error(Localization.t("fill_all_fields"))
		return

	if nickname.length() < 3 or nickname.length() > 32:
		UIUtils.show_error("Nickname must be 3-32 characters")
		return

	var data = {
		"email": email,
		"username": nickname,
		"password": password
	}

	print("Дані для запиту:", data)
	var req = Network.request("/auth/register", HTTPClient.METHOD_POST, data)
	if req != null:
		req.request_completed.connect(Callable(self, "_on_register_response"))

func _on_register_response(_result: int, code: int, _headers, body: PackedByteArray):
	print("Отримано відповідь:", code)
	var body_text = body.get_string_from_utf8()
	print("Тіло:", body_text)

	if code == 200 or code == 201:
		UIUtils.show_success(Localization.t("register_success"))
		Nav.go("Login")
	else:
		UIUtils.show_error(Localization.t("register_failed") + ": " + body_text)
