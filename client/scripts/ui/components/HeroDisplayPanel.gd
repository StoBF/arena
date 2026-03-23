extends PanelContainer

## Placeholder for future 3D hero viewport.

@onready var title_label: Label = $Margin/VBox/TitleLabel
@onready var subtitle_label: Label = $Margin/VBox/SubtitleLabel
@onready var placeholder: PanelContainer = $Margin/VBox/PlaceholderViewport

func set_hero_name(name_str: String) -> void:
	if title_label != null:
		title_label.text = name_str if not name_str.is_empty() else "Hero"
	if subtitle_label != null:
		subtitle_label.text = ""
