extends Control

@onready var status_label: Label = $VBox/Status
@onready var create_button: Button = $VBox/Actions/CreateButton

func _tx(key: String, fallback: String) -> String:
	return CabinetStyle.text(key, fallback)

func _ready() -> void:
	create_button.pressed.connect(_on_create_pressed)
	_apply_translations()

func _on_create_pressed() -> void:
	create_button.disabled = true
	status_label.text = _tx("ui.hero_creation.status.generating", "Generating hero...")

	var response: Dictionary = await ApiClient.create_hero("")
	create_button.disabled = false

	if not bool(response.get("ok", false)):
		var err_msg: String = str(response.get("message", response.get("error", "Request failed")))
		status_label.text = _tx("ui.hero_creation.status.failed_reason", "Generation failed: %s") % err_msg
		return

	var created: Dictionary = _extract_hero(response.get("data", {}))
	if created.is_empty():
		status_label.text = _tx("ui.hero_creation.status.failed", "Hero generation failed")
		return

	await HeroManager.load_heroes()
	status_label.text = _tx("ui.hero_creation.status.generated", "Hero generated!")
	# Optionally, auto-switch to hero list after a short delay
	await get_tree().create_timer(1.0).timeout
	if has_node("/root/UIManager"):
		UIManager.open_view("heroes")

func _apply_translations() -> void:
	$VBox/Title.text = _tx("ui.hero_creation.title", "Hero Creation")
	$VBox/Actions/CreateButton.text = _tx("ui.common.generate", "Generate")

func _extract_hero(data: Variant) -> Dictionary:
	if data is Dictionary:
		var parsed := data as Dictionary
		if parsed.has("result") and parsed["result"] is Dictionary:
			return (parsed["result"] as Dictionary).duplicate(true)
		return parsed.duplicate(true)
	return {}
