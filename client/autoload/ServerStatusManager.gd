extends Node

const POLL_INTERVAL_SECONDS: float = 10.0

var _poll_timer: Timer = null

func _ready() -> void:
	_start_polling()
	request_status_update()

func _exit_tree() -> void:
	if _poll_timer and is_instance_valid(_poll_timer):
		_poll_timer.stop()

func _start_polling() -> void:
	if _poll_timer and is_instance_valid(_poll_timer):
		return
	_poll_timer = Timer.new()
	_poll_timer.wait_time = POLL_INTERVAL_SECONDS
	_poll_timer.one_shot = false
	_poll_timer.timeout.connect(request_status_update)
	add_child(_poll_timer)
	_poll_timer.start()

func request_status_update() -> void:
	if has_node("/root/ApiClient") == false or has_node("/root/AppState") == false:
		return

	var response: Dictionary = await ApiClient.get_server_status()
	if bool(response.get("ok", false)) == false:
		AppState.set_server_status("offline", 0)
		return

	var payload: Variant = response.get("data", {})
	if payload is Dictionary:
		var data: Dictionary = payload
		var status: String = str(data.get("status", "offline"))
		var players_online: int = int(data.get("online_players", 0))
		AppState.set_server_status(status, players_online)
		return

	AppState.set_server_status("offline", 0)
