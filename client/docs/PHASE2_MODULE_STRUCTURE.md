# Phase 2 Module Structure (Non-Breaking)

This structure introduces target modules while preserving current runtime script paths.

## Target modules

- `autoload/`
  - `ApiClient.gd`
  - `AuthManager.gd`
  - `AppState.gd`
  - `SceneManager.gd`
  - `ServerStatusManager.gd`

- `scripts/ui/`
  - `player_hub/PlayerHubModule.gd` → bridges to `scripts/ui/scenes/PlayerHub.gd`
  - `auction/AuctionModule.gd` → bridges to `scripts/ui/scenes/Auction.gd`
  - `chat/ChatOverlayModule.gd` → chat module anchor
  - `hero_creation/HeroCreationModule.gd` → bridges to `scripts/ui/scenes/HeroCreation.gd`
  - `inventory/InventoryModule.gd` → bridges to `scripts/ui/controllers/InventoryController.gd`
  - `storage/StorageModule.gd` → bridges to `scripts/ui/scenes/Storage.gd`
  - `settings/SettingsModule.gd` → bridges to `scripts/ui/scenes/Settings.gd`
  - `auth/LoginModule.gd` / `auth/RegisterModule.gd` → bridge to auth scenes

- `scripts/ui/components/`
  - `hero_card/`
  - `item_slot/ItemSlot.gd` (bridge)
  - `auction_row/`
  - `chat_message/`

- `scripts/systems/`
  - `api/ApiGateway.gd` → bridge to `scripts/network/ApiClient.gd`
  - `navigation/NavigationSystem.gd` → bridge to `autoload/SceneManager.gd`
  - `state/StateStore.gd` → bridge to `autoload/AppState.gd`

## Responsibility boundaries

- `ApiClient`: all HTTP transport and JSON/error normalization
- `AuthManager`: login/register/logout and token lifecycle
- `AppState`: single source of truth for persistent client data
- `SceneManager`: view routing and navigation transitions
- `ServerStatusManager`: periodic `/server/status` polling and AppState update
- UI modules: view-level rendering and user interactions only
- System bridges: migration-safe paths for future rerouting without scene breakage
