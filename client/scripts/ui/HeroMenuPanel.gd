extends Control
class_name HeroMenuPanel

signal item_equipped(slot_name, item_id)
signal item_unequipped(slot_name, item_id)

@onready var hero_icon = $HeroIcon
@onready var equipment_grid = $EquipmentGrid
@onready var items_grid = $ItemsGrid
@onready var tooltip = $Tooltip

var slot_nodes := {}
var hero = {}
var available_items := []

func _ready():
    # define slots
    slot_nodes = {
        "Helmet": $EquipmentGrid/Slot_Helmet,
        "Armor": $EquipmentGrid/Slot_Armor,
        "Gloves": $EquipmentGrid/Slot_Gloves,
        "Boots": $EquipmentGrid/Slot_Boots,
        "Quantum Module": $EquipmentGrid/Slot_QuantumModule,
    }

    _setup_drag_and_drop()
    hero_icon.pressed.connect(Callable(self, "_on_hero_icon_pressed"))

    _load_hero()
    _load_items()

func _setup_drag_and_drop():
    for name in slot_nodes.keys():
        var slot = slot_nodes[name]
        slot.slot_name = name
        slot.gui_input.connect(Callable(self, "_on_slot_gui_input")).bind(name)
        slot.drop_data.connect(Callable(self, "_on_slot_drop")).bind(name)
    items_grid.drop_data.connect(Callable(self, "_on_items_drop"))

func _load_hero():
    # placeholder; should request hero data from server
    hero = {"id": -1, "level": 1, "quantum_crafting_skill": 0}
    # set icon if available
    hero_icon.texture = preload("res://assets/icons/hero_placeholder.png")

func _load_items():
    # placeholder items list
    available_items = [
        {"id": 101, "name": "Photon Helmet", "slot": "Helmet", "required_level": 2, "required_skill": 1,
         "stability": 5, "energy": 10, "durability": 3, "mutation_chance": 0.1,
         "icon_path": "res://assets/icons/helmet.png"},
        {"id": 102, "name": "Quantum Boots", "slot": "Boots", "required_level": 1, "required_skill": 0,
         "stability": 2, "energy": 0, "durability": 5, "mutation_chance": 0.0,
         "icon_path": "res://assets/icons/boots.png"},
    ]
    _populate_items()

func _populate_items():
    items_grid.clear()
    for item in available_items:
        var icon = preload("res://scenes/InventoryItemIcon.tscn").instantiate()
        icon.item_data = item
        # display texture or placeholder for 3D model
        if item.has("icon_path"):
            icon.texture = load(item.icon_path)
        else:
            icon.texture = preload("res://assets/icons/item_placeholder.png")
        # requirements check
        if not _meets_requirements(item):
            icon.modulate = Color(1,1,1,0.4)
            icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
        else:
            icon.mouse_filter = Control.MOUSE_FILTER_PASS
            icon.gui_input.connect(Callable(self, "_on_item_gui_input")).bind(item)
        icon.connect("mouse_entered", Callable(self, "_on_item_hover")).bind(item)
        icon.connect("mouse_exited", Callable(self, "_on_tooltip_hide"))
        items_grid.add_child(icon)

func _meets_requirements(item):
    if hero.level < item.get("required_level", 0):
        return false
    if hero.quantum_crafting_skill < item.get("required_skill", 0):
        return false
    return true

func _on_item_gui_input(event, item):
    if event is InputEventMouseButton and event.pressed and event.button_index == BUTTON_LEFT:
        if not _meets_requirements(item):
            return
        var drag = {"item": item}
        var preview = TextureRect.new()
        preview.texture = load(item.icon_path) if item.has("icon_path") else null
        items_grid.start_drag(drag, preview)

func _on_slot_gui_input(event, slot_name):
    if event is InputEventMouseButton and event.pressed and event.button_index == BUTTON_LEFT:
        var slot = slot_nodes[slot_name]
        if slot.has_meta("equipped_item"):
            var data = {"item": slot.get_meta("equipped_item"), "origin_slot": slot_name}
            var preview = TextureRect.new()
            preview.texture = slot.texture
            slot.start_drag(data, preview)

func _on_slot_drop(position, data, slot_name):
    if data.has("item"):
        var item = data.item
        # slot mismatch check
        if item.slot != slot_name:
            return
        # skill requirement check
        if hero.quantum_crafting_skill < item.get("required_skill", 0):
            UIUtils.show_error(Localization.t("skill_too_low"))
            return
        var target_slot = slot_nodes[slot_name]
        # if there's already something equipped, swap it back
        if target_slot.has_meta("equipped_item") and target_slot.get_meta("equipped_item") != null:
            var old = target_slot.get_meta("equipped_item")
            _unequip(slot_name)
            # after unequipping we add old item back into inventory
            available_items.append(old)
            _populate_items()
        # perform equip
        _equip(item, slot_name)
        # remove the item from available list if it came from inventory
        if not data.has("origin_slot"):
            for i in range(available_items.size()):
                if available_items[i].id == item.id:
                    available_items.remove_at(i)
                    break
            _populate_items()
        # if the drag originated from another slot (swap scenario), notify
        if data.has("origin_slot"):
            emit_signal("item_unequipped", data.origin_slot, item.id)

func _on_items_drop(position, data):
    if data.has("origin_slot") and data.has("item"):
        var slotname = data.origin_slot
        var old = slot_nodes[slotname].get_meta("equipped_item")
        _unequip(slotname)
        # returned item should be added back to inventory
        if old:
            available_items.append(old)
            _populate_items()

func _equip(item, slot_name):
    var slot = slot_nodes[slot_name]
    slot.texture = load(item.icon_path) if item.has("icon_path") else null
    slot.set_meta("equipped_item", item)
    emit_signal("item_equipped", slot_name, item.id)

func _unequip(slot_name):
    var slot = slot_nodes[slot_name]
    var item = slot.get_meta("equipped_item")
    slot.texture = null
    slot.set_meta("equipped_item", null)
    emit_signal("item_unequipped", slot_name, item.id)

func _on_item_hover(item):
    var text = "%s\nStability: %d\nEnergy: %d\nDurability: %d\nMutation: %.2f" % [
        item.name, item.stability, item.energy, item.durability, item.mutation_chance]
    tooltip.get_node("Label").text = text
    tooltip.popup()

func _on_tooltip_hide():
    tooltip.hide()

func _on_hero_icon_pressed():
    # when placed in other UI, pressing icon should open this panel
    popup_centered()
