extends Control
class_name MainMenuScreen

# UI Elements
@onready var heroes_button         = $CanvasLayer/MarginContainer/HBoxContainer2/VBoxContainer2/HeroesButton
@onready var auction_button        = $CanvasLayer/MarginContainer/HBoxContainer2/VBoxContainer2/AuctionButton
@onready var inventory_button      = $CanvasLayer/MarginContainer/HBoxContainer2/VBoxContainer2/InventoryButton
@onready var to_battle_button      = $CanvasLayer/MarginContainer/HBoxContainer2/VBoxContainer2/ToBattleButton
@onready var deleted_heroes_button = $CanvasLayer/MarginContainer/HBoxContainer2/VBoxContainer2/DeletedHeroesButton
@onready var settings_button       = $CanvasLayer/MarginContainer/HBoxContainer2/StatsContainer/SettingsButton
@onready var exit_button           = $CanvasLayer/MarginContainer/HBoxContainer2/StatsContainer/ExitButton
@onready var chat_box              = $CanvasLayer/MarginContainer/HBoxContainer2/VBoxContainer2/Control/ChatBox
@onready var nickname_label_title  = $CanvasLayer/MarginContainer/VBoxContainer/HBoxContainer/GridContainer/NicknameLabelTitle
@onready var nickname_label        = $CanvasLayer/MarginContainer/VBoxContainer/HBoxContainer/GridContainer/NicknameLabel
@onready var currency_label_title  = $CanvasLayer/MarginContainer/VBoxContainer/HBoxContainer/GridContainer/CurrencyGridContainer/CurrencyLabelTitle
@onready var currency_label        = $CanvasLayer/MarginContainer/VBoxContainer/HBoxContainer/GridContainer/CurrencyGridContainer/CurrencyLabel
@onready var hero_icons_container  = $CanvasLayer/MarginContainer/VBoxContainer/HBoxContainer/HeroPanel/GridContainer

# Data storage for heroes
var heroes_data: Array = []
var _top_bar: TopBar = null

func _ready():
	print("[MainMenu] _ready() START")

	# --- TopBar (no back button on MainMenu, but show nav) ---
	_top_bar = TopBar.add_to(self, false, true)

	# Debug log to verify initialization
	_log_node("ChatBox", chat_box)
	_log_node("HeroesButton", heroes_button)
	_log_node("NicknameLabelTitle", nickname_label_title)
	_log_node("CurrencyLabelTitle", currency_label_title)
	_log_node("HeroIconsContainer", hero_icons_container)

	# Setup client locale with fallback to English
	var lang = OS.get_locale_language()
	if not ["en", "pl", "uk"].has(lang):
		lang = "en"
	TranslationServer.set_locale(lang)
	Localization.connect("locale_changed", Callable(self, "_localize_ui"))

	# Connect UI signals (with null checks)
	if heroes_button:
		heroes_button.pressed.connect(_on_create_hero_pressed)
	if auction_button:
		auction_button.pressed.connect(_on_auction_pressed)
	if to_battle_button:
		to_battle_button.pressed.connect(_on_battle_pressed)
	if deleted_heroes_button:
		deleted_heroes_button.pressed.connect(_on_deleted_pressed)
	if exit_button:
		exit_button.pressed.connect(_on_exit_pressed)
	if inventory_button:
		inventory_button.pressed.connect(_on_inventory_pressed)
	if settings_button:
		settings_button.pressed.connect(_on_settings_pressed)
	if not AppState.auction_lot_requested.is_connected(Callable(self, "_on_auction_lot_requested")):
		AppState.auction_lot_requested.connect(Callable(self, "_on_auction_lot_requested"))

	# Listen for cached user data updates (TopBar also listens)
	AppState.user_data_updated.connect(_on_user_data_updated)

	# Localize UI texts
	_localize_ui()

	# Fetch heroes list from server
	_load_heroes()

	# Load user data to display nickname and balance
	_load_user()

	# If returning from hero creation, display the newly created hero
	if not AppState.last_created_hero.is_empty():
		_display_hero_info(AppState.last_created_hero)
		send_chat_message("system", "[System] New hero generated: %s" % AppState.last_created_hero.get("name", "Unknown"))
		AppState.last_created_hero.clear()

	print("[MainMenu] _ready() DONE")


## Helper: log whether a node was found
func _log_node(label: String, node) -> void:
	if node:
		print("[MainMenu] ✓ %s found" % label)
	else:
		print("[MainMenu] ✗ %s is NULL — check NodePath" % label)

func _localize_ui():
	# Titles with fallback translations
	if nickname_label_title:
		nickname_label_title.text  = tr("nickname") if tr("nickname") != "nickname" else "Nickname"
	if currency_label_title:
		currency_label_title.text  = tr("currency") if tr("currency") != "currency" else "Currency"
	# Main buttons with fallback translations
	if heroes_button:
		heroes_button.text         = tr("heroes") if tr("heroes") != "heroes" else "Heroes"
	if auction_button:
		auction_button.text        = tr("auction") if tr("auction") != "auction" else "Auction"
	if to_battle_button:
		to_battle_button.text      = tr("to_battle") if tr("to_battle") != "to_battle" else "To Battle"
	if inventory_button:
		inventory_button.text      = tr("inventory") if tr("inventory") != "inventory" else "Inventory"
	if deleted_heroes_button:
		deleted_heroes_button.text = tr("deleted_heroes") if tr("deleted_heroes") != "deleted_heroes" else "Deleted Heroes"
	if settings_button:
		settings_button.text       = tr("settings") if tr("settings") != "settings" else "Settings"
	if exit_button:
		exit_button.text           = tr("exit") if tr("exit") != "exit" else "Exit"

func _on_heroes_loaded(result: int, code: int, headers: PackedStringArray, body: PackedByteArray):
	print("[MainMenu] _on_heroes_loaded result=%d code=%d body_size=%d" % [result, code, body.size()])
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		var json = JSON.new()
		var err = json.parse(body.get_string_from_utf8())
		if err == OK:
			var parsed = json.data
			# Backend returns HeroesPaginatedResponse: { result: [...], total: N }
			if typeof(parsed) == TYPE_DICTIONARY and parsed.has("result"):
				heroes_data = parsed["result"]
			elif typeof(parsed) == TYPE_ARRAY:
				heroes_data = parsed
			else:
				heroes_data = []
			print("[MainMenu] Parsed %d heroes" % heroes_data.size())
			# Populate icon container
			if hero_icons_container:
				for child in hero_icons_container.get_children():
					child.queue_free()
				var scene = preload("res://scenes/HeroIcon.tscn")
				for hero in heroes_data:
					var icon = scene.instantiate() as HeroIcon
					icon.set_hero_data(hero)
					# Connect the custom signal (hero_selected) for click handling
					icon.hero_selected.connect(_on_hero_icon_pressed)
					hero_icons_container.add_child(icon)
				print("[MainMenu] Added %d hero icons to grid" % heroes_data.size())
			else:
				print("[MainMenu] ERROR hero_icons_container is NULL")
			# Display first hero info & select it
			if heroes_data.size() > 0:
				_display_hero_info(heroes_data[0])
				AppState.current_hero_id = heroes_data[0].get("id", -1)
				send_chat_message("system", "[System] Loaded %d heroes" % heroes_data.size())
			return
		print("[MainMenu] Heroes JSON parse error: ", err)
	print("[MainMenu] Failed to load heroes: result=%d code=%d" % [result, code])
	UIUtils.show_error(tr("load_heroes_failed") if tr("load_heroes_failed") != "load_heroes_failed" else "Failed to load heroes")
	send_chat_message("system", "[System] Failed to load heroes (HTTP %d)" % code)

func _on_hero_icon_pressed(hero_id) -> void:
	print("[MainMenu] Hero icon pressed: id=%s" % str(hero_id))
	AppState.current_hero_id = hero_id
	for hero in heroes_data:
		if hero.get("id") == hero_id:
			_display_hero_info(hero)
			send_chat_message("system", "[System] Selected hero: %s" % hero.get("name", "?"))
			return
	print("[MainMenu] Hero with ID %s not found in heroes_data" % str(hero_id))

func _display_hero_info(hero: Dictionary) -> void:
	# Cache stats grid for performance
	var stats_grid = $CanvasLayer/MarginContainer/HBoxContainer2/StatsContainer/GridContainer
	var perks_grid = $CanvasLayer/MarginContainer/HBoxContainer2/StatsContainer/PerckGrid

	# Update stats labels with fallback values
	stats_grid.get_node("NameValue").text = hero.get("name", "Unknown")
	stats_grid.get_node("LevelValue").text = str(hero.get("level", 0))
	stats_grid.get_node("XPLabel").text = str(hero.get("xp", 0))
	stats_grid.get_node("LevelGenerationLabel").text = str(hero.get("generation", 0))
	stats_grid.get_node("StrengthLabel").text = str(hero.get("strength", 0))
	stats_grid.get_node("SpeedLabel").text = str(hero.get("speed", 0))
	stats_grid.get_node("AgilityLabel").text = str(hero.get("agility", 0))
	stats_grid.get_node("EnduranceLabel").text = str(hero.get("endurance", 0))
	stats_grid.get_node("HealthLabel").text = str(hero.get("health", 0))
	stats_grid.get_node("DefenseLabel").text = str(hero.get("defense", 0))
	stats_grid.get_node("LuckLabel").text = str(hero.get("luck", 0))
	stats_grid.get_node("TrainingLabel").text = str(hero.get("training", 0))
	stats_grid.get_node("FOVLabel").text = str(hero.get("fov", 0))

	# Update perks
	for i in range(1, 11):
		var perk_label = perks_grid.get_node("perck_" + str(i))
		var perks = hero.get("perks", [])
		perk_label.text = perks[i-1] if i <= perks.size() else ""

func _on_generate_response(result: int, code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if result == HTTPRequest.RESULT_SUCCESS and code in [200, 201]:
		UIUtils.show_success(tr("generate_success") if tr("generate_success") != "generate_success" else "Hero generated successfully")
		send_chat_message("system", "[System] Hero generated successfully")
		_load_heroes()
		return
	var msg = ""
	var json = JSON.new()
	var err = json.parse(body.get_string_from_utf8())
	if err == OK and json.data.has("detail"):
		msg = json.data.detail
	else:
		msg = tr("generate_failed") if tr("generate_failed") != "generate_failed" else "Failed to generate hero"
	UIUtils.show_error(msg)
	send_chat_message("system", "[System] Hero generation failed: %s" % msg)

func _on_create_hero_pressed():
	Nav.go("GenerateHero")

func _on_auction_pressed():
	Nav.go("Auction")

func _on_auction_lot_requested(lot_id: int) -> void:
	if lot_id <= 0:
		return
	Nav.go("Auction")

func _on_inventory_pressed():
	Nav.go("Inventory")

func _on_settings_pressed():
	Nav.go("Settings")

func _on_battle_pressed():
	Nav.go("Battle")

func _on_deleted_pressed():
	# DeletedHeroes scene not implemented yet
	UIUtils.show_error("Deleted Heroes is not available yet")

func _on_exit_pressed():
	get_tree().quit()

func _load_user():
	var req = Network.request("/auth/me", HTTPClient.METHOD_GET)
	req.request_completed.connect(_on_user_loaded)

func _load_heroes():
	var req = Network.request("/heroes/", HTTPClient.METHOD_GET)
	req.request_completed.connect(_on_heroes_loaded)

func _on_user_loaded(result: int, code: int, headers: PackedStringArray, body: PackedByteArray):
	print("[MainMenu] _on_user_loaded result=%d code=%d body_size=%d" % [result, code, body.size()])
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		var json = JSON.new()
		var err = json.parse(body.get_string_from_utf8())
		if err == OK:
			var user = json.data
			# Cache in AppState so TopBar (and any scene) can display it
			AppState.set_user_data(user)
			# Also update local labels
			_on_user_data_updated()
			send_chat_message("system", "[System] User loaded: %s" % user.get("username", "Unknown"))
			return
		print("[MainMenu] User JSON parse error: ", err)
	print("[MainMenu] Failed to load user: result=%d code=%d body=%s" % [result, code, body.get_string_from_utf8().left(200)])
	UIUtils.show_error(tr("load_user_failed") if tr("load_user_failed") != "load_user_failed" else "Failed to load user data")
	send_chat_message("system", "[System] Failed to load user data (HTTP %d)" % code)


## Called when AppState.user_data_updated fires (or directly after /auth/me success)
func _on_user_data_updated() -> void:
	if nickname_label:
		nickname_label.text = AppState.username if not AppState.username.is_empty() else "Unknown"
	else:
		print("[MainMenu] WARN nickname_label is NULL")
	if currency_label:
		currency_label.text = str(AppState.balance)
	else:
		print("[MainMenu] WARN currency_label is NULL")

func send_chat_message(channel: String, message: String):
	if chat_box and chat_box.has_method("AddLog"):
		chat_box.call("AddLog", channel, message)
	else:
		print("Failed to send chat message: ChatBox not initialized or AddLog missing")
