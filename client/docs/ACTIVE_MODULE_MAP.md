# Active Module Map (Client)

This document describes the **current active runtime architecture** after stabilization/refactor.

## Runtime Entry

- Main scene: `res://Main.tscn`
- Runtime UI controller: `scripts/ui/controllers/UIManager.gd`

## Active Autoloads

- `Network` → `scripts/network/NetworkManager.gd`
- `ApiClient` → `scripts/network/ApiClient.gd`
- `LocalizationManager` → `autoload/LocalizationManager.gd`
- `AppState` → `autoload/AppState.gd`
- `SceneManager` → `autoload/SceneManager.gd`
- `HeroManager` → `autoload/HeroManager.gd`
- `InventoryManager` → `autoload/InventoryManager.gd`
- `AuctionManager` → `autoload/AuctionManager.gd`
- `WebSocketManager` → `autoload/WebSocketManager.gd`
- `AuthManager` → `autoload/AuthManager.gd`
- `Nav` → `autoload/NavigationManager.gd` (compatibility/fallback navigation)

## Active UI Scenes (UIManager-routed)

- `scenes/ui/LoginScene.tscn`
- `scenes/ui/RegisterScene.tscn`
- `scenes/ui/PlayerHub.tscn`
- `scenes/ui/HeroCreation.tscn`
- `scenes/ui/Storage.tscn`
- `scenes/ui/Auction.tscn`
- `scenes/ui/BattleRoom.tscn`
- `scenes/ui/Settings.tscn`

## Active Reusable Components

- `scripts/ui/components/hero_card/HeroCard.gd`
- `scripts/ui/components/item_slot/` *(represented by existing `ItemSlot.gd`)*
- `scripts/ui/components/auction_row/AuctionRow.gd`
- `scripts/ui/components/chat_message/ChatMessage.gd`
- `scripts/ui/components/AuctionTable.gd` *(row pooling)*
- `scripts/ui/components/EquipSlot.gd`

## State Ownership Rules

- Persistent runtime data is owned by `AppState`.
- API responses update state through `AppState` setters/signals.
- UI scenes render from `AppState` and manager signals.
- Scene transitions go through `SceneManager` (or `Nav` compatibility layer).

## Known Compatibility Layers

- `NavigationManager.gd` still contains scene-path transition fallback for non-UI flows.
- `NetworkManager.gd` remains transport layer under `ApiClient`.

## Retired Assets

The following legacy panel/scene assets were retired from the active codebase:

- `scenes/ui/login_screen.tscn`
- `scenes/ui/Register.tscn`
- `scenes/ui/ChatBox.tscn`
- `scenes/ui/HeroIcon.tscn`
- `scripts/ui/scenes/LoginPanel.gd`
- `scripts/ui/scenes/RegisterPanel.gd`
- `scripts/ui/scenes/ChatBox.gd`
- `scripts/ui/scenes/HeroIcon.gd`
