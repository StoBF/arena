extends Control

@onready var status_label: Label = $VBox/StatusLabel
@onready var poll_timer: Timer = $PollTimer

func _ready() -> void:
	if has_node("/root/ApiClient"):
		await (get_node("/root/ApiClient") as UIApiClient).subscribe_chat_socket("global")
	poll_timer.timeout.connect(_poll_messages)
	poll_timer.start()
	_poll_messages()

func _poll_messages() -> void:
	if has_node("/root/ApiClient") == false or has_node("/root/AppState") == false:
		return
	var response: Dictionary = await (get_node("/root/ApiClient") as UIApiClient).poll_chat_messages("global")
	if bool(response.get("ok", false)) == false:
		return
	var incoming: Array = response.get("data", []) as Array
	if incoming.is_empty():
		return
	var state := get_node("/root/AppState") as UIAppState
	for message_variant in incoming:
		if message_variant is Dictionary:
			var message: Dictionary = message_variant as Dictionary
			state.push_chat_message(message)
			if has_node("/root/EventBus"):
				(get_node("/root/EventBus") as UIEventBus).chat_message.emit(message)
	status_label.text = "Messages: %d" % state.chat_messages.size()
