extends Control
class_name HeroListPanel

# UI Elements
@onready var list_container = $HeroScroll/ListContainer
@onready var generate_button = $GenerateButton
@onready var generate_dialog = $GenerateDialog

func _ready():
    # TopBar replaces the old BackToDashboardButton
    TopBar.add_to(self, true, true)
    print("[HeroList] _ready() START")
    # Connect signals
    Localization.locale_changed.connect(Callable(self, "_localize_ui"))
    if generate_button:
        generate_button.pressed.connect(Callable(self, "_on_generate_pressed"))
    else:
        print("[HeroList] WARN: GenerateButton is NULL")

    # Load initial data
    _load_heroes()
    _localize_ui()

func _localize_ui():
    if generate_button:
        generate_button.text = Localization.t("generate") if Localization.has_key("generate") else "Generate"

func _load_heroes():
    print("[HeroList] Loading heroes from server")
    var req = Network.request("/heroes/", HTTPClient.METHOD_GET)
    req.request_completed.connect(Callable(self, "_on_heroes_response"))

func _on_heroes_response(result: int, code: int, headers, body: PackedByteArray):
    print("[HeroList] _on_heroes_response code=%d" % code)
    if result == HTTPRequest.RESULT_SUCCESS and code == 200:
        var json = JSON.new()
        var err = json.parse(body.get_string_from_utf8())
        if err == OK:
            var parsed = json.data
            var heroes_arr: Array = []
            if typeof(parsed) == TYPE_DICTIONARY and parsed.has("result"):
                heroes_arr = parsed["result"]
            elif typeof(parsed) == TYPE_ARRAY:
                heroes_arr = parsed
            _populate_heroes(heroes_arr)
            return
        print("[HeroList] JSON parse error: %d" % err)
    UIUtils.show_error(Localization.t("load_heroes_failed") if Localization.has_key("load_heroes_failed") else "Failed to load heroes")

func _populate_heroes(heroes: Array):
    if not list_container:
        print("[HeroList] WARN: list_container is NULL")
        return
    # Clear existing heroes
    for child in list_container.get_children():
        child.queue_free()

    # Add clickable hero cards
    var card_scene = preload("res://scenes/ui/HeroCard.tscn")
    for hero in heroes:
        var card = card_scene.instantiate() as HeroCard
        card.set_data(hero)
        card.hero_selected.connect(func(data):
            AppState.current_hero_id = data.get("id", -1)
            print("[HeroList] Selected hero: %s (id=%s)" % [data.get("name", "?"), str(data.get("id", "?"))])
        )
        list_container.add_child(card)
    print("[HeroList] Populated %d hero cards" % heroes.size())

func _on_generate_pressed():
    Nav.go("GenerateHero")