extends Control

@onready var player_hero_label: Label = $VBox/Body/PlayerHeroPanel/PlayerHeroLabel
@onready var enemy_hero_label: Label = $VBox/Body/EnemyHeroPanel/EnemyHeroLabel
@onready var start_button: Button = $VBox/Footer/StartBattleButton

var _player_data: Node = null

func _ready() -> void:
	$VBox/Header/BackButton.pressed.connect(func(): EventBus.emit_scene_changed("PlayerHub"))
	start_button.pressed.connect(_on_start_pressed)
	if LocalizationManager.locale_changed.is_connected(_on_locale_changed) == false:
		LocalizationManager.locale_changed.connect(_on_locale_changed)
	if has_node("/root/EventBus") and EventBus.hero_selected.is_connected(_on_eventbus_hero_selected) == false:
		EventBus.hero_selected.connect(_on_eventbus_hero_selected)
	_apply_translations()
	enemy_hero_label.text = tr("ui.battle.enemy_training")

func bind_controllers(player_data: Node, _inventory_controller: Node, _craft_controller: Node) -> void:
	_player_data = player_data
	_on_hero_selected(AppState.selected_hero)

func _on_eventbus_hero_selected(_hero_id: int) -> void:
	_on_hero_selected(AppState.selected_hero)

func _on_hero_selected(hero: Dictionary) -> void:
	if hero.is_empty():
		player_hero_label.text = tr("ui.battle.player_none")
		start_button.disabled = true
	else:
		player_hero_label.text = tr("ui.battle.player_name") % str(hero.get("name", "Hero"))
		start_button.disabled = false

func _on_start_pressed() -> void:
	$VBox/Footer/Status.text = tr("ui.battle.started")

func _on_locale_changed(_locale_code: String) -> void:
	_apply_translations()
	_on_hero_selected(_player_data.get_selected_hero() if _player_data != null else {})
	enemy_hero_label.text = tr("ui.battle.enemy_training")

func _apply_translations() -> void:
	$VBox/Header/BackButton.text = tr("ui.common.back")
	$VBox/Header/Title.text = tr("ui.battle.title")
	start_button.text = tr("ui.battle.start")
