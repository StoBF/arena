extends Control

signal open_player_hub

@onready var status_label: Label = $VBox/Status

var _player_data: Node = null

func _ready() -> void:
	$VBox/Actions/CreateButton.pressed.connect(_on_create_pressed)
	$VBox/Actions/BackButton.pressed.connect(func(): open_player_hub.emit())

func bind_controllers(player_data: Node, _inventory_controller: Node, _craft_controller: Node) -> void:
	_player_data = player_data

func _on_create_pressed() -> void:
	var name_input: LineEdit = $VBox/NameInput
	if _player_data.create_hero(name_input.text):
		status_label.text = "Hero created"
		name_input.clear()
	else:
		status_label.text = "Cannot create hero"
