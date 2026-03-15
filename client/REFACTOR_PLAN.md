# UI REFACTOR PLAN — Arena Manager

## PHASE 1: Foundation (shared utilities, theme, cleanup)

### 1A. Create shared utilities
- **CREATE** `scripts/utils/ResponseParser.gd` — centralize `_extract_array()` used by every module
- **CREATE** `scripts/utils/DateTimeUtils.gd` — centralize `_normalize_datetime_string()` used by AuctionTable + Auction

### 1B. Apply global theme  
- **MODIFY** `project.godot` — add `gui/theme="res://themes/GameTheme.tres"` under `[gui]`

### 1C. Fix UIUtils (visible toast system)
- **REWRITE** `autoload/UIUtils.gd` — create a CanvasLayer-based overlay that can display toasts in any viewport

### 1D. Disconnect redundant navigation autoloads
- **MODIFY** `project.godot` — remove `Nav` and `SceneManager` autoload entries
- **MODIFY** `scripts/ui/controllers/UIManager.gd` — remove SceneManager.bind_ui_root() call; add auth/hero guard logic inline

## PHASE 2: Legacy removal

### 2A. Delete legacy shell
- **DELETE** `scenes/ui/shell/UIShell.tscn`
- **DELETE** `scenes/ui/shell/TopBar.tscn`
- **DELETE** `scripts/ui/shell/UIShellController.gd`
- **DELETE** `scripts/ui/shell/TopBarController.gd`

### 2B. Delete legacy modules (scenes/ui/modules/**)
- **DELETE** `scenes/ui/modules/account/AccountModule.tscn`
- **DELETE** `scenes/ui/modules/auction/AuctionModule.tscn`
- **DELETE** `scenes/ui/modules/chat/ChatModule.tscn`
- **DELETE** `scenes/ui/modules/heroes/HeroListModule.tscn`
- **DELETE** `scenes/ui/modules/hero_details/HeroDetailsModule.tscn`
- **DELETE** `scenes/ui/modules/inventory/InventoryModule.tscn`
- **DELETE** `scenes/ui/modules/raid/RaidModule.tscn`
- **DELETE** `scenes/ui/modules/workshop/WorkshopModule.tscn`

### 2C. Delete legacy module controllers
- **DELETE** `scripts/ui/modules/account/AccountController.gd`
- **DELETE** `scripts/ui/modules/auction/AuctionController.gd`
- **DELETE** `scripts/ui/modules/chat/ChatController.gd`
- **DELETE** `scripts/ui/modules/heroes/HeroListController.gd`
- **DELETE** `scripts/ui/modules/hero_details/HeroDetailsController.gd`
- **DELETE** `scripts/ui/modules/inventory/InventoryController.gd`
- **DELETE** `scripts/ui/modules/raid/RaidController.gd`
- **DELETE** `scripts/ui/modules/workshop/WorkshopController.gd`

### 2D. Delete legacy core scripts  
- **DELETE** `scripts/core/AppState.gd` (UIAppState)
- **DELETE** `scripts/core/EventBus.gd` (UIEventBus)
- **DELETE** `scripts/core/ApiClient.gd` (UIApiClient)
- **DELETE** `scripts/core/ModuleRouter.gd`
- **DELETE** `scripts/core/LazySceneLoader.gd`

### 2E. Delete legacy domain scripts (scripts/ui/auth, scripts/ui/auction, etc.)
- **DELETE** `scripts/ui/auth/LoginModule.gd`
- **DELETE** `scripts/ui/auth/RegisterModule.gd`
- **DELETE** `scripts/ui/auction/AuctionModule.gd`
- **DELETE** `scripts/ui/chat/ChatOverlayModule.gd`
- **DELETE** `scripts/ui/hero_creation/HeroCreationModule.gd`
- **DELETE** `scripts/ui/inventory/InventoryModule.gd`
- **DELETE** `scripts/ui/player_hub/PlayerHubModule.gd`
- **DELETE** `scripts/ui/settings/SettingsModule.gd`
- **DELETE** `scripts/ui/storage/StorageModule.gd`

### 2F. Delete unused legacy components/scenes
- **DELETE** `scenes/ui/ChatBox.tscn` (no script, unused)
- **DELETE** `scenes/ui/HeroIcon.tscn` (unused in active flow)
- **DELETE** `scripts/ui/components/hero_icon/HeroIcon.gd`

## PHASE 3: New reusable components

- **CREATE** `scripts/ui/components/StatusPill.gd` + `scenes/ui/components/StatusPill.tscn`
- **CREATE** `scripts/ui/components/ModuleHeader.gd` + `scenes/ui/components/ModuleHeader.tscn`
- **CREATE** `scripts/ui/components/EmptyState.gd` + `scenes/ui/components/EmptyState.tscn`
- **CREATE** `scripts/ui/components/LoadingOverlay.gd` + `scenes/ui/components/LoadingOverlay.tscn`
- **CREATE** `scripts/ui/components/ErrorBanner.gd` + `scenes/ui/components/ErrorBanner.tscn`
- **CREATE** `scripts/ui/components/ActivityFeed.gd` + `scenes/ui/components/ActivityFeed.tscn`
- **CREATE** `scripts/ui/components/BodyPartStatusRow.gd` + `scenes/ui/components/BodyPartStatusRow.tscn`
- **CREATE** `scripts/ui/components/TeamSlotCard.gd` + `scenes/ui/components/TeamSlotCard.tscn`
- **CREATE** `scripts/ui/components/FilterBar.gd` + `scenes/ui/components/FilterBar.tscn`
- **CREATE** `scripts/ui/components/DetailPanel.gd` + `scenes/ui/components/DetailPanel.tscn`

## PHASE 4: Refactor PlayerHub

- **REWRITE** `scenes/ui/PlayerHub.tscn` — new layout with: TopBar, LeftSidebar (all game modules), CenterPanel, RightSidebar (ChatPanel + ActivityFeed), BottomActionBar
- **REWRITE** `scripts/ui/scenes/PlayerHub.gd` — add sidebar active highlighting, new module routing, wired BottomActionBar, ActivityFeed, new sidebar entries (Training, Healing, Arena, Boss Raids)

## PHASE 5: Refactor existing modules

- **REWRITE** `scripts/ui/modules_mmo/HeroesModule.gd` + `scenes/modules/HeroesModule.tscn` — new hero detail panel with HP, status, body parts, action buttons
- **REWRITE** `scripts/ui/modules_mmo/InventoryModule.gd` + `scenes/modules/InventoryModule.tscn` — module header, loading/empty states, i18n
- **REWRITE** `scripts/ui/modules_mmo/AuctionModule.gd` + `scenes/modules/AuctionModule.tscn` — filters, bid/buy/list, live updates
- **REWRITE** `scripts/ui/modules_mmo/CraftModule.gd` + `scenes/modules/CraftModule.tscn` — recipe list, resources, craft preview

## PHASE 6: Create new modules

- **CREATE** `scripts/ui/modules_mmo/TrainingModule.gd` + `scenes/modules/TrainingModule.tscn`
- **CREATE** `scripts/ui/modules_mmo/HealingModule.gd` + `scenes/modules/HealingModule.tscn`
- **CREATE** `scripts/ui/modules_mmo/ArenaModule.gd` + `scenes/modules/ArenaModule.tscn`
- **CREATE** `scripts/ui/modules_mmo/BossRaidModule.gd` + `scenes/modules/BossRaidModule.tscn`

## PHASE 7: Critical fixes

- **REWRITE** `scripts/ui/components/AuctionTable.gd` — fix corrupted set_lots() 
- **MODIFY** `scripts/ui/controllers/UIManager.gd` — auth guards, remove SceneManager binding
- **MODIFY** `scripts/ui/components/hero_card_view.gd` — add status pill, HP bar

## FILES SUMMARY

| Action | Count |
|--------|-------|
| DELETE (legacy) | ~30 files |
| CREATE (new) | ~25 files |
| REWRITE (existing) | ~12 files |
| MODIFY (minor) | ~5 files |
