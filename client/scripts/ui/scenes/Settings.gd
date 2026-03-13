extends Control

func _ready() -> void:
	$VBox/Header/BackButton.pressed.connect(func(): EventBus.emit_scene_changed("PlayerHub"))
	$VBox/Body/VolumeSlider.value_changed.connect(_on_volume_changed)
	$VBox/Body/FullscreenToggle.toggled.connect(_on_fullscreen_toggled)
	$VBox/Body/LanguageOption.item_selected.connect(_on_language_selected)
	$VBox/Body/LogoutButton.pressed.connect(_on_logout_pressed)
	if LocalizationManager.locale_changed.is_connected(_on_locale_changed) == false:
		LocalizationManager.locale_changed.connect(_on_locale_changed)
	_apply_translations()

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
	var locale: String = LocalizationManager.get_supported_locales()[index]
	LocalizationManager.set_locale(locale)

func _on_locale_changed(_locale_code: String) -> void:
	_apply_translations()

func _on_logout_pressed() -> void:
	AuthManager.logout()
	EventBus.emit_scene_changed("LoginScene")

func _apply_translations() -> void:
	$VBox/Header/BackButton.text = tr("ui.common.back")
	$VBox/Header/Title.text = tr("ui.settings.title")
	$VBox/Body/VolumeLabel.text = tr("ui.settings.volume")
	$VBox/Body/FullscreenToggle.text = tr("ui.settings.fullscreen")
	$VBox/Body/LogoutButton.text = tr("ui.common.logout")

	var option: OptionButton = $VBox/Body/LanguageOption
	var selected_locale: String = LocalizationManager.get_locale()
	option.clear()
	for locale_code in LocalizationManager.get_supported_locales():
		option.add_item(LocalizationManager.get_language_label(locale_code))
	option.select(maxi(0, LocalizationManager.get_supported_locales().find(selected_locale)))
