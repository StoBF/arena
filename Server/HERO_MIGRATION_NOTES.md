# Hero System Migration Notes

> Generated as part of the hero architecture refactor.  
> Review carefully before running `alembic revision --autogenerate`.

---

## Overview

The hero system has been refactored from a simple 9-stat RPG model to a complex architecture with:

- **7 primary stats** (S.P.E.I.A.L.W): strength, perception, endurance, intelligence, agility, luck, willpower
- **9 computed derived stats** (never stored): max_hp, initiative, accuracy, evasion, critical_chance, critical_resistance, armor_efficiency, recovery_speed, trauma_resistance
- **Archetypes** (7): VANGUARD, PREDATOR, PHANTOM, MYSTIC, WARDEN, APOSTLE, CHIMERA
- **Hero abilities** with type/domain classification
- **Hero history** audit trail
- **Permanent death** and kill-tracking systems
- **Training stat targeting** (train a specific primary stat)

---

## New Enum Types

Create these PostgreSQL enum types **before** adding columns that reference them:

```sql
CREATE TYPE hero_archetype AS ENUM ('VANGUARD','PREDATOR','PHANTOM','MYSTIC','WARDEN','APOSTLE','CHIMERA');
CREATE TYPE ability_type   AS ENUM ('OFFENSIVE','DEFENSIVE','UTILITY','SUPPORT','MUTATION');
CREATE TYPE ability_domain AS ENUM ('BIOMORPH','SPACE','PSIONIC','ELEMENTAL','SHADOW','BLOOD','ORDER','CHAOS');
```

---

## Changes to `heroes` Table

### New Columns

| Column                       | Type                    | Nullable | Default         | Notes                                   |
|------------------------------|-------------------------|----------|-----------------|------------------------------------------|
| `perception`                 | `INTEGER`               | NO       | `0`             | New primary stat                        |
| `willpower`                  | `INTEGER`               | NO       | `0`             | New primary stat                        |
| `archetype`                  | `hero_archetype` (enum) | YES      | `NULL`          | Existing heroes get NULL (untyped)      |
| `current_hp`                 | `INTEGER`               | NO       | `100`           | Tracks current hit points               |
| `max_hp_override`            | `INTEGER`               | YES      | `NULL`          | Manual cap; NULL = use derived          |
| `is_dead`                    | `BOOLEAN`               | NO       | `false`         | Death flag                              |
| `dead_at`                    | `TIMESTAMP`             | YES      | `NULL`          | Timestamp of death                      |
| `death_cause`                | `VARCHAR(200)`          | YES      | `NULL`          | e.g. 'killed_by:hero:42'               |
| `is_permadead`               | `BOOLEAN`               | NO       | `false`         | True = cannot be revived                |
| `total_kills`                | `INTEGER`               | NO       | `0`             | Lifetime kill count                     |
| `total_deaths`               | `INTEGER`               | NO       | `0`             | Lifetime death count                    |
| `total_absorbed`             | `INTEGER`               | NO       | `0`             | Predatory Assimilation trigger count    |
| `training_stat`              | `VARCHAR(30)`           | YES      | `NULL`          | Which primary stat is being trained     |
| `training_sessions_completed`| `INTEGER`               | NO       | `0`             | Total completed training sessions       |
| `created_at`                 | `TIMESTAMP`             | NO       | `now()`         | Hero creation timestamp                 |

### Deprecated Columns (make nullable, then drop)

These columns previously stored stats that are now **computed derived stats**:

| Column          | Action                                                  |
|-----------------|---------------------------------------------------------|
| `speed`         | `ALTER COLUMN speed DROP NOT NULL; SET DEFAULT NULL;`   |
| `health`        | `ALTER COLUMN health DROP NOT NULL; SET DEFAULT NULL;`  |
| `defense`       | `ALTER COLUMN defense DROP NOT NULL; SET DEFAULT NULL;` |
| `field_of_view` | `ALTER COLUMN field_of_view DROP NOT NULL; SET DEFAULT NULL;` |

> **Phase 1**: Make nullable + set default NULL (this migration).  
> **Phase 2**: After confirming no code reads them, `ALTER TABLE heroes DROP COLUMN ...` in a future migration.

### Renamed Columns

| Old Name      | New Name  | Notes                                    |
|---------------|-----------|------------------------------------------|
| `dead_until`  | `dead_at` | Semantic change: permanent death, not timer. If `dead_until` exists, rename it. |

### New Indexes

```sql
CREATE INDEX ix_heroes_archetype ON heroes (archetype);
-- ix_heroes_owner_deleted already existed; verify it's still present.
```

---

## Data Migration (existing heroes)

For heroes that already exist in the database:

```sql
-- Map old stats to new primary stats
UPDATE heroes SET
    perception = COALESCE(field_of_view, 5),
    willpower  = COALESCE(defense, 5),
    current_hp = COALESCE(health, 100)
WHERE perception = 0 AND willpower = 0;

-- Null out deprecated columns
UPDATE heroes SET
    speed = NULL,
    health = NULL,
    defense = NULL,
    field_of_view = NULL;
```

> Existing heroes will have `archetype = NULL` which is valid (legacy/untyped).

---

## New Tables

### `hero_abilities`

```sql
CREATE TABLE hero_abilities (
    id             SERIAL PRIMARY KEY,
    hero_id        INTEGER NOT NULL REFERENCES heroes(id) ON DELETE CASCADE,
    ability_code   VARCHAR(80) NOT NULL,
    ability_name   VARCHAR(120) NOT NULL,
    ability_type   ability_type NOT NULL,
    ability_domain ability_domain NOT NULL,
    ability_level  INTEGER NOT NULL DEFAULT 1,
    is_active      BOOLEAN NOT NULL DEFAULT true,
    metadata_json  TEXT,
    acquired_at    TIMESTAMP NOT NULL DEFAULT now(),
    source         VARCHAR(80),
    CONSTRAINT uq_hero_ability_code UNIQUE (hero_id, ability_code)
);

CREATE INDEX ix_hero_abilities_hero_id ON hero_abilities (hero_id);
CREATE INDEX ix_hero_abilities_type ON hero_abilities (hero_id, ability_type);
```

### `hero_history`

```sql
CREATE TABLE hero_history (
    id          SERIAL PRIMARY KEY,
    hero_id     INTEGER NOT NULL REFERENCES heroes(id) ON DELETE CASCADE,
    event_type  VARCHAR(50) NOT NULL,
    event_data  TEXT,
    created_at  TIMESTAMP NOT NULL DEFAULT now()
);

CREATE INDEX ix_hero_history_hero_id ON hero_history (hero_id);
CREATE INDEX ix_hero_history_hero_event ON hero_history (hero_id, event_type);
```

---

## Alembic Auto-generation Command

```bash
cd Server
alembic revision --autogenerate -m "hero_system_refactor_v2"
```

After generating, **manually review** the migration file:

1. Ensure enum types are created before columns that reference them.
2. Ensure `dead_until` → `dead_at` rename is handled correctly (Alembic may generate a drop + add instead of rename).
3. Verify the data migration SQL above is included as a `op.execute()` step.
4. Confirm deprecated columns are altered to nullable, not dropped.

---

## Files Changed

| File | Change |
|------|--------|
| `app/database/models/hero.py` | Hero model: new stats, archetype, death system, training_stat. New models: HeroAbility, HeroHistory. Enums: HeroArchetype, AbilityType, AbilityDomain. |
| `app/database/models/__init__.py` | Added HeroAbility, HeroHistory, HeroArchetype, AbilityType, AbilityDomain exports |
| `app/schemas/hero.py` | Complete rewrite: HeroAbilityOut, HeroAbilityCreate, DerivedStats, TrainRequest, updated HeroCreate/HeroOut/HeroRead/HeroGenerateRequest |
| `app/core/derived_stats.py` | **NEW** — PrimaryStats dataclass + compute_derived() for 9 derived stats |
| `app/core/hero_config.py` | ATTRIBUTE_RANGES for 7 stats, ARCHETYPE_STAT_WEIGHTS, ARCHETYPE_ABILITY_AFFINITY, ARCHETYPE_STARTER_ABILITIES, updated NICKNAME_MAP |
| `app/services/hero_generation.py` | Complete rewrite: archetype-weighted rolling, starter abilities, history entry |
| `app/services/hero.py` | Updated: get_total_stats, get_nickname, generate_and_store, get_hero_with_perks, start_training (accepts training_stat), complete_training (increments stat, records history) |
| `app/routers/hero.py` | Updated: generate endpoint uses model_validate/model_dump, train endpoint accepts TrainRequest body |

---

## Testing Checklist

- [ ] Run `alembic upgrade head` on a test database
- [ ] Generate a hero with each archetype — verify starter ability is created
- [ ] Verify derived stats computation matches expected formulas
- [ ] Start training with `training_stat = "strength"` — verify hero.training_stat is set
- [ ] Complete training — verify stat is incremented by +1 and history entry is created
- [ ] Verify dead heroes cannot train
- [ ] Check that existing heroes (NULL archetype) still serialize correctly
- [ ] Verify Redis cache invalidation fires on all mutations
