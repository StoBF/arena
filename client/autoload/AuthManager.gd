extends Node

signal login_succeeded
signal login_failed(message: String)
signal register_succeeded
signal register_failed(message: String)
signal auth_state_changed(is_authenticated: bool)

var jwt_token: String = ""

func _ready() -> void:
	jwt_token = AppState.access_token

func is_authenticated() -> bool:
	return jwt_token.is_empty() == false

func login(email: String, password: String) -> Dictionary:
	var payload := {
		"login": email,
		"password": password,
	}
	var response: Dictionary = await ApiClient.request_post("/auth/login", payload)
	if bool(response.get("ok", false)) == false:
		var message := str(response.get("message", "Login failed"))
		login_failed.emit(message)
		return {"ok": false, "message": message}

	var data: Dictionary = _extract_dict(response.get("data", {}))
	var token: String = str(data.get("access_token", ""))
	if token.is_empty():
		var no_token_message := "Login failed: access token missing"
		login_failed.emit(no_token_message)
		return {"ok": false, "message": no_token_message}

	_set_token(token)
	login_succeeded.emit()
	return {"ok": true, "data": data}

func register(email: String, password: String) -> Dictionary:
	var username: String = _username_from_email(email)
	var payload := {
		"email": email,
		"username": username,
		"password": password,
	}
	var response: Dictionary = await ApiClient.request_post("/auth/register", payload)
	if bool(response.get("ok", false)) == false:
		var message := str(response.get("message", "Register failed"))
		register_failed.emit(message)
		return {"ok": false, "message": message}

	register_succeeded.emit()
	return {"ok": true, "data": _extract_dict(response.get("data", {}))}

func logout() -> void:
	_set_token("")
	AppState.username = ""
	AppState.balance = 0.0
	AppState.current_hero_id = -1
	AppState.user_id = -1

func _set_token(token: String) -> void:
	jwt_token = token
	AppState.set_access_token(token)
	Network.set_auth_header(token)
	auth_state_changed.emit(is_authenticated())

func _extract_dict(data: Variant) -> Dictionary:
	if data is Dictionary:
		return (data as Dictionary).duplicate(true)
	return {}

func _username_from_email(email: String) -> String:
	var local: String = email
	if email.contains("@"):
		local = email.split("@", false, 1)[0]
	local = local.strip_edges().replace(" ", "_")
	if local.length() < 3:
		local = "user_%d" % Time.get_unix_time_from_system()
	return local
