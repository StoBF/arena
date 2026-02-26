# Project Architecture (code‑base driven)

This document describes how the **current repository** is structured and how the
core subsystems are implemented.  It is **not** a set of generic guidelines – it
reflects the actual files, classes and logic that are present today and points
out shortcomings and concrete refactorings.

---
## 1. Folder layout and entry points

- `/Server/app/main.py` is the FastAPI application; routers are mounted there and
  startup/shutdown events are defined.
- The Godot client lives under `/client`.  UI panels such as `AuctionPanel.gd`
  talk to the backend via `Network.request()`.  Recent updates added an item/lot
  toggle and call the new `/auctions/lots` endpoints; the panel also adjusts
  bid URLs based on the selected mode.- `/Server/app/routers` contains HTTP and WebSocket endpoints grouped by feature
  (`hero.py`, `auction.py`, `chat.py`, etc.).  A new helper in
  `routers/_ws.py` centralises the subscribe/publish loop; `chat.py` now
  calls `websocket_loop()` and performs only per-channel persistence.  The
  WebSocket chat code no longer directly uses `redis_pubsub` everywhere.
- `/Server/app/services` hosts business‑logic classes such as
  `hero.py`, `auction.py`, `auction_lot.py`, `auth.py`.  `auction.py` now
  handles only item auctions; hero lots moved to `AuctionLotService` in
  `auction_lot.py`.  Each service takes an `AsyncSession` in its constructor and
  exposes async methods.
- `/Server/app/database/models` holds SQLAlchemy ORM definitions; heroes are in
  `hero.py` (now using `SoftDeleteMixin` from `app/database/base.py`), the bulk
  of other entities (auction, bid, item, chat message, …) are scanned from
  `models.py`.
- `/Server/app/utils/jwt.py` implements the JWT helpers used across the project.
- Background tasks live under `/Server/app/tasks` (e.g. `auctions.py`).

A full list of database tables is defined in the models files; the ones touched
by this document are summarised below.

---
## 2. Database models in use

Tables currently present (see
`/Server/app/database/models/models.py` and `hero.py`):

| Table | Description |
|-------|-------------|
| `heroes` | `Hero` entity with stats, owner_id, training/auction flags, soft‑delete
  fields, `is_dead`, `dead_until` etc. |
| `hero_perks` | `HeroPerk` join table with optional `perk_id` foreign key. |
| `items`, `stash`, `equipment` | Inventory / equipment system. |
| `auctions` | Item auctions (`Auction` model) with `start_price`, `current_price`,
  `end_time`, `status` enum (see `app/core/enums.py`). |
| `auction_lots` | Hero auction lots (`AuctionLot`). |
| `bids`, `auto_bids` | Bids for either `auctions` or `auction_lots`. |
| `chat_messages`, `offline_messages` | Chat history and undelivered DM storage. |
| plus `users`, `announcements`, `pvp_matches` etc. (other models not shown).

Constraints and relationships are declared inline; many `with_for_update`
locks in the services indicate the code’s current concurrency model.

---
## 3. Hero system implementation

The entire hero lifecycle is implemented in `/Server/app/services/hero.py`:

- `create_hero` checks the per‑user count (`MAX_HEROES` in
  `app/core/hero_config.py`) and inserts a new row.
- `get_hero` and `list_heroes` are thin wrappers over SQLAlchemy `select` with
  optional eager‑loading of `perks`/`equipment_items` to avoid lazy load
  in async contexts.
- Deletion is a **soft delete**: `delete_hero` sets `is_deleted = True` and
  records `deleted_at`.
- `restore_hero` reverses the deletion but only if `deleted_at` is within the
  last **seven days** (see line 68 of `hero.py`).  Older heroes raise 404.
- `generate_and_store` combines balance deduction (through
  `AccountingService.adjust_balance`) with hero creation inside an explicit
  transaction.  The user row is locked with `SELECT … FOR UPDATE` and the cost
  is precisely `100 × currency` (currency comes from the request).  This
  method is called from the `/heroes/generate` router.
- Training, experience gain and stat computation are also implemented here.

**Cross-cutting note:** `BidService` (the largest service at 316 lines) now
emits cache invalidation events when bids are placed.  Both item auctions and
hero lots trigger `auctions:active*` (and `auctions:active_lots*` for lot
bids), ensuring the paginated listing endpoints stay fresh without router
intervention.

### Improvement request already satisfied
> Heroes can be restored only within 7 days.  — this is exactly the behaviour
of `restore_hero` (see the `cutoff` calculation above).

---
## 4. Auction subsystem and expiration logic

Auctions (items) and lots (heroes) are handled by
`/Server/app/services/auction.py`.  Important behaviours:

1. **Creation**: `create_auction` and `create_auction_lot` both start a
   transaction (`async with self._txn():`) to remove items/heroes from the
   seller’s stash and mark the hero as `is_on_auction = True` respectively.
   The `end_time` is calculated as `datetime.utcnow() + timedelta(hours=duration)`;
   the caller provides `duration` (in hours) without validation.
2. **Listing**: `list_auctions`/`list_auction_lots` add `where … AND end_time >
   datetime.utcnow()` when `active_only` is requested, so expired rows are
   filtered but not updated.
3. **Closing**: `close_auction` and `close_auction_lot` are carefully written
   with pessimistic locks and multiple user/hero row locks.  They set
   `status = AuctionStatus.FINISHED` and transfer funds/items/heroes
   atomically.
4. **Background task**: `/Server/app/tasks/auctions.py` contains
   `close_expired_auctions_task()`.  It wakes every 60 s, selects all `ACTIVE`
   auctions whose `end_time <= now`, locks them (`skip_locked=True`), and calls
   `AuctionService.close_auction()` one by one.  The task is started in
   `main.on_startup` via `asyncio.create_task()`.

   Transactions are common across services; a helper `_txn()` was originally
   copied between `AuctionService`, `EquipmentService` and others.  This has
   been factored into `BaseService` so that every subclass inherits the
   same nested‑transaction behaviour without duplication.

### Current expiration behaviour and shortcomings

- There is **no hard limit** on the `duration` parameter; a malicious client
  could create an auction that ends far in the future.  The requirement of
  "auctions must expire after 24 hours" is therefore not enforced.
- Expired auctions are only processed by the background loop.  If the server
  is stopped for, say, 12 hours, those auctions are not closed until the first
  iteration of the loop after startup (up to one minute later).  There is no
  code in `on_startup` to immediately sweep the database.

### Required improvements

1. **Enforce 24‑hour limit**: modify `create_auction`/`create_auction_lot` to
   ignore or clamp the `duration` argument.  Example patch:
   ```python
   MAX_AUCTION_DURATION_HOURS = 24
   duration = min(duration, MAX_AUCTION_DURATION_HOURS)
   end_time = datetime.utcnow() + timedelta(hours=MAX_AUCTION_DURATION_HOURS)
   ```
   (similarly for lots).  Alternatively, drop the `duration` parameter
   entirely and always use `end_time = utcnow() + 1 day`.
2. **Process expired auctions on startup**: call the same sweep logic once from
   `main.on_startup` before starting the background task.  e.g.: 
   ```python
   async def close_all_expired():
       async with AsyncSessionLocal() as session:
           await AuctionService(session).close_expired_auctions()
   
   @app.on_event("startup")
   async def on_startup():
       await create_database_if_not_exists()
       await create_db_and_tables()
       await close_all_expired()      # new
       asyncio.create_task(delete_old_heroes_task())
       asyncio.create_task(close_expired_auctions_task())
   ```
   and extract the query from the task into `AuctionService.close_expired_auctions`.

These changes guarantee that no auction remains `ACTIVE` past 24 h and that
any gap while the server was down is repaired immediately.

---
## 5. JWT implementation used in the codebase

The file `/Server/app/utils/jwt.py` defines:

- `create_access_token(data, expires_delta)` – adds `exp` and `type: "access"` claims, signs with `settings.JWT_SECRET_KEY` and algorithm from configuration. Default lifetime is `settings.JWT_ACCESS_TOKEN_MINUTES` (20 min).
- `decode_access_token(token)` – returns the payload or `None` if verification fails or the `type` claim is not `"access"`.
- `create_refresh_token(data, family_id=None)` – similar to access but with `type: "refresh"`, a longer expiry (`settings.JWT_REFRESH_TOKEN_DAYS`), and a `family` UUID used for rotation tracking; returns `(token, family_id)`.
- `decode_refresh_token(token)` – validates `type` and returns payload or `None`.

No other helpers are present; authentication and token rotation logic lives in
`/Server/app/services/auth.py` which imports these functions (see lines 51 and
84).  Tokens carry `sub` (user id) and `role`, and the `chat.ws_*` endpoints
call `decode_access_token` manually to authenticate WebSocket query parameters.

The JWT secret is set in `app/core/config.py` via `pydantic.BaseSettings` and
is read from the environment.  Refresh‑token families are stored in the
`users.refresh_token_family` column (see `auth.py`).

---
## 6. WebSocket / chat implementation

Chat functionality is implemented entirely within
`/Server/app/routers/chat.py`.  Three endpoints are exposed:

- `/ws/general` and `/ws/trade` are broadcast channels.  Each connection:
  1. extracts `token` from `websocket.query_params`;
  2. decodes it with `decode_access_token`; rejects invalid tokens (code
     1008);
  3. subscribes to a Redis Pub/Sub channel using `subscribe_channel("general")`
     or `("trade")`; a background async task forwards any messages on the
     channel to the socket;
  4. receives text from the client, persists it in `chat_messages` table and
     publishes to Redis with `publish_message`.
- `/ws/private` handles direct messages.  On connect it adds the user to the
  `online_users` Redis set, sends undelivered messages using
  `NotificationService.send_offline_messages`, then behaves similarly to the
  public channels.  Messages contain a JSON object with `to` and `text`; if recipient is offline the message is stored in the `offline_messages` table and delivered later.  System messages are sent via the helper `send_system_message` which simply creates a background task calling `publish_message("private", …)`.

The Redis pub/sub implementation is defined under `app/core/redis_pubsub.py`; the router uses `publish_message`/`subscribe_channel` helpers directly.  There is no abstraction layer between the HTTP/WebSocket code and Redis.

History endpoints (`/chat/history`, `/chat/private-history`) perform straight SQL selects over `ChatMessage` and enforce simple role checks.  Moderators can delete messages using `/chat/message/{message_id}`.

---
## 7. Architectural weaknesses found in the current codebase

A review of the existing implementation reveals several pain points:

1. **Hard‑coded secrets**: `chat.py` previously defined
   `SECRET_KEY = "your_secret_key"` which was unused; all authentication now
   uses the central JWT helpers and configuration, so the constant has been
   removed to avoid confusion.
2. **Auction/lot logic separated**: originally all auction code lived in
   `auction.py` and handled both items and hero lots.  This led to a massive
   `AuctionService` class (>500 lines) and duplicated validation/transfer logic.
   Hero‑lot support has now been extracted to `AuctionLotService`.  `AuctionService`
   no longer exposes `create_auction_lot`, `delete_auction_lot`, or
   `close_auction_lot`; the background sweep delegates expired lots to the
   smaller `AuctionLotService` and startup performs a unified sweep.  This
   separation simplifies testing and enforces the single‑responsibility principle.
3. **No startup sweep for expired auctions/lots**: as mentioned above, the background task runs only after a delay.  Tests and logs show repeated exceptions leaking into `server.log` (see earlier grep output).  This suggests the task sometimes fails due to misconfigured models and then leaves auctions active.
4. **Large service classes**: `AuctionService` is over 500 lines long, mixing query logic, business rules, notification publishing, and transaction helpers.  It is difficult to unit‑test and reason about.  The `_txn()` helper is repeated in other services.
5. **Missing WebSocket abstraction**: each `ws_*` handler duplicates subscription/publishing code and session management; there is an opportunity to factor common behaviour into a base class or helper functions.
6. **Weak typing and shape of JSON**: some endpoints take bare primitive types (`duration: int`) without validation beyond Pydantic; the auth router mixes string user IDs and ints inconsistently.
7. **Decoupled cache invalidation via events**: services no longer
   import `redis_cache`.  Instead they emit `cache_invalidate` events through
   the new `app/core/events.py` emitter.  The cache layer subscribes and
   handles wildcards (e.g. `auctions:active*`), enabling paginated cache keys
   to be invalidated with a single event.  This reduces coupling, simplifies
   testing (handlers can record emitted keys), and prepares for possible future
   swaps of the caching backend.
8. **Thread‑safety and startup ordering**: background tasks were previously started unawaited and any uncaught exception would log an error but otherwise kill the task silently.  The `close_expired_auctions_task` now wraps its loop in a try/except block and sleeps briefly on failure, ensuring the worker remains alive even if a transient database error occurs.  Startup logic also now forces an initial sweep of expired auctions so outages don't leave auctions active.
9. **Hero soft‑delete special case**: deleted heroes remain in the same table and many queries must explicitly filter `is_deleted == False`; a single `get_hero` call defaults to `only_active=True`, but there is no global query filter, leading to repeated where clauses.  The mixin used to attach a `before_compile` event to each mapped class, but SQLAlchemy doesn't support that event on arbitrary targets; it has been replaced by a global listener on `Query` which inspects the entities and adds the filter.
10. **Empty `MessageService`**: the placeholder class is imported by `HeroService` but never implemented; indicates incomplete code and inconsistent dependency graphs.

---
## 8. Concrete refactoring recommendations

To address the weaknesses above and make the architecture more maintainable,
apply the following specific changes:

1. **Unify auction/lot logic**
   - Extract common behaviours (`_close`, `_transfer_funds`, `_notify`) into
     a base class or module.  Introduce an enum or strategy object so that
     `Auction` and `AuctionLot` share code instead of duplicating it.
   - Add `AuctionService.close_expired_lots()` and update the task to sweep
     both tables.  Rename task to `close_expired_auctions_and_lots_task`.
2. **Startup sweep**: implement `AuctionService.close_all_expired()` and invoke
   it synchronously in `main.on_startup` before background tasks start.
3. **Remove hard‑coded chat secret**: delete the unused constant and move
   WebSocket token decoding to a shared helper (e.g. `app.auth.websocket_user`).
4. **Factor WebSocket boilerplate**: create a helper in `app/routers/_ws.py` that
   encapsulates the subscribe/publish loop and error handling; each handler then
   needs only to supply channel names and a storage callback.
5. **Introduce domain events or pub/sub wrapper**: instead of calling
   `redis_cache.delete` from services, emit an event (e.g. `CacheInvalidation`
   dataclass) and handle it in a separate layer; makes testing easier.
6. **Add SQLAlchemy query filters**: configure a `Base` query property or use
   `__mapper_args__ = {'always_refresh': True}` with a default filter for
   `is_deleted` to avoid forgetting the clause.  Alternatively move soft delete
   handling into a mixin.
7. **Split `AuctionService`**: break it into `AuctionService` and
   `AuctionLotService` (or `HeroAuctionService`) each <250 lines.  Move
   transaction helper `_txn()` into a shared `ServiceBase` class used by all
   services (already exists but could expose the helper there).
8. **Implement `MessageService` or remove import**: decide whether chat logic
   belongs in a service and finish the implementation; currently the import in
   `HeroService.send_offline_messages` is unnecessary and circular.
9. **Add thorough type hints and Pydantic models**: use request/response models
   everywhere instead of raw ints and strings in routers (`duration: int` →
   `AuctionCreateRequest` with validators).  This will prevent invalid JSON
   and allow automatic documentation to show the 24‑hour rule.
10. **Improve background task resilience**: wrap the body of each loop in a
    try/except that logs and either exits or back‑off properly.  In `main.on_startup`
    store the task objects and monitor them; possibly use `asyncio.create_task`
    helper wrappers that restart on failure.
11. **Remove dead code**: the global `SECRET_KEY` and the empty
    `MessageService` class should be deleted to reduce confusion.

---
## 9. Additional notes

- **WebSocket chat** is the only real-time component; there is no other use of
  WebSockets or async Data APIs.  All other endpoints are ordinary REST.
- **Hero generation** relies on a separate module
  `app/services/hero_generation.py` which returns an object with the computed
  stats.  That module can be tested independently of the service above.
- **JWT tokens** are stored nowhere except the client; the server only tests
  them on each request and when WebSocket clients connect.

By basing this document strictly on the current codebase and by proposing the
changes listed, developers can carry out targeted refactors and ensure the
system meets the additional requirements (24‑h auction lifetime, startup
processing, clearly documented hero restore window).  The architecture will
still be FastAPI + PostgreSQL + Redis + JWT, but the modules will be cleaner and
safer to evolve.
