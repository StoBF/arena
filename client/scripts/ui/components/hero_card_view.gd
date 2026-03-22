extends PanelContainer


signal delete_requested(hero_id: int)
signal auction_requested(hero_id: int)

@onready var portrait: TextureRect = $Margin/Root/PortraitFrame/Portrait
@onready var name_label: Label = $Margin/Root/Content/NameLabel
@onready var meta_label: Label = $Margin/Root/Content/MetaLabel
@onready var stats_label: Label = $Margin/Root/Content/StatsLabel
@onready var auction_button: Button = $Margin/Root/Content/ActionRow/AuctionButton
@onready var delete_button: Button = $Margin/Root/Content/ActionRow/DeleteButton

var _hero_id: int = -1

func _ready() -> void:
	auction_button.pressed.connect(func() -> void: auction_requested.emit(_hero_id))
	delete_button.pressed.connect(func() -> void: delete_requested.emit(_hero_id))
	auction_button.tooltip_text = "List this hero for auction."
	delete_button.tooltip_text = "Permanently delete this hero. This cannot be undone."

func set_hero(hero: Dictionary) -> void:
	_hero_id = int(hero.get("id", -1))
	name_label.text = str(hero.get("name", "Hero"))

	# Roles
	var primary: String = str(hero.get("primary_role", "")).capitalize()
	var secondary: String = str(hero.get("secondary_role", "")).capitalize()
	if primary.is_empty() or primary == "None":
		primary = "-"
	var role_text: String = primary
	if not secondary.is_empty() and secondary != "None" and secondary != primary:
		role_text += " / " + secondary
	meta_label.text = role_text + "  |  Gen %s" % str(hero.get("hero_generation_level", "1"))

	# Compact summary: tags + skill count
	stats_label.text = _build_summary(hero)

	var portrait_path: String = str(hero.get("portrait", ""))
	if not portrait_path.is_empty() and ResourceLoader.exists(portrait_path):
		portrait.texture = load(portrait_path)
	else:
		portrait.texture = null

func set_hero_data(hero: Dictionary, _selected: bool = false) -> void:
	set_hero(hero)

func _build_summary(hero: Dictionary) -> String:
	var parts: PackedStringArray = []

	# Top tags (2-4)
	var tags: Array = []
	if hero.has("tags") and hero["tags"] is Array:
		tags = hero["tags"] as Array
	var tag_labels: PackedStringArray = UIModels.top_tags(tags, 3)
	if not tag_labels.is_empty():
		parts.append(", ".join(tag_labels))

	# Skill family summary
	var skills: Array = []
	if hero.has("skills") and hero["skills"] is Array:
		skills = hero["skills"] as Array
	var skill_summary: String = UIModels.skill_family_summary(skills)
	parts.append(skill_summary)

	return "\n".join(parts)
