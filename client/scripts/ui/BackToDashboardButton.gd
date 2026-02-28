## Reusable "Back to Dashboard" button.
## Add as a child node in any scene to get a one-click return to MainMenu.
## Preserves AppState across scene changes.
extends Button
class_name BackToDashboardButton

func _ready() -> void:
	# Default appearance — can be overridden in the scene tree
	if text.is_empty():
		text = Localization.t("back") if Localization.has_key("back") else "← Back"
	pressed.connect(_on_pressed)
	Localization.locale_changed.connect(_on_locale_changed)

func _on_locale_changed() -> void:
	text = Localization.t("back") if Localization.has_key("back") else "← Back"

func _on_pressed() -> void:
	print("[BackToDashboard] Returning to MainMenu")
	Nav.go_main_menu()
