# UI

## Layout & Responsiveness
- Build UI with **Control** nodes and container nodes. For example, use `VBoxContainer`, `HBoxContainer`, `GridContainer`, `TabContainer`, etc., for automatic, responsive layout:contentReference[oaicite:3]{index=3}:contentReference[oaicite:4]{index=4}.
- Do not manually position elements with fixed coordinates. Instead, set anchors and use containers so the UI adapts to different screen sizes and aspect ratios.

## Node organization
- Use a `CanvasLayer` for HUD/UI so it remains on top of the game world.
- Name UI scenes and nodes clearly: e.g. `InventoryUI.tscn` (root `Control`) with child `InventoryPanel`, `EquipButton`, etc. Use PascalCase for node and class names, snake_case for file names:contentReference[oaicite:5]{index=5}.
- Example UI tree:
  
    Control (HUD)  
    ├─ ChatPanel (PanelContainer)  
    │   └─ RichTextLabel (with `bbcode_enabled = true`)  
    ├─ InventoryPanel (PanelContainer)  
    │   └─ GridContainer (item slots)  
    └─ HBoxContainer (BottomButtons)  

## Interactive elements
- Connect UI signals to handlers (e.g. `button.pressed`, `line_edit.text_submitted`).
- For chat, use `RichTextLabel` with BBCode enabled. Format clickable links using `[url]` and connect `meta_clicked` signal.
- Example deep-link handling:
    ```
    chat_label.bbcode_enabled = true  
    chat_label.append_bbcode("[url=auction://lot/%d]Lot %d[/url]\n" % [lot_id, lot_id])  
    chat_label.connect("meta_clicked", self, "_on_link_clicked")  
    ```  

## Prohibited patterns
- Do not hardcode UI positions or sizes; avoid `rect_position` overrides when using containers.
- Do not place input-handling logic in UI scripts; use `InputManager` for global input.