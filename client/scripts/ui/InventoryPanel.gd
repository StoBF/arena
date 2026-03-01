extends Control
class_name InventoryPanel

# UI Elements
@onready var inventory_scroll = $InventoryScroll
@onready var items_container = $InventoryScroll/ItemsContainer
@onready var sell_dialog = $SellDialog

func _ready():
    # TopBar replaces old BackToDashboardButton
    TopBar.add_to(self, true, true)
    print("[Inventory] _ready() START")
    # Connect signals
    if sell_dialog and sell_dialog.has_signal("sell_requested"):
        sell_dialog.sell_requested.connect(Callable(self, "_on_sell_requested"))
    Localization.locale_changed.connect(Callable(self, "_update_locale"))

    # Load initial data
    _load_inventory()
    _update_locale()

func _load_inventory():
    if AppState.current_hero_id <= 0:
        print("[Inventory] No hero selected, skipping inventory load")
        UIUtils.show_error("Select a hero first")
        return
    print("[Inventory] Loading inventory for hero_id=%d" % AppState.current_hero_id)
    var req = Network.request("/heroes/%d/inventory" % AppState.current_hero_id, HTTPClient.METHOD_GET)
    req.request_completed.connect(Callable(self, "_on_inventory_response"))

func _on_inventory_response(result: int, code: int, headers, body: PackedByteArray):
    print("[Inventory] _on_inventory_response code=%d" % code)
    if result == HTTPRequest.RESULT_SUCCESS and code == 200:
        var json = JSON.new()
        var err = json.parse(body.get_string_from_utf8())
        if err == OK:
            var parsed = json.data
            var items_arr: Array = []
            if typeof(parsed) == TYPE_DICTIONARY and parsed.has("result"):
                items_arr = parsed["result"]
            elif typeof(parsed) == TYPE_ARRAY:
                items_arr = parsed
            _populate_inventory(items_arr)
            return
        print("[Inventory] JSON parse error: %d" % err)
    UIUtils.show_error(Localization.t("load_inventory_failed") if Localization.has_key("load_inventory_failed") else "Failed to load inventory")

func _populate_inventory(items: Array):
    if not items_container:
        print("[Inventory] WARN: items_container is NULL")
        return
    # Clear existing items
    for child in items_container.get_children():
        child.queue_free()

    # Add new items
    for item in items:
        var hbox = HBoxContainer.new()

        # Add item name
        var label = Label.new()
        label.text = item.get("name", "Unknown Item")
        hbox.add_child(label)

        # Add sell button
        var sell_btn = Button.new()
        sell_btn.pressed.connect(Callable(self, "_on_sell_button_pressed").bind(item.get("id", 0)))
        sell_btn.text = Localization.t("sell") if Localization.has_key("sell") else "Sell"
        hbox.add_child(sell_btn)

        items_container.add_child(hbox)
    print("[Inventory] Populated %d items" % items.size())

func _on_sell_button_pressed(item_id: int):
    if sell_dialog and sell_dialog.has_method("set_item"):
        sell_dialog.set_item(item_id)
        sell_dialog.popup_centered()
    else:
        print("[Inventory] WARN: sell_dialog missing or has no set_item method")

func _on_sell_requested(item_id: int, price: float):
    var data = {
        "item_id": item_id,
        "price": price
    }

    var req = Network.request("/auctions/", HTTPClient.METHOD_POST, data)
    req.request_completed.connect(Callable(self, "_on_sell_response"))

func _on_sell_response(result: int, code: int, headers, body: PackedByteArray):
    if result == HTTPRequest.RESULT_SUCCESS and code == 200:
        UIUtils.show_success(Localization.t("sell_success") if Localization.has_key("sell_success") else "Item listed!")
        _load_inventory()
    else:
        UIUtils.show_error(Localization.t("sell_failed") if Localization.has_key("sell_failed") else "Failed to sell item")

func _update_locale():
    pass  # Dynamic texts are set during _populate_inventory