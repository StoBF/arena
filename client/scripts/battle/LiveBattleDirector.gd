extends Node3D
## LiveBattleDirector.gd
## Root controller for a live 5v5 MOBA spectator session.
##
## Responsibilities:
##   - Connect WS to /ws/live-battles/{battle_id}
##   - Parse snapshots + events from server
##   - Drive HeroVisualController nodes
##   - Drive BattleCamera director
##   - Drive SpectatorHUD
##   - Handle battle_finished event
##
## Usage (from a parent scene or GameManager):
##   $LiveBattleDirector.connect_to_battle("uuid-here")

signal battle_finished(winner_team: String)
signal hero_died(hero_id: int, team_id: String)
signal kill_event(killer_id: int, victim_id: int)

# ── Node refs ─────────────────────────────────────────────────────────────────
@onready var hud:           Node   = $SpectatorHUD
@onready var camera:        Node   = $BattleCamera
@onready var heroes_root:   Node3D = $HeroesRoot
@onready var event_renderer: Node  = $BattleEventRenderer

# ── State ─────────────────────────────────────────────────────────────────────
var battle_id:    String = ""
var tick_rate:    int    = 10
var _ws:          WebSocketPeer
var _heroes:      Dictionary = {}   # hero_id (int) → HeroVisualController
var _battle_done: bool   = false
var _last_snapshot: Dictionary = {}

# ── Exported settings ─────────────────────────────────────────────────────────
@export var hero_vc_scene: PackedScene = null  # HeroVisualController scene

func _ready() -> void:
	set_process(false)

func connect_to_battle(bid: String) -> void:
	battle_id = bid
	_ws = WebSocketPeer.new()
	var url := ApiClient.get_ws_url("/ws/live-battles/ws/%s" % bid)
	var err := _ws.connect_to_url(url)
	if err != OK:
		push_error("LiveBattleDirector: WS connect failed: %d" % err)
		return
	set_process(true)

func _process(_delta: float) -> void:
	_ws.poll()
	match _ws.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			while _ws.get_available_packet_count() > 0:
				var raw := _ws.get_packet().get_string_from_utf8()
				_handle_message(raw)
		WebSocketPeer.STATE_CLOSED:
			set_process(false)
		_:
			pass

# ── Message handling ──────────────────────────────────────────────────────────

func _handle_message(raw: String) -> void:
	var data = JSON.parse_string(raw)
	if data == null:
		return
	var msg_type: String = data.get("type", "")
	match msg_type:
		"hello":
			_on_hello(data)
		"snapshot":
			_on_snapshot(data)
		"battle_finished":
			_on_battle_finished(data)

func _on_hello(data: Dictionary) -> void:
	tick_rate = data.get("tick_rate", 10)
	var heroes_info: Array = data.get("heroes", [])
	for hi in heroes_info:
		_spawn_hero(hi)
	hud.init_battle(data)
	camera.init_battle(data, _heroes)

func _on_snapshot(snap: Dictionary) -> void:
	if _battle_done:
		return
	_last_snapshot = snap
	var hero_list: Array = snap.get("heroes", [])
	for hsnap in hero_list:
		var hid: int = hsnap.get("hero_id", 0)
		if _heroes.has(hid):
			_heroes[hid].apply_snapshot(hsnap)

	var events: Array = snap.get("events", [])
	for ev in events:
		_dispatch_event(ev)

	hud.update_snapshot(snap)
	camera.update_snapshot(snap, _heroes)

func _dispatch_event(ev: Dictionary) -> void:
	var etype: String = ev.get("type", "")
	match etype:
		"hero_dead":
			var hid: int = ev.get("target_id", 0)
			var tid: String = _heroes[hid].team_id if _heroes.has(hid) else ""
			emit_signal("hero_died", hid, tid)
			event_renderer.play_event(ev)
		"kill_trigger":
			emit_signal("kill_event", ev.get("source_id", 0), ev.get("target_id", 0))
			event_renderer.play_event(ev)
		"cast_interrupted", "cast_redirected", "skill_hit":
			event_renderer.play_event(ev)
		_:
			pass

func _on_battle_finished(data: Dictionary) -> void:
	_battle_done = true
	var winner: String = data.get("winner", "draw")
	emit_signal("battle_finished", winner)
	hud.show_victory(winner)
	_ws.close()
	set_process(false)

# ── Hero spawning ─────────────────────────────────────────────────────────────

func _spawn_hero(hi: Dictionary) -> void:
	var hid: int = hi.get("hero_id", 0)
	var vc: Node
	if hero_vc_scene != null:
		vc = hero_vc_scene.instantiate()
	else:
		vc = _create_placeholder_hero(hi)
	heroes_root.add_child(vc)
	vc.init(hi)
	_heroes[hid] = vc

func _create_placeholder_hero(hi: Dictionary) -> Node3D:
	var vc := Node3D.new()
	var mesh := MeshInstance3D.new()
	var role: String = hi.get("role", "VANGUARD")
	var team: String = hi.get("team_id", "A")

	# Shape per role
	var m: Mesh
	match role:
		"VANGUARD":   m = BoxMesh.new()
		"STRIKER":    m = CapsuleMesh.new()
		"CONTROLLER": m = CylinderMesh.new()
		"SUPPORT":    m = SphereMesh.new()
		_:
			var bm := BoxMesh.new()
			bm.size = Vector3(0.5, 1.2, 0.3)
			m = bm

	mesh.mesh = m
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.4, 1.0) if team == "A" else Color(1.0, 0.2, 0.2)
	mesh.material_override = mat
	vc.add_child(mesh)

	# Name label
	var lbl := Label3D.new()
	lbl.text = hi.get("name", "Hero")
	lbl.position = Vector3(0, 1.6, 0)
	lbl.font_size = 32
	lbl.modulate = Color.WHITE
	vc.add_child(lbl)

	# HP bar (simple 3D billboard)
	# attach a HeroVisualController script if available
	var hvc_script := preload("res://scripts/battle/HeroVisualController.gd")
	if hvc_script:
		vc.set_script(hvc_script)

	return vc

# ── Inspector: focus selected hero ───────────────────────────────────────────

func select_hero(hero_id: int) -> void:
	hud.show_hero_detail(hero_id, _last_snapshot)
	camera.follow_hero(hero_id, _heroes)
