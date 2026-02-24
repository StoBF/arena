extends HBoxContainer
class_name InventoryItem

var item_data := {} # id, name, quantity, icon_path

func set_data(data: Dictionary) -> void:
    item_data = data
    $Icon.texture = preload(data.get("icon_path","res://assets/icons/item_placeholder.png"))
    $Name.text = data.get("name","")
    $Quantity.text = "x%d" % data.get("quantity",0)

func _ready():
    # could connect drag signals here
    pass
