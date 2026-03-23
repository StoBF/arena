extends PanelContainer

## Structured hero summary for hub overlay (data from UIModels.hero_full).

@onready var name_label: Label = $Margin/Scroll/RootVBox/SectionIdentity/NameLabel
@onready var level_label: Label = $Margin/Scroll/RootVBox/SectionIdentity/LevelLabel
@onready var role_label: Label = $Margin/Scroll/RootVBox/SectionIdentity/RoleLabel
@onready var hp_label: Label = $Margin/Scroll/RootVBox/SectionCombat/Grid/HPValue
@onready var atk_label: Label = $Margin/Scroll/RootVBox/SectionCombat/Grid/AtkValue
@onready var def_label: Label = $Margin/Scroll/RootVBox/SectionCombat/Grid/DefValue
@onready var spd_label: Label = $Margin/Scroll/RootVBox/SectionCombat/Grid/SpdValue
@onready var traits_label: Label = $Margin/Scroll/RootVBox/SectionTraits/TraitsValue
@onready var equip_label: Label = $Margin/Scroll/RootVBox/SectionEquipment/EquipValue
@onready var status_label: Label = $Margin/Scroll/RootVBox/SectionStatus/StatusValue
@onready var btn_inventory: Button = $Margin/Scroll/RootVBox/ActionRow/BtnInventory
@onready var btn_auction: Button = $Margin/Scroll/RootVBox/ActionRow/BtnAuction
@onready var btn_battle: Button = $Margin/Scroll/RootVBox/ActionRow/BtnBattle

signal inventory_pressed()
signal auction_pressed()
signal battle_prep_pressed()

func _ready() -> void:
	btn_inventory.pressed.connect(func() -> void: inventory_pressed.emit())
	btn_auction.pressed.connect(func() -> void: auction_pressed.emit())
	btn_battle.pressed.connect(func() -> void: battle_prep_pressed.emit())

func set_hero(hero: Dictionary) -> void:
	if hero.is_empty():
		_clear()
		return
	var p: Dictionary = UIModels.hero_full(hero)
	name_label.text = str(p.get("name", "—"))
	level_label.text = "Gen %d  ·  v%d" % [int(p.get("hero_generation_level", 1)), int(p.get("generation_version", 2))]
	var primary: String = str(p.get("primary_role", "")).capitalize()
	var secondary: String = str(p.get("secondary_role", "")).capitalize()
	if primary.is_empty() or primary == "None":
		primary = "—"
	var role_text: String = primary
	if not secondary.is_empty() and secondary != "None" and secondary != primary:
		role_text += " / " + secondary
	role_label.text = role_text
	var stats: Dictionary = p.get("stats", {}) as Dictionary
	var derived: Dictionary = p.get("derived_stats", {}) as Dictionary
	hp_label.text = "%d / %d" % [int(p.get("current_hp", 0)), int(derived.get("max_hp", 100))]
	atk_label.text = str(int(stats.get("strength", 0)))
	def_label.text = str(int(stats.get("resilience", 0)))
	spd_label.text = str(int(derived.get("initiative", 0)))
	var tags: Array = p.get("tags", []) as Array
	var tag_labels: PackedStringArray = UIModels.top_tags(tags, 6)
	traits_label.text = ", ".join(tag_labels) if not tag_labels.is_empty() else "—"
	equip_label.text = _equipment_summary(hero)
	var cond: String = str(p.get("condition", "healthy")).capitalize()
	if bool(p.get("is_on_auction", false)):
		cond += "  ·  On auction"
	status_label.text = cond

func _equipment_summary(hero: Dictionary) -> String:
	if not hero.has("equipment") or not (hero["equipment"] is Dictionary):
		return "—"
	var eq: Dictionary = hero["equipment"] as Dictionary
	var parts: PackedStringArray = []
	for k in ["shirt", "pants", "shoes", "weapon"]:
		if eq.has(k) and eq[k] is Dictionary:
			var it: Dictionary = eq[k] as Dictionary
			var n: String = str(it.get("name", ""))
			if not n.is_empty():
				parts.append(n)
	return ", ".join(parts) if not parts.is_empty() else "—"

func _clear() -> void:
	name_label.text = "—"
	level_label.text = ""
	role_label.text = ""
	hp_label.text = "—"
	atk_label.text = "—"
	def_label.text = "—"
	spd_label.text = "—"
	traits_label.text = "—"
	equip_label.text = "—"
	status_label.text = "—"
