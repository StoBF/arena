extends Window
class_name SellDialogPanel

# UI Elements
@onready var price_field = $PriceField
@onready var sell_button = $SellButton

# Properties
var item_id: int = -1

signal sell_requested(item_id: int, price: float)

func _ready():
    sell_button.pressed.connect(Callable(self, "_on_sell_button_pressed"))

func set_item(id: int):
    item_id = id

func _on_sell_button_pressed():
    var price = float(price_field.text)
    emit_signal("sell_requested", item_id, price)
    hide() 