extends PanelContainer

signal selected(hero_id: int)

@onready var portrait: TextureRect = $Margin/Root/PortraitFrame/Portrait
@onready var name_label: Label = $Margin/Root/Content/NameLabel
@onready var meta_label: Label = $Margin/Root/Content/MetaLabel
@onready var stats_label: Label = $Margin/Root/Content/StatsLabel
@onready var select_button: Button = $Margin/Root/Content/ActionRow/SelectButton
@onready var inspect_button: Button = $Margin/Root/Content/ActionRow/InspectButton

var _hero_id: int = -1

func _ready() -> void:
	select_button.pressed.connect(func() -> void: selected.emit(_hero_id))
	inspect_button.pressed.connect(func() -> void: selected.emit(_hero_id))

func set_hero(hero: Dictionary) -> void:
	_hero_id = int(hero.get("id", -1))
	name_label.text = str(hero.get("name", "Hero"))
	meta_label.text = "Level %s | Gen %s" % [str(hero.get("level", "-")), str(hero.get("generation", hero.get("gen", "-")))]
	stats_label.text = _build_stats(hero)
	var portrait_path: String = str(hero.get("portrait", ""))
	if portrait_path.is_empty() == false and ResourceLoader.exists(portrait_path):
		portrait.texture = load(portrait_path)
	else:
		portrait.texture = null

func set_hero_data(hero: Dictionary, _selected: bool = false) -> void:
	set_hero(hero)

func _build_stats(hero: Dictionary) -> String:
	var strength: Variant = hero.get("strength", "-")
	var agility: Variant = hero.get("agility", "-")
	var intelligence: Variant = hero.get("intelligence", "-")
	var vitality: Variant = hero.get("vitality", "-")
	if hero.has("attributes") and hero["attributes"] is Dictionary:
		var attributes := hero["attributes"] as Dictionary
		strength = attributes.get("strength", strength)
		agility = attributes.get("agility", agility)
		intelligence = attributes.get("intelligence", intelligence)
		vitality = attributes.get("vitality", vitality)
	return "STR %s  AGI %s  INT %s  VIT %s" % [str(strength), str(agility), str(intelligence), str(vitality)]
