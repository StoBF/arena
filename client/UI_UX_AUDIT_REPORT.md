# COMPLETE UI / UX AUDIT — Arena Manager (Godot 4.5 Client)

Generated: 2026-03-15  
Scope: Full read-only analysis of every `.tscn` scene, `.gd` script, component, autoload, and theme file related to UI.

---

## 1. PROJECT UI ARCHITECTURE

### 1.1 Scene Inventory (40 scenes total)

#### Top-Level / Root Scenes

| Scene | Path | Root Node | Script | Purpose |
|-------|------|-----------|--------|---------|
| Main.tscn | `res://Main.tscn` | Control | `scripts/ui/controllers/UIManager.gd` | Application root. Contains UIRoot/CurrentView container where all views are swapped. Also hosts PlayerData, InventoryController, CraftController child nodes. |
| Player.tscn | `res://Player.tscn` | — | `Player.gd` | Legacy gameplay entity (not UI) |
| ItemDrop.tscn | `res://ItemDrop.tscn` | — | `ItemDrop.gd` | Legacy gameplay entity (not UI) |

#### Primary UI View Scenes (loaded into Main → UIRoot/CurrentView)

| Scene | Path | Root Node | Script | Purpose |
|-------|------|-----------|--------|---------|
| LoginScene.tscn | `res://scenes/ui/LoginScene.tscn` | Control | `scripts/ui/scenes/LoginScene.gd` | Player login. Email + password fields, server status indicator, Login/Register buttons. |
| RegisterScene.tscn | `res://scenes/ui/RegisterScene.tscn` | Control | `scripts/ui/scenes/RegisterScene.gd` | Account registration. Email, password, confirm password, back-to-login. |
| PlayerHub.tscn | `res://scenes/ui/PlayerHub.tscn` | Control | `scripts/ui/scenes/PlayerHub.gd` | **Primary MMO dashboard**. Left sidebar nav, top bar (player info, currency, notifications), center ModuleContainer, right ChatPanel, bottom quick-action bar. |
| HeroCreation.tscn | `res://scenes/ui/HeroCreation.tscn` | Control | `scripts/ui/scenes/HeroCreation.gd` | Hero generation. Name input, investment slider, balance display, generate/back buttons. |
| Storage.tscn | `res://scenes/ui/Storage.tscn` | Control | `scripts/ui/scenes/Storage.gd` | Inventory + equipment management. 8 EquipSlot components (helmet, armor, gloves, weapon, artifact, ring, belt, boots), hero preview, item grid, recipes. |
| Auction.tscn | `res://scenes/ui/Auction.tscn` | Control | `scripts/ui/scenes/Auction.gd` | **Legacy standalone auction screen**. Category filter, AuctionTable component, bid/buyout controls, pagination, WebSocket live updates, ConfirmDialog. |
| BattleRoom.tscn | `res://scenes/ui/BattleRoom.tscn` | Control | `scripts/ui/scenes/BattleRoom.gd` | Battle lobby. Player hero vs enemy hero display, start battle button. Placeholder with no real battle logic. |
| Settings.tscn | `res://scenes/ui/Settings.tscn` | Control | `scripts/ui/scenes/Settings.gd` | Settings panel. Volume slider, fullscreen toggle, language selector, logout button. |
| ChatBox.tscn | `res://scenes/ui/ChatBox.tscn` | Control | *(none)* | Legacy standalone chat with TabContainer (General, Trade, System, Private), RichTextLabel logs, message input. **Not scripted.** |

#### MMO Hub Module Scenes (loaded into PlayerHub → ModuleContainer)

| Scene | Path | Root Node | Script | Purpose |
|-------|------|-----------|--------|---------|
| HeroesModule.tscn | `res://scenes/modules/HeroesModule.tscn` | Control | `scripts/ui/modules_mmo/HeroesModule.gd` | Hero roster grid with HeroCard components, detail panel (stats, equipment, promote/manage gear). |
| InventoryModule.tscn | `res://scenes/modules/InventoryModule.tscn` | Control | `scripts/ui/modules_mmo/InventoryModule.gd` | Hero-scoped inventory grid with ItemSlot components, item detail panel. |
| AuctionModule.tscn | `res://scenes/modules/AuctionModule.tscn` | Control | `scripts/ui/modules_mmo/AuctionModule.gd` | Auction as embedded module. Filter panel, Tree-based lot listing, detail panel. **Simpler than standalone Auction.tscn.** |
| CraftModule.tscn | `res://scenes/modules/CraftModule.tscn` | Control | `scripts/ui/modules_mmo/CraftModule.gd` | Placeholder. Shows static text "Workshop — Select a hero and open crafting recipes." |
| RaidModule.tscn | `res://scenes/modules/RaidModule.tscn` | Control | `scripts/ui/modules_mmo/RaidModule.gd` | Placeholder. Shows static text "Raid Lobby — Queue and raid details." |

#### Legacy Shell Scenes (UIShell architecture — NOT used in active flow)

| Scene | Path | Root Node | Script | Purpose |
|-------|------|-----------|--------|---------|
| UIShell.tscn | `res://scenes/ui/shell/UIShell.tscn` | Control | `scripts/ui/shell/UIShellController.gd` | Alternate shell with TopBar, ContentHost, OverlayHost, LoadingMask. Uses UIModuleRouter for navigation. **Not loaded by Main.tscn — dead code.** |
| TopBar.tscn | `res://scenes/ui/shell/TopBar.tscn` | Control | `scripts/ui/shell/TopBarController.gd` | Horizontal button bar (Account, Heroes, Inventory, Auction, Workshop, Raid, Chat). Emits `navigation_requested` signal. Part of UIShell. |

#### Legacy Module Scenes (loaded by UIModuleRouter)

| Scene | Path | Root Node | Script | Purpose |
|-------|------|-----------|--------|---------|
| AccountModule.tscn | `res://scenes/ui/modules/account/AccountModule.tscn` | Control | `scripts/ui/modules/account/AccountController.gd` | Minimal account view. Calls `ApiClient.get_account()`, shows status label. |
| HeroListModule.tscn | `res://scenes/ui/modules/heroes/HeroListModule.tscn` | Control | `scripts/ui/modules/heroes/HeroListController.gd` | Two hardcoded "Select Hero 1/2" buttons. Uses UIAppState cast. |
| HeroDetailsModule.tscn | `res://scenes/ui/modules/hero_details/HeroDetailsModule.tscn` | Control | `scripts/ui/modules/hero_details/HeroDetailsController.gd` | Shows "Hero ID: -1" label. Stub. |
| InventoryModule.tscn | `res://scenes/ui/modules/inventory/InventoryModule.tscn` | Control | `scripts/ui/modules/inventory/InventoryController.gd` | Shows hero ID, item count, refresh button. Minimal. |
| AuctionModule.tscn | `res://scenes/ui/modules/auction/AuctionModule.tscn` | Control | `scripts/ui/modules/auction/AuctionController.gd` | Shows lot count, reload/bid buttons. Minimal. |
| WorkshopModule.tscn | `res://scenes/ui/modules/workshop/WorkshopModule.tscn` | Control | `scripts/ui/modules/workshop/WorkshopController.gd` | Shows "Hero ID: -1" label. Stub. |
| RaidModule.tscn | `res://scenes/ui/modules/raid/RaidModule.tscn` | Control | `scripts/ui/modules/raid/RaidController.gd` | Shows "Hero ID: -1" label. Stub. |
| ChatModule.tscn | `res://scenes/ui/modules/chat/ChatModule.tscn` | Control | `scripts/ui/modules/chat/ChatController.gd` | Shows message count, PollTimer (3s). Minimal. |

#### UI Component Scenes (reusable)

| Scene | Path | Root Node | Script | Purpose |
|-------|------|-----------|--------|---------|
| HeroCard.tscn | `res://scenes/ui/components/HeroCard.tscn` | PanelContainer | `scripts/ui/components/hero_card_view.gd` | Hero portrait + name + meta + stats + Select/Inspect buttons. Used in HeroesModule grid. |
| HeroIcon.tscn | `res://scenes/ui/HeroIcon.tscn` | TextureButton | `scripts/ui/components/hero_icon/HeroIcon.gd` | Compact hero button with icon, name, level. Used in legacy flows. |
| HeroSlot.tscn | `res://scenes/ui/components/HeroSlot.tscn` | Button | `scripts/ui/components/HeroSlot.gd` | Simple "Empty" / hero name button with slot index. |
| ItemSlot.tscn | `res://scenes/ui/components/ItemSlot.tscn` | Button | `scripts/ui/components/ItemSlot.gd` | Item display: icon, name, quantity, rarity border coloring, drag-and-drop support. |
| EquipSlot.tscn | `res://scenes/ui/components/EquipSlot.tscn` | Button | `scripts/ui/components/EquipSlot.gd` | Equipment slot button with slot_name export. Shows "SlotName: ItemName" or "SlotName: Empty". Supports drag-drop receive. |
| AuctionTable.tscn | `res://scenes/ui/components/AuctionTable.tscn` | VBoxContainer | `scripts/ui/components/AuctionTable.gd` | Table with column headers (Icon, Item, Seller, Current, Buyout, Remaining), scrollable row container using AuctionRow scripts. Live countdown timer. |
| CurrencyBar.tscn | `res://scenes/ui/components/CurrencyBar.tscn` | PanelContainer | `scripts/ui/components/CurrencyBar.gd` | Shows "Gold" label + amount. |
| NotificationBadge.tscn | `res://scenes/ui/components/NotificationBadge.tscn` | PanelContainer | `scripts/ui/components/NotificationBadge.gd` | Red circle badge with count. Auto-hides when count=0. |
| ChatPanel.tscn | `res://scenes/ui/components/ChatPanel.tscn` | Control | `scripts/ui/components/ChatPanel.gd` | Tab-based chat (Global/Trade/System), message ItemList, input row, system messages list, announcements list. |
| ConfirmDialog.tscn | `res://scenes/ui/components/ConfirmDialog.tscn` | ConfirmationDialog | `scripts/ui/components/ConfirmDialog.gd` | Thin wrapper around ConfirmationDialog, re-emits `action_confirmed`. |
| TooltipItem.tscn | `res://scenes/ui/components/TooltipItem.tscn` | PanelContainer | `scripts/ui/components/TooltipItem.gd` | Item tooltip popup showing name, quantity, category. Starts hidden. |
| RecipeSlot.tscn | `res://scenes/ui/components/RecipeSlot.tscn` | Button | `scripts/ui/components/RecipeSlot.gd` | Recipe button emitting `recipe_selected`. |
| PopupRecipe.tscn | `res://scenes/ui/components/PopupRecipe.tscn` | PanelContainer | `scripts/ui/components/PopupRecipe.gd` | Recipe detail popup with requirements label, craft/close buttons. |

### 1.2 Architecture Diagram

```
project.godot
  main_scene = Main.tscn

Main.tscn (UIManager.gd)
├── PlayerData (PlayerData.gd)          — local hero/resource data from JSON files
├── InventoryController (InventoryController.gd) — local + server item sync
├── CraftController (CraftController.gd) — recipe/craft logic
└── UIRoot (MarginContainer)
    └── CurrentView (Control)           — one view instance at a time
        ├── LoginScene                  ← if not authenticated
        ├── RegisterScene               ← from login
        ├── PlayerHub                   ← primary dashboard after login
        │   ├── TopBar (player info, CurrencyBar, NotificationBadge)
        │   ├── LeftSidebar (nav buttons → _load_module())
        │   ├── CenterArea
        │   │   ├── ModuleContainer     ← swappable modules
        │   │   │   ├── HeroesModule
        │   │   │   ├── InventoryModule
        │   │   │   ├── AuctionModule
        │   │   │   ├── CraftModule (placeholder)
        │   │   │   └── RaidModule (placeholder)
        │   │   └── BottomBar (quick action buttons)
        │   └── RightSidebar (ChatPanel)
        ├── HeroCreation                ← standalone full-screen view
        ├── Storage                     ← standalone equip/inventory view
        ├── Auction                     ← standalone full auction view
        ├── BattleRoom                  ← standalone battle view
        └── Settings                    ← standalone settings view
```

### 1.3 Theme System

**File:** `themes/GameTheme.tres`

- Dark fantasy palette: near-black panels (0.06, 0.07, 0.09), dark button backgrounds (0.14, 0.16, 0.21)
- Gold accent on hover/pressed borders (0.81, 0.71, 0.44 / 0.9, 0.77, 0.42)
- Muted blue-gray text: Labels (0.9, 0.92, 0.95), Buttons (0.89, 0.92, 0.98)
- Rounded corners: 8px on buttons/lists, 10px on panels, 6px on line edits
- Drop shadows on panels (5px) and buttons (3-4px)
- Default font size 16px, Labels 17px, LineEdit 15px
- Covers: Button (normal/hover/pressed), PanelContainer, Label, LineEdit, ItemList, Tree

**Usage:** GameTheme.tres is **NOT** globally applied. The project.godot has no `gui/theme` setting. PlayerHub.tscn uses a local inline `SubResource("Theme_h8otj")` (empty Theme). GameTheme.tres is only applied if scenes explicitly reference it — most do not.

---

## 2. MAIN INTERFACE FLOW

### 2.1 Player Session Path

```
App Launch
  ↓
Main.tscn loaded (UIManager._ready())
  ↓
AuthManager.is_authenticated()?
  ├── NO → open_view("LoginScene")
  │         ├── [Login pressed] → AuthManager.login() → EventBus.emit_scene_changed("PlayerHub")
  │         └── [Register pressed] → EventBus.emit_scene_changed("RegisterScene")
  │                                   └── [Register OK → Back to Login]
  └── YES → EventBus.emit_scene_changed("PlayerHub")
              ↓
        PlayerHub._ready()
              → _load_module("heroes")  ← default module
              → _refresh_chat_histories()
              → _apply_announcements()
              
        From PlayerHub sidebar buttons:
              Heroes → _load_module("heroes")
              Inventory → _load_module("inventory")
              Auction → _load_module("auction")
              Craft → _load_module("craft")
              Raid → _load_module("raid")
              Settings → EventBus.emit_scene_changed("Settings")  ← leaves hub
              Logout → AuthManager.logout() → EventBus.emit_scene_changed("LoginScene")

        From HeroesModule:
              "Manage Gear" → EventBus.emit_scene_changed("Storage")  ← leaves hub

        From PlayerHub bottom bar:
              Arena / Queue / Market / Raid ← buttons exist but have no connected logic

        From standalone scenes (Storage, Auction, BattleRoom, Settings):
              "Back" → EventBus.emit_scene_changed("PlayerHub")  ← returns to hub
```

### 2.2 Navigation Mechanisms (3 overlapping systems)

#### System 1: EventBus + UIManager (ACTIVE)
- **EventBus.emit_scene_changed(name)** sets `last_scene_name` and emits `scene_changed`
- **UIManager._on_eventbus_scene_changed()** calls `open_view(EventBus.last_scene_name)`
- `open_view()` uses a match statement to map name → preloaded PackedScene, instantiates into `UIRoot/CurrentView`
- **This is the primary navigation system used by all scene scripts.**

#### System 2: SceneManager Autoload (WIRED but passive)
- SceneManager is registered as autoload.
- UIManager._ready() calls `SceneManager.bind_ui_root(self)` 
- SceneManager.open_playerhub() etc. call `_resolve_ui_root().open_view("PlayerHub")`
- **SceneManager is bound but never directly called for navigation. It delegates to UIManager anyway.**

#### System 3: NavigationManager (Nav) Autoload (WIRED but unused)
- Registered as autoload `Nav`.
- Contains `SCENES` dict, `VIEW_ROUTES` dict, auth guards, hero guards, deduplication.
- Has `go()`, `go_view()`, `go_path()`, `go_main_menu()` methods.
- Can call `get_tree().change_scene_to_file()` which would destroy the entire Main.tscn tree.
- **No script in the active codebase calls Nav.go() or Nav.go_path().** This is dead code.

#### System 4: PlayerHub Internal Module Loading
- PlayerHub owns MODULE_SCENES dict mapping names to `scenes/modules/*.tscn`
- `_load_module(name)` destroys current module, instantiates new one in ModuleContainer
- **Sidebar button presses invoke _load_module() directly — NOT EventBus**
- Settings/Logout navigate away via EventBus.emit_scene_changed()

### 2.3 Transition Mechanism

All transitions use `queue_free()` on the old view + `add_child()` for the new view. There are no animated transitions, no loading screens, no history stack, and no back-button support outside of explicit "Back" buttons hardcoded per scene.

---

## 3. ACCOUNT / MAIN MENU UI (PlayerHub)

### 3.1 Layout Structure

```
PlayerHub (Control, full-rect)
└── RootMargin (MarginContainer, 12/14/12/14)
    ├── Background Sprite2D (decorative image)
    └── RootVBox (VBoxContainer, separation=12)
        ├── TopBarPanel (PanelContainer, min-height=64)
        │   └── TopBarMargin → TopBar (HBoxContainer, separation=16)
        │       ├── PlayerInfo (VBoxContainer)
        │       │   ├── UsernameLabel ("Player: -")
        │       │   └── StatusLabel ("Server: offline")
        │       ├── TopSpacer (flexible)
        │       ├── CurrencyBar (component instance)
        │       └── NotificationsButton (Button, min-width=170)
        │           └── NotificationBadge (component instance)
        │
        ├── BodyRow (HBoxContainer, separation=14)
        │   ├── LeftSidebarPanel (PanelContainer, min-width=230)
        │   │   └── LeftMenu (VBoxContainer, separation=12)
        │   │       ├── GameTitle Label ("Arena")
        │   │       ├── HeroesButton (min-height=44, icon=Iron Sword)
        │   │       ├── InventoryButton (min-height=44, icon=Blue Jeans)
        │   │       ├── AuctionButton (min-height=44, icon=Slime Potion)
        │   │       ├── CraftButton (min-height=44, icon=Tree Branch)
        │   │       ├── RaidButton (min-height=44, icon=Brown Shirt)
        │   │       ├── SettingsButton (min-height=44, icon=Brown Boots)
        │   │       ├── MenuSpacer (flexible)
        │   │       └── LogoutButton (min-height=44, icon=Brown Boots)
        │   │
        │   ├── CenterArea (VBoxContainer, expand-fill)
        │   │   ├── MainPanel (PanelContainer, expand-fill)
        │   │   │   └── MainMargin → ModuleContainer (Control, expand-fill)
        │   │   │       └── [dynamically loaded module]
        │   │   │
        │   │   └── BottomBarPanel (PanelContainer, min-height=62)
        │   │       └── QuickActions (HBoxContainer, separation=12)
        │   │           ├── ActionArena (Button, min-width=160)
        │   │           ├── ActionQueue (Button, min-width=160)
        │   │           ├── ActionMarket (Button, min-width=160)
        │   │           ├── BottomSpacer (flexible)
        │   │           └── ActionRaid (Button, min-width=160)
        │   │
        │   └── RightSidebarPanel (PanelContainer, min-width=360)
        │       └── ChatPanel (component instance)
```

### 3.2 Top Bar Elements

| Element | Type | Data Source | Update Trigger |
|---------|------|-------------|----------------|
| UsernameLabel | Label | `AppState.username` | `EventBus.user_data_updated` |
| StatusLabel | Label | `AppState.server_status`, `AppState.online_players` | `EventBus.server_status_updated` |
| CurrencyBar | Component | `AppState.balance` | `_apply_top_bar()` called from `_on_user_data_updated()` |
| NotificationBadge | Component | Internal `_notification_count` | Incremented on `EventBus.chat_updated` if channel ≠ active |

### 3.3 How Heroes Are Loaded from Server

1. PlayerHub does NOT load heroes itself.
2. HeroesModule._ready() calls `_load_heroes()` → `ApiClient.get_heroes()` → `/heroes/`
3. Response parsed by `_extract_heroes()` → `AppState.set_heroes_data(heroes)`
4. `_render_heroes()` creates HeroCard instances in CardsGrid
5. First hero auto-selected in detail panel

### 3.4 How Hero Icons Are Generated

- HeroCard.tscn uses `hero_card_view.gd` which sets:
  - `name_label.text` from `hero.name`
  - `meta_label.text` = "Level X | Gen Y"  
  - `stats_label.text` = "STR X  AGI X  INT X  VIT X"
  - `portrait.texture` from `hero.portrait` path (if exists, else null)
- HeroIcon.tscn (legacy) uses `hero_icon/HeroIcon.gd`:
  - TextureButton with Icon TextureRect, NameLabel, LevelLabel
  - Falls back to `icon.svg` if no hero icon texture

### 3.5 How Clicking a Hero Works

1. HeroCard.`select_button.pressed` → emits `selected(hero_id: int)`
2. HeroesModule.`_on_card_selected(hero_id)`:
   - Finds hero in `AppState.heroes`
   - Calls `_apply_hero_details(hero)` — fills detail panel
   - Calls `AppState.set_selected_hero(hero)` — updates global state
   - Calls `EventBus.emit_hero_selected(hero_id)` — broadcasts

### 3.6 Scripts Controlling PlayerHub

| Script | Role |
|--------|------|
| `scripts/ui/scenes/PlayerHub.gd` | Main hub controller: navigation, module loading, chat, notifications |
| `scripts/ui/components/ChatPanel.gd` | Chat tab switching, message rendering, send action |
| `scripts/ui/components/CurrencyBar.gd` | Gold amount display |
| `scripts/ui/components/NotificationBadge.gd` | Red badge counter |

---

## 4. HERO UI SYSTEM

### 4.1 Hero Icon Generation

**HeroCard** (active system):
- PanelContainer (280×170 minimum)
- Contains PortraitFrame (72×72 PanelContainer → TextureRect), Content VBox (name, meta, stats, action buttons)
- Portrait loaded from `hero.portrait` resource path; null if missing
- No placeholder portrait beyond empty TextureRect

**HeroIcon** (legacy):
- TextureButton with separate Icon TextureRect + VBoxContainer (name + level labels)
- Falls back to `res://icon.svg` (Godot default icon)

### 4.2 Hero List Logic

In HeroesModule:
1. `_load_heroes()` → `ApiClient.get_heroes()` → HTTP GET `/heroes/`
2. Response unwrapped: checks for `data.result[]`, `data.items[]`, or raw array
3. `AppState.set_heroes_data()` stores globally
4. `_render_heroes()` clears grid, creates HeroCard per hero, connects `selected` signal
5. First hero auto-selected for detail panel

### 4.3 Hero Selection Logic

- HeroCard emits `selected(hero_id: int)` on Select or Inspect button press
- HeroesModule receives → looks up hero in `AppState.heroes`
- Sets `_selected_hero` locally 
- Updates `AppState.selected_hero` globally
- Fires `EventBus.emit_hero_selected(hero_id)`
- Other modules (InventoryModule, BattleRoom) listen to `EventBus.hero_selected`

### 4.4 Hero Details Panel

Displayed in HeroesModule right panel:

| Field | Source Key | Format |
|-------|-----------|--------|
| Name | `hero.name` | "Name: {name}" |
| Level | `hero.level` | BBCode bold |
| Generation | `hero.generation` or `hero.gen` | BBCode bold |
| Wins | `hero.wins` or `hero.victories` | BBCode bold |
| Losses | `hero.losses` or `hero.defeats` | BBCode bold |
| Attributes | `hero.attributes{}` or fallback `hero.strength`, `hero.agility`, `hero.intelligence`, `hero.vitality` | Key: Value per line |
| Equipment | `hero.equipment{}` | ItemList rows "SlotName: ItemName" |

### 4.5 Hero Stats Display

Stats rendered in two places:
1. **HeroCard** (compact): `_build_stats()` → "STR X  AGI X  INT X  VIT X" single line
2. **Detail panel** (full): `_stat_block()` → multiline, each attribute on own line with BBCode

Both check `hero.attributes` dict first, then fall back to top-level `hero.strength` etc.

### 4.6 Hero Creation Flow

1. User navigates to HeroCreation scene (not accessible from PlayerHub sidebar — must use heroesModule "Manage Gear" → Storage, or direct navigation)
2. Name input + investment slider (0 to AppState.balance)
3. `ApiClient.create_hero(name, investment)` → POST `/heroes/generate`
4. On success: `HeroManager.load_heroes()`, refresh profile, show result status with rarity
5. Back button → `EventBus.emit_scene_changed("PlayerHub")`

---

## 5. INVENTORY UI

### 5.1 Two Inventory Interfaces

#### InventoryModule (embedded in PlayerHub)
- **Scene:** `scenes/modules/InventoryModule.tscn` 
- **Script:** `scripts/ui/modules_mmo/InventoryModule.gd`
- HSplitContainer layout: left GridPanel (6-column item grid), right DetailPanel
- Loads items for selected hero: `ApiClient.get_inventory(hero_id)` → GET `/inventory/{hero_id}`
- Creates ItemSlot instances in GridContainer
- Item detail shows: name, rarity, quantity, BBCode description
- Listens to `EventBus.hero_selected` to reload

#### Storage (standalone scene)
- **Scene:** `scenes/ui/Storage.tscn`
- **Script:** `scripts/ui/scenes/Storage.gd`
- Full equipment management view
- Left: 4 EquipSlots (helmet, armor, gloves, weapon)
- Center: HeroPreviewPanel (name, gen, level, wins/losses)
- Right: 4 EquipSlots (artifact, ring, belt, boots)
- Bottom: 5-column item grid + delete hero button
- Uses InventoryController for equip/unequip + server sync
- Includes RecipeSlot and PopupRecipe overlays for crafting

### 5.2 Inventory Grid System

- **Container:** GridContainer (5 columns in Storage, 6 columns in InventoryModule)
- **Slots:** ItemSlot.tscn instances created dynamically per item
- No fixed slot count — grid grows with item count
- No empty-slot placeholders
- Scrollable via parent ScrollContainer

### 5.3 Slot System (ItemSlot)

```
ItemSlot (Button, 86×86 min)
├── Content (VBoxContainer, 6px padding)
│   ├── Icon (TextureRect, aspect-fit)
│   ├── NameLabel (center-aligned, autowrap)
│   └── QuantityLabel (center-aligned, "x{N}")
```

- `set_item_data(data)`: Sets id, name, quantity, rarity-colored border, icon texture, tooltip
- Rarity colors: common=#7e8590, rare=#3f7ed8, epic=#8a4fd4, legendary=#f3b545
- StyleBoxFlat border override per rarity
- Disabled if quantity ≤ 0

### 5.4 Item Representation

Items are Dictionary objects with keys:
- `id`: String — unique identifier
- `name`: String — display name
- `quantity`: int — stack count
- `rarity`: String — "common", "rare", "epic", "legendary"
- `description`: String — tooltip/detail text
- `icon`: String — resource path for texture
- `category`: String — item type classification

### 5.5 Equip / Unequip Logic

1. User clicks inventory ItemSlot → `_selected_item_id` set
2. User clicks EquipSlot → `equip_slot_selected` signal → `_on_equip_slot_selected(slot_name)`
3. `InventoryController.equip_item_to_selected_hero(item_id, slot_name)` → `InventoryManager.equip_item_for_active_hero(item_id)`
4. Server call, then local refresh of equipment + items
5. EquipSlot text updates to "SlotName: ItemName"

### 5.6 Drag and Drop

**ItemSlot** implements `_get_drag_data()`:
- Returns `{type: "inventory_item", item_id, item_name}`
- Shows Label preview with item name

**EquipSlot** implements `_can_drop_data()` + `_drop_data()`:
- Accepts payloads where `type == "inventory_item"`
- On drop: emits `item_dropped_to_slot(item_id, slot_name)`
- Storage.gd connects this to auto-equip

**ItemSlot._can_drop_data()** returns false (items can't be dropped onto other items).

### 5.7 Inventory Scripts

| Script | Location | Role |
|--------|----------|------|
| `scripts/ui/modules_mmo/InventoryModule.gd` | MMO module | Hero-scoped grid + detail |
| `scripts/ui/scenes/Storage.gd` | Standalone scene | Full equip management |
| `scripts/ui/components/ItemSlot.gd` | Component | Slot display + drag source |
| `scripts/ui/components/EquipSlot.gd` | Component | Equip slot + drop target |
| `scripts/ui/controllers/InventoryController.gd` | Main child | Server sync, equip API, item management |
| `autoload/InventoryManager.gd` | Autoload | Core inventory service (CRUD, caching, equipment tracking) |

---

## 6. AUCTION UI

### 6.1 Two Auction Interfaces

#### Standalone Auction Scene (full-featured)
- **Scene:** `scenes/ui/Auction.tscn`
- **Script:** `scripts/ui/scenes/Auction.gd` (335 lines)
- **Features:**
  - Category OptionButton (heroes, armor, helmets, gloves, artifacts, recipes, resources)
  - AuctionTable component with scrollable rows
  - Lot selection → bid amount SpinBox + Place Bid / Buyout buttons
  - Pagination (prev/next) with page label
  - Auto-refresh polling every 8 seconds
  - WebSocket live updates (bid, lot created, lot closed)
  - Buyout confirmation dialog
  - Lot expiry detection
  - i18n translations

#### Embedded AuctionModule (in PlayerHub)
- **Scene:** `scenes/modules/AuctionModule.tscn`
- **Script:** `scripts/ui/modules_mmo/AuctionModule.gd` (130 lines)
- **Features:**
  - Search input + rarity OptionButton + min price filter
  - Tree control for lot listing (4 columns: ID, Item, Seller, Bid)
  - Detail panel (name, seller, bid, description)
  - No pagination, no live updates, no bidding controls
  - Fetches all lots at once (page_size=50)

### 6.2 Auction Listing UI

**AuctionTable** component (used by standalone Auction):
- Column headers: Icon, Item (180px), Seller (130px), Current (110px), Buyout (110px), Remaining (130px)
- Rows are `AuctionRow` (Button) instances created from script (not scene)
- Row pooling for performance
- Selected row highlighted via `toggle_mode`
- Emits `lot_selected(lot: Dictionary)`
- Live countdown timers with urgency indicators (⚠ ≤ 60s, ‼ ≤ 10s)

**Embedded module** uses Godot Tree control:
- 4 columns: ID, Item, Seller, Bid
- Standard Tree selection
- Client-side filtering (search, rarity, min price)

### 6.3 Bidding Interface (Standalone Only)

| Control | Type | Behavior |
|---------|------|----------|
| SelectedLotLabel | Label | Shows selected lot item name |
| BidAmount | SpinBox | Min value = computed min bid (current + 1 or explicit min_next_bid) |
| PlaceBidButton | Button | Calls `AuctionManager.place_bid(lot_id, amount)` |
| BuyoutButton | Button | Opens ConfirmDialog → `AuctionManager.buy_now(lot_id)` |
| ActionStatus | Label | Shows success/failure messages |

### 6.4 Price Display

Prices extracted from lot dict with fallback keys:
- Current: `current_price` → `current_bid` → `starting_price`
- Buyout: `buyout` → `buyout_price`
- Formatted as `"%.2f"`

### 6.5 Timer Display

Three timer modes in AuctionTable:
1. **Absolute**: `expires_at`/`end_time`/`ends_at` → parsed to unix → countdown from now
2. **Relative**: `remaining_seconds`/`expires_in`/`time_left` → decrement from capture time
3. **Static**: `remaining_time` string displayed as-is

Ticked every 1 second via `_process(delta)`. Rows disabled when expired.

### 6.6 API Calls Used

| Action | Method | Endpoint | Called By |
|--------|--------|----------|-----------|
| List lots | GET | `/auctions/lots?type=X&page=N&page_size=N` | `AuctionManager.fetch_lots()` |
| Lot details | GET | `/auctions/{lot_id}` | `AuctionManager.fetch_lot_details()` |
| Place bid | POST | `/auctions/{lot_id}/bid` `{amount}` | `AuctionManager.place_bid()` |
| Buy now | POST | `/auctions/{lot_id}/buyout` | `AuctionManager.buy_now()` |
| WebSocket | WS | Auction subscription | `WebSocketManager.ensure_auction_subscription()` |

---

## 7. NETWORK → UI CONNECTION

### 7.1 Data Flow Architecture

```
Server (FastAPI)
  ↕ HTTP (NetworkManager.gd → retry, auth, timeout)
  ↕ WebSocket (WebSocketManager.gd → auction real-time)
  ↓
ApiClient.gd            ← thin facade over Network, normalizes responses
  ↓
Autoload Managers       ← domain logic, caching, error handling
  ├── HeroManager.gd   ← hero CRUD, selection
  ├── InventoryManager.gd ← items, equipment, equip/unequip
  ├── AuctionManager.gd   ← lot fetching, bidding, pagination
  ├── AuthManager.gd      ← login, register, token management
  └── ServerStatusManager.gd ← polling server status
  ↓
AppState.gd             ← central mutable state store
  ↓ (emits signals directly + via EventBus)
EventBus.gd             ← broadcast signals with last-value cache
  ↓
UI Scripts              ← connect to EventBus signals, read AppState
```

### 7.2 ApiClient Usage Pattern

Every API call returns a Dictionary:
```gdscript
{
  "ok": bool,
  "code": int,        # HTTP status code
  "result": int,      # HTTPRequest result enum
  "headers": PackedStringArray,
  "data": Variant,    # parsed JSON body
  "message": String   # error description if !ok
}
```

### 7.3 How Server Data Becomes UI Elements

**Heroes:**
1. `ApiClient.get_heroes()` → HTTP response
2. `HeroManager._extract_heroes()` → `Array[Dictionary]`
3. `AppState.set_heroes_data()` → stores + emits `heroes_updated`
4. HeroesModule receives via direct call or `EventBus.heroes_updated`
5. For each hero: `HeroCard.set_hero(hero_dict)` → labels, portrait, stats

**Inventory:**
1. `ApiClient.get_inventory(hero_id)` → HTTP response
2. Response parsed in calling script (`InventoryModule._extract_items()` or `InventoryManager`)
3. `AppState.set_inventory_data(items)` → stores + emits `inventory_updated`
4. For each item: `ItemSlot.set_item_data(item_dict)` → icon, name, quantity, rarity border

**Auction Lots:**
1. `AuctionManager.fetch_lots(filters)` → `ApiClient.get_auction_lots()`
2. Parsed items + pagination → `AppState.set_auction_data()`
3. `EventBus.emit_auction_updated()`
4. Auction.gd: `_on_eventbus_auction_updated()` → `AuctionTable.set_lots(items)`
5. AuctionTable creates/updates AuctionRow instances with lot data

**Chat:**
1. `ApiClient.get_chat_messages(channel, limit, offset)` → HTTP
2. Synced to `AppState.set_chat_messages(channel, messages)`
3. `EventBus.emit_chat_updated()`
4. ChatPanel.`set_channel_messages()` → `_render_current_channel()` → ItemList.add_item()

### 7.4 Signals Updating UI

| Signal | Source | Listeners |
|--------|--------|-----------|
| `EventBus.hero_selected` | AppState.set_selected_hero | InventoryModule, BattleRoom, Storage |
| `EventBus.heroes_updated` | AppState.set_heroes_data | HeroesModule (indirect) |
| `EventBus.user_data_updated` | AppState.set_user_data | PlayerHub (top bar), HeroCreation (balance) |
| `EventBus.inventory_updated` | AppState.set_inventory_data | Storage |
| `EventBus.auction_updated` | AppState.set_auction_data | Auction.gd |
| `EventBus.chat_updated` | AppState.push_chat_message | PlayerHub (notification count) |
| `EventBus.server_status_updated` | AppState.set_server_status | LoginScene (indicator), PlayerHub (status label) |
| `EventBus.scene_changed` | Any script | UIManager (view switching) |

---

## 8. UI DESIGN PROBLEMS

### 8.1 Critical Structural Problems

#### P1: Dual Architecture — Active + Legacy Stacks Coexist

Two complete UI architectures are present and **both partially functional**:

| | Active Stack | Legacy Stack |
|-|-----------|-------------|
| Shell | Main.tscn → UIManager → PlayerHub | UIShell.tscn → UIShellController → TopBar |
| Router | PlayerHub._load_module() | UIModuleRouter with LazySceneLoader |
| State | AppState (autoload) | UIAppState (class_name, scripts/core) |
| Events | EventBus (autoload) | UIEventBus (class_name, scripts/core) |
| API | ApiClient (autoload) | UIApiClient (class_name, scripts/core) |
| Modules | scenes/modules/*.tscn | scenes/ui/modules/**/*.tscn |

Legacy modules (AccountModule, HeroListModule, etc.) are stub implementations that reference `UIAppState` class not compatible with the active `AppState` autoload. **Running them causes cast errors.**

#### P2: Three Navigation Systems

1. **EventBus.emit_scene_changed()** + UIManager (used everywhere)
2. **SceneManager** autoload (bound but passive — redundant indirection)
3. **NavigationManager (Nav)** autoload (fully implemented with guards — completely unused)

This creates confusion about which navigation API is canonical.

#### P3: AuctionTable.gd Code Corruption

Lines 30-47 of `AuctionTable.gd` contain **garbled/interleaved code**:

```gdscript
func set_lots(lots: Array) -> void:
			_set_empty_visible(true)
			for row in _row_pool:
				if row is Control:
					(row as Control).visible = false

	if lots.is_empty():
		_set_empty_visible(false)
		var empty_label := Label.new()
		for i: int in range(lots.size()):
			var row = _ensure_row(i)
			row.visible = true
			row.disabled = false
			var lot_variant = lots[i]
		rows_container.add_child(empty_label)
		_selected_lot_id = -1
				row.set_auction_lot(lot)
```

Multiple code blocks from different logic paths are merged together with wrong indentation. This function **will crash at runtime**.

#### P4: GameTheme.tres Not Applied Globally

The theme is defined but not set in `project.godot` `gui/theme`. PlayerHub uses an empty inline theme. Most scenes inherit default Godot styling unless components apply their own StyleBoxFlat overrides.

### 8.2 Layout / Hierarchy Problems

#### P5: Inconsistent Layout Patterns

- LoginScene, RegisterScene, HeroCreation: centered VBox with fixed offset sizing (no responsive)
- PlayerHub: responsive 3-column layout with margins
- Storage: full-rect VBox with manual offsets
- Auction: MarginContainer approach
- BattleRoom, Settings: centered fixed VBox

No consistent layout methodology. Mixing anchor-based, offset-based, and container-based layouts.

#### P6: No Responsive/Mobile Considerations

- PlayerHub has fixed min-width sidebar (230px) + fixed right panel (360px)
- Bottom bar buttons have fixed 160px widths
- No breakpoint logic for different screen sizes
- Mobile renderer configured but UI is desktop-only design

#### P7: Bottom Bar Quick Actions Are Disconnected

PlayerHub bottom bar has 4 buttons (Arena, Queue, Market, Raid) that **have no `pressed` signal connections**. They are purely decorative.

#### P8: Module Navigation State Not Tracked

PlayerHub._load_module() doesn't track which module is active. No way to restore module state on return. No breadcrumbs or tab highlighting for current module.

### 8.3 Component / Code Problems

#### P9: Hardcoded Strings in MMO Modules

HeroesModule, InventoryModule, AuctionModule use hardcoded English strings ("Loading heroes...", "Failed to load", "Name: -"). The standalone scenes (Auction.gd, Storage.gd) properly use `tr()` keys. **i18n coverage is inconsistent.**

#### P10: Duplicated Data Extraction Logic

`_extract_heroes()`, `_extract_items()`, `_extract_lots()` are copy-pasted across:
- HeroesModule.gd
- InventoryModule.gd
- AuctionModule.gd (mmo)
- HeroManager.gd
- InventoryManager.gd
- AuctionManager.gd
- Auction.gd (standalone)

Same pattern: check for Array, check for `data.result[]`, check for `data.items[]`. Should be a single utility function.

#### P11: Duplicated _normalize_datetime_string()

Present in both AuctionTable.gd and Auction.gd — identical 20-line function.

#### P12: State Duplication

Hero data lives in:
- `AppState.heroes` (Array)
- `AppState.selected_hero` (Dictionary)  
- `HeroManager._heroes` (Array[Dictionary])
- `PlayerData.heroes` (local JSON) — legacy, loaded from file, not server

Inventory data lives in:
- `AppState.inventory` + `AppState.inventory_items`
- `InventoryManager._items` + `_items_by_hero`
- `InventoryController._items` (local JSON seeds)

#### P13: Inconsistent Hero ID Types

- AppState: `current_hero_id: int`, `selected_hero.id` (varies)
- HeroManager: `_active_hero_id: int`
- PlayerData: `selected_hero_id: String`
- HeroCard: `_hero_id: int`
- UIModels.hero() normalizes to `String`

int vs String hero IDs create subtle bugs in lookups.

#### P14: Missing Loading States

No loading spinners, no skeleton screens, no progress indicators during:
- Hero list fetch
- Inventory fetch  
- Auction lot fetch
- Hero creation API call

Only text-status labels that briefly show "Loading..." then update.

#### P15: Missing Error Recovery UI

Network failures show brief text in status labels. No:
- Retry buttons (except manual Refresh)
- Error dialogs
- Offline state handling
- Connection loss detection in UI

#### P16: No Scroll Indicators

ScrollContainers (heroes grid, inventory grid, auction rows) have no visual scroll indicators. Users don't know there's more content below.

#### P17: Memory Leak Risk — queue_free() Without Await

Module switching calls `queue_free()` on old module then immediately instantiates new one. During the frame gap, both exist simultaneously. If old module has pending awaits, those coroutines can dangle and reference freed objects.

#### P18: UIUtils Notification Is Invisible

UIUtils creates a Label as a child of the autoload Node (which has no visual scene tree placement). The Label is never positioned on screen and its opacity animation plays on a node that isn't in any viewport. **Error/success toasts are never actually visible.**

---

## 9. UI COMPONENT REUSE

### 9.1 Components That Exist and Are Reused

| Component | Used In | Reuse Count |
|-----------|---------|-------------|
| HeroCard.tscn | HeroesModule (grid) | 1 scene |
| ItemSlot.tscn | InventoryModule (grid), Storage (grid) | 2 scenes |
| EquipSlot.tscn | Storage (8 instances) | 1 scene |
| CurrencyBar.tscn | PlayerHub (top bar) | 1 scene |
| NotificationBadge.tscn | PlayerHub (top bar) | 1 scene |
| ChatPanel.tscn | PlayerHub (right sidebar) | 1 scene |
| AuctionTable.tscn | Auction (standalone) | 1 scene |
| ConfirmDialog.tscn | Auction (buyout), Storage (delete hero) | 2 scenes |
| TooltipItem.tscn | Storage | 1 scene |
| RecipeSlot.tscn | Storage | 1 scene |
| PopupRecipe.tscn | Storage | 1 scene |
| HeroIcon.tscn | Not currently used in active flow | 0 scenes (legacy) |
| HeroSlot.tscn | Not currently used in active flow | 0 scenes (legacy) |

### 9.2 Components That Should Exist But Don't

| Missing Component | Where Needed | Currently Implemented As |
|-------------------|-------------|--------------------------|
| **LoadingSpinner** | Every API call | Hardcoded "Loading..." status labels |
| **ErrorBanner** | Every screen | `UIUtils.show_error()` that doesn't render |
| **PageHeader** | Every view (Back + Title + Spacer + Actions pattern) | Manually built HBoxContainer per scene |
| **StatRow** | Hero details, item details | Inline label text formatting |
| **TabNavigation** | PlayerHub sidebar highlighting | No active tab tracking |
| **EmptyState** | Hero list (no heroes), Inventory (no items), Auction (no lots) | Either no handling or plain label |
| **DetailPanel** | Heroes detail, Inventory detail, Auction detail | Each module builds its own VBox with similar fields |
| **FilterBar** | Auction (both versions have different filter approaches) | Inline per-module |
| **PaginationBar** | Auction scene | Inline HBoxContainer |
| **BottomActionBar** | Auction (bid/buyout), Storage (delete hero) | Inline per scene |

### 9.3 Style Inconsistencies

| Issue | Where |
|-------|-------|
| Panel margin = 12px in PlayerHub, 16px in Auction, 8px in CraftModule | Across scenes |
| Grid separation varies: 6px (Storage), 8px (HeroesModule), 10px (InventoryModule) | Grid containers |
| Button min-height: 44px (sidebar), 42px (EquipSlot), 34px (AuctionRow), unset (others) | Various |
| Title labels: some bold via BBCode, some plain, some use `horizontal_alignment = 1` | Headers |
| Font sizes: theme says 16, Labels override to 17, some components use default | Text elements |

---

## 10. SUGGESTED UI ARCHITECTURE IMPROVEMENTS

### 10.1 UI Architecture Recommendations

1. **Consolidate to single architecture**: Remove UIShell, UIModuleRouter, UIAppState, UIEventBus, UIApiClient, UILazySceneLoader, TopBarController, and all legacy module scenes/controllers. Leave only Main.tscn → UIManager → PlayerHub → modules_mmo.

2. **Unify navigation**: Keep EventBus.emit_scene_changed() as the single navigation API. Remove SceneManager and NavigationManager autoloads. Port Nav's auth/hero guards into UIManager.open_view().

3. **Fix AuctionTable.gd**: The `set_lots()` function is completely corrupted and must be rewritten.

4. **Apply GameTheme.tres globally**: Set `gui/theme` in project.godot or apply to Main.tscn root so all children inherit it.

5. **Create shared utility**:
   - `ResponseParser.extract_array(data)` — replaces all duplicated _extract_heroes/items/lots
   - `DateTimeUtils.normalize(str)` — replaces duplicated datetime parsing
   - `FormatUtils.currency(amount)` — consistent currency formatting

6. **Standardize hero ID as int**: Remove all String hero IDs. UIModels.hero() should return int id.

7. **Create base module class**: All MMO modules share: header with title+refresh, body split, status label. Create `BaseModule extends Control` with these common elements.

8. **Add proper loading/error states**: Create LoadingOverlay and ErrorBanner components used across all modules.

9. **Complete i18n**: All hardcoded English strings in modules_mmo scripts must use `tr()` keys.

10. **Fix UIUtils**: Either make it add its notification Label to the active viewport's CanvasLayer, or replace with a proper toast/snackbar system.

### 10.2 Scene List Summary (for redesign reference)

**Keep (active):** Main.tscn, LoginScene, RegisterScene, PlayerHub, HeroCreation, Storage, Auction (standalone), BattleRoom, Settings, all components, all scenes/modules/*.tscn

**Remove or consolidate (dead/legacy):** UIShell.tscn, TopBar.tscn, all scenes/ui/modules/**/*.tscn (AccountModule, HeroListModule, HeroDetailsModule, legacy InventoryModule, legacy AuctionModule, WorkshopModule, legacy RaidModule, ChatModule), ChatBox.tscn, HeroIcon.tscn (unused), HeroSlot.tscn (unused)

**Fix:** AuctionTable.gd (corrupted code)

### 10.3 Navigation Flow Simplification

```
Target flow (single system):
  EventBus.emit_scene_changed("view_name")
    → UIManager._on_eventbus_scene_changed()
      → open_view(name)
        → guards: auth check, hero check
        → queue_free old view
        → instantiate + add_child new view
        → bind_controllers()
```

### 10.4 State Architecture Simplification

```
Target state flow:
  Server → ApiClient → Domain Manager (HeroManager etc.)
    → AppState (single source of truth)
      → EventBus signals
        → UI reads AppState, reacts to signals
```

Remove: PlayerData local JSON, InventoryController._items local copies, UIAppState class, dual inventory/inventory_items arrays in AppState.

---

*End of UI/UX Audit Report*
