extends Control
## ClanApplicationScene.gd
## Two modes:
##   1. Applicant: fill and submit an application form for a specific clan
##   2. Recruiter: view + accept/reject/interview pending applications

signal back_pressed()
signal application_submitted()

# ── Mode ─────────────────────────────────────────────────────────────────────
enum Mode { APPLY, MANAGE }
var mode:    Mode = Mode.APPLY
var clan_id: int  = 0

# ── Apply-mode refs ───────────────────────────────────────────────────────────
@onready var apply_panel:     Control       = $ApplyPanel
@onready var message_edit:    TextEdit      = $ApplyPanel/MessageEdit
@onready var city_edit:       LineEdit      = $ApplyPanel/CityEdit
@onready var playstyle_edit:  LineEdit      = $ApplyPanel/PlaystyleEdit
@onready var avail_edit:      LineEdit      = $ApplyPanel/AvailEdit
@onready var submit_btn:      Button        = $ApplyPanel/SubmitButton

# ── Manage-mode refs ──────────────────────────────────────────────────────────
@onready var manage_panel:    Control       = $ManagePanel
@onready var app_list:        VBoxContainer = $ManagePanel/ScrollContainer/AppList
@onready var filter_option:   OptionButton  = $ManagePanel/FilterOption

@onready var back_button:     Button        = $BackButton
@onready var status_lbl:      Label         = $StatusLabel

func _ready() -> void:
	back_button.pressed.connect(func(): emit_signal("back_pressed"))
	submit_btn.pressed.connect(_on_submit)
	filter_option.item_selected.connect(_on_filter_changed)
	_setup_filter_options()
	status_lbl.text = ""
	_set_mode(mode)

func set_apply_mode(id: int) -> void:
	clan_id = id
	mode    = Mode.APPLY
	_set_mode(mode)

func set_manage_mode(id: int) -> void:
	clan_id = id
	mode    = Mode.MANAGE
	_set_mode(mode)
	await _load_applications()

func _set_mode(m: Mode) -> void:
	apply_panel.visible  = (m == Mode.APPLY)
	manage_panel.visible = (m == Mode.MANAGE)

func _setup_filter_options() -> void:
	filter_option.clear()
	for s in ["new", "in_review", "interview", "trial", "accepted", "rejected"]:
		filter_option.add_item(s)

func _on_filter_changed(_idx: int) -> void:
	await _load_applications()

func _on_submit() -> void:
	submit_btn.disabled = true
	var res = await ApiClient.apply_to_clan(clan_id, {
		"message":           message_edit.text.strip_edges(),
		"city_name":         city_edit.text.strip_edges(),
		"playstyle":         playstyle_edit.text.strip_edges(),
		"availability_text": avail_edit.text.strip_edges(),
	})
	submit_btn.disabled = false
	if res is Dictionary and res.has("id"):
		_set_status("Application submitted!")
		emit_signal("application_submitted")
	else:
		_set_status("Failed: " + str(res.get("detail", "error")))

func _load_applications() -> void:
	for c in app_list.get_children():
		c.queue_free()
	var status_filter := filter_option.get_item_text(filter_option.selected)
	var apps = await ApiClient.get_clan_applications(clan_id, status_filter)
	if apps.is_empty():
		var lbl := Label.new()
		lbl.text = "No applications"
		app_list.add_child(lbl)
		return
	for a in apps:
		app_list.add_child(_make_app_row(a))

func _make_app_row(a: Dictionary) -> Control:
	var row   := VBoxContainer.new()
	var lbl   := Label.new()
	lbl.text  = "User #%d | %s | %s" % [
		a.get("user_id", 0),
		a.get("status", "?"),
		a.get("city_name", ""),
	]
	var msg   := Label.new()
	msg.text  = a.get("message", "")
	msg.add_theme_font_size_override("font_size", 11)
	row.add_child(lbl)
	row.add_child(msg)

	var btns := HBoxContainer.new()
	var app_id: int = a.get("id", 0)

	if a.get("status") in ["new", "in_review", "interview", "trial"]:
		var accept_btn := Button.new()
		accept_btn.text = "Accept"
		accept_btn.pressed.connect(func(): _on_accept(app_id))
		btns.add_child(accept_btn)

		var reject_btn := Button.new()
		reject_btn.text = "Reject"
		reject_btn.pressed.connect(func(): _on_reject(app_id))
		btns.add_child(reject_btn)

		if a.get("status") == "new":
			var interview_btn := Button.new()
			interview_btn.text = "Interview"
			interview_btn.pressed.connect(func(): _on_interview(app_id))
			btns.add_child(interview_btn)

	row.add_child(btns)
	return row

func _on_accept(app_id: int) -> void:
	var res = await ApiClient.accept_application(clan_id, app_id)
	if res is Dictionary and res.get("ok"):
		_set_status("Accepted!")
		await _load_applications()

func _on_reject(app_id: int) -> void:
	var res = await ApiClient.reject_application(clan_id, app_id)
	if res is Dictionary and res.get("ok"):
		_set_status("Rejected")
		await _load_applications()

func _on_interview(app_id: int) -> void:
	var res = await ApiClient.start_application_interview(clan_id, app_id)
	if res is Dictionary and res.get("ok"):
		_set_status("Moved to interview stage")
		await _load_applications()

func _set_status(msg: String) -> void:
	status_lbl.text = msg
