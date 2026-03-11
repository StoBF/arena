extends HBoxContainer
class_name ChatMessage

@onready var _label: Label = Label.new()

func _ready() -> void:
	if get_child_count() == 0:
		_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(_label)

func set_chat_message(message: String) -> void:
	_label.text = message
