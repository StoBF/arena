extends Node

signal locale_changed(locale_code: String)

const SUPPORTED_LOCALES: PackedStringArray = ["en", "uk", "pl"]
const LOCALE_CONFIG_PATH := "user://locale.cfg"
const CONFIG_SECTION := "locale"
const CONFIG_KEY := "code"

var _locale: String = ""

func _ready() -> void:
	var saved: String = _load_saved_locale()
	if saved.is_empty() == false and SUPPORTED_LOCALES.has(saved):
		set_locale(saved)
		return

	var os_locale: String = OS.get_locale_language().to_lower()
	if SUPPORTED_LOCALES.has(os_locale):
		set_locale(os_locale)
	else:
		set_locale("en")

func get_supported_locales() -> PackedStringArray:
	return SUPPORTED_LOCALES

func get_locale() -> String:
	return _locale

func set_locale(locale_code: String) -> void:
	var normalized: String = locale_code.strip_edges().to_lower()
	if SUPPORTED_LOCALES.has(normalized) == false:
		return
	if _locale == normalized:
		return

	_locale = normalized
	TranslationServer.set_locale(_locale)
	_save_locale(_locale)
	locale_changed.emit(_locale)

func get_language_label(locale_code: String) -> String:
	match locale_code:
		"en":
			return tr("lang.english")
		"uk":
			return tr("lang.ukrainian")
		"pl":
			return tr("lang.polish")
		_:
			return locale_code

func _load_saved_locale() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(LOCALE_CONFIG_PATH) != OK:
		return ""
	return str(cfg.get_value(CONFIG_SECTION, CONFIG_KEY, "")).to_lower()

func _save_locale(locale_code: String) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(CONFIG_SECTION, CONFIG_KEY, locale_code)
	cfg.save(LOCALE_CONFIG_PATH)
