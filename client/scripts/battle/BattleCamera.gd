extends Camera3D
## BattleCamera.gd
## Three spectator camera modes:
##   FREE        — mouse-driven free-cam
##   FOLLOW_HERO — tracks a selected hero
##   AUTO_DIRECTOR — AI-driven: focuses on highest-intensity moment

enum Mode { FREE, FOLLOW_HERO, AUTO_DIRECTOR }

# ── Exposed settings ──────────────────────────────────────────────────────────
@export var free_move_speed:    float = 15.0
@export var free_rotate_speed:  float = 0.003
@export var zoom_speed:         float = 3.0
@export var min_zoom:           float = 5.0
@export var max_zoom:           float = 60.0
@export var director_lerp:      float = 2.5   # smoothness of auto-director pan
@export var follow_lerp:        float = 8.0

# ── State ─────────────────────────────────────────────────────────────────────
var mode:           Mode  = Mode.AUTO_DIRECTOR
var _follow_id:     int   = -1
var _heroes:        Dictionary = {}   # hero_id → HeroVisualController
var _last_snap:     Dictionary = {}
var _director_pos:  Vector3 = Vector3(0, 20, 0)
var _director_target: Vector3 = Vector3.ZERO
var _mouse_dragging: bool = false

func _ready() -> void:
	position = Vector3(0, 22, -5)
	rotation_degrees = Vector3(-65, 0, 0)

func init_battle(data: Dictionary, heroes: Dictionary) -> void:
	_heroes = heroes

func update_snapshot(snap: Dictionary, heroes: Dictionary) -> void:
	_heroes   = heroes
	_last_snap = snap
	if mode == Mode.AUTO_DIRECTOR:
		_update_auto_director(snap)

func _update_auto_director(snap: Dictionary) -> void:
	# Find highest-intensity cluster: area with most heroes + recent events
	var hero_list: Array = snap.get("heroes", [])
	if hero_list.is_empty():
		return

	# Weight positions by intensity (low HP, active cast, dead → skip)
	var wx: float = 0.0
	var wz: float = 0.0
	var total_w: float = 0.0
	for h in hero_list:
		if h.get("dead", false):
			continue
		var pos_d: Dictionary = h.get("pos", {})
		var hp: float = h.get("hp_pct", 1.0)
		var w: float  = 2.0 - hp          # low HP = more interesting
		if h.get("cast") != null:
			w += 1.5
		if h.get("control") != null and h.get("control", "") != "":
			w += 1.0
		wx += pos_d.get("x", 0.0) * w
		wz += pos_d.get("z", 0.0) * w
		total_w += w

	if total_w < 0.01:
		return

	var focus := Vector3(wx / total_w, 0.0, wz / total_w)
	_director_target = focus

func _process(delta: float) -> void:
	match mode:
		Mode.FREE:
			_process_free(delta)
		Mode.FOLLOW_HERO:
			_process_follow(delta)
		Mode.AUTO_DIRECTOR:
			_process_director(delta)

func _process_free(delta: float) -> void:
	var vel := Vector3.ZERO
	var basis := global_transform.basis
	if Input.is_key_pressed(KEY_W): vel += -basis.z
	if Input.is_key_pressed(KEY_S): vel +=  basis.z
	if Input.is_key_pressed(KEY_A): vel += -basis.x
	if Input.is_key_pressed(KEY_D): vel +=  basis.x
	if Input.is_key_pressed(KEY_Q): vel +=  Vector3.DOWN
	if Input.is_key_pressed(KEY_E): vel +=  Vector3.UP
	if vel.length_squared() > 0.0:
		position += vel.normalized() * free_move_speed * delta

func _process_follow(delta: float) -> void:
	if _follow_id < 0 or not _heroes.has(_follow_id):
		return
	var hero_pos: Vector3 = _heroes[_follow_id].position
	var desired := hero_pos + Vector3(0, 12, -6)
	position = position.lerp(desired, delta * follow_lerp)
	look_at(hero_pos + Vector3.UP, Vector3.UP)

func _process_director(delta: float) -> void:
	var desired := _director_target + Vector3(0, 20, -8)
	_director_pos = _director_pos.lerp(desired, delta * director_lerp)
	position = _director_pos
	var look_at_pt := _director_target + Vector3(0, 0, 0)
	look_at(look_at_pt, Vector3.UP)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_mouse_dragging = event.pressed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and mode == Mode.FREE:
			position += -global_transform.basis.z * zoom_speed
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and mode == Mode.FREE:
			position += global_transform.basis.z * zoom_speed

	if event is InputEventMouseMotion and _mouse_dragging and mode == Mode.FREE:
		rotate_y(-event.relative.x * free_rotate_speed)
		rotate(global_transform.basis.x, -event.relative.y * free_rotate_speed)

	# Mode shortcuts
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1: set_mode(Mode.FREE)
			KEY_2: set_mode(Mode.FOLLOW_HERO)
			KEY_3: set_mode(Mode.AUTO_DIRECTOR)

func set_mode(m: Mode) -> void:
	mode = m

func follow_hero(hero_id: int, heroes: Dictionary) -> void:
	_heroes    = heroes
	_follow_id = hero_id
	set_mode(Mode.FOLLOW_HERO)
