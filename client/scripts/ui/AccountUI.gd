extends Control
class_name AccountUI

# This controller coordinates the main windows and applies the consistent style.
# It assumes that each 'page' will be another scene added to ContentStack.

@onready var nickname_label = $TopBar/Nickname
@onready var currency_label = $TopBar/Currency
@onready var sidebar = $MainHBox/Sidebar
@onready var content_stack = $MainHBox/ContentStack
@onready var stats_panel = $MainHBox/StatsPanel/StatPanelInstance
@onready var chat_panel = $ChatSection/Chat

var heroes := []
var selected_hero = null

func _ready():
    # wire sidebar buttons
    $MainHBox/Sidebar/CreateHero.pressed.connect(func(): _show_page("CreateHero"))
    $MainHBox/Sidebar/TrainHero.pressed.connect(func(): _show_page("TrainHero"))
    $MainHBox/Sidebar/Auction.pressed.connect(func(): _show_page("Auction"))
    $MainHBox/Sidebar/Battle.pressed.connect(func(): _show_page("Battle"))
    $MainHBox/Sidebar/Inventory.pressed.connect(func(): _show_page("Inventory"))
    $MainHBox/Sidebar/Deleted.pressed.connect(func(): _show_page("Deleted"))

    # bottom buttons
    $BottomBar/Logout.pressed.connect(self, "_on_logout")
    $BottomBar/Settings.pressed.connect(self, "_on_settings")

    _load_player_info()
    _load_heroes()

func _show_page(name: String) -> void:
    # a simple mapper - pages should be children of ContentStack with matching names
    for child in content_stack.get_children():
        child.visible = (child.name == name)

func _load_player_info():
    # placeholder backend call
    nickname_label.text = "Player123"
    currency_label.text = "Currency: 1000"

func _load_heroes():
    # populate heroes from server (placeholder)
    heroes = [
        {"id":1, "name":"Alpha","level":5, "stats": {"strength":10,"speed":5,"agility":6,"endurance":7,"health":50,"defense":4,"luck":2,"training":"none","field_of_view":10}},
        {"id":2, "name":"Beta","level":3, "stats": {"strength":8,"speed":7,"agility":5,"endurance":6,"health":40,"defense":3,"luck":3,"training":"none","field_of_view":8}},
    ]
    _refresh_hero_selection()

func _refresh_hero_selection():
    # assume each page may have a hero selection area; broadcast to them
    for page in content_stack.get_children():
        if page.has_method("set_hero_list"):
            page.set_hero_list(heroes)

func select_hero(hero_id):
    for h in heroes:
        if h.id == hero_id:
            selected_hero = h
            stats_panel.set_stats(h.stats)
            # notify pages
            for page in content_stack.get_children():
                if page.has_method("on_hero_selected"):
                    page.on_hero_selected(h)
            break

func _on_logout():
    print("logout placeholder")

func _on_settings():
    print("settings placeholder")

# placeholder API calls
func fetch_heroes():
    # GET /heroes
    pass

func fetch_hero_stats(hero_id):
    # GET /heroes/{id}
    pass

# ... rest of backend stubs to be implemented per window
