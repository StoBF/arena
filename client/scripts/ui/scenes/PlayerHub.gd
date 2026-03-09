extends Control

signal open_storage
signal open_auction
signal open_battle_room
signal open_settings
signal open_hero_creation

const HERO_SLOT_SCENE := preload("res://scenes/ui/components/HeroSlot.tscn")

@onready var hero_slots_container: HBoxContainer = $VBox/HeroSlots

var _player_data: Node = null

func _ready() -> void:
	$VBox/Buttons/StorageButton.pressed.connect(func(): open_storage.emit())
	$VBox/Buttons/AuctionButton.pressed.connect(func(): open_auction.emit())
	$VBox/Buttons/BattleButton.pressed.connect(func(): open_battle_room.emit())
	$VBox/Buttons/SettingsButton.pressed.connect(func(): open_settings.emit())
	$VBox/Buttons/HeroCreationButton.pressed.connect(func(): open_hero_creation.emit())

func bind_controllers(player_data: Node, _inventory_controller: Node, _craft_controller: Node) -> void:
	_player_data = player_data
	if _player_data.heroes_changed.is_connected(_refresh_hero_slots) == false:
		_player_data.heroes_changed.connect(_refresh_hero_slots)
	if _player_data.hero_selected.is_connected(_on_hero_selected) == false:
		_player_data.hero_selected.connect(_on_hero_selected)
	_refresh_hero_slots(_player_data.get_heroes())
	_on_hero_selected(_player_data.get_selected_hero())

func _refresh_hero_slots(_heroes: Array) -> void:
	for child in hero_slots_container.get_children():
		child.queue_free()
	var slots: Array = _player_data.get_hero_slots()
	for i: int in range(slots.size()):
		var slot = HERO_SLOT_SCENE.instantiate()
		slot.slot_index = i
		slot.set_hero_data(slots[i] as Dictionary, _is_selected(slots[i] as Dictionary))
		slot.hero_slot_selected.connect(_on_hero_slot_selected)
		hero_slots_container.add_child(slot)

func _on_hero_slot_selected(index: int) -> void:
	_player_data.select_hero_by_index(index)

func _on_hero_selected(_hero: Dictionary) -> void:
	_refresh_hero_slots(_player_data.get_heroes())

func _is_selected(hero: Dictionary) -> bool:
	if hero.is_empty():
		return false
	var selected: Dictionary = _player_data.get_selected_hero()
	if selected.is_empty():
		return false
	return str(hero.get("id", "")) == str(selected.get("id", ""))
