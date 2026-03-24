extends Control
## ClanCreateScene.gd
## Form for creating a new clan.

signal clan_created(clan: Dictionary)
signal back_pressed()

@onready var name_edit:       LineEdit    = $Form/NameEdit
@onready var description_edit:TextEdit    = $Form/DescriptionEdit
@onready var country_edit:    LineEdit    = $Form/CountryEdit
@onready var region_edit:     LineEdit    = $Form/RegionEdit
@onready var city_edit:       LineEdit    = $Form/CityEdit
@onready var mode_option:     OptionButton = $Form/ModeOption
@onready var type_option:     OptionButton = $Form/TypeOption
@onready var recruit_option:  OptionButton = $Form/RecruitOption
@onready var offline_check:   CheckBox    = $Form/OfflineCheck
@onready var create_button:   Button      = $Form/CreateButton
@onready var back_button:     Button      = $BackButton
@onready var error_label:     Label       = $ErrorLabel

const MODES    := ["casual", "competitive", "pve", "pvp", "mixed"]
const TYPES    := ["local", "regional", "international"]
const RECRUITS := ["open", "by_application", "invite_only"]

func _ready() -> void:
	create_button.pressed.connect(_on_create)
	back_button.pressed.connect(func(): emit_signal("back_pressed"))
	_fill_options(mode_option,   ["Casual", "Competitive", "PvE", "PvP", "Mixed"])
	_fill_options(type_option,   ["Local", "Regional", "International"])
	_fill_options(recruit_option, ["Open", "By Application", "Invite Only"])
	error_label.visible = false

func _fill_options(btn: OptionButton, labels: Array) -> void:
	btn.clear()
	for i in labels.size():
		btn.add_item(labels[i], i)

func _on_create() -> void:
	error_label.visible = false
	var clan_name := name_edit.text.strip_edges()
	if clan_name.length() < 3:
		_show_error("Clan name must be at least 3 characters")
		return
	if country_edit.text.strip_edges().length() < 2:
		_show_error("Country code is required (2-4 chars)")
		return

	create_button.disabled = true
	var result = await ApiClient.create_clan({
		"name":             clan_name,
		"description":      description_edit.text.strip_edges(),
		"country_code":     country_edit.text.strip_edges().left(4),
		"region_name":      region_edit.text.strip_edges(),
		"city_name":        city_edit.text.strip_edges(),
		"language":         "en",
		"clan_type":        TYPES[type_option.selected],
		"clan_mode":        MODES[mode_option.selected],
		"offline_friendly": offline_check.button_pressed,
		"recruitment_mode": RECRUITS[recruit_option.selected],
	})
	create_button.disabled = false

	if result is Dictionary and result.has("id"):
		emit_signal("clan_created", result)
	else:
		_show_error(str(result.get("detail", "Failed to create clan")))

func _show_error(msg: String) -> void:
	error_label.text = msg
	error_label.visible = true
