extends Control
class_name InventoryPanel

# UI Elements
@onready var inventory_scroll = $InventoryScroll
@onready var items_container = $InventoryScroll/ItemsContainer
@onready var sell_dialog = $SellDialog

func _ready():
    # Back to dashboard button
    var back_btn = BackToDashboardButton.new()
    add_child(back_btn)
    move_child(back_btn, 0)
    # Connect signals
    sell_dialog.sell_requested.connect(Callable(self, "_on_sell_requested"))
    Localization.locale_changed.connect(Callable(self, "_update_locale"))
    
    # Load initial data
    _load_inventory()
    _update_locale()

func _load_inventory():
    var req = Network.get_inventory(AppState.current_hero_id)
    req.request_completed.connect(Callable(self, "_on_inventory_response"))

func _on_inventory_response(result: int, code: int, headers, body: PackedByteArray):
    if result == OK and code == 200:
        var parsed = JSON.parse_string(body.get_string_from_utf8())
        if parsed.error == OK:
            _populate_inventory(parsed.result)
            return
    UIUtils.show_error(Localization.t("load_inventory_failed"))

func _populate_inventory(items: Array):
    # Clear existing items
    for child in items_container.get_children():
        child.queue_free()
    
    # Add new items
    for item in items:
        var hbox = HBoxContainer.new()
        
        # Add item name
        var label = Label.new()
        label.text = item.get("name", "")
        hbox.add_child(label)
        
        # Add sell button
        var sell_btn = Button.new()
        sell_btn.pressed.connect(Callable(self, "_on_sell_button_pressed").bind(item.get("id")))
        sell_btn.text = Localization.t("sell")
        hbox.add_child(sell_btn)
        
        items_container.add_child(hbox)

func _on_sell_button_pressed(item_id: int):
    sell_dialog.set_item(item_id)
    sell_dialog.popup_centered()

func _on_sell_requested(item_id: int, price: float):
    var data = {
        "item_id": item_id,
        "price": price
    }
    
    var req = Network.request("/auctions", HTTPClient.METHOD_POST, data)
    req.request_completed.connect(Callable(self, "_on_sell_response"))

func _on_sell_response(result: int, code: int, headers, body: PackedByteArray):
    if code == 200:
        UIUtils.show_success(Localization.t("sell_success"))
        _load_inventory()
    else:
        UIUtils.show_error(Localization.t("sell_failed"))

func _update_locale():
    # Update any dynamic UI text that needs localization
    _load_inventory() 