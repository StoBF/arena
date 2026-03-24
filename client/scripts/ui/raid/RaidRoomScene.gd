extends Control
## RaidRoomScene.gd
## Preparation room: roster, coalition composition, loot preview, start button.

signal raid_started(room_id: int)
signal back_pressed

@onready var room_id_lbl:     Label         = $VBox/Header/RoomIdLabel
@onready var boss_name_lbl:   Label         = $VBox/Header/BossName
@onready var participants_list: VBoxContainer = $VBox/Content/Participants/List
@onready var loot_preview_list: VBoxContainer = $VBox/Content/LootPreview/List
@onready var hero_id_input:   LineEdit      = $VBox/Footer/HeroIdInput
@onready var join_btn:        Button        = $VBox/Footer/JoinBtn
@onready var lock_btn:        Button        = $VBox/Footer/LockBtn
@onready var start_btn:       Button        = $VBox/Footer/StartBtn
@onready var back_btn:        Button        = $VBox/Footer/BackBtn
@onready var status_lbl:      Label         = $VBox/StatusLabel

var room_id:     int = -1
var spawn_id:    int = -1
var template_id: int = -1

func _ready() -> void:
	back_btn.pressed.connect(func(): emit_signal("back_pressed"))
	join_btn.pressed.connect(_on_join_pressed)
	lock_btn.pressed.connect(_on_lock_pressed)
	start_btn.pressed.connect(_on_start_pressed)

func initialize(p_room_id: int, p_spawn_id: int, p_template_id: int) -> void:
	room_id     = p_room_id
	spawn_id    = p_spawn_id
	template_id = p_template_id
	room_id_lbl.text = "Room #%d" % room_id
	_refresh()

func _refresh() -> void:
	if room_id <= 0:
		return
	status_lbl.text = "Refreshing..."
	var api = ApiClient.new()
	add_child(api)
	var room_data = await api.get_raid_room(room_id)
	var loot_data = await api.get_raid_boss_loot(template_id)
	api.queue_free()

	if room_data.has("error"):
		status_lbl.text = "Error: " + str(room_data.get("error", ""))
		return

	var room = room_data.get("room", {})
	boss_name_lbl.text = "Spawn #%d | Status: %s | Loot: %s" % [
		room.get("spawn_id", 0), room.get("status", "?"), room.get("loot_rule", "?")
	]
	_populate_participants(room_data.get("participants", []),
	                       room_data.get("hero_count", 0))
	_populate_loot_preview(loot_data if loot_data is Array else [])

	var status = room.get("status", "preparing")
	lock_btn.disabled  = status != "preparing"
	start_btn.disabled = status not in ["preparing", "locked"]
	status_lbl.text    = "Room is %s." % status

func _populate_participants(participants: Array, count: int) -> void:
	for ch in participants_list.get_children():
		ch.queue_free()
	var header = Label.new()
	header.text = "Heroes in room: %d" % count
	participants_list.add_child(header)
	for p in participants:
		var hbox = HBoxContainer.new()
		var lbl  = Label.new()
		lbl.text = "Hero #%d  (User %d)  %s" % [
			p.get("hero_id", 0),
			p.get("user_id", 0),
			"✅ Ready" if p.get("is_ready", false) else "⏳ Not ready",
		]
		hbox.add_child(lbl)
		participants_list.add_child(hbox)

func _populate_loot_preview(loot: Array) -> void:
	for ch in loot_preview_list.get_children():
		ch.queue_free()
	for entry in loot:
		var hbox = HBoxContainer.new()
		var lbl  = Label.new()
		var prefix = "✨ " if entry.get("is_guaranteed", false) else ""
		var chance = entry.get("adjusted_chance", entry.get("base_chance", 0))
		lbl.text = "%s%s — %.2f%%" % [prefix, entry.get("display_name", "?"), chance]
		lbl.add_theme_font_size_override("font_size", 12)
		hbox.add_child(lbl)
		loot_preview_list.add_child(hbox)

func _on_join_pressed() -> void:
	var hero_text = hero_id_input.text.strip_edges()
	if hero_text.is_empty():
		status_lbl.text = "Enter Hero ID first."
		return
	var hero_id = int(hero_text)
	status_lbl.text = "Joining..."
	var api = ApiClient.new()
	add_child(api)
	var result = await api.join_raid_room(room_id, hero_id)
	api.queue_free()
	if result.has("error"):
		status_lbl.text = "Join failed: " + str(result.get("error", ""))
	else:
		status_lbl.text = "Joined! Hero #%d is in the room." % hero_id
		_refresh()

func _on_lock_pressed() -> void:
	status_lbl.text = "Locking roster..."
	var api = ApiClient.new()
	add_child(api)
	var result = await api.lock_raid_room(room_id)
	api.queue_free()
	if result.has("error"):
		status_lbl.text = "Lock failed: " + str(result.get("error", ""))
	else:
		status_lbl.text = "Roster locked."
		_refresh()

func _on_start_pressed() -> void:
	status_lbl.text = "Starting raid..."
	start_btn.disabled = true
	var api = ApiClient.new()
	add_child(api)
	var result = await api.start_raid(room_id)
	api.queue_free()
	if result.has("error"):
		status_lbl.text = "Start failed: " + str(result.get("error", ""))
		start_btn.disabled = false
	else:
		status_lbl.text = "Raid started! Outcome: %s" % result.get("outcome", "?")
		emit_signal("raid_started", room_id)
