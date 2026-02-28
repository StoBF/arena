extends CanvasLayer
class_name LoginPanel

# UI Elements
@onready var sign_in_button = $Control/VBoxContainer/TextureRect/SignIn/Button
@onready var create_button = $Control/VBoxContainer/TextureRect/CreateAccount/Button
@onready var username_field = $Control/VBoxContainer/TextureRect/LoginFields/username
@onready var password_field = $Control/VBoxContainer/TextureRect/LoginFields/password
@onready var remember_me_checkbox = $Control/VBoxContainer/TextureRect/LoginFields/RememberMeCheckBox
@onready var language_option = $Control/VBoxContainer/TextureRect/LanguageContainer/LanguageOption
@onready var language_label = $Control/VBoxContainer/TextureRect/LanguageContainer/LanguageLabel
@onready var server_status_label = $Control/VBoxContainer/TextureRect/ServerStatusContainer/ServerStatusLabel
@onready var server_status_refresh_btn = $Control/VBoxContainer/TextureRect/ServerStatusContainer/ServerStatusRefresh

const LOCALE_ORDER = ["en", "uk", "pl"]
const SERVER_STATUS_REFRESH_INTERVAL := 30.0
var _status_refresh_timer: Timer = null

func _ready() -> void:
	_setup_language_selector()
	_localize_ui()
	Localization.locale_changed.connect(_localize_ui)
	_load_saved_credentials()
	sign_in_button.pressed.connect(_on_login_pressed)
	create_button.pressed.connect(_on_create_account_pressed)
	_setup_server_status()

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
	sign_in_button.text = Localization.t("login_button")
	create_button.text = Localization.t("register_button")
	username_field.placeholder_text = Localization.t("username")
	password_field.placeholder_text = Localization.t("password")
	if remember_me_checkbox:
		remember_me_checkbox.text = Localization.t("remember_me")
	if language_label:
		language_label.text = Localization.t("language")
	if language_option and language_option.item_count >= 3:
		language_option.set_item_text(0, Localization.t("english"))
		language_option.set_item_text(1, Localization.t("ukrainian"))
		language_option.set_item_text(2, Localization.t("polish"))
	if server_status_refresh_btn:
		server_status_refresh_btn.text = Localization.t("server_status_refresh")

func _setup_server_status() -> void:
	if server_status_label:
		server_status_label.text = Localization.t("server_status_checking")
	if server_status_refresh_btn:
		server_status_refresh_btn.pressed.connect(_on_refresh_status_pressed)
	if Network:
		Network.server_status_checked.connect(_on_server_status_checked)
	Network.check_server_status()
	_start_status_refresh_timer()

func _start_status_refresh_timer() -> void:
	if _status_refresh_timer != null:
		return
	_status_refresh_timer = Timer.new()
	_status_refresh_timer.wait_time = SERVER_STATUS_REFRESH_INTERVAL
	_status_refresh_timer.one_shot = false
	_status_refresh_timer.timeout.connect(_on_status_refresh_timeout)
	add_child(_status_refresh_timer)
	_status_refresh_timer.start()

func _on_status_refresh_timeout() -> void:
	Network.check_server_status()

func _on_refresh_status_pressed() -> void:
	if server_status_label:
		server_status_label.text = Localization.t("server_status_checking")
	Network.check_server_status()

func _on_server_status_checked(online: bool, latency_ms: float, error_message: String) -> void:
	if not is_instance_valid(server_status_label):
		return
	if online:
		server_status_label.text = Localization.t("server_online") + " (" + (Localization.t("server_latency") % int(latency_ms)) + ")"
	else:
		server_status_label.text = Localization.t("server_offline") + " — " + error_message

# Завантаження збереженого username (безпечно, без пароля)
func _load_saved_credentials() -> void:
	var saved_username = ConfigManager.load_username()
	if not saved_username.is_empty():
		username_field.text = saved_username
		if remember_me_checkbox:
			remember_me_checkbox.button_pressed = true
		
		# Спробувати автоматичний логін через збережений токен
		var saved_token = ConfigManager.load_token()
		if not saved_token.is_empty():
			call_deferred("_try_auto_login_with_token", saved_token)

func _on_login_pressed():
	var email = username_field.text.strip_edges()
	var password = password_field.text.strip_edges()

	if email.is_empty() or password.is_empty():
		UIUtils.show_error(Localization.t("fill_all_fields"))
		return

	var data = {
		"login": email,
		"password": password
	}

	print("Відправляю запит на логін:", data)
	var req = Network.request("/auth/login", HTTPClient.METHOD_POST, data)
	req.request_completed.connect(Callable(self, "_on_request_completed"))

func _on_create_account_pressed():
	Nav.go("Register")

func _on_request_completed(_result: int, code: int, _headers, body: PackedByteArray):
	print("Отримано відповідь. Код:", code)

	if code == 200:
		var text = body.get_string_from_utf8()
		var parsed = JSON.parse_string(text)
		print("Parsed JSON:", parsed)

		if typeof(parsed) == TYPE_DICTIONARY and parsed.has("access_token"):
			var token = parsed["access_token"]
			AppState.set_access_token(token)
			Network.set_auth_header(token)
			print("Token:", AppState.token)
			
			# Безпечне збереження: тільки username та token, НЕ пароль
			if remember_me_checkbox and remember_me_checkbox.button_pressed:
				ConfigManager.save_username(username_field.text.strip_edges())
				ConfigManager.save_token(token)
			else:
				ConfigManager.clear_all()
			
			Nav.go("MainMenu")
			return
		else:
			print("⚠️ Відповідь без токена або невірна структура:", parsed)

	UIUtils.show_error(Localization.t("login_failed"))

# Спробувати автоматичний логін через збережений токен
func _try_auto_login_with_token(token: String) -> void:
	if token.is_empty():
		return
	
	# Валідуємо токен через запит до сервера
	AppState.set_access_token(token)
	Network.set_auth_header(token)
	
	# Перевіряємо валідність токену через запит до /user
	var req = Network.request("/user", HTTPClient.METHOD_GET)
	req.request_completed.connect(Callable(self, "_on_token_validation_completed"))

func _on_token_validation_completed(result: int, code: int, _headers, _body: PackedByteArray) -> void:
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		# Токен валідний, переходимо до головного меню
		Nav.go("MainMenu")
	else:
		# Токен невалідний, очищаємо його
		ConfigManager.clear_all()
		AppState.set_access_token("")
		UIUtils.show_error(Localization.t("session_expired"))
