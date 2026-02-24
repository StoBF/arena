extends Control
class_name BattlePreparationRoom

signal hero_submitted(hero_id)
signal bet_placed(hero_id, amount)
signal queue_updated(queue)

@onready var hero_list = $VBox/HeroSelectHBox/HeroList
@onready var submit_btn = $VBox/SubmitHBox/SubmitButton
@onready var queue_display = $VBox/SubmitHBox/QueueDisplay
@onready var your_stats = $VBox/StatsContainer/YourStats/Stats
@onready var opp_stats = $VBox/StatsContainer/OpponentStats/Stats
@onready var prediction = $VBox/Prediction
@onready var bet_amount = $VBox/BetContainer/Amount
@onready var bet_btn = $VBox/BetContainer/PlaceBet
@onready var queue_timer = $QueueTimer

var heroes := []        # list of hero dicts from inventory
var current_hero = null
var battle_queue := []  # list of hero dicts currently queued

func _ready():
    submit_btn.pressed.connect(Callable(self, "_on_submit_pressed"))
    bet_btn.pressed.connect(Callable(self, "_on_bet_pressed"))
    queue_timer.timeout.connect(Callable(self, "_poll_queue"))
    queue_timer.start()
    _load_heroes()

# ---------- UI population ----------
func _load_heroes():
    # placeholder: fetch from backend
    heroes = [
        {"id":1, "name":"Alpha","attack":10,"defense":8,"health":50},
        {"id":2, "name":"Beta","attack":7,"defense":12,"health":45},
    ]
    hero_list.clear()
    for h in heroes:
        hero_list.add_item(h.name, h.id)

func _on_submit_pressed():
    var hid = hero_list.get_selected_id()
    current_hero = heroes.find(lambda x: x.id == hid)
    if not current_hero:
        return
    submit_hero_to_queue(hid)
    emit_signal("hero_submitted", hid)
    _update_your_stats()

func _update_your_stats():
    if current_hero:
        your_stats.text = "Atk: %d\nDef: %d\nHP: %d" % [current_hero.attack, current_hero.defense, current_hero.health]

func _update_opponent_stats():
    if battle_queue.size() >= 2 and current_hero:
        var opp = battle_queue[0].id == current_hero.id ? battle_queue[1] : battle_queue[0]
        opp_stats.text = "Atk: %d\nDef: %d\nHP: %d" % [opp.attack, opp.defense, opp.health]
        _predict_winner(current_hero, opp)
    else:
        opp_stats.text = ""
        prediction.text = "Prediction: N/A"

func _predict_winner(h1, h2):
    var score1 = h1.attack + h1.defense + h1.health
    var score2 = h2.attack + h2.defense + h2.health
    var chance = score1/(score1+score2) * 100
    prediction.text = "Prediction: %s likely (%.1f%%)" % [h1.name, chance]

# ---------- polling ----------
func _poll_queue():
    fetch_battle_queue()

func _on_queue_received(qarr):
    battle_queue = qarr
    queue_display.text = "Queue: %d heroes" % battle_queue.size()
    emit_signal("queue_updated", battle_queue)
    _update_opponent_stats()

# ---------- betting ----------
func _on_bet_pressed():
    if not current_hero:
        return
    var amt = bet_amount.text.to_int()
    if amt <= 0:
        return
    place_bet(current_hero.id, amt)
    emit_signal("bet_placed", current_hero.id, amt)

# ---------- placeholder backend calls ----------
func submit_hero_to_queue(hero_id):
    # TODO: replace with Network.request to /battle/queue/submit
    print("[API] submit hero", hero_id)

func fetch_battle_queue():
    # TODO: GET /battle/queue
    # simulate two entries after submit
    if current_hero and battle_queue.size() < 2:
        battle_queue.append(current_hero)
    _on_queue_received(battle_queue)

func place_bet(hero_id, amount):
    # TODO: POST /battle/bet
    print("[API] bet", hero_id, amount)

func fetch_hero_stats(hero_id):
    # TODO: GET /battle/hero/%d
    return heroes.find(lambda x: x.id == hero_id)

# ---------- helpers for reuse ----------
func set_hero_list(list_of_heroes):
    heroes = list_of_heroes
    hero_list.clear()
    for h in heroes:
        hero_list.add_item(h.name, h.id)

func start_polling(interval=2.0):
    queue_timer.wait_time = interval
    queue_timer.start()

func stop_polling():
    queue_timer.stop()

