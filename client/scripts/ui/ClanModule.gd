extends Node
## ClanModule.gd
## Central clan UI controller. Manages all clan-related screens and state.
##
## Usage:
##   - Add to scene tree as an AutoLoad or attach to a parent Control node
##   - Call show_browser() / show_clan_details(id) from your main menu
##
## Screens (enum Tab):
##   BROWSER         – search / browse clans
##   CREATE          – create a new clan
##   OVERVIEW        – selected clan overview
##   MEMBERS         – member list + role management
##   APPLICATIONS    – join applications (officer view)
##   STORAGE         – clan storage
##   MEETUPS         – meetup events
##   ACTIVITY        – activity log
##   MY_APPLICATION  – own pending application status

# ── State ─────────────────────────────────────────────────────────────────────
enum Tab {
	BROWSER, CREATE, OVERVIEW, MEMBERS,
	APPLICATIONS, STORAGE, MEETUPS, ACTIVITY, MY_APPLICATION
}

var current_tab:    Tab           = Tab.BROWSER
var active_clan_id: int           = 0
var my_member_data: Dictionary    = {}   # own ClanMember record
var clan_data:      Dictionary    = {}   # current clan full data
var members:        Array         = []
var applications:   Array         = []
var storage_items:  Array         = []
var meetups:        Array         = []
var activity:       Array         = []

# WebSocket for clan chat
var _chat_ws: WebSocketPeer       = null
var _chat_clan_id: int            = 0

signal clan_loaded(clan: Dictionary)
signal members_loaded(list: Array)
signal applications_loaded(list: Array)
signal storage_loaded(list: Array)
signal meetups_loaded(list: Array)
signal activity_loaded(list: Array)
signal chat_message_received(msg: Dictionary)
signal error_occurred(message: String)
signal tab_changed(tab: Tab)

# ── Lifecycle ─────────────────────────────────────────────────────────────────
func _process(_delta: float) -> void:
	if _chat_ws != null:
		_chat_ws.poll()
		var state := _chat_ws.get_ready_state()
		if state == WebSocketPeer.STATE_OPEN:
			while _chat_ws.get_available_packet_count() > 0:
				var pkt := _chat_ws.get_packet()
				_on_chat_packet(pkt)

# ── Navigation ────────────────────────────────────────────────────────────────
func show_browser() -> void:
	current_tab = Tab.BROWSER
	emit_signal("tab_changed", current_tab)

func show_create() -> void:
	current_tab = Tab.CREATE
	emit_signal("tab_changed", current_tab)

func show_clan(clan_id: int) -> void:
	active_clan_id = clan_id
	current_tab = Tab.OVERVIEW
	emit_signal("tab_changed", current_tab)
	await _load_clan()

func show_members() -> void:
	current_tab = Tab.MEMBERS
	emit_signal("tab_changed", current_tab)
	await _load_members()

func show_applications() -> void:
	current_tab = Tab.APPLICATIONS
	emit_signal("tab_changed", current_tab)
	await _load_applications()

func show_storage() -> void:
	current_tab = Tab.STORAGE
	emit_signal("tab_changed", current_tab)
	await _load_storage()

func show_meetups() -> void:
	current_tab = Tab.MEETUPS
	emit_signal("tab_changed", current_tab)
	await _load_meetups()

func show_activity() -> void:
	current_tab = Tab.ACTIVITY
	emit_signal("tab_changed", current_tab)
	await _load_activity()

# ── Data loaders ──────────────────────────────────────────────────────────────
func search_clans(filters: Dictionary = {}) -> Array:
	var result = await ApiClient.search_clans(filters)
	return result

func _load_clan() -> void:
	var data = await ApiClient.get_clan(active_clan_id)
	if data is Dictionary and data.has("id"):
		clan_data = data
		emit_signal("clan_loaded", clan_data)
	else:
		emit_signal("error_occurred", "Failed to load clan data")

func _load_members() -> void:
	var data = await ApiClient.get_clan_members(active_clan_id)
	members = data
	emit_signal("members_loaded", members)

func _load_applications(status: String = "") -> void:
	var data = await ApiClient.get_clan_applications(active_clan_id, status)
	applications = data
	emit_signal("applications_loaded", applications)

func _load_storage() -> void:
	var data = await ApiClient.get_clan_storage(active_clan_id)
	storage_items = data
	emit_signal("storage_loaded", storage_items)

func _load_meetups() -> void:
	var data = await ApiClient.get_clan_meetups(active_clan_id)
	meetups = data
	emit_signal("meetups_loaded", meetups)

func _load_activity() -> void:
	var data = await ApiClient.get_clan_activity(active_clan_id)
	activity = data
	emit_signal("activity_loaded", activity)

# ── Clan CRUD ─────────────────────────────────────────────────────────────────
func create_clan(form: Dictionary) -> Dictionary:
	var result = await ApiClient.create_clan(form)
	if result is Dictionary and result.has("id"):
		active_clan_id = result["id"]
	return result

func update_clan(data: Dictionary) -> Dictionary:
	return await ApiClient.update_clan(active_clan_id, data)

func disband_clan() -> Dictionary:
	return await ApiClient.disband_clan(active_clan_id)

# ── Member management ─────────────────────────────────────────────────────────
func kick_member(user_id: int) -> Dictionary:
	return await ApiClient.kick_clan_member(active_clan_id, user_id)

func leave_clan() -> Dictionary:
	return await ApiClient.leave_clan(active_clan_id)

func set_role(user_id: int, role: String) -> Dictionary:
	return await ApiClient.set_member_role(active_clan_id, user_id, role)

func set_nickname(user_id: int, nickname: String) -> Dictionary:
	return await ApiClient.set_member_nickname(active_clan_id, user_id, nickname)

func set_permissions(user_id: int, perms: Dictionary) -> Dictionary:
	return await ApiClient.set_member_permissions(active_clan_id, user_id, perms)

func transfer_leadership(new_leader_id: int) -> Dictionary:
	return await ApiClient.transfer_leadership(active_clan_id, new_leader_id)

# ── Applications ──────────────────────────────────────────────────────────────
func apply_to_clan(data: Dictionary) -> Dictionary:
	return await ApiClient.apply_to_clan(active_clan_id, data)

func accept_application(app_id: int, note: String = "") -> Dictionary:
	return await ApiClient.accept_application(active_clan_id, app_id, note)

func reject_application(app_id: int, note: String = "") -> Dictionary:
	return await ApiClient.reject_application(active_clan_id, app_id, note)

func start_interview(app_id: int, note: String = "") -> Dictionary:
	return await ApiClient.start_application_interview(active_clan_id, app_id, note)

# ── Storage ───────────────────────────────────────────────────────────────────
func deposit(item_type: String, item_id: int, quantity: int, note: String = "") -> Dictionary:
	return await ApiClient.deposit_to_clan_storage(
		active_clan_id, item_type, item_id, quantity, note)

func withdraw(item_type: String, item_id: int, quantity: int, note: String = "") -> Dictionary:
	return await ApiClient.withdraw_from_clan_storage(
		active_clan_id, item_type, item_id, quantity, note)

func get_storage_log(limit: int = 50) -> Array:
	return await ApiClient.get_clan_storage_logs(active_clan_id, limit)

# ── Meetup / QR ───────────────────────────────────────────────────────────────
func create_meetup(data: Dictionary) -> Dictionary:
	return await ApiClient.create_clan_meetup(active_clan_id, data)

func generate_qr(meetup_id: int) -> Dictionary:
	return await ApiClient.generate_meetup_qr(meetup_id)

func check_in_qr(meetup_id: int, token: String) -> Dictionary:
	return await ApiClient.meetup_check_in(meetup_id, token)

func close_meetup(meetup_id: int) -> Dictionary:
	return await ApiClient.close_meetup(meetup_id)

# ── Clan chat WebSocket ───────────────────────────────────────────────────────
func connect_chat(clan_id: int, jwt_token: String) -> void:
	if _chat_ws != null and _chat_clan_id == clan_id:
		return   # already connected
	disconnect_chat()
	_chat_clan_id = clan_id
	_chat_ws = WebSocketPeer.new()
	var base_url: String = ApiClient.BASE_URL.replace("https://", "wss://").replace("http://", "ws://")
	var ws_url := "%s/ws/clan/%d?token=%s" % [base_url, clan_id, jwt_token]
	_chat_ws.connect_to_url(ws_url)

func disconnect_chat() -> void:
	if _chat_ws != null:
		_chat_ws.close()
		_chat_ws = null
	_chat_clan_id = 0

func send_chat(text: String) -> void:
	if _chat_ws == null or _chat_ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	var payload := JSON.stringify({"text": text})
	_chat_ws.send_text(payload)

func _on_chat_packet(pkt: PackedByteArray) -> void:
	var text := pkt.get_string_from_utf8()
	var parsed = JSON.parse_string(text)
	if parsed is Dictionary:
		emit_signal("chat_message_received", parsed)

# ── Helpers ───────────────────────────────────────────────────────────────────
func is_leader() -> bool:
	return my_member_data.get("role", "") == "leader"

func is_officer_or_above() -> bool:
	var role := my_member_data.get("role", "")
	return role in ["leader", "co_leader", "officer"]

func can_manage_storage() -> bool:
	return bool(my_member_data.get("can_manage_storage", false)) or is_leader()

func can_withdraw_storage() -> bool:
	return bool(my_member_data.get("can_withdraw_storage", false)) or is_leader()

func trust_level() -> int:
	return int(my_member_data.get("trust_level", 0))
