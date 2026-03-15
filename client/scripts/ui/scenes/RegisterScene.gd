extends Control

@onready var email_input: LineEdit = $VBox/EmailInput
@onready var password_input: LineEdit = $VBox/PasswordInput
@onready var confirm_input: LineEdit = $VBox/ConfirmPasswordInput
@onready var status_label: Label = $VBox/Status
@onready var register_button: Button = $VBox/Actions/RegisterButton

func _ready() -> void:
	register_button.pressed.connect(_on_register_pressed)
	$VBox/Actions/BackToLoginButton.pressed.connect(func(): EventBus.emit_scene_changed("LoginScene"))
	if LocalizationManager.locale_changed.is_connected(_on_locale_changed) == false:
		LocalizationManager.locale_changed.connect(_on_locale_changed)
	_apply_translations()

func _on_register_pressed() -> void:
	var email: String = email_input.text.strip_edges()
	var password: String = password_input.text.strip_edges()
	var confirm_password: String = confirm_input.text.strip_edges()

	if email.is_empty() or password.is_empty() or confirm_password.is_empty():
		status_label.text = tr("ui.register.status.fill_all")
		return
	if password != confirm_password:
		status_label.text = tr("ui.register.status.password_mismatch")
		return
	if password.length() < 6:
		status_label.text = tr("ui.register.status.password_short")
		return

	register_button.disabled = true
	status_label.text = tr("ui.register.status.creating")
	var result: Dictionary = await AuthManager.register(email, password)
	register_button.disabled = false
	if bool(result.get("ok", false)):
		status_label.text = tr("ui.register.status.success")
		password_input.clear()
		confirm_input.clear()
	else:
		status_label.text = str(result.get("message", tr("ui.register.status.failed")))

func _on_locale_changed(_locale_code: String) -> void:
	_apply_translations()

func _apply_translations() -> void:
	$VBox/Title.text = tr("ui.register.title")
	email_input.placeholder_text = tr("ui.common.email")
	password_input.placeholder_text = tr("ui.common.password")
	confirm_input.placeholder_text = tr("ui.register.confirm_password")
	$VBox/Actions/RegisterButton.text = tr("ui.common.register")
	$VBox/Actions/BackToLoginButton.text = tr("ui.register.back_to_login")
