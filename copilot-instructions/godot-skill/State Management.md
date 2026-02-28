# State Management

## AppState singleton
- Use `AppState.gd` (autoload) to store game-wide data (player stats, inventory list, battle frames, etc.).
- Store only serializable data (ints, floats, Arrays, Dictionaries). Do not store Node references or scene objects.
- Define signals to notify changes (e.g. `signal inventory_updated`, `signal heroes_changed`).

## Managing updates
- Update `AppState` when data arrives from the server. For example:
    ```
    AppState.inventory = data.items
    AppState.emit_signal("inventory_updated")
    ```
- Other scripts (UI, game logic) should connect to these signals and refresh their state accordingly.
- Keep state access consistent: read from `AppState`, do not duplicate data in multiple places.

## Scoped states
- Reset or clear state variables on scene changes if necessary (e.g. clear `AppState.battle_frames` after a battle ends).
- Use separate state fields for different contexts (e.g. `AppState.battle_frames` vs `AppState.shop_items`).

## Prohibited patterns
- Do not directly manipulate scene nodes from `AppState`; use signals or event callbacks to affect the UI.
- Do not keep critical game data outside of `AppState` (avoid untracked global variables).