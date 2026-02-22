extends Node

## Localization singleton. Loads JSON translations, persists user choice,
## and syncs with Godot's TranslationServer so tr() works everywhere.
## Use Localization.t("key") or tr("key") after locale is set.

# Properties
var locale: String = "en"
var translations: Dictionary = {}

# Constants
const LOCALES_PATH = "res://locales/"
const SUPPORTED_LOCALES = ["en", "pl", "uk"]
const LOCALE_CONFIG_PATH = "user://locale.cfg"
const CONFIG_SECTION = "locale"

# Signals
signal locale_changed

# Singleton instance
static var _instance: Node

func _ready() -> void:
	_instance = self
	# Load saved locale first, then fallback to OS or default
	var saved = _load_saved_locale()
	if saved.is_empty():
		var os_lang = OS.get_locale_language()
		# Map language codes to our supported locales
		if os_lang in SUPPORTED_LOCALES:
			load_locale(os_lang)
		else:
			load_locale("en")
	else:
		load_locale(saved)

func _load_saved_locale() -> String:
	var cfg = ConfigFile.new()
	var err = cfg.load(LOCALE_CONFIG_PATH)
	if err != OK:
		return ""
	return cfg.get_value(CONFIG_SECTION, "code", "")

func _save_locale(code: String) -> void:
	var cfg = ConfigFile.new()
	cfg.set_value(CONFIG_SECTION, "code", code)
	cfg.save(LOCALE_CONFIG_PATH)

## Set and load a locale by code (e.g. "en", "uk", "pl"). Saves choice and emits locale_changed.
func load_locale(new_locale: String) -> void:
	if not new_locale in SUPPORTED_LOCALES:
		push_error("Unsupported locale: %s" % new_locale)
		return

	var file_path = LOCALES_PATH + new_locale + ".json"
	var file = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		push_error("Failed to open locale file: %s" % file_path)
		return

	var content = file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(content)
	if parsed == null:
		push_error("Failed to parse locale file: %s" % file_path)
		return

	translations = parsed
	locale = new_locale
	_save_locale(new_locale)

	# Sync Godot's TranslationServer so tr() works in scenes
	TranslationServer.set_locale(new_locale)
	emit_signal("locale_changed")

## Get translated string for key. Use this when not using tr().
static func t(key: String) -> String:
	if _instance == null:
		push_error("Localization singleton not initialized")
		return key
	if not _instance.translations.has(key):
		push_warning("Missing translation key: %s" % key)
		return key
	return _instance.translations[key]

## Get list of supported locale codes (for language selector).
static func get_supported_locales() -> Array:
	return SUPPORTED_LOCALES.duplicate()

## Get display name for a locale code (uses current translations for "english", "ukrainian", "polish").
static func get_locale_display_name(code: String) -> String:
	if _instance == null:
		return code
	var names = {
		"en": "english",
		"uk": "ukrainian",
		"pl": "polish"
	}
	var key = names.get(code, code)
	return _instance.translations.get(key, code) 
