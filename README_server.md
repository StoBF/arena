# Arena Server Architecture (FastAPI)

## High-Level Architecture Overview

The Arena server is a FastAPI-based REST API backend that manages user authentication, hero lifecycle, item management, and auction mechanics for a multiplayer hero management game. It uses PostgreSQL as the primary database with SQLite for testing, Redis for caching, and async SQLAlchemy for database operations.

### Architecture Layers

```
┌─────────────────────────────────────────────────────────────┐
│  HTTP API Layer (FastAPI)                                   │
│  - Route handlers, request validation, response models       │
│  - 18+ routers: auth, hero, auction, bid, equipment, etc.   │
│  - Rate limiting, CORS middleware, exception handling        │
└─────────────────────────────────────────────────────────────┘
                           ▼
┌─────────────────────────────────────────────────────────────┐
│  Business Logic Layer (Services)                            │
│  - AuthService, HeroService, AuctionService, BidService     │
│  - Hero generation, stat calculation, validation logic       │
│  - Auction expiration, winner determination                  │
└─────────────────────────────────────────────────────────────┘
                           ▼
┌─────────────────────────────────────────────────────────────┐
│  Cache Layer (Redis)                                        │
│  - Heroes list cache (60s TTL)                              │
│  - Auctions list cache (30s TTL)                            │
│  - Pub/Sub for real-time notifications                      │
└─────────────────────────────────────────────────────────────┘
                           ▼
┌─────────────────────────────────────────────────────────────┐
│  Data Access Layer (SQLAlchemy ORM)                         │
│  - Async session management                                 │
│  - Model relationships & constraints                        │
│  - Transaction handling                                     │
└─────────────────────────────────────────────────────────────┘
                           ▼
┌─────────────────────────────────────────────────────────────┐
│  Database Layer (PostgreSQL / SQLite)                       │
│  - User, Hero, Item, Stash, Auction, Bid tables             │
│  - Equipment, Announcement, Event tables                    │
│  - Relations & foreign keys                                 │
└─────────────────────────────────────────────────────────────┘
                           ▼
┌─────────────────────────────────────────────────────────────┐
│  Background Tasks (AsyncIO)                                 │
│  - delete_old_heroes_task() every 3600s                     │
│  - close_expired_auctions_task() every 60s                  │
│  - revive_dead_heroes_task() every 60s                      │
└─────────────────────────────────────────────────────────────┘
```

## FastAPI Routers & Endpoints

### Router Organization

| Router Module | Prefix | Endpoints | Purpose |
|---------------|--------|-----------|---------|
| `auth.py` | `/auth` | register, login, refresh | User authentication |
| `hero.py` | `/heroes` | list, create, get, update, delete, restore | Hero CRUD |
| `auction.py` | `/auctions` | create, list, get, cancel, close, lots | Item & hero auctions |
| `bid.py` | `/bids` | place_bid, list, get, delete, autobid | Bidding system |
| `inventory.py` | `/inventory` | CRUD stash items | Item management |
| `equipment.py` | `/equipment` | equip, unequip, list | Hero gear |
| `announcement.py` | `/announcements` | server-wide messages | System messages |
| `chat.py` | `/chat` | messages, channels, WebSocket | Team communication |
| `item.py` | `/items` | admin CRUD | Item definitions |
| `craft.py` | `/craft` | recipes, crafting | Crafting system |
| `raid.py` | `/raid` | raid matchmaking | Cooperative battles |
| `pvp.py` | `/pvp` | matchmaking, battles | Player vs player |
| `tournaments.py` | `/tournaments` | brackets, registration | Tournament system |
| `events.py` | `/events` | active events | Time-limited events |
| `health.py` | `/health` | ping, status | Healthcheck |

### Authentication Endpoints

```
POST /auth/register
├─ Input: {email, username, password}
├─ Output: {id, email, username}
└─ Validation: email unique, password min 6 chars

POST /auth/login
├─ Input: {login (email/username), password}
├─ Output: {access_token, refresh_token, token_type}
└─ Flow: Verify password → Generate JWT → Return tokens

POST /auth/refresh
├─ Input: {refresh_token}
├─ Output: {access_token, token_type}
└─ Validation: Token must have type="refresh"

POST /auth/google-login
├─ Input: {google_token}
├─ Output: {access_token, refresh_token, token_type}
├─ Auto-registers if new user
└─ Rate limited: 5/minute
```

### Hero Management Endpoints

```
GET /heroes
├─ Returns: List[HeroRead]
├─ Cache: heroes:{user_id} (60s TTL)
└─ Query: current_user_id

GET /heroes/{hero_id}
├─ Returns: HeroRead
├─ Validation: Hero owned by user
└─ Eager loads: perks, equipment_items

POST /heroes/generate
├─ Input: {generation, currency, locale}
├─ Process: Check hero count < MAX_HEROES
│   → generate_hero() RNG stat generation
│   → Create Hero record
│   → Deduct currency from user balance
├─ Returns: HeroRead
└─ Rate limited: 5/minute

POST /heroes/{hero_id}/delete
├─ Logic: Soft delete (is_deleted=true, deleted_at=now)
├─ Retention: 7 days before hard delete
├─ Validation: User owns hero, hero not on auction
└─ Background task: Hard delete after 7 days

POST /heroes/{hero_id}/restore
├─ Logic: Unset is_deleted, clear deleted_at
├─ Validation: Hero deleted < 7 days ago
└─ Returns: HeroRead
```

### Auction System Endpoints

#### Item Auctions

```
POST /auctions
├─ Input: {item_id, start_price, duration, quantity}
├─ Validation:
│   ├─ User owns item via Stash (quantity >= requested)
│   ├─ Remove from stash (or reduce quantity)
│   └─ Create Auction record
├─ Returns: AuctionOut
└─ Cache: Delete auctions:active

GET /auctions
├─ Returns: List[AuctionOut]
├─ Filter: status="active" AND end_time > now()
├─ Cache: auctions:active (30s TTL)
├─ Eager load: bids relationship
└─ Response: [{id, item_id, current_price, bids}, ...]

POST /auctions/{auction_id}/cancel
├─ Validation:
│   ├─ User is seller
│   ├─ Status="active" AND not ended
│   └─ No bids placed (current_price == start_price)
├─ Logic: Set status="canceled"
│   → Return item to seller's stash
├─ Returns: AuctionOut
└─ Cache: Invalidate auctions:active
```

#### Hero Auctions (AuctionLot)

```
POST /auctions/lots
├─ Input: {hero_id, starting_price, duration, buyout_price}
├─ Validation:
│   ├─ Hero not already on active lot
│   ├─ Hero: not dead, not training, no equipment
│   └─ User owns hero
├─ Logic:
│   ├─ Set hero.is_on_auction = true
│   ├─ Create AuctionLot record
│   └─ end_time = now + duration hours
├─ Returns: AuctionLotOut
└─ Cache: Invalidate auctions:active

POST /auctions/lots/{lot_id}/close
├─ Logic:
│   ├─ Determine highest bidder
│   ├─ Transfer hero to winner (update hero.owner_id)
│   ├─ Move balance from winner.reserved to seller.balance
│   └─ Set is_active=0
├─ Edge case: No bids → Return hero to seller
└─ Pub/Sub: Notify winner & seller via Redis
```

### Bidding Endpoints

```
POST /bids
├─ Input: {auction_id OR lot_id, amount}
├─ Route branching:
│   ├─ lot_id → BidService.place_lot_bid()
│   └─ auction_id → BidService.place_bid()
├─ Validation: User has sufficient balance
└─ Returns: BidOut

POST /bids/autobid
├─ Input: {auction_id OR lot_id, max_amount}
├─ Logic: Create AutoBid record
│   → Auto-place bids up to max_amount if outbid
├─ Returns: AutoBidOut
```

## Request/Response Flow Diagrams

### Authentication Flow (Login)

```
Client: POST /auth/login {login, password}
    ▼
Router: @app.post("/login")
    ├─ Request validation (Pydantic UserLogin)
    │
    ├─ AuthService.authenticate_user()
    │   ├─ Query: SELECT * FROM users WHERE email=login OR username=login
    │   ├─ pwd_context.verify(password, hashed_password)
    │   └─ Return User object or None
    │
    ├─ If auth fails: HTTPException(401, "Invalid credentials")
    │
    └─ If auth succeeds:
        ├─ AuthService.generate_tokens(user)
        │   ├─ create_access_token({sub: user.id, role: user.role, exp: now+60min})
        │   ├─ create_refresh_token({sub: user.id, role: user.role, exp: now+7days, type: refresh})
        │   └─ jwt.encode() with HS256
        │
        └─ Return {access_token, refresh_token, token_type: "bearer"}

Client receives tokens ──► AppState.token = access_token
                          ──► Save refresh_token (client-side, NOT shown here)
                          ──► Network.set_auth_header("Bearer {token}")
```

### Hero Retrieval (With Cache)

```
Client: GET /heroes (with Authorization header)
    ▼
Router: @app.get("/heroes")
    ├─ Depends(get_current_user_info) → Verify JWT
    │   ├─ decode_access_token(token)
    │   ├─ Check exp < now?
    │   └─ Extract user_id, role from payload
    │
    ├─ Check Redis cache: heroes:{user_id}
    │   │
    │   ├─ CACHE HIT:
    │   │   └─ Return cached list (fast path ~1ms)
    │   │
    │   └─ CACHE MISS:
    │       ├─ Query database:
    │       │   SELECT * FROM heroes
    │       │   WHERE owner_id=user_id AND is_deleted=False
    │       │   LEFT JOIN hero_perks
    │       │   LEFT JOIN equipment
    │       │
    │       ├─ Process results into HeroRead[] schema
    │       │   └─ Serialize relationships
    │       │
    │       ├─ Store in Redis: SET heroes:{user_id} <json> EX 60
    │       │   └─ 60-second expiration
    │       │
    │       └─ Return serialized heroes
    │
    └─ Response: 200 OK [HeroRead, ...]
```

### Auction Closure with Transaction

```
Task (every 60 sec): close_expired_auctions_task()
    ▼
Query: SELECT * FROM auctions 
       WHERE status="active" AND end_time <= NOW()
    ▼
For each auction:
    │
    ├─ BEGIN TRANSACTION
    │   │
    │   ├─ SELECT * FROM bids WHERE auction_id=? ORDER BY amount DESC LIMIT 1 (FOR UPDATE)
    │   │   └─ Lock bid row if it exists
    │   │
    │   ├─ If highest_bid exists:
    │   │   │
    │   │   ├─ winner_id = highest_bid.bidder_id
    │   │   │
    │   │   ├─ UPDATE users SET reserved -= bid.amount WHERE id=winner_id
    │   │   ├─ UPDATE users SET balance += bid.amount WHERE id=seller_id
    │   │   │
    │   │   ├─ UPDATE stash SET quantity += auction.quantity 
    │   │   │   WHERE user_id=winner_id AND item_id=auction.item_id
    │   │   │   (INSERT if not exists)
    │   │   │
    │   │   ├─ Pub/Sub: publish_message("private", 
    │   │   │   {type: "system", text: "You won auction!"}, winner_id)
    │   │   │
    │   │   └─ Pub/Sub: publish_message("private",
    │   │       {type: "system", text: "Your item sold!"}, seller_id)
    │   │
    │   └─ Else (no bids):
    │       ├─ Return item to seller stash
    │       └─ Pub/Sub: Notify seller
    │
    │   ├─ UPDATE auctions SET status="closed" WHERE id=?
    │   │
    │   └─ COMMIT TRANSACTION
    │
    └─ redis_cache.delete("auctions:active")
```

### Hero Generation (Expensive Operation)

```
Client: POST /heroes/generate {generation, currency, locale}
    ▼
Router: generate_and_store(owner_id, request)
    ├─ Validation:
    │   ├─ User hero count < MAX_HEROES
    │   └─ Check currency cost
    │
    ├─ HeroService.generate_and_store()
    │   │
    │   ├─ async generate_hero(session, owner_id, generation, currency, locale)
    │   │   │
    │   │   ├─ Load generation config (stat ranges, perk pools)
    │   │   │
    │   │   ├─ For each stat attribute:
    │   │   │   └─ RNG: base_stat + random(0, generation * 2)
    │   │   │   └─ strength, agility, intelligence, etc.
    │   │   │
    │   │   ├─ Select random perks from pool
    │   │   │   └─ Assign perk_level based on RNG
    │   │   │
    │   │   ├─ Calculate nickname based on highest stat
    │   │   │   └─ if strength > others → "the Strong"
    │   │   │
    │   │   └─ Return hero_data object
    │   │
    │   ├─ Create Hero record:
    │   │   ├── INSERT INTO heroes (name, owner_id, strength, agility, ..., is_deleted=False)
    │   │   └── Store perks in hero_perks (cascade)
    │   │
    │   └─ COMMIT & REFRESH
    │
    ├─ Deduct currency from user.balance
    │   └─ UPDATE users SET balance -= cost WHERE id=owner_id
    │
    └─ Return HeroRead (200 Created)
```

### Bid Placement with Concurrency Control

```
Client: POST /bids {auction_id, amount}
    ▼
Router: place_bid(bidder_id, auction_id, amount)
    ├─ Validation:
    │   ├─ Auction exists AND status="active" AND end_time > now()
    │   ├─ Bidder ≠ seller
    │   └─ amount > current_price
    │
    ├─ BEGIN TRANSACTION
    │   │
    │   ├─ SELECT * FROM users WHERE id=bidder_id FOR UPDATE
    │   │   └─ Lock user row to prevent race condition
    │   │
    │   ├─ Validate: balance - reserved >= amount
    │   │   └─ If insufficient: ROLLBACK, HTTPException(400)
    │   │
    │   ├─ Get previous high bidder (if exists):
    │   │   ├─ SELECT * FROM bids WHERE auction_id=? 
    │   │   │   ORDER BY amount DESC LIMIT 1
    │   │   └─ If prev_bidder != current_bidder:
    │   │       └─ UPDATE users SET reserved -= prev_bid.amount 
    │   │           WHERE id=prev_bidder
    │   │
    │   ├─ Update current bidder:
    │   │   └─ UPDATE users SET reserved += amount WHERE id=bidder_id
    │   │
    │   ├─ Create new bid:
    │   │   └─ INSERT INTO bids (auction_id, bidder_id, amount, created_at)
    │   │
    │   ├─ Update auction:
    │   │   ├─ UPDATE auctions SET current_price = amount, winner_id = bidder_id
    │   │   └─ WHERE id=auction_id
    │   │
    │   └─ COMMIT TRANSACTION
    │
    └─ Return BidOut (200)
```

## Database Schema & Relationships

### Core Models

#### User

```sql
TABLE users (
    id INTEGER PRIMARY KEY,
    email VARCHAR UNIQUE NOT NULL,
    username VARCHAR UNIQUE,
    hashed_password VARCHAR,
    is_active BOOLEAN DEFAULT TRUE,
    is_google_account BOOLEAN DEFAULT FALSE,
    balance DECIMAL(12,2) DEFAULT 0,          -- Available funds
    reserved DECIMAL(12,2) DEFAULT 0,         -- Funds locked in bids
    role VARCHAR DEFAULT "user",              -- user, admin, moderator
    created_at TIMESTAMP DEFAULT NOW()
);

-- Relationships:
-- User --1:N--> Hero (owner_id)
-- User --1:N--> Stash (user_id)
-- User --1:N--> Auction (seller_id, winner_id)
-- User --1:N--> Bid (bidder_id)
```

#### Hero

```sql
TABLE heroes (
    id INTEGER PRIMARY KEY,
    owner_id INTEGER FOREIGN KEY --> users.id,
    name VARCHAR(100) NOT NULL,
    generation INTEGER DEFAULT 1,
    nickname VARCHAR(100),
    strength INTEGER DEFAULT 0,        -- Combat attribute
    agility INTEGER DEFAULT 0,         -- Evasion
    intelligence INTEGER DEFAULT 0,    -- Magic/utility
    endurance INTEGER DEFAULT 0,       -- Stamina/resistance
    speed INTEGER DEFAULT 0,           -- Turn order
    health INTEGER DEFAULT 0,          -- HP
    defense INTEGER DEFAULT 0,         -- Damage reduction
    luck INTEGER DEFAULT 0,            -- Crit/dodge chance
    field_of_view INTEGER DEFAULT 0,   -- Visibility range
    gold INTEGER DEFAULT 0,            -- Loot currency
    level INTEGER DEFAULT 1,
    experience INTEGER DEFAULT 0,
    is_training BOOLEAN DEFAULT FALSE,
    training_end_time DATETIME,
    is_dead BOOLEAN DEFAULT FALSE,
    dead_until DATETIME,
    is_on_auction BOOLEAN DEFAULT FALSE,
    is_deleted BOOLEAN DEFAULT FALSE,  -- Soft delete
    deleted_at DATETIME,
    locale VARCHAR(5) DEFAULT "en",
    created_at TIMESTAMP DEFAULT NOW()
);

INDEX: (owner_id, is_deleted)  -- Fast hero list queries
INDEX: (is_on_auction)
INDEX: (is_deleted, deleted_at)  -- Cleanup task

-- Relationships:
-- Hero --1:N--> HeroPerk (hero_id, cascade delete)
-- Hero --1:N--> Equipment (hero_id, cascade delete)
-- Hero --1:N--> AuctionLot (hero_id)
```

#### Item & Stash

```sql
TABLE items (
    id INTEGER PRIMARY KEY,
    name VARCHAR NOT NULL,
    description TEXT,
    type ENUM(equipment, artifact, resource, material, consumable, weapon, armor, helmet),
    bonus_strength INTEGER DEFAULT 0,   -- Equipment stat bonuses
    bonus_agility INTEGER DEFAULT 0,
    bonus_intelligence INTEGER DEFAULT 0,
    bonus_endurance INTEGER DEFAULT 0,
    bonus_speed INTEGER DEFAULT 0,
    bonus_health INTEGER DEFAULT 0,
    bonus_defense INTEGER DEFAULT 0,
    bonus_luck INTEGER DEFAULT 0,
    slot_type VARCHAR(32),              -- weapon, helmet, armor, etc.
    created_at TIMESTAMP DEFAULT NOW()
);

TABLE stash (
    id INTEGER PRIMARY KEY,
    user_id INTEGER FOREIGN KEY --> users.id,
    item_id INTEGER FOREIGN KEY --> items.id,
    quantity INTEGER DEFAULT 1,
    UNIQUE(user_id, item_id)            -- One entry per item per user
);

INDEX: (user_id)  -- User inventory lookups
```

#### Auction & Bid

```sql
TABLE auctions (
    id INTEGER PRIMARY KEY,
    item_id INTEGER FOREIGN KEY --> items.id,
    seller_id INTEGER FOREIGN KEY --> users.id,
    start_price INTEGER NOT NULL,
    current_price INTEGER NOT NULL,
    end_time DATETIME NOT NULL,
    winner_id INTEGER FOREIGN KEY --> users.id (nullable),
    quantity INTEGER DEFAULT 1,         -- Number of items in lot
    status VARCHAR(20) DEFAULT "active", -- active, closed, canceled
    created_at TIMESTAMP DEFAULT NOW()
);

INDEX: (status, end_time)  -- Closure task queries
INDEX: (seller_id)         -- User's auctions

TABLE bids (
    id INTEGER PRIMARY KEY,
    auction_id INTEGER FOREIGN KEY --> auctions.id (nullable),
    lot_id INTEGER FOREIGN KEY --> auction_lots.id (nullable),
    bidder_id INTEGER FOREIGN KEY --> users.id,
    amount INTEGER NOT NULL,
    created_at TIMESTAMP DEFAULT NOW()
);

INDEX: (auction_id, amount DESC)  -- Find highest bid
INDEX: (bidder_id)                -- User's bids
```

#### AuctionLot (Hero Auction)

```sql
TABLE auction_lots (
    id INTEGER PRIMARY KEY,
    hero_id INTEGER FOREIGN KEY --> heroes.id UNIQUE,  -- One lot per hero
    seller_id INTEGER FOREIGN KEY --> users.id,
    starting_price INTEGER NOT NULL,
    current_price INTEGER NOT NULL,
    buyout_price INTEGER,               -- Fixed-price option
    end_time DATETIME NOT NULL,
    winner_id INTEGER FOREIGN KEY --> users.id (nullable),
    is_active INTEGER DEFAULT 1,        -- 1=active, 0=closed
    created_at TIMESTAMP DEFAULT NOW()
);

INDEX: (is_active, end_time)  -- Closure task
INDEX: (seller_id)            -- Seller's lots
```

#### Equipment

```sql
TABLE equipment (
    id INTEGER PRIMARY KEY,
    hero_id INTEGER FOREIGN KEY --> heroes.id,
    item_id INTEGER FOREIGN KEY --> items.id,
    slot VARCHAR NOT NULL,              -- weapon, helmet, armor, etc.
    UNIQUE(hero_id, slot)               -- One item per slot per hero
);

-- Relationships:
-- Equipment.item --M:1--> Item
-- Equipment.hero --M:1--> Hero
```

## JWT Authentication Flow

### Token Structure

#### Access Token (15-60 min TTL)

```json
{
  "sub": "1",                 // User ID (string)
  "role": "user",            // user, admin, moderator
  "exp": 1708790400,         // Expiration Unix timestamp
  "iat": 1708789800,         // Issued at
  "iss": "arena"             // Issuer (optional)
}
```

Encoded with HS256 (HMAC-SHA256):
```
eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxIiwicm9sZSI6InVzZXIiLCJleHAiOjE3MDg3OTA0MDB9.signature
```

#### Refresh Token (7 day TTL)

```json
{
  "sub": "1",
  "role": "user",
  "type": "refresh",         // Distinguishes from access token
  "exp": 1709395200,         // 7 days from issue
  "iat": 1708790400
}
```

### Token Validation (get_current_user_info)

```python
async def get_current_user_info(token: str = Depends(oauth2_scheme)):
    # Extract token from "Authorization: Bearer <token>"
    payload = decode_access_token(token)
    
    if not payload or "sub" not in payload or "role" not in payload:
        raise HTTPException(status_code=401, detail="Invalid token")
    
    user_id = int(payload["sub"])
    role = payload["role"]
    
    return {"user_id": user_id, "role": role}
```

### Role-Based Access Control (RBAC)

```python
async def get_current_user(
    required_role: str = "user",
    token: str = Depends(oauth2_scheme),
    session: AsyncSession = Depends(get_session),
):
    """Full user object from DB with role checking."""
    payload = decode_access_token(token)
    
    if payload.get("role") == "admin":
        pass  # Admin has all permissions
    elif payload.get("role") == "moderator" and required_role != "admin":
        pass  # Moderator has moderator + user permissions
    elif required_role != "user":
        raise HTTPException(status_code=403, detail="Insufficient privileges")
    
    # Fetch full user object for downstream logic
    user = await session.execute(
        select(User).where(User.id == user_id)
    )
    return user.scalars().first()
```

## Background Tasks & Lifecycle

### Task 1: delete_old_heroes_task() [Every 1 hour]

```python
while True:
    await asyncio.sleep(3600)  # 3600 seconds
    
    cutoff = datetime.utcnow() - timedelta(days=7)
    
    # Find heroes deleted > 7 days ago
    old_heroes = select(Hero).where(
        Hero.is_deleted == True,
        Hero.deleted_at < cutoff
    )
    
    # Hard delete from database
    for hero in old_heroes:
        await session.delete(hero)  # Cascade deletes equipment, perks
    
    await session.commit()
```

**Purpose**: Clean up soft-deleted heroes after retention period

**Cascade Effects**:
- CASCADE DELETE on hero_perks
- CASCADE DELETE on equipment
- Frees row locks

### Task 2: close_expired_auctions_task() [Every 60 seconds]

```python
while True:
    await asyncio.sleep(60)
    
    now = datetime.utcnow()
    
    # Find expired active auctions
    expired = select(Auction).where(
        Auction.status == "active",
        Auction.end_time <= now
    )
    
    for auction in expired:
        await AuctionService(session).close_auction(auction.id)
        
        # Notify participants via Redis Pub/Sub
        if auction.winner_id:
            publish_message("private", 
                {type: "system", text: f"You won! Price: {auction.current_price}"},
                auction.winner_id)
```

**Purpose**: Auto-close auctions, determine winners, transfer items/funds

**Critical**: No optimistic locking → RACE CONDITION (see risks)

### Task 3: revive_dead_heroes_task() [Every 60 seconds]

```python
while True:
    await asyncio.sleep(60)
    
    now = datetime.utcnow()
    
    # Find heroes whose death timer expired
    to_revive = select(Hero).where(
        Hero.is_dead == True,
        Hero.dead_until != None,
        Hero.dead_until <= now
    )
    
    for hero in to_revive:
        hero.is_dead = False
        hero.dead_until = None
    
    await session.commit()
```

**Purpose**: Auto-revive dead heroes after cooldown period

## Startup & Initialization

```python
@app.on_event("startup")
async def on_startup():
    # 1. Create database if not exists (PostgreSQL only)
    await create_database_if_not_exists()
    
    # 2. Create tables from SQLAlchemy metadata
    await create_db_and_tables()
    
    # 3. Start background tasks
    asyncio.create_task(delete_old_heroes_task())
    asyncio.create_task(close_expired_auctions_task())
    asyncio.create_task(revive_dead_heroes_task())
```

## Known Technical Risks & Issues

### 1. **Race Condition: Concurrent Auction Closures (HIGH SEVERITY)**

**Problem**: Two workers process same expired auction simultaneously.

**Scenario**:
```
Worker 1: SELECT * FROM auctions WHERE id=5
          (Gets auction, begins transaction)
Worker 2: SELECT * FROM auctions WHERE id=5
          (Gets auction, begins transaction)
Worker 1: UPDATE auctions SET status="closed" WHERE id=5
          (Closes auction, transfers item)
Worker 2: UPDATE auctions SET status="closed" WHERE id=5
          (Closes same auction again!)
          └─ Item transferred twice to two users
```

**Root Cause**: `close_expired_auctions_task()` has no record lock during closure.

**Impact**:
- Item duplicated (financial loss)
- Winner ID overwritten multiple times
- Funds transferred incorrectly

**Current Code**:
```python
result = await session.execute(
    select(Auction).where(Auction.status == "active", Auction.end_time <= now)
)
expired_auctions = result.scalars().all()  # No FOR UPDATE lock!
```

**Fix**:
```python
result = await session.execute(
    select(Auction)
    .where(Auction.status == "active", Auction.end_time <= now)
    .with_for_update()  # Pessimistic lock!
)
# Now only one worker can process each auction
```

### 2. **Auction Closure + Hero Deletion Race (MEDIUM SEVERITY)**

**Scenario**:
1. Hero put on auction lot (is_on_auction=true)
2. User deletes hero in another tab (is_deleted=true)
3. Auction closure tries to transfer deleted hero

**Impact**: Auction winner receives deleted hero or error

**Fix**:
```python
async def close_auction_lot(self, lot_id: int):
    lot = await self.session.get(AuctionLot, lot_id, with_for_update=True)
    hero = await self.session.get(Hero, lot.hero_id, with_for_update=True)
    
    if hero.is_deleted:
        raise HTTPException(400, "Hero was deleted")  # Refund bids
    
    # Safe to proceed
    hero.owner_id = lot.winner_id
    await self.session.commit()
```

### 3. **Cache Invalidation Race (MEDIUM SEVERITY)**

**Problem**: Redis cache delete doesn't guarantee immediate consistency.

**Scenario**:
```
Thread A: Place bid → UPDATE auction → redis_cache.delete("auctions:active")
Thread B: Simultaneously GET /auctions (cache hit, stale data)
          → Returns old auction state (before bid update)
```

**Root Cause**: Cache deletion is async, slow to propagate.

**Current Code**:
```python
# Place bid
await self.session.commit()
await redis_cache.delete("auctions:active")  # May not delete immediately!
```

**Fix**:
```python
# Use versioned cache keys
cache_version = int(time.time() / 60)  # Changes every minute
cache_key = f"auctions:active:v{cache_version}"

# Or use shorter TTL
await redis_cache.set("auctions:active", data, expire=15)  # 15-second expiration
```

### 4. **No Pagination on Large Lists (MEDIUM SEVERITY)**

**Problem**: `/heroes` and `/auctions` endpoints return entire list.

**Scenario**: User with 10,000 heroes → JSON payload 50+ MB → OOM

**Current Code**:
```python
heroes = await HeroService(db).list_heroes(user['user_id'])
return heroes  # No limit!
```

**Fix**:
```python
@router.get("/heroes")
async def read_heroes(
    limit: int = Query(20, ge=1, le=100),
    offset: int = Query(0, ge=0),
    db: AsyncSession = Depends(get_session),
    user=Depends(get_current_user_info)
):
    # Fetch with LIMIT/OFFSET
    query = select(Hero).where(
        Hero.owner_id == user['user_id'],
        Hero.is_deleted == False
    ).limit(limit).offset(offset)
    
    heroes = await db.execute(query)
    return heroes.scalars().all()
```

### 5. **Bid Service Field Inconsistency (LOW SEVERITY)**

**Problem**: Different field names across bid model and service.

**In models.py**:
```python
class Bid(Base):
    amount = Column(Integer)  # Field name
```

**In bid.py**:
```python
bid = Bid(lot_id=lot_id, bidder_id=bidder_id, bid_amount=bid_amount)
                                         ^^^ Wrong field name!
```

**Impact**: Silent failure, bid not created

**Fix**: Use consistent `amount` field everywhere.

### 6. **No Request Idempotency (MEDIUM SEVERITY)**

**Problem**: Network retry without idempotency key.

**Scenario**:
1. Client places bid
2. Server processes ✓ (bid created, amount reserved)
3. Response timeout (client doesn't receive)
4. Client retries
5. Server processes again → Duplicate bid!

**Impact**: Double-charging users, inconsistent bid history

**Current Code**:
```python
# No idempotency key check
bid = Bid(auction_id=auction_id, bidder_id=bidder_id, amount=amount)
self.session.add(bid)
await self.session.commit()
```

**Fix**:
```python
# Use natural unique constraint or explicit key
@router.post("/bids")
async def place_bid(
    data: BidCreate,
    idempotency_key: str = Header(None),
    db: AsyncSession = Depends(get_session),
):
    if idempotency_key:
        # Check cache: "idempotency:{idempotency_key}"
        cached_result = await redis_cache.get(f"idempotency:{idempotency_key}")
        if cached_result:
            return cached_result  # Return cached result
    
    bid = await service.place_bid(...)
    
    if idempotency_key:
        await redis_cache.set(f"idempotency:{idempotency_key}", bid.dict(), expire=3600)
    
    return bid
```

### 7. **No Database Indexes on Join Columns (MEDIUM SEVERITY)**

**Problem**: Foreign keys define relationships but lack query indexes.

**Slow Queries**:
```sql
-- These queries become full table scans!
SELECT * FROM heroes WHERE owner_id = 1;
SELECT * FROM auction_lots WHERE seller_id = 1 AND is_active = 1;
```

**Current Models**:
```python
class Hero(Base):
    owner_id = Column(Integer, ForeignKey("users.id"))  # No index!
```

**Fix**:
```python
class Hero(Base):
    owner_id = Column(Integer, ForeignKey("users.id"), index=True)
    
# In models with compound criteria:
__table_args__ = (
    Index('ix_heroes_owner_deleted', 'owner_id', 'is_deleted'),
    Index('ix_auction_lots_active', 'is_active', 'end_time'),
)
```

### 8. **Refresh Token Exposed to Client-Side XSS (HIGH SEVERITY)**

**Risk**: If refresh token stored in browser localStorage/sessionStorage, XSS can steal it.

**Current Practice** (implied):
```javascript
// UNSAFE - if client stores here
localStorage.setItem("refresh_token", response.refresh_token)
```

**Recommendation**:
- Store refresh token in HTTP-only, Secure cookie
- Set SameSite=Strict to prevent CSRF
- Access token can be in memory

### 9. **No Rate Limiting on Critical Endpoints (MEDIUM SEVERITY)**

**Current**: Some endpoints rate limited (auth 5/min), others unrestricted.

**Attack**: User can spam `/heroes/generate` → DOS

**Fix**:
```python
@router.post("/heroes/generate")
@limiter.limit("1/minute")  # One hero per minute
async def generate_hero(...):
    ...
```

### 10. **Soft Delete Not Enforced in All Queries (MEDIUM SEVERITY)**

**Problem**: Some queries forget to filter `is_deleted=False`.

**Example Vulnerability**:
```python
# AuctionService.list_auctions() includes deleted heroes!
heroes = await session.execute(select(Hero))  # Oops, no WHERE is_deleted=False
```

**Fix**: Create base query helper:
```python
def _active_heroes_query(self):
    return select(Hero).where(Hero.is_deleted == False)

# Use everywhere
heroes = await self.session.execute(self._active_heroes_query())
```

## Recommended Improvements

### Immediate (1-2 weeks)

1. **Add FOR UPDATE Locks to Auctions**
   ```python
   select(Auction).where(...).with_for_update()
   ```
   Priority: **CRITICAL** (prevents item duplication)

2. **Implement Pagination with LIMIT/OFFSET**
   - Add `limit` and `offset` query parameters to `/heroes` and `/auctions`
   - Priority: **HIGH** (prevents OOM)

3. **Add Database Indexes**
   ```python
   __table_args__ = (
       Index('ix_hero_owner_deleted', 'owner_id', 'is_deleted'),
       Index('ix_auction_lot_end_time', 'is_active', 'end_time'),
   )
   ```
   Priority: **HIGH** (performance)

### Short Term (1 month)

4. **Implement Idempotency Keys**
   - Add header validation and caching
   - Priority: **MEDIUM** (prevents duplicates on retry)

5. **Add Refresh Token via HTTP-Only Cookie**
   - Store refresh token in secure, HTTP-only cookie
   - Implement token rotation strategy
   - Priority: **MEDIUM** (security)

6. **Audit and Fix Soft Delete Filtering**
   - Create `_active_entities_query()` helper
   - Ensure all queries include `is_deleted=False`
   - Priority: **MEDIUM** (data consistency)

### Medium Term (2 months)

7. **Add Request Logging & Monitoring**
   ```python
   @app.middleware("http")
   async def log_requests(request: Request, call_next):
       start_time = time.time()
       response = await call_next(request)
       process_time = time.time() - start_time
       logging.info(f"{request.method} {request.url.path} {response.status_code} {process_time:.3f}s")
       return response
   ```

8. **Implement Redis Pub/Sub for Real-Time Notifications**
   - Push auction updates live to connected clients
   - Replace polling with WebSocket

9. **Add Comprehensive Error Handling**
   - Custom exception classes
   - Consistent error response schema
   - Detailed logging for debugging

### Long Term (3+ months)

10. **Implement Event Sourcing**
    - Maintain immutable event log of all state changes
    - Audit trail for compliance
    - Time-travel debugging

11. **Add API Versioning**
    - `/v1/heroes`, `/v2/heroes` endpoints
    - Support deprecation windows
    - Backward compatibility strategy

12. **Implement GraphQL Alternative**
    - Allow clients to request only needed fields
    - Reduce payload size
    - Improved developer experience

## Configuration & Environment Variables

### .env File Structure

```bash
# Database
DATABASE_URL=postgresql+asyncpg://user:password@localhost/arena_db

# JWT
JWT_SECRET_KEY=<random-secret-key-at-least-32-chars>
JWT_ALGORITHM=HS256
JWT_EXPIRATION_MINUTES=60

# CORS
ALLOWED_ORIGINS=http://localhost:5000,https://arena.example.com

# Server
HOST=0.0.0.0
PORT=8081

# Email (optional)
EMAIL_HOST=smtp.gmail.com
EMAIL_PORT=587
EMAIL_FROM=noreply@arena.example.com
EMAIL_HOST_USER=your-email@gmail.com
EMAIL_HOST_PASSWORD=<app-password>

# Redis
REDIS_URL=redis://localhost:6379

# Logging
LOG_LEVEL=INFO
```

### Settings Class (app/core/config.py)

```python
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    DATABASE_URL: str = "sqlite+aiosqlite:///:memory:"
    JWT_SECRET_KEY: str = "supersecretkey"
    JWT_ALGORITHM: str = "HS256"
    JWT_EXPIRATION_MINUTES: int = 60
    ALLOWED_ORIGINS: str = "*"
    HOST: str = "0.0.0.0"
    PORT: int = 8081
    
    @property
    def allowed_origins_list(self) -> List[str]:
        if self.ALLOWED_ORIGINS.strip() == "*":
            return ["*"]
        return [o.strip() for o in self.ALLOWED_ORIGINS.split(",")]

settings = Settings()
```

## API Response Schemas (Pydantic)

### UserOut

```python
class UserOut(BaseModel):
    id: int
    email: EmailStr
    username: Optional[str] = None
    
    class Config:
        from_attributes = True
```

### HeroRead

```python
class HeroRead(BaseModel):
    id: int
    name: str
    owner_id: int
    generation: int
    strength: int
    agility: int
    level: int
    experience: int
    perks: List[str]
    equipment: List[Equipment]
    
    class Config:
        from_attributes = True
```

### AuctionOut

```python
class AuctionOut(BaseModel):
    id: int
    item_id: int
    seller_id: int
    current_price: int
    end_time: datetime
    status: str
    bids: List[BidOut]
    
    class Config:
        from_attributes = True
```

## Troubleshooting Common Issues

### Issue: "422 Unprocessable Entity" on POST request

**Cause**: Pydantic validation failed (missing/wrong field types).

**Debug**:
```python
@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request, exc):
    logging.error(f"Validation error: {exc.errors()}")  # Log details
    return JSONResponse(
        status_code=422,
        content={"detail": exc.errors()}  # Return validation details
    )
```

Check `exc.errors()` output for exact field issues.

### Issue: Auction not closing automatically

**Cause**: Background task not running or database connection lost.

**Debug**:
1. Check if startup events executed:
   ```python
   logging.info("Startup tasks created")  # Add to on_startup()
   ```

2. Monitor task execution:
   ```python
   async def close_expired_auctions_task():
       while True:
           logging.info(f"[AUCTION] Checking for expired auctions...")
           # Process...
   ```

3. Verify database connectivity:
   ```python
   async with AsyncSessionLocal() as session:
       await session.execute(select(text("SELECT 1")))  # DB health check
   ```

### Issue: Bids not being reserved correctly

**Cause**: Concurrent bidding without transaction lock.

**Scenario**:
```
User 1: place_bid (100) → balance - reserved >= 100 ✓ → reserved += 100
User 2: place_bid (150) → balance - reserved >= 150 ✓ → reserved += 150
        (But both using same balance, no lock!)
```

**Fix**: Ensure transaction lock on user:
```python
async def place_bid(...):
    async with session.begin():
        user = await session.get(User, user_id, with_for_update=True)
        # Now safe from concurrent updates
```

---

## Summary

The Arena server implements a **layered FastAPI architecture** with:

- **18+ routers** for modular endpoint management
- **Service layer** for business logic encapsulation
- **SQLAlchemy ORM** with async support
- **JWT authentication** with role-based access (RBAC)
- **Redis caching** for high-traffic endpoints
- **Background tasks** for async operations (cleanup, auctions)

**Key Strengths**:
✓ Clean router/service separation
✓ Async database operations
✓ JWT token-based authentication
✓ Redis cache integration
✓ Rate limiting on sensitive endpoints

**Key Weaknesses**:
✗ Race condition on auction closure (HIGH SEVERITY)
✗ No pagination (OOM risk)
✗ Missing database indexes
✗ No request idempotency
✗ Refresh token security concern
✗ Soft delete enforcement gaps

**Critical Priority Fixes**:
1. Add `with_for_update()` locks to auction closure
2. Implement pagination (limit/offset)
3. Add database indexes on FK columns
4. Move refresh token to HTTP-only cookies

The application is architecturally sound but requires immediate attention to race conditions and scalability issues before production deployment.
