# Alembic Migration System — Setup & Usage

## Overview

A single migration (`0001`) creates **all tables** from the current
SQLAlchemy models via `Base.metadata.create_all()`.  The migration is
**idempotent** (`checkfirst=True`) and works on both PostgreSQL and
SQLite.

The `env.py` safety filter prevents autogenerate from ever emitting
`DROP TABLE`, `DROP COLUMN`, `DROP INDEX`, or `DROP CONSTRAINT`
operations.

## Migration Chain

```
0001 (head)  Initial schema — all tables from current models
```

## Configuration

| File | Purpose |
|------|---------|
| `alembic.ini` | Alembic settings; DB URL loaded dynamically from `.env` |
| `migrations/env.py` | Runtime config: model imports, safety filters, async→sync URL |
| `app/.env` | `DATABASE_URL=postgresql+asyncpg://...` |

### Safety Filters in `env.py`

- **No DROP TABLE** — existing DB-only tables are preserved
- **No DROP COLUMN** — existing DB-only columns are preserved
- **No type changes** — `compare_type=False`
- **No server default diffs** — `compare_server_default=False`
- **Batch mode** — `render_as_batch=True` for SQLite compatibility

---

## Commands

All commands assume you are in `Server/` with the venv activated.

### Fresh Database (no tables exist)

```bash
alembic upgrade head
```

Creates all tables defined in the current SQLAlchemy models.

### Existing Database (tables already created by `create_all()`)

```bash
alembic stamp head
```

Marks the database as up-to-date **without** running any SQL. Use this
once on databases that were bootstrapped with `Base.metadata.create_all()`.

### Full Reset (drop everything and recreate)

```bash
# PostgreSQL
psql -U <user> -d <dbname> -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;"
alembic upgrade head

# SQLite
rm data/hero_manager.db
alembic upgrade head
```

### Check Current Version

```bash
alembic current
```

### Generate a New Migration

```bash
alembic revision --autogenerate -m "description of changes"
```

**Always review** the generated file before running. The safety filters
prevent destructive ops in autogenerate, but manual review is still
recommended.

### Apply Pending Migrations

```bash
alembic upgrade head
```

### Roll Back One Step

```bash
alembic downgrade -1
```

### View Migration History

```bash
alembic history --verbose
```

---

## Production Deployment

1. **First time on existing DB**: `alembic stamp head`
2. **All subsequent deploys**: `alembic upgrade head`
3. **New schema changes**: modify models → `alembic revision --autogenerate -m "..."` → review → commit → deploy → `alembic upgrade head`
