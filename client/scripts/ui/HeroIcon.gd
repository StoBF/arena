extends TextureButton
class_name HeroIcon

## Emitted when this icon is clicked. Carries the hero's id.
signal hero_selected(hero_id)

var hero_id: Variant = null
var _hero_data: Dictionary = {}

@onready var icon_tex    = $Icon
@onready var name_label  = $VBoxContainer/NameLabel
@onready var level_label = $VBoxContainer/LevelLabel

## Store hero data. If already in the tree, applies immediately;
## otherwise deferred to _ready() (fixes @onready null crash).
func set_hero_data(data: Dictionary) -> void:
	_hero_data = data
	hero_id = data.get("id")
	if is_inside_tree():
		_apply_hero_data()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	pressed.connect(_on_pressed)
	mouse_entered.connect(_on_mouse_enter)
	mouse_exited.connect(_on_mouse_exit)
	if not _hero_data.is_empty():
		_apply_hero_data()

func _apply_hero_data() -> void:
	if name_label:
		name_label.text = str(_hero_data.get("name", ""))
	else:
		print("[HeroIcon] WARN name_label is null")
	if level_label:
		var lvl_tr = tr("level") if tr("level") != "level" else "Level"
		level_label.text = "%s: %d" % [lvl_tr, _hero_data.get("level", 0)]
	else:
		print("[HeroIcon] WARN level_label is null")
	if icon_tex and _hero_data.has("image") and _hero_data.get("image"):
		icon_tex.texture = _hero_data["image"]

func _on_pressed() -> void:
	if hero_id != null:
		AppState.current_hero_id = hero_id
		print("[HeroIcon] Selected hero_id=%s" % str(hero_id))
		hero_selected.emit(hero_id)

func _on_mouse_enter() -> void:
	self.modulate = Color(1, 1, 1, 0.8)

func _on_mouse_exit() -> void:
	self.modulate = Color(1, 1, 1, 1)
