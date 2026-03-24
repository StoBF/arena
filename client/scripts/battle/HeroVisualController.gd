extends Node3D
## HeroVisualController.gd
## Manages one hero's 3D visual representation.
## Receives server snapshots and smoothly interpolates position.

# ── Identity ──────────────────────────────────────────────────────────────────
var hero_id:     int    = 0
var team_id:     String = "A"
var hero_name:   String = ""
var role:        String = "VANGUARD"

# ── Visual children ───────────────────────────────────────────────────────────
var _mesh:       MeshInstance3D
var _label:      Label3D
var _hp_bar:     MeshInstance3D
var _st_bar:     MeshInstance3D
var _status_lbl: Label3D
var _effect_lbl: Label3D

# ── Interpolation ─────────────────────────────────────────────────────────────
const LERP_SPEED := 12.0
var _target_pos: Vector3 = Vector3.ZERO
var _target_rot: float   = 0.0
var _is_dead:    bool    = false

# ── Colors ────────────────────────────────────────────────────────────────────
const COLOR_TEAM_A := Color(0.2, 0.4, 1.0)
const COLOR_TEAM_B := Color(1.0, 0.2, 0.2)
const COLOR_HP_OK  := Color(0.2, 0.9, 0.2)
const COLOR_HP_LOW := Color(0.9, 0.7, 0.1)
const COLOR_HP_CRT := Color(0.9, 0.2, 0.1)
const COLOR_ST     := Color(0.2, 0.6, 1.0)

func init(info: Dictionary) -> void:
	hero_id   = info.get("hero_id", 0)
	team_id   = info.get("team_id", "A")
	hero_name = info.get("name", "Hero")
	role      = info.get("role", "VANGUARD")

	_build_visuals()

	# Initial position from hello payload
	var pos_d: Dictionary = info.get("pos", {})
	var start  := Vector3(pos_d.get("x", 0.0), 0.0, pos_d.get("z", 0.0))
	position   = start
	_target_pos = start

func _build_visuals() -> void:
	# Main mesh (role-based placeholder)
	_mesh = MeshInstance3D.new()
	_mesh.mesh = _mesh_for_role(role)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = COLOR_TEAM_A if team_id == "A" else COLOR_TEAM_B
	_mesh.material_override = mat
	add_child(_mesh)

	# Name label
	_label = Label3D.new()
	_label.text = hero_name
	_label.position = Vector3(0, 1.7, 0)
	_label.font_size = 28
	_label.modulate = Color.WHITE
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(_label)

	# HP bar (thin mesh above head)
	_hp_bar = _make_bar(Vector3(0, 2.0, 0), Color(0.2, 0.9, 0.2))
	add_child(_hp_bar)

	# Stamina bar (just below HP)
	_st_bar = _make_bar(Vector3(0, 1.75, 0), COLOR_ST)
	add_child(_st_bar)

	# Status label (controlled / panic / stunned / etc)
	_status_lbl = Label3D.new()
	_status_lbl.position = Vector3(0, 2.25, 0)
	_status_lbl.font_size = 22
	_status_lbl.modulate = Color(1, 0.85, 0)
	_status_lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_status_lbl.visible = false
	add_child(_status_lbl)

	# Effect icons (small text list)
	_effect_lbl = Label3D.new()
	_effect_lbl.position = Vector3(0, 2.5, 0)
	_effect_lbl.font_size = 18
	_effect_lbl.modulate = Color(0.8, 0.8, 0.8)
	_effect_lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(_effect_lbl)

func _process(delta: float) -> void:
	if _is_dead:
		return
	# Smooth interpolation between server-authoritative positions
	position      = position.lerp(_target_pos, delta * LERP_SPEED)
	rotation.y    = lerp_angle(rotation.y, _target_rot, delta * LERP_SPEED * 0.6)

func apply_snapshot(snap: Dictionary) -> void:
	var pos_d: Dictionary = snap.get("pos", {})
	_target_pos = Vector3(pos_d.get("x", position.x), 0.0, pos_d.get("z", position.z))
	_target_rot = snap.get("rot", rotation.y)

	var hp_pct: float  = snap.get("hp_pct", 1.0)
	var st_pct: float  = snap.get("stamina_pct", 1.0)
	var dead: bool     = snap.get("dead", false)
	var unc: bool      = snap.get("unconscious", false)
	var ctrl: String   = snap.get("control", "")
	var state: String  = snap.get("state", "")

	_update_hp_bar(hp_pct)
	_update_st_bar(st_pct)
	_update_status(ctrl, state, unc, dead)
	_update_effects(snap.get("effects", []))

	if dead and not _is_dead:
		_die()

func _die() -> void:
	_is_dead = true
	var mat := (_mesh.material_override as StandardMaterial3D)
	if mat:
		mat.albedo_color = Color(0.3, 0.3, 0.3)
	_mesh.rotation_degrees.x = 90.0
	_label.visible       = false
	_status_lbl.visible  = false
	_hp_bar.visible      = false
	_st_bar.visible      = false

func _update_hp_bar(pct: float) -> void:
	_hp_bar.scale.x = max(pct, 0.0)
	var mat := (_hp_bar.material_override as StandardMaterial3D)
	if not mat:
		return
	if pct > 0.5:
		mat.albedo_color = COLOR_HP_OK
	elif pct > 0.25:
		mat.albedo_color = COLOR_HP_LOW
	else:
		mat.albedo_color = COLOR_HP_CRT

func _update_st_bar(pct: float) -> void:
	_st_bar.scale.x = max(pct, 0.0)

func _update_status(ctrl: String, state: String, unc: bool, dead: bool) -> void:
	if dead:
		_status_lbl.text    = "DEAD"
		_status_lbl.visible = true
	elif unc:
		_status_lbl.text    = "KO"
		_status_lbl.visible = true
	elif ctrl != "":
		_status_lbl.text    = ctrl.to_upper()
		_status_lbl.visible = true
	elif state in ["retreat", "cast_skill", "channel_skill"]:
		_status_lbl.text    = state.replace("_", " ").to_upper()
		_status_lbl.visible = true
	else:
		_status_lbl.visible = false

func _update_effects(effects: Array) -> void:
	if effects.is_empty():
		_effect_lbl.visible = false
	else:
		_effect_lbl.text    = " ".join(PackedStringArray(effects))
		_effect_lbl.visible = true

# ── Mesh helpers ──────────────────────────────────────────────────────────────

func _mesh_for_role(r: String) -> Mesh:
	match r:
		"VANGUARD":
			var m := BoxMesh.new()
			m.size = Vector3(0.8, 1.6, 0.8)
			return m
		"STRIKER":
			var m := CapsuleMesh.new()
			m.radius = 0.35
			m.height = 1.6
			return m
		"CONTROLLER":
			var m := CylinderMesh.new()
			m.top_radius    = 0.3
			m.bottom_radius = 0.4
			m.height        = 1.6
			return m
		"SUPPORT":
			var m := SphereMesh.new()
			m.radius = 0.5
			m.height = 1.0
			return m
		_:  # TRANSFER
			var m := BoxMesh.new()
			m.size = Vector3(0.5, 1.4, 0.3)
			return m

func _make_bar(pos: Vector3, color: Color) -> MeshInstance3D:
	var bar  := MeshInstance3D.new()
	var bm   := BoxMesh.new()
	bm.size  = Vector3(1.0, 0.1, 0.05)
	bar.mesh = bm
	var mat  := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bar.material_override = mat
	bar.position = pos
	bar.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	return bar
