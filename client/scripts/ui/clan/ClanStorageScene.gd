extends Control
## ClanStorageScene.gd
## Clan shared storage UI with deposit / withdraw and transaction log.

signal back_pressed()

@onready var items_list:     VBoxContainer = $ScrollContainer/ItemsList
@onready var log_list:       VBoxContainer = $LogScroll/LogList
@onready var deposit_btn:    Button        = $Actions/DepositButton
@onready var withdraw_btn:   Button        = $Actions/WithdrawButton
@onready var back_button:    Button        = $BackButton
@onready var item_type_edit: LineEdit      = $Actions/ItemTypeEdit
@onready var item_id_edit:   LineEdit      = $Actions/ItemIdEdit
@onready var qty_edit:       LineEdit      = $Actions/QtyEdit
@onready var note_edit:      LineEdit      = $Actions/NoteEdit
@onready var status_lbl:     Label         = $StatusLabel

var clan_id: int = 0

func _ready() -> void:
	back_button.pressed.connect(func(): emit_signal("back_pressed"))
	deposit_btn.pressed.connect(_on_deposit)
	withdraw_btn.pressed.connect(_on_withdraw)
	status_lbl.text = ""
	if clan_id > 0:
		await refresh()

func load_for_clan(id: int) -> void:
	clan_id = id
	await refresh()

func refresh() -> void:
	await _load_items()
	await _load_log()

func _load_items() -> void:
	for c in items_list.get_children():
		c.queue_free()
	var items = await ApiClient.get_clan_storage(clan_id)
	if items.is_empty():
		var lbl := Label.new()
		lbl.text = "Storage is empty"
		items_list.add_child(lbl)
		return
	for item in items:
		var row  := HBoxContainer.new()
		var lbl  := Label.new()
		var avail := item.get("quantity", 0) - item.get("reserved_quantity", 0)
		lbl.text = "[%s id=%d]  qty: %d  reserved: %d  available: %d" % [
			item.get("item_type", "?"),
			item.get("item_id", 0),
			item.get("quantity", 0),
			item.get("reserved_quantity", 0),
			avail,
		]
		row.add_child(lbl)
		items_list.add_child(row)

func _load_log() -> void:
	for c in log_list.get_children():
		c.queue_free()
	var txs = await ApiClient.get_clan_storage_logs(clan_id, 30)
	for tx in txs:
		var lbl := Label.new()
		lbl.text = "[%s] %s id=%d qty=%d — %s" % [
			tx.get("action_type", "?"),
			tx.get("item_type", "?"),
			tx.get("item_id", 0),
			tx.get("quantity", 0),
			tx.get("note", ""),
		]
		lbl.add_theme_font_size_override("font_size", 11)
		log_list.add_child(lbl)

func _on_deposit() -> void:
	var item_type := item_type_edit.text.strip_edges()
	var item_id   := int(item_id_edit.text.strip_edges())
	var qty       := int(qty_edit.text.strip_edges())
	if item_type == "" or item_id <= 0 or qty <= 0:
		_set_status("Fill all fields correctly")
		return
	deposit_btn.disabled = true
	var res = await ApiClient.deposit_to_clan_storage(
		clan_id, item_type, item_id, qty, note_edit.text.strip_edges())
	deposit_btn.disabled = false
	if res is Dictionary and res.get("ok"):
		_set_status("Deposited %d units" % qty)
		await refresh()
	else:
		_set_status("Deposit failed: " + str(res.get("detail", "error")))

func _on_withdraw() -> void:
	var item_type := item_type_edit.text.strip_edges()
	var item_id   := int(item_id_edit.text.strip_edges())
	var qty       := int(qty_edit.text.strip_edges())
	if item_type == "" or item_id <= 0 or qty <= 0:
		_set_status("Fill all fields correctly")
		return
	withdraw_btn.disabled = true
	var res = await ApiClient.withdraw_from_clan_storage(
		clan_id, item_type, item_id, qty, note_edit.text.strip_edges())
	withdraw_btn.disabled = false
	if res is Dictionary and res.get("ok"):
		_set_status("Withdrew %d units" % qty)
		await refresh()
	else:
		_set_status("Withdraw failed: " + str(res.get("detail", "error")))

func _set_status(msg: String) -> void:
	status_lbl.text = msg
