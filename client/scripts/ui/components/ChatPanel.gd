extends Control

signal message_submitted(channel: String, text: String)
signal channel_changed(channel: String)

const CHANNEL_BY_TAB := {
	0: "global",
	1: "trade",
	2: "system",
}

@onready var tabs: TabContainer = $Root/Tabs
@onready var messages: ItemList = $Root/Messages
@onready var message_input: LineEdit = $Root/InputRow/MessageInput
@onready var send_button: Button = $Root/InputRow/SendButton
@onready var system_messages: ItemList = $Root/SystemMessages
@onready var announcements: ItemList = $Root/Announcements

var _messages_by_channel: Dictionary = {
	"global": [],
	"trade": [],
	"system": [],
}

func _ready() -> void:
	tabs.set_tab_title(0, "Global")
	tabs.set_tab_title(1, "Trade")
	tabs.set_tab_title(2, "System")
	tabs.tab_changed.connect(_on_tab_changed)
	send_button.pressed.connect(_on_send_pressed)
	message_input.text_submitted.connect(func(_v: String) -> void: _on_send_pressed())
	_render_current_channel()

func get_current_channel() -> String:
	return CHANNEL_BY_TAB.get(tabs.current_tab, "global")

func set_channel_messages(channel: String, lines: Array) -> void:
	_messages_by_channel[channel] = lines.duplicate(true)
	if channel == get_current_channel():
		_render_current_channel()

func set_system_messages(lines: Array) -> void:
	system_messages.clear()
	for line in lines:
		system_messages.add_item(str(line))

func set_announcements(lines: Array) -> void:
	announcements.clear()
	for line in lines:
		announcements.add_item(str(line))

func _on_tab_changed(_index: int) -> void:
	_render_current_channel()
	channel_changed.emit(get_current_channel())

func _on_send_pressed() -> void:
	var text: String = message_input.text.strip_edges()
	if text.is_empty():
		return
	message_submitted.emit(get_current_channel(), text)
	message_input.clear()

func _render_current_channel() -> void:
	messages.clear()
	var channel: String = get_current_channel()
	var lines: Array = _messages_by_channel.get(channel, []) as Array
	for line in lines:
		messages.add_item(str(line))
	if messages.item_count > 0:
		messages.select(messages.item_count - 1)
	var system_tab: bool = channel == "system"
	message_input.editable = system_tab == false
	send_button.disabled = system_tab
