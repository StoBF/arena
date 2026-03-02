extends Control
class_name HeroMenuPanel

signal item_equipped(slot_name: String, item_id: int)
signal item_unequipped(slot_name: String, item_id: int)

@onready var hero_icon: TextureButton = $HeroIcon
@onready var equipment_grid: GridContainer = $EquipmentGrid
@onready var items_grid: GridContainer = $ItemsGrid
@onready var tooltip: PopupPanel = $Tooltip

var slot_nodes: Dictionary = {}
var hero: Dictionary = {}
var available_items: Array[Dictionary] = []

func _ready() -> void:
    # TopBar
    TopBar.add_to(self, true, true)
    print("[HeroMenu] _ready() START")
    # define slots (with null safety)
    slot_nodes = {}
    if equipment_grid:
        for sn: String in ["Helmet", "Armor", "Gloves", "Boots", "Quantum Module"]:
            var node_name: String = "Slot_%s" % sn.replace(" ", "")
            var slot: Node = equipment_grid.get_node_or_null(node_name)
            if slot:
                slot_nodes[sn] = slot
            else:
                print("[HeroMenu] WARN: slot '%s' not found" % node_name)

    if hero_icon and hero_icon.has_signal("pressed"):
        hero_icon.pressed.connect(Callable(self, "_on_hero_icon_pressed"))

    _load_hero()
    _load_items()

func _setup_drag_and_drop() -> void:
    for name_variant: Variant in slot_nodes.keys():
        var name: String = str(name_variant)
        var slot: Variant = slot_nodes[name]
        slot.slot_name = name
        slot.gui_input.connect(Callable(self, "_on_slot_gui_input")).bind(name)
        slot.drop_data.connect(Callable(self, "_on_slot_drop")).bind(name)
    items_grid.drop_data.connect(Callable(self, "_on_items_drop"))

func _load_hero() -> void:
    # Load hero data from server if available
    var hero_id: int = AppState.current_hero_id
    if hero_id > 0:
        print("[HeroMenu] Loading hero %d" % hero_id)
        var req: HTTPRequest = Network.request("/heroes/%d" % hero_id, HTTPClient.METHOD_GET)
        req.request_completed.connect(func(result: int, code: int, _hdrs: PackedStringArray, body: PackedByteArray):
            if result == HTTPRequest.RESULT_SUCCESS and code == 200:
                var json: JSON = JSON.new()
                if json.parse(body.get_string_from_utf8()) == OK and typeof(json.data) == TYPE_DICTIONARY:
                    hero = json.data
                    print("[HeroMenu] Hero loaded: %s" % hero.get("name", "?"))
        )
    else:
        hero = {"id": -1, "level": 1, "quantum_crafting_skill": 0}
        print("[HeroMenu] No hero selected — using placeholder")

func _load_items() -> void:
    # TODO: Load items from server when API is available
    available_items = []
    print("[HeroMenu] Items list cleared (server API pending)")
    _populate_items()

func _populate_items() -> void:
    if not items_grid:
        print("[HeroMenu] WARN: items_grid is NULL")
        return
    for child in items_grid.get_children():
        child.queue_free()
    for item: Dictionary in available_items:
        var label: Button = Button.new()
        label.text = item.get("name", "?")
        label.pressed.connect(func():
            print("[HeroMenu] Item selected: %s" % item.get("name", "?"))
        )
        items_grid.add_child(label)
    print("[HeroMenu] Populated %d items" % available_items.size())

func _meets_requirements(item: Dictionary) -> bool:
    if int(hero.get("level", 0)) < int(item.get("required_level", 0)):
        return false
    if int(hero.get("quantum_crafting_skill", 0)) < int(item.get("required_skill", 0)):
        return false
    return true

func _on_item_gui_input(event: InputEvent, item: Dictionary) -> void:
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        if not _meets_requirements(item):
            return
        var drag: Dictionary = {"item": item}
        var preview: TextureRect = TextureRect.new()
        preview.texture = load(item.get("icon_path", "")) if item.has("icon_path") else null
        items_grid.start_drag(drag, preview)

func _on_slot_gui_input(event: InputEvent, slot_name: String) -> void:
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        var slot: Variant = slot_nodes[slot_name]
        if slot.has_meta("equipped_item"):
            var data: Dictionary = {"item": slot.get_meta("equipped_item"), "origin_slot": slot_name}
            var preview: TextureRect = TextureRect.new()
            preview.texture = slot.texture
            slot.start_drag(data, preview)

func _on_slot_drop(_position: Vector2, data: Dictionary, slot_name: String) -> void:
    if data.has("item"):
        var item: Dictionary = data["item"]
        # slot mismatch check
        if item.get("slot", "") != slot_name:
            return
        # skill requirement check
        if hero.quantum_crafting_skill < item.get("required_skill", 0):
            UIUtils.show_error(Localization.t("skill_too_low"))
            return
        var target_slot: Variant = slot_nodes[slot_name]
        # if there's already something equipped, swap it back
        if target_slot.has_meta("equipped_item") and target_slot.get_meta("equipped_item") != null:
            var old: Dictionary = target_slot.get_meta("equipped_item")
            _unequip(slot_name)
            # after unequipping we add old item back into inventory
            available_items.append(old)
            _populate_items()
        # perform equip
        _equip(item, slot_name)
        # remove the item from available list if it came from inventory
        if not data.has("origin_slot"):
            for i in range(available_items.size()):
                if available_items[i].get("id", -1) == item.get("id", -1):
                    available_items.remove_at(i)
                    break
            _populate_items()
        # if the drag originated from another slot (swap scenario), notify
        if data.has("origin_slot"):
            emit_signal("item_unequipped", data["origin_slot"], item.get("id", -1))

func _on_items_drop(_position: Vector2, data: Dictionary) -> void:
    if data.has("origin_slot") and data.has("item"):
        var slotname: String = str(data["origin_slot"])
        var old: Dictionary = slot_nodes[slotname].get_meta("equipped_item")
        _unequip(slotname)
        # returned item should be added back to inventory
        if old:
            available_items.append(old)
            _populate_items()

func _equip(item: Dictionary, slot_name: String) -> void:
    var slot: Variant = slot_nodes[slot_name]
    slot.texture = load(item.get("icon_path", "")) if item.has("icon_path") else null
    slot.set_meta("equipped_item", item)
    emit_signal("item_equipped", slot_name, int(item.get("id", -1)))

func _unequip(slot_name: String) -> void:
    var slot: Variant = slot_nodes[slot_name]
    var item: Dictionary = slot.get_meta("equipped_item")
    slot.texture = null
    slot.set_meta("equipped_item", null)
    emit_signal("item_unequipped", slot_name, int(item.get("id", -1)) if item else -1)

func _on_item_hover(item: Dictionary) -> void:
    var text: String = "%s\nStability: %d\nEnergy: %d\nDurability: %d\nMutation: %.2f" % [
        item.get("name", "?"), item.get("stability", 0), item.get("energy", 0), item.get("durability", 0), item.get("mutation_chance", 0.0)]
    tooltip.get_node("Label").text = text
    tooltip.popup()

func _on_tooltip_hide() -> void:
    tooltip.hide()

func _on_hero_icon_pressed() -> void:
    # when pressed inside this panel, keep behavior deterministic in Godot 4
    Nav.go("HeroMenu")
