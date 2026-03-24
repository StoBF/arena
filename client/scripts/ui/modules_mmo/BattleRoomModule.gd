extends Control
## BattleRoomModule — Tactical battle planning room.
##
## Flow:
##  1. Create room  → choose heroes → POST /battle/room/create
##  2. Share room ID with opponent → opponent joins via POST /battle/room/{id}/join
##  3. Each player sets a team directive and per-hero orders
##  4. Press "Ready" → POST /battle/room/{id}/ready
##  5. When all ready, server auto-simulates; WS broadcasts result
##  6. Module shows battle log + per-player rewards

# ── Constants ────────────────────────────────────────────────────────────────

const STANCES := ["attack", "defense", "control", "support", "intercept", "reserve"]
const STANCE_COLORS := {
	"attack":    Color(0.95, 0.35, 0.35),
	"defense":   Color(0.35, 0.65, 0.95),
	"control":   Color(0.75, 0.4,  0.9),
	"support":   Color(0.3,  0.85, 0.5),
	"intercept": Color(0.95, 0.75, 0.3),
	"reserve":   Color(0.6,  0.6,  0.6),
}

enum Phase { LOBBY, PLANNING, WAITING_RESULT, RESULT }

# ── State ─────────────────────────────────────────────────────────────────────

var _room_id:       int    = -1
var _phase:         int    = Phase.LOBBY
var _my_heroes:     Array  = []
var _all_heroes:    Array  = []
var _selected_ids:  Array  = []
var _orders:        Dictionary = {}   # hero_id → OrderDict
var _directive:     Dictionary = {}
var _result:        Dictionary = {}
var _ws:            WebSocketPeer = null
var _is_creator:    bool   = false

# ── UI refs ───────────────────────────────────────────────────────────────────

@onready var lbl_status:     Label       = $VBox/TopBar/LblStatus
@onready var lbl_room_id:    Label       = $VBox/TopBar/LblRoomId
@onready var btn_create:     Button      = $VBox/Lobby/BtnCreate
@onready var btn_join:       Button      = $VBox/Lobby/BtnJoin
@onready var edit_join_id:   LineEdit    = $VBox/Lobby/EditJoinId
@onready var hero_grid:      GridContainer = $VBox/Lobby/HeroGrid
@onready var panel_planning: Control     = $VBox/Planning
@onready var panel_lobby:    Control     = $VBox/Lobby
@onready var panel_result:   Control     = $VBox/Result
@onready var orders_list:    VBoxContainer = $VBox/Planning/OrdersList
@onready var btn_ready:      Button      = $VBox/Planning/BtnReady
@onready var btn_cancel:     Button      = $VBox/Planning/BtnCancel
@onready var log_container:  VBoxContainer = $VBox/Result/LogContainer
@onready var lbl_winner:     Label       = $VBox/Result/LblWinner
@onready var rewards_list:   VBoxContainer = $VBox/Result/RewardsList

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready():
	btn_create.pressed.connect(_on_create_pressed)
	btn_join.pressed.connect(_on_join_pressed)
	btn_ready.pressed.connect(_on_ready_pressed)
	btn_cancel.pressed.connect(_on_cancel_pressed)
	_show_phase(Phase.LOBBY)
	_load_heroes()


func _process(_delta):
	if _ws and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.poll()
		while _ws.get_available_packet_count() > 0:
			var pkt = _ws.get_packet()
			_handle_ws_message(JSON.parse_string(pkt.get_string_from_utf8()))

# ── Hero loading ──────────────────────────────────────────────────────────────

func _load_heroes():
	var resp = await ApiClient.get_heroes()
	if resp.get("ok", false):
		_all_heroes = resp.get("data", {}).get("items", [])
		_rebuild_hero_grid()


func _rebuild_hero_grid():
	for c in hero_grid.get_children():
		c.queue_free()
	for hero in _all_heroes:
		var btn := Button.new()
		btn.text = "%s (Gen%d)" % [hero.get("name", "?"), hero.get("hero_generation_level", 0)]
		btn.toggle_mode = true
		var hid: int = hero.get("id", -1)
		btn.pressed.connect(func(): _toggle_hero(hid, btn))
		hero_grid.add_child(btn)


func _toggle_hero(hero_id: int, btn: Button):
	if hero_id in _selected_ids:
		_selected_ids.erase(hero_id)
		btn.button_pressed = false
	else:
		_selected_ids.append(hero_id)
		btn.button_pressed = true

# ── Create / Join ─────────────────────────────────────────────────────────────

func _on_create_pressed():
	if _selected_ids.is_empty():
		lbl_status.text = "Select at least one hero."
		return
	var resp = await ApiClient.create_battle_room(_selected_ids)
	if not resp.get("ok", false):
		lbl_status.text = "Error: " + str(resp.get("message", "unknown"))
		return
	var data = resp.get("data", {})
	_room_id  = data.get("id", -1)
	_is_creator = true
	lbl_room_id.text = "Room ID: %d  (share with opponent)" % _room_id
	_connect_ws()
	_enter_planning(data)


func _on_join_pressed():
	var rid = int(edit_join_id.text.strip_edges())
	if rid <= 0:
		lbl_status.text = "Enter a valid Room ID."
		return
	if _selected_ids.is_empty():
		lbl_status.text = "Select at least one hero."
		return
	var resp = await ApiClient.join_battle_room(rid, _selected_ids)
	if not resp.get("ok", false):
		lbl_status.text = "Error: " + str(resp.get("message", "unknown"))
		return
	_room_id = rid
	_connect_ws()
	_enter_planning(resp.get("data", {}))

# ── Planning phase ────────────────────────────────────────────────────────────

func _enter_planning(room_data: Dictionary):
	_show_phase(Phase.PLANNING)
	lbl_status.text = "Planning — set orders for each hero, then press Ready."
	_rebuild_orders_ui()


func _rebuild_orders_ui():
	for c in orders_list.get_children():
		c.queue_free()
	for hero_id in _selected_ids:
		var hero = _find_hero(hero_id)
		if not hero:
			continue
		var row := HBoxContainer.new()
		var lbl := Label.new()
		lbl.text = hero.get("name", "Hero %d" % hero_id)
		lbl.custom_minimum_size.x = 120
		row.add_child(lbl)

		var stance_btn := OptionButton.new()
		for s in STANCES:
			stance_btn.add_item(s.capitalize())
		stance_btn.item_selected.connect(func(idx): _set_order_field(hero_id, "stance", STANCES[idx]))
		row.add_child(stance_btn)

		var action_edit := LineEdit.new()
		action_edit.placeholder_text = "Action (e.g. basic_attack)"
		action_edit.custom_minimum_size.x = 150
		action_edit.text_changed.connect(func(t): _set_order_field(hero_id, "primary_action", t))
		row.add_child(action_edit)

		var target_edit := LineEdit.new()
		target_edit.placeholder_text = "Target (hero_id or rule)"
		target_edit.custom_minimum_size.x = 130
		target_edit.text_changed.connect(func(t): _set_order_field(hero_id, "primary_target", t))
		row.add_child(target_edit)

		var fallback_edit := LineEdit.new()
		fallback_edit.placeholder_text = "Fallback rule"
		fallback_edit.custom_minimum_size.x = 130
		fallback_edit.text_changed.connect(func(t): _set_order_field(hero_id, "fallback_rule", t))
		row.add_child(fallback_edit)

		var submit_btn := Button.new()
		submit_btn.text = "Submit"
		submit_btn.pressed.connect(func(): _submit_order(hero_id))
		row.add_child(submit_btn)

		orders_list.add_child(row)


func _set_order_field(hero_id: int, key: String, value: String):
	if not _orders.has(hero_id):
		_orders[hero_id] = {"hero_id": hero_id, "stance": "attack",
			"primary_action": "basic_attack", "primary_target": "",
			"fallback_rule": "", "reactive_trigger": ""}
	_orders[hero_id][key] = value


func _submit_order(hero_id: int):
	var order = _orders.get(hero_id, {"hero_id": hero_id, "stance": "attack",
		"primary_action": "basic_attack"})
	var resp = await ApiClient.submit_battle_order(_room_id, order)
	if resp.get("ok", false):
		lbl_status.text = "Order for hero %d submitted." % hero_id
	else:
		lbl_status.text = "Order error: " + str(resp.get("message", "?"))

# ── Ready ─────────────────────────────────────────────────────────────────────

func _on_ready_pressed():
	btn_ready.disabled = true
	var resp = await ApiClient.battle_room_ready(_room_id)
	if resp.get("ok", false):
		lbl_status.text = "Ready! Waiting for opponent..."
		_show_phase(Phase.WAITING_RESULT)
	else:
		btn_ready.disabled = false
		lbl_status.text = "Error: " + str(resp.get("message", "?"))


func _on_cancel_pressed():
	await ApiClient.cancel_battle_room(_room_id)
	_disconnect_ws()
	_show_phase(Phase.LOBBY)
	lbl_status.text = "Room cancelled."

# ── WebSocket ─────────────────────────────────────────────────────────────────

func _connect_ws():
	_ws = WebSocketPeer.new()
	var base = ApiClient.BASE_URL.replace("http://", "ws://").replace("https://", "wss://")
	var token = ApiClient.get_token()
	_ws.connect_to_url("%s/battle/room/ws/%d?token=%s" % [base, _room_id, token])


func _disconnect_ws():
	if _ws:
		_ws.close()
		_ws = null


func _handle_ws_message(msg: Dictionary):
	if not msg:
		return
	match msg.get("event", ""):
		"player_joined":
			lbl_status.text = "Opponent joined! You can now plan."
		"order_updated":
			lbl_status.text = "Opponent updated an order."
		"directive_updated":
			lbl_status.text = "Directive updated."
		"player_ready":
			lbl_status.text = "A player is ready..."
		"battle_complete":
			_result = msg
			_show_result(msg)
		"room_cancelled":
			_show_phase(Phase.LOBBY)
			lbl_status.text = "Room was cancelled."

# ── Result display ────────────────────────────────────────────────────────────

func _show_result(data: Dictionary):
	_show_phase(Phase.RESULT)
	var winner = data.get("winner_team", "draw")
	lbl_winner.text = "Winner: Team %s" % winner.to_upper()
	_disconnect_ws()


func _find_hero(hero_id: int) -> Dictionary:
	for h in _all_heroes:
		if h.get("id", -1) == hero_id:
			return h
	return {}

# ── Phase visibility ──────────────────────────────────────────────────────────

func _show_phase(p: int):
	_phase = p
	panel_lobby.visible    = (p == Phase.LOBBY)
	panel_planning.visible = (p == Phase.PLANNING)
	panel_result.visible   = (p == Phase.RESULT)
	if p == Phase.WAITING_RESULT:
		panel_planning.visible = false
		lbl_status.text = "Simulating battle..."
