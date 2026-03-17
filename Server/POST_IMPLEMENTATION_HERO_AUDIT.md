# POST-IMPLEMENTATION HERO SYSTEM AUDIT

> **Generated:** 2025-07-25  
> **Scope:** All hero-system backend code — models, schemas, services, routers, config, migrations, tests  
> **Status:** READ-ONLY inspection. No code was modified.

---

## Table of Contents

1. [Models & Enums](#1-models--enums)
2. [Schemas (Pydantic)](#2-schemas-pydantic)
3. [Services (Business Logic)](#3-services-business-logic)
4. [Routers (API Endpoints)](#4-routers-api-endpoints)
5. [Config & Derived Stats](#5-config--derived-stats)
6. [Migrations (Alembic)](#6-migrations-alembic)
7. [Legacy Code Conflicts](#7-legacy-code-conflicts)
8. [Tests](#8-tests)
9. [Critical Issues & Runtime Risks](#9-critical-issues--runtime-risks)
10. [Recommendations & Action Plan](#10-recommendations--action-plan)

---

## 1. Models & Enums

**File:** `app/database/models/hero.py` (375 lines)

### 1.1 Enums Defined (7)

| Enum | Values | DB Constraint |
|------|--------|---------------|
| `HeroArchetype` | VANGUARD, PREDATOR, PHANTOM, MYSTIC, WARDEN, APOSTLE, CHIMERA | `create_constraint=True` |
| `AbilityType` | OFFENSIVE, DEFENSIVE, SUPPORT, UTILITY, MUTATION | `create_constraint=True` |
| `AbilityDomain` | ORDER, CHAOS, BLOOD, SHADOW, PSIONIC, BIOMORPH, ELEMENTAL, SPACE | `create_constraint=True` |
| `BodyPartStatus` | HEALTHY, INJURED, CRIPPLED, BROKEN, DESTROYED | `create_constraint=True` |
| `TrainingType` | ATTRIBUTE, DISCIPLINE, ABILITY | `create_constraint=True` |
| `TrainingStatus` | QUEUED, RUNNING, COMPLETED, CANCELLED | `create_constraint=True` |
| `HeroCondition` | HEALTHY, WOUNDED, SEVERELY_INJURED, CRIPPLED, DEAD | `create_constraint=True` |

All enums inherit from `(str, enum.Enum)`. **Status: GOOD.**

### 1.2 Models Defined (10)

| Model | Table | FK | Notes |
|-------|-------|-----|-------|
| `Hero` | `heroes` | `owner_id → users.id` | Primary entity. 40+ columns. |
| `HeroAbility` | `hero_abilities` | `hero_id → heroes.id CASCADE` | Unique `(hero_id, ability_code)` |
| `HeroHistory` | `hero_history` | `hero_id → heroes.id CASCADE` | Event log |
| `HeroBodyPart` | `hero_body_parts` | `hero_id → heroes.id CASCADE` | Unique `(hero_id, part_name)` |
| `HeroTrainingQueue` | `hero_training_queue` | `hero_id → heroes.id CASCADE` | Queue system |
| `HeroCombatStats` | `hero_combat_stats` | `hero_id → heroes.id CASCADE` | 1:1 relation |
| `HeroTitle` | `hero_titles` | `hero_id → heroes.id CASCADE` | Unique `(hero_id, title_code)` |
| `HeroResurrectionEvent` | `hero_resurrection_events` | `hero_id → heroes.id CASCADE` | Uses `create_constraint=False` for condition enums |
| `HeroPerk` | `hero_perks` | `hero_id → heroes.id CASCADE` | Unique `(hero_id, perk_id)` |
| *(All exports confirmed in `__init__.py`)* | | | |

### 1.3 Hero Model — Column Audit

**Primary stats (S.P.E.I.A.L.W):**
- `strength`, `perception`, `endurance`, `intelligence`, `agility`, `luck`, `willpower` — all `Integer, nullable=False` ✅

**Deprecated columns (still present):**
- `speed`, `health`, `defense`, `field_of_view` — all `Integer, nullable=True, default=None`
- Comment says "kept for migration, will be dropped" but no migration exists to drop them

**New columns (no migration):**
- `archetype` (Enum), `current_hp`, `max_hp_override`, `condition` (Enum), `resurrection_count`
- `dead_at`, `death_cause`, `is_permadead`
- `total_kills`, `total_deaths`, `total_absorbed`
- `training_stat`, `training_sessions_completed`
- `perception`, `willpower` (new primary stats)
- `created_at`

**Missing from model:** `dead_until` — was in original migration but has been replaced by `dead_at`. The column is NOT in the model. **This breaks 4 legacy files at runtime.**

### 1.4 Relationship Loading Strategies

| Relationship | Strategy | Loaded on `get_hero`? |
|-------------|----------|----------------------|
| `abilities` | `selectin` | ✅ Always |
| `body_parts` | `selectin` | ✅ Always |
| `combat_stats` | `selectin` | ✅ Always |
| `titles` | `selectin` | ✅ Always |
| `perks` | default (lazy) | Only via `load_perks=True` |
| `history_entries` | `noload` | ❌ Never (explicit only) |
| `training_queue` | `noload` | ❌ Never (explicit only) |
| `resurrection_events` | `noload` | ❌ Never (explicit only) |

**Issue:** `combat_stats`, `titles`, and `body_parts` are selectin-loaded on every hero fetch but `HeroRead` does NOT expose them (see §2.3).

### 1.5 Table Args

```python
__table_args__ = (
    CheckConstraint('gold >= 0', name='ck_hero_gold_non_negative'),
    Index('ix_heroes_owner_deleted', 'owner_id', 'is_deleted'),
    Index('ix_heroes_archetype', 'archetype'),
)
```

**Issue:** `ix_heroes_archetype` index is new and has no corresponding Alembic migration.

---

## 2. Schemas (Pydantic)

**File:** `app/schemas/hero.py` (280 lines)

### 2.1 Schema Inventory (22 schemas)

| Schema | Purpose | Status |
|--------|---------|--------|
| `PerkOut` | Perk display | ✅ |
| `HeroAbilityOut` | Ability display | ✅ `from_attributes=True` |
| `HeroAbilityCreate` | Ability creation | ✅ |
| `DerivedStats` | 9 computed stat fields | ✅ |
| `BodyPartOut` | Body part display | ✅ |
| `HeroBodyResponse` | Aggregate body state | ✅ |
| `HeroCreate` | Hero creation input | ✅ S.P.E.I.A.L.W stats |
| `HeroOut` | Flat hero output | ✅ All new fields present |
| `HeroRead` | Hero + relationships | ⚠️ Missing `combat_stats`, `titles`, `body_parts` |
| `HeroGenerateRequest` | Generation params | ✅ |
| `TrainRequest` | OLD training input | ⚠️ Legacy — should be deprecated |
| `TrainingStartRequest` | NEW training input | ✅ |
| `TrainingQueueOut` | Queue entry output | ✅ Includes `time_remaining_seconds` |
| `TrainingQueueResponse` | Queue aggregate | ✅ |
| `CombatStatsOut` | Combat stats output | ✅ |
| `HeroTitleOut` | Title output | ✅ |
| `HeroStoryResponse` | Combat + titles composite | ⚠️ No endpoint serves this |
| `PerkUpgradeRequest` | Perk upgrade input | ✅ |
| `ResurrectRequest` | Resurrection input | ✅ |
| `ResurrectionEventOut` | Resurrection event output | ✅ |
| `HeroStatusResponse` | Status aggregate | ✅ |

### 2.2 Issues Found

1. **`HeroRead` is incomplete** — exposes `perks`, `abilities`, `derived_stats`, but NOT `combat_stats`, `titles`, or `body_parts` despite those being selectin-loaded. Wasted eager loads.

2. **`HeroStoryResponse`** — defined at line 238 but no router endpoint returns it. Dead schema.

3. **`TrainRequest`** — old training schema still imported by router. Duplicate concept alongside `TrainingStartRequest`.

4. **`HeroAbilityOut.ability_level`** has `= 1` default but model column name is `level`, not `ability_level`. Relies on `from_attributes=True` auto-mapping — this will fail unless there's an alias or the attribute name matches. **Potential serialization bug**: the model column is `level` but schema field is `ability_level`. Needs `alias` or `@computed_field`.

---

## 3. Services (Business Logic)

### 3.1 `HeroService` (`app/services/hero.py`, 366 lines)

| Method | Status | Notes |
|--------|--------|-------|
| `create_hero()` | ✅ | Basic creation, no archetype/body parts |
| `get_hero()` | ✅ | Supports `load_perks`, `load_equipment` |
| `list_heroes()` | ✅ | Paginated, filters `is_deleted=False` |
| `update_hero()` | ✅ | Name change only |
| `delete_hero()` | ✅ | Soft delete |
| `restore_hero()` | ✅ | Soft restore |
| `generate_and_store()` | ✅ | Uses pessimistic lock, calls `hero_generation.generate_hero()` |
| `add_experience()` | ✅ | Level-up formula: `base_xp = int(100 * (1.5 ** (lvl - 1)))` |
| `get_total_stats()` | ✅ | Equipment bonuses + `compute_derived_for_hero` |
| `get_nickname()` | ✅ | Uses new PRIMARY_STATS + NICKNAME_MAP |
| **`start_training()`** | ❌ DUPLICATE | **OLD system** — writes `is_training`, `training_stat`, `training_end_time` on Hero |
| **`complete_training()`** | ❌ DUPLICATE | **OLD system** — increments stat +1, resets flags on Hero |
| `get_hero_with_perks()` | ✅ | Builds `HeroRead` with perks, abilities, derived_stats |
| `upgrade_perk()` | ✅ | +1 level, max 100 |

**Critical Issue — Duplicate Training:**
- `HeroService.start_training()` + `HeroService.complete_training()` = OLD inline training
- `TrainingService.start_training()` + `TrainingService.claim_training()` = NEW queue-based training
- Both are active, both have router endpoints, both modify hero stats
- They use different mechanisms (Hero columns vs HeroTrainingQueue table)

### 3.2 `TrainingService` (`app/services/training.py`, 331 lines)

| Method | Status | Notes |
|--------|--------|-------|
| `start_training()` | ✅ | Validates target, checks slots (max 3), creates queue entry |
| `cancel_training()` | ✅ | Marks CANCELLED + history |
| `claim_training()` | ✅ | Applies result, auto-requeues if target_level not reached |
| `get_training_queue()` | ✅ | Returns all active/completed entries with live `time_remaining` |
| `compute_training_minutes()` | ✅ | `base * (1 + level * 0.18)^1.35` |

**Validation coverage:** Checks hero ownership, hero not dead, slot availability, target validity against PRIMARY_STATS / DISCIPLINES / ability codes.

### 3.3 `ResurrectionService` (`app/services/resurrection.py`, 243 lines)

| Method | Status | Notes |
|--------|--------|-------|
| `resurrect()` | ✅ | Validates dead/permadead/cap, applies artifact effects (HP restore, stat penalty, side effects) |
| `kill_hero()` | ✅ | Sets condition=DEAD, dead_at, death_cause, is_dead=True, increments total_deaths |
| `apply_damage()` | ✅ | Reduces HP, updates condition, triggers death if HP<=0 |
| `get_status()` | ✅ | Returns HeroStatusResponse |
| `condition_from_hp()` | ✅ | Maps HP ratio → HeroCondition via CONDITION_THRESHOLDS |
| `update_hero_condition()` | ✅ | Recalculates condition, auto-marks dead if HP<=0 |

**Status: GOOD.** Clean implementation with proper transaction handling.

### 3.4 `hero_generation.py` (`app/services/hero_generation.py`, 203 lines)

| Step | Status | Notes |
|------|--------|-------|
| Archetype selection | ✅ | Weighted random (CHIMERA rarer) |
| Stat rolling | ✅ | `ATTRIBUTE_RANGES[gen] * ARCHETYPE_STAT_WEIGHTS` |
| Perk assignment | ✅ | Random from PERKS_LIST |
| Starter ability | ✅ | From ARCHETYPE_STARTER_ABILITIES |
| History entry | ✅ | "hero_created" event |
| Body parts | ✅ | 6 parts from BODY_PARTS config |
| Combat stats | ✅ | Initialized to 0s |
| HP initialization | ✅ | `current_hp = derived.max_hp` |

**Status: GOOD.** Complete hero generation pipeline.

### 3.5 `CombatService` (`app/services/combat.py`, ~165 lines)

**CRITICAL ISSUES:**

1. **Uses deprecated stats** (line 129-133):
   ```python
   "speed": hero.speed,       # nullable, may be None
   "health": hero.health,     # nullable, may be None → used as HP
   "defense": hero.defense,   # nullable, may be None
   "field_of_view": hero.field_of_view,  # nullable, may be None
   ```
   New heroes have these as `None`. Combat will crash with `TypeError` on arithmetic.

2. **Uses `dead_until` column** (lines 113, 116):
   ```python
   hero.dead_until = now + timedelta(minutes=RECOVERY_TIME_MINUTES)  # AttributeError
   hero.dead_until = None  # AttributeError
   ```
   Column does NOT exist on model. Runtime crash.

3. **Does NOT use new systems:**
   - No `condition` update
   - No `dead_at` / `death_cause` set
   - No `HeroCombatStats` update
   - No `ResurrectionService.kill_hero()` call
   - No body part damage
   - No derived stats (initiative, evasion, critical_chance, etc.)

4. **Commits inside loop** (line 115): `await self.db.commit()` inside `for f in fighters` — commits partial state on each iteration.

### 3.6 `RaidService` (`app/services/raid.py`, ~180 lines)

**Issues:**

1. **Uses `dead_until`** (line 104): `h.dead_until` — column doesn't exist. `is_team_defeated()` will crash.
2. **Uses `Hero.__table__.select()`** — raw table access, no ORM relationships loaded.
3. Does not interact with any new hero subsystem (conditions, body parts, combat stats).

---

## 4. Routers (API Endpoints)

**File:** `app/routers/hero.py` (278 lines)

### 4.1 Endpoint Inventory

| Method | Path | Schema | System |
|--------|------|--------|--------|
| GET | `/heroes/` | `HeroesPaginatedResponse` | ✅ Core |
| GET | `/heroes/{id}` | `HeroRead` | ✅ Core |
| POST | `/heroes/generate` | `HeroRead` | ✅ Generation |
| DELETE | `/heroes/{id}` | `HeroRead` | ✅ Core |
| POST | `/heroes/{id}/restore` | `HeroRead` | ✅ Core |
| GET | `/heroes/{id}/body` | `HeroBodyResponse` | ✅ Body parts |
| POST | `/heroes/{id}/train` | `HeroRead` | ⚠️ **OLD** training |
| POST | `/heroes/{id}/complete_training` | `HeroRead` | ⚠️ **OLD** training |
| POST | `/heroes/{id}/perks/upgrade` | `dict` | ✅ Perks |
| POST | `/heroes/{id}/training/start` | `TrainingQueueOut` | ✅ **NEW** training |
| POST | `/heroes/{id}/training/cancel` | `TrainingQueueOut` | ✅ **NEW** training |
| POST | `/heroes/{id}/training/claim` | `TrainingQueueOut` | ✅ **NEW** training |
| GET | `/heroes/{id}/training` | `TrainingQueueResponse` | ✅ **NEW** training |
| POST | `/heroes/{id}/resurrect` | `ResurrectionEventOut` | ✅ Resurrection |
| GET | `/heroes/{id}/status` | `HeroStatusResponse` | ✅ Status |

### 4.2 Issues Found

1. **Duplicate training endpoints:**
   - `POST /{id}/train` → OLD `HeroService.start_training()` (uses `TrainRequest`)
   - `POST /{id}/training/start` → NEW `TrainingService.start_training()` (uses `TrainingStartRequest`)
   - Both are live. Clients could use either, causing inconsistent state.

2. **Missing endpoints:**
   - No endpoint for `HeroStoryResponse` (combat stats + titles composite)
   - No endpoint to get hero history entries
   - No endpoint to manage abilities (add/remove/level up individual abilities)
   - No endpoint for hero titles (automatic awarding happens nowhere in code)

3. **`generate_hero` endpoint** manually constructs HeroRead with empty lists instead of using `get_hero_with_perks()`:
   ```python
   payload["perks"] = []
   payload["abilities"] = []
   payload["derived_stats"] = None
   ```
   This means the response omits the starter ability and derived stats that were just created.

4. **`/heroes/{id}` GET** returns raw hero object as `HeroRead` — does NOT call `get_hero_with_perks()`, so `perks`, `abilities`, and `derived_stats` are computed only if the ORM auto-populates them. `perks` has default lazy loading so will NOT be populated. Response will have empty `perks` list.

### 4.3 Battle Router Issues

**File:** `app/routers/battle.py` (263 lines)

| Line | Issue |
|------|-------|
| 33 | `hero.dead_until` → `AttributeError` (column removed from model) |
| 39 | `enemy.dead_until` → `AttributeError` |
| 62 | `h.dead_until` → `AttributeError` |
| 69 | `e.dead_until` → `AttributeError` |
| 92 | `h.dead_until` → `AttributeError` |
| 98 | `boss.dead_until` → `AttributeError` |
| 179 | `hero.defense` → returns `None` for new heroes (deprecated) |
| 180 | `hero.health` → returns `None` for new heroes (deprecated) |
| 253 | `h1.defense + h1.health` → `TypeError: unsupported operand type(s) for +: 'NoneType' and 'NoneType'` |

**All duel/team/raid endpoints in `battle.py` will crash on any hero created with the new system.**

---

## 5. Config & Derived Stats

### 5.1 `hero_config.py` (`app/core/hero_config.py`, 235 lines)

| Config Section | Status | Notes |
|---------------|--------|-------|
| `BASE_SUCCESS_RATES` | ✅ | Generation success rates (gen 1-10) |
| `PRIMARY_STATS` | ✅ | 7 stats: S.P.E.I.A.L.W |
| `ATTRIBUTE_RANGES` | ✅ | Gen 1-10 ranges for all 7 stats |
| `ARCHETYPE_STAT_WEIGHTS` | ✅ | 7 archetypes × 7 stats |
| `ARCHETYPE_ABILITY_AFFINITY` | ✅ | Domain lists per archetype |
| `ARCHETYPE_STARTER_ABILITIES` | ✅ | One ability per archetype |
| `BODY_PARTS` | ✅ | 6 parts with default HP |
| `TRAINING_BASE_TIME` | ✅ | 3 types: 15/30/45 min |
| `TRAINING_MAX_QUEUE_SLOTS` | ✅ | 3 slots max |
| `DISCIPLINES` | ✅ | 6 disciplines defined |
| `HERO_TITLES` | ✅ | 6 titles with thresholds |
| `CONDITION_THRESHOLDS` | ✅ | 5 condition tiers |
| `RESURRECTION_ARTIFACTS` | ✅ | 2 artifacts defined |
| `MAX_RESURRECTIONS` | ✅ | 3 max |
| `PERKS_LIST` | ✅ | 50 perks |
| `NICKNAME_MAP` | ✅ | 3 locales × 9 entries |

**Issue — Stale module-level variable:**
```python
__table_args__ = {'extend_existing': True}  # Line 235
```
This is a module-level dict, NOT inside any class. It has no effect in a config file. Likely copy-paste artifact — harmless but confusing.

### 5.2 `derived_stats.py` (`app/core/derived_stats.py`, ~125 lines)

| Derived Stat | Formula | Status |
|-------------|---------|--------|
| `max_hp` | `50 + END*8 + STR*2 + WIL*3 + LVL*5` | ✅ |
| `initiative` | `AGI*3 + PER*2 + LCK + LVL` | ✅ |
| `accuracy` | `PER*3 + AGI + INT*0.5 + LVL*0.5` | ✅ |
| `evasion` | `AGI*3 + PER + LCK*0.5 + LVL*0.5` | ✅ |
| `critical_chance` | `LCK*1.5 + PER*0.8 + AGI*0.3 + LVL*0.1` (cap 75%) | ✅ |
| `critical_resistance` | `WIL*1.2 + END*0.8 + LCK*0.3 + LVL*0.1` (cap 75%) | ✅ |
| `armor_efficiency` | `1 - exp(-0.005 * (END*2 + STR*1.5 + WIL*0.5))` | ✅ |
| `recovery_speed` | `END*0.6 + WIL*0.4 + INT*0.2 + LVL*0.1` | ✅ |
| `trauma_resistance` | `WIL*2.0 + END*1.0 + STR*0.5 + LVL*0.2` (cap 95%) | ✅ |

**Status: GOOD.** Clean implementation. `compute_derived_for_hero()` convenience wrapper handles ORM instances. Used correctly by `hero.py`, `hero_generation.py`, and `resurrection.py`.

**Not used by:** `combat.py`, `battle.py` — these still use raw deprecated stats.

---

## 6. Migrations (Alembic)

### 6.1 Existing Migrations

| Revision | Description |
|----------|-------------|
| `9a4b80142bda` | Initial tables — defines `heroes` with OLD schema |
| `629b1354c75b` | Add recipe_id to crafted items |
| `149a888a2550` | Empty (pass/pass) |
| `a1b2c3d4e5f6` | Add request_id to bids |
| `b2c3d4e5f6a7` | Add database indexes |
| `c3d4e5f6a7b8` | Make username not null |

### 6.2 Initial Migration (`heroes` table) vs Current Model

The initial migration defines the `heroes` table with:
```
id, name, generation, nickname, strength, agility, intelligence, endurance,
speed, health, defense, luck, field_of_view, gold, level, experience,
is_training, training_end_time, locale, owner_id, is_dead, dead_until,
is_on_auction, is_deleted, deleted_at
```

The **current model** has added **17 new columns** and changed **1 column** (`dead_until` → `dead_at`) that have **NO migration**:

| Column | Type | Status |
|--------|------|--------|
| `perception` | Integer NOT NULL | ❌ **No migration** |
| `willpower` | Integer NOT NULL | ❌ **No migration** |
| `archetype` | Enum (hero_archetype) | ❌ **No migration** |
| `current_hp` | Integer NOT NULL default 100 | ❌ **No migration** |
| `max_hp_override` | Integer nullable | ❌ **No migration** |
| `condition` | Enum (hero_condition) NOT NULL | ❌ **No migration** |
| `resurrection_count` | Integer NOT NULL default 0 | ❌ **No migration** |
| `dead_at` | DateTime nullable | ❌ **No migration** (replaces `dead_until`) |
| `death_cause` | String(200) nullable | ❌ **No migration** |
| `is_permadead` | Boolean default False | ❌ **No migration** |
| `total_kills` | Integer NOT NULL default 0 | ❌ **No migration** |
| `total_deaths` | Integer NOT NULL default 0 | ❌ **No migration** |
| `total_absorbed` | Integer NOT NULL default 0 | ❌ **No migration** |
| `training_stat` | String(30) nullable | ❌ **No migration** |
| `training_sessions_completed` | Integer NOT NULL default 0 | ❌ **No migration** |
| `created_at` | DateTime NOT NULL | ❌ **No migration** |

**Column to REMOVE:** `dead_until` (still in migration, removed from model)

### 6.3 New Tables with NO Migration (7)

| Table | Model | FK | Status |
|-------|-------|-----|--------|
| `hero_abilities` | `HeroAbility` | heroes.id CASCADE | ❌ **No migration** |
| `hero_history` | `HeroHistory` | heroes.id CASCADE | ❌ **No migration** |
| `hero_body_parts` | `HeroBodyPart` | heroes.id CASCADE | ❌ **No migration** |
| `hero_training_queue` | `HeroTrainingQueue` | heroes.id CASCADE | ❌ **No migration** |
| `hero_combat_stats` | `HeroCombatStats` | heroes.id CASCADE | ❌ **No migration** |
| `hero_titles` | `HeroTitle` | heroes.id CASCADE | ❌ **No migration** |
| `hero_resurrection_events` | `HeroResurrectionEvent` | heroes.id CASCADE | ❌ **No migration** |

### 6.4 New Enum Types with NO Migration (7)

| Enum Type | Used By |
|-----------|---------|
| `hero_archetype` | Hero.archetype |
| `ability_type` | HeroAbility.ability_type (CHECK) |
| `ability_domain` | HeroAbility.ability_domain (CHECK) |
| `bodypart_status` | HeroBodyPart.status (CHECK) |
| `training_type` | HeroTrainingQueue.training_type (CHECK) |
| `training_status` | HeroTrainingQueue.status (CHECK) |
| `hero_condition` | Hero.condition, HeroResurrectionEvent.condition_before/after |

### 6.5 New Index with NO Migration

- `ix_heroes_archetype` on `heroes.archetype`

**The database is completely out of sync with the model. Running `alembic revision --autogenerate` should detect all of these.**

---

## 7. Legacy Code Conflicts

### 7.1 `dead_until` References (Model column REMOVED)

| File | Lines | Code | Impact |
|------|-------|------|--------|
| `app/services/combat.py` | 113 | `hero.dead_until = now + timedelta(...)` | **AttributeError** at runtime |
| `app/services/combat.py` | 116 | `hero.dead_until = None` | **AttributeError** at runtime |
| `app/services/raid.py` | 92, 102, 104 | `h.dead_until` accessed | **AttributeError** at runtime |
| `app/routers/battle.py` | 33, 39, 62, 69, 92, 98 | `hero.dead_until` in error messages | **AttributeError** at runtime |
| `app/tasks/cleanup.py` | 33, 38 | `Hero.dead_until != None`, `hero.dead_until = None` | **SQLAlchemy error** (no column) |
| `tests/test_combat_service.py` | 47 | `hero1.dead_until = datetime(...)` | **AttributeError** in tests |
| `migrations/.../initial_tables.py` | 286 | `dead_until` column defined | Only in old DB schema |

### 7.2 Deprecated Stat References (columns are nullable, `None` for new heroes)

| File | Lines | Attributes | Impact |
|------|-------|-----------|--------|
| `app/services/combat.py` | 129-133 | `speed`, `health`, `defense`, `field_of_view` | **TypeError** (None in arithmetic) |
| `app/routers/battle.py` | 179-180 | `defense`, `health` | Returns `None` in API response |
| `app/routers/battle.py` | 253 | `defense + health` in prediction | **TypeError** (None + None) |
| `tests/test_combat_service.py` | 34-35 | Sets `speed`, `health`, `defense`, `field_of_view` | Tests pass by setting deprecated stats |
| `tests/test_hero_service.py` | 46-48 | Asserts `speed`, `health`, `defense`, `field_of_view` ranges | **FAIL** — ATTRIBUTE_RANGES no longer has these keys |

### 7.3 Duplicate Training Systems

| System | Entry Point | Mechanism | Storage |
|--------|-------------|-----------|---------|
| **OLD** | `POST /{id}/train` → `HeroService.start_training()` | Set `is_training=True`, `training_stat`, `training_end_time` on Hero | Hero columns |
| **OLD** | `POST /{id}/complete_training` → `HeroService.complete_training()` | Increment stat +1, reset flags | Hero columns |
| **NEW** | `POST /{id}/training/start` → `TrainingService.start_training()` | Create `HeroTrainingQueue` entry | Separate table |
| **NEW** | `POST /{id}/training/claim` → `TrainingService.claim_training()` | Apply result, auto-requeue | Separate table |

Both coexist. The OLD system still modifies hero stats directly. The NEW system uses the queue table. A hero could simultaneously be training via both systems.

### 7.4 Title Awarding — No Implementation

`HERO_TITLES` config defines 6 titles with field + threshold conditions (e.g., "total_kills >= 100" → "The Slayer"), but **no code anywhere** checks these thresholds and awards titles. The `HeroTitle` model and `HeroTitleOut` schema are ready, but the awarding logic is missing entirely.

---

## 8. Tests

### 8.1 `test_hero_service.py` (140 lines)

| Test | Status | Issues |
|------|--------|--------|
| `test_create_and_get_hero` | ⚠️ | Uses `create_hero()` which has no archetype/body parts |
| `test_generate_hero_with_all_attributes` | ❌ BROKEN | Asserts `speed`, `health`, `defense`, `field_of_view` ranges from `ATTRIBUTE_RANGES` — these keys no longer exist |
| `test_add_experience_and_level_up` | ✅ | Should work |
| `test_get_total_stats_with_equipment` | ⚠️ | Accesses `stats["strength"]` which now returns derived stats dict, not flat dict |
| `test_get_nickname_for_new_attributes` | ⚠️ | Sets deprecated `speed`, `health`, `defense`, `field_of_view` but tests nickname for `luck` — may work |
| `test_hero_training_flow` | ⚠️ | Tests OLD `start_training()` — no `training_stat` argument |
| `test_upgrade_perk` | ✅ | Should work |

**Line 112:** `test_hero_training_flow` calls `service.start_training(hero.id, duration_minutes=1)` — OLD signature expects `(hero_id, training_stat, duration_minutes)`. Missing `training_stat` arg. **Will fail.**

### 8.2 `test_combat_service.py` (~85 lines)

| Test | Status | Issues |
|------|--------|--------|
| `test_duel_basic` | ❌ BROKEN | Creates heroes with deprecated `speed`, `health`, `defense`, `field_of_view`. Sets `dead_until` (doesn't exist on model). Imports `revive_dead_heroes_task` which uses `dead_until`. |
| `test_perk_effects` | ❌ BROKEN | Same deprecated stats. Combat service will use them but the entire flow relies on `dead_until`. |

### 8.3 Missing Test Coverage

- No tests for `TrainingService` (new queue system)
- No tests for `ResurrectionService`
- No tests for `hero_generation.generate_hero()`
- No tests for `derived_stats.compute_derived()`
- No tests for body part damage
- No tests for hero condition transitions
- No tests for abilities

---

## 9. Critical Issues & Runtime Risks

### Severity: 🔴 CRITICAL (Runtime crash)

| # | Issue | Files Affected | Impact |
|---|-------|---------------|--------|
| C1 | `dead_until` column removed from model but referenced in 4 files | combat.py, raid.py, battle.py, cleanup.py | **AttributeError** on any battle/raid/cleanup |
| C2 | Deprecated stats (`speed`, `health`, `defense`, `field_of_view`) are `None` for new heroes but used in arithmetic | combat.py, battle.py | **TypeError** on combat with new heroes |
| C3 | **No Alembic migration** for 17 new columns, 7 new tables, 7 new enum types | All new subsystems | DB tables don't exist in production. All new features non-functional. |
| C4 | `HeroAbilityOut.ability_level` doesn't match model column name `level` | schemas/hero.py | Serialization may return default `1` instead of actual level |

### Severity: 🟠 HIGH (Functional bugs)

| # | Issue | Files Affected | Impact |
|---|-------|---------------|--------|
| H1 | Duplicate training systems (OLD + NEW) both active | hero.py, training.py, hero router | Conflicting state, confusing API |
| H2 | `generate_hero` endpoint returns empty perks/abilities/derived_stats | hero router L78-80 | Client doesn't see starter ability or stats after generation |
| H3 | `GET /heroes/{id}` doesn't populate perks (lazy loading) | hero router L63 | `HeroRead.perks` always empty |
| H4 | Title awarding logic not implemented | — | Titles never granted despite models/config being ready |
| H5 | `HeroRead` doesn't expose `combat_stats`, `titles`, `body_parts` | schemas/hero.py | Selectin-loaded data wasted; clients can't see these |
| H6 | Tests reference removed stats/columns | Both test files | All hero tests broken |

### Severity: 🟡 MEDIUM (Tech debt)

| # | Issue | Files Affected | Impact |
|---|-------|---------------|--------|
| M1 | `HeroStoryResponse` schema defined but no endpoint | schemas/hero.py | Dead code |
| M2 | `TrainRequest` schema still exists alongside `TrainingStartRequest` | schemas/hero.py | Confusing dual schemas |
| M3 | `__table_args__` stale variable in hero_config.py | hero_config.py L235 | No effect, confusing |
| M4 | `CombatService` commits inside loop | combat.py L115 | Partial state on error |
| M5 | No endpoint for history entries, ability management | hero router | Feature gaps |
| M6 | `cleanup.py` revive_dead_heroes_task uses timer-based revival, incompatible with new resurrection system | cleanup.py | Conceptual conflict |

---

## 10. Recommendations & Action Plan

### Phase 1: Database Sync (BLOCKING — Must Do First)

1. **Generate Alembic migration** for all 17 new columns, 7 new tables, 7 enum types, column rename (`dead_until` → `dead_at`), and new index (`ix_heroes_archetype`)
2. **Data migration step:** For existing heroes, set `perception` and `willpower` using legacy stat derivation (or defaults), compute `current_hp` from derived `max_hp`, set `condition = 'healthy'`, set `created_at = NOW()`
3. **Drop deprecated columns** (`speed`, `health`, `defense`, `field_of_view`) in a follow-up migration after legacy code is updated

### Phase 2: Fix Legacy Code (BLOCKING — Prevents Crashes)

4. **Update `combat.py`:**
   - Replace `dead_until` with `ResurrectionService.kill_hero()` calls
   - Replace deprecated stats with `compute_derived_for_hero()` or equivalent
   - Update `apply_perk_effects()` to use S.P.E.I.A.L.W
   - Use initiative for turn order, accuracy/evasion for hit calculation, etc.
   - Remove commit-per-hero loop

5. **Update `battle.py`:**
   - Replace all `hero.dead_until` references with `hero.dead_at` or condition checks
   - Replace `hero.defense` / `hero.health` with derived stat computation
   - Update predict endpoint to use derived stats

6. **Update `raid.py`:**
   - Replace `dead_until` in `is_team_defeated()` with `hero.is_dead` / `hero.condition`

7. **Update `cleanup.py`:**
   - Remove `revive_dead_heroes_task()` or convert it to work with the new resurrection system (no more timer-based auto-revive)

### Phase 3: Remove Duplicates & Fix Gaps

8. **Remove old training** from `HeroService` (delete `start_training()`, `complete_training()`) and their router endpoints (`/train`, `/complete_training`). Remove `TrainRequest` schema.

9. **Fix `HeroRead` schema:** Add optional `combat_stats: Optional[CombatStatsOut]`, `titles: List[HeroTitleOut]`, `body_parts: List[BodyPartOut]`

10. **Fix `generate_hero` endpoint:** Use `get_hero_with_perks()` or fully populate the response including starter ability and derived stats.

11. **Fix `GET /heroes/{id}`:** Either use `get_hero_with_perks()` or `selectinload(Hero.perks)` in the query.

12. **Fix `HeroAbilityOut`:** Rename `ability_level` to `level` or add `alias="level"` to match model column.

13. **Implement title awarding:** Add a check after combat/training/stat changes that evaluates `HERO_TITLES` thresholds against `HeroCombatStats` and creates `HeroTitle` entries.

14. **Add `HeroStoryResponse` endpoint** or remove the dead schema.

### Phase 4: Tests

15. **Fix `test_hero_service.py`:** Remove deprecated stat assertions, update training test to use new system, fix `test_generate_hero_with_all_attributes` for new ATTRIBUTE_RANGES keys.

16. **Fix `test_combat_service.py`:** Remove `dead_until` references, use new stat system.

17. **Add new tests for:** TrainingService, ResurrectionService, generate_hero, derived_stats, body parts, conditions, abilities.

---

## Appendix: File-by-File Summary

| File | Lines | Status | Critical Issues |
|------|-------|--------|-----------------|
| `app/database/models/hero.py` | 375 | ✅ Implemented | No migration for any changes |
| `app/database/models/__init__.py` | ~20 | ✅ Exports correct | — |
| `app/schemas/hero.py` | 280 | ⚠️ Mostly good | HeroRead incomplete, ability_level mismatch, dead schema |
| `app/services/hero.py` | 366 | ⚠️ Has duplicates | Old training must be removed |
| `app/services/hero_generation.py` | 203 | ✅ Good | — |
| `app/services/training.py` | 331 | ✅ Good | — |
| `app/services/resurrection.py` | 243 | ✅ Good | — |
| `app/services/combat.py` | ~165 | 🔴 Broken | dead_until, deprecated stats, no new system integration |
| `app/services/raid.py` | ~180 | 🔴 Broken | dead_until usage |
| `app/routers/hero.py` | 278 | ⚠️ Has issues | Duplicate training, generate response incomplete |
| `app/routers/battle.py` | 263 | 🔴 Broken | dead_until × 6, deprecated stats × 3 |
| `app/core/hero_config.py` | 235 | ✅ Good | Stale `__table_args__` (harmless) |
| `app/core/derived_stats.py` | ~125 | ✅ Good | Not used by combat/battle |
| `app/tasks/cleanup.py` | ~45 | 🔴 Broken | dead_until, conceptual conflict with resurrection |
| `tests/test_hero_service.py` | 140 | 🔴 Broken | Deprecated stat assertions, wrong training args |
| `tests/test_combat_service.py` | ~85 | 🔴 Broken | dead_until, deprecated stats |
| `migrations/versions/*` | 6 files | ❌ Missing | No migration for any new hero system changes |
