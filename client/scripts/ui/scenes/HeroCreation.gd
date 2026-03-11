extends Control

signal open_player_hub

@onready var status_label: Label = $VBox/Status
@onready var name_input: LineEdit = $VBox/NameInput
@onready var balance_label: Label = $VBox/BalanceLabel
@onready var investment_slider: HSlider = $VBox/InvestmentSlider
@onready var investment_value_label: Label = $VBox/InvestmentValue
@onready var create_button: Button = $VBox/Actions/CreateButton

var _player_data: Node = null
var _last_create_response_data: Dictionary = {}

func _ready() -> void:
	create_button.pressed.connect(_on_create_pressed)
	$VBox/Actions/BackButton.pressed.connect(func(): open_player_hub.emit())
	investment_slider.value_changed.connect(_on_investment_changed)
	if LocalizationManager.locale_changed.is_connected(_on_locale_changed) == false:
		LocalizationManager.locale_changed.connect(_on_locale_changed)
	if AppState.user_data_updated.is_connected(_on_user_data_updated) == false:
		AppState.user_data_updated.connect(_on_user_data_updated)
	_apply_translations()
	_refresh_balance_and_slider_limits()
	_on_investment_changed(investment_slider.value)

func bind_controllers(player_data: Node, _inventory_controller: Node, _craft_controller: Node) -> void:
	_player_data = player_data

func _on_create_pressed() -> void:
	var hero_name: String = name_input.text.strip_edges()
	if hero_name.is_empty():
		status_label.text = tr("ui.hero_creation.status.enter_name")
		return

	var investment: int = int(investment_slider.value)
	if investment < 0:
		status_label.text = tr("ui.hero_creation.status.invalid_investment")
		return

	if AppState.balance > 0.0 and float(investment) > AppState.balance:
		status_label.text = tr("ui.hero_creation.status.not_enough_balance")
		return

	create_button.disabled = true
	status_label.text = tr("ui.hero_creation.status.generating")
	var previous_balance: float = AppState.balance

	var created: Dictionary = await _create_hero_via_api(hero_name, investment)
	create_button.disabled = false

	if created.is_empty():
		status_label.text = tr("ui.hero_creation.status.failed")
		return

	var rarity_text: String = _derive_rarity(created, investment)
	await HeroManager.load_heroes()
	await _refresh_profile_from_server()
	status_label.text = tr("ui.hero_creation.status.generated") % [
		str(created.get("name", hero_name)),
		rarity_text,
		previous_balance,
		AppState.balance,
	]
	name_input.clear()

func _on_investment_changed(value: float) -> void:
	investment_value_label.text = tr("ui.hero_creation.investment_value") % int(value)

func _on_locale_changed(_locale_code: String) -> void:
	_apply_translations()
	_refresh_balance_and_slider_limits()
	_on_investment_changed(investment_slider.value)

func _apply_translations() -> void:
	$VBox/Title.text = tr("ui.hero_creation.title")
	name_input.placeholder_text = tr("ui.hero_creation.name_placeholder")
	$VBox/InvestmentLabel.text = tr("ui.hero_creation.investment")
	$VBox/Actions/CreateButton.text = tr("ui.common.generate")
	$VBox/Actions/BackButton.text = tr("ui.common.back")

func _on_user_data_updated() -> void:
	_refresh_balance_and_slider_limits()

func _refresh_balance_and_slider_limits() -> void:
	var balance_value: float = maxi(0.0, AppState.balance)
	balance_label.text = tr("ui.hero_creation.balance") % balance_value
	if balance_value <= 0.0:
		investment_slider.max_value = 0.0
		investment_slider.value = 0.0
	else:
		investment_slider.max_value = balance_value
		if investment_slider.value > balance_value:
			investment_slider.value = balance_value

func _create_hero_via_api(hero_name: String, investment: int) -> Dictionary:
	_last_create_response_data = {}
	var response: Dictionary = await ApiClient.create_hero(hero_name, investment)

	if bool(response.get("ok", false)):
		var data_success: Variant = response.get("data", {})
		if data_success is Dictionary:
			_last_create_response_data = (data_success as Dictionary).duplicate(true)
		return _extract_hero(data_success)

	var err_message := str(response.get("message", "Request failed"))
	status_label.text = tr("ui.hero_creation.status.failed_reason") % err_message
	return {}

func _extract_hero(data: Variant) -> Dictionary:
	if data is Dictionary:
		var parsed := data as Dictionary
		if parsed.has("result") and parsed["result"] is Dictionary:
			return (parsed["result"] as Dictionary).duplicate(true)
		return parsed.duplicate(true)
	return {}

func _generation_from_investment(investment: int) -> int:
	if investment >= 800:
		return 5
	if investment >= 500:
		return 4
	if investment >= 300:
		return 3
	if investment >= 150:
		return 2
	return 1

func _derive_rarity(hero: Dictionary, investment: int) -> String:
	if hero.has("rarity"):
		return str(hero.get("rarity", "Common"))
	var generation: int = int(hero.get("generation", _generation_from_investment(investment)))
	if generation >= 5:
		return "Legendary"
	if generation == 4:
		return "Epic"
	if generation == 3:
		return "Rare"
	if generation == 2:
		return "Uncommon"
	return "Common"

func _refresh_profile_from_server() -> void:
	var response: Dictionary = await ApiClient.get_user()
	if bool(response.get("ok", false)) == false:
		return
	var parsed: Variant = response.get("data", {})
	if parsed is Dictionary:
		var profile := parsed as Dictionary
		if profile.has("result") and profile["result"] is Dictionary:
			AppState.set_user_data((profile["result"] as Dictionary).duplicate(true))
			return
		AppState.set_user_data(profile.duplicate(true))

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
