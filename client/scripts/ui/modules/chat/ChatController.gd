extends Control

@onready var status_label: Label = $VBox/StatusLabel

func _ready() -> void:
	await ApiClient.connect_chat()
	if has_node("/root/EventBus"):
		var bus := get_node("/root/EventBus") as UIEventBus
		if bus.chat_updated.is_connected(_on_chat_updated) == false:
			bus.chat_updated.connect(_on_chat_updated)
	_render_messages()

func _on_chat_updated() -> void:
	_render_messages()

func _render_messages() -> void:
	if has_node("/root/AppState") == false:
		status_label.text = "Messages: 0"
		return
	var state := get_node("/root/AppState") as UIAppState
	var count: int = state.chat_messages.size()
	if count <= 0:
		status_label.text = "Messages: 0"
		return
	var last_variant: Variant = state.chat_messages[count - 1]
	var last_text: String = ""
	if last_variant is Dictionary:
		last_text = str((last_variant as Dictionary).get("text", ""))
	status_label.text = "Messages: %d | Last: %s" % [count, last_text]
