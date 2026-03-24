extends Control
## ClanChatPanel.gd
## Embedded clan chat panel: shows history, connects WS, sends messages.
## Add to any scene that needs clan chat (e.g. ClanDetailsScene).
##
## Usage:
##   $ClanChatPanel.load_chat(clan_id, jwt_token)

@onready var messages_list: VBoxContainer = $ScrollContainer/MessagesList
@onready var input_edit:    LineEdit      = $InputRow/InputEdit
@onready var send_btn:      Button        = $InputRow/SendButton
@onready var scroll:        ScrollContainer = $ScrollContainer

var _clan_id: int      = 0
var _module:  Node     = null  # ClanModule reference

func _ready() -> void:
	send_btn.pressed.connect(_on_send)
	input_edit.text_submitted.connect(_on_send)

func load_chat(clan_id: int, jwt_token: String, clan_module: Node) -> void:
	_clan_id = clan_id
	_module  = clan_module
	_module.chat_message_received.connect(_on_message_received)
	_module.connect_chat(clan_id, jwt_token)
	await _load_history()

func _load_history() -> void:
	var history = await ApiClient.get_clan_chat_history(_clan_id, 50)
	for m in history:
		_append_message(m)

func _on_message_received(msg: Dictionary) -> void:
	_append_message(msg)

func _append_message(m: Dictionary) -> void:
	var lbl := Label.new()
	if m.get("type", "chat") == "system":
		lbl.text = "[SYS] %s" % m.get("action", "")
		lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	else:
		var sender_id: int = m.get("user_id", 0) if m.has("user_id") else m.get("sender_user_id", 0)
		lbl.text = "User#%d: %s" % [sender_id, m.get("text", m.get("content", ""))]
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	messages_list.add_child(lbl)
	await get_tree().process_frame
	scroll.scroll_vertical = scroll.get_v_scroll_bar().max_value

func _on_send(_submitted_text: String = "") -> void:
	var text := input_edit.text.strip_edges()
	if text == "" or _module == null:
		return
	_module.send_chat(text)
	input_edit.text = ""
