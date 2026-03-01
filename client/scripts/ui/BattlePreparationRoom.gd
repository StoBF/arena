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
    TopBar.add_to(self, true, true)
    print("[BattleRoom] _ready() START")
    submit_btn.pressed.connect(Callable(self, "_on_submit_pressed"))
    bet_btn.pressed.connect(Callable(self, "_on_bet_pressed"))
    queue_timer.timeout.connect(Callable(self, "_poll_queue"))
    AppState.battle_queue_updated.connect(Callable(self, "_on_appstate_queue_updated"))
    AppState.battle_queue_error.connect(Callable(self, "_on_appstate_queue_error"))
    AppState.battle_submit_updated.connect(Callable(self, "_on_appstate_submit_updated"))
    AppState.battle_bet_updated.connect(Callable(self, "_on_appstate_bet_updated"))
    queue_timer.start()
    _load_heroes()

# ---------- UI population ----------
func _load_heroes():
    print("[BattleRoom] Loading heroes from server")
    var req = Network.request("/heroes/", HTTPClient.METHOD_GET)
    req.request_completed.connect(func(result, code, _hdrs, body):
        if result == HTTPRequest.RESULT_SUCCESS and code == 200:
            var json = JSON.new()
            var err = json.parse(body.get_string_from_utf8())
            if err == OK:
                var parsed = json.data
                if typeof(parsed) == TYPE_DICTIONARY and parsed.has("result"):
                    heroes = parsed["result"]
                elif typeof(parsed) == TYPE_ARRAY:
                    heroes = parsed
                else:
                    heroes = []
                hero_list.clear()
                for h in heroes:
                    hero_list.add_item(h.get("name", "?"), h.get("id", 0))
                print("[BattleRoom] Loaded %d heroes" % heroes.size())
                return
        print("[BattleRoom] Failed to load heroes")
    )

func _on_submit_pressed():
    var hid = hero_list.get_selected_id()
    current_hero = _find_hero_by_id(hid)
    if not current_hero:
        return
    submit_hero_to_queue(hid)
    emit_signal("hero_submitted", hid)
    _update_your_stats()

func _update_your_stats():
    if current_hero:
        your_stats.text = "Atk: %d\nDef: %d\nHP: %d" % [current_hero.attack, current_hero.defense, current_hero.health]

func _update_opponent_stats():
    var queued_heroes = _extract_queued_heroes()
    if queued_heroes.size() >= 2 and current_hero:
        var opp = queued_heroes[0].id == current_hero.id ? queued_heroes[1] : queued_heroes[0]
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

func _on_appstate_queue_updated(queue_data):
    _on_queue_received(queue_data)

func _on_appstate_queue_error(message: String):
    queue_display.text = message

func _on_appstate_submit_updated(success: bool, detail: String):
    queue_display.text = detail

func _on_appstate_bet_updated(success: bool, detail: String):
    queue_display.text = detail

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
    var req = Network.request("/battle/queue/submit", HTTPClient.METHOD_POST, {"hero_id": hero_id})
    req.request_completed.connect(func(result, code, _hdrs, _body):
        if result == HTTPRequest.RESULT_SUCCESS and code == 200:
            AppState.set_battle_submit_result(true, "Queue: waiting for opponent")
        else:
            AppState.set_battle_submit_result(false, "Queue: submit failed")
    )

func fetch_battle_queue():
    var req = Network.request("/battle/queue", HTTPClient.METHOD_GET)
    req.request_completed.connect(func(result, code, _hdrs, body):
        if result != HTTPRequest.RESULT_SUCCESS or code != 200:
            AppState.set_battle_queue_error("Queue: unavailable")
            return

        var json = JSON.new()
        var err = json.parse(body.get_string_from_utf8())
        if err != OK or typeof(json.data) != TYPE_ARRAY:
            AppState.set_battle_queue_error("Queue: invalid response")
            return

        AppState.update_battle_queue(json.data)
    )

func place_bet(hero_id, amount):
    var req = Network.request("/battle/bet", HTTPClient.METHOD_POST, {"hero_id": hero_id, "amount": amount})
    req.request_completed.connect(func(result, code, _hdrs, _body):
        if result == HTTPRequest.RESULT_SUCCESS and code == 200:
            AppState.set_battle_bet_result(true, "Bet accepted")
        else:
            AppState.set_battle_bet_result(false, "Bet failed")
    )

func fetch_hero_stats(hero_id):
    return _find_hero_by_id(hero_id)

func _find_hero_by_id(hero_id):
    for hero in heroes:
        if hero.id == hero_id:
            return hero
    return null

func _extract_queued_heroes() -> Array:
    var extracted: Array = []
    for entry in battle_queue:
        var queued_id = entry.get("hero_id", -1) if typeof(entry) == TYPE_DICTIONARY else -1
        var hero = _find_hero_by_id(queued_id)
        if hero:
            extracted.append(hero)
    return extracted

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

