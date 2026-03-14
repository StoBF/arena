extends Control

var _hero_id: int = -1

@onready var hero_id_label: Label = $VBox/HeroIdLabel

func set_hero(hero_id: int) -> void:
	_hero_id = hero_id
	hero_id_label.text = "Hero ID: %d" % _hero_id

func _ready() -> void:
	if has_node("/root/EventBus"):
		var bus := get_node("/root/EventBus") as UIEventBus
		if bus.hero_changed.is_connected(_on_hero_changed) == false:
			bus.hero_changed.connect(_on_hero_changed)
	if has_node("/root/AppState"):
		set_hero((get_node("/root/AppState") as UIAppState).selected_hero_id)

func _on_hero_changed(hero_id: int) -> void:
	set_hero(hero_id)
