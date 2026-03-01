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
    # TopBar
    TopBar.add_to(self, true, true)
    print("[HeroMenu] _ready() START")
    # define slots (with null safety)
    slot_nodes = {}
    if equipment_grid:
        for sn in ["Helmet", "Armor", "Gloves", "Boots", "Quantum Module"]:
            var node_name = "Slot_%s" % sn.replace(" ", "")
            var slot = equipment_grid.get_node_or_null(node_name)
            if slot:
                slot_nodes[sn] = slot
            else:
                print("[HeroMenu] WARN: slot '%s' not found" % node_name)

    if hero_icon and hero_icon.has_signal("pressed"):
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
    # Load hero data from server if available
    var hero_id = AppState.current_hero_id
    if hero_id > 0:
        print("[HeroMenu] Loading hero %d" % hero_id)
        var req = Network.request("/heroes/%d" % hero_id, HTTPClient.METHOD_GET)
        req.request_completed.connect(func(result, code, _hdrs, body):
            if result == HTTPRequest.RESULT_SUCCESS and code == 200:
                var json = JSON.new()
                if json.parse(body.get_string_from_utf8()) == OK and typeof(json.data) == TYPE_DICTIONARY:
                    hero = json.data
                    print("[HeroMenu] Hero loaded: %s" % hero.get("name", "?"))
        )
    else:
        hero = {"id": -1, "level": 1, "quantum_crafting_skill": 0}
        print("[HeroMenu] No hero selected — using placeholder")

func _load_items():
    # TODO: Load items from server when API is available
    available_items = []
    print("[HeroMenu] Items list cleared (server API pending)")
    _populate_items()

func _populate_items():
    if not items_grid:
        print("[HeroMenu] WARN: items_grid is NULL")
        return
    for child in items_grid.get_children():
        child.queue_free()
    for item in available_items:
        var label = Button.new()
        label.text = item.get("name", "?")
        label.pressed.connect(func():
            print("[HeroMenu] Item selected: %s" % item.get("name", "?"))
        )
        items_grid.add_child(label)
    print("[HeroMenu] Populated %d items" % available_items.size())

func _meets_requirements(item):
    if hero.level < item.get("required_level", 0):
        return false
    if hero.quantum_crafting_skill < item.get("required_skill", 0):
        return false
    return true

func _on_item_gui_input(event, item):
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        if not _meets_requirements(item):
            return
        var drag = {"item": item}
        var preview = TextureRect.new()
        preview.texture = load(item.icon_path) if item.has("icon_path") else null
        items_grid.start_drag(drag, preview)

func _on_slot_gui_input(event, slot_name):
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
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
