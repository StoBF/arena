extends Node

# Constants
const ERROR_COLOR = Color(1, 0, 0)  # Red
const SUCCESS_COLOR = Color(0, 1, 0)  # Green

# Properties
var _notification_label: Label
var _notification_timer: Timer

func _ready():
	# Create notification label
	_notification_label = Label.new()
	_notification_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notification_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_notification_label.modulate = Color(1, 1, 1, 0)  # Start invisible
	add_child(_notification_label)
	
	# Create timer
	_notification_timer = Timer.new()
	_notification_timer.one_shot = true
	_notification_timer.timeout.connect(Callable(self, "_on_notification_timeout"))
	add_child(_notification_timer)

func show_error(message: String):
	_show_notification(message, ERROR_COLOR)

func show_success(message: String):
	_show_notification(message, SUCCESS_COLOR)

func _show_notification(message: String, color: Color):
	_notification_label.text = message
	_notification_label.modulate = color
	
	# Animate in
	var tween = create_tween()
	tween.tween_property(_notification_label, "modulate", Color(1, 1, 1, 1), 0.2)
	
	# Start timer
	_notification_timer.start(3.0)

func _on_notification_timeout():
	# Animate out
	var tween = create_tween()
	tween.tween_property(_notification_label, "modulate", Color(1, 1, 1, 0), 0.2) 
