extends Button
class_name HeroCard

var hero_data := {}  # should contain id, name, level, stats, icon_path etc.

func set_data(data: Dictionary) -> void:
    hero_data = data
    text = "%s (Lvl %d)" % [data.get("name",""), data.get("level",0)]
    # TODO: set icon if available

func _ready():
    connect("pressed", self, "_on_pressed")

func _on_pressed():
    emit_signal("hero_selected", hero_data)
