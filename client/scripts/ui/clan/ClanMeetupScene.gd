extends Control
## ClanMeetupScene.gd
## Create meetup events, generate QR codes, and handle member check-ins.
## Officers/leaders create events; members scan QR to check in.

signal back_pressed()

@onready var meetups_list:    VBoxContainer = $ScrollContainer/MeetupsList
@onready var title_edit:      LineEdit      = $CreateForm/TitleEdit
@onready var city_edit:       LineEdit      = $CreateForm/CityEdit
@onready var create_btn:      Button        = $CreateForm/CreateButton
@onready var qr_panel:        PanelContainer = $QRPanel
@onready var qr_token_label:  Label         = $QRPanel/TokenLabel
@onready var qr_expires_label:Label         = $QRPanel/ExpiresLabel
@onready var checkin_edit:    LineEdit      = $CheckInForm/TokenEdit
@onready var checkin_btn:     Button        = $CheckInForm/CheckInButton
@onready var close_btn:       Button        = $QRPanel/CloseQRButton
@onready var back_button:     Button        = $BackButton
@onready var status_lbl:      Label         = $StatusLabel

var clan_id:       int        = 0
var _active_meetup_id: int    = 0

func _ready() -> void:
	back_button.pressed.connect(func(): emit_signal("back_pressed"))
	create_btn.pressed.connect(_on_create_meetup)
	checkin_btn.pressed.connect(_on_check_in)
	close_btn.pressed.connect(_on_close_qr_panel)
	qr_panel.visible = false
	status_lbl.text  = ""
	if clan_id > 0:
		await _load_meetups()

func load_for_clan(id: int) -> void:
	clan_id = id
	await _load_meetups()

func _load_meetups() -> void:
	for c in meetups_list.get_children():
		c.queue_free()
	var meetups = await ApiClient.get_clan_meetups(clan_id)
	if meetups.is_empty():
		var lbl := Label.new()
		lbl.text = "No meetups scheduled yet"
		meetups_list.add_child(lbl)
		return
	for m in meetups:
		meetups_list.add_child(_make_meetup_row(m))

func _make_meetup_row(m: Dictionary) -> Control:
	var row   := HBoxContainer.new()
	var info  := VBoxContainer.new()
	var title := Label.new()
	title.text = "[%s] %s — %s" % [
		m.get("status", "?"),
		m.get("title", ""),
		m.get("city_name", ""),
	]
	var detail := Label.new()
	detail.text = "%d participants" % m.get("participant_count", 0)
	detail.add_theme_font_size_override("font_size", 11)
	info.add_child(title)
	info.add_child(detail)
	row.add_child(info)

	if m.get("status") == "scheduled" or m.get("status") == "active":
		var qr_btn := Button.new()
		qr_btn.text = "Gen QR"
		var mid: int = m.get("id", 0)
		qr_btn.pressed.connect(func(): _on_generate_qr(mid))
		row.add_child(qr_btn)

		if m.get("status") == "active":
			var close_meetup_btn := Button.new()
			close_meetup_btn.text = "Close"
			close_meetup_btn.pressed.connect(func(): _on_close_meetup(mid))
			row.add_child(close_meetup_btn)
	return row

func _on_create_meetup() -> void:
	var title := title_edit.text.strip_edges()
	if title.length() < 3:
		_set_status("Title too short")
		return
	create_btn.disabled = true
	var res = await ApiClient.create_clan_meetup(clan_id, {
		"title":    title,
		"city_name": city_edit.text.strip_edges(),
	})
	create_btn.disabled = false
	if res is Dictionary and res.has("id"):
		title_edit.text = ""
		city_edit.text  = ""
		_set_status("Meetup created!")
		await _load_meetups()
	else:
		_set_status("Failed: " + str(res.get("detail", "error")))

func _on_generate_qr(meetup_id: int) -> void:
	_active_meetup_id = meetup_id
	var res = await ApiClient.generate_meetup_qr(meetup_id)
	if res is Dictionary and res.has("qr_token"):
		qr_token_label.text   = "Token: " + res.get("qr_token", "")
		qr_expires_label.text = "Expires: " + res.get("expires_at", "")
		qr_panel.visible = true
	else:
		_set_status("Failed to generate QR")

func _on_close_qr_panel() -> void:
	qr_panel.visible = false

func _on_check_in() -> void:
	var token := checkin_edit.text.strip_edges()
	if token == "":
		_set_status("Enter QR token")
		return
	checkin_btn.disabled = true
	var res = await ApiClient.meetup_check_in(_active_meetup_id, token)
	checkin_btn.disabled = false
	if res is Dictionary and res.get("ok"):
		_set_status("Check-in successful! Trust bonus awarded.")
		checkin_edit.text = ""
	else:
		_set_status("Check-in failed: " + str(res.get("detail", "error")))

func _on_close_meetup(meetup_id: int) -> void:
	var res = await ApiClient.close_meetup(meetup_id)
	if res is Dictionary and res.get("ok"):
		_set_status("Meetup closed")
		await _load_meetups()

func _set_status(msg: String) -> void:
	status_lbl.text = msg
