extends Control
class_name BattlePrepPanel

signal hero_submitted(hero_id)
signal bet_placed(amount)

@onready var hero_list = $VBox/SelectHeroHBox/HeroList
@onready var submit_btn = $VBox/SubmitButton
@onready var queue_status = $VBox/QueueStatus
@onready var your_stats_label = $VBox/StatsHBox/YourStats/Stats
@onready var opp_stats_label = $VBox/StatsHBox/OpponentStats/Stats
@onready var prediction_label = $VBox/Prediction
@onready var bet_amount = $VBox/BetHBox/Amount
@onready var bet_btn = $VBox/BetHBox/BetButton
@onready var queue_timer = $QueueTimer

# local state
var heroes := []      # {id, name, attack, defense, health}
var current_hero = null
var queue := []       # two entries of hero dicts

func _ready():
    submit_btn.pressed.connect(Callable(self, "_on_submit_pressed"))
    bet_btn.pressed.connect(Callable(self, "_on_bet_pressed"))
    queue_timer.timeout.connect(Callable(self, "_poll_queue"))
    queue_timer.start()
    _load_heroes()

func _load_heroes():
    # placeholder: would call Network.request("/heroes", GET) and parse result
    # for now, populate with example data
    heroes = [
        {"id": 1, "name": "Alpha", "attack": 10, "defense": 8, "health": 50},
        {"id": 2, "name": "Beta", "attack": 7, "defense": 12, "health": 45},
    ]
    hero_list.clear()
    for h in heroes:
        hero_list.add_item(h.name, h.id)

func _on_submit_pressed():
    var id = hero_list.get_selected_id()
    current_hero = null
    for h in heroes:
        if h.id == id:
            current_hero = h
            break
    if current_hero == null:
        return
    # send to backend
    var req = Network.request("/battle/submit", NetworkManager.POST, {"hero_id": id})
    req.request_completed.connect(func(result, code, hdrs, body):
        if code == 200:
            queue_status.text = "Waiting for opponent..."
        else:
            queue_status.text = "Submission failed"
    )
    emit_signal("hero_submitted", id)
    _update_your_stats()

func _update_your_stats():
    if not current_hero:
        your_stats_label.text = ""
        return
    your_stats_label.text = "Attack: %d\nDefense: %d\nHealth: %d" % [
        current_hero.attack, current_hero.defense, current_hero.health]

func _update_opponent_stats():
    if queue.size() < 2:
        opp_stats_label.text = ""
        prediction_label.text = ""
        return
    var opp = queue[0].id == current_hero.id ? queue[1] : queue[0]
    opp_stats_label.text = "Attack: %d\nDefense: %d\nHealth: %d" % [
        opp.attack, opp.defense, opp.health]
    _compute_prediction(current_hero, opp)

func _compute_prediction(h1, h2):
    # simple sum-based prediction
    var score1 = h1.attack + h1.defense + h1.health
    var score2 = h2.attack + h2.defense + h2.health
    var p1 = score1 / float(score1 + score2) * 100
    prediction_label.text = "Win chance: %.1f%%" % p1

func _poll_queue():
    # fetch queue state from server
    var req = Network.request("/battle/queue", NetworkManager.GET)
    req.request_completed.connect(func(result, code, hdrs, body):
        if code == 200:
            var resp = JSON.parse_string(body.get_string_from_utf8())
            if resp.error == OK:
                queue = resp.result
                if queue.size() >= 2:
                    queue_status.text = "Ready to battle"
                    _update_opponent_stats()
                else:
                    queue_status.text = "Waiting for opponent..."
        else:
            queue_status.text = "Queue error"
    )

func _on_bet_pressed():
    var amt = bet_amount.text.to_int()
    if amt <= 0:
        return
    # send bet to backend
    var req = Network.request("/battle/bet", NetworkManager.POST, {"amount": amt})
    req.request_completed.connect(func(result, code, hdrs, body):
        if code == 200:
            UIUtils.show_success("Bet placed")
        else:
            UIUtils.show_error("Bet failed")
    )
    emit_signal("bet_placed", amt)

# modular hooks
func set_heroes(list):
    heroes = list
    hero_list.clear()
    for h in heroes:
        hero_list.add_item(h.name, h.id)

func start_polling(interval=3.0):
    queue_timer.wait_time = interval
    queue_timer.start()

func stop_polling():
    queue_timer.stop()
