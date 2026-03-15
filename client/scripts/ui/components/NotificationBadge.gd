extends PanelContainer

@onready var count_label: Label = $CountLabel

func _ready() -> void:
	_apply_style()
	set_count(0)

func set_count(value: int) -> void:
	var count: int = maxi(0, value)
	visible = count > 0
	count_label.text = str(count)

func _apply_style() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#c73a3a")
	style.corner_radius_top_left = 9
	style.corner_radius_top_right = 9
	style.corner_radius_bottom_left = 9
	style.corner_radius_bottom_right = 9
	add_theme_stylebox_override("panel", style)
