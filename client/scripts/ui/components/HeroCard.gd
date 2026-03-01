extends Button
class_name HeroCard

signal hero_selected(hero_data)

var hero_data := {}

func set_data(data: Dictionary) -> void:
	hero_data = data
	if is_inside_tree():
		_apply_data()

func _ready():
	pressed.connect(_on_pressed)
	if not hero_data.is_empty():
		_apply_data()

func _apply_data() -> void:
	text = "%s (Lvl %d)" % [hero_data.get("name", ""), hero_data.get("level", 0)]

func _on_pressed():
	print("[HeroCard] Pressed hero: %s" % hero_data.get("name", "?"))
	hero_selected.emit(hero_data)
