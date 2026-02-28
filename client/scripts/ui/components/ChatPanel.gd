extends VBoxContainer
class_name ChatPanel

signal message_sent(text, channel)

@onready var tabs: TabContainer = $Tabs

func _ready():
    # connect send buttons on all tabs
    for i in range(tabs.get_tab_count()):
        var page := tabs.get_child(i)
        var send_button: Button = page.get_node("InputHBox/Send")
        var line_edit: LineEdit = page.get_node("InputHBox/LineEdit")
        var channel_name := tabs.get_tab_title(i)
        send_button.pressed.connect(func(): _on_send_pressed(line_edit, channel_name))

func _on_send_pressed(line_edit: LineEdit, channel: String):
    var text := line_edit.text.strip_edges()
    if text.is_empty():
        return

    emit_signal("message_sent", text, channel)

    var message_list := _get_current_message_list()
    if message_list and message_list.has_method("add_item"):
        message_list.add_item("[%s] %s" % [channel, text])

    line_edit.clear()

func _get_current_message_list():
    var current_page := tabs.get_current_tab_control()
    if current_page == null:
        return null
    return current_page.get_node("MessageList")

# placeholder backend method
func send_message(channel, text):
    print("[CHAT] send to", channel, text)
