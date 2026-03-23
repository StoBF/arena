extends Control

signal message_submitted(channel: String, text: String)
signal channel_changed(channel: String)

const CHANNEL_BY_TAB := {
	0: "global",
	1: "trade",
	2: "system",
}

const ROW_COLOR_EVEN := Color(0.10, 0.11, 0.14, 0.0)
const ROW_COLOR_ODD  := Color(0.16, 0.18, 0.22, 0.6)
const ROW_COLOR_SYSTEM := Color(0.12, 0.15, 0.10, 0.5)

@onready var tabs: TabContainer = $Root/Tabs
@onready var messages_global: ItemList = $Root/Tabs/Global/MessagesGlobal
@onready var messages_trade: ItemList = $Root/Tabs/Trade/MessagesTrade
@onready var messages_system: ItemList = $Root/Tabs/System/MessagesSystem
@onready var message_input: LineEdit = $Root/InputArea/InputMargin/InputRow/MessageInput
@onready var send_button: Button = $Root/InputArea/InputMargin/InputRow/SendButton
@onready var channel_indicator: Label = $Root/ChatHeader/HeaderMargin/HeaderRow/ChannelIndicator

var _messages_by_channel: Dictionary = {
	"global": [],
	"trade": [],
	"system": [],
}

func _ready() -> void:
	if tabs == null or message_input == null or send_button == null:
		push_warning("ChatPanel: required nodes missing")
		return
	tabs.set_tab_title(0, "Global")
	tabs.set_tab_title(1, "Trade")
	tabs.set_tab_title(2, "System")
	tabs.tab_changed.connect(_on_tab_changed)
	send_button.pressed.connect(_on_send_pressed)
	message_input.text_submitted.connect(func(_v: String) -> void: _on_send_pressed())
	_apply_list_theme(messages_global)
	_apply_list_theme(messages_trade)
	_apply_list_theme(messages_system)
	_render_current_channel()

func _apply_list_theme(list: ItemList) -> void:
	if list == null:
		return
	list.add_theme_constant_override("v_separation", 3)
	list.add_theme_constant_override("h_separation", 10)

func get_current_channel() -> String:
	if tabs == null:
		return "global"
	return CHANNEL_BY_TAB.get(tabs.current_tab, "global")

func _messages_list_for_channel(channel: String) -> ItemList:
	match channel:
		"global":
			return messages_global
		"trade":
			return messages_trade
		"system":
			return messages_system
		_:
			return messages_global

func set_channel_messages(channel: String, lines: Array) -> void:
	_messages_by_channel[channel] = lines.duplicate(true)
	if channel == get_current_channel():
		_render_current_channel()

func set_system_messages(lines: Array) -> void:
	var existing: Array = _messages_by_channel.get("system", []) as Array
	for line in lines:
		if not existing.has(line):
			existing.append(line)
	_messages_by_channel["system"] = existing
	if get_current_channel() == "system":
		_render_current_channel()

func set_announcements(lines: Array) -> void:
	var existing: Array = _messages_by_channel.get("system", []) as Array
	for line in lines:
		var entry: String = "[Announce] " + str(line)
		if not existing.has(entry):
			existing.append(entry)
	_messages_by_channel["system"] = existing
	if get_current_channel() == "system":
		_render_current_channel()

func _on_tab_changed(_index: int) -> void:
	if tabs == null:
		return
	_render_current_channel()
	channel_changed.emit(get_current_channel())

func _on_send_pressed() -> void:
	var text: String = message_input.text.strip_edges()
	if text.is_empty():
		return
	message_submitted.emit(get_current_channel(), text)
	message_input.clear()

func _format_line(raw: Variant) -> String:
	if raw is Dictionary:
		var d: Dictionary = raw
		var author: String = str(d.get("username", d.get("user", d.get("from", ""))))
		var body: String = str(d.get("text", d.get("message", d.get("body", str(d)))))
		if author.is_empty():
			return "  " + body
		return "  %-16s | %s" % [author, body]
	return "  " + str(raw)

func _render_current_channel() -> void:
	var channel: String = get_current_channel()
	var list: ItemList = _messages_list_for_channel(channel)
	if list == null:
		return
	list.clear()
	var lines: Array = _messages_by_channel.get(channel, []) as Array
	var is_system: bool = channel == "system"
	for i in range(lines.size()):
		list.add_item(_format_line(lines[i]))
		if is_system:
			list.set_item_custom_bg_color(i, ROW_COLOR_SYSTEM)
			list.set_item_custom_color(i, Color(0.72, 0.82, 0.65, 1))
		elif i % 2 == 0:
			list.set_item_custom_bg_color(i, ROW_COLOR_EVEN)
		else:
			list.set_item_custom_bg_color(i, ROW_COLOR_ODD)
	if list.item_count > 0:
		list.select(list.item_count - 1)
		list.ensure_current_is_visible()
	var system_tab: bool = channel == "system"
	message_input.editable = system_tab == false
	send_button.disabled = system_tab
	if channel_indicator != null:
		channel_indicator.text = channel.capitalize()
