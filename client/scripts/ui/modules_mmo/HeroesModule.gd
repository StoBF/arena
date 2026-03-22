extends Control

## HeroesModule — roster management, hero inspection, skills, and body parts.

const HERO_CARD_SCENE := preload("res://scenes/ui/components/HeroCard.tscn")

@onready var cards_grid: GridContainer = $Root/Body/RosterPanel/RosterMargin/CardsScroll/CardsGrid
@onready var refresh_button: Button = $Root/Header/RefreshButton
@onready var detail_name: Label = $Root/Body/DetailPanel/DetailMargin/DetailVBox/DetailName
@onready var detail_role: Label = $Root/Body/DetailPanel/DetailMargin/DetailVBox/DetailRole
@onready var detail_stats: RichTextLabel = $Root/Body/DetailPanel/DetailMargin/DetailVBox/DetailStats
@onready var tags_label: Label = $Root/Body/DetailPanel/DetailMargin/DetailVBox/TagsLabel
@onready var skills_title: Label = $Root/Body/DetailPanel/DetailMargin/DetailVBox/SkillsSection/SkillsTitle
@onready var skills_list: ItemList = $Root/Body/DetailPanel/DetailMargin/DetailVBox/SkillsSection/SkillsList
@onready var skill_detail_panel: PanelContainer = $Root/Body/DetailPanel/DetailMargin/DetailVBox/SkillsSection/SkillDetailPanel
@onready var skill_detail_content: RichTextLabel = $Root/Body/DetailPanel/DetailMargin/DetailVBox/SkillsSection/SkillDetailPanel/SkillDetailContent
@onready var status_label: Label = $Root/StatusLabel

var _selected_hero: Dictionary = {}
var _parsed_skills: Array[Dictionary] = []
var _loading_overlay: Node = null
var _empty_state: Node = null
var _status_pill: Node = null
var _body_parts_container: VBoxContainer = null
var _is_loading: bool = false

func _tx(key: String, fallback: String) -> String:
	return CabinetStyle.text(key, fallback)

func _ready() -> void:
	if refresh_button == null or status_label == null:
		push_warning("HeroesModule nodes are not ready; skipping initialization")
		return
	if not refresh_button.pressed.is_connected(_on_refresh_pressed):
		refresh_button.pressed.connect(_on_refresh_pressed)
	if skills_list != null and not skills_list.item_selected.is_connected(_on_skill_selected):
		skills_list.item_selected.connect(_on_skill_selected)
	_create_overlays()
	_connect_hero_signals()
	call_deferred("_apply_cabinet_visuals")
	call_deferred("_bootstrap_heroes")

func _exit_tree() -> void:
	_disconnect_hero_signals()

func _apply_cabinet_visuals() -> void:
	CabinetStyle.style_screen(self)
	CabinetStyle.style_header($Root/Header/Title, refresh_button)
	CabinetStyle.style_status_label(status_label)

func _create_overlays() -> void:
	_loading_overlay = LoadingOverlay.new()
	$Root/Body/RosterPanel.add_child(_loading_overlay)
	_empty_state = EmptyState.new()
	_empty_state.visible = false
	$Root/Body/RosterPanel/RosterMargin.add_child(_empty_state)
	# Status pill in detail panel (under name)
	_status_pill = StatusPill.new()
	var detail_vbox: VBoxContainer = $Root/Body/DetailPanel/DetailMargin/DetailVBox
	detail_vbox.add_child(_status_pill)
	detail_vbox.move_child(_status_pill, 2)  # after DetailName + DetailRole
	# Body parts section
	_body_parts_container = VBoxContainer.new()
	_body_parts_container.name = "BodyPartsSection"
	var bp_title := Label.new()
	bp_title.text = _tx("HEROES_BODY_PARTS", "Body Parts")
	_body_parts_container.add_child(bp_title)
	detail_vbox.add_child(_body_parts_container)

func _connect_hero_signals() -> void:
	if HeroManager != null:
		if HeroManager.heroes_updated.is_connected(_on_heroes_updated) == false:
			HeroManager.heroes_updated.connect(_on_heroes_updated)
		if HeroManager.heroes_load_failed.is_connected(_on_heroes_load_failed) == false:
			HeroManager.heroes_load_failed.connect(_on_heroes_load_failed)

func _disconnect_hero_signals() -> void:
	if HeroManager == null:
		return
	if HeroManager.heroes_updated.is_connected(_on_heroes_updated):
		HeroManager.heroes_updated.disconnect(_on_heroes_updated)
	if HeroManager.heroes_load_failed.is_connected(_on_heroes_load_failed):
		HeroManager.heroes_load_failed.disconnect(_on_heroes_load_failed)

func _bootstrap_heroes() -> void:
	if cards_grid == null:
		return
	var cached_heroes: Array = HeroManager.get_heroes()
	if not cached_heroes.is_empty():
		_render_heroes(cached_heroes)
	status_label.text = _tx("HEROES_LOADING", "Loading heroes...")
	_load_heroes(true)

func _on_refresh_pressed() -> void:
	_load_heroes(true)

func _load_heroes(force_refresh: bool = false) -> void:
	if _is_loading:
		return
	_is_loading = true
	status_label.text = _tx("HEROES_LOADING", "Loading heroes...")
	if _loading_overlay != null:
		_loading_overlay.show_loading()
	_empty_state.visible = false
	if force_refresh or HeroManager.get_heroes().is_empty():
		await HeroManager.load_heroes()
	else:
		_on_heroes_updated(HeroManager.get_heroes())
	if _loading_overlay != null:
		_loading_overlay.hide_loading()
	_is_loading = false

func _on_heroes_updated(heroes: Array[Dictionary]) -> void:
	var normalized: Array = []
	for hero in heroes:
		normalized.append(hero.duplicate(true))
	_render_heroes(normalized)

func _on_heroes_load_failed(message: String) -> void:
	if _loading_overlay != null:
		_loading_overlay.hide_loading()
	_is_loading = false
	status_label.text = _tx("HEROES_LOAD_FAILED", "Failed to load heroes")
	if not message.is_empty():
		UIUtils.show_error(message)

func _render_heroes(heroes: Array) -> void:
	for child in cards_grid.get_children():
		child.queue_free()
	if heroes.is_empty():
		_empty_state.visible = true
		if _empty_state.has_method("set_content"):
			_empty_state.set_content(
				_tx("HEROES_NO_HEROES", "No Heroes"),
				_tx("HEROES_RECRUIT_HINT", "Recruit or create a hero to begin."))
		status_label.text = ""
		return
	_empty_state.visible = false
	for hero_variant in heroes:
		if not hero_variant is Dictionary:
			continue
		var card: Control = HERO_CARD_SCENE.instantiate()
		cards_grid.add_child(card)
		if card.has_method("set_hero"):
			card.set_hero(hero_variant as Dictionary)
		if card.has_signal("selected") and not card.selected.is_connected(_on_card_selected):
			card.selected.connect(_on_card_selected)
	var selected_id: int = int(AppState.selected_hero.get("id", HeroManager.get_active_hero_id()))
	var selected_from_list: Dictionary = _find_hero_by_id(heroes, selected_id)
	if selected_from_list.is_empty() and not heroes.is_empty() and heroes[0] is Dictionary:
		selected_from_list = (heroes[0] as Dictionary).duplicate(true)
	if not selected_from_list.is_empty():
		_apply_hero_details(selected_from_list)
		HeroManager.set_active_hero_id(int(selected_from_list.get("id", -1)))
	status_label.text = "%d heroes" % heroes.size()

func _on_card_selected(hero_id: int) -> void:
	var hero: Dictionary = HeroManager.get_hero_by_id(hero_id)
	if hero.is_empty():
		UIUtils.show_warning(_tx("HEROES_SELECT_FIRST", "Select a hero first"))
		return
	_apply_hero_details(hero)
	HeroManager.set_active_hero_id(hero_id)


# ─── Hero detail rendering ───────────────────────────────────────

func _apply_hero_details(hero: Dictionary) -> void:
	_selected_hero = hero.duplicate(true)

	# Parse through UIModels for safe typed access
	var parsed: Dictionary = UIModels.hero_full(hero)

	# Name
	detail_name.text = str(parsed.get("name", "-"))

	# Roles
	var primary: String = str(parsed.get("primary_role", "")).capitalize()
	var secondary: String = str(parsed.get("secondary_role", "")).capitalize()
	if primary.is_empty() or primary == "None":
		primary = "-"
	var role_text: String = primary
	if not secondary.is_empty() and secondary != "None" and secondary != primary:
		role_text += " / " + secondary
	detail_role.text = role_text

	# Status pill
	var condition: String = str(parsed.get("condition", "healthy")).to_lower()
	if _status_pill != null and _status_pill.has_method("set_status"):
		_status_pill.set_status(condition)

	# Stats block (v2 stats)
	detail_stats.text = _build_stats_block(parsed)

	# Tags
	var tags: Array = parsed.get("tags", []) as Array
	var tag_labels: PackedStringArray = UIModels.top_tags(tags, 6)
	if tag_labels.is_empty():
		tags_label.text = ""
		tags_label.visible = false
	else:
		tags_label.text = ", ".join(tag_labels)
		tags_label.visible = true

	# Skills
	_parsed_skills.clear()
	var skills: Array = parsed.get("skills", []) as Array
	for s_variant: Variant in skills:
		if s_variant is Dictionary:
			_parsed_skills.append(s_variant as Dictionary)
	_render_skill_list()

	# Clear skill detail
	_clear_skill_detail()

	# Body parts
	_render_body_parts(parsed)


func _build_stats_block(parsed: Dictionary) -> String:
	var stats: Dictionary = parsed.get("stats", {}) as Dictionary
	var derived: Dictionary = parsed.get("derived_stats", {}) as Dictionary
	var lines: PackedStringArray = []

	# Generation info
	lines.append("[b]Gen Level:[/b] %d  [b]Version:[/b] %d" % [
		int(parsed.get("hero_generation_level", 1)),
		int(parsed.get("generation_version", 2)),
	])
	lines.append("")

	# Core stats (v2)
	lines.append("[b]— Core Stats —[/b]")
	var stat_names: Array[String] = ["stamina", "strength", "willpower", "reflex", "resilience", "focus", "adaptability", "luck"]
	for stat_name: String in stat_names:
		lines.append("[b]%s:[/b] %d" % [stat_name.capitalize(), int(stats.get(stat_name, 0))])

	# Derived stats
	if not derived.is_empty():
		lines.append("")
		lines.append("[b]— Derived —[/b]")
		if derived.has("max_hp"):
			lines.append("[b]Max HP:[/b] %d" % int(derived.get("max_hp", 0)))
		if derived.has("initiative"):
			lines.append("[b]Initiative:[/b] %d" % int(derived.get("initiative", 0)))
		if derived.has("accuracy"):
			lines.append("[b]Accuracy:[/b] %d" % int(derived.get("accuracy", 0)))
		if derived.has("evasion"):
			lines.append("[b]Evasion:[/b] %d" % int(derived.get("evasion", 0)))
		if derived.has("critical_chance") and float(derived.get("critical_chance", 0.0)) > 0.0:
			lines.append("[b]Crit Chance:[/b] %.1f%%" % (float(derived.get("critical_chance", 0.0)) * 100.0))

	# Combat counters
	var kills: int = int(parsed.get("total_kills", 0))
	var deaths: int = int(parsed.get("total_deaths", 0))
	if kills > 0 or deaths > 0:
		lines.append("")
		lines.append("[b]Kills:[/b] %d  [b]Deaths:[/b] %d" % [kills, deaths])

	return "\n".join(lines)


# ─── Skill list & detail ─────────────────────────────────────────

func _render_skill_list() -> void:
	if skills_list == null:
		return
	skills_list.clear()
	if _parsed_skills.is_empty():
		skills_title.text = _tx("HEROES_SKILLS", "Skills (0)")
		return
	skills_title.text = "Skills (%d)" % _parsed_skills.size()
	for sk: Dictionary in _parsed_skills:
		var display: String = str(sk.get("display_name", sk.get("skill_code", "?")))
		var family: String = str(sk.get("skill_family", "")).capitalize()
		var label: String = display
		if not family.is_empty():
			label += "  [%s]" % family
		if bool(sk.get("is_signature", false)):
			label += "  *"
		skills_list.add_item(label)


func _on_skill_selected(index: int) -> void:
	if index < 0 or index >= _parsed_skills.size():
		_clear_skill_detail()
		return
	var sk: Dictionary = _parsed_skills[index]
	_show_skill_detail(sk)


func _clear_skill_detail() -> void:
	if skill_detail_panel != null:
		skill_detail_panel.visible = false
	if skill_detail_content != null:
		skill_detail_content.text = ""


func _show_skill_detail(sk: Dictionary) -> void:
	if skill_detail_panel == null or skill_detail_content == null:
		return
	skill_detail_panel.visible = true

	var lines: PackedStringArray = []
	var name_text: String = str(sk.get("display_name", sk.get("skill_code", "?")))
	lines.append("[b]%s[/b]" % name_text)

	# Family & cast info
	var family: String = str(sk.get("skill_family", "")).capitalize()
	var cast_type: String = str(sk.get("cast_type", "")).capitalize()
	if not family.is_empty() or not cast_type.is_empty():
		lines.append("[b]Category:[/b] %s  |  [b]Cast:[/b] %s" % [family, cast_type])

	# Targeting
	var target_type: String = str(sk.get("target_type", "")).capitalize()
	var target_team: String = str(sk.get("target_team", "")).capitalize()
	if not target_type.is_empty():
		lines.append("[b]Target:[/b] %s  |  [b]Team:[/b] %s" % [target_type, target_team])

	# Short description
	var desc_short: String = str(sk.get("description_short", ""))
	if not desc_short.is_empty():
		lines.append("")
		lines.append("[i]%s[/i]" % desc_short)

	lines.append("")

	# Instance values
	var stamina_cost: int = int(sk.get("stamina_cost_value", 0))
	var cooldown: float = float(sk.get("cooldown_value", 0.0))
	var power: int = int(sk.get("power_value", 0))
	var duration: float = float(sk.get("duration_value", 0.0))
	var radius: float = float(sk.get("radius_value", 0.0))

	if stamina_cost > 0:
		lines.append("[b]Stamina Cost:[/b] %d" % stamina_cost)
	if cooldown > 0.0:
		lines.append("[b]Cooldown:[/b] %.1fs" % cooldown)
	if power > 0:
		lines.append("[b]Power:[/b] %d" % power)
	if duration > 0.0:
		lines.append("[b]Duration:[/b] %.1fs" % duration)
	if radius > 0.0:
		lines.append("[b]Radius:[/b] %.1f" % radius)

	# Flags
	var catalog: Dictionary = sk.get("catalog", {}) as Dictionary
	var flags: PackedStringArray = []
	if not catalog.is_empty():
		if bool(catalog.get("is_interruptible", false)):
			flags.append("Interruptible")
		if bool(catalog.get("is_redirectable", false)):
			flags.append("Redirectable")
		if bool(catalog.get("is_stealable", false)):
			flags.append("Stealable")
		if bool(catalog.get("is_upgradable", false)):
			flags.append("Upgradable")
		if bool(catalog.get("has_kill_trigger", false)):
			flags.append("Kill Trigger")
		if not bool(catalog.get("requires_vision", true)):
			flags.append("No Vision Required")
		var control_tier: Variant = catalog.get("control_tier", null)
		if control_tier != null and int(control_tier) > 0:
			flags.append("CC Tier %d" % int(control_tier))

	if not flags.is_empty():
		lines.append("")
		lines.append("[b]Flags:[/b] %s" % ", ".join(flags))

	# Effects
	var effects: Array = sk.get("effects", []) as Array
	if not effects.is_empty():
		lines.append("")
		lines.append("[b]— Effects —[/b]")
		for eff_variant: Variant in effects:
			if not (eff_variant is Dictionary):
				continue
			var eff: Dictionary = eff_variant as Dictionary
			var etype: String = str(eff.get("effect_type", "")).capitalize()
			var etarget: String = str(eff.get("effect_target", "")).capitalize()
			var evalue: float = float(eff.get("effect_value", 0.0))
			lines.append("  %s → %s: %.1f" % [etype, etarget, evalue])

	# Upgrade / signature
	var upgrade_count: int = int(sk.get("upgrade_count", 0))
	if upgrade_count > 0:
		lines.append("")
		lines.append("[b]Upgrades:[/b] %d" % upgrade_count)
	if bool(sk.get("is_signature", false)):
		lines.append("[color=gold][b]★ Signature Skill[/b][/color]")

	# Full description
	var catalog_for_desc: Dictionary = sk.get("catalog", {}) as Dictionary
	var desc_full: String = str(catalog_for_desc.get("description_full", ""))
	if not desc_full.is_empty():
		lines.append("")
		lines.append("[b]Details:[/b]")
		lines.append(desc_full)

	skill_detail_content.text = "\n".join(lines)


# ─── Body parts ──────────────────────────────────────────────────

func _render_body_parts(hero: Dictionary) -> void:
	if _body_parts_container == null:
		return
	while _body_parts_container.get_child_count() > 1:
		_body_parts_container.get_child(_body_parts_container.get_child_count() - 1).queue_free()
	var body_parts: Array = []
	if hero.has("body_parts") and hero["body_parts"] is Array:
		body_parts = hero["body_parts"] as Array
	if body_parts.is_empty():
		for part_name: String in ["Head", "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg"]:
			var row := BodyPartStatusRow.new()
			_body_parts_container.add_child(row)
			if row.has_method("set_data"):
				row.set_data(part_name, 100.0, 100.0, "healthy")
	else:
		for bp_variant: Variant in body_parts:
			if not bp_variant is Dictionary:
				continue
			var bp := bp_variant as Dictionary
			var row := BodyPartStatusRow.new()
			_body_parts_container.add_child(row)
			if row.has_method("set_data"):
				var part_name: String = str(bp.get("part_name", bp.get("name", "?")))
				var part_status: String = str(bp.get("status", bp.get("condition", "healthy")))
				row.set_data(
					part_name,
					float(bp.get("current_hp", 100)),
					float(bp.get("max_hp", 100)),
					part_status)


# ─── Helpers ─────────────────────────────────────────────────────

func _find_hero_by_id(heroes: Array, hero_id: int) -> Dictionary:
	if hero_id <= 0:
		return {}
	for hero_variant in heroes:
		if hero_variant is Dictionary == false:
			continue
		var hero := hero_variant as Dictionary
		if int(hero.get("id", -1)) == hero_id:
			return hero.duplicate(true)
	return {}
