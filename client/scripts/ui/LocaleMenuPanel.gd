extends Control
class_name LocaleMenuPanel

# UI Elements (scene uses "LocaleMenu#..." node names)
@onready var title = $"LocaleMenu#Title"
@onready var english_button = $"LocaleMenu#EnglishButton"
@onready var polish_button = $"LocaleMenu#PolishButton"
@onready var ukrainian_button = $"LocaleMenu#UkrainianButton"
@onready var back_button = $"LocaleMenu#BackButton"

func _ready() -> void:
	english_button.pressed.connect(Callable(self, "_on_locale_pressed").bind("en"))
	polish_button.pressed.connect(Callable(self, "_on_locale_pressed").bind("pl"))
	ukrainian_button.pressed.connect(Callable(self, "_on_locale_pressed").bind("uk"))
	back_button.pressed.connect(Callable(self, "_on_back_pressed"))
	_localize_ui()
	Localization.locale_changed.connect(_localize_ui)

func _localize_ui() -> void:
	title.text = Localization.t("language")
	english_button.text = Localization.t("english")
	polish_button.text = Localization.t("polish")
	ukrainian_button.text = Localization.t("ukrainian")
	back_button.text = Localization.t("back")

func _on_locale_pressed(locale_code: String) -> void:
	Localization.load_locale(locale_code)
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn") 
