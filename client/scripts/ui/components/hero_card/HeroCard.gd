extends Button
class_name HeroCard

# Legacy component path kept for compatibility only.
# Canonical runtime hero card in active module flow:
# - res://scenes/ui/components/HeroCard.tscn
# - res://scripts/ui/components/hero_card_view.gd

signal hero_selected(hero_id: int)

const DEFAULT_HERO_ICON: Texture2D = preload("res://icon.svg")

var _hero_id: int = -1

func _ready() -> void:
	push_warning("[HeroCard] Legacy script path loaded. Prefer HeroCard.tscn + hero_card_view.gd")
	toggle_mode = true
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	custom_minimum_size = Vector2(140, 56)
	if is_connected("pressed", _on_pressed) == false:
		pressed.connect(_on_pressed)

func set_hero_data(hero: Dictionary, selected: bool) -> void:
	_hero_id = int(hero.get("id", -1))
	text = str(hero.get("name", "Hero"))
	icon = DEFAULT_HERO_ICON
	button_pressed = selected
	disabled = _hero_id <= 0

func _on_pressed() -> void:
	if _hero_id > 0:
		if has_node("/root/EventBus"):
			EventBus.emit_hero_selected(_hero_id)
		hero_selected.emit(_hero_id)
