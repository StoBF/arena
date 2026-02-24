extends VBoxContainer
class_name ChatPanel

signal message_sent(text, channel)

@onready var tabs = $Tabs

func _ready():
    # connect send buttons on all tabs
    for i in range(tabs.get_tab_count()):
        var page = tabs.get_child(i)
        var send = page.get_node("InputHBox/Send")
        var line = page.get_node("InputHBox/LineEdit")
        send.pressed.connect(func(): _on_send_pressed(line.text, tabs.get_tab_title(i)))

func _on_send_pressed(text, channel):
    if text.empty():
        return
    emit_signal("message_sent", text, channel)
    # add to list
    var current = tabs.get_current_tab().get_node("MessageList")
    current.add_item("[%s] %s" % [channel, text])
    tabs.get_current_tab().get_node("InputHBox/LineEdit").text = ""

# placeholder backend method
func send_message(channel, text):
    print("[CHAT] send to", channel, text)
