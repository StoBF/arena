extends Control

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

func _ready() -> void:
	refresh_button.pressed.connect(_load_lots)
	apply_filter_button.pressed.connect(_render_lots)
	search_input.text_submitted.connect(func(_v: String) -> void: _render_lots())
	min_price_input.text_submitted.connect(func(_v: String) -> void: _render_lots())
	lots_tree.item_selected.connect(_on_lot_selected)
	_setup_filters()
	_setup_tree()
	_load_lots()

func bind_controllers(_player_data: Node, _inventory_controller: Node, _craft_controller: Node) -> void:
	return

func _load_lots() -> void:
	status_label.text = "Loading lots..."
	var response: Dictionary = await ApiClient.get_auction_lots({"page": 1, "page_size": 50})
	if bool(response.get("ok", false)) == false:
		status_label.text = "Failed to load lots"
		return
	_lots = _extract_lots(response.get("data", {}))
	_lots_by_id.clear()
	for lot_variant in _lots:
		if lot_variant is Dictionary == false:
			continue
		var lot := lot_variant as Dictionary
		_lots_by_id[int(lot.get("id", -1))] = lot
	_render_lots()
	status_label.text = "Loaded %d lots" % _lots.size()

func _setup_filters() -> void:
	rarity_filter.clear()
	rarity_filter.add_item("All", 0)
	rarity_filter.add_item("Common", 1)
	rarity_filter.add_item("Rare", 2)
	rarity_filter.add_item("Epic", 3)
	rarity_filter.add_item("Legendary", 4)

func _setup_tree() -> void:
	lots_tree.columns = 4
	lots_tree.set_column_title(0, "ID")
	lots_tree.set_column_title(1, "Item")
	lots_tree.set_column_title(2, "Seller")
	lots_tree.set_column_title(3, "Bid")
	lots_tree.set_column_titles_visible(true)

func _render_lots() -> void:
	lots_tree.clear()
	var root: TreeItem = lots_tree.create_item()
	var search_term: String = search_input.text.strip_edges().to_lower()
	var rarity: String = rarity_filter.get_item_text(rarity_filter.selected).to_lower()
	var min_bid: float = float(min_price_input.text) if min_price_input.text.strip_edges().is_valid_float() else 0.0
	for lot_variant in _lots:
		if lot_variant is Dictionary == false:
			continue
		var lot := lot_variant as Dictionary
		if _passes_filters(lot, search_term, rarity, min_bid) == false:
			continue
		var item := lots_tree.create_item(root)
		item.set_text(0, str(lot.get("id", "-")))
		item.set_text(1, str(lot.get("item_name", lot.get("title", "Lot"))))
		item.set_text(2, str(lot.get("seller_name", lot.get("seller", "-"))))
		item.set_text(3, str(lot.get("current_bid", lot.get("start_price", "-"))))

func _passes_filters(lot: Dictionary, search_term: String, rarity: String, min_bid: float) -> bool:
	var title: String = str(lot.get("item_name", lot.get("title", ""))).to_lower()
	if search_term.is_empty() == false and title.contains(search_term) == false:
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
	if _lots_by_id.has(lot_id) == false:
		return
	var lot := _lots_by_id[lot_id] as Dictionary
	detail_name.text = "Name: %s" % str(lot.get("item_name", lot.get("title", "-")))
	detail_seller.text = "Seller: %s" % str(lot.get("seller_name", lot.get("seller", "-")))
	detail_bid.text = "Current Bid: %s" % str(lot.get("current_bid", lot.get("start_price", "-")))
	detail_description.text = "[b]Rarity:[/b] %s\n[b]Lot ID:[/b] %d\n\n%s" % [
		str(lot.get("rarity", "common")).capitalize(),
		lot_id,
		str(lot.get("description", "No description")),
	]

func _extract_lots(parsed: Variant) -> Array:
	if parsed is Array:
		return (parsed as Array).duplicate(true)
	if parsed is Dictionary:
		var data := parsed as Dictionary
		if data.has("result") and data["result"] is Array:
			return (data["result"] as Array).duplicate(true)
		if data.has("items") and data["items"] is Array:
			return (data["items"] as Array).duplicate(true)
	return []

