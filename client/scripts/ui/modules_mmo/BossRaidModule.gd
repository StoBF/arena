extends Control

## BossRaidModule — browse bosses, build a raid team, launch the raid,
## view the battle log and collect rewards.

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
var _bosses: Array = []
var _heroes: Array = []
var _selected_boss: Dictionary = {}
var _team_slots: Array = []            # Array of TeamSlotCard nodes
var _last_instance_id: int = -1        # last raid instance for battle/rewards

# ---------------------------------------------------------------------------
# UI nodes (built in code)
# ---------------------------------------------------------------------------
var _loading_overlay: LoadingOverlay = null
var _empty_state: EmptyState = null
var _boss_list: ItemList = null
var _boss_detail: DetailPanel = null
var _hero_list: ItemList = null
var _team_container: HBoxContainer = null
var _start_button: Button = null
var _battle_button: Button = null
var _rewards_button: Button = null
var _log_display: RichTextLabel = null
var _status_label: Label = null

const MAX_TEAM := 5

func _tx(key: String, fallback: String) -> String:
	var value: String = tr(key)
	if value == key:
		return fallback
	return value

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------
func _ready() -> void:
	_build_ui()
	call_deferred("_apply_cabinet_visuals")
	_load_data()

func _apply_cabinet_visuals() -> void:
	CabinetStyle.style_screen(self)
	if _status_label != null:
		CabinetStyle.style_status_label(_status_label)

# ---------------------------------------------------------------------------
# UI construction — 3-column layout
# ---------------------------------------------------------------------------
func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	CabinetStyle.style_module_root(root)
	add_child(root)

	# --- Header ---
	var header := ModuleHeader.new()
	root.add_child(header)
	header.set_title(_tx("ui.boss_raid.title", "Boss Raids"))
	header.refresh_pressed.connect(_load_data)

	# --- Main 3-column body ---
	var body := HBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	root.add_child(body)

	# Col 1 — Boss list
	var boss_panel := PanelContainer.new()
	boss_panel.custom_minimum_size = Vector2(200, 0)
	boss_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(boss_panel)
	var boss_vbox := VBoxContainer.new()
	boss_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	boss_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	boss_panel.add_child(boss_vbox)
	var boss_title := Label.new()
	boss_title.text = _tx("ui.boss_raid.bosses", "Bosses")
	boss_title.add_theme_font_size_override("font_size", 14)
	CabinetStyle.style_section_label(boss_title)
	boss_vbox.add_child(boss_title)
	_boss_list = ItemList.new()
	_boss_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_boss_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_boss_list.item_selected.connect(_on_boss_selected)
	boss_vbox.add_child(_boss_list)

	_loading_overlay = LoadingOverlay.new()
	boss_panel.add_child(_loading_overlay)
	_empty_state = EmptyState.new()
	_empty_state.visible = false
	boss_vbox.add_child(_empty_state)

	# Col 2 — Boss detail + battle log
	var detail_panel := PanelContainer.new()
	detail_panel.custom_minimum_size = Vector2(280, 0)
	detail_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(detail_panel)
	var detail_vbox := VBoxContainer.new()
	detail_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_vbox.add_theme_constant_override("separation", 6)
	detail_panel.add_child(detail_vbox)
	_boss_detail = DetailPanel.new()
	_boss_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_vbox.add_child(_boss_detail)

	var log_title := Label.new()
	log_title.text = _tx("ui.boss_raid.log_title", "Battle Log")
	log_title.add_theme_font_size_override("font_size", 13)
	detail_vbox.add_child(log_title)
	_log_display = RichTextLabel.new()
	_log_display.bbcode_enabled = true
	_log_display.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log_display.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log_display.custom_minimum_size = Vector2(0, 100)
	_log_display.text = "[i]%s[/i]" % _tx("ui.boss_raid.no_raid", "No raid started yet")
	detail_vbox.add_child(_log_display)

	# Col 3 — Team builder
	var team_panel := PanelContainer.new()
	team_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	team_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(team_panel)
	var team_vbox := VBoxContainer.new()
	team_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	team_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	team_vbox.add_theme_constant_override("separation", 8)
	team_panel.add_child(team_vbox)

	var heroes_title := Label.new()
	heroes_title.text = _tx("ui.boss_raid.hero_roster", "Hero Roster")
	heroes_title.add_theme_font_size_override("font_size", 14)
	team_vbox.add_child(heroes_title)
	_hero_list = ItemList.new()
	_hero_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hero_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_hero_list.item_activated.connect(_on_hero_double_clicked)
	team_vbox.add_child(_hero_list)

	var team_label := Label.new()
	team_label.text = _tx("ui.boss_raid.team_max", "Raid Team (max %d)") % MAX_TEAM
	team_label.add_theme_font_size_override("font_size", 13)
	team_vbox.add_child(team_label)
	_team_container = HBoxContainer.new()
	_team_container.add_theme_constant_override("separation", 6)
	team_vbox.add_child(_team_container)

	# Action buttons row
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 6)
	team_vbox.add_child(btn_row)

	_start_button = Button.new()
	_start_button.text = _tx("ui.boss_raid.start", "Start Raid")
	_start_button.custom_minimum_size = Vector2(0, 44)
	_start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_start_button.pressed.connect(_on_start_raid)
	btn_row.add_child(_start_button)

	_battle_button = Button.new()
	_battle_button.text = _tx("ui.boss_raid.fight", "Fight!")
	_battle_button.custom_minimum_size = Vector2(0, 44)
	_battle_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_battle_button.pressed.connect(_on_fight_raid)
	_battle_button.visible = false
	btn_row.add_child(_battle_button)

	_rewards_button = Button.new()
	_rewards_button.text = _tx("ui.boss_raid.collect_rewards", "Collect Rewards")
	_rewards_button.custom_minimum_size = Vector2(0, 44)
	_rewards_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rewards_button.pressed.connect(_on_collect_rewards)
	_rewards_button.visible = false
	btn_row.add_child(_rewards_button)

	# Footer status
	_status_label = Label.new()
	_status_label.text = ""
	root.add_child(_status_label)

	_rebuild_team_slots()

# ---------------------------------------------------------------------------
# Team slots
# ---------------------------------------------------------------------------
func _rebuild_team_slots() -> void:
	for slot in _team_slots:
		if is_instance_valid(slot):
			slot.queue_free()
	_team_slots.clear()
	for i in range(MAX_TEAM):
		var card := TeamSlotCard.new()
		card.custom_minimum_size = Vector2(90, 70)
		card.set_slot_index(i)
		card.hero_removed.connect(_on_hero_removed.bind(i))
		_team_container.add_child(card)
		_team_slots.append(card)

# ---------------------------------------------------------------------------
# Data loading
# ---------------------------------------------------------------------------
func _load_data() -> void:
	_loading_overlay.show_loading()
	_empty_state.visible = false
	_boss_list.clear()
	_hero_list.clear()
	_bosses.clear()
	_heroes.clear()
	_selected_boss = {}

	# Load bosses
	var boss_resp: Dictionary = await ApiClient.get_bosses()
	if bool(boss_resp.get("ok", false)):
		_bosses = ResponseParser.extract_array(boss_resp.get("data", {}))

	for b in _bosses:
		if b is Dictionary:
			_boss_list.add_item("%s  (Lv.%s)" % [
				str(b.get("name", "?")), str(b.get("level", "?"))])

	if _bosses.is_empty():
		_empty_state.visible = true
		if _empty_state.has_method("set_content"):
			_empty_state.set_content(
				_tx("ui.boss_raid.unavailable_title", "No Boss Raids Available"),
				_tx("ui.boss_raid.unavailable_hint", "Boss raid data is currently unavailable.")
			)
	else:
		_empty_state.visible = false

	# Load heroes — H8: Use HeroManager (canonical cache, avoids direct ApiClient)
	await HeroManager.load_heroes()
	_loading_overlay.hide_loading()
	var all: Array = HeroManager.get_heroes()
	for h in all:
		if not h is Dictionary:
			continue
		var hero := h as Dictionary
		if not bool(hero.get("is_dead", false)) and not bool(hero.get("is_training", false)):
			_heroes.append(hero)

	for h in _heroes:
		if h is Dictionary:
			_hero_list.add_item("%s  (Lv.%s)" % [
				str(h.get("name", "?")), str(h.get("level", "?"))])
	_status_label.text = _tx("ui.boss_raid.status", "%d bosses · %d heroes") % [_bosses.size(), _heroes.size()]

# ---------------------------------------------------------------------------
# Boss selection
# ---------------------------------------------------------------------------
func _on_boss_selected(index: int) -> void:
	if index < 0 or index >= _bosses.size():
		return
	_selected_boss = _bosses[index] as Dictionary
	_boss_detail.set_title(str(_selected_boss.get("name", "Boss")))
	_boss_detail.set_fields({
		"Level": str(_selected_boss.get("level", "-")),
		"Rewards": str(_selected_boss.get("rewards", "-")),
		"Description": str(_selected_boss.get("description", "")),
	})
	# Reset action flow
	_last_instance_id = -1
	_start_button.visible = true
	_battle_button.visible = false
	_rewards_button.visible = false
	_log_display.text = "[i]%s[/i]" % _tx("ui.boss_raid.select_and_start", "Select heroes and start the raid")

# ---------------------------------------------------------------------------
# Team interaction
# ---------------------------------------------------------------------------
func _on_hero_double_clicked(index: int) -> void:
	if index < 0 or index >= _heroes.size():
		return
	var hero := _heroes[index] as Dictionary
	var hero_id: int = int(hero.get("id", -1))
	# Prevent duplicates
	for slot in _team_slots:
		if slot.get_hero_id() == hero_id:
			UIUtils.show_warning("Hero already in raid team")
			return
	for slot in _team_slots:
		if slot.is_empty_slot():
			slot.set_hero(hero)
			return
	UIUtils.show_warning("Raid team is full (%d max)" % MAX_TEAM)

func _on_hero_removed(slot_index: int) -> void:
	if slot_index >= 0 and slot_index < _team_slots.size():
		var slot = _team_slots[slot_index]
		if slot.has_method("clear_slot"):
			slot.clear_slot()

# ---------------------------------------------------------------------------
# Raid flow: Start → Fight → Collect Rewards
# ---------------------------------------------------------------------------
func _on_start_raid() -> void:
	if _selected_boss.is_empty():
		UIUtils.show_warning("Select a boss first")
		return
	var hero_ids: Array = _collect_team_ids()
	if hero_ids.is_empty():
		UIUtils.show_warning("Add at least one hero to the team")
		return

	var boss_id: int = int(_selected_boss.get("id", -1))
	_status_label.text = "Starting raid..."
	_start_button.disabled = true
	var response: Dictionary = await ApiClient.start_boss_raid(boss_id, hero_ids)
	_start_button.disabled = false

	if bool(response.get("ok", false)):
		var data: Variant = response.get("data", {})
		if data is Dictionary:
			_last_instance_id = int((data as Dictionary).get("id",
				(data as Dictionary).get("instance_id", -1)))
		UIUtils.show_success("Raid started against %s!" % str(_selected_boss.get("name", "Boss")))
		_log_display.text = "[b]Raid instance created.[/b]\nPress [b]Fight![/b] to begin the battle."
		_start_button.visible = false
		_battle_button.visible = true
		_rewards_button.visible = false
	else:
		var msg: String = str(response.get("message", response.get("error", "Raid failed")))
		UIUtils.show_error(msg)
		_log_display.text = "[color=red]%s[/color]" % msg
	_status_label.text = ""

func _on_fight_raid() -> void:
	if _last_instance_id < 0:
		UIUtils.show_warning("No active raid instance")
		return
	_status_label.text = "Fighting..."
	_battle_button.disabled = true
	var response: Dictionary = await ApiClient.raid_battle(_last_instance_id)
	_battle_button.disabled = false

	if bool(response.get("ok", false)):
		var data: Variant = response.get("data", {})
		_render_battle_log(data)
		_battle_button.visible = false
		_rewards_button.visible = true
	else:
		var msg: String = str(response.get("message", response.get("error", "Battle failed")))
		UIUtils.show_error(msg)
		_log_display.text = "[color=red]%s[/color]" % msg
	_status_label.text = ""

func _on_collect_rewards() -> void:
	if _last_instance_id < 0:
		UIUtils.show_warning("No raid to collect rewards from")
		return
	_status_label.text = "Collecting rewards..."
	_rewards_button.disabled = true
	var response: Dictionary = await ApiClient.raid_rewards(_last_instance_id)
	_rewards_button.disabled = false

	if bool(response.get("ok", false)):
		var rewards: Array = ResponseParser.extract_array(response.get("data", {}))
		var lines: PackedStringArray = ["[b]Rewards:[/b]"]
		for r in rewards:
			if r is Dictionary:
				lines.append("• %s x%s" % [
					str(r.get("name", r.get("item", "Reward"))),
					str(r.get("quantity", r.get("amount", 1))),
				])
		if lines.size() == 1:
			lines.append("No rewards dropped")
		_log_display.text += "\n\n" + "\n".join(lines)
		UIUtils.show_success("Rewards collected!")
		_rewards_button.visible = false
		_start_button.visible = true
		_last_instance_id = -1
	else:
		var msg: String = str(response.get("message", response.get("error", "Rewards failed")))
		UIUtils.show_error(msg)
	_status_label.text = ""

# ---------------------------------------------------------------------------
# Battle log rendering
# ---------------------------------------------------------------------------
func _render_battle_log(data: Variant) -> void:
	if data is Dictionary == false:
		_log_display.text = "[i]Battle complete — no log returned[/i]"
		return
	var d := data as Dictionary
	var winner: String = str(d.get("winner", "unknown"))
	var log_entries: Array = d.get("log", []) as Array if d.get("log") is Array else []
	var lines: PackedStringArray = [
		"[b]Winner:[/b] %s" % winner.capitalize(),
		"",
	]
	for entry in log_entries:
		lines.append("• %s" % str(entry))
	if log_entries.is_empty():
		lines.append("[i]No detailed log available[/i]")

	var remaining_a: Array = d.get("team_a_remaining", []) as Array if d.get("team_a_remaining") is Array else []
	var remaining_b: Array = d.get("team_b_remaining", []) as Array if d.get("team_b_remaining") is Array else []
	if remaining_a is Array and not (remaining_a as Array).is_empty():
		lines.append("\n[b]Survivors:[/b] %d heroes" % (remaining_a as Array).size())
	_log_display.text = "\n".join(lines)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
func _collect_team_ids() -> Array:
	var ids: Array = []
	for slot in _team_slots:
		var hid: int = slot.get_hero_id()
		if hid > 0:
			ids.append(hid)
	return ids
