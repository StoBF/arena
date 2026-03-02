extends VBoxContainer
class_name ChatPanel

signal message_sent(text, channel)

@onready var tabs: TabContainer = $Tabs

func _ready() -> void:
    # connect send buttons on all tabs
    for i in range(tabs.get_tab_count()):
        var page: Node = tabs.get_child(i)
        var send_button: Button = page.get_node("InputHBox/Send")
        var line_edit: LineEdit = page.get_node("InputHBox/LineEdit")
        var channel_name: String = tabs.get_tab_title(i)
        if not send_button.pressed.is_connected(_on_send_pressed.bind(line_edit, channel_name)):
            send_button.pressed.connect(_on_send_pressed.bind(line_edit, channel_name))

func _on_send_pressed(line_edit: LineEdit, channel: String) -> void:
    var text: String = line_edit.text.strip_edges()
    if text.is_empty():
        return

    emit_signal("message_sent", text, channel)

    var message_list: ItemList = _get_current_message_list()
    if message_list != null:
        message_list.add_item("[%s] %s" % [channel, text])

    line_edit.clear()

func _get_current_message_list() -> ItemList:
    var current_page: Control = tabs.get_current_tab_control()
    if current_page == null:
        return null
    if not current_page.has_node("MessageList"):
        return null
    return current_page.get_node("MessageList") as ItemList

# placeholder backend method
func send_message(channel: String, text: String) -> void:
    print("[CHAT] send to", channel, text)
