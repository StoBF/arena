# Development Guidelines for Godot 4.4.1 Client

These are the guiding principles and conventions to follow when building the Arena client in Godot 4.4.1.

## 1. Project & File Organization
- Keep scenes (`.tscn`) under `scenes/` grouped by feature (UI, chat, heroes, etc.).
- Place UI scripts in `scripts/ui/`, network manager in `scripts/network/`, and global state in `scripts/state/`.
- Assets (fonts, textures, audio) go into clearly named subfolders in the project root.

## 2. Node & Variable Naming
- Use PascalCase for node names (`HeroesButton`, `HeroIconsContainer`, `ChatBox`).
- GDScript vars use `@onready var camel_case_name = $NodeName`.
- Prefix signal handlers with `_on_` (e.g. `_on_send_message`, `_on_hero_icon_pressed`).

## 3. Signal Connections
- Always connect signals in `_ready()` with `button.pressed.connect(Callable(self, "_on_action"))`.
- Avoid dynamic `get_node()` calls; rely on `$Path/To/Node` matching scene structure.

## 4. Asynchronous HTTP Requests
- Use `NetworkManager.request()` for all REST calls.
- Replace deprecated `yield(...)` with `await req.request_completed` (Godot 4 syntax).
- Handle status codes (`OK` and `200`/`201`) and parse JSON via `JSON.parse_string()`.

## 5. Localization
- Call `TranslationServer.set_locale(OS.get_locale_language())` in `_ready()`.
- Wrap all UI strings in `tr("key")` and maintain JSON files in `locales/*.json`.
- Re-run `_localize_ui()` on `locale_changed` signal.

## 6. Chat Integration
- Use a dedicated scene `ChatBox.tscn` with its own script (`ChatBox.gd`) and TabContainer.
- Do not duplicate chat logic in the main menu; embed one instance of `ChatBox` (always visible).
- Keep chat polling and send logic contained in `ChatBox.gd`.

## 7. Hero Icons & Stats
- Store hero icons dynamically in `HeroIconsContainer` (GridContainer) via script.
- `HeroIcon.gd` exposes `func set_hero_data(data: Dictionary)` that populates icon, name, level.
- Remove any placeholder/imported static icons from the scene.

## 8. Hero Creation Flow
- Use a separate scene `GenerateHeroScene.tscn` and script to collect name and blessing.
- On success, save result to `AppState.last_created_hero` and return to main menu.
- In `MainMenuScreen.gd` `_ready()`, detect `last_created_hero` and show its details.

## 9. Global State Management
- Keep minimal global state in `AppState` singleton: `current_hero_id`, `last_created_hero`, auth token.
- All scenes and scripts read/write to this central state.

## 10. UX & Error Handling
- Show errors via `UIUtils.show_error(tr("error_key"))`, successes with `UIUtils.show_success()`.
- Validate user input (e.g. non-empty hero name) and localize validation messages.

## 11. Code Style & Version Control
- Use 4-space indentation, PascalCase nodes, camelCase vars/functions.
- Commit frequently with descriptive messages: `feat(chat): integrate ChatBox in main menu`.
- Periodically run the editor's built-in linter and formatter.

_By adhering to these guidelines, we ensure a clean, consistent, and maintainable codebase for the Arena client._ 