# POST-IMPLEMENTATION HERO SYSTEM AUDIT

**Date:** 2026-03-15
**Scope:** All hero-related backend code added/modified during the recent refactor
**Verdict:** Structurally sound new code, but **critical legacy conflicts** prevent the server from running against the existing database without a migration.

---

## 1. FILES CHANGED

### Modified Files

| File | Lines | Summary |
|------|-------|---------|
| `Server/app/database/models/hero.py` | 375 | Massive expansion: 7 enums, 10 models, new columns on Hero |
| `Server/app/database/models/__init__.py` | 20 | Updated exports for all new models and enums |
| `Server/app/schemas/hero.py` | 280 | Added 15+ new schema classes/fields |
| `Server/app/core/hero_config.py` | 235 | Added archetype config, body parts, training, titles, resurrection |
| `Server/app/routers/hero.py` | 278 | Added 7 new endpoints |
| `Server/app/services/hero.py` | 366 | No structural changes; retains old inline training system |
| `Server/app/services/hero_generation.py` | 203 | Expanded to seed body parts, combat stats, abilities, archetype |

### New Files

| File | Lines | Purpose |
|------|-------|---------|
| `Server/app/core/derived_stats.py` | ~132 | Derived stat computation (max_hp, initiative, accuracy, etc.) |
| `Server/app/services/training.py` | 331 | New queue-based training service |
| `Server/app/services/resurrection.py` | 243 | Death/resurrection service |

---

## 2. NEW DATABASE MODELS

### Enums Added (in `models/hero.py`)

| Enum | Values | DB Type |
|------|--------|---------|
| `HeroArchetype` | VANGUARD, PREDATOR, PHANTOM, MYSTIC, WARDEN, APOSTLE, CHIMERA | `hero_archetype` |
| `AbilityType` | OFFENSIVE, DEFENSIVE, UTILITY, SUPPORT, MUTATION | `ability_type` |
| `AbilityDomain` | BIOMORPH, SPACE, PSIONIC, ELEMENTAL, SHADOW, BLOOD, ORDER, CHAOS | `ability_domain` |
| `BodyPartStatus` | healthy, injured, crippled, broken, destroyed | `body_part_status` |
| `TrainingType` | attribute, discipline, ability | `training_type` |
| `TrainingStatus` | queued, running, completed, cancelled | `training_status` |
| `HeroCondition` | healthy, wounded, severely_injured, crippled, dead | `hero_condition` |

### New Columns on `heroes` Table

| Column | Type | Default | Notes |
|--------|------|---------|-------|
| `perception` | Integer | 0 | **New primary stat** |
| `willpower` | Integer | 0 | **New primary stat** |
| `archetype` | Enum(HeroArchetype) | NULL | Hero archetype |
| `current_hp` | Integer | 100 | Current hit points |
| `max_hp_override` | Integer | NULL | Manual HP cap |
| `condition` | Enum(HeroCondition) | HEALTHY | Overall health state |
| `resurrection_count` | Integer | 0 | Times revived |
| `dead_at` | DateTime | NULL | Time of death |
| `death_cause` | String(200) | NULL | Cause of death |
| `is_permadead` | Boolean | False | Cannot be revived |
| `total_kills` | Integer | 0 | Lifetime kills |
| `total_deaths` | Integer | 0 | Lifetime deaths |
| `total_absorbed` | Integer | 0 | Predatory Assimilation count |
| `nickname` | String(100) | "" | Display nickname |
| `training_stat` | String(30) | NULL | Which stat is training |
| `training_sessions_completed` | Integer | 0 | Training counter |

### New Tables

| Table | Columns | Relationships |
|-------|---------|---------------|
| `hero_abilities` | id, hero_id, ability_code, ability_name, ability_type, ability_domain, ability_level, is_active, metadata_json, acquired_at, source | Hero ↔ HeroAbility |
| `hero_history` | id, hero_id, event_type, event_data, created_at | Hero ↔ HeroHistory |
| `hero_body_parts` | id, hero_id, part_name, max_hp, current_hp, armor, status, updated_at | Hero ↔ HeroBodyPart |
| `hero_training_queue` | id, hero_id, training_type, training_target, current_level, target_level, started_at, ends_at, status, room_slot, efficiency | Hero ↔ HeroTrainingQueue |
| `hero_combat_stats` | id, hero_id, total_kills, boss_kills, arena_wins, battles, damage_dealt, damage_taken, last_battle_at | Hero ↔ HeroCombatStats (1:1) |
| `hero_titles` | id, hero_id, title_code, title_name, awarded_at, source | Hero ↔ HeroTitle |
| `hero_resurrection_events` | id, hero_id, artifact_used, revived_at, side_effects_json, condition_before, condition_after, hp_restored_to | Hero ↔ HeroResurrectionEvent |

---

## 3. NEW PYDANTIC SCHEMAS

| Schema | Type | Location |
|--------|------|----------|
| `HeroAbilityOut` | Response | `schemas/hero.py` |
| `HeroAbilityCreate` | Request | `schemas/hero.py` |
| `DerivedStats` | Computed | `schemas/hero.py` |
| `BodyPartOut` | Response | `schemas/hero.py` |
| `HeroBodyResponse` | Response | `schemas/hero.py` |
| `TrainingStartRequest` | Request | `schemas/hero.py` |
| `TrainingQueueOut` | Response | `schemas/hero.py` (has computed `time_remaining_seconds`) |
| `TrainingQueueResponse` | Response | `schemas/hero.py` |
| `CombatStatsOut` | Response | `schemas/hero.py` |
| `HeroTitleOut` | Response | `schemas/hero.py` |
| `HeroStoryResponse` | Response | `schemas/hero.py` |
| `ResurrectRequest` | Request | `schemas/hero.py` |
| `ResurrectionEventOut` | Response | `schemas/hero.py` |
| `HeroStatusResponse` | Response | `schemas/hero.py` |

### Schema Updates

- `HeroOut` now includes: `archetype`, `condition`, `resurrection_count`, `current_hp`, `max_hp_override`, `death_cause`, `dead_at`, `is_permadead`, `total_kills`, `total_deaths`, `total_absorbed`, `training_stat`, `training_sessions_completed`
- `HeroRead` extends `HeroOut` with `perks`, `abilities`, `derived_stats`
- `HeroCreate` updated with 7 primary stat fields + `archetype`

---

## 4. NEW API ENDPOINTS

| Method | Path | Response Model | Service | Status |
|--------|------|---------------|---------|--------|
| GET | `/{hero_id}/body` | `HeroBodyResponse` | HeroService (inline) | ✅ Working |
| POST | `/{hero_id}/training/start` | `TrainingQueueOut` | TrainingService | ✅ Working |
| POST | `/{hero_id}/training/cancel` | `TrainingQueueOut` | TrainingService | ✅ Working |
| POST | `/{hero_id}/training/claim` | `TrainingQueueOut` | TrainingService | ✅ Working |
| GET | `/{hero_id}/training` | `TrainingQueueResponse` | TrainingService | ✅ Working |
| POST | `/{hero_id}/resurrect` | `ResurrectionEventOut` | ResurrectionService | ✅ Working |
| GET | `/{hero_id}/status` | `HeroStatusResponse` | ResurrectionService | ✅ Working |

### Endpoints with NO route (schemas exist but unused)

| Schema | Expected Route | Status |
|--------|---------------|--------|
| `HeroStoryResponse` | `GET /{hero_id}/story` | ❌ **Missing endpoint** |
| `CombatStatsOut` | (part of story) | Unused directly |
| `HeroTitleOut` | (part of story) | Unused directly |
| `HeroAbilityCreate` | `POST /{hero_id}/abilities` | ❌ **Missing endpoint** |

---

## 5. SERVICE LAYER CHANGES

### New Services

| Service | File | Methods |
|---------|------|---------|
| `TrainingService` | `services/training.py` | `start_training`, `cancel_training`, `claim_training`, `get_training_queue` |
| `ResurrectionService` | `services/resurrection.py` | `resurrect`, `kill_hero`, `apply_damage`, `get_status` |

### Updated Services

| Service | Changes |
|---------|---------|
| `HeroService` | **No changes** — still contains old inline training (`start_training`, `complete_training`) |
| `hero_generation.py` | Now seeds: archetype, starter ability, body parts (6), combat stats (zeroed), history entry, derived HP |

### Helper Functions Added

| Function | File | Purpose |
|----------|------|---------|
| `compute_derived()` | `core/derived_stats.py` | Compute all 9 derived stats from primaries |
| `compute_derived_for_hero()` | `core/derived_stats.py` | Convenience wrapper for Hero ORM objects |
| `compute_training_minutes()` | `services/training.py` | Time formula: `base * (1 + level * 0.18)^1.35` |
| `condition_from_hp()` | `services/resurrection.py` | Map HP ratio → HeroCondition |
| `update_hero_condition()` | `services/resurrection.py` | Recalculate and set condition on hero |

---

## 6. INCONSISTENCIES FOUND

### 6.1 CRITICAL: `dead_until` Column Missing from Model

The `dead_until` column was **removed from the Hero model** but is still referenced in **4 files**:

| File | Lines | Usage |
|------|-------|-------|
| `services/combat.py` | 113, 115-116 | `hero.dead_until = now + timedelta(...)` / `hero.dead_until = None` |
| `services/raid.py` | 92, 102, 104 | `h.dead_until <= now` |
| `tasks/cleanup.py` | 33, 38 | `Hero.dead_until != None`, `hero.dead_until = None` |
| `routers/battle.py` | 33, 39, 62, 69, 92, 98 | `hero.dead_until` in error messages |

**Impact:** These will cause `AttributeError` at runtime. The old timed-death system (`is_dead` + `dead_until`) conflicts with the new condition-based death system (`condition` + `dead_at` + `death_cause` + `is_permadead`).

### 6.2 CRITICAL: Duplicate Training Systems

Two training systems now coexist:

| System | Location | Endpoints | Status |
|--------|----------|-----------|--------|
| **Old (inline)** | `HeroService.start_training()` / `complete_training()` | `POST /{id}/train`, `POST /{id}/complete_training` | Uses `is_training`, `training_end_time`, `training_stat` columns on Hero |
| **New (queue-based)** | `TrainingService` | `POST /{id}/training/start`, etc. | Uses `hero_training_queue` table |

Both are active and routed. The old system still writes to `is_training`, `training_end_time`, `training_stat` on the Hero model. The new system uses a separate queue table. They do **not interact** — a hero can be simultaneously training in both systems.

### 6.3 CRITICAL: Combat Service Uses Deprecated Stats

`services/combat.py` → `apply_perk_effects()` (line 122-147) builds a stat dict using:
```python
"speed": hero.speed,
"health": hero.health,
"defense": hero.defense,
"field_of_view": hero.field_of_view,
```

These are **deprecated columns** (nullable, defaulting to `None`). The combat service does not use the new derived stats system at all. `calculate_damage()` uses `hero.defense` directly.

Similarly, `routers/battle.py` line 179-180 returns `hero.defense` and `hero.health`.

### 6.4 Combat Service Does Not Set `condition`

`services/combat.py` line 112-116 sets `hero.is_dead = True` and `hero.dead_until` when a hero dies in combat, but:
- Does **not** set `hero.condition = HeroCondition.DEAD`
- Does **not** set `hero.dead_at`
- Does **not** set `hero.death_cause`
- Does **not** increment `hero.total_deaths`
- Does **not** create a `HeroHistory` entry for death
- Does **not** use `ResurrectionService.kill_hero()`

This means heroes killed in combat will have `is_dead=True` but `condition=HEALTHY`, creating an inconsistent state.

### 6.5 Stale `__table_args__` in Config File

`core/hero_config.py` line 235 contains:
```python
__table_args__ = {'extend_existing': True}
```
This is a module-level variable in a **config file**, not a model. It has no effect but is confusing — it looks like it was copy-pasted from an SQLAlchemy model by mistake.

### 6.6 `HeroStoryResponse` Schema Has No Endpoint

`CombatStatsOut`, `HeroTitleOut`, and `HeroStoryResponse` schemas exist in `schemas/hero.py` but there is **no API endpoint** that returns them. The hero's combat stats and titles are eager-loaded (via `selectin`) on every `GET /heroes/{id}` call, but `HeroRead` does not include them in its response.

### 6.7 `HeroRead` Does Not Expose combat_stats, titles, or body_parts

`HeroRead` extends `HeroOut` with only `perks`, `abilities`, and `derived_stats`. Despite `combat_stats`, `titles`, and `body_parts` being `selectin`-loaded on every hero fetch, they are **not serialized** in the response because `HeroRead` has no fields for them. This wastes database queries on every request.

### 6.8 `BaseService.return_user()` Uses Pydantic v1 `from_orm()`

`base_service.py` line 19: `return UserOut.from_orm(user)` — the new hero code uses Pydantic v2's `model_validate()`, but this old method persists. It will fail if `UserOut` doesn't have the v1 compatibility config.

### 6.9 Test Assertions Reference Removed Stats

`tests/test_hero_service.py` lines 46-49:
```python
assert attrs["speed"][0] <= hero.speed <= attrs["speed"][1]
assert attrs["health"][0] <= hero.health <= attrs["health"][1]
assert attrs["defense"][0] <= hero.defense <= attrs["defense"][1]
assert attrs["field_of_view"][0] <= hero.field_of_view <= attrs["field_of_view"][1]
```

These reference `speed`, `health`, `defense`, `field_of_view` in `ATTRIBUTE_RANGES` which **no longer exist** — `ATTRIBUTE_RANGES` now only has the 7 S.P.E.I.A.L.W stats.

Also `test_combat_service.py` line 30 creates heroes with `speed=10, health=50, defense=5, field_of_view=5`.

### 6.10 `revive_dead_heroes_task()` Uses `dead_until`

`tasks/cleanup.py` has an auto-revive task that queries `Hero.dead_until` — a column that no longer exists in the model. This task will crash on startup.

---

## 7. BROKEN OR RISKY AREAS

### 🔴 WILL CRASH AT RUNTIME

| Issue | File | Reason |
|-------|------|--------|
| `dead_until` not on model | `combat.py`, `raid.py`, `cleanup.py`, `battle.py` | `AttributeError` on any combat/raid/battle operation |
| Auto-revive task | `tasks/cleanup.py` | Queries non-existent column; crashes background task |
| Tests reference removed stats | `test_hero_service.py`, `test_combat_service.py` | Will fail on `speed`, `health`, `defense`, `field_of_view` |

### 🟡 LOGICAL INCONSISTENCIES (will not crash but produce wrong results)

| Issue | Impact |
|-------|--------|
| Duplicate training systems | Player confusion; hero can train in both systems simultaneously |
| Combat doesn't set `condition` | Dead heroes show `condition=HEALTHY` after combat death |
| Combat uses deprecated stat columns | All combat damage calculations use NULL values (speed, health, defense) |
| `selectin` on unused relationships | Wasted DB queries on every hero fetch (combat_stats, titles) |
| `HeroStoryResponse` unused | Dead code / incomplete feature |

### 🟢 MINOR / COSMETIC

| Issue | Impact |
|-------|--------|
| `__table_args__` in hero_config.py | No runtime effect; confusing code |
| `from_orm()` in base_service.py | Works if Pydantic v1 compat mode is on |
| `select` import unused in `resurrection.py` | Minor lint warning (`from sqlalchemy.future import select`) |

---

## 8. MIGRATION REQUIREMENTS

**No Alembic migrations exist for ANY of the refactored code.** The initial migration (`9a4b80142bda`) reflects the old schema with `speed`, `health`, `defense`, `field_of_view`, `dead_until` and without any new tables or columns.

### Required Migration Operations

#### A. New Columns on `heroes`

```
ADD COLUMN perception INTEGER NOT NULL DEFAULT 0
ADD COLUMN willpower INTEGER NOT NULL DEFAULT 0
ADD COLUMN archetype hero_archetype (nullable)
ADD COLUMN current_hp INTEGER NOT NULL DEFAULT 100
ADD COLUMN max_hp_override INTEGER (nullable)
ADD COLUMN condition hero_condition NOT NULL DEFAULT 'healthy'
ADD COLUMN resurrection_count INTEGER NOT NULL DEFAULT 0
ADD COLUMN nickname VARCHAR(100) NOT NULL DEFAULT ''
ADD COLUMN dead_at DATETIME (nullable)
ADD COLUMN death_cause VARCHAR(200) (nullable)
ADD COLUMN is_permadead BOOLEAN DEFAULT FALSE
ADD COLUMN total_kills INTEGER NOT NULL DEFAULT 0
ADD COLUMN total_deaths INTEGER NOT NULL DEFAULT 0
ADD COLUMN total_absorbed INTEGER NOT NULL DEFAULT 0
ADD COLUMN training_stat VARCHAR(30) (nullable)
ADD COLUMN training_sessions_completed INTEGER NOT NULL DEFAULT 0
ADD COLUMN created_at DATETIME NOT NULL DEFAULT now()
```

#### B. Column Modifications on `heroes`

```
ALTER COLUMN speed SET NULLABLE (currently NOT NULL → needs to be nullable for deprecation)
ALTER COLUMN health SET NULLABLE
ALTER COLUMN defense SET NULLABLE
ALTER COLUMN field_of_view SET NULLABLE
```

#### C. Column Removal Decision: `dead_until`

The `dead_until` column exists in the DB (from initial migration) but is **not in the model**. Either:
- **Option A:** Remove it from DB (requires updating combat/raid/battle code first)
- **Option B:** Re-add it to the model temporarily until combat is migrated

#### D. New Enum Types

```
CREATE TYPE hero_archetype AS ENUM (...)
CREATE TYPE ability_type AS ENUM (...)
CREATE TYPE ability_domain AS ENUM (...)
CREATE TYPE body_part_status AS ENUM (...)
CREATE TYPE training_type AS ENUM (...)
CREATE TYPE training_status AS ENUM (...)
CREATE TYPE hero_condition AS ENUM (...)
```

#### E. New Tables

```
CREATE TABLE hero_abilities (...)
CREATE TABLE hero_history (...)
CREATE TABLE hero_body_parts (...)
CREATE TABLE hero_training_queue (...)
CREATE TABLE hero_combat_stats (...)
CREATE TABLE hero_titles (...)
CREATE TABLE hero_resurrection_events (...)
```

#### F. New Indexes

```
ix_heroes_archetype (heroes.archetype)
ix_hero_abilities_type (hero_abilities.hero_id, ability_type)
ix_hero_history_hero_event (hero_history.hero_id, event_type)
ix_hero_body_parts_hero (hero_body_parts.hero_id)
ix_training_queue_hero_status (hero_training_queue.hero_id, status)
ix_hero_titles_hero (hero_titles.hero_id)
ix_resurrection_hero (hero_resurrection_events.hero_id)
```

---

## 9. WHAT IS SAFE TO KEEP

The following new code is **well-structured, internally consistent, and production-quality**:

| Component | Verdict | Notes |
|-----------|---------|-------|
| Hero model (`models/hero.py`) | ✅ Safe | Clean enum definitions, proper constraints, correct relationship declarations |
| All 7 new enum types | ✅ Safe | Consistent `(str, enum.Enum)` pattern, correct SAEnum usage |
| `hero_abilities` table + schema | ✅ Safe | Proper unique constraints, domain/type enums |
| `hero_body_parts` table + schema | ✅ Safe | Unique(hero_id, part_name), generation seeding |
| `hero_training_queue` table + schema + service | ✅ Safe | Well-designed queue with auto-requeue, time formulas, slot management |
| `hero_combat_stats` table + schema | ✅ Safe | 1:1 relationship, zeroed seeding at generation |
| `hero_titles` table + schema | ✅ Safe | Unique(hero_id, title_code) |
| `hero_resurrection_events` table + schema + service | ✅ Safe | Artifact validation, side effects, cap enforcement, history logging |
| `hero_history` table | ✅ Safe | Audit trail with JSON event_data |
| `derived_stats.py` | ✅ Safe | Clean formulas, no DB dependency, pure computation |
| `hero_config.py` (except `__table_args__`) | ✅ Safe | Well-organized config for all subsystems |
| `hero_generation.py` | ✅ Safe | Seeds all new subsystems correctly |
| `TrainingService` | ✅ Safe | Complete queue-based training with proper validation |
| `ResurrectionService` | ✅ Safe | Proper death/resurrection flow with history |
| All new API endpoints | ✅ Safe | Consistent patterns, proper auth, correct response models |
| `__init__.py` exports | ✅ Safe | All models and enums properly exported |

---

## 10. WHAT MUST BE FIXED BEFORE CONTINUING

### Priority 1 — BLOCKING (server will crash)

| # | Issue | Fix Required |
|---|-------|-------------|
| 1 | **`dead_until` column missing from model** | Either add `dead_until = Column(DateTime, nullable=True)` back to Hero model, or update `combat.py`, `raid.py`, `cleanup.py`, `battle.py` to use the new death system (`condition`, `dead_at`, `ResurrectionService.kill_hero()`) |
| 2 | **No Alembic migration for any new tables/columns/enums** | Generate a migration that adds all 17+ new columns, 7 enum types, 7 new tables, and their indexes |
| 3 | **`revive_dead_heroes_task()` in `tasks/cleanup.py`** | Remove or rewrite — the timed auto-revive concept conflicts with the new resurrection-requires-artifact design |

### Priority 2 — HIGH (broken functionality)

| # | Issue | Fix Required |
|---|-------|-------------|
| 4 | **Combat service uses deprecated stats** | Rewrite `combat.py` → `apply_perk_effects()` and `calculate_damage()` to use `compute_derived_for_hero()` instead of `hero.speed`, `hero.health`, `hero.defense`, `hero.field_of_view` |
| 5 | **Combat service doesn't set `condition`** | After combat death, call `ResurrectionService.kill_hero()` or manually set `condition=DEAD`, `dead_at`, `death_cause`, `total_deaths`, and create HeroHistory entry |
| 6 | **Duplicate training systems** | Remove old inline training from `HeroService` (`start_training()`, `complete_training()`) and old endpoints (`POST /{id}/train`, `POST /{id}/complete_training`), or deprecate them |
| 7 | **`battle.py` router uses deprecated stats** | Lines 179-180 return `hero.defense` and `hero.health` — update to use derived stats |

### Priority 3 — MEDIUM (incomplete features / waste)

| # | Issue | Fix Required |
|---|-------|-------------|
| 8 | **`HeroStoryResponse` has no endpoint** | Add `GET /{hero_id}/story` endpoint returning combat_stats + titles |
| 9 | **`HeroRead` doesn't expose combat_stats/titles/body_parts** | Either add these fields to `HeroRead` or change relationships to `lazy="noload"` to avoid wasted queries |
| 10 | **Tests reference removed attributes** | Update `test_hero_service.py` and `test_combat_service.py` to use new S.P.E.I.A.L.W stats |

### Priority 4 — LOW (cleanup)

| # | Issue | Fix Required |
|---|-------|-------------|
| 11 | **Stale `__table_args__` in `hero_config.py`** | Remove line 235: `__table_args__ = {'extend_existing': True}` |
| 12 | **Unused import in `resurrection.py`** | `from sqlalchemy.future import select` is imported but unused |
| 13 | **`BaseService.return_user()` uses `from_orm()`** | Update to `model_validate()` for Pydantic v2 consistency |
| 14 | **`HeroAbilityCreate` schema unused** | No endpoint to add abilities to a hero — either add one or remove the schema |

---

## SUMMARY

The refactor introduced a comprehensive, well-architected hero system spanning 7 new database tables, 7 enums, 15 schemas, 7 new API endpoints, 3 services, and a derived stats engine. The **new code is internally consistent and well-structured**.

However, the refactor was done **without updating the legacy combat, raid, and battle systems** that still depend on:
1. The removed `dead_until` column
2. The deprecated `speed`, `health`, `defense`, `field_of_view` columns
3. The old death model (timed auto-revive vs. artifact-based resurrection)
4. The old training model (inline vs. queue-based)

**The server cannot start and handle combat/raid/battle requests in its current state.** The most urgent fix is resolving the `dead_until` references and generating an Alembic migration for the 7 new tables and 17+ new columns.
