# Drag and Drop

## Inventory drag-and-drop
- Implement `get_drag_data(position)`, `can_drop_data(position, data)`, and `drop_data(position, data)` in Controls for draggable inventory items and drop targets.
- Provide a preview with `set_drag_preview(texture)` during drag.
- Example:
  
      func get_drag_data(position):
          var drag_data = {"item_id": self.item_id}
          set_drag_preview($Icon.texture)
          return drag_data

      func can_drop_data(position, data):
          return data.has("item_id")

      func drop_data(position, data):
          Network.request_equip_item(data.item_id, hero_id)

- Refresh inventory only when the inventory UI is open or on explicit drop events. Trigger an HTTP update in `Network.gd` as needed.

## Naming & Structure
- Scene and script names: e.g. `InventorySlot.tscn` (root `Control`), script `inventory_slot.gd` (class_name `InventorySlot`).
- Hero equipment slots are similar scenes (e.g. `HeroSlot.tscn`) with drop logic in the script.
- Keep drag data minimal (e.g. just item IDs or refs).

## Prohibited patterns
- Do not simulate drag-and-drop manually via mouse events; use Godot's Control drag callbacks.
- Do not update inventory state outside the allowed scope (only on drop or confirmation).