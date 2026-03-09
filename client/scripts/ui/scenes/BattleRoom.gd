extends Control

signal open_player_hub

@onready var player_hero_label: Label = $VBox/Body/PlayerHeroPanel/PlayerHeroLabel
@onready var enemy_hero_label: Label = $VBox/Body/EnemyHeroPanel/EnemyHeroLabel
@onready var start_button: Button = $VBox/Footer/StartBattleButton

var _player_data: Node = null

func _ready() -> void:
	$VBox/Header/BackButton.pressed.connect(func(): open_player_hub.emit())
	start_button.pressed.connect(_on_start_pressed)
	enemy_hero_label.text = "Enemy: Training Bot"

func bind_controllers(player_data: Node, _inventory_controller: Node, _craft_controller: Node) -> void:
	_player_data = player_data
	if _player_data.hero_selected.is_connected(_on_hero_selected) == false:
		_player_data.hero_selected.connect(_on_hero_selected)
	_on_hero_selected(_player_data.get_selected_hero())

func _on_hero_selected(hero: Dictionary) -> void:
	if hero.is_empty():
		player_hero_label.text = "Player: No hero selected"
		start_button.disabled = true
	else:
		player_hero_label.text = "Player: %s" % str(hero.get("name", "Hero"))
		start_button.disabled = false

func _on_start_pressed() -> void:
	$VBox/Footer/Status.text = "Battle started"
