# Phase 17 Validation Matrix

Scope: static architecture/runtime-path validation for client flows after incremental refactor.

## 1) Login Flow

- **Status:** PASS
- **Evidence:**
  - Login action: `scripts/ui/scenes/LoginScene.gd` (`_on_login_pressed`)
  - Auth call: `AuthManager.login(...)`
  - Navigation: `scripts/ui/controllers/UIManager.gd` (`login_success` → `SceneManager.open_playerhub`)
- **Notes:** minimal login UI retained with server status indicator.

## 2) Server Status Monitoring

- **Status:** PASS
- **Evidence:**
  - Poll manager: `autoload/ServerStatusManager.gd` (10s timer)
  - State update: `AppState.set_server_status(...)`
  - UI subscription: `LoginScene.gd` subscribes to `AppState.server_status_updated`
- **Notes:** no manual refresh button required in login flow.

## 3) Hero Creation

- **Status:** PASS
- **Evidence:**
  - Submit call: `HeroCreation.gd` (`ApiClient.create_hero(...)`)
  - Post-success sync: `await HeroManager.load_heroes()` + profile refresh via `ApiClient.get_user()`
  - State writes: `AppState.set_heroes_data(...)`, `AppState.set_user_data(...)`

## 4) Hero Selection

- **Status:** PASS
- **Evidence:**
  - Hero bar emits: `scripts/ui/components/hero_card/HeroCard.gd` (`hero_selected`)
  - Hub flow: `PlayerHub.gd` (`hero_selected(hero_id)` + details render + `HeroManager.set_active_hero_id(...)`)
  - State sync: `AppState.set_selected_hero(...)`

## 5) Chat Messaging + History

- **Status:** PASS (with compatibility fallback)
- **Evidence:**
  - Send API: `ApiClient.send_chat_message(...)`
  - History API: `ApiClient.get_chat_messages(...)` (`/chat/messages` then fallback `/chat/history`)
  - AppState source: `AppState.set_chat_messages(...)` and `AppState.push_chat_message(...)`
  - UI render: `PlayerHub.gd` + `scripts/ui/components/chat_message/ChatMessage.gd`
  - Performance cap: `AppState.MAX_CHAT_HISTORY = 200`
- **Notes:** channel colors active (global white, trade yellow, system green).

## 6) Auction Browsing + Actions

- **Status:** PASS
- **Evidence:**
  - Lots source: `AuctionManager.fetch_lots(...)` → `AppState.set_auction_data(...)`
  - Scene updates from manager signals: `Auction.gd`
  - Post-mutation sync centralized: `AuctionManager._sync_after_auction_mutation(...)`
- **Notes:** redundant scene-level `_request_lots()` after successful bid/buyout removed.

## 7) Inventory Usage (Storage)

- **Status:** PASS
- **Evidence:**
  - Equipment actions: `InventoryController.equip_item_to_selected_hero(...)` → `InventoryManager.equip_item_for_active_hero(...)`
  - Inventory source: `InventoryManager.get_items(...)` → `AppState.set_inventory_data(...)`
  - Storage refresh path: `Storage.gd` + `InventoryController.refresh_items_from_server(...)`

## 8) No UI Overlap

- **Status:** PARTIAL (static check only)
- **Evidence:**
  - `PlayerHub.tscn` layout uses segmented regions (top/center/right/bottom-left chat overlay)
- **Notes:** runtime viewport/device-size QA still required for full confirmation.

## 9) No Broken Signals

- **Status:** PASS (static)
- **Evidence:**
  - Diagnostics: no script/scene errors in touched files via static checker.

## 10) No Duplicate API Calls

- **Status:** PARTIAL
- **Resolved:** duplicate refresh after auction bid/buyout removed in `Auction.gd`.
- **Remaining watch items:**
  - Some flows intentionally refresh both local controller cache and manager state for compatibility (`Storage.gd` / `InventoryController.gd`).
  - Recommend optional telemetry pass to quantify call frequency before removing compatibility refreshes.

## 11) AppState as Single Source of Truth

- **Status:** PASS (for persistent runtime state)
- **Evidence:**
  - AppState owns user/heroes/inventory/auction/chat/server status fields and emits update signals.
  - UI scenes subscribe to AppState and manager signals; persistent writes routed through managers/API.

---

## Final Runtime QA Needed

For complete sign-off, run manual integrated checks in editor/runtime:
- login + transition to hub
- status updates every 10s
- hero creation updates bar + balance
- hero selection updates details
- chat send/history/channel color behavior
- auction paging + bid/buyout refresh
- storage equip drag/drop + inventory consistency
