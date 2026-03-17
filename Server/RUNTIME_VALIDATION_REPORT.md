# RUNTIME VALIDATION REPORT — Hero System Backend

> **Date:** 2026-03-15  
> **Method:** Static code analysis + live Python import verification  
> **Scope:** `app/database/models/*`, `app/schemas/*`, `app/services/*`, `app/routers/*`, `app/main.py`, `app/tasks/*`, `migrations/`  
> **Result:** All modules import successfully. **14 runtime-crash risks, 9 logic bugs, 6 structural issues** identified.

---

## 1. Import Validation

All 23 hero-system modules were imported in a live Python 3.14 process. **Zero import errors.**

| Module | Status |
|--------|--------|
| `app.database.models` (all) | OK |
| `app.schemas.hero`, `app.schemas.pagination` | OK |
| `app.core.hero_config`, `app.core.derived_stats`, `app.core.events`, `app.core.enums` | OK |
| `app.services.hero`, `hero_generation`, `training`, `resurrection`, `combat`, `raid`, `accounting`, `inventory` | OK |
| `app.routers.hero`, `app.routers.battle` | OK |
| `app.tasks.cleanup` | OK |

> Imports succeed because Python only validates syntax and top-level names at import time. The `dead_until` references inside function bodies crash only at **call time**, not at import time.

---

## 2. SQLAlchemy Model Relationship Audit

### 2.1 Relationship Pairs — All Match

| Parent | Child | back_populates | Cascade | Status |
|--------|-------|---------------|---------|--------|
| `Hero.owner` ↔ `User.heroes` | `User` | `heroes` | — | ✅ |
| `Hero.perks` ↔ `HeroPerk.hero` | `HeroPerk` | `hero` | all, delete-orphan | ✅ |
| `Hero.equipment_items` ↔ `Equipment.hero` | `Equipment` | `hero` | all, delete-orphan | ✅ |
| `Hero.abilities` ↔ `HeroAbility.hero` | `HeroAbility` | `hero` | all, delete-orphan | ✅ |
| `Hero.history_entries` ↔ `HeroHistory.hero` | `HeroHistory` | `hero` | all, delete-orphan | ✅ |
| `Hero.body_parts` ↔ `HeroBodyPart.hero` | `HeroBodyPart` | `hero` | all, delete-orphan | ✅ |
| `Hero.training_queue` ↔ `HeroTrainingQueue.hero` | `HeroTrainingQueue` | `hero` | all, delete-orphan | ✅ |
| `Hero.combat_stats` ↔ `HeroCombatStats.hero` | `HeroCombatStats` | `hero` (uselist=False) | all, delete-orphan | ✅ |
| `Hero.titles` ↔ `HeroTitle.hero` | `HeroTitle` | `hero` | all, delete-orphan | ✅ |
| `Hero.resurrection_events` ↔ `HeroResurrectionEvent.hero` | `HeroResurrectionEvent` | `hero` | all, delete-orphan | ✅ |
| `HeroPerk.perk` → `Perk` | `Perk` | (no back_populates) | — | ✅ |

### 2.2 Relationship Issues

| # | Issue | Impact |
|---|-------|--------|
| R1 | `Equipment.hero` uses string ref `"app.database.models.hero.Hero"` — works but inconsistent with other models that use `"Hero"` | Cosmetic only ✅ |
| R2 | `HeroPerk.hero` also uses full path string `"app.database.models.hero.Hero"` | Cosmetic only ✅ |
| R3 | `AuctionLot.hero` → `Hero` relationship exists but Hero has no `back_populates` for it | ⚠️ One-directional — OK for read-only usage |

---

## 3. Schema ↔ Model Field Alignment

### 3.1 `HeroOut` vs `Hero` Model — Verified Match

All 30 fields in `HeroOut` map exactly to `Hero` model columns. Enum types (`HeroArchetype`, `HeroCondition`) match. `ConfigDict(from_attributes=True)` is set. **No mismatches.**

### 3.2 `HeroAbilityOut` vs `HeroAbility` Model

| Schema Field | Model Column | Match |
|-------------|-------------|-------|
| `ability_level: int = 1` | `ability_level = Column(Integer, default=1)` | ✅ Exact |
| All other fields | Matching columns | ✅ |

### 3.3 `TrainingQueueOut` vs `HeroTrainingQueue` Model

| Schema Field | Model Column | Match |
|-------------|-------------|-------|
| `time_remaining_seconds` | (not in model) | ✅ Computed at serialization time in `_enrich_queue_out()` |
| All other fields | Matching columns | ✅ |

### 3.4 `ResurrectionEventOut` vs `HeroResurrectionEvent` Model — ✅ All match

### 3.5 `BodyPartOut` vs `HeroBodyPart` Model — ✅ All match

### 3.6 `CombatStatsOut` vs `HeroCombatStats` Model — ✅ All match

### 3.7 `PerkOut` Schema — Cross-Model Schema

`PerkOut` is NOT directly serialized from a single model. It is manually constructed in `HeroService.get_hero_with_perks()` from **both** `HeroPerk` and `Perk` models:

```python
PerkOut(
    id=perk.id,           # from Perk
    name=perk.name,       # from Perk
    description=perk.description,  # from Perk
    effect_type=perk.effect_type,  # from Perk
    max_level=perk.max_level,      # from Perk
    modifiers=perk.modifiers or {},  # from Perk (JSON)
    affected=perk.affected or [],    # from Perk (JSON)
    perk_level=hp.perk_level         # from HeroPerk
)
```

**Issue:** This requires each `HeroPerk` to have a valid `perk_id` pointing to a `Perk` row. Generation does set `perk_id`, so this works. However, `HeroPerk` rows created with only `perk_name` (no `perk_id`) will cause `perk` to be `None`, skipping the perk in the response silently.

### 3.8 Issues Found

| # | Issue | Severity |
|---|-------|----------|
| S1 | `HeroRead` exposes `perks`, `abilities`, `derived_stats` but NOT `combat_stats`, `titles`, `body_parts` — despite those being selectin-loaded on every hero fetch | 🟠 Wasted DB work + missing data for client |
| S2 | `HeroStoryResponse` schema (line 238) has no endpoint that returns it | 🟡 Dead code |
| S3 | `TrainRequest` (old training schema) coexists with `TrainingStartRequest` (new training) | 🟡 Confusing duplication |

---

## 4. Service Methods — Field Access Audit

### 4.1 Fields Accessed on `Hero` Model That DO Exist

All field accesses in `HeroService`, `TrainingService`, `ResurrectionService`, and `hero_generation` reference real `Hero` model columns. Verified:
- `strength`, `perception`, `endurance`, `intelligence`, `agility`, `luck`, `willpower` ✅
- `current_hp`, `condition`, `is_dead`, `dead_at`, `death_cause`, `is_permadead` ✅
- `resurrection_count`, `total_deaths`, `total_kills`, `total_absorbed` ✅
- `is_training`, `training_end_time`, `training_stat`, `training_sessions_completed` ✅
- `archetype`, `current_hp`, `max_hp_override` ✅

### 4.2 Fields Accessed on `Hero` That DO NOT Exist — `dead_until`

| File | Line(s) | Code | Crash Type |
|------|---------|------|-----------|
| `app/services/combat.py` | 113 | `hero.dead_until = now + timedelta(...)` | `AttributeError` |
| `app/services/combat.py` | 116 | `hero.dead_until = None` | `AttributeError` |
| `app/services/raid.py` | 104 | `if not h.dead_until or h.dead_until <= now` | `AttributeError` |
| `app/routers/battle.py` | 33 | `f"...dead until {hero.dead_until}"` | `AttributeError` |
| `app/routers/battle.py` | 39 | `f"...dead until {enemy.dead_until}"` | `AttributeError` |
| `app/routers/battle.py` | 62 | `f"...dead until {h.dead_until}"` | `AttributeError` |
| `app/routers/battle.py` | 69 | `f"...dead until {e.dead_until}"` | `AttributeError` |
| `app/routers/battle.py` | 92 | `f"...dead until {h.dead_until}"` | `AttributeError` |
| `app/routers/battle.py` | 98 | `f"...dead until {boss.dead_until}"` | `AttributeError` |
| `app/tasks/cleanup.py` | 33 | `Hero.dead_until != None` | `AttributeError` at query level |
| `app/tasks/cleanup.py` | 38 | `hero.dead_until = None` | `AttributeError` |
| `tests/test_combat_service.py` | 47 | `hero1.dead_until = datetime(...)` | `AttributeError` |

> **Root cause:** The `Hero` model was refactored from `dead_until` (timer-based revival) to `dead_at` (permanent death timestamp). The legacy files were not updated.

### 4.3 Deprecated Stat Access (columns exist but are `None` for new heroes)

| File | Line(s) | Fields | Impact |
|------|---------|--------|--------|
| `combat.py` | 129 | `hero.speed` | Returns `None` → used as sort key → `TypeError` |
| `combat.py` | 130 | `hero.health` | Returns `None` → used as HP → `TypeError` when doing arithmetic |
| `combat.py` | 131 | `hero.defense` | Returns `None` → `TypeError` in `calculate_damage()` |
| `combat.py` | 133 | `hero.field_of_view` | Returns `None` → added to stats dict |
| `battle.py` | 179 | `hero.defense` | Returns `None` in JSON response — functional but incorrect |
| `battle.py` | 180 | `hero.health` | Returns `None` in JSON response |
| `battle.py` | 253 | `h1.defense + h1.health` | `TypeError: unsupported operand type(s) for +: 'NoneType' and 'NoneType'` |

### 4.4 Item Bonus Fields vs PRIMARY_STATS Mismatch

`HeroService.get_total_stats()` iterates `PRIMARY_STATS` and does `getattr(item, f"bonus_{stat}", 0)`:

| Stat in PRIMARY_STATS | Item.bonus_X exists? | Effect |
|----------------------|---------------------|--------|
| `strength` | `bonus_strength` ✅ | Bonus applied |
| `perception` | ❌ No `bonus_perception` | `getattr` returns 0 — **equipment perception bonuses impossible** |
| `endurance` | `bonus_endurance` ✅ | Bonus applied |
| `intelligence` | `bonus_intelligence` ✅ | Bonus applied |
| `agility` | `bonus_agility` ✅ | Bonus applied |
| `luck` | `bonus_luck` ✅ | Bonus applied |
| `willpower` | ❌ No `bonus_willpower` | `getattr` returns 0 — **equipment willpower bonuses impossible** |

**Additionally:** `bonus_speed`, `bonus_health`, `bonus_defense` exist on `Item` but are NOT in `PRIMARY_STATS`, so equipment bonuses for these deprecated stats are silently ignored.

---

## 5. Router ↔ Service Method Audit

### 5.1 Hero Router (`app/routers/hero.py`)

| Endpoint | Service Call | Method Exists? | Signature Match? |
|----------|-------------|----------------|-----------------|
| `GET /heroes/` | `HeroService.list_heroes(user_id, limit, offset)` | ✅ | ✅ |
| `GET /heroes/{id}` | `HeroService.get_hero(hero_id)` | ✅ | ✅ |
| `POST /heroes/generate` | `HeroService.generate_and_store(owner_id, req)` | ✅ | ✅ |
| `DELETE /heroes/{id}` | `HeroService.delete_hero(hero_id, user_id)` | ✅ | ✅ |
| `POST /heroes/{id}/restore` | `HeroService.restore_hero(hero_id, user_id)` | ✅ | ✅ |
| `GET /heroes/{id}/body` | `HeroService.get_hero(hero_id)` + manual build | ✅ | ✅ |
| `POST /heroes/{id}/train` | `HeroService.start_training(hero_id, stat, dur)` | ✅ | ✅ |
| `POST /heroes/{id}/complete_training` | `HeroService.complete_training(hero_id, xp)` | ✅ | ✅ |
| `POST /heroes/{id}/perks/upgrade` | `HeroService.upgrade_perk(hero_id, perk_id, user_id)` | ✅ | ✅ |
| `POST /heroes/{id}/training/start` | `TrainingService.start_training(hero_id, user_id, req)` | ✅ | ✅ |
| `POST /heroes/{id}/training/cancel` | `TrainingService.cancel_training(hero_id, user_id, entry_id)` | ✅ | ✅ |
| `POST /heroes/{id}/training/claim` | `TrainingService.claim_training(hero_id, user_id, entry_id)` | ✅ | ✅ |
| `GET /heroes/{id}/training` | `TrainingService.get_training_queue(hero_id, user_id)` | ✅ | ✅ |
| `POST /heroes/{id}/resurrect` | `ResurrectionService.resurrect(hero_id, user_id, artifact)` | ✅ | ✅ |
| `GET /heroes/{id}/status` | `ResurrectionService.get_status(hero_id, user_id)` | ✅ | ✅ |

### 5.2 Battle Router (`app/routers/battle.py`)

| Endpoint | Service Call | Method Exists? | Runtime Issue? |
|----------|-------------|----------------|---------------|
| `POST /battle/duel` | `CombatService.simulate_duel(hero, enemy)` | ✅ | 🔴 `dead_until` crash, deprecated stats |
| `POST /battle/team` | `CombatService.simulate_team_battle(heroes, enemies)` | ✅ | 🔴 Same |
| `POST /battle/raid` | `CombatService.simulate_raid(heroes, boss)` | ✅ | 🔴 Same |
| `GET /battle/hero/{id}` | Direct query | — | 🔴 Returns `hero.defense`, `hero.health` (both `None` for new heroes) |
| `GET /battle/predict` | Direct query | — | 🔴 `h1.defense + h1.health` = `TypeError` for new heroes |

### 5.3 Issues

| # | Issue | Severity |
|---|-------|----------|
| RT1 | `POST /heroes/generate` manually constructs response with empty `perks=[]`, `abilities=[]`, `derived_stats=None` instead of using `get_hero_with_perks()` — starter ability and computed stats are omitted from the response | 🟠 Logic bug |
| RT2 | `GET /heroes/{id}` returns raw ORM object as `HeroRead` — `perks` uses default lazy loading so will be empty list; `derived_stats` is `None` | 🟠 Logic bug |
| RT3 | Old training endpoints (`/train`, `/complete_training`) and new training endpoints (`/training/start`, `/training/cancel`, `/training/claim`) coexist — both functional, both modify hero stats through different mechanisms | 🟠 Conflicting logic |

---

## 6. Router Registration Audit (main.py)

### 6.1 All Registered Routers

| Import | Registration | Tags/Prefix |
|--------|-------------|-------------|
| `auth.router` | `app.include_router(auth.router, prefix="/auth", tags=["Auth"])` | ✅ |
| `hero.router` | `app.include_router(hero.router)` | ✅ (prefix `/heroes` set on router) |
| `auction.router` | `app.include_router(auction.router)` | ✅ |
| `bid.router` | `app.include_router(bid.router)` | ✅ |
| `announcement.router` | `app.include_router(announcement.router)` | ✅ |
| `inventory.router` | `app.include_router(inventory.router)` | ✅ |
| `equipment.router` | `app.include_router(equipment.router)` | ✅ |
| `workshop.router` | `app.include_router(workshop.router)` | ✅ |
| `chat.router` | `app.include_router(chat.router, tags=["Chat"])` | ✅ |
| `health_router` | `app.include_router(health_router)` | ✅ |
| `battle_router` | `app.include_router(battle_router)` | ✅ |
| `raid_router` | `app.include_router(raid_router)` | ✅ |
| `craft_router` | `app.include_router(craft_router)` | ✅ |
| `pvp_router` | `app.include_router(pvp_router)` | ✅ |
| `tournaments_router` | `app.include_router(tournaments_router)` | ✅ |
| `events_router` | `app.include_router(events_router)` | ✅ |
| `server_router` | `app.include_router(server_router)` | ✅ |
| `auctions_ws_router` | `app.include_router(auctions_ws_router, tags=["Auction WS"])` | ✅ |

**All routers in `app/routers/` are registered.** No missing registrations.

### 6.2 Background Tasks

| Task | Registered in Lifespan? | Status |
|------|------------------------|--------|
| `delete_old_heroes_task()` | ✅ (line 66) | Functional |
| `close_expired_auctions_task()` | ✅ (line 67) | Functional |
| `revive_dead_heroes_task()` | ❌ **Not started** | Defined in `cleanup.py` but never launched — also broken (uses `dead_until`) |

---

## 7. Migration Consistency

### 7.1 Existing Migrations

| Revision | Description | Hero-Related? |
|----------|-------------|--------------|
| `9a4b80142bda` | Initial tables | ✅ Defines `heroes` table with OLD schema |
| `629b1354c75b` | Add recipe_id to crafted items | ❌ |
| `149a888a2550` | Empty (pass/pass) | ❌ |
| `a1b2c3d4e5f6` | Add request_id to bids | ❌ |
| `b2c3d4e5f6a7` | Add database indexes | ❌ |
| `c3d4e5f6a7b8` | Make username not null | ❌ |

### 7.2 `heroes` Table: Migration vs Model

The initial migration creates `heroes` with these columns:

```
id, name, generation, nickname, strength, agility, intelligence, endurance,
speed(NOT NULL), health(NOT NULL), defense(NOT NULL), luck, field_of_view(NOT NULL),
gold, level, experience, is_training, training_end_time, locale, owner_id,
is_dead, dead_until, is_on_auction, is_deleted, deleted_at
```

The current model requires these **additional** columns (no migration exists):

| Column | Type | Default | Migration Status |
|--------|------|---------|-----------------|
| `perception` | Integer NOT NULL | 0 | ❌ Missing |
| `willpower` | Integer NOT NULL | 0 | ❌ Missing |
| `archetype` | Enum(hero_archetype) nullable | None | ❌ Missing |
| `current_hp` | Integer NOT NULL | 100 | ❌ Missing |
| `max_hp_override` | Integer nullable | None | ❌ Missing |
| `condition` | Enum(hero_condition) NOT NULL | 'healthy' | ❌ Missing |
| `resurrection_count` | Integer NOT NULL | 0 | ❌ Missing |
| `dead_at` | DateTime nullable | None | ❌ Missing (replaces `dead_until`) |
| `death_cause` | String(200) nullable | None | ❌ Missing |
| `is_permadead` | Boolean | False | ❌ Missing |
| `total_kills` | Integer NOT NULL | 0 | ❌ Missing |
| `total_deaths` | Integer NOT NULL | 0 | ❌ Missing |
| `total_absorbed` | Integer NOT NULL | 0 | ❌ Missing |
| `training_stat` | String(30) nullable | None | ❌ Missing |
| `training_sessions_completed` | Integer NOT NULL | 0 | ❌ Missing |
| `created_at` | DateTime NOT NULL | utcnow | ❌ Missing |

**Column to rename/drop:** `dead_until` → model uses `dead_at` instead.  
**Columns to make nullable:** `speed`, `health`, `defense`, `field_of_view` (currently NOT NULL in migration, nullable in model).

### 7.3 New Tables — No Migration

| Table | Columns | FK | Migration |
|-------|---------|-----|-----------|
| `hero_abilities` | 11 cols + 2 indexes + unique constraint | heroes.id CASCADE | ❌ Missing |
| `hero_history` | 5 cols + 1 composite index | heroes.id CASCADE | ❌ Missing |
| `hero_body_parts` | 8 cols + unique constraint | heroes.id CASCADE | ❌ Missing |
| `hero_training_queue` | 11 cols + composite index | heroes.id CASCADE | ❌ Missing |
| `hero_combat_stats` | 9 cols + unique hero_id | heroes.id CASCADE | ❌ Missing |
| `hero_titles` | 7 cols + unique constraint | heroes.id CASCADE | ❌ Missing |
| `hero_resurrection_events` | 9 cols + index | heroes.id CASCADE | ❌ Missing |

### 7.4 New Enum Types — No Migration

| Enum | Used By |
|------|---------|
| `hero_archetype` | Hero.archetype |
| `ability_type` | HeroAbility.ability_type |
| `ability_domain` | HeroAbility.ability_domain |
| `body_part_status` | HeroBodyPart.status |
| `training_type` | HeroTrainingQueue.training_type |
| `training_status` | HeroTrainingQueue.status |
| `hero_condition` | Hero.condition, HeroResurrectionEvent.condition_before/after |

### 7.5 New Index — No Migration

| Index | Table | Columns |
|-------|-------|---------|
| `ix_heroes_archetype` | heroes | archetype |

---

## 8. Enum Definition Audit

All 7 hero enums are defined in `app/database/models/hero.py` and exported via `__init__.py`:

| Enum | Values | Imported By | Status |
|------|--------|------------|--------|
| `HeroArchetype` | 7 values | schemas, services, config | ✅ |
| `AbilityType` | 5 values | schemas, generation | ✅ |
| `AbilityDomain` | 8 values | schemas, generation | ✅ |
| `BodyPartStatus` | 5 values | schemas | ✅ |
| `TrainingType` | 3 values | schemas, training service | ✅ |
| `TrainingStatus` | 4 values | training service | ✅ |
| `HeroCondition` | 5 values | schemas, resurrection service, model | ✅ |

No missing enum definitions. All enum values used in config (`CONDITION_THRESHOLDS`, `RESURRECTION_ARTIFACTS`) match the enum members.

---

## 9. Consolidated Issue Tracker

### 🔴 CRITICAL — Runtime Crash on Call

| ID | Description | File(s) | Trigger |
|----|------------|---------|---------|
| C1 | `hero.dead_until` — attribute does not exist on Hero model | combat.py:113,116 | Any battle completes |
| C2 | `hero.dead_until` — attribute does not exist on Hero model | battle.py:33,39,62,69,92,98 | Any duel/team/raid with dead hero |
| C3 | `h.dead_until` — attribute does not exist | raid.py:104 | `is_team_defeated()` call |
| C4 | `Hero.dead_until` in SQLAlchemy query — no such column | cleanup.py:33 | Cleanup task tick (every 60s) |
| C5 | `hero.dead_until = None` — attribute write fails | cleanup.py:38 | (never reached due to C4) |
| C6 | `hero.speed` is `None` → `sorted(fighters, key=lambda f: f["stats"]["speed"])` | combat.py:70 | Combat with new hero |
| C7 | `hero.health` is `None` → `stats["health"]` used as HP → arithmetic | combat.py:130,65 | Combat with new hero |
| C8 | `hero.defense` is `None` → `int(defense * 0.7)` in `calculate_damage()` | combat.py:131,150 | Combat with new hero |
| C9 | `h1.defense + h1.health` — `None + None` | battle.py:253 | `GET /battle/predict` with new hero |
| C10 | 7 new DB tables do not exist — any INSERT/SELECT will fail | All new services | Any new-subsystem endpoint called |
| C11 | 16 new Hero columns not in DB — `INSERT` with new hero data fails | hero_generation.py | `POST /heroes/generate` |
| C12 | 7 enum types not created in Postgres — `INSERT` fails with check constraint | hero_generation.py | `POST /heroes/generate` |
| C13 | `dead_until` column exists in DB but not in model — `create_db_and_tables()` won't remove it; Alembic autogenerate would try to drop it | — | Schema sync |
| C14 | `cleanup.py:revive_dead_heroes_task` uses `Hero.dead_until` in query filter | cleanup.py:33 | If task were ever started |

### 🟠 HIGH — Logic Bugs / Data Errors

| ID | Description | File(s) |
|----|------------|---------|
| H1 | `POST /heroes/generate` returns `perks=[], abilities=[], derived_stats=None` — omits the starter ability and derived stats just created | hero router:78-80 |
| H2 | `GET /heroes/{id}` returns `HeroRead` from raw ORM → `perks` always empty (lazy-loaded), `derived_stats` always `None` | hero router:63 |
| H3 | Duplicate training: OLD (`/train`, `/complete_training`) and NEW (`/training/start`, `/claim`, `/cancel`) coexist with different mechanisms | hero router, hero service, training service |
| H4 | `HeroRead` schema missing `combat_stats`, `titles`, `body_parts` fields despite selectin-loading | schemas/hero.py:161 |
| H5 | `Item` model missing `bonus_perception`, `bonus_willpower` columns — equipment cannot boost these new primary stats | models.py, hero service:229 |
| H6 | `CombatService` does not use new systems: no `condition` update, no `HeroCombatStats` tracking, no body part damage, no `ResurrectionService.kill_hero()` | combat.py |
| H7 | `CombatService.simulate_battle` commits inside `for` loop — partial commit on error | combat.py:115 |
| H8 | Hero title awarding logic unimplemented — `HERO_TITLES` config and `HeroTitle` model exist but nothing checks thresholds | (nowhere) |
| H9 | `revive_dead_heroes_task` not started in `main.py` lifespan — dead code, also broken | main.py, cleanup.py |

### 🟡 MEDIUM — Tech Debt / Cosmetic

| ID | Description | File(s) |
|----|------------|---------|
| M1 | `HeroStoryResponse` schema defined but no endpoint serves it | schemas/hero.py:238 |
| M2 | `TrainRequest` schema coexists with `TrainingStartRequest` | schemas/hero.py |
| M3 | `__table_args__ = {'extend_existing': True}` at module level in config file — no effect | hero_config.py:235 |
| M4 | `GET /battle/hero/{id}` returns `defense` and `health` keys — deprecated stats, will be `None` for new heroes | battle.py:178-180 |
| M5 | No endpoints for: hero history, ability management, title listing | hero router |
| M6 | Tests (`test_hero_service.py`, `test_combat_service.py`) reference removed stats and `dead_until` — all hero tests broken | tests/ |

---

## 10. Test File Status

| Test File | Tests | Status |
|-----------|-------|--------|
| `test_hero_service.py` | `test_create_and_get_hero` | ⚠️ Works but hero has no archetype/body parts |
| | `test_generate_hero_with_all_attributes` | ❌ Asserts `speed`, `health`, `defense`, `field_of_view` from ATTRIBUTE_RANGES — keys removed |
| | `test_add_experience_and_level_up` | ✅ Should pass |
| | `test_get_total_stats_with_equipment` | ⚠️ May fail if derived stats format changed |
| | `test_get_nickname_for_new_attributes` | ⚠️ Sets deprecated stats — may work for nickname test |
| | `test_hero_training_flow` | ❌ Calls `start_training(hero.id, duration_minutes=1)` — missing required `training_stat` argument |
| | `test_upgrade_perk` | ✅ Should pass |
| `test_combat_service.py` | `test_duel_basic` | ❌ Uses `dead_until`, deprecated stats |
| | `test_perk_effects` | ❌ Same issues |

---

## Appendix: Quick Reference — What Crashes When

| User Action | Endpoint | Crash Point | Error |
|------------|----------|-------------|-------|
| Generate a hero | `POST /heroes/generate` | DB INSERT | Missing columns/tables/enums in Postgres |
| View hero detail | `GET /heroes/{id}` | — | Works but incomplete data (no perks/derived_stats) |
| Start a duel | `POST /battle/duel` | battle.py:33 | `AttributeError: 'Hero' object has no attribute 'dead_until'` |
| Team battle | `POST /battle/team` | battle.py:62 | `AttributeError: 'Hero' object has no attribute 'dead_until'` |
| Raid battle | `POST /battle/raid` | battle.py:92 | `AttributeError: 'Hero' object has no attribute 'dead_until'` |
| Predict battle | `GET /battle/predict` | battle.py:253 | `TypeError: unsupported operand type(s) for +: 'NoneType' and 'NoneType'` |
| View hero combat stats | `GET /battle/hero/{id}` | — | Returns `{"defense": null, "health": null}` |
| New training (queue) | `POST /heroes/{id}/training/start` | DB INSERT | Table `hero_training_queue` does not exist |
| Resurrect hero | `POST /heroes/{id}/resurrect` | DB INSERT | Table `hero_resurrection_events` does not exist |
| View hero status | `GET /heroes/{id}/status` | — | Works (reads from Hero columns only) |
| Cleanup task | (background) | cleanup.py:33 | `AttributeError` on `Hero.dead_until` in query |
