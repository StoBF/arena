# Arena Client Architecture (Godot 4)

## High-Level Architecture Overview

The Arena client is a Godot 4 application written in GDScript that implements a real-time multiplayer hero management and auction system. It follows a layered architecture with clear separation between presentation (scenes), state management (autoload singletons), and network communication.

### Architecture Layers

```
┌─────────────────────────────────────────────────────────────┐
│  Presentation Layer (Scenes & UI Panels)                    │
│  - login_screen.tscn, MainMenu.tscn, Auction.tscn, etc.     │
│  - Each scene handles user interaction and visual feedback   │
└─────────────────────────────────────────────────────────────┘
                           ▼
┌─────────────────────────────────────────────────────────────┐
│  Business Logic Layer (UI Panels Scripts)                   │
│  - LoginPanel.gd, AuctionPanel.gd, HeroListPanel.gd        │
│  - Form validation, state transitions, data formatting      │
└─────────────────────────────────────────────────────────────┘
                           ▼
┌─────────────────────────────────────────────────────────────┐
│  State Management Layer (Autoload Singletons)              │
│  - AppState.gd (user session, hero data)                   │
│  - Localization.gd (i18n, locale persistence)              │
│  - UIUtils.gd (toast notifications, dialogs)               │
│  - NetworkManager.gd (HTTP client, retry logic)            │
│  - ServerConfig.gd (server endpoint configuration)         │
└─────────────────────────────────────────────────────────────┘
                           ▼
┌─────────────────────────────────────────────────────────────┐
│  Network Layer (HTTP over HTTPClient Godot API)            │
│  - Bearer token authentication                              │
│  - Automatic retry with exponential backoff                 │
│  - Server status health checks                              │
└─────────────────────────────────────────────────────────────┘
                           ▼
┌─────────────────────────────────────────────────────────────┐
│  FastAPI Backend (HTTP JSON API)                           │
└─────────────────────────────────────────────────────────────┘
```

## Scene Structure & Navigation

### Core Scenes

| Scene | Purpose | Script | Key Dependencies |
|-------|---------|--------|------------------|
| `login_screen.tscn` | User authentication entry point | `LoginPanel.gd` | `NetworkManager`, `Localization` |
| `Register.tscn` | User account creation | `RegisterPanel.gd` | `NetworkManager`, `Localization` |
| `MainMenu.tscn` | Main hub after login | `MainMenuScreen.gd` | `AppState`, `NetworkManager`, `HeroIcon` |
| `Auction.tscn` | Auction browsing & bidding | `AuctionPanel.gd` | `NetworkManager`, `UIUtils` |
| `Inventory.tscn` | Item management | `InventoryPanel.gd` | `AppState`, `NetworkManager` |
| `HeroList.tscn` | Hero roster management | `HeroListPanel.gd` | `AppState`, `NetworkManager` |
| `GenerateHeroScene.tscn` | Hero creation/generation | `GenerateHeroScene.gd` | `NetworkManager`, `AppState` |
| `HeroEquipment.tscn` | Equipment management | `HeroEquipmentPanel.gd` | `NetworkManager`, `AppState` |
| `ChatBox.tscn` | Team/global chat | `ChatBox.gd` | `NetworkManager` |

### Scene Navigation Flow

```
login_screen.tscn ──► Register.tscn
    │
    └─ [Authentication] ─► MainMenu.tscn
                              │
                              ├─► HeroList.tscn
                              ├─► Auction.tscn ──► [Place Bid]
                              ├─► Inventory.tscn
                              ├─► HeroEquipment.tscn
                              ├─► GenerateHeroScene.tscn
                              └─► ChatBox.tscn
```

## Autoload Singletons (Global State)

### AppState.gd

Persistent global state for authenticated session:

```gdscript
var token: String = ""              # JWT access token
var user_id: int = -1               # Current user ID
var current_hero_id: int = -1       # Selected hero ID
var last_created_hero: Dictionary = {}  # Temp storage for new hero
```

**Lifecycle**: Initialized at startup, persists across scene changes, cleared on logout.

**Risks**:
- Token stored in plaintext (no encryption)
- No refresh token management in AppState
- No token expiration tracking

### Localization.gd

Internationalization and locale management:

```gdscript
var locale: String = "en"                          # Current locale
var translations: Dictionary = {}                  # Loaded translations
const SUPPORTED_LOCALES = ["en", "pl", "uk"]
const LOCALE_CONFIG_PATH = "user://locale.cfg"
signal locale_changed
```

**Features**:
- Lazy loads JSON translation files (`locales/en.json`, etc.)
- Persists user locale choice to filesystem
- Emits signal on locale changes for UI updates

**Implementation Details**:
- `t(key: String)` method returns translated string with fallback to key name
- Uses Godot's TranslationServer for `tr()` function support

### UIUtils.gd

Centralized UI feedback management:

```gdscript
static func show_error(message: String) -> void
static func show_success(message: String) -> void
static func show_info(message: String) -> void
```

Uses temporary toast notifications or modal dialogs.

### NetworkManager.gd

Core HTTP communication layer with automatic retry logic:

```gdscript
var default_headers: Array = []        # Auth headers
var max_retries: int = 3              # Retry attempts
var retry_delay: float = 1.0          # Backoff seconds

signal request_completed(result, code, headers, body_text)
signal server_status_checked(online, latency_ms, error_message)

func set_auth_header(token: String) -> void
func request(endpoint, method, data, headers, retry_count) -> HTTPRequest
func check_server_status() -> void
```

**Key Methods**:

- `request()`: Creates HTTPRequest node, manages active requests cache, handles connection lifecycle
- `_on_request_completed()`: Processes response; triggers automatic retry on server errors (5xx)
- `_retry_request()`: Exponential backoff retry with `await get_tree().create_timer()`
- `check_server_status()`: Periodic healthcheck with timeout tracking

**Request Flow**:
```
request() ─► HTTPRequest.request() ─► _on_request_completed() ──► retries? ──► emit signal
                                              ▲
                                              │ (retry)
                                     _retry_request()
```

### ServerConfig.gd

Singleton for server connection configuration:

```gdscript
var _server_url: String = "http://localhost:8081"
var _use_https: bool = false

func get_http_endpoint(path: String) -> String
func set_server_url(url: String) -> void
```

## Authentication Flow

### Login Request Sequence

```
User Input (email/password)
    ▼
LoginPanel._on_login_pressed()
    ▼
Network.request("/auth/login", POST, {login, password})
    ▼
HTTPRequest sends request with timeout=10s
    ▼
Server validates credentials
    ▼
Server returns {access_token, refresh_token, token_type}
    ▼
AppState.token = access_token
    ▼
Network.set_auth_header("Bearer {token}")
    ▼
Navigate to MainMenu.tscn
```

### Token Usage

Every authenticated request includes header:
```
Authorization: Bearer <access_token>
```

Added by `NetworkManager.set_auth_header()` and appended to every request.

### Registration Flow

```
User Input (email, username, password)
    ▼
RegisterPanel.on_register_pressed()
    ▼
Network.request("/auth/register", POST, {email, username, password})
    ▼
Server creates User, returns {id, email, username}
    ▼
UIUtils.show_success("Registration successful")
    ▼
Navigate back to login_screen.tscn
```

## Request/Response Flow Diagrams

### Hero List Retrieval

```
MainMenuScreen._ready()
    │
    ├─ Network.request("/heroes", GET)
    │
    └─► HTTPRequest.request()
        │
        ├─► Server processes request (checks JWT)
        │   │
        │   ├─ Load heroes from DB (is_deleted=false)
        │   │
        │   ├─ Load eager relationships (perks, equipment)
        │   │
        │   └─ Return HeroRead[] schema
        │
        ├─► NetworkManager._on_request_completed()
        │   │
        │   └─ emit signal "request_completed"
        │
        └─► MainMenuScreen._on_heroes_loaded()
            │
            ├─ Parse JSON response
            │
            ├─ Instantiate HeroIcon for each hero
            │
            ├─ Cache heroes_data: Array
            │
            └─ Display hero info in UI
```

### Auction Bidding Flow

```
User enters bid amount → AuctionPanel._on_bid_button_pressed()
    │
    ├─ Validate bid amount > 0
    │
    ├─ Network.request("/bids", POST, {auction_id, amount})
    │
    └─► HTTPRequest.request()
        │
        ├─► BidService.place_bid()
        │   │
        │   ├─ Lock user row for update (SELECT...FOR UPDATE)
        │   │
        │   ├─ Validate user.balance - user.reserved >= amount
        │   │
        │   ├─ Release previous bidder's reserved funds
        │   │
        │   ├─ Reserve funds: user.reserved += amount
        │   │
        │   ├─ Create Bid record
        │   │
        │   ├─ Update Auction.current_price, winner_id
        │   │
        │   └─ Commit transaction
        │
        └─► AuctionPanel._on_bid_response()
            │
            ├─ UIUtils.show_success()
            │
            └─ _load_auctions() [refresh list]
```

## Data Flow: Hero Generation

```
GenerateHeroScene._on_generate_pressed()
    │
    ├─ Collect generation parameters {generation, currency, locale}
    │
    └─► Network.request("/heroes/generate", POST, data)
        │
        ├─► HeroService.generate_and_store()
        │   │
        │   ├─ Validate hero count < MAX_HEROES
        │   │
        │   ├─ Call generate_hero() service
        │   │   │
        │   │   ├─ RNG-based stat generation
        │   │   │
        │   │   └─ Assign perks/traits
        │   │
        │   ├─ Create Hero record
        │   │
        │   ├─ Commit to DB
        │   │
        │   └─ Return HeroRead
        │
        ├─ Cache in AppState.last_created_hero
        │
        └─► Client navigates to MainMenu
            │
            └─ MainMenu displays new hero
```

## Data Model (Client-Side JSON Schema)

### User Model
```json
{
  "id": 1,
  "email": "user@example.com",
  "username": "player_name",
  "balance": 1000.00,
  "reserved": 50.00
}
```

### Hero Model
```json
{
  "id": 1,
  "name": "Aragorn",
  "owner_id": 1,
  "generation": 1,
  "nickname": "the Brave",
  "level": 5,
  "experience": 250,
  "strength": 18,
  "agility": 14,
  "intelligence": 10,
  "endurance": 16,
  "speed": 12,
  "health": 50,
  "defense": 8,
  "luck": 6,
  "field_of_view": 10,
  "is_training": false,
  "is_dead": false,
  "is_on_auction": false,
  "is_deleted": false,
  "perks": ["Leadership", "Diplomacy"],
  "equipment_items": [
    {
      "id": 1,
      "hero_id": 1,
      "item_id": 1,
      "slot": "weapon",
      "item": {...}
    }
  ]
}
```

### Auction Model
```json
{
  "id": 1,
  "item_id": 5,
  "seller_id": 2,
  "start_price": 100,
  "current_price": 150,
  "end_time": "2024-02-25T18:30:00",
  "status": "active",
  "quantity": 1,
  "winner_id": null,
  "bids": [
    {
      "id": 1,
      "bidder_id": 3,
      "amount": 150,
      "created_at": "2024-02-25T17:45:00"
    }
  ]
}
```

### AuctionLot Model (Hero Auction)
```json
{
  "id": 1,
  "hero_id": 5,
  "seller_id": 2,
  "starting_price": 500,
  "current_price": 600,
  "buyout_price": 1000,
  "end_time": "2024-02-26T00:00:00",
  "is_active": 1,
  "winner_id": null
}
```

## Known Technical Risks & Issues

### 1. **Token Security (HIGH SEVERITY)**

**Risk**: Access token stored in plaintext in AppState singleton.

**Current Implementation**:
```gdscript
var token: String = ""  # Visible in memory, no encryption
```

**Attack Vector**: Malicious GDScript code in user-installed mods, memory dumps, or reverse engineering can extract token.

**Recommendation**:
- Use Godot's `OS.request_permissions()` for secure credential storage
- Implement refresh token flow with short-lived access tokens (15 min)
- Store refresh token in OS keychain/credential manager
- Add token expiration tracking before making requests

### 2. **No Token Expiration Handling (MEDIUM SEVERITY)**

**Risk**: Client doesn't track JWT expiration; requests fail with 401 without automatic refresh.

**Current Behavior**: No logic to detect expired token or trigger refresh_token endpoint.

**Scenario**: User leaves app running for 1+ hour, token expires, next request fails.

**Recommendation**:
```gdscript
func _make_authenticated_request(endpoint, method, data):
    if is_token_expired():
        await refresh_token()
    return Network.request(endpoint, method, data)

func is_token_expired() -> bool:
    # Decode JWT payload, check "exp" claim
    var payload = jwt_decode(AppState.token)
    return payload["exp"] < Time.get_ticks_msec() / 1000
```

### 3. **Race Condition: Concurrent Hero Deletion + Auction (MEDIUM SEVERITY)**

**Scenario**:
1. User puts hero on auction (sets `is_on_auction = true`)
2. Auction closure happens
3. User deletes hero in another tab (sets `is_deleted = true`)
4. Auction task tries to transfer "deleted hero" to auction winner

**Current Code**:
```python
# No transaction lock on hero during auction closure
hero = await self.session.get(Hero, lot.hero_id)
# Hero could be deleted here by another request
await self.session.delete(hero)
```

**Recommendation**:
```python
# Use pessimistic locking
async with session.begin():
    hero = await session.get(Hero, lot.hero_id, with_for_update=True)
    if hero.is_deleted:
        raise HTTPException(400, "Hero was deleted")
    # Safe to proceed
```

### 4. **Lack of Pagination (MEDIUM SEVERITY)**

**Risk**: Hero list, auction list loaded entirely in memory.

**Scenario**: User with 1000 heroes: all loaded in one request, UI freezes.

**Current Implementation**:
```gdscript
Network.request("/heroes", GET)  # No limit/offset params
```

**Recommendation**:
```gdscript
Network.request("/heroes?limit=20&offset=0", GET)
# Implement lazy loading with ItemList/GridContainer scroll handling
```

### 5. **Cache Invalidation Race (LOW SEVERITY)**

**Current Flow**:
```python
# Redis cache delete after auction close
await redis_cache.delete("auctions:active")

# But concurrent read might load stale data:
cached = await redis_cache.get("auctions:active")  # Still valid!
```

**Recommendation**:
- Use cache versioning/timestamps
- Implement cache layer with TTL-based expiration (30-60 sec)
- Add cache validation on client side

### 6. **Missing Input Validation (MEDIUM SEVERITY)**

**Client Side**:
- Bid amount: no range validation (negative bids possible)
- Hero name: 256 characters allowed but UI truncates at 50
- Generation parameter: no bounds checking

**Recommendation**:
```gdscript
func _validate_bid(amount: float) -> bool:
    if amount <= 0:
        UIUtils.show_error("Bid must be positive")
        return false
    if amount > 999999999:
        UIUtils.show_error("Bid too large")
        return false
    return true
```

### 7. **Network Retry Without Idempotency Check (MEDIUM SEVERITY)**

**Risk**: POST request retried up to 3 times without idempotency key.

**Scenario**: Bid placed → server processes ✓ → network timeout → client retries → duplicate bid created.

**Current Code**:
```gdscript
func _retry_request(request_info):
    # Retries same POST without idempotency protection
    request(request_info.endpoint, request_info.method, ...)
```

**Recommendation**:
- Add `Idempotency-Key` header (UUID for each request)
- Server checks duplicate key before processing
- Return 200 with cached result on duplicate

### 8. **Chat Message Persistence Not Clear (LOW SEVERITY)**

**Risk**: Chat UI doesn't specify if messages persist or are session-scoped.

**Current UI**: `ChatBox.gd` sends messages but no indication of storage model.

**Recommendation**: Document whether chat is:
- Ephemeral (in-memory only, lost on disconnect)
- Persistent (stored in DB for history)
- Hybrid (short-term buffer + archival)

### 9. **Hardcoded Server URL (LOW SEVERITY)**

**Risk**: Server endpoint hardcoded in `ServerConfig.gd` singleton.

**Current**:
```gdscript
var _server_url: String = "http://localhost:8081"
```

**Recommendation**:
- Load from `project.godot` export vars
- Support via environment variable override
- Detect from current domain (for web builds)

### 10. **HTTPRequest Timeout Not Exponential (LOW SEVERITY)**

**Current**: All requests use fixed timeout:
```gdscript
http_request.timeout = 10.0  # Always 10 seconds
```

**Better Practice**: Increase timeout on retries
```gdscript
http_request.timeout = 10.0 + (retry_count * 5)  # 10s, 15s, 20s
```

## Recommended Improvements

### Short Term (1-2 weeks)

1. **Implement Token Refresh Flow**
   ```gdscript
   # Add to NetworkManager
   signal token_refreshed
   func refresh_access_token() -> bool:
       var response = Network.request("/auth/refresh", POST, {refresh_token})
       # Update AppState.token
       # Retry original request
   ```

2. **Add Request Idempotency Keys**
   ```gdscript
   # Generate UUID for every request
   var idempotency_key = UUID.v4()
   headers.append("Idempotency-Key: %s" % idempotency_key)
   ```

3. **Implement Pagination**
   - Add `limit` and `offset` query parameters
   - Implement scrollable ItemList with lazy loading on bottom-reached

### Medium Term (1 month)

4. **Secure Token Storage**
   - Migrate from plaintext AppState to Godot's credentials API
   - Implement 15-minute access token + 7-day refresh token

5. **Add Network Error Handling**
   - Detect 401 Unauthorized → trigger token refresh
   - Detect 403 Forbidden → show permission denied message
   - Retry with exponential backoff

6. **Implement Optimistic UI Updates**
   - Update UI immediately on user action
   - Revert on server error
   - Example: Show bid placed immediately, revert on 400 response

### Long Term (2-3 months)

7. **Add Local Data Caching**
   - Cache hero list locally with sync strategy
   - Offline mode support

8. **Implement WebSocket Connection** (if supporting real-time updates)
   - Replace polling with WebSocket for live auction updates
   - Real-time hero status notifications

9. **Add Telemetry/Analytics**
   - Track client-side errors
   - Monitor network latency distribution
   - Identify UI bottlenecks

## Configuration Files

### Localization JSON Structure

**locales/en.json**:
```json
{
  "login_button": "Sign In",
  "register_button": "Create Account",
  "password": "Password",
  "username": "Username",
  "email": "Email",
  "remember_me": "Remember me",
  "server_online": "Server Online",
  "server_offline": "Server Offline",
  "server_latency": "Latency: %d ms",
  "heroes": "Heroes",
  "auction": "Auction",
  "inventory": "Inventory",
  "generate_success": "Hero generated successfully",
  "bid_success": "Bid placed successfully"
}
```

**locales/uk.json** (Ukrainian):
```json
{
  "login_button": "Увійти",
  "register_button": "Створити акаунт",
  ...
}
```

### Project Settings (project.godot)

Critical autoload configuration:
```ini
[autoload]
AppState="res://autoload/AppState.gd"
Localization="res://autoload/Localization.gd"
UIUtils="res://autoload/UIUtils.gd"
Network="res://scripts/network/NetworkManager.gd"
ServerConfig="res://scripts/network/ServerConfig.gd"
```

Viewport & rendering:
```ini
[display]
window/size/viewport_width=1920
window/size/viewport_height=1080

[physics]
2d/default_gravity=0  # Menu-based, not physics game
```

## Troubleshooting Common Issues

### Issue: "401 Unauthorized" on every request after login

**Cause**: `AppState.token` not set after login response.

**Debug**: Add print statement:
```gdscript
func _on_login_response(...):
    AppState.token = response_data["access_token"]
    print("Token set: ", AppState.token)  # Debug
    Network.set_auth_header(AppState.token)
```

### Issue: Heroes list not loading

**Causes**:
1. User not authenticated (token missing)
2. Server offline (check server status label)
3. Timeout after 10s (increase `http_request.timeout`)

**Check**:
```gdscript
print("Request sent to: ", ServerConfig.get_http_endpoint("/heroes"))
print("Auth header: ", Network.default_headers)
```

### Issue: Auction bid fails with "Insufficient funds"

**Cause**: User balance doesn't account for `reserved` funds from previous bids.

**Expected Balance Calculation**: `available = balance - reserved`

---

## File Structure Summary

```
client/
├── autoload/                    # Global singletons
│   ├── AppState.gd             # Session & user state
│   ├── Localization.gd         # i18n management
│   └── UIUtils.gd              # Toast/dialog utilities
├── scenes/                      # TSCN scene files
│   ├── login_screen.tscn
│   ├── MainMenu.tscn
│   ├── Auction.tscn
│   ├── HeroList.tscn
│   ├── GenerateHeroScene.tscn
│   └── ... (other scenes)
├── scripts/
│   ├── network/
│   │   ├── NetworkManager.gd   # HTTP client + retry logic
│   │   └── ServerConfig.gd     # Server config
│   └── ui/                      # UI panel scripts
│       ├── LoginPanel.gd
│       ├── AuctionPanel.gd
│       ├── HeroListPanel.gd
│       └── ... (other panels)
├── locales/                     # i18n JSON files
│   ├── en.json
│   ├── uk.json
│   └── pl.json
├── assets/                      # Images, icons
└── project.godot                # Project config
```

---

## Summary

The Arena client implements a **multi-layered Godot 4 architecture** with:

- **Scene-based UI** for modular screen management
- **Singleton autoloads** for persistent state and shared services
- **NetworkManager abstraction** for resilient HTTP communication
- **Bearer token authentication** with JWT validation
- **Localization system** supporting 3 languages

**Key Strengths**:
✓ Clear separation of concerns
✓ Automatic retry logic with exponential backoff
✓ Multi-language support
✓ Modular scene structure

**Key Weaknesses**:
✗ No token refresh flow
✗ Plaintext token storage
✗ No pagination support
✗ Lack of network error recovery for 401/403
✗ No idempotency for POST requests

Recommended priority fixes: token refresh, pagination, and idempotency keys.
