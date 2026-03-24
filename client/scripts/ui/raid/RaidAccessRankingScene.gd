extends Control
## RaidAccessRankingScene.gd
## Shows clan Raid Access Points ranking (weekly and monthly cycles).
## Used for weekly/monthly boss qualification check.

signal back_pressed

@onready var cycle_selector: OptionButton  = $VBox/Header/CycleSelector
@onready var ranking_list:   VBoxContainer = $VBox/Content/RankingList
@onready var my_score_lbl:   Label         = $VBox/Header/MyScoreLabel
@onready var back_btn:       Button        = $VBox/Footer/BackBtn
@onready var refresh_btn:    Button        = $VBox/Header/RefreshBtn
@onready var status_lbl:     Label         = $VBox/StatusLabel

var my_clan_id: int = -1

func _ready() -> void:
	back_btn.pressed.connect(func(): emit_signal("back_pressed"))
	refresh_btn.pressed.connect(_load)
	cycle_selector.add_item("Weekly", 0)
	cycle_selector.add_item("Monthly", 1)
	cycle_selector.item_selected.connect(func(_idx): _load())
	_load()

func set_clan_id(clan_id: int) -> void:
	my_clan_id = clan_id

func _load() -> void:
	status_lbl.text = "Loading..."
	for ch in ranking_list.get_children():
		ch.queue_free()

	var cycle = "weekly" if cycle_selector.selected == 0 else "monthly"
	var api = ApiClient.new()
	add_child(api)
	var ranking = await api.get_raid_access_ranking(cycle, 20)
	api.queue_free()

	if ranking.has("error"):
		status_lbl.text = "Error: " + str(ranking.get("error", ""))
		return

	var entries = ranking if ranking is Array else []
	_build_list(entries, cycle)
	status_lbl.text = "Showing top %d clans for %s cycle." % [entries.size(), cycle]

func _build_list(entries: Array, cycle: String) -> void:
	for ch in ranking_list.get_children():
		ch.queue_free()

	# Header
	var header = Label.new()
	header.text = "# | Clan ID   | Points | Qualified"
	header.add_theme_font_size_override("font_size", 13)
	ranking_list.add_child(header)

	for i in range(entries.size()):
		var e    = entries[i]
		var hbox = HBoxContainer.new()
		var lbl  = Label.new()
		var rank = i + 1
		var icon = ""
		if rank == 1: icon = "🥇 "
		elif rank == 2: icon = "🥈 "
		elif rank == 3: icon = "🥉 "
		else: icon = "   "

		var qual_str = "✅" if e.get("qualified", false) else "❌"
		lbl.text = "%s%2d | Clan #%d | %d pts | %s" % [
			icon, rank,
			e.get("clan_id", 0),
			e.get("points", 0),
			qual_str,
		]
		lbl.add_theme_font_size_override("font_size", 12)

		if e.get("clan_id", -1) == my_clan_id:
			lbl.add_theme_color_override("font_color", Color(0.4, 1.0, 1.0))

		hbox.add_child(lbl)
		ranking_list.add_child(hbox)

	# Show my score separately at top
	if my_clan_id > 0:
		var my_entry = entries.filter(func(e): return e.get("clan_id") == my_clan_id)
		if my_entry.is_empty():
			my_score_lbl.text = "Your clan has no points this %s." % cycle
		else:
			var e = my_entry[0]
			my_score_lbl.text = "Your clan: %d pts (Rank ~%d) %s" % [
				e.get("points", 0),
				entries.find(e) + 1,
				"✅ Qualified" if e.get("qualified", false) else "❌ Not qualified",
			]
