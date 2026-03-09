extends Control

signal open_player_hub

func _ready() -> void:
	$VBox/Header/BackButton.pressed.connect(func(): open_player_hub.emit())
	$VBox/Body/VolumeSlider.value_changed.connect(_on_volume_changed)
	$VBox/Body/FullscreenToggle.toggled.connect(_on_fullscreen_toggled)
	$VBox/Body/LanguageOption.item_selected.connect(_on_language_selected)
	$VBox/Body/LanguageOption.add_item("en")
	$VBox/Body/LanguageOption.add_item("pl")
	$VBox/Body/LanguageOption.add_item("uk")

func bind_controllers(_player_data: Node, _inventory_controller: Node, _craft_controller: Node) -> void:
	pass

func _on_volume_changed(value: float) -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(clamp(value, 0.0, 1.0)))

func _on_fullscreen_toggled(enabled: bool) -> void:
	if enabled:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

func _on_language_selected(index: int) -> void:
	var locale := $VBox/Body/LanguageOption.get_item_text(index)
	TranslationServer.set_locale(locale)
