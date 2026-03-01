## Reusable top navigation bar included in every game scene.
## Displays: Back button | Nickname | Currency | Quick-nav buttons.
## Usage:  TopBar.add_to(self)  in any scene's _ready().
extends PanelContainer
class_name TopBar

signal back_pressed

@onready var back_button: Button = $HBox/BackButton
@onready var nickname_label: Label = $HBox/NicknameLabel
@onready var currency_label: Label = $HBox/CurrencyLabel
@onready var main_menu_btn: Button = $HBox/NavButtons/MainMenuBtn
@onready var auction_btn: Button = $HBox/NavButtons/AuctionBtn
@onready var inventory_btn: Button = $HBox/NavButtons/InventoryBtn
@onready var battle_btn: Button = $HBox/NavButtons/BattleBtn
@onready var settings_btn: Button = $HBox/NavButtons/SettingsBtn

# Whether the Back button should be visible (hide on MainMenu itself)
var show_back := true : set = _set_show_back
# Whether quick-nav buttons should be visible
var show_nav := true : set = _set_show_nav

## Static factory: adds a TopBar to the given parent at the top.
## Returns the TopBar instance for optional customization.
static func add_to(parent: Node, p_show_back := true, p_show_nav := true) -> TopBar:
	var bar: TopBar = preload("res://scenes/ui/TopBar.tscn").instantiate()
	bar.show_back = p_show_back
	bar.show_nav = p_show_nav
	parent.add_child(bar)
	parent.move_child(bar, 0)
	print("[TopBar] Added to scene '%s'" % parent.name)
	return bar


func _ready() -> void:
	# --- button connections ---
	back_button.pressed.connect(_on_back)
	main_menu_btn.pressed.connect(func(): _navigate("MainMenu"))
	auction_btn.pressed.connect(func(): _navigate("Auction"))
	inventory_btn.pressed.connect(func(): _navigate("Inventory"))
	battle_btn.pressed.connect(func(): _navigate("Battle"))
	settings_btn.pressed.connect(func(): _navigate("Settings"))

	# --- initial data ---
	_refresh_display()
	AppState.user_data_updated.connect(_refresh_display)
	Localization.locale_changed.connect(_localize)
	_localize()

	# Apply visibility flags
	_set_show_back(show_back)
	_set_show_nav(show_nav)


func _refresh_display() -> void:
	if nickname_label:
		nickname_label.text = AppState.username if not AppState.username.is_empty() else "—"
	if currency_label:
		currency_label.text = "%s %.0f" % [_coin_icon(), AppState.balance]


func _navigate(scene_name: String) -> void:
	print("[TopBar] Navigate → %s" % scene_name)
	Nav.go(scene_name)


func _on_back() -> void:
	print("[TopBar] Back pressed")
	back_pressed.emit()
	Nav.go_main_menu()


func _localize() -> void:
	if back_button:
		back_button.text = Localization.t("back") if Localization.has_key("back") else "← Back"
	if main_menu_btn:
		main_menu_btn.text = Localization.t("main_menu") if Localization.has_key("main_menu") else "Menu"
	if auction_btn:
		auction_btn.text = Localization.t("auction") if Localization.has_key("auction") else "Auction"
	if inventory_btn:
		inventory_btn.text = Localization.t("inventory") if Localization.has_key("inventory") else "Inventory"
	if battle_btn:
		battle_btn.text = Localization.t("to_battle") if Localization.has_key("to_battle") else "Battle"
	if settings_btn:
		settings_btn.text = Localization.t("settings") if Localization.has_key("settings") else "Settings"


func _set_show_back(val: bool) -> void:
	show_back = val
	if back_button:
		back_button.visible = val

func _set_show_nav(val: bool) -> void:
	show_nav = val
	if is_inside_tree():
		$HBox/NavButtons.visible = val


static func _coin_icon() -> String:
	return "💰"
