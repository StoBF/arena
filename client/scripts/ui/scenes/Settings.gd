extends Control

@onready var resolution_option: OptionButton = $VBox/Body/ResolutionOption
@onready var volume_slider: HSlider = $VBox/Body/VolumeSlider
@onready var fullscreen_toggle: CheckButton = $VBox/Body/FullscreenToggle
@onready var language_option: OptionButton = $VBox/Body/LanguageOption
@onready var back_button: Button = $VBox/Header/BackButton
@onready var logout_button: Button = $VBox/Body/LogoutButton


func _tx(key: String, fallback: String) -> String:
	return CabinetStyle.text(key, fallback)


func _ready() -> void:
	AppState.load_settings()

	_init_resolution_options()

	back_button.pressed.connect(func(): EventBus.navigate_to(EventBus.SCENE_PLAYER_HUB))
	volume_slider.value_changed.connect(_on_volume_changed)
	fullscreen_toggle.toggled.connect(_on_fullscreen_toggled)
	language_option.item_selected.connect(_on_language_selected)
	resolution_option.item_selected.connect(_on_resolution_selected)
	logout_button.pressed.connect(_on_logout_pressed)

	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_size(AppState.window_resolution)
		var screen_size: Vector2i = DisplayServer.screen_get_size()
		var pos: Vector2i = Vector2i(
			int((screen_size.x - AppState.window_resolution.x) / 2),
			int((screen_size.y - AppState.window_resolution.y) / 2)
		)
		DisplayServer.window_set_position(pos)

	if not LocalizationManager.locale_changed.is_connected(_on_locale_changed):
		LocalizationManager.locale_changed.connect(_on_locale_changed)

	_apply_translations()


func _exit_tree() -> void:
	if LocalizationManager.locale_changed.is_connected(_on_locale_changed):
		LocalizationManager.locale_changed.disconnect(_on_locale_changed)


func _on_volume_changed(value: float) -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(clamp(value, 0.0, 1.0)))


func _on_fullscreen_toggled(enabled: bool) -> void:
	if enabled:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		resolution_option.disabled = true
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		resolution_option.disabled = false


func _init_resolution_options() -> void:
	var resolutions: Array[Vector2i] = [
		Vector2i(1280, 720),
		Vector2i(1600, 900),
		Vector2i(1920, 1080),
		Vector2i(2560, 1440)
	]

	resolution_option.clear()

	for i: int in range(resolutions.size()):
		var res: Vector2i = resolutions[i]
		resolution_option.add_item("%dx%d" % [res.x, res.y])
		resolution_option.set_item_metadata(i, res)

	var current: Vector2i = DisplayServer.window_get_size()
	var idx: int = 0

	for i: int in range(resolutions.size()):
		if resolutions[i] == current:
			idx = i
			break

	resolution_option.select(idx)
	resolution_option.disabled = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN


func _on_resolution_selected(index: int) -> void:
	var res: Variant = resolution_option.get_item_metadata(index)
	if res is Vector2i:
		var target_res: Vector2i = res
		DisplayServer.window_set_size(target_res)

		var screen_size: Vector2i = DisplayServer.screen_get_size()
		var pos: Vector2i = Vector2i(
			int((screen_size.x - target_res.x) / 2),
			int((screen_size.y - target_res.y) / 2)
		)
		DisplayServer.window_set_position(pos)

		AppState.window_resolution = target_res
		AppState.save_settings()


func _on_language_selected(index: int) -> void:
	var locales: Array = LocalizationManager.get_supported_locales()
	if index < 0 or index >= locales.size():
		UIUtils.show_warning(_tx("ui.settings.invalid_language_index", "Invalid language selection"))
		return

	var locale: String = str(locales[index])
	LocalizationManager.set_locale(locale)


func _on_locale_changed(_locale_code: String) -> void:
	_apply_translations()


func _on_logout_pressed() -> void:
	AuthManager.logout()
	var routed: bool = EventBus.navigate_to(EventBus.SCENE_LOGIN)
	if not routed:
		UIUtils.show_error("Failed to navigate to login after logout")


func _apply_translations() -> void:
	back_button.text = tr("ui.common.back")
	$VBox/Header/Title.text = tr("ui.settings.title")
	$VBox/Body/VolumeLabel.text = tr("ui.settings.volume")
	fullscreen_toggle.text = tr("ui.settings.fullscreen")
	logout_button.text = tr("ui.common.logout")

	var option: OptionButton = language_option
	var selected_locale: String = LocalizationManager.get_locale()

	option.clear()
	for locale_code: String in LocalizationManager.get_supported_locales():
		option.add_item(LocalizationManager.get_language_label(locale_code))

	option.select(maxi(0, LocalizationManager.get_supported_locales().find(selected_locale)))
