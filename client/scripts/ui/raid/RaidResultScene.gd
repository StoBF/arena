extends Control
## RaidResultScene.gd
## Post-battle screen: outcome, contributions, rewards, boss progression.

signal back_pressed

@onready var outcome_lbl:      Label         = $VBox/Header/OutcomeLbl
@onready var summary_lbl:      Label         = $VBox/Header/SummaryLbl
@onready var boss_progress_lbl:Label         = $VBox/Header/BossProgressLbl
@onready var contributions_list: VBoxContainer = $VBox/Content/Contributions/List
@onready var rewards_list:     VBoxContainer  = $VBox/Content/Rewards/List
@onready var back_btn:         Button         = $VBox/Footer/BackBtn

var room_id: int = -1

const RARITY_COLORS: Dictionary = {
	"common":    Color(0.8, 0.8, 0.8),
	"uncommon":  Color(0.3, 0.8, 0.3),
	"rare":      Color(0.2, 0.5, 1.0),
	"epic":      Color(0.7, 0.2, 0.9),
	"legendary": Color(1.0, 0.6, 0.0),
	"mythic":    Color(0.9, 0.1, 0.1),
}

func _ready() -> void:
	back_btn.pressed.connect(func(): emit_signal("back_pressed"))
	if room_id > 0:
		_load()

func initialize(p_room_id: int) -> void:
	room_id = p_room_id

func _load() -> void:
	outcome_lbl.text = "Loading result..."
	var api = ApiClient.new()
	add_child(api)
	var result = await api.get_raid_result(room_id)
	api.queue_free()

	if result.has("error"):
		outcome_lbl.text = "Error loading result."
		return

	_populate_header(result)
	_populate_contributions(result.get("contributions", []))
	_populate_rewards(result.get("rewards", []))

func _populate_header(data: Dictionary) -> void:
	var outcome = data.get("outcome", "unknown")
	if outcome == "victory":
		outcome_lbl.text = "🏆 VICTORY!"
		outcome_lbl.add_theme_color_override("font_color", Color(0.2, 1.0, 0.2))
	else:
		outcome_lbl.text = "💀 DEFEAT"
		outcome_lbl.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2))

	var s = data.get("summary", {})
	summary_lbl.text = "Ticks: %d  |  Phases broken: %d  |  Boss HP remaining: %.1f%%  |  Heroes alive: %d" % [
		s.get("total_ticks", 0),
		s.get("phases_broken", 0),
		s.get("boss_hp_pct", 0.0) * 100.0,
		s.get("heroes_alive", 0),
	]

	var xp_gained   = data.get("boss_xp_gained", 0)
	var lvl_before  = data.get("level_before",   0)
	var lvl_after   = data.get("level_after",    0)
	var mutation    = data.get("mutation_gained", "")
	if xp_gained > 0:
		boss_progress_lbl.text = "Boss gained %d XP  (Lv.%d → %d)%s" % [
			xp_gained, lvl_before, lvl_after,
			"  ⚠ NEW MUTATION: %s" % mutation if mutation else ""
		]
		boss_progress_lbl.add_theme_color_override("font_color", Color(1.0, 0.5, 0.0))
	else:
		boss_progress_lbl.text = ""

func _populate_contributions(contribs: Array) -> void:
	for ch in contributions_list.get_children():
		ch.queue_free()

	var header = Label.new()
	header.text = "Hero         Damage    Taken  Kills  Score  Contrib%  MVP"
	contributions_list.add_child(header)

	for c in contribs:
		var lbl = Label.new()
		var mvp = "⭐" if c.get("is_mvp", false) else ""
		lbl.text = "Hero#%d    %d  %d  %d  %.0f  %.1f%%  %s" % [
			c.get("hero_id", 0),
			c.get("damage_dealt", 0),
			c.get("damage_taken", 0),
			c.get("kills", 0),
			c.get("contribution_score", 0.0),
			c.get("contribution_pct", 0.0),
			mvp,
		]
		lbl.add_theme_font_size_override("font_size", 12)
		contributions_list.add_child(lbl)

func _populate_rewards(rewards: Array) -> void:
	for ch in rewards_list.get_children():
		ch.queue_free()

	if rewards.is_empty():
		var lbl = Label.new()
		lbl.text = "No items dropped."
		rewards_list.add_child(lbl)
		return

	for r in rewards:
		var hbox = HBoxContainer.new()
		var lbl  = Label.new()
		var rarity = r.get("rarity", "common")
		var owner_tag = ""
		if r.get("clan_id"):
			owner_tag = " [Clan]"
		var qty = r.get("quantity", 1)
		lbl.text = "%s%s ×%d%s" % [
			r.get("display_name", "?"), owner_tag, qty,
			"  ★ ULTRA RARE" if r.get("is_ultra_rare", false) else ""
		]
		lbl.add_theme_color_override("font_color",
			RARITY_COLORS.get(rarity, Color.WHITE))
		lbl.add_theme_font_size_override("font_size", 13)
		hbox.add_child(lbl)
		rewards_list.add_child(hbox)
