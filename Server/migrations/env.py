"""Alembic environment configuration for Hero Manager API.

Key features:
- Loads DATABASE_URL from app/.env (same source the application uses)
- Converts async driver (asyncpg / aiosqlite) → sync driver (psycopg2 / sqlite)
- Imports ALL SQLAlchemy models so autogenerate sees every table
- Safety filter: never emits DROP TABLE, DROP COLUMN, DROP INDEX, etc.
"""
from logging.config import fileConfig
import os
import sys
from pathlib import Path

from dotenv import load_dotenv
from sqlalchemy import engine_from_config, pool

from alembic import context

# ---------------------------------------------------------------------------
# Project bootstrap
# ---------------------------------------------------------------------------
# Ensure the Server/ directory is on sys.path so `app.*` imports work
# regardless of the cwd when the `alembic` CLI is invoked.
_server_root = str(Path(__file__).resolve().parents[1])
if _server_root not in sys.path:
    sys.path.insert(0, _server_root)

# Load .env from app/.env (same file the FastAPI application reads)
_env_path = Path(_server_root) / "app" / ".env"
load_dotenv(_env_path)

# ---------------------------------------------------------------------------
# Database URL – convert async → sync driver for Alembic
# ---------------------------------------------------------------------------
_raw_url = os.getenv("DATABASE_URL", "sqlite+aiosqlite:///:memory:")


def _to_sync_url(url: str) -> str:
    """Convert an async SQLAlchemy URL to a synchronous driver URL."""
    return (
        url
        .replace("postgresql+asyncpg://", "postgresql+psycopg2://")
        .replace("sqlite+aiosqlite://", "sqlite://")
    )


SYNC_DATABASE_URL = _to_sync_url(_raw_url)

# ---------------------------------------------------------------------------
# Model imports – register ALL tables with Base.metadata
# ---------------------------------------------------------------------------
# The models __init__.py imports every model module (hero, user, models,
# perk, craft, resource, pve, raid_boss, tournament, event, battle,
# currency_transaction, quantum_models).  Importing the package is enough.
import app.database.models  # noqa: F401 – side effect: registers all tables

from app.database.base import Base

# ---------------------------------------------------------------------------
# Alembic config
# ---------------------------------------------------------------------------
config = context.config

# Override the placeholder URL from alembic.ini with the real value
config.set_main_option("sqlalchemy.url", SYNC_DATABASE_URL)

# Set up Python logging from alembic.ini [loggers] section
if config.config_file_name is not None:
    fileConfig(config.config_file_name)

target_metadata = Base.metadata


# ---------------------------------------------------------------------------
# Safety filters – prevent destructive autogenerate operations
# ---------------------------------------------------------------------------
def include_object(object, name, type_, reflected, compare_to):
    """Exclude DB-only objects from the diff so Alembic never generates
    DROP TABLE, DROP COLUMN, DROP INDEX, or DROP CONSTRAINT.

    Parameters
    ----------
    object    – the SchemaItem (Table, Column, Index …)
    name      – name of the object
    type_     – "table", "column", "index", "unique_constraint",
                "foreign_key_constraint", "check_constraint"
    reflected – True if the object was reflected from the live database
    compare_to – the model-side counterpart, or None if there is none
    """
    if reflected and compare_to is None:
        # Object exists in the DB but not in models → skip it.
        return False
    return True


# ---------------------------------------------------------------------------
# Migration runners
# ---------------------------------------------------------------------------
def run_migrations_offline() -> None:
    """Run migrations in 'offline' mode (emit SQL without a live connection)."""
    context.configure(
        url=SYNC_DATABASE_URL,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
        include_object=include_object,
        compare_type=False,            # don't auto-change column types
        compare_server_default=False,   # don't diff server defaults
        render_as_batch=True,           # safer ALTER TABLE on SQLite
    )
    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    """Run migrations in 'online' mode (live DB connection)."""
    connectable = engine_from_config(
        config.get_section(config.config_ini_section, {}),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )

    with connectable.connect() as connection:
        context.configure(
            connection=connection,
            target_metadata=target_metadata,
            include_object=include_object,
            compare_type=False,
            compare_server_default=False,
            render_as_batch=True,
        )
        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
