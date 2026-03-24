extends CanvasLayer
## SpectatorHUD.gd
## Spectator overlay for live 5v5 battles.
##
## Panels:
##   Top bar    — Team A vs B, timer, alive counts, damage totals
##   Left panel — Team A hero list (compact)
##   Right panel — Team B hero list (compact)
##   Bottom panel — Selected hero detail (role, stats, buffs, cooldowns, target)
##   Event feed  — Last N combat events scrolling on screen

# ── Top bar ───────────────────────────────────────────────────────────────────
@onready var team_a_label:   Label = $TopBar/TeamALabel
@onready var team_b_label:   Label = $TopBar/TeamBLabel
@onready var timer_label:    Label = $TopBar/TimerLabel
@onready var a_alive_label:  Label = $TopBar/AliveA
@onready var b_alive_label:  Label = $TopBar/AliveB
@onready var a_dmg_label:    Label = $TopBar/DmgA
@onready var b_dmg_label:    Label = $TopBar/DmgB
@onready var camera_mode_lbl: Label = $TopBar/CameraMode

# ── Side panels ───────────────────────────────────────────────────────────────
@onready var a_hero_list:    VBoxContainer = $LeftPanel/ScrollContainer/HeroList
@onready var b_hero_list:    VBoxContainer = $RightPanel/ScrollContainer/HeroList

# ── Selected hero detail ──────────────────────────────────────────────────────
@onready var detail_panel:   PanelContainer = $DetailPanel
@onready var det_name_lbl:   Label          = $DetailPanel/VBox/NameLabel
@onready var det_role_lbl:   Label          = $DetailPanel/VBox/RoleLabel
@onready var det_hp_lbl:     Label          = $DetailPanel/VBox/HpLabel
@onready var det_st_lbl:     Label          = $DetailPanel/VBox/StaminaLabel
@onready var det_target_lbl: Label          = $DetailPanel/VBox/TargetLabel
@onready var det_state_lbl:  Label          = $DetailPanel/VBox/StateLabel
@onready var det_buffs_lbl:  Label          = $DetailPanel/VBox/BuffsLabel

# ── Event feed ────────────────────────────────────────────────────────────────
@onready var event_feed:     VBoxContainer  = $EventFeed/VBox

# ── Victory overlay ───────────────────────────────────────────────────────────
@onready var victory_panel:  Control        = $VictoryPanel
@onready var victory_label:  Label          = $VictoryPanel/Label

# ── State ─────────────────────────────────────────────────────────────────────
var _selected_hero_id: int = -1
var _heroes:           Dictionary = {}   # hero_id → info dict
var _last_heroes_snap: Dictionary = {}   # hero_id → snap dict
var _event_messages:   Array      = []
const MAX_EVENTS       := 8

func _ready() -> void:
	victory_panel.visible = false
	detail_panel.visible  = false

func init_battle(data: Dictionary) -> void:
	team_a_label.text = "Team A"
	team_b_label.text = "Team B"
	timer_label.text  = "0:00"
	a_alive_label.text = "5"
	b_alive_label.text = "5"
	a_dmg_label.text  = "0"
	b_dmg_label.text  = "0"

	var heroes_info: Array = data.get("heroes", [])
	for hi in heroes_info:
		var hid: int = hi.get("hero_id", 0)
		_heroes[hid] = hi

	_rebuild_side_panels()

func _rebuild_side_panels() -> void:
	_clear(a_hero_list)
	_clear(b_hero_list)
	for hid in _heroes:
		var hi: Dictionary = _heroes[hid]
		var lbl := Label.new()
		lbl.text = "[%s] %s" % [hi.get("role", "?")[:3], hi.get("name", "Hero")]
		lbl.add_theme_font_size_override("font_size", 12)
		if hi.get("team_id") == "A":
			a_hero_list.add_child(lbl)
		else:
			b_hero_list.add_child(lbl)

func update_snapshot(snap: Dictionary) -> void:
	var elapsed: float = snap.get("elapsed", 0.0)
	var mins := int(elapsed) / 60
	var secs := int(elapsed) % 60
	timer_label.text = "%d:%02d" % [mins, secs]

	a_alive_label.text = str(snap.get("team_a_alive", 5))
	b_alive_label.text = str(snap.get("team_b_alive", 5))

	# Update hero snap cache + side panel labels
	for hsnap in snap.get("heroes", []):
		var hid: int = hsnap.get("hero_id", 0)
		_last_heroes_snap[hid] = hsnap
		_update_side_panel_row(hid, hsnap)

	# Damage totals
	var a_dmg: float = 0.0
	var b_dmg: float = 0.0
	for hid in _last_heroes_snap:
		var hs = _last_heroes_snap[hid]
		# damage not in snap directly, but we track team_id from _heroes
		pass  # server sends team_a/b totals via event feed in full impl
	a_dmg_label.text = str(int(a_dmg))
	b_dmg_label.text = str(int(b_dmg))

	# Update selected hero detail
	if _selected_hero_id >= 0 and _last_heroes_snap.has(_selected_hero_id):
		_refresh_detail(_selected_hero_id, _last_heroes_snap[_selected_hero_id])

func _update_side_panel_row(hid: int, hsnap: Dictionary) -> void:
	# Side panel rows are just Labels; update text with HP info
	# For a richer UI, store the Label nodes in a dict
	pass  # minimal — full impl would update per-row nodes

func show_hero_detail(hero_id: int, full_snap: Dictionary) -> void:
	_selected_hero_id = hero_id
	detail_panel.visible = true
	if _last_heroes_snap.has(hero_id):
		_refresh_detail(hero_id, _last_heroes_snap[hero_id])

func _refresh_detail(hid: int, hsnap: Dictionary) -> void:
	var hi: Dictionary = _heroes.get(hid, {})
	det_name_lbl.text   = hi.get("name", "Hero#%d" % hid)
	det_role_lbl.text   = hi.get("role", "?")
	det_hp_lbl.text     = "HP: %.0f%%" % (hsnap.get("hp_pct", 1.0) * 100)
	det_st_lbl.text     = "Stamina: %.0f%%" % (hsnap.get("stamina_pct", 1.0) * 100)
	det_target_lbl.text = "Target: #%s" % str(hsnap.get("target_id", "-"))
	det_state_lbl.text  = "State: %s" % hsnap.get("state", "idle")
	var effs: Array = hsnap.get("effects", [])
	det_buffs_lbl.text  = "Effects: %s" % (", ".join(PackedStringArray(effs)) if effs else "none")

func push_event_message(text: String, color: Color = Color.WHITE) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.modulate = color
	lbl.add_theme_font_size_override("font_size", 13)
	event_feed.add_child(lbl)
	_event_messages.append(lbl)
	if _event_messages.size() > MAX_EVENTS:
		var old: Node = _event_messages.pop_front()
		old.queue_free()

func show_victory(winner: String) -> void:
	victory_panel.visible = true
	if winner == "A":
		victory_label.text = "TEAM A WINS!"
		victory_label.modulate = Color(0.2, 0.4, 1.0)
	elif winner == "B":
		victory_label.text = "TEAM B WINS!"
		victory_label.modulate = Color(1.0, 0.2, 0.2)
	else:
		victory_label.text = "DRAW"
		victory_label.modulate = Color.YELLOW

func _clear(container: Node) -> void:
	for c in container.get_children():
		c.queue_free()
