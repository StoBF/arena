# Arena Manager – UI Refactor Summary

## Overview

Complete UI refactor of the Arena Manager Godot 4.5 client, transforming it from a fragmented dual-architecture system into a unified **hero management + arena spectator dashboard** inspired by Battle Brothers, Darkest Dungeon, and Football Manager.

---

## Architecture Changes

### Navigation: 3 Systems → 1
- **Removed**: `Nav` autoload, `SceneManager` autoload, `ModuleRouter`
- **Kept**: `EventBus.emit_scene_changed()` → `UIManager._on_eventbus_scene_changed()` → `open_view()`

### Auth & Hero Guards
- `UIManager.open_view()` now checks auth state (redirects to Login) and hero existence (redirects to PlayerHub) before switching views.

### Global Theme
- `GameTheme.tres` now applied globally via `project.godot` → `[gui] theme/custom`.

---

## New Shared Utilities

| File | Purpose |
|------|---------|
| `scripts/utils/ResponseParser.gd` | `extract_array()` / `extract_pagination()` — replaces all duplicated response parsing |
| `scripts/utils/DateTimeUtils.gd` | `normalize_datetime()` / `format_countdown()` / `format_price()` — replaces inline datetime logic |

---

## 10 Reusable Components (script-only, programmatic UI)

| Component | File | Purpose |
|-----------|------|---------|
| StatusPill | `scripts/ui/components/StatusPill.gd` | Color-coded hero status tags (healthy/injured/critical/dead/training/healing/etc.) |
| ModuleHeader | `scripts/ui/components/ModuleHeader.gd` | Title + status text + refresh button |
| EmptyState | `scripts/ui/components/EmptyState.gd` | Centered icon + title + description for empty views |
| LoadingOverlay | `scripts/ui/components/LoadingOverlay.gd` | Semi-transparent overlay with pulsing "Loading…" label |
| ErrorBanner | `scripts/ui/components/ErrorBanner.gd` | Dismissible error message with optional retry button |
| ActivityFeed | `scripts/ui/components/ActivityFeed.gd` | Scrollable timestamped event log (battle/auction/training/healing/craft/system) |
| BodyPartStatusRow | `scripts/ui/components/BodyPartStatusRow.gd` | Body part name + HP ProgressBar + condition label |
| TeamSlotCard | `scripts/ui/components/TeamSlotCard.gd` | Hero slot for team composition (used in Arena & Boss Raid) |
| FilterBar | `scripts/ui/components/FilterBar.gd` | Search field + category dropdown + apply button |
| DetailPanel | `scripts/ui/components/DetailPanel.gd` | Title + key-value fields + action buttons |

---

## PlayerHub Rewrite

**New layout**: TopBar | LeftSidebar (200px) | CenterArea | RightSidebar (320px)

### Left Sidebar Navigation (3 groups)
1. **Core**: Heroes, Inventory, Workshop, Auction
2. **Activities**: Training, Healing
3. **Combat**: Arena, Boss Raids
4. **Footer**: Settings, Logout

### Features Added
- Active sidebar button highlighting (gold `StyleBoxFlat`)
- Server status color indicator (green/yellow/red)
- ActivityFeed in right sidebar
- Quick-status label (hero count)
- BottomActionBar wired: Create Hero → HeroCreation, Queue PvP → Arena module, Boss Raid → BossRaid module, Market → Auction module

---

## Module Summary

### Refactored Existing Modules

| Module | Key Changes |
|--------|-------------|
| **HeroesModule** | +LoadingOverlay, +EmptyState, +StatusPill, +BodyPartStatusRow (6 body parts), ResponseParser |
| **InventoryModule** | +LoadingOverlay, +EmptyState, ResponseParser |
| **AuctionModule** | +Bid/Buy controls (LineEdit + Place Bid + Buy Now buttons), +LoadingOverlay, +EmptyState, +Time Left column, ResponseParser, DateTimeUtils |
| **CraftModule** | Complete rewrite from empty stub → recipe browser with DetailPanel, craft button |

### New Modules

| Module | Purpose |
|--------|---------|
| **TrainingModule** | Hero selection (idle/healthy only), training type dropdown, start training |
| **HealingModule** | Injured hero list, body part damage display, heal action |
| **ArenaModule** | PvP mode selection (1v1/3v3/5v5), team composition with TeamSlotCards, queue system |
| **BossRaidModule** | Boss selection, 3-column layout, 5-slot team builder, raid start |

### Deleted
- `RaidModule.gd` + `RaidModule.tscn` (replaced by BossRaidModule)

---

## AuctionTable Rewrite

- Fixed corrupted `set_lots()` function
- Uses `DateTimeUtils.normalize_datetime()` and `DateTimeUtils.format_countdown_urgent()` instead of inline methods
- Clean row pool management with proper `time_cells` tracking

---

## UIUtils (Toast System) Rewrite

- **Before**: Label node in autoload tree → invisible
- **After**: `CanvasLayer` (layer 100) → `VBoxContainer` at top-center → animated fade-in/out toasts with colored left borders, max 5 visible

---

## i18n Updates

~70 new translation keys added across all 3 locale files:

| Locale | File | Status |
|--------|------|--------|
| English | `locales/en.json` | ✅ Updated |
| Polish | `locales/pl.json` | ✅ Updated |
| Ukrainian | `locales/uk.json` | ✅ Updated |

Key categories: `HUB_*`, `HEROES_*`, `INV_*`, `AUCTION_*`, `CRAFT_*`, `TRAINING_*`, `HEALING_*`, `ARENA_*`, `BOSS_*`, `ui.auction_table.*`

---

## Deleted Files (~30+)

### Shell System
- `scenes/ui/shell/UIShell.tscn`, `TopBar.tscn`
- `scripts/ui/shell/UIShellController.gd`, `TopBarController.gd`

### Legacy Modules (8 scenes + 8 scripts)
- `scenes/ui/modules/` — Heroes, Inventory, Auction, Chat, HeroCreation, Settings, Storage, Craft `.tscn` files
- `scripts/ui/modules/` — corresponding controller `.gd` files

### Legacy Core
- `scripts/core/` — AppState.gd, EventBus.gd, ApiClient.gd, ModuleRouter.gd, LazySceneLoader.gd

### Legacy Domain Scripts
- `scripts/ui/auth/`, `scripts/ui/auction/`, `scripts/ui/chat/`, `scripts/ui/hero_creation/`, `scripts/ui/inventory/`, `scripts/ui/player_hub/`, `scripts/ui/settings/`, `scripts/ui/storage/`

### Other
- `scenes/ui/ChatBox.tscn`, `scenes/ui/HeroIcon.tscn`, `scripts/ui/components/hero_icon/`
- `RaidModule.gd`, `RaidModule.tscn`

---

## File Count

| Category | Count |
|----------|-------|
| New scripts created | 16 (10 components + 4 modules + 2 utilities) |
| New scenes created | 4 (.tscn for new modules) |
| Scripts rewritten | 6 (PlayerHub.gd, UIUtils.gd, CraftModule.gd, AuctionTable.gd, PlayerHub.tscn, CraftModule.tscn) |
| Scripts refactored | 5 (UIManager.gd, HeroesModule.gd, InventoryModule.gd, AuctionModule.gd) |
| Config modified | 1 (project.godot) |
| Locale files updated | 3 (en.json, pl.json, uk.json) |
| Files deleted | ~30+ |
