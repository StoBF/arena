extends HBoxContainer
class_name ChatMessage

@onready var _label: Label = Label.new()

const COLOR_GLOBAL := Color(1.0, 1.0, 1.0, 1.0)
const COLOR_TRADE := Color(1.0, 0.9, 0.35, 1.0)
const COLOR_SYSTEM := Color(0.4, 1.0, 0.5, 1.0)

func _ready() -> void:
	if get_child_count() == 0:
		_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(_label)

func set_chat_message(message: String, channel: String = "global") -> void:
	_label.text = message
	var normalized_channel: String = channel.strip_edges().to_lower()
	if _is_system_line(message):
		_label.modulate = COLOR_SYSTEM
	elif normalized_channel == "trade":
		_label.modulate = COLOR_TRADE
	else:
		_label.modulate = COLOR_GLOBAL

func _is_system_line(message: String) -> bool:
	var lower: String = message.strip_edges().to_lower()
	return lower.begins_with("[system]") or lower.begins_with("[система]")
