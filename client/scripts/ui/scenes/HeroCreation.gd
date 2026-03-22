extends Control

@onready var status_label: Label = $VBox/Status
@onready var create_button: Button = $VBox/Actions/CreateButton

func _tx(key: String, fallback: String) -> String:
	return CabinetStyle.text(key, fallback)

func _txf(key: String, fallback: String, args: Array = []) -> String:
	return CabinetStyle.textf(key, fallback, args)

func _ready() -> void:
	create_button.pressed.connect(_on_create_pressed)
	$VBox/Actions/BackButton.pressed.connect(func() -> void: EventBus.navigate_to(EventBus.SCENE_PLAYER_HUB))
	if LocalizationManager.locale_changed.is_connected(_on_locale_changed) == false:
		LocalizationManager.locale_changed.connect(_on_locale_changed)
	_apply_translations()

func _on_create_pressed() -> void:
	create_button.disabled = true
	status_label.text = _tx("ui.hero_creation.status.generating", "Generating hero...")

	var response: Dictionary = await ApiClient.create_hero("")
	create_button.disabled = false

	if not bool(response.get("ok", false)):
		var err_msg: String = str(response.get("message", response.get("error", "Request failed")))
		status_label.text = _txf("ui.hero_creation.status.failed_reason", "Generation failed: %s", [err_msg])
		return

	var created: Dictionary = _extract_hero(response.get("data", {}))
	if created.is_empty():
		status_label.text = _tx("ui.hero_creation.status.failed", "Hero generation failed")
		return

	var parsed: Dictionary = UIModels.hero_full(created)
	await HeroManager.load_heroes()

	var hero_name: String = str(parsed.get("name", "Unknown"))
	var role: String = str(parsed.get("primary_role", "-")).capitalize()
	var gen_level: int = int(parsed.get("hero_generation_level", 1))
	var skill_count: int = (parsed.get("skills", []) as Array).size()
	status_label.text = _txf("ui.hero_creation.status.generated_v2",
		"Generated: %s | Role: %s | Gen Level: %d | Skills: %d",
		[hero_name, role, gen_level, skill_count])

func _on_locale_changed(_locale_code: String) -> void:
	_apply_translations()

func _apply_translations() -> void:
	$VBox/Title.text = _tx("ui.hero_creation.title", "Hero Creation")
	$VBox/Actions/CreateButton.text = _tx("ui.common.generate", "Generate")
	$VBox/Actions/BackButton.text = _tx("ui.common.back", "Back")

func _extract_hero(data: Variant) -> Dictionary:
	if data is Dictionary:
		var parsed := data as Dictionary
		if parsed.has("result") and parsed["result"] is Dictionary:
			return (parsed["result"] as Dictionary).duplicate(true)
		return parsed.duplicate(true)
	return {}


func _extract_balance_from_response(data: Dictionary) -> float:
	if data.is_empty():
		return -1.0

	var direct_keys: PackedStringArray = ["balance", "new_balance", "currency_balance"]
	for key in direct_keys:
		if data.has(key):
			return float(data.get(key, -1.0))

	if data.has("result") and data["result"] is Dictionary:
		var result_dict := data["result"] as Dictionary
		for key in direct_keys:
			if result_dict.has(key):
				return float(result_dict.get(key, -1.0))

	if data.has("user") and data["user"] is Dictionary:
		var user_dict := data["user"] as Dictionary
		if user_dict.has("balance"):
			return float(user_dict.get("balance", -1.0))

	return -1.0
