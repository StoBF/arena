@onready var resolution_option: OptionButton = $VBox/Body/ResolutionOption
extends Control

func _tx(key: String, fallback: String) -> String:
	return CabinetStyle.text(key, fallback)

func _ready() -> void:
		   AppState.load_settings()
		   _init_resolution_options()
		   resolution_option.item_selected.connect(_on_resolution_selected)
		   # Apply saved resolution if not fullscreen
		   if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_FULLSCREEN:
			   DisplayServer.window_set_size(AppState.window_resolution)
			   var screen_size = DisplayServer.screen_get_size()
			   var pos = (screen_size / 2 - AppState.window_resolution / 2).floor()
			   DisplayServer.window_set_position(pos)
	$VBox/Header/BackButton.pressed.connect(func(): EventBus.navigate_to(EventBus.SCENE_PLAYER_HUB))
	$VBox/Body/VolumeSlider.value_changed.connect(_on_volume_changed)
	$VBox/Body/FullscreenToggle.toggled.connect(_on_fullscreen_toggled)
	$VBox/Body/LanguageOption.item_selected.connect(_on_language_selected)
	$VBox/Body/LogoutButton.pressed.connect(_on_logout_pressed)
	if LocalizationManager.locale_changed.is_connected(_on_locale_changed) == false:
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
   var resolutions = [
	   Vector2i(1280, 720),
	   Vector2i(1600, 900),
	   Vector2i(1920, 1080),
	   Vector2i(2560, 1440)
   ]
   resolution_option.clear()
   for res in resolutions:
	   resolution_option.add_item("%dx%d" % [res.x, res.y], res)
   var current = DisplayServer.window_get_size()
   var idx = 0
   for i in range(resolutions.size()):
	   if resolutions[i] == current:
		   idx = i
		   break
   resolution_option.select(idx)
   resolution_option.disabled = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN

func _on_resolution_selected(index: int) -> void:
   var res = resolution_option.get_item_metadata(index)
   if res is Vector2i:
	   DisplayServer.window_set_size(res)
	   var screen_size = DisplayServer.screen_get_size()
	   var pos = (screen_size / 2 - res / 2).floor()
	   DisplayServer.window_set_position(pos)
	   AppState.window_resolution = res
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
	if routed == false:
		UIUtils.show_error("Failed to navigate to login after logout")

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
