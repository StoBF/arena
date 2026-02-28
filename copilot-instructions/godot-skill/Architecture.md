# Architecture

## Scene organization
- Each game feature has its own scene (e.g. `BattleArena.tscn`, `Hero.tscn`, `InventoryUI.tscn`). Use composition: instance sub-scenes (heroes, UI panels) as children of a root node.
- Example scene tree:
  
    Node3D (BattleArena)  
    ├─ Camera3D  
    ├─ SpawnManager (Node3D, script: spawn_manager.gd)  
    └─ UI (CanvasLayer)  
        ├─ ChatPanel  
        └─ InventoryPanel  
- Design scenes to be self-contained and loosely coupled; use signals or dependency injection (pass references/data) rather than hard-coded node paths:contentReference[oaicite:0]{index=0}.

## Autoloads & Singletons
- Declare `Network.gd`, `AppState.gd`, `InputManager.gd` as Autoloads (Singletons). 
- `Network.gd` handles HTTP/WebSocket communication; `AppState.gd` holds shared game state (inventory, heroes, battle data); `InputManager.gd` processes and filters user input.
- Keep client and server logic separate: client should only send commands and play back results, never simulate game rules locally.

## Coding standards
- Use composition over inheritance: avoid deep inheritance chains. Connect nodes via signals or callbacks (loose coupling):contentReference[oaicite:1]{index=1}.
- Type-safe node references: e.g. `onready var spawn_manager: SpawnManager = $SpawnManager`.
- Naming: script files in snake_case (e.g. `battle_arena.gd`), classes in PascalCase (`class_name BattleArena`), node names in PascalCase:contentReference[oaicite:2]{index=2}.
- Example script header:
  
      extends Node3D  
      class_name BattleArena  

      onready var spawn_manager: SpawnManager = $SpawnManager  

## Prohibited patterns
- Avoid long `get_node()` chains or hard-coded paths; do not tightly couple scenes.
- Do not mix UI code with game logic; separate UI scenes/panels from core battle logic.
- Never simulate battles on the client; always run game logic on the server and stream results to play back.