# CLIENT_AUDIT_REPORT

Date: 2026-03-15  
Scope: Full technical audit of `client/` (Godot 4 project), including scenes, scripts, autoload singletons, UI architecture, API communication, navigation, data/state flow, and architectural quality risks.

---

## 1. PROJECT STRUCTURE

### 1.1 Top-level structure

```text
client/
  autoload/
  config/
  Data/
  docs/
  scenes/
  scripts/
  tests/
  themes/
  item_icons/
  images/
  assets/
  locales/
  Main.tscn
  project.godot
  Player.tscn
  ItemDrop.tscn
  Player.gd
  ItemDrop.gd
  PickupZone.gd
  PlayerInventory.gd
  JSONData.gd
```

### 1.2 Folder purpose map

- `autoload/`
  - Global singleton services loaded via `project.godot` (networking, auth, app state, managers, navigation/event bus).
- `config/`
  - Environment config (`dev.json`, `prod.json`) used by `ServerConfig.gd`.
- `Data/`
  - Local JSON datasets (`HeroData.json`, `ItemData.json`, `RecipeData.json`) used by controller/model bootstrap.
- `scenes/`
  - UI scenes and modules (`scenes/ui/**`) and newer MMO module scenes (`scenes/modules/**`).
- `scripts/`
  - Main codebase; split into `network`, `ui`, `core`, `systems`, `models`, `utils`.
- `tests/`
  - GDScript tests for UI routing, localization, websocket auction events, inventory optimistic behavior, etc.
- `themes/`
  - Global `GameTheme.tres` for dark fantasy style.
- `item_icons/`, `images/`, `assets/`
  - Runtime iconography and sprites.
- `locales/`
  - Translation data consumed by `LocalizationManager` + `tr()` usages.

### 1.3 Architectural observation

The repository currently contains **two UI architecture generations** in parallel:

1. Legacy scene-per-screen + legacy module stack (`scenes/ui/modules/*`, `scripts/ui/modules/*`, `scripts/core/*`), and  
2. New MMO modular hub (`scenes/ui/PlayerHub.tscn` + `scenes/modules/*` + `scripts/ui/modules_mmo/*`).

This dual-stack coexistence is the most important structural fact for future redesign.

---

## 2. AUTOLOAD SINGLETONS

Autoload list from `project.godot`:

1. `Network` → `scripts/network/NetworkManager.gd`
2. `ApiClient` → `scripts/network/ApiClient.gd`
3. `JsonData` → `JSONData.gd`
4. `PlayerInventory` → `PlayerInventory.gd`
5. `LocalizationManager` → `autoload/LocalizationManager.gd`
6. `AppState` → `autoload/AppState.gd`
7. `EventBus` → `autoload/EventBus.gd`
8. `UIUtils` → `autoload/UIUtils.gd`
9. `Nav` → `autoload/NavigationManager.gd`
10. `HeroManager` → `autoload/HeroManager.gd`
11. `InventoryManager` → `autoload/InventoryManager.gd`
12. `AuctionManager` → `autoload/AuctionManager.gd`
13. `WebSocketManager` → `autoload/WebSocketManager.gd`
14. `AuthManager` → `autoload/AuthManager.gd`
15. `SceneManager` → `autoload/SceneManager.gd`
16. `ServerStatusManager` → `autoload/ServerStatusManager.gd`

### 2.1 `NetworkManager.gd`
- Responsibility:
  - Low-level HTTP orchestration (`HTTPRequest` creation, headers, retries, timeout, JSON parsing).
  - Token refresh single-flight for `401` via `/auth/refresh`.
  - Server status ping helper.
- Main functions:
  - `request_json(...)`, `_send_once(...)`, `_refresh_access_token_single_flight()`, `check_server_status()`.
- Usage:
  - Called by `ApiClient` autoload.
  - Writes token to `AppState` and emits `token_refreshed`.

### 2.2 `ApiClient.gd` (active)
- Responsibility:
  - Backend endpoint facade (`auth`, `heroes`, `inventory`, `auction`, `chat history`, `server status`).
  - Response normalization and synchronization into `AppState` (`set_auction_data`, `set_chat_messages`).
- Main functions:
  - `login`, `register`, `get_user`, `get_heroes`, `get_inventory`, `get_auction_lots`, `get_chat_messages`, `request_*` wrappers.
- Usage:
  - Called by scene scripts, managers, and controllers.
  - Delegates network execution to `Network.request_json(...)`.

### 2.3 `AuthManager.gd`
- Responsibility:
  - Login/register/logout orchestration.
  - Token assignment into `AppState` and `Network` auth header.
- Main functions:
  - `login`, `register`, `logout`, `is_authenticated`.
- Usage:
  - Used by `LoginScene`, `RegisterScene`, `Settings`, `PlayerHub`.

### 2.4 `AppState.gd` (active global state)
- Responsibility:
  - In-memory canonical client state (user profile, heroes, inventory, auctions, chat, selected hero, server status, auth tokens).
  - Emits rich state signals + forwards updates through `EventBus`.
- Main functions:
  - `set_user_data`, `set_heroes_data`, `set_inventory_data`, `set_auction_data`, `set_chat_messages`, `push_chat_message`, `set_selected_hero`, `clear_user_state`.
- Usage:
  - Read/write by almost every UI and manager script.

### 2.5 `EventBus.gd` (active bus)
- Responsibility:
  - Broad app-wide broadcast channel with “last-*” snapshots.
- Main functions:
  - `emit_scene_changed`, `emit_hero_selected`, `emit_chat_updated`, etc.
- Usage:
  - UI navigation trigger path (`UIManager` listens `scene_changed`).
  - Cross-module notifications (hero changes, inventory updates, chat updates).

### 2.6 `NavigationManager.gd` (`Nav`)
- Responsibility:
  - Scene/view route mapping + guards (auth required, hero required) + fallback handling.
- Main functions:
  - `go`, `go_view`, `go_path`, `_do_change`, `go_main_menu`.
- Usage:
  - Alternative navigation API; partially overlaps `SceneManager` + `EventBus` + `UIManager` path.

### 2.7 `SceneManager.gd`
- Responsibility:
  - Adapter over `UIManager.open_view` with methods (`open_playerhub`, `open_auction`, etc.).
- Main functions:
  - `bind_ui_root`, `open_*`, `_open_view`.
- Usage:
  - Bound by `UIManager` on startup.

### 2.8 `HeroManager.gd`
- Responsibility:
  - Hero cache + active hero management + `/heroes` sync.
- Main functions:
  - `load_heroes`, `set_active_hero_id`, `get_hero_by_id`.
- Usage:
  - Hero selection in UI scenes/modules, `Storage`, `HeroCreation`, battle flows.

### 2.9 `InventoryManager.gd`
- Responsibility:
  - Inventory/equipment domain logic, optimistic operations, cache by hero.
  - Equip/unequip/lock/dismantle/sell operations and preview stats.
- Main functions:
  - `get_items`, `equip_item`, `unequip_item`, `lock_item`, `sell_item_on_auction`, optimistic helpers.
- Usage:
  - `Storage.gd`, controller layer, post-auction sync.

### 2.10 `AuctionManager.gd`
- Responsibility:
  - Auction list querying with filter normalization + mutation operations (bid, buy, create, cancel).
- Main functions:
  - `fetch_lots`, `place_bid`, `buy_now`, `create_lot`, `cancel_lot`.
- Usage:
  - Legacy `Auction.gd` scene and state synchronization.

### 2.11 `WebSocketManager.gd`
- Responsibility:
  - Maintains `/ws/auctions` websocket subscription with reconnection/backoff.
- Main functions:
  - `ensure_auction_subscription`, `_handle_auction_packet`, `_schedule_auction_reconnect`.
- Usage:
  - `Auction.gd` live updates path.

### 2.12 `LocalizationManager.gd`
- Responsibility:
  - Locale persistence and switching (`en`, `uk`, `pl`).
- Main functions:
  - `set_locale`, `get_supported_locales`, `get_language_label`.
- Usage:
  - All UI scenes invoking `tr(...)` and listening `locale_changed`.

### 2.13 `ServerStatusManager.gd`
- Responsibility:
  - Poll server status every 10s and update `AppState.server_status/online_players`.
- Main function:
  - `request_status_update`.
- Usage:
  - Login and top bar status indicators.

### 2.14 `UIUtils.gd`
- Responsibility:
  - Lightweight transient message label/tween notifications.
- Usage:
  - Validation and error display from scenes/managers.

### 2.15 `JsonData.gd`
- Responsibility:
  - Loads `Data/ItemData.json` and exposes item metadata utilities.
- Usage:
  - `PlayerInventory` stack size and icon resolution.

### 2.16 `PlayerInventory.gd` (legacy gameplay inventory singleton)
- Responsibility:
  - Slot-based inventory/hotbar/equipment logic with drag/drop helpers.
- Observation:
  - Coexists with `InventoryManager` + controller stack and may represent older gameplay-side inventory model.

### 2.17 Autoload dependency graph (high level)

- `AuthManager` → `ApiClient`, `AppState`, `Network`
- `ApiClient` → `Network`, `AppState`, `LocalizationManager`
- `Network` → `ServerConfig`, `AppState`
- `HeroManager` / `InventoryManager` / `AuctionManager` → `ApiClient`, `AppState` (and cross-call each other)
- `ServerStatusManager` → `ApiClient`, `AppState`
- `WebSocketManager` → `ServerConfig`, `AppState`
- UI scripts consume `EventBus` + `AppState` as read/write hubs.

---

## 3. SCENE ARCHITECTURE

Total `.tscn` discovered: 40

### 3.1 Runtime root & gameplay scenes

| Scene | Script | Purpose | Loaded by |
|---|---|---|---|
| `Main.tscn` | `scripts/ui/controllers/UIManager.gd` (+ child scripts `PlayerData`, `InventoryController`, `CraftController`) | Main app root and view host (`UIRoot/CurrentView`) | `project.godot run/main_scene` |
| `Player.tscn` | `Player.gd`, `PickupZone.gd` | 2D character gameplay scene | standalone/legacy gameplay flow |
| `ItemDrop.tscn` | `ItemDrop.gd` | Dropped item in world | gameplay flow |

### 3.2 Screen scenes (scene-per-view)

| Scene | Script | Purpose | Parent / Host |
|---|---|---|---|
| `scenes/ui/LoginScene.tscn` | `scripts/ui/scenes/LoginScene.gd` | Login form + server status | Instanced into `Main/UIRoot/CurrentView` by `UIManager` |
| `scenes/ui/RegisterScene.tscn` | `scripts/ui/scenes/RegisterScene.gd` | Registration | `UIManager` |
| `scenes/ui/PlayerHub.tscn` | `scripts/ui/scenes/PlayerHub.gd` | New MMO dashboard hub with dynamic module container | `UIManager` |
| `scenes/ui/HeroCreation.tscn` | `scripts/ui/scenes/HeroCreation.gd` | Hero generation flow | `UIManager` |
| `scenes/ui/Storage.tscn` | `scripts/ui/scenes/Storage.gd` | Legacy inventory/equipment screen | `UIManager` |
| `scenes/ui/Auction.tscn` | `scripts/ui/scenes/Auction.gd` | Legacy auction table/live bid view | `UIManager` |
| `scenes/ui/BattleRoom.tscn` | `scripts/ui/scenes/BattleRoom.gd` | Battle room placeholder | `UIManager` |
| `scenes/ui/Settings.tscn` | `scripts/ui/scenes/Settings.gd` | Settings/logout | `UIManager` |
| `scenes/ui/ChatBox.tscn` | none | Old standalone chat control | currently not primary path |
| `scenes/ui/HeroIcon.tscn` | `scripts/ui/components/hero_icon/HeroIcon.gd` | Icon widget | embedded component use |

### 3.3 New MMO module scenes (active in PlayerHub)

| Scene | Script | Purpose | Parent |
|---|---|---|---|
| `scenes/modules/HeroesModule.tscn` | `scripts/ui/modules_mmo/HeroesModule.gd` | Hero roster + detail panel | dynamically loaded in `PlayerHub/ModuleContainer` |
| `scenes/modules/InventoryModule.tscn` | `scripts/ui/modules_mmo/InventoryModule.gd` | Grid inventory + detail panel | same |
| `scenes/modules/AuctionModule.tscn` | `scripts/ui/modules_mmo/AuctionModule.gd` | Search/filter/list/detail auction view | same |
| `scenes/modules/CraftModule.tscn` | `scripts/ui/modules_mmo/CraftModule.gd` | Craft placeholder module | same |
| `scenes/modules/RaidModule.tscn` | `scripts/ui/modules_mmo/RaidModule.gd` | Raid placeholder module | same |

### 3.4 Legacy module scenes (parallel architecture)

`scenes/ui/modules/**`:
- `account/AccountModule.tscn`
- `auction/AuctionModule.tscn`
- `chat/ChatModule.tscn`
- `heroes/HeroListModule.tscn`
- `hero_details/HeroDetailsModule.tscn`
- `inventory/InventoryModule.tscn`
- `raid/RaidModule.tscn`
- `workshop/WorkshopModule.tscn`

These are used by older modular shell patterns (`scripts/core/ModuleRouter.gd`, `scripts/ui/shell/*`) and coexist with new MMO modules.

### 3.5 Reusable component scenes

`scenes/ui/components/`:
- `HeroCard.tscn`, `HeroSlot.tscn`, `HeroIcon` support
- `ItemSlot.tscn`, `EquipSlot.tscn`, `TooltipItem.tscn`
- `AuctionTable.tscn`, `ConfirmDialog.tscn`
- `RecipeSlot.tscn`, `PopupRecipe.tscn`
- `CurrencyBar.tscn`, `ChatPanel.tscn`, `NotificationBadge.tscn`

### 3.6 Scene loading/switching mechanism

- Primary runtime navigation:
  - UI emits `EventBus.emit_scene_changed("ViewName")`.
  - `UIManager` listens `EventBus.scene_changed` and calls `open_view(...)`.
  - Existing view node is `queue_free()`d, new scene instantiated into `Main/UIRoot/CurrentView`.
- Secondary/adapter layer:
  - `SceneManager` can call `open_view` on bound `UIManager`.
- Additional route layer:
  - `Nav` (`NavigationManager`) supports route aliases + guards + optional `change_scene_to_file` fallback.

---

## 4. UI STRUCTURE

### 4.1 Current UI system behavior

- There are two concurrent UI paradigms:
  1. **Scene-per-screen** (Login/Register/Storage/Auction/Settings/...) loaded by `UIManager`.
  2. **Hub-with-dynamic-modules** (`PlayerHub` + `ModuleContainer`) loading `scenes/modules/*`.

- `PlayerHub` currently acts as a dashboard shell:
  - Left sidebar nav buttons load modules.
  - Right sidebar contains always-visible chat panel.
  - Top bar shows user + status + currency.
  - Bottom row has quick action buttons.

### 4.2 Open-window/menu behavior

- Most screen transitions are event-driven via `EventBus.scene_changed`.
- In-module transitions are direct function calls (`_load_module`) rather than central router.
- Some modules/scenes still use legacy direct navigation conventions.

### 4.3 Reuse level and consistency

- Positive:
  - New reusable components exist and are used in MMO modules (`HeroCard`, `ItemSlot`, `CurrencyBar`, `ChatPanel`, `NotificationBadge`).
- Issues:
  - Legacy and new module stacks duplicate functionality.
  - Mixed visual idioms across old scenes and new hub.
  - Reuse is partial; several old screens still render bespoke controls.

### 4.4 Structural UI problems

- Duplicate UI systems (`scenes/modules/*` and `scenes/ui/modules/*`).
- Deep node paths in scripts increase fragility.
- Inconsistent translation usage (newer scripts still include literal strings).
- Some component scripts appear damaged (notably `AuctionTable.gd` has malformed flow/indent blocks).

---

## 5. UI COMPONENTS

### 5.1 Reusable components present

- Hero-related:
  - `HeroCard` (`hero_card_view.gd`)
  - `HeroSlot`
  - `HeroIcon`
- Inventory/equipment:
  - `ItemSlot` (icon, rarity border, tooltip text)
  - `EquipSlot` (drop target + slot event signals)
  - `TooltipItem`
- Auction:
  - `AuctionTable` + `auction_row/AuctionRow.gd`
- Shared shell widgets:
  - `CurrencyBar`
  - `ChatPanel` (tabs, messages, announcements)
  - `NotificationBadge`
  - `ConfirmDialog`
- Crafting widgets:
  - `RecipeSlot`
  - `PopupRecipe`

### 5.2 Gaps

- No unified base button/panel component abstraction (style is theme-driven, not behavior-driven).
- Component API contracts are not standardized across old/new stacks.

---

## 6. HERO UI

### 6.1 Hero display paths

- New path:
  - `PlayerHub` loads `HeroesModule` in `ModuleContainer`.
  - `HeroesModule` calls `ApiClient.get_heroes()`, updates `AppState`, renders card grid.
  - Click on `HeroCard` emits `selected(hero_id)` → module sets `AppState.selected_hero` + `EventBus.hero_selected`.
  - Right detail panel displays stats/equipment/actions.

- Legacy path:
  - `Storage` scene uses `HeroManager.active_hero_changed` and `AppState.heroes` to update selected hero labels and equipment context.

### 6.2 Hero details behavior

- Derived in `HeroesModule.gd` via `_apply_hero_details(...)`.
- Stats from either `attributes` dictionary or inferred flat keys.
- Equipment list rendered from hero payload `equipment` dictionary when present.

### 6.3 Server load path

- `HeroesModule` or `HeroManager.load_heroes()` triggers `ApiClient.get_heroes` or manager request wrappers.
- Response normalized and stored in `AppState`.

---

## 7. INVENTORY UI

### 7.1 Inventory layouts

- New module (`scenes/modules/InventoryModule.tscn`):
  - Left: grid of `ItemSlot` components.
  - Right: item detail panel (name/rarity/qty/description).

- Legacy scene (`scenes/ui/Storage.tscn`):
  - Item grid + dual equipment side panels + hero preview.
  - More complete equipment interaction logic currently lives here.

### 7.2 Item slot behavior

- `ItemSlot.gd` supports:
  - Display (`name`, `quantity`, icon), rarity border styling, tooltip text.
  - Drag source via `_get_drag_data`.
  - Emits `item_selected` and `item_dropped`.

### 7.3 Equipment behavior

- `EquipSlot.gd`:
  - Emits `equip_slot_selected(slot_name)`.
  - Supports drop target and emits `item_dropped_to_slot(item_id, slot_name)`.

### 7.4 Drag & drop system

- Exists in component layer (`ItemSlot` drag payload + `EquipSlot` drop accept logic).
- Fully used in `Storage.gd`; new MMO inventory module currently uses click-select rather than full DnD equip path.

---

## 8. SERVER COMMUNICATION

### 8.1 Active HTTP architecture

- Layering:
  - `ApiClient` (endpoint façade) → `NetworkManager.request_json` (transport/retries/refresh).

### 8.2 Request structure

- Standard response dictionary:
  - `ok`, `result`, `code`, `headers`, `data`, `message`, optionally `raw_body`.
- JSON body automatically serialized for non-GET/DELETE requests.
- Authorization header injected when `AppState.access_token` exists.

### 8.3 Authentication/JWT handling

- `AuthManager.login` stores `access_token` + `refresh_token`.
- `NetworkManager` on 401:
  - if allowed and not yet attempted, runs `_refresh_access_token_single_flight`.
  - retries original request on success.
- `AppState` is source-of-truth for token fields.

### 8.4 Chat communication

- HTTP chat history: `ApiClient.get_chat_messages` → `/chat/history`.
- Message send in active code is websocket-only backend; API method returns not-supported response and UI falls back to local echo in some places.

### 8.5 WebSocket communication

- `WebSocketManager` handles `/ws/auctions` with token query.
- Emits events: `auction_bid_update`, `auction_lot_closed`, `auction_lot_created`.

### 8.6 Example requests

- Auth:
  - `POST /auth/login` payload `{login, password}`
- Profile:
  - `GET /auth/me`
- Heroes:
  - `GET /heroes/`
  - `POST /heroes/generate`
- Inventory:
  - `GET /inventory/{hero_id}`
- Auction:
  - `GET /auctions/lots?limit={n}&offset={m}`
  - `POST /auctions/{lot_id}/bid`
- Server status:
  - `GET /server/status`

---

## 9. DATA FLOW

### 9.1 Typical flow

`server -> ApiClient/Network -> AppState -> EventBus/AppState signals -> scene/module controller -> UI repaint`

### 9.2 Concrete examples

- Hero list:
  - `HeroesModule._load_heroes()` → `ApiClient.get_heroes()` → `AppState.set_heroes_data()` → module renders cards.
- Inventory:
  - `InventoryModule._load_inventory()` → `ApiClient.get_inventory(hero_id)` → `AppState.set_inventory_data()` → grid rebuild.
- Auction:
  - `AuctionModule._load_lots()` → `ApiClient.get_auction_lots(...)` → render tree/detail.
- Server status:
  - `ServerStatusManager` polling → `AppState.set_server_status()` → `EventBus.server_status_updated` → top bar/login status update.

### 9.3 Who updates UI

- Scene scripts (`scripts/ui/scenes/*`) and module scripts (`modules_mmo/*`, legacy modules) are responsible for repaint.
- Components perform local state rendering when passed dictionaries.

---

## 10. NAVIGATION SYSTEM

### 10.1 Navigation mechanisms in use

1. **Primary**: `EventBus.emit_scene_changed(name)` + `UIManager.open_view(name)`.  
2. **Adapter**: `SceneManager.open_*()` wrappers.  
3. **Route layer**: `Nav` (`NavigationManager`) with guard checks and fallback behavior.

### 10.2 Screen switching

- `UIManager` destroys previous current view and instantiates new scene into `Main/UIRoot/CurrentView`.

### 10.3 Module switching

- In `PlayerHub`, only `ModuleContainer` child is replaced (good for performance and state isolation).

### 10.4 Navigation issues

- Three overlapping navigation APIs increase cognitive load and coupling.
- Potential divergence risk if route names differ between `UIManager`, `SceneManager`, and `Nav` maps.

---

## 11. GAME STATE MANAGEMENT

### 11.1 Where key data lives

- Player info/currency/tokens:
  - `autoload/AppState.gd` (`user`, `username`, `balance`, `access_token`, `refresh_token`)
- Heroes:
  - Canonical runtime in `AppState.heroes`
  - Domain helper/cache in `HeroManager._heroes`
- Inventory:
  - Runtime snapshots in `AppState.inventory`
  - Domain logic + per-hero cache in `InventoryManager`
  - Additional legacy inventory in `PlayerInventory` (separate model)
- Auctions:
  - Runtime in `AppState.auction_lots` + pagination
  - Domain fetch/mutation in `AuctionManager`
- Chat:
  - `AppState.chat_messages` dictionary by channel

### 11.2 State architecture quality

- Strength: centralized mutable state exists (`AppState`) with signals.
- Weakness: duplicate state models exist (`scripts/core/AppState.gd`, `PlayerData.gd`, `PlayerInventory.gd`).

---

## 12. PERFORMANCE RISKS

1. Rebuilding full UI lists frequently:
   - Multiple modules clear and re-instantiate children on refresh.
2. Deep node path dependence:
   - long `$A/B/C/...` lookups across many scripts.
3. Concurrent polling and refresh loops:
   - Auction polling + websocket updates can duplicate refresh work.
4. Parallel architecture footprint:
   - Legacy + new module systems loaded/maintained in same repo increases maintenance overhead.
5. Potential script quality issue:
   - `scripts/ui/components/AuctionTable.gd` appears syntactically/structurally corrupted (mis-indented and logically broken code blocks), which can cause runtime instability.
6. Event signal accumulation risk:
   - Many scenes/modules connect signals in `_ready` with selective disconnect coverage.

---

## 13. ARCHITECTURE PROBLEMS

1. **Dual architecture stacks in production tree**
   - New MMO stack and legacy stack both active in codebase.
2. **State duplication**
   - `autoload/AppState` vs `scripts/core/AppState` vs `PlayerData`/`PlayerInventory` semantics overlap.
3. **API client duplication history**
   - active `scripts/network/ApiClient.gd` and legacy `scripts/core/ApiClient.gd` (still present).
4. **Navigation overlap**
   - `UIManager`, `SceneManager`, and `Nav` each own part of route logic.
5. **UI logic and data-fetch logic are mixed**
   - Many scene/module scripts fetch HTTP directly and render directly (limited separation of concerns).
6. **Inconsistent i18n and UI contracts**
   - New modules include hardcoded strings while legacy scenes use translation keys.
7. **Component quality inconsistency**
   - Some components are robust (`ItemSlot`, `ChatPanel`), while others are partially broken (`AuctionTable`).
8. **Legacy dead/unclear paths**
   - `ChatBox.tscn`, old module router/shell stack, system wrappers (`ApiGateway`, `StateStore`) add ambiguity.

---

## 14. SUMMARY

### 14.1 Implemented well

- Functional global singleton ecosystem for auth/network/state.
- Centralized network layer with retry + token-refresh single-flight.
- `PlayerHub` dynamic module replacement strategy avoids full hub reload.
- Major game domains (heroes/inventory/auction/chat/server status) all wired end-to-end.
- Reusable UI component set exists and is improving.

### 14.2 Incomplete or transitional

- Craft/Raid MMO modules are placeholders.
- New modules do not yet fully replicate all advanced legacy functionality.
- Some systems (`scripts/systems/*`, `scripts/core/*`) appear transitional wrappers.

### 14.3 Poorly designed / high-priority refactor targets

- Coexisting duplicate architectures (UI + state + api layers).
- Navigation ownership split across multiple mechanisms.
- Uneven code quality in key component script(s) (`AuctionTable.gd`).
- Mixed localization/style standards.

Overall assessment: **The client is feature-rich but architecturally transitional**. The codebase is in a migration phase from legacy screen/module patterns to a hub-driven MMO modular UI, and currently carries significant duplication that should be consolidated before the next large redesign.

---

## 15. EXPORT

Report file generated at:

`client/CLIENT_AUDIT_REPORT.md`

This report is structured for downstream AI/system ingestion and should be used as baseline input for future UI/client architecture redesign planning.
