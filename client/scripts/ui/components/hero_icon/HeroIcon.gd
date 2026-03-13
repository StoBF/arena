extends TextureButton
class_name HeroIcon

signal hero_selected(hero_id: int)

const DEFAULT_HERO_ICON: Texture2D = preload("res://icon.svg")

@onready var icon_rect: TextureRect = $Icon
@onready var name_label: Label = $VBoxContainer/NameLabel
@onready var level_label: Label = $VBoxContainer/LevelLabel

var _hero_id: int = -1

func _ready() -> void:
	if pressed.is_connected(_on_pressed) == false:
		pressed.connect(_on_pressed)

func set_hero_data(hero: Dictionary, selected: bool = false) -> void:
	_hero_id = int(hero.get("id", -1))
	name_label.text = str(hero.get("name", "Hero"))
	level_label.text = "Level: %s" % str(hero.get("level", 1))
	button_pressed = selected
	disabled = _hero_id <= 0
	if hero.has("icon") and hero["icon"] is Texture2D:
		icon_rect.texture = hero["icon"] as Texture2D
	else:
		icon_rect.texture = DEFAULT_HERO_ICON

func _on_pressed() -> void:
	if _hero_id > 0:
		hero_selected.emit(_hero_id)
		if has_node("/root/EventBus"):
			EventBus.emit_hero_selected(_hero_id)
