extends GutTest

var menu

func before_each():
    menu = preload("res://scripts/ui/HeroMenuPanel.gd").new()
    # create dummy hero and items
    menu.hero = {"id": 1, "level": 1, "quantum_crafting_skill": 0}
    menu.available_items = [
        {"id": 10, "name": "Photon Helmet", "slot": "Helmet", "required_level": 1, "required_skill": 0,
         "stability": 5, "energy": 10, "durability": 3, "mutation_chance": 0.1,
         "icon_path": "res://assets/icons/helmet.png"},
        {"id": 11, "name": "Advanced Boots", "slot": "Boots", "required_level": 2, "required_skill": 1,
         "stability": 2, "energy": 0, "durability": 5, "mutation_chance": 0.0,
         "icon_path": "res://assets/icons/boots.png"}
    ]
    menu._populate_items()

func test_drag_and_drop_to_empty_slot():
    var item = menu.available_items[0]
    menu._on_slot_drop(Vector2.ZERO, {"item": item}, "Helmet")
    assert_eq(menu.slot_nodes["Helmet"].get_meta("equipped_item")["id"], item.id)

func test_swap_items():
    # equip first
    menu._on_slot_drop(Vector2.ZERO, {"item": menu.available_items[0]}, "Helmet")
    # now drag second item into same slot (should remove first to inventory)
    menu.hero.quantum_crafting_skill = 1
    menu.available_items.append(menu.available_items[1])
    menu._on_slot_drop(Vector2.ZERO, {"item": menu.available_items[1]}, "Helmet")
    assert_eq(menu.slot_nodes["Helmet"].get_meta("equipped_item")["id"], 11)

func test_skill_requirement_prevents_equip():
    var blocked = {"id": 20, "slot": "Helmet", "required_skill": 5, "icon_path": ""}
    menu.available_items.append(blocked)
    menu._populate_items()
    menu.hero.quantum_crafting_skill = 0
    menu._on_slot_drop(Vector2.ZERO, {"item": blocked}, "Helmet")
    assert_false(menu.slot_nodes["Helmet"].has_meta("equipped_item"))

func test_tooltip_on_item_hover():
    var item = menu.available_items[0]
    menu._on_item_hover(item)
    assert_true(menu.tooltip.visible)
    assert_match("Stability", menu.tooltip.get_node("Label").text)
    menu._on_tooltip_hide()
    assert_false(menu.tooltip.visible)

func test_icon_updates_on_equip():
    var item = menu.available_items[0]
    menu._on_slot_drop(Vector2.ZERO, {"item": item}, "Helmet")
    assert_eq(menu.slot_nodes["Helmet"].texture.get_path(), item.icon_path)

