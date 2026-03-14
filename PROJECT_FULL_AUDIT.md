# PROJECT_FULL_AUDIT

## 1) PROJECT OVERVIEW

### Repository purpose (code-evidenced)
- Backend is a FastAPI service (`Server/app/main.py`) with async SQLAlchemy, JWT auth, auction, heroes, inventory, equipment, crafting, chat, raid/PvE/PvP, tournaments, events, and server status APIs.
- Client is Godot (`client/project.godot`) with autoload managers for auth, heroes, inventory, auction, websocket, app state, navigation, and status polling.
- There are **two client networking layers** in code:
  - New/autoload path: `client/scripts/network/ApiClient.gd` + `client/scripts/network/NetworkManager.gd` (registered in `client/project.godot`).
  - Legacy/UI layer: `client/scripts/core/ApiClient.gd` (`class_name UIApiClient`) + UI modules/controllers using `/root/ApiClient` casts.

### Important folder tree
```text
arena/
├─ Server/
│  ├─ app/
│  │  ├─ main.py
│  │  ├─ core/                # config, enums, redis cache/pubsub, locks, events
│  │  ├─ auth/                # auth dependencies
│  │  ├─ database/
│  │  │  ├─ base.py
│  │  │  ├─ session.py
│  │  │  └─ models/           # user, hero, auction, bid, pve/pvp, craft, etc.
│  │  ├─ schemas/             # pydantic schemas for routers/services
│  │  ├─ services/            # domain services (hero, auction, bid, craft, raid, etc.)
│  │  ├─ routers/             # HTTP + WebSocket routes
│  │  └─ tasks/               # background cleanup + auction sweep
│  ├─ migrations/
│  └─ tests/
├─ client/
│  ├─ project.godot
│  ├─ autoload/               # AppState, AuthManager, HeroManager, etc.
│  ├─ scripts/
│  │  ├─ network/             # active network layer
│  │  ├─ core/                # legacy/parallel UI network/state layer
│  │  ├─ ui/modules/          # module controllers
│  │  ├─ ui/scenes/           # Godot scenes logic
│  │  └─ utils/               # ServerConfig and helpers
│  └─ tests/
└─ sql/
```

## 2) SERVER ARCHITECTURE

### Startup and app wiring
- `Server/app/main.py`:
  - Loads env (`dotenv`), configures logging (`app.core.log_config.setup_logging`).
  - FastAPI `lifespan` performs:
    1. `wait_for_postgres_ready()`
    2. `create_database_if_not_exists()` (PostgreSQL only)
    3. `create_db_and_tables()`
    4. Optional Redis cache connect (`settings.REDIS_URL`)
    5. One startup auction sweep (`run_auction_sweep_once`)
    6. Starts background tasks: `delete_old_heroes_task`, `close_expired_auctions_task`
  - Middleware: CORS + request/response logging middleware.
  - Exception handlers: HTTP/validation/SQLAlchemy/generic.
  - Rate limit global default: SlowAPI limiter `10/second`.

### Router registration
- Included in `main.py`:
  - `auth` (`/auth` prefix), `hero`, `auction`, `bid`, `announcement`, `inventory`, `equipment`, `workshop`, `chat`, `health`, `battle`, `raid`, `craft`, `pvp`, `tournaments`, `events`, `server`.
- **Not included in `main.py`** (exists in routers folder):
  - `item.py` (`/items`) and `pve.py` (`/pve/raid`) are present but not mounted.

### Cross-cutting backend components
- `Server/app/core/config.py`: environment-backed settings (DB URL, JWT times, CORS origins, cookie flags, retries).
- `Server/app/auth/__init__.py`: auth dependencies (`get_current_user_info`, `get_current_user`) using JWT + DB lookup + role checks.
- `Server/app/database/session.py`: async engine/session; creates metadata for all imported models.
- `Server/app/core/events.py`: in-process event bus used for cache invalidation events.
- `Server/app/services/base_service.py`: transaction helper `_txn()` and shared commit/rollback utility.

## 3) DATABASE STRUCTURE

### ORM foundation
- Base + soft delete mixin: `Server/app/database/base.py`.
- Session/engine: `Server/app/database/session.py`.
- Metadata import aggregator: `Server/app/database/models/__init__.py`.

### Main tables by domain (from model classes)

| Domain | Tables (model files) |
|---|---|
| Users/Auth | `users` (`models/user.py`) |
| Heroes | `heroes`, `hero_perks`, `perks` (`models/hero.py`, `models/perk.py`) |
| Items/Inventory/Equipment | `items`, `stash`, `equipment` (`models/models.py`) |
| Auctions/Bids | `auctions`, `auction_lots`, `bids`, `auto_bids` (`models/models.py`) |
| Chat | `chat_messages`, `offline_messages` (`models/models.py`) |
| Battle betting | `battle_queue`, `battle_bets` (`models/battle.py`) |
| Crafting | `craft_recipes`, `craft_recipe_resources`, `crafted_items`, `craft_queue` (`models/craft.py`) |
| PvE/Raid | `mob_templates`, `boss_perks`, `mob_perks`, `raid_arena_instances`, `pve_battle_logs`, `raid_bosses`, `raid_drops`, `recipe_drops` (`models/pve.py`, `models/raid_boss.py`) |
| PvP | `pvp_matches`, `pvp_battle_logs`, `leaderboard` (`models/models.py`) |
| Events | `event_definitions`, `event_instances` (`models/event.py`) |
| Tournaments | `tournament_templates`, `tournament_instances` (`models/tournament.py`) |
| Economy ledger | `currency_transactions` (`models/currency_transaction.py`) |
| Resources | `resources` (`models/resource.py`) |
| Quantum subsystem | `quantum_heroes`, `quantum_equipment`, `quantum_resources`, `quantum_recipes`, `quantum_crafted_items` (`models/quantum_models.py`) |

### Constraints/indexes observed
- Monetary non-negative checks on users/hero/auction/bid/autobid (`CheckConstraint` definitions).
- Composite index `ix_heroes_owner_deleted` and soft-delete fields in `heroes`.
- Unique constraints for hero perks, stash `(user_id,item_id)`, equipment `(hero_id,slot)`, battle queue uniqueness, bet uniqueness `(bettor_id,hero_id)`.

## 4) HERO SYSTEM

### API and service
- Router: `Server/app/routers/hero.py` (`/heroes` endpoints).
- Service: `Server/app/services/hero.py`.
- Generation logic: `Server/app/services/hero_generation.py` + `Server/app/core/hero_config.py`.

### Mechanics implemented in code
- Hero listing with pagination and cache keying (`heroes:{user_id}:{limit}:{offset}`).
- Hero generation (`/heroes/generate`) with:
  - generation tier checks,
  - probabilistic generation (`BASE_SUCCESS_RATES` + currency bonus function),
  - Faker localized names (`LOCALE_MAP`),
  - random attributes (`ATTRIBUTE_RANGES`),
  - perk assignment from `perks` table,
  - nickname derivation from dominant trait/perk.
- Hero soft delete/restore window: deleted heroes can be restored only if within 7 days (`deleted_at` cutoff in service).
- Training lifecycle: start/complete training with XP reward.
- Perk upgrade endpoint increments `HeroPerk.perk_level`.
- Experience/level-up progression in `add_experience` (`100 * level^1.5` threshold).

## 5) AUCTION SYSTEM

### Files
- Routers: `Server/app/routers/auction.py`, `Server/app/routers/bid.py`.
- Services: `Server/app/services/auction.py`, `Server/app/services/auction_lot.py`, `Server/app/services/bid.py`.
- Background sweep: `Server/app/tasks/auctions.py`.

### Implemented behavior
- Two auction types:
  - Item auctions (`auctions` table).
  - Hero lots (`auction_lots` table).
- Transactional safeguards:
  - `SELECT ... FOR UPDATE` on auction/lot/user/stash rows.
  - background sweeps use advisory lock (`pg_try_advisory_lock`) to avoid duplicate closes across instances.
- Bids support idempotency key (`Bid.request_id` unique, checked in `BidService.place_bid` / `place_lot_bid`).
- Reserve accounting and release flows are ledgered through `AccountingService.adjust_balance`.
- Auto-bid model and endpoint exist (`/auctions/autobid` with reserve adjustments).

### Client-facing mismatch facts
- Client `AuctionManager.gd` calls `/auctions/%d/bid`, `/auctions/%d/buy`, DELETE `/auctions/%d` and `/auction/lots?...`.
- Server routers expose `/bids/`, `/auctions/{id}/cancel` (POST), and `/auctions/lots` (plural route/prefix conventions differ).
- This mismatch is code-observed in route strings and router definitions.

## 6) INVENTORY & ITEMS

### Backend
- Router: `Server/app/routers/inventory.py` (stash add/list).
- Item router exists: `Server/app/routers/item.py` (CRUD), **not mounted** in `main.py`.
- Services: `services/inventory.py`, `services/item.py`, `services/equipment.py`.

### Implemented behavior
- Stash stores `(user_id,item_id,quantity)`.
- Equip/unequip operations are transactional and support slot swaps.
- Ownership checks are in equipment router/service.

### Client behavior
- `InventoryManager.gd` uses routes such as `/inventory`, `/items/%d`, `/heroes/%d/equip`, `/inventory/%d/dismantle`, `/inventory/%d/lock`.
- Several of these routes are not present in mounted backend routers (`/heroes/%d/equip`, `/inventory/%d/dismantle`, `/inventory/%d/lock`).

## 7) CRAFTING / WORKSHOP

### Files
- Routers: `Server/app/routers/craft.py`, `Server/app/routers/workshop.py`.
- Service: `Server/app/services/craft.py`.
- Models: `Server/app/database/models/craft.py`.

### Implemented logic
- Recipe listing and availability checks (`can_craft` compares stash resources).
- Craft queue with `ready_at` time.
- Finish craft creates `CraftedItem` with mutation chance.
- Disenchant returns a configured fraction of recipe resources.
- Both `/craft/*` and `/workshop/*` routes overlap in responsibility.

## 8) RAID BOSSES / PVE / PVP SYSTEMS

### Raid/PvE
- Router files: `routers/raid.py`, `routers/pve.py`.
- Services: `services/raid.py`, `services/pve.py`, `services/combat.py`, `services/actions.py`.
- `raid.py` routes are mounted; `pve.py` routes are not mounted in `main.py`.
- `RaidService` supports:
  - raid instance creation,
  - wave generation from mob templates,
  - battle log persistence,
  - reward roll/drop to stash.

### PvP
- Router: `routers/pvp.py`.
- Service: `services/pvp.py`.
- Features in code:
  - match creation,
  - battle log persistence,
  - Elo-like leaderboard update,
  - reward roll placeholders via settings IDs.

### Battle queue/betting
- Router: `routers/battle.py` includes duel/team/raid sim, queue submit/list, hero stats lookup, betting, prediction.

### Stub/partial indicators
- `services/actions.py` has TODO stubs for action resolution and PvP simulation returning empty/default values.
- `services/pve.py` uses fields (`wave`, `mobs`) not present in `RaidArenaInstance` model from `models/pve.py` (code inconsistency).

## 9) CLIENT ARCHITECTURE (GODOT)

### Project and autoload registration
- `client/project.godot` autoloads active singletons:
  - `Network`, `ApiClient` from `scripts/network/*`,
  - state/managers (`AppState`, `HeroManager`, `InventoryManager`, `AuctionManager`, `WebSocketManager`, `AuthManager`, `ServerStatusManager`, etc.).

### Networking layers in code
1. **Active network layer** (`client/scripts/network/ApiClient.gd`, `NetworkManager.gd`):
   - JSON requests via `Network.request_json`.
   - Access token refresh single-flight logic in `NetworkManager`.
2. **Legacy/UI layer** (`client/scripts/core/ApiClient.gd` with `class_name UIApiClient`):
   - hardcoded `base_url` and separate HTTP/WebSocket code.
   - used by multiple `client/scripts/ui/modules/*Controller.gd` files via `/root/ApiClient` casts.

### UI modules/scenes analyzed
- Modules: `client/scripts/ui/modules/*` controllers for account, auction, chat, heroes, hero_details, inventory, raid, workshop.
- Scenes: `client/scripts/ui/scenes/LoginScene.gd`, `RegisterScene.gd`, `PlayerHub.gd`, `HeroCreation.gd`, `Auction.gd`, `Storage.gd`, `BattleRoom.gd`, `Settings.gd`.
- Event-driven UI pattern through `EventBus` and `AppState` updates.

### Real-time client channels
- `PlayerHub.gd` opens chat sockets via `ServerConfig.get_ws_endpoint(channel, token)` for `general` and `trade`.
- `WebSocketManager.gd` implements auction socket to `/ws/auctions` with reconnect.

## 10) API ENDPOINTS

### Endpoint inventory from `Server/app/routers` (HTTP + WebSocket)
Legend:
- Auth: `yes` if dependency uses `get_current_user`/`get_current_user_info`; else `no`.
- Client usage lists literal route call sites found in client scripts.
- `uncertain` means path mapping is not directly resolvable due dynamic composition or conflicting layers.

| Router file | Method | Route | Params summary | Auth | Response model | Client usage (route strings) |
|---|---|---|---|---|---|---|
| `routers/auth.py` | POST | `/auth/register` | `UserCreate` body | no | `UserOut` | `scripts/network/ApiClient.gd` `/auth/register`; `scripts/core/ApiClient.gd` `/auth/register` |
| `routers/auth.py` | POST | `/auth/login` | `UserLogin` body | no | `TokenResponse` | `scripts/network/ApiClient.gd` `/auth/login`; `scripts/core/ApiClient.gd` `/auth/login` |
| `routers/auth.py` | POST | `/auth/google-login` | `google_token` body | no | `TokenResponse` | none found |
| `routers/auth.py` | POST | `/auth/refresh` | refresh token from cookie/body/header | no | `TokenRefreshResponse` | `scripts/network/NetworkManager.gd` `/auth/refresh` |
| `routers/auth.py` | POST | `/auth/logout` | request/response | yes | none | none found |
| `routers/auth.py` | GET | `/auth/me` | none | yes | `UserWithBalance` | `scripts/network/ApiClient.gd` `/auth/me` |
| `routers/hero.py` | GET | `/heroes/` | query `limit`,`offset` | yes | `HeroesPaginatedResponse` | `autoload/HeroManager.gd` `/heroes`; `scripts/network/ApiClient.gd` `/heroes/`; `scripts/core/ApiClient.gd` `/heroes` |
| `routers/hero.py` | GET | `/heroes/{hero_id}` | path `hero_id` | yes | `HeroRead` | `scripts/core/ApiClient.gd` `/heroes/%d` |
| `routers/hero.py` | POST | `/heroes/generate` | body `HeroGenerateRequest` | yes | `HeroRead` | `scripts/network/ApiClient.gd` `/heroes/generate` |
| `routers/hero.py` | DELETE | `/heroes/{hero_id}` | path `hero_id` | yes | `HeroRead` | `scripts/core/ApiClient.gd` `/heroes/%d` |
| `routers/hero.py` | POST | `/heroes/{hero_id}/restore` | path `hero_id` | yes | `HeroRead` | none found |
| `routers/hero.py` | POST | `/heroes/{hero_id}/train` | path `hero_id`, query `duration_minutes` | yes | `HeroRead` | none found |
| `routers/hero.py` | POST | `/heroes/{hero_id}/complete_training` | path `hero_id`, query `xp_reward` | yes | `HeroRead` | none found |
| `routers/hero.py` | POST | `/heroes/{hero_id}/perks/upgrade` | path `hero_id`, body `PerkUpgradeRequest` | yes | `dict` | none found |
| `routers/auction.py` | POST | `/auctions/` | body `AuctionCreate` | yes | `AuctionOut` | `autoload/AuctionManager.gd` `/auctions`; `autoload/InventoryManager.gd` `/auctions/` |
| `routers/auction.py` | GET | `/auctions/` | query `limit`,`offset` | yes | `AuctionsPaginatedResponse` | none found |
| `routers/auction.py` | POST | `/auctions/{auction_id}/cancel` | path `auction_id` | yes | `AuctionOut` | none found |
| `routers/auction.py` | POST | `/auctions/{auction_id}/close` | path `auction_id` | yes | `AuctionOut` | none found |
| `routers/auction.py` | POST | `/auctions/lots` | body `AuctionLotCreate` | yes | `AuctionLotOut` | none found |
| `routers/auction.py` | GET | `/auctions/lots` | query `limit`,`offset` | yes | `AuctionLotsPaginatedResponse` | `scripts/network/ApiClient.gd` `/auctions/lots`; `autoload/AuctionManager.gd` `/auction/lots?%s` (legacy mismatch) |
| `routers/auction.py` | GET | `/auctions/{auction_id}` | path `auction_id` | yes | `AuctionOut` | `autoload/AuctionManager.gd` `/auctions/%d` |
| `routers/auction.py` | POST | `/auctions/lots/{lot_id}/close` | path `lot_id` | yes | `AuctionLotOut` | none found |
| `routers/auction.py` | POST | `/auctions/lots/{lot_id}/delete` | path `lot_id` | yes | `AuctionLotOut` | none found |
| `routers/auction.py` | POST | `/auctions/autobid` | body `AutoBidCreate` | yes | `AutoBidOut` | none found |
| `routers/bid.py` | POST | `/bids/` | body `BidCreate` | yes | `BidOut` | none found (client calls `/auctions/%d/bid` and `/auction/bid`) |
| `routers/bid.py` | GET | `/bids/` | query `limit`,`offset` | yes | `BidsPaginatedResponse` | none found |
| `routers/bid.py` | GET | `/bids/{bid_id}` | path `bid_id` | yes | `BidOut` | none found |
| `routers/bid.py` | DELETE | `/bids/{bid_id}` | path `bid_id` | yes | `BidOut` | none found |
| `routers/announcement.py` | POST | `/announcements/` | body `AnnouncementCreate` | yes | `AnnouncementOut` | none found |
| `routers/announcement.py` | GET | `/announcements/` | none | yes | `List[AnnouncementOut]` | none found |
| `routers/announcement.py` | GET | `/announcements/{announcement_id}` | path `announcement_id` | yes | `AnnouncementOut` | none found |
| `routers/announcement.py` | DELETE | `/announcements/{announcement_id}` | path `announcement_id` | yes | `AnnouncementOut` | none found |
| `routers/inventory.py` | POST | `/inventory/` | body `StashCreate` | yes | `StashOut` | none found |
| `routers/inventory.py` | GET | `/inventory/` | none | yes | `List[StashOut]` | `autoload/InventoryManager.gd` `/inventory` |
| `routers/equipment.py` | POST | `/equipment/` | body `EquipmentCreate` | yes | `EquipmentOut` | `client/tests/test_integration.gd` `/equipment/` |
| `routers/equipment.py` | DELETE | `/equipment/{equipment_id}` | path `equipment_id` | yes | none | none found |
| `routers/equipment.py` | GET | `/equipment/` | none | yes | `List[EquipmentOut]` | none found |
| `routers/equipment.py` | GET | `/equipment/hero/{hero_id}` | path `hero_id` | yes | `List[EquipmentOut]` | none found |
| `routers/workshop.py` | GET | `/workshop/available` | none | yes | `List[CraftRecipeOut]` | none found |
| `routers/workshop.py` | GET | `/workshop/queue` | none | yes | `List[CraftQueueOut]` | none found |
| `routers/workshop.py` | POST | `/workshop/craft/{recipe_id}` | path `recipe_id` | yes | `CraftQueueOut` | `scripts/ui/controllers/CraftController.gd` `/workshop/craft/%s`; tests `/workshop/craft/1` |
| `routers/workshop.py` | POST | `/workshop/finish/{queue_id}` | path `queue_id` | yes | `CraftedItemOut` | none found |
| `routers/workshop.py` | POST | `/workshop/disenchant/{crafted_id}` | path `crafted_id` | yes | `DisenchantOut` | none found |
| `routers/chat.py` | WS | `/ws/general` | query `token` | token query | n/a | `PlayerHub.gd` via `ServerConfig.get_ws_endpoint("general", token)` |
| `routers/chat.py` | WS | `/ws/trade` | query `token` | token query | n/a | `PlayerHub.gd` via `ServerConfig.get_ws_endpoint("trade", token)` |
| `routers/chat.py` | WS | `/ws/system` | query `token` | token query | n/a | none found |
| `routers/chat.py` | WS | `/ws/private` | query `token` | token query | n/a | none found |
| `routers/chat.py` | GET | `/chat/history` | query `channel`,`user_id?`,`limit` | yes | `List[ChatMessageOut]` | `scripts/network/ApiClient.gd` `/chat/history?%s` |
| `routers/chat.py` | DELETE | `/chat/message/{message_id}` | path `message_id` | yes (+role runtime) | `ChatMessageOut` | none found |
| `routers/chat.py` | POST | `/chat/system-message` | body `to_user_id`,`text` | yes (+admin runtime) | none | none found |
| `routers/chat.py` | GET | `/chat/private-history` | query `user_id`,`other_id`,`limit` | yes (+participant/runtime role) | `List[ChatMessageOut]` | none found |
| `routers/health.py` | GET | `/health` and `/health/` | none | no | none | status path from `scripts/utils/ServerConfig.gd` default `/health` |
| `routers/battle.py` | POST | `/battle/duel` | query/body `hero_id`,`enemy_id` | yes | none | none found |
| `routers/battle.py` | POST | `/battle/team` | body `hero_ids`,`enemy_ids` | yes | none | none found |
| `routers/battle.py` | POST | `/battle/raid` | body `hero_ids`,`boss_id` | yes | none | none found |
| `routers/battle.py` | POST | `/battle/queue/submit` | body `SubmitIn(hero_id)` | yes | none | none found |
| `routers/battle.py` | GET | `/battle/queue` | none | no | none | none found |
| `routers/battle.py` | GET | `/battle/hero/{hero_id}` | path `hero_id` | no | none | none found |
| `routers/battle.py` | POST | `/battle/bet` | body `BetIn(hero_id,amount)` | yes | none | none found |
| `routers/battle.py` | GET | `/battle/predict` | none | no | none | none found |
| `routers/raid.py` | GET | `/raid/bosses` | none | no | `List[RaidBossOut]` | `scripts/core/ApiClient.gd` `/raid/bosses` |
| `routers/raid.py` | POST | `/raid/start` | params `boss_id`,`hero_ids` | yes | `ArenaInstanceOut` | none found |
| `routers/raid.py` | POST | `/raid/battle/{instance_id}` | path `instance_id` | no | `PvEBattleLogOut` | none found |
| `routers/raid.py` | POST | `/raid/rewards/{instance_id}` | path `instance_id` | no | `List[RewardOut]` | none found |
| `routers/craft.py` | GET | `/craft/recipes` | none | no | `List[CraftRecipeOut]` | none found (`scripts/core/ApiClient.gd` uses `/recipes`) |
| `routers/craft.py` | POST | `/craft/start` | body `CraftStartIn` | yes | `CraftQueueOut` | none found |
| `routers/craft.py` | POST | `/craft/finish` | body `CraftQueueOut` | yes | `CraftedItemOut` | none found |
| `routers/craft.py` | POST | `/craft/disenchant` | body `DisenchantIn` | yes | `DisenchantOut` | none found |
| `routers/craft.py` | GET | `/craft/available` | none | yes | `List[CraftRecipeOut]` | none found |
| `routers/craft.py` | GET | `/craft/queue` | none | yes | `List[CraftQueueOut]` | none found |
| `routers/pvp.py` | POST | `/pvp/match` | body `PvPMatchIn` | no | `PvPBattleLogOut` | none found |
| `routers/pvp.py` | GET | `/pvp/leaderboard` | none | no | `List[LeaderboardEntryOut]` | none found |
| `routers/tournaments.py` | POST | `/tournaments` | body `TournamentCreateIn` | yes | `TournamentOut` | none found |
| `routers/tournaments.py` | POST | `/tournaments/{tournament_id}/advance` | path + body `MatchAdvanceIn` | yes | `TournamentOut` | none found |
| `routers/events.py` | GET | `/events/definitions` | none | no | `List[EventDefinitionOut]` | none found |
| `routers/events.py` | POST | `/events/schedule` | none | no | `List[int]` | none found |
| `routers/events.py` | POST | `/events/{instance_id}/activate` | path `instance_id` | no | `EventInstanceOut` | none found |
| `routers/events.py` | POST | `/events/{instance_id}/finalize` | path `instance_id` | no | `EventInstanceOut` | none found |
| `routers/events.py` | POST | `/events/{instance_id}/join` | path + body `EventJoinIn` | yes | `EventInstanceOut` | none found |
| `routers/server.py` | GET | `/server/status` | none | no | `ServerStatusOut` | `scripts/network/ApiClient.gd` `/server/status` |
| `routers/item.py` *(not mounted)* | POST | `/items/` | body `ItemCreate` | yes | `ItemOut` | `autoload/InventoryManager.gd` `/items/%d` only GET-style usage |
| `routers/item.py` *(not mounted)* | GET | `/items/` | none | yes | `List[ItemOut]` | none found |
| `routers/item.py` *(not mounted)* | GET | `/items/{item_id}` | path `item_id` | yes | `ItemOut` | `autoload/InventoryManager.gd` `/items/%d` |
| `routers/item.py` *(not mounted)* | PUT | `/items/{item_id}` | path + body | yes | `ItemOut` | none found |
| `routers/item.py` *(not mounted)* | DELETE | `/items/{item_id}` | path | yes | `ItemOut` | none found |
| `routers/pve.py` *(not mounted)* | POST | `/pve/raid/start` | body/list `hero_ids` | yes | `ArenaInstanceOut` | none found |
| `routers/pve.py` *(not mounted)* | POST | `/pve/raid/battle/{instance_id}` | path | no | `PvEBattleLogOut` | none found |
| `routers/pve.py` *(not mounted)* | POST | `/pve/raid/rewards/{instance_id}` | path | no | `List[RewardOut]` | none found |

## 11) REALTIME / CHAT SYSTEM

### Server
- Chat WS endpoints in `Server/app/routers/chat.py`: `/ws/general`, `/ws/trade`, `/ws/system`, `/ws/private`.
- Shared WS loop in `Server/app/routers/_ws.py`:
  - subscribes to Redis pub/sub channel,
  - receives client text,
  - persists via callback,
  - republishes to channel.
- Redis pub/sub adapter: `Server/app/core/redis_pubsub.py`.
- Private chat handles offline storage (`OfflineMessage`) and later delivery via `NotificationService.send_offline_messages`.

### Client
- `PlayerHub.gd` opens WebSocket per chat channel via `ServerConfig.get_ws_endpoint(channel, token)` and polls in `_process`.
- `WebSocketManager.gd` handles auction stream on `/ws/auctions`.

### Observed mismatch
- `/ws/auctions` endpoint is referenced by client (`autoload/WebSocketManager.gd`) but not defined in server routers.

## 12) SECURITY

### Implemented controls
- JWT access/refresh tokens (`Server/app/utils/jwt.py`) with token type claims and expirations.
- Refresh token rotation family IDs generated (`create_refresh_token(... family_id=...)`).
- Password hashing via `passlib` bcrypt (`services/auth.py`).
- Cookie flags for refresh token (`httponly`, env-driven `secure`/`samesite`) in `routers/auth.py`.
- Route protection via OAuth2 bearer dependency (`app/auth/__init__.py`).
- Role checks implemented in runtime logic for some endpoints (`chat` moderation/admin checks, `get_current_user(required_role=...)`).
- Rate limits:
  - global default `10/second` (main app limiter),
  - auth endpoint limits `5/minute` (`routers/auth.py`).

### Security-relevant caveats from code
- `JWT_SECRET_KEY` default literal in `core/config.py` (`"supersecretkey"`) rather than env-only.
- In-memory active session registry (`services/session_registry.py`) is process-local and non-distributed.
- `redis_cache` implementation is currently stubbed no-op (`core/redis_cache.py` connect/get/set return no-op/None).

## 13) GAME ECONOMY

### Monetary model in code
- User has `balance` and `reserved` (`models/user.py`) with non-negative checks.
- Ledger table `currency_transactions` stores amount/type/reference/time.
- `AccountingService.adjust_balance` is used in hero generation, bidding, auction settle, autobid updates.

### Economy flows implemented
- Hero generation charges user (`hero_generation` transaction type in `HeroService.generate_and_store`).
- Bid reserve and release transactions (`bid_reserve`, `bid_release_reserved`).
- Auction close payout and reserve release (`auction_payout`, `auction_release_reserved`).
- Battle bet reservation adds `CurrencyTransaction` (`battle_bet_reserved` in `routers/battle.py`).

## 14) BACKGROUND TASKS

### Defined tasks
- `Server/app/tasks/cleanup.py`:
  - `delete_old_heroes_task()` every hour removes soft-deleted heroes older than 7 days.
  - `revive_dead_heroes_task()` every minute revives heroes after `dead_until`.
- `Server/app/tasks/auctions.py`:
  - startup one-shot sweep (`run_auction_sweep_once`),
  - recurring minute sweep (`close_expired_auctions_task`) with advisory lock.

### Started at app runtime
- `main.py` starts:
  - `delete_old_heroes_task`,
  - `close_expired_auctions_task`.
- `revive_dead_heroes_task` exists but is **not started in `main.py`**.

## 15) CODE QUALITY ANALYSIS

### Positive patterns
- Transaction boundaries and row locks are explicit in auction/bid/equipment/hero critical paths.
- Clear service/router separation and schema usage in most endpoints.
- Test suites exist on both server and client sides.

### Code-level issues observed (factual)
1. **Mounted/unmounted router divergence**: `routers/item.py` and `routers/pve.py` not included in app, yet client and code reference related paths.
2. **Client route drift**:
   - new network layer and legacy UI layer target different route conventions (`/auction` vs `/auctions`, `/inventory/equip` vs `/equipment`).
3. **WebSocket mismatch**: client `/ws/auctions` without server handler.
4. **Service/model inconsistencies**:
   - `services/pve.py` uses `RaidArenaInstance` fields (`wave`, `mobs`) not defined in model.
   - `services/raid.py` accesses `boss.loot_items` while model defines `loot_table`.
   - `EventService.schedule_events` calls `EventDefinition.has_cron_match(...)`; method not present in `models/event.py`.
5. **Cache layer inconsistency**:
   - routers/services call Redis cache interface, but `core/redis_cache.py` methods are stubs returning no cache behavior.
6. **Incomplete placeholder code**:
   - `services/actions.py` has TODO stubs for combat resolution.
7. **Syntax/format anomaly**:
   - `client/scripts/ui/scenes/Storage.gd` has a visibly mis-indented line with a leading extra space before `selected_hero_label.text`.

## 16) CURRENTLY IMPLEMENTED GAME MECHANICS

Based on code paths, the following mechanics are implemented:
- User registration/login/logout/token refresh/profile.
- Hero generation, listing, deletion/restoration, training, XP/leveling, perks upgrade.
- Item stash management, equipment equip/unequip with slot and stash mutation.
- Item auctions and hero auction lots with bid placement, auto-bid model, close/cancel flows.
- Battle queue + betting, duel/team/raid simulations.
- Crafting recipe checks, craft queue, finish craft, disenchant.
- Raid instance setup, wave generation, PvE battle log, reward drop attempt.
- PvP match creation + leaderboard updates (winner may be unresolved due simulation stub).
- Events/tournaments CRUD-like progression endpoints.
- Chat channels/history/private history plus moderation/system message endpoints.
- Server online status endpoint exposing active session count.

## 17) MISSING OR PARTIALLY IMPLEMENTED SYSTEMS

From direct code evidence:
- `services/actions.py` combat simulation stubs (TODO) make PvP outcome path partial.
- `EventDefinition` cron method (`has_cron_match`) is referenced but absent.
- `revive_dead_heroes_task` is defined but not wired in startup.
- `core/redis_cache.py` currently no-op stub while many endpoints expect caching.
- `WebSocketManager` auction channel endpoint lacks backend implementation.
- Multiple client endpoints reference non-existent or differently-shaped backend routes.
- `pve.py` router exists but not mounted.
- `item.py` router exists but not mounted.

## 18) SUGGESTED ARCHITECTURE IMPROVEMENTS

Code-grounded recommendations:
1. **Consolidate to one client networking layer** (prefer `scripts/network/*`) and remove/adapter-map `scripts/core/ApiClient.gd` route drift.
2. **Generate route contract map** from mounted FastAPI routers and validate client literals against it in CI.
3. **Either mount or remove dormant routers** (`item.py`, `pve.py`) to eliminate ambiguous API surface.
4. **Implement missing realtime channel or remove client dependency** (`/ws/auctions`).
5. **Align service-model contracts** (`RaidService` boss relation names, `PvEService` fields, event cron helper).
6. **Replace cache stubs with real Redis behavior** or remove cache calls to avoid false assumptions.
7. **Promote session/online tracking to shared store** if multi-instance deployment is expected; current registry is process-local.

## 19) SUMMARY

- The repository contains a substantial MMO-like backend/client codebase with heroes, auction, inventory/equipment, craft, battle, raid, PvP, events, tournaments, and chat.
- Core transactional logic for economy-sensitive flows is present and generally robust in auction/bid/equipment domains.
- Major onboarding risk is **contract drift** between server routes and client calls due parallel/legacy client network layers and unmounted routers.
- Real-time/chat is partially complete: chat WS channels exist; auction WS channel is client-only.
- Several subsystems are clearly partial by code (action simulation stubs, event cron helper, pve/router mounting, cache stubs), and should be treated as incomplete until aligned.

---

### Uncertainty notes
- `uncertain`: runtime usage priority between the active autoload `scripts/network/ApiClient.gd` and legacy `scripts/core/ApiClient.gd` in all scenes/modules cannot be proven statically without execution traces.
- `uncertain`: whether some inconsistent service code paths are exercised in current deployment cannot be confirmed from static code only.
