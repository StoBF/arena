extends Control

signal login_success
signal open_register

@onready var email_input: LineEdit = $VBox/EmailInput
@onready var password_input: LineEdit = $VBox/PasswordInput
@onready var status_label: Label = $VBox/Status
@onready var login_button: Button = $VBox/Actions/LoginButton

func _ready() -> void:
	login_button.pressed.connect(_on_login_pressed)
	$VBox/Actions/RegisterButton.pressed.connect(func(): open_register.emit())
	if LocalizationManager.locale_changed.is_connected(_on_locale_changed) == false:
		LocalizationManager.locale_changed.connect(_on_locale_changed)
	_apply_translations()

func bind_controllers(_player_data: Node, _inventory_controller: Node, _craft_controller: Node) -> void:
	pass

func _on_login_pressed() -> void:
	var email: String = email_input.text.strip_edges()
	var password: String = password_input.text.strip_edges()
	if email.is_empty() or password.is_empty():
		status_label.text = tr("ui.login.status.enter_credentials")
		return

	login_button.disabled = true
	status_label.text = tr("ui.login.status.signing_in")
	var result: Dictionary = await AuthManager.login(email, password)
	login_button.disabled = false
	if bool(result.get("ok", false)):
		status_label.text = tr("ui.login.status.success")
		password_input.clear()
		login_success.emit()
	else:
		status_label.text = str(result.get("message", tr("ui.login.status.failed")))

func _on_locale_changed(_locale_code: String) -> void:
	_apply_translations()

func _apply_translations() -> void:
	$VBox/Title.text = tr("ui.login.title")
	email_input.placeholder_text = tr("ui.common.email")
	password_input.placeholder_text = tr("ui.common.password")
	$VBox/Actions/LoginButton.text = tr("ui.common.login")
	$VBox/Actions/RegisterButton.text = tr("ui.login.open_register")
