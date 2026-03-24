extends Control
## RaidBossDetailScene.gd
## Shows full boss info: stats, phases, mutations, loot table, history.
## Opened from RaidBossCalendarScene.

signal create_room_requested(spawn_id: int)
signal back_pressed

@onready var boss_name_lbl:    Label        = $VBox/Header/BossName
@onready var boss_info_lbl:    Label        = $VBox/Header/BossInfo
@onready var progress_lbl:     Label        = $VBox/Header/ProgressInfo
@onready var win_streak_lbl:   Label        = $VBox/Header/WinStreak
@onready var mutations_list:   VBoxContainer = $VBox/Content/Mutations/List
@onready var phases_list:      VBoxContainer = $VBox/Content/Phases/List
@onready var loot_list:        VBoxContainer = $VBox/Content/Loot/List
@onready var history_list:     VBoxContainer = $VBox/Content/History/List
@onready var create_room_btn:  Button       = $VBox/Footer/CreateRoomBtn
@onready var back_btn:         Button       = $VBox/Footer/BackBtn
@onready var tab_bar:          TabBar       = $VBox/Content/TabBar
@onready var status_lbl:       Label        = $VBox/StatusLabel

var template_id: int = -1
var spawn_id:    int = -1

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
	create_room_btn.pressed.connect(func():
		if spawn_id > 0:
			emit_signal("create_room_requested", spawn_id)
		else:
			status_lbl.text = "No active spawn for this boss."
	)
	if template_id > 0:
		_load()

func initialize(p_template_id: int, p_spawn_id: int) -> void:
	template_id = p_template_id
	spawn_id    = p_spawn_id
	create_room_btn.disabled = spawn_id <= 0

func _load() -> void:
	status_lbl.text = "Loading..."
	var api = ApiClient.new()
	add_child(api)

	var detail = await api.get_raid_boss_detail(template_id)
	var loot   = await api.get_raid_boss_loot(template_id)
	var hist   = await api.get_raid_boss_history(template_id)
	api.queue_free()

	if detail.has("error"):
		status_lbl.text = "Error loading boss."
		return

	_populate_header(detail)
	_populate_mutations(detail.get("mutations", []))
	_populate_phases(detail.get("phases", []))
	_populate_loot(loot if loot is Array else [])
	_populate_history(hist if hist is Array else [])
	status_lbl.text = ""

func _populate_header(detail: Dictionary) -> void:
	var tmpl    = detail.get("template", {})
	var prog    = detail.get("progress", {})

	boss_name_lbl.text = tmpl.get("name", "???")
	boss_info_lbl.text = "%s | %s | %d clans | %d heroes" % [
		tmpl.get("category", "").capitalize(),
		tmpl.get("archetype", "").capitalize(),
		tmpl.get("max_clans", 1),
		tmpl.get("max_heroes", 5),
	]

	if prog:
		progress_lbl.text = "Lv.%d  Rank %d  XP %d  Victories %d" % [
			prog.get("current_level", 1),
			prog.get("rank", 0),
			0,
			prog.get("total_wins", 0),
		]
		win_streak_lbl.text = "Win streak: %d  |  Hero kills: %d" % [
			prog.get("win_streak", 0),
			prog.get("hero_kills", 0),
		]
	else:
		progress_lbl.text = "No progress data"
		win_streak_lbl.text = ""

func _populate_mutations(mutations: Array) -> void:
	for ch in mutations_list.get_children():
		ch.queue_free()
	if mutations.is_empty():
		var lbl = Label.new()
		lbl.text = "No active mutations."
		mutations_list.add_child(lbl)
		return
	for m in mutations:
		var lbl = Label.new()
		lbl.text = "⚠ %s — %s" % [m.get("name", "?"), str(m.get("effect", {}))]
		lbl.add_theme_color_override("font_color", Color(1.0, 0.6, 0.0))
		mutations_list.add_child(lbl)

func _populate_phases(phases: Array) -> void:
	for ch in phases_list.get_children():
		ch.queue_free()
	for ph in phases:
		var panel = PanelContainer.new()
		var vbox  = VBoxContainer.new()
		panel.add_child(vbox)
		var title = Label.new()
		title.text = "Phase %d: %s  (triggers at ≤%d%% HP)" % [
			ph.get("phase_number", 1),
			ph.get("name", ""),
			int(ph.get("trigger_hp_pct", 1.0) * 100),
		]
		title.add_theme_font_size_override("font_size", 14)
		vbox.add_child(title)
		var abilities = Label.new()
		abilities.text = "Abilities: " + ", ".join(ph.get("abilities", []))
		abilities.add_theme_font_size_override("font_size", 12)
		vbox.add_child(abilities)
		phases_list.add_child(panel)

func _populate_loot(loot: Array) -> void:
	for ch in loot_list.get_children():
		ch.queue_free()

	# Header
	var header = Label.new()
	header.text = "%-30s  %s    %s    %s" % ["Item", "Rarity", "Chance", "Qty"]
	header.add_theme_font_size_override("font_size", 12)
	loot_list.add_child(header)

	for entry in loot:
		var hbox   = HBoxContainer.new()
		var name_l = Label.new()
		name_l.text = entry.get("display_name", "?")
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var rarity  = entry.get("rarity", "common")
		name_l.add_theme_color_override("font_color",
			RARITY_COLORS.get(rarity, Color.WHITE))
		hbox.add_child(name_l)

		var chance_l = Label.new()
		var adj_chance = entry.get("adjusted_chance", entry.get("base_chance", 0))
		chance_l.text = "%.2f%%" % adj_chance
		if entry.get("is_guaranteed", false):
			chance_l.text = "Guaranteed"
		chance_l.custom_minimum_size = Vector2(70, 0)
		hbox.add_child(chance_l)

		var qty_l = Label.new()
		qty_l.text = "%d–%d" % [entry.get("min_qty", 1), entry.get("max_qty", 1)]
		qty_l.custom_minimum_size = Vector2(40, 0)
		hbox.add_child(qty_l)

		loot_list.add_child(hbox)

func _populate_history(history: Array) -> void:
	for ch in history_list.get_children():
		ch.queue_free()
	if history.is_empty():
		var lbl = Label.new()
		lbl.text = "No battle history yet."
		history_list.add_child(lbl)
		return
	for entry in history:
		var lbl  = Label.new()
		var icon = "✅" if entry.get("outcome") == "victory" else "💀"
		lbl.text = "%s %s — %s — Lv.%d→%d  +%d XP" % [
			icon,
			entry.get("outcome", "?").capitalize(),
			", ".join(entry.get("clan_names", ["?"])),
			entry.get("level_before", 1),
			entry.get("level_after", 1),
			entry.get("xp_gained", 0),
		]
		lbl.add_theme_font_size_override("font_size", 12)
		history_list.add_child(lbl)
