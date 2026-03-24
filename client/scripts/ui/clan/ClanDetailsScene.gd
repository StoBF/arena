extends Control
## ClanDetailsScene.gd
## Shows full details of a selected clan: overview + tabs.
## Tabs: Overview | Members | Applications | Storage | Meetups | Activity

signal back_pressed()
signal joined_clan()

enum Tab { OVERVIEW, MEMBERS, APPLICATIONS, STORAGE, MEETUPS, ACTIVITY }

@onready var clan_name_lbl:   Label        = $Header/ClanNameLabel
@onready var level_lbl:       Label        = $Header/LevelLabel
@onready var emblem_img:      TextureRect  = $Header/EmblemImage
@onready var tab_bar:         TabContainer = $TabContainer
@onready var join_button:     Button       = $Header/JoinButton
@onready var apply_button:    Button       = $Header/ApplyButton
@onready var back_button:     Button       = $BackButton
@onready var description_lbl: Label        = $TabContainer/Overview/DescriptionLabel
@onready var members_list:    VBoxContainer = $TabContainer/Members/MembersList
@onready var storage_list:    VBoxContainer = $TabContainer/Storage/StorageList

var clan_id: int = 0
var _clan:   Dictionary = {}
var _my_member: Dictionary = {}

func _ready() -> void:
	back_button.pressed.connect(func(): emit_signal("back_pressed"))
	join_button.pressed.connect(_on_join)
	apply_button.pressed.connect(_on_apply)
	if clan_id > 0:
		await _load()

func load_clan(id: int) -> void:
	clan_id = id
	await _load()

func _load() -> void:
	_clan = await ApiClient.get_clan(clan_id)
	_render_overview()
	await _load_members()

func _render_overview() -> void:
	clan_name_lbl.text = "[Lv%d] %s" % [_clan.get("level", 1), _clan.get("name", "")]
	level_lbl.text     = "XP: %d | Rep: %d | %d members" % [
		_clan.get("experience", 0),
		_clan.get("reputation", 0),
		_clan.get("member_count", 0),
	]
	description_lbl.text = _clan.get("description", "")

	var rec_mode := _clan.get("recruitment_mode", "by_application")
	join_button.visible  = rec_mode == "open"
	apply_button.visible = rec_mode == "by_application"

func _load_members() -> void:
	var members = await ApiClient.get_clan_members(clan_id)
	for c in members_list.get_children():
		c.queue_free()
	for m in members:
		var row := HBoxContainer.new()
		var lbl := Label.new()
		var nick := m.get("nickname", "")
		lbl.text = "[%s] %s (trust: %d)" % [
			m.get("role", "member"),
			("«" + nick + "»") if nick != "" else "user#%d" % m.get("user_id", 0),
			m.get("trust_level", 0),
		]
		row.add_child(lbl)
		members_list.add_child(row)

func _on_join() -> void:
	join_button.disabled = true
	var res = await ApiClient.apply_to_clan(clan_id, {"message": "Joining open clan"})
	join_button.disabled = false
	if res is Dictionary and (res.has("id") or res.get("ok")):
		emit_signal("joined_clan")

func _on_apply() -> void:
	# Open application form — caller handles scene transition
	pass
