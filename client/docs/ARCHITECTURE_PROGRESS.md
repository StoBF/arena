# Client Architecture Progress

## Completed

- **Phase 1 (Diagnostic):** scene/script/autoload/API/signal audit completed.
- **Phase 2 (Modular structure):** target folders created with non-breaking bridge modules.
- **Phase 3 (Global state):** `AppState` centralized fields/signals include:
  - `user`, `balance`, `heroes`, `selected_hero`, `inventory`, `auction_lots`, `chat_messages`, `server_status`, `online_players`
  - signals: `user_data_updated`, `heroes_updated`, `inventory_updated`, `auction_updated`, `chat_updated`, `selected_hero_changed`, `server_status_updated`
- **Phase 4 (API client):** centralized `ApiClient` methods include:
  - `login`, `register`, `get_user`, `get_heroes`, `create_hero`, `get_auction_lots`, `get_chat_messages`, `send_chat_message`, `get_server_status`
- **Phase 5 (Login scene):** language selector/refresh removed; minimal auth UI + status indicator.
- **Phase 6 (Server status):** `ServerStatusManager` autoload polls every 10s and updates `AppState`.
- **Phase 7 (PlayerHub layout):** top hero bar, right details, top-right currency, bottom-left chat overlay, center main panel.
- **Phase 8/9 (Hero bar/details):** hero source from `AppState.heroes`; selection updates details via signal flow.
- **Phase 10 (Hero creation sync):** successful creation refreshes heroes and profile/balance.
- **Phase 11 (Auction table):** category filters and lots rendering from API+state are active.
- **Phase 12 (Storage/inventory):** hero-centric equipment layout + drag/drop pathways remain active.
- **Phase 15/16 (Event flow/performance):** state/signal-first flow reinforced; chat history capped at 200 in `AppState`.
- **Phase 17 (Global EventBus):** `EventBus` autoload added and integrated as cross-system signal hub.
  - Global signals: `hero_selected(hero_id)`, `heroes_updated`, `user_data_updated`, `inventory_updated`, `auction_updated`, `chat_message_received`, `chat_updated`, `server_status_updated`, `scene_changed`.
  - Emission flow standardized: `Api/Managers -> AppState set_* -> EventBus emit_* -> UI subscribers`.
  - Navigation flow standardized via `EventBus.emit_scene_changed(...)` consumed by `UIManager`.
  - Key UI subscribers migrated: `PlayerHub`, `LoginScene`, `Storage`, `Auction`, `HeroCreation`, `BattleRoom`.

## In Progress

- **Phase 13/14 (MMO chat + chat API alignment):**
  - Chat color coding implemented in chat component (global/trade/system).
  - `PlayerHub` now hydrates chat history through `ApiClient.get_chat_messages(...)` into `AppState`.
  - `ApiClient.get_chat_messages(...)` supports `/chat/messages` and legacy `/chat/history` fallback.

## Pending Final Validation

- End-to-end runtime verification pass for:
  - login
  - server status monitoring
  - hero creation
  - hero selection
  - chat messaging/history
  - auction browsing
  - inventory usage

- Final checks:
  - no UI overlap
  - no broken signals
  - no duplicate API calls on critical paths
  - AppState remains source of truth for persistent UI state
