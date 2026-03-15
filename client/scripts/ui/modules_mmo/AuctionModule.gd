extends Control

## AuctionModule — lot browser with filters, bid/buy controls, detail panel.

@onready var refresh_button: Button = $Root/Header/RefreshButton
@onready var search_input: LineEdit = $Root/FiltersPanel/FiltersMargin/FiltersRow/SearchInput
@onready var rarity_filter: OptionButton = $Root/FiltersPanel/FiltersMargin/FiltersRow/RarityFilter
@onready var min_price_input: LineEdit = $Root/FiltersPanel/FiltersMargin/FiltersRow/MinPriceInput
@onready var apply_filter_button: Button = $Root/FiltersPanel/FiltersMargin/FiltersRow/ApplyFilterButton
@onready var lots_tree: Tree = $Root/Body/ListPanel/ListMargin/LotsTree
@onready var detail_name: Label = $Root/Body/DetailPanel/DetailMargin/DetailVBox/DetailName
@onready var detail_seller: Label = $Root/Body/DetailPanel/DetailMargin/DetailVBox/DetailSeller
@onready var detail_bid: Label = $Root/Body/DetailPanel/DetailMargin/DetailVBox/DetailBid
@onready var detail_description: RichTextLabel = $Root/Body/DetailPanel/DetailMargin/DetailVBox/DetailDescription
@onready var status_label: Label = $Root/StatusLabel

var _lots: Array = []
var _lots_by_id: Dictionary = {}
var _selected_lot_id: int = -1
var _loading_overlay: Node = null
var _empty_state: Node = null
var _bid_input: LineEdit = null
var _bid_button: Button = null
var _buy_button: Button = null

func _ready() -> void:
	refresh_button.pressed.connect(_load_lots)
	apply_filter_button.pressed.connect(_render_lots)
	search_input.text_submitted.connect(func(_v: String) -> void: _render_lots())
	min_price_input.text_submitted.connect(func(_v: String) -> void: _render_lots())
	lots_tree.item_selected.connect(_on_lot_selected)
	_setup_filters()
	_setup_tree()
	_create_overlays()
	_create_bid_controls()
	_load_lots()

func _create_overlays() -> void:
	_loading_overlay = LoadingOverlay.new()
	$Root/Body/ListPanel.add_child(_loading_overlay)
	_empty_state = EmptyState.new()
	_empty_state.visible = false
	$Root/Body/ListPanel/ListMargin.add_child(_empty_state)

func _create_bid_controls() -> void:
	var detail_vbox: VBoxContainer = $Root/Body/DetailPanel/DetailMargin/DetailVBox
	var sep := HSeparator.new()
	detail_vbox.add_child(sep)
	var action_row := HBoxContainer.new()
	action_row.name = "AuctionActions"
	_bid_input = LineEdit.new()
	_bid_input.placeholder_text = "Bid amount"
	_bid_input.custom_minimum_size = Vector2(100, 0)
	_bid_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_row.add_child(_bid_input)
	_bid_button = Button.new()
	_bid_button.text = "Place Bid"
	_bid_button.pressed.connect(_on_bid_pressed)
	action_row.add_child(_bid_button)
	_buy_button = Button.new()
	_buy_button.text = "Buy Now"
	_buy_button.pressed.connect(_on_buy_pressed)
	action_row.add_child(_buy_button)
	detail_vbox.add_child(action_row)

func _load_lots() -> void:
	status_label.text = "Loading..."
	_loading_overlay.show_loading()
	_empty_state.visible = false
	var response: Dictionary = await ApiClient.get_auction_lots({"page": 1, "page_size": 50})
	_loading_overlay.hide_loading()
	if not bool(response.get("ok", false)):
		status_label.text = "Failed to load lots"
		UIUtils.show_error("Failed to load auction lots")
		return
	_lots = ResponseParser.extract_array(response.get("data", {}))
	_lots_by_id.clear()
	for lot_variant in _lots:
		if not lot_variant is Dictionary:
			continue
		var lot := lot_variant as Dictionary
		_lots_by_id[int(lot.get("id", -1))] = lot
	_render_lots()
	status_label.text = "%d lots" % _lots.size()

func _setup_filters() -> void:
	rarity_filter.clear()
	for label in ["All", "Common", "Rare", "Epic", "Legendary"]:
		rarity_filter.add_item(label)

func _setup_tree() -> void:
	lots_tree.columns = 5
	lots_tree.set_column_title(0, "ID")
	lots_tree.set_column_title(1, "Item")
	lots_tree.set_column_title(2, "Seller")
	lots_tree.set_column_title(3, "Current Bid")
	lots_tree.set_column_title(4, "Time Left")
	lots_tree.set_column_titles_visible(true)

func _render_lots() -> void:
	lots_tree.clear()
	var root: TreeItem = lots_tree.create_item()
	var search_term: String = search_input.text.strip_edges().to_lower()
	var rarity: String = rarity_filter.get_item_text(rarity_filter.selected).to_lower()
	var min_bid: float = float(min_price_input.text) if min_price_input.text.strip_edges().is_valid_float() else 0.0
	var visible_count: int = 0
	for lot_variant in _lots:
		if not lot_variant is Dictionary:
			continue
		var lot := lot_variant as Dictionary
		if not _passes_filters(lot, search_term, rarity, min_bid):
			continue
		var item := lots_tree.create_item(root)
		item.set_text(0, str(lot.get("id", "-")))
		item.set_text(1, str(lot.get("item_name", lot.get("title", "Lot"))))
		item.set_text(2, str(lot.get("seller_name", lot.get("seller", "-"))))
		item.set_text(3, DateTimeUtils.format_price(lot.get("current_bid", lot.get("start_price", 0))))
		# Time remaining
		var end_time: String = str(lot.get("end_time", lot.get("expires_at", "")))
		if end_time.is_empty():
			item.set_text(4, "-")
		else:
			item.set_text(4, end_time.substr(0, 16))
		visible_count += 1
	if visible_count == 0:
		_empty_state.visible = true
		if _empty_state.has_method("set_content"):
			_empty_state.set_content("No Lots Found", "Try adjusting filters or check back later.")
	else:
		_empty_state.visible = false

func _passes_filters(lot: Dictionary, search_term: String, rarity: String, min_bid: float) -> bool:
	var title: String = str(lot.get("item_name", lot.get("title", ""))).to_lower()
	if not search_term.is_empty() and not title.contains(search_term):
		return false
	var lot_rarity: String = str(lot.get("rarity", "common")).to_lower()
	if rarity != "all" and lot_rarity != rarity:
		return false
	var bid_value: float = float(lot.get("current_bid", lot.get("start_price", 0.0)))
	if bid_value < min_bid:
		return false
	return true

func _on_lot_selected() -> void:
	var selected := lots_tree.get_selected()
	if selected == null:
		return
	var lot_id: int = int(selected.get_text(0))
	if not _lots_by_id.has(lot_id):
		return
	_selected_lot_id = lot_id
	var lot := _lots_by_id[lot_id] as Dictionary
	detail_name.text = str(lot.get("item_name", lot.get("title", "-")))
	detail_seller.text = "Seller: %s" % str(lot.get("seller_name", lot.get("seller", "-")))
	detail_bid.text = "Current Bid: %s" % DateTimeUtils.format_price(lot.get("current_bid", lot.get("start_price", 0)))
	detail_description.text = "[b]Rarity:[/b] %s\n[b]Lot ID:[/b] %d\n\n%s" % [
		str(lot.get("rarity", "common")).capitalize(),
		lot_id,
		str(lot.get("description", "No description")),
	]

func _on_bid_pressed() -> void:
	if _selected_lot_id < 0:
		UIUtils.show_warning("Select a lot first")
		return
	var bid_text: String = _bid_input.text.strip_edges()
	if not bid_text.is_valid_float() or float(bid_text) <= 0:
		UIUtils.show_warning("Enter a valid bid amount")
		return
	var amount: float = float(bid_text)
	status_label.text = "Placing bid..."
	var response: Dictionary = await ApiClient.place_bid(_selected_lot_id, amount)
	if bool(response.get("ok", false)):
		UIUtils.show_success("Bid placed: %s" % DateTimeUtils.format_price(amount))
		_bid_input.text = ""
		_load_lots()
	else:
		var msg: String = str(response.get("message", response.get("error", "Bid failed")))
		UIUtils.show_error(msg)
		status_label.text = msg

func _on_buy_pressed() -> void:
	if _selected_lot_id < 0:
		UIUtils.show_warning("Select a lot first")
		return
	status_label.text = "Buying..."
	var response: Dictionary = await ApiClient.buy_lot(_selected_lot_id)
	if bool(response.get("ok", false)):
		UIUtils.show_success("Purchase successful!")
		_load_lots()
	else:
		var msg: String = str(response.get("message", response.get("error", "Purchase failed")))
		UIUtils.show_error(msg)
		status_label.text = msg

