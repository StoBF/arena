extends Control
## ClanBrowserScene.gd
## Displays a searchable list of clans with territory filters.
## Connect to a parent container in your main menu.
##
## Signals:
##   clan_selected(clan_id: int)     — emitted when player taps a clan row
##   create_clan_pressed()           — emitted when player taps "Create Clan"

signal clan_selected(clan_id: int)
signal create_clan_pressed()

# ── Node refs (assign in editor or via code) ─────────────────────────────────
@onready var country_edit:       LineEdit = $Filters/CountryEdit
@onready var city_edit:          LineEdit = $Filters/CityEdit
@onready var mode_option:        OptionButton = $Filters/ModeOption
@onready var search_button:      Button   = $Filters/SearchButton
@onready var create_button:      Button   = $CreateButton
@onready var clan_list:          VBoxContainer = $ScrollContainer/ClanList
@onready var loading_label:      Label    = $LoadingLabel

# ── State ─────────────────────────────────────────────────────────────────────
var _clans: Array = []

func _ready() -> void:
	search_button.pressed.connect(_on_search)
	create_button.pressed.connect(func(): emit_signal("create_clan_pressed"))
	_populate_mode_options()
	await _load_clans({})

func _populate_mode_options() -> void:
	mode_option.clear()
	mode_option.add_item("Any mode",    0)
	mode_option.add_item("Casual",      1)
	mode_option.add_item("Competitive", 2)
	mode_option.add_item("PvE",         3)
	mode_option.add_item("PvP",         4)
	mode_option.add_item("Mixed",       5)

func _on_search() -> void:
	var filters := {}
	if country_edit.text.strip_edges() != "":
		filters["country_code"] = country_edit.text.strip_edges().left(4)
	if city_edit.text.strip_edges() != "":
		filters["city_name"] = city_edit.text.strip_edges()
	var modes := ["", "casual", "competitive", "pve", "pvp", "mixed"]
	var idx := mode_option.selected
	if idx > 0 and idx < modes.size():
		filters["clan_mode"] = modes[idx]
	await _load_clans(filters)

func _load_clans(filters: Dictionary) -> void:
	loading_label.visible = true
	_clear_list()
	_clans = await ApiClient.search_clans(filters)
	loading_label.visible = false
	_render_list()

func _render_list() -> void:
	_clear_list()
	if _clans.is_empty():
		var lbl := Label.new()
		lbl.text = "No clans found. Try different filters or create your own!"
		clan_list.add_child(lbl)
		return
	for clan in _clans:
		clan_list.add_child(_make_clan_row(clan))

func _clear_list() -> void:
	for c in clan_list.get_children():
		c.queue_free()

func _make_clan_row(clan: Dictionary) -> Control:
	var row  := HBoxContainer.new()
	var info := VBoxContainer.new()

	var name_lbl := Label.new()
	name_lbl.text = "[Lv%d] %s" % [clan.get("level", 1), clan.get("name", "?")]

	var detail_lbl := Label.new()
	detail_lbl.text = "%s · %s · %d members" % [
		clan.get("city_name", ""),
		clan.get("clan_mode", ""),
		clan.get("member_count", 0),
	]
	detail_lbl.add_theme_font_size_override("font_size", 11)

	info.add_child(name_lbl)
	info.add_child(detail_lbl)
	row.add_child(info)

	var join_btn := Button.new()
	join_btn.text = "View"
	var clan_id: int = clan.get("id", 0)
	join_btn.pressed.connect(func(): emit_signal("clan_selected", clan_id))
	row.add_child(join_btn)
	return row
