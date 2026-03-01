# Alembic Migration System — Setup & Usage

## Overview

The Alembic migration system is fully configured and synchronized with all **42 SQLAlchemy model tables**. All migrations are **idempotent** and **production-safe** — they will not drop tables, columns, or change column types.

## Migration Chain

```
9a4b80142bda  Initial tables (42 tables, full schema)
  └─ 629b1354c75b  Placeholder (no-op)
       └─ 149a888a2550  Placeholder (no-op)
            └─ a1b2c3d4e5f6  Add request_id to bids (idempotent)
                 └─ b2c3d4e5f6a7  Add database indexes (idempotent)
                      └─ c3d4e5f6a7b8  Make username NOT NULL (idempotent)  ← HEAD
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

Creates all 42 tables and applies all subsequent migrations.

### Existing Database (tables already created by `create_all()`)

```bash
alembic stamp head
```

Marks the database as up-to-date **without** running any SQL. Use this once on databases that were bootstrapped with `Base.metadata.create_all()`.

### Check Current Version

```bash
alembic current
```

### Generate a New Migration

```bash
alembic revision --autogenerate -m "description of changes"
```

**Always review** the generated file before running. The safety filters prevent destructive ops in autogenerate, but manual review is still recommended.

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

## Files Modified During Setup

| File | Change |
|------|--------|
| `app/core/config.py` | `DATABASE_URL` now reads `os.getenv()` |
| `app/database/session.py` | Added missing model imports; conditional SQLite engine args |
| `app/database/models/__init__.py` | Added `Item`, `AutoBid`, `Announcement`, `quantum_models` imports |
| `alembic.ini` | Removed hardcoded URL; added date-based file template |
| `migrations/env.py` | Complete rewrite with safety filters + dotenv loading |
| `migrations/versions/9a4b80142bda_*.py` | Replaced `pass` with full 42-table schema |
| `migrations/versions/a1b2c3d4e5f6_*.py` | Added idempotency guard |
| `migrations/versions/b2c3d4e5f6a7_*.py` | Added idempotency guard |
| `migrations/versions/c3d4e5f6a7b8_*.py` | Added idempotency guard + SQLite dialect support |

## Production Deployment

1. **First time on existing DB**: `alembic stamp head`
2. **All subsequent deploys**: `alembic upgrade head`
3. **New schema changes**: modify models → `alembic revision --autogenerate -m "..."` → review → commit → deploy → `alembic upgrade head`
