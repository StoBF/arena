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
var heroes: Array = []      # {id, name, attack, defense, health}
var current_hero = null
var queue: Array = []       # two entries of hero dicts

func _ready():
	# TopBar replaces the old BackToDashboardButton
	TopBar.add_to(self, true, true)
	print("[BattlePrep] _ready() START")
	submit_btn.pressed.connect(Callable(self, "_on_submit_pressed"))
	bet_btn.pressed.connect(Callable(self, "_on_bet_pressed"))
	queue_timer.timeout.connect(Callable(self, "_poll_queue"))
	AppState.battle_queue_updated.connect(Callable(self, "_on_appstate_queue_updated"))
	AppState.battle_queue_error.connect(Callable(self, "_on_appstate_queue_error"))
	AppState.battle_submit_updated.connect(Callable(self, "_on_appstate_submit_updated"))
	AppState.battle_bet_updated.connect(Callable(self, "_on_appstate_bet_updated"))
	queue_timer.start()
	_load_heroes()

func _load_heroes():
	print("[BattlePrep] Loading heroes from server")
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
				print("[BattlePrep] Loaded %d heroes" % heroes.size())
				return
		print("[BattlePrep] Failed to load heroes: code=%d" % code)
		UIUtils.show_error("Failed to load heroes")
	)

func _on_submit_pressed():
	var id = hero_list.get_selected_id()
	current_hero = null
	for h in heroes:
		if h.get("id", -1) == id:
			current_hero = h
			break
	if current_hero == null:
		return
	submit_hero_to_queue(id)
	emit_signal("hero_submitted", id)
	_update_your_stats()

func _update_your_stats():
	if not current_hero:
		your_stats_label.text = ""
		return
	your_stats_label.text = "Attack: %d\nDefense: %d\nHealth: %d" % [
		int(current_hero.get("attack", current_hero.get("strength", 0))),
		int(current_hero.get("defense", 0)),
		int(current_hero.get("health", 0))]

func _update_opponent_stats():
	if queue.size() < 2:
		opp_stats_label.text = ""
		prediction_label.text = ""
		return
	var queued_heroes = _extract_queued_heroes()
	if queued_heroes.size() < 2 or not current_hero:
		opp_stats_label.text = ""
		prediction_label.text = ""
		return

	var opp = queued_heroes[1] if queued_heroes[0].get("id", -1) == current_hero.get("id", -1) else queued_heroes[0]
	opp_stats_label.text = "Attack: %d\nDefense: %d\nHealth: %d" % [
		int(opp.get("attack", opp.get("strength", 0))),
		int(opp.get("defense", 0)),
		int(opp.get("health", 0))]
	_compute_prediction(current_hero, opp)

func _compute_prediction(h1, h2):
	# simple sum-based prediction
	var score1 = int(h1.get("attack", h1.get("strength", 0))) + int(h1.get("defense", 0)) + int(h1.get("health", 0))
	var score2 = int(h2.get("attack", h2.get("strength", 0))) + int(h2.get("defense", 0)) + int(h2.get("health", 0))
	if score1 + score2 <= 0:
		prediction_label.text = "Win chance: N/A"
		return
	var p1 = score1 / float(score1 + score2) * 100
	prediction_label.text = "Win chance: %.1f%%" % p1

func _poll_queue():
	fetch_battle_queue()

func _on_bet_pressed():
	if not current_hero:
		return
	var amt = bet_amount.text.to_int()
	if amt <= 0:
		return
	place_bet(int(current_hero.get("id", -1)), amt)
	emit_signal("bet_placed", amt)

func _on_appstate_queue_updated(queue_data):
	queue = queue_data
	if queue.size() >= 2:
		queue_status.text = "Ready to battle"
	else:
		queue_status.text = "Waiting for opponent..."
	_update_opponent_stats()

func _on_appstate_queue_error(message: String):
	queue_status.text = message

func _on_appstate_submit_updated(success: bool, detail: String):
	queue_status.text = detail

func _on_appstate_bet_updated(success: bool, detail: String):
	if success:
		UIUtils.show_success(detail)
	else:
		UIUtils.show_error(detail)

func submit_hero_to_queue(hero_id):
	var req = Network.request("/battle/queue/submit", HTTPClient.METHOD_POST, {"hero_id": hero_id})
	req.request_completed.connect(func(result, code, _hdrs, _body):
		if result == HTTPRequest.RESULT_SUCCESS and code == 200:
			AppState.set_battle_submit_result(true, "Waiting for opponent...")
		else:
			AppState.set_battle_submit_result(false, "Submission failed")
	)

func fetch_battle_queue():
	var req = Network.request("/battle/queue", HTTPClient.METHOD_GET)
	req.request_completed.connect(func(result, code, _hdrs, body):
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			AppState.set_battle_queue_error("Queue error")
			return

		var json = JSON.new()
		var err = json.parse(body.get_string_from_utf8())
		if err != OK or typeof(json.data) != TYPE_ARRAY:
			AppState.set_battle_queue_error("Queue response error")
			return

		AppState.update_battle_queue(json.data)
	)

func place_bet(hero_id, amount):
	var req = Network.request("/battle/bet", HTTPClient.METHOD_POST, {"hero_id": hero_id, "amount": amount})
	req.request_completed.connect(func(result, code, _hdrs, _body):
		if result == HTTPRequest.RESULT_SUCCESS and code == 200:
			AppState.set_battle_bet_result(true, "Bet placed")
		else:
			AppState.set_battle_bet_result(false, "Bet failed")
	)

func _find_hero_by_id(hero_id):
	for hero in heroes:
		if hero.get("id", -1) == hero_id:
			return hero
	return null

func _extract_queued_heroes() -> Array:
	var extracted: Array = []
	for entry in queue:
		var queued_id = entry.get("hero_id", -1) if typeof(entry) == TYPE_DICTIONARY else -1
		var hero = _find_hero_by_id(queued_id)
		if hero:
			extracted.append(hero)
	return extracted

# modular hooks
func set_heroes(list):
	heroes = list
	hero_list.clear()
	for h in heroes:
		hero_list.add_item(h.get("name", "?"), h.get("id", 0))

func start_polling(interval=3.0):
	queue_timer.wait_time = interval
	queue_timer.start()

func stop_polling():
	queue_timer.stop()
