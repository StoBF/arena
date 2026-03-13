# EventBus Phase 10 Validation (Godot Client)

## Scope

Validation of global EventBus architecture rollout across client systems:

- Hero flow
- Chat flow
- Auction flow
- Inventory flow
- Server status flow
- Scene navigation flow

## Required Signals (EventBus)

Defined in `autoload/EventBus.gd`:

- `hero_selected(hero_id)`
- `heroes_updated`
- `user_data_updated`
- `inventory_updated`
- `auction_updated`
- `chat_message_received`
- `chat_updated`
- `server_status_updated`
- `scene_changed`

Status: ✅ Implemented

## Architecture Flow Verification

Target flow:

`Server -> ApiClient -> AppState update -> EventBus emit -> UI refresh`

### 1) Hero Selection

- Source emit:
  - `scripts/ui/components/hero_card/HeroCard.gd` emits `EventBus.emit_hero_selected(_hero_id)`
- State update:
  - `scripts/ui/scenes/PlayerHub.gd` handles event and syncs to `HeroManager/AppState`
- UI consumers:
  - `scripts/ui/scenes/PlayerHub.gd` (hero details)
  - `scripts/ui/scenes/BattleRoom.gd` (selected hero label)

Status: ✅ Pass (static)

### 2) Chat Updates

- Source fetch:
  - `scripts/network/ApiClient.gd::get_chat_messages(...)`
- AppState update:
  - ApiClient now hydrates `AppState.set_chat_messages(channel, lines)`
- Event emit:
  - `AppState.set_chat_messages` emits EventBus `chat_updated`
- UI consumer:
  - `scripts/ui/scenes/PlayerHub.gd` listens to EventBus `chat_updated` and refreshes chat list

Status: ✅ Pass (static)

### 3) Auction Updates

- Source fetch:
  - `scripts/network/ApiClient.gd::get_auction_lots(...)`
- AppState update:
  - ApiClient now hydrates `AppState.set_auction_data(items, pagination)`
- Event emit:
  - `AppState.set_auction_data` emits EventBus `auction_updated`
- UI consumer:
  - `scripts/ui/scenes/Auction.gd` listens to EventBus and refreshes `AuctionTable`

Status: ✅ Pass (static)

### 4) Inventory Updates

- Source mutation:
  - Inventory operations via `InventoryManager` and controllers
- AppState update:
  - `AppState.set_inventory_data(items)`
- Event emit:
  - EventBus `inventory_updated`
- UI consumer:
  - `scripts/ui/scenes/Storage.gd` listens to EventBus and refreshes inventory grid

Status: ✅ Pass (static)

### 5) Server Status Updates

- Source poll:
  - `autoload/ServerStatusManager.gd` polls every 10 seconds
- AppState update:
  - `AppState.set_server_status(status, online_players)`
- Event emit:
  - EventBus `server_status_updated`
- UI consumers:
  - `scripts/ui/scenes/LoginScene.gd`
  - `scripts/ui/scenes/PlayerHub.gd`

Status: ✅ Pass (static)

### 6) Scene Navigation (No direct scene-to-scene calls)

- Navigation event emit:
  - UI scenes call `EventBus.emit_scene_changed("...")`
- Consumer/orchestrator:
  - `scripts/ui/controllers/UIManager.gd` listens to EventBus `scene_changed` and opens target view

Status: ✅ Pass (static)

## Dependency & Loop Safety

### Circular dependency risk

- EventBus is one-way pub/sub mediator.
- Scenes no longer route through direct scene signals for primary navigation.

Status: ✅ No circular dependency introduced (static review)

### Duplicate signal refresh risk

- Auction duplicate AppState writes removed from `AuctionManager` (ApiClient now source of auction hydration).
- PlayerHub duplicate chat hydration removed (ApiClient now source of chat hydration).
- Hero reselection no-op guard remains in PlayerHub.

Status: ✅ Reduced duplicate refresh paths

### UI refresh loop risk

- EventBus handlers update local UI from AppState snapshots.
- No handler emits same EventBus signal recursively.

Status: ✅ No direct loop found (static)

## Runtime Validation Checklist (Manual)

Pending manual runtime execution in Godot editor/client:

- [ ] Hero click updates details panel immediately
- [ ] Battle room selected hero mirrors hero selection
- [ ] Incoming chat history updates chat overlay without duplicate lines
- [ ] Auction table refreshes on fetch/realtime events without duplicate redraw bursts
- [ ] Inventory updates after equip/move operations
- [ ] Login and PlayerHub server status indicators update every poll interval
- [ ] Scene transitions work through EventBus only

Status: 🟨 Pending manual runtime confirmation

## Final Summary

- EventBus architecture is implemented and integrated across core systems.
- Required global signals are present.
- Core data/event flow now aligns with the requested pipeline.
- Static validation passes; runtime checklist remains to be executed in live client.
