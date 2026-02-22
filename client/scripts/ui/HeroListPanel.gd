extends Control
class_name HeroListPanel

# UI Elements
@onready var list_container = $HeroScroll/ListContainer
@onready var generate_button = $GenerateButton
@onready var generate_dialog = $GenerateDialog

func _ready():
    # Connect signals
    Localization.locale_changed.connect(Callable(self, "_localize_ui"))
    generate_button.pressed.connect(Callable(self, "_on_generate_pressed"))
    
    # Load initial data
    _load_heroes()
    _localize_ui()

func _localize_ui():
    generate_button.text = Localization.t("generate")

func _load_heroes():
    var req = Network.request("/heroes", HTTPClient.METHOD_GET)
    req.request_completed.connect(Callable(self, "_on_heroes_response"))

func _on_heroes_response(result: int, code: int, headers, body: PackedByteArray):
    if code == 200:
        var parsed = JSON.parse_string(body.get_string_from_utf8())
        if parsed.error == OK:
            _populate_heroes(parsed.result)
            return
    UIUtils.show_error(Localization.t("load_heroes_failed"))

func _populate_heroes(heroes: Array):
    # Clear existing heroes
    for child in list_container.get_children():
        child.queue_free()
    
    # Add new heroes
    for hero in heroes:
        var hbox = HBoxContainer.new()
        
        # Add hero info
        var label = Label.new()
        label.text = "%s (Lvl %d)" % [hero.get("name", ""), hero.get("level", 0)]
        hbox.add_child(label)
        
        list_container.add_child(hbox)

func _on_generate_pressed():
    generate_dialog.popup_centered()
    generate_dialog.generate_requested.connect(Callable(self, "_on_generate_request"), CONNECT_ONE_SHOT)

func _on_generate_request(generation: int, currency: int):
    var data = {
        "generation": generation,
        "currency": currency
    }
    
    var req = Network.request("/heroes/generate", HTTPClient.METHOD_POST, data)
    req.request_completed.connect(Callable(self, "_on_generate_response"))

func _on_generate_response(result: int, code: int, headers, body: PackedByteArray):
    if code == 200:
        UIUtils.show_success(Localization.t("generate_success"))
        _load_heroes()  # Refresh hero list
    else:
        UIUtils.show_error(Localization.t("generate_hero_failed")) 