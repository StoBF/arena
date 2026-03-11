extends TextureButton
class_name HeroIcon

var hero_id: Variant = null


@onready var icon_tex    = $Icon
@onready var name_label  = $VBoxContainer/NameLabel
@onready var level_label = $VBoxContainer/LevelLabel

func set_hero_data(data: Dictionary) -> void:
	hero_id = data.id
	name_label.text  = data.name
	level_label.text = tr("level") + ": %d" % data.level
	if data.has("image") and data.image:
		icon_tex.texture = data.image

func _ready() -> void:
	connect("pressed", Callable(self, "_on_pressed"))
	connect("mouse_entered", Callable(self, "_on_mouse_enter"))
	connect("mouse_exited", Callable(self, "_on_mouse_exit"))

func _on_pressed() -> void:
	if hero_id != null:
		AppState.current_hero_id = hero_id
		# TODO: emit_signal("hero_selected", hero_id)

func _on_mouse_enter() -> void:
	self.modulate = Color(1,1,1,0.8)

func _on_mouse_exit() -> void:
	self.modulate = Color(1,1,1,1)
