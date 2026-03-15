## ActivityFeed — scrollable event log for the right sidebar.
## Shows recent game events: hero trained, auction sold, battle finished, etc.
class_name ActivityFeed
extends VBoxContainer

const MAX_ENTRIES := 50
const ENTRY_COLORS := {
	"battle":   Color(0.95, 0.45, 0.35),
	"auction":  Color(0.85, 0.75, 0.4),
	"training": Color(0.4, 0.7, 0.95),
	"healing":  Color(0.45, 0.85, 0.75),
	"craft":    Color(0.7, 0.55, 0.85),
	"system":   Color(0.6, 0.63, 0.7),
	"default":  Color(0.7, 0.72, 0.78),
}

var _title_label: Label
var _scroll: ScrollContainer
var _entries_vbox: VBoxContainer
var _entries: Array = []


func _ready() -> void:
	add_theme_constant_override("separation", 4)

	_title_label = Label.new()
	_title_label.text = tr("ui.activity_feed.title")
	_title_label.add_theme_font_size_override("font_size", 14)
	_title_label.add_theme_color_override("font_color", Color(0.75, 0.72, 0.62))
	add_child(_title_label)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)

	_entries_vbox = VBoxContainer.new()
	_entries_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_entries_vbox.add_theme_constant_override("separation", 2)
	_scroll.add_child(_entries_vbox)


## Add an event entry. category: "battle", "auction", "training", "healing", "craft", "system"
func add_entry(text: String, category: String = "default") -> void:
	var timestamp := Time.get_time_string_from_system().substr(0, 5)
	var color: Color = ENTRY_COLORS.get(category, ENTRY_COLORS["default"])

	var label := Label.new()
	label.text = "[%s] %s" % [timestamp, text]
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_entries_vbox.add_child(label)
	_entries.append(label)

	# Trim old entries
	while _entries.size() > MAX_ENTRIES:
		var old: Label = _entries.pop_front()
		if is_instance_valid(old):
			old.queue_free()

	# Scroll to bottom
	await get_tree().process_frame
	_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


func clear_entries() -> void:
	for entry in _entries:
		if is_instance_valid(entry):
			entry.queue_free()
	_entries.clear()
