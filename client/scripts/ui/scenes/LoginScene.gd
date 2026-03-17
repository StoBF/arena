extends Control

@onready var email_input: LineEdit = $VBox/EmailInput
@onready var password_input: LineEdit = $VBox/PasswordInput
@onready var login_button: Button = $VBox/Actions/LoginButton
@onready var server_status_label: Label = $VBox/ServerStatus/Label
@onready var server_status_indicator: ColorRect = $VBox/ServerStatus/Indicator

const STATUS_ONLINE_COLOR := Color(0.1, 0.75, 0.2, 1.0)
const STATUS_OFFLINE_COLOR := Color(0.8, 0.1, 0.1, 1.0)

func _ready() -> void:
	login_button.pressed.connect(_on_login_pressed)
	$VBox/Actions/RegisterButton.pressed.connect(func(): EventBus.navigate_to(EventBus.SCENE_REGISTER))
	if AuthManager.login_succeeded.is_connected(_on_login_succeeded) == false:
		AuthManager.login_succeeded.connect(_on_login_succeeded)
	if AuthManager.login_failed.is_connected(_on_login_failed) == false:
		AuthManager.login_failed.connect(_on_login_failed)
	_apply_translations()
	_subscribe_status_updates()
	_set_status_ui(AppState.server_status == "online", AppState.online_players)

func _exit_tree() -> void:
	if has_node("/root/EventBus") and EventBus.server_status_updated.is_connected(_on_server_status_updated):
		EventBus.server_status_updated.disconnect(_on_server_status_updated)
	if AuthManager.login_succeeded.is_connected(_on_login_succeeded):
		AuthManager.login_succeeded.disconnect(_on_login_succeeded)
	if AuthManager.login_failed.is_connected(_on_login_failed):
		AuthManager.login_failed.disconnect(_on_login_failed)

func _on_login_pressed() -> void:
	var email: String = email_input.text.strip_edges()
	var password: String = password_input.text.strip_edges()
	if email.is_empty() or password.is_empty():
		if has_node("/root/UIUtils"):
			UIUtils.show_error(tr("ui.login.status.enter_credentials"))
		return

	login_button.disabled = true
	if has_node("/root/UIUtils"):
		UIUtils.show_info(tr("ui.login.status.signing_in"))
	await AuthManager.login(email, password)
	login_button.disabled = false

func _on_login_succeeded() -> void:
	password_input.clear()
	if has_node("/root/UIUtils"):
		UIUtils.show_success(tr("ui.login.status.success"))
	EventBus.navigate_to(EventBus.SCENE_PLAYER_HUB)

func _on_login_failed(message: String) -> void:
	if has_node("/root/UIUtils"):
		UIUtils.show_error(message if message.is_empty() == false else tr("ui.login.status.failed"))

func _apply_translations() -> void:
	email_input.placeholder_text = tr("ui.common.email")
	password_input.placeholder_text = tr("ui.common.password")
	$VBox/Actions/LoginButton.text = tr("ui.common.login")
	$VBox/Actions/RegisterButton.text = tr("ui.login.open_register")
	_set_status_ui(AppState.server_status == "online", AppState.online_players)

func _subscribe_status_updates() -> void:
	if has_node("/root/EventBus") == false:
		_set_status_ui(false, 0)
		return
	if EventBus.server_status_updated.is_connected(_on_server_status_updated) == false:
		EventBus.server_status_updated.connect(_on_server_status_updated)

func _on_server_status_updated() -> void:
	_set_status_ui(AppState.server_status == "online", AppState.online_players)

func _set_status_ui(is_online: bool, players_online: int) -> void:
	server_status_indicator.color = STATUS_ONLINE_COLOR if is_online else STATUS_OFFLINE_COLOR
	server_status_label.text = "Server: %s | Players online: %d" % ["ONLINE" if is_online else "OFFLINE", maxi(0, players_online)]
