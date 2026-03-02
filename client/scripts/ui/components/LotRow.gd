extends HBoxContainer
class_name LotRow

signal bid_requested(lot_data: Dictionary)
signal buy_now_requested(lot_data: Dictionary)
signal details_requested(lot_data: Dictionary)

const TEN_MINUTES := 600

@onready var icon_rect: TextureRect = $Icon
@onready var name_label: Label = $Name
@onready var stats_label: Label = $Stats
@onready var min_price_label: Label = $MinPrice
@onready var current_bid_label: Label = $CurrentBid
@onready var bid_step_label: Label = $BidStep
@onready var buy_now_label: Label = $BuyNow
@onready var time_left_box: VBoxContainer = $TimeLeft
@onready var time_left_label: Label = $TimeLeft/TimeLabel
@onready var time_left_progress: ProgressBar = $TimeLeft/TimeProgress
@onready var seller_label: Label = $Seller
@onready var bid_button: Button = $Actions/BidButton
@onready var buy_now_button: Button = $Actions/BuyNowButton
@onready var details_button: Button = $Actions/DetailsButton

var lot_data: Dictionary = {}
var _end_time_unix: int = 0
var _start_time_unix: int = 0
var _duration_seconds: int = 3600
var _last_current_bid: float = -1.0
var _is_closed: bool = false

func _ready() -> void:
	bid_button.pressed.connect(_on_bid_pressed)
	buy_now_button.pressed.connect(_on_buy_now_pressed)
	details_button.pressed.connect(_on_details_pressed)
	set_process(true)

func set_lot_data(data: Dictionary) -> void:
	lot_data = data.duplicate(true)
	_apply_data()

func refresh_bid(new_current_bid: float) -> void:
	if _is_closed:
		return
	if _last_current_bid >= 0.0 and new_current_bid > _last_current_bid:
		_flash_new_bid()
	_last_current_bid = new_current_bid
	current_bid_label.text = _money_text(new_current_bid)
	lot_data["current_price"] = new_current_bid
	lot_data["current_bid"] = new_current_bid

func apply_bid_update(event_data: Dictionary) -> void:
	var new_bid := float(event_data.get("current_bid", event_data.get("current_price", -1.0)))
	if new_bid < 0.0:
		return
	refresh_bid(new_bid)
	if event_data.has("bid_step"):
		var step := float(event_data.get("bid_step", 0.0))
		bid_step_label.text = _money_text(step)
		lot_data["bid_step"] = step

func mark_closed() -> void:
	_is_closed = true
	lot_data["is_closed"] = true
	bid_button.disabled = true
	buy_now_button.disabled = true
	bid_button.text = "Closed"
	buy_now_button.text = "Closed"
	modulate = Color(0.8, 0.8, 0.8, 1.0)

func _process(_delta: float) -> void:
	if _end_time_unix <= 0:
		return
	var now := Time.get_unix_time_from_system()
	var left := maxi(0, _end_time_unix - int(now))
	time_left_label.text = _format_seconds(left)
	time_left_progress.max_value = maxf(1.0, float(_duration_seconds))
	time_left_progress.value = float(left)
	if left < TEN_MINUTES:
		time_left_label.modulate = Color(1.0, 0.35, 0.35, 1.0)
		time_left_progress.modulate = Color(1.0, 0.35, 0.35, 1.0)
	else:
		time_left_label.modulate = Color(1, 1, 1, 1)
		time_left_progress.modulate = Color(1, 1, 1, 1)

func _apply_data() -> void:
	name_label.text = str(lot_data.get("name", lot_data.get("title", "Unknown")))
	stats_label.text = _build_stats_text(lot_data)
	min_price_label.text = _money_text(float(lot_data.get("start_price", lot_data.get("min_price", 0.0))))
	var current_bid := float(lot_data.get("current_price", lot_data.get("current_bid", 0.0)))
	_last_current_bid = current_bid
	current_bid_label.text = _money_text(current_bid)
	bid_step_label.text = _money_text(float(lot_data.get("bid_step", 0.0)))
	buy_now_label.text = _money_text(float(lot_data.get("buy_now", lot_data.get("buy_now_price", 0.0))))
	seller_label.text = str(lot_data.get("seller", lot_data.get("seller_name", "-")))

	var icon_path := str(lot_data.get("icon_path", "")).strip_edges()
	if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
		icon_rect.texture = load(icon_path)
	else:
		icon_rect.texture = null

	_end_time_unix = _resolve_end_time(lot_data)
	_start_time_unix = _resolve_start_time(lot_data)
	_duration_seconds = maxi(1, _end_time_unix - _start_time_unix)
	if _end_time_unix <= 0:
		time_left_label.text = "--:--:--"
		time_left_progress.value = 0.0

	if bool(lot_data.get("is_closed", false)):
		mark_closed()

func _resolve_end_time(data: Dictionary) -> int:
	if data.has("end_time_unix"):
		return int(data.get("end_time_unix", 0))
	if data.has("end_ts"):
		return int(data.get("end_ts", 0))
	if data.has("time_left"):
		return int(Time.get_unix_time_from_system()) + int(data.get("time_left", 0))
	return 0

func _resolve_start_time(data: Dictionary) -> int:
	if data.has("start_time_unix"):
		return int(data.get("start_time_unix", 0))
	if data.has("created_at_unix"):
		return int(data.get("created_at_unix", 0))
	if _end_time_unix > 0 and data.has("duration"):
		return _end_time_unix - int(data.get("duration", 3600))
	return int(Time.get_unix_time_from_system())

func _on_bid_pressed() -> void:
	bid_requested.emit(lot_data.duplicate(true))

func _on_buy_now_pressed() -> void:
	buy_now_requested.emit(lot_data.duplicate(true))

func _on_details_pressed() -> void:
	details_requested.emit(lot_data.duplicate(true))

func _flash_new_bid() -> void:
	var tween := create_tween()
	tween.tween_property(self, "modulate", Color(1.0, 1.0, 0.45, 1.0), 0.14)
	tween.tween_property(self, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.18)

func _format_seconds(seconds: int) -> String:
	var s := maxi(0, seconds)
	var h := s / 3600
	var m := (s % 3600) / 60
	var sec := s % 60
	return "%02d:%02d:%02d" % [h, m, sec]

func _build_stats_text(data: Dictionary) -> String:
	if bool(data.get("is_hero", false)):
		return "Lvl %d | STR %d AGI %d HP %d" % [
			int(data.get("level", 1)),
			int(data.get("strength", 0)),
			int(data.get("agility", 0)),
			int(data.get("health", 0))
		]
	var rarity := str(data.get("rarity", "Common"))
	var power := int(data.get("power", 0))
	return "%s | Power %d" % [rarity, power]

func _money_text(value: float) -> String:
	return "%.2f" % value
