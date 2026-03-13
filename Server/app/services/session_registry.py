from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
import hashlib
import threading
import time

from app.utils.jwt import decode_access_token


@dataclass
class SessionRecord:
    user_id: int
    expires_at: float
    last_seen: float


class ActiveSessionRegistry:
    """In-memory registry of active authenticated access tokens.

    Design goals:
    - lightweight reads for frequent polling
    - no token plaintext storage (hash only)
    - automatic stale/expired cleanup
    """

    def __init__(self, prune_interval_seconds: float = 5.0) -> None:
        self._sessions: dict[str, SessionRecord] = {}
        self._lock = threading.Lock()
        self._last_prune_at: float = 0.0
        self._prune_interval_seconds = prune_interval_seconds

    def register_access_token(self, token: str) -> bool:
        payload = decode_access_token(token)
        if not payload:
            return False

        try:
            user_id = int(payload.get("sub"))
        except Exception:
            return False

        expires_at = self._extract_expiry_epoch(payload)
        now = time.time()
        token_key = self._hash_token(token)

        with self._lock:
            self._maybe_prune_locked(now)
            self._sessions[token_key] = SessionRecord(
                user_id=user_id,
                expires_at=expires_at,
                last_seen=now,
            )
        return True

    def touch_access_token(self, token: str) -> None:
        token_key = self._hash_token(token)
        now = time.time()
        with self._lock:
            self._maybe_prune_locked(now)
            if token_key in self._sessions:
                record = self._sessions[token_key]
                record.last_seen = now
                self._sessions[token_key] = record

    def unregister_access_token(self, token: str) -> None:
        token_key = self._hash_token(token)
        with self._lock:
            self._sessions.pop(token_key, None)

    def online_players_count(self) -> int:
        now = time.time()
        with self._lock:
            self._maybe_prune_locked(now)
            user_ids = {record.user_id for record in self._sessions.values()}
            return len(user_ids)

    def _maybe_prune_locked(self, now: float) -> None:
        if (now - self._last_prune_at) < self._prune_interval_seconds:
            return

        expired_keys = [
            key for key, record in self._sessions.items()
            if record.expires_at <= now
        ]
        for key in expired_keys:
            self._sessions.pop(key, None)
        self._last_prune_at = now

    @staticmethod
    def _hash_token(token: str) -> str:
        return hashlib.sha256(token.encode("utf-8")).hexdigest()

    @staticmethod
    def _extract_expiry_epoch(payload: dict) -> float:
        exp = payload.get("exp")
        if isinstance(exp, (int, float)):
            return float(exp)
        if isinstance(exp, str):
            try:
                return float(exp)
            except ValueError:
                pass
        if isinstance(exp, datetime):
            if exp.tzinfo is None:
                exp = exp.replace(tzinfo=timezone.utc)
            return exp.timestamp()

        # Fallback: short grace window if exp claim is unexpectedly absent.
        return time.time() + 60.0


active_session_registry = ActiveSessionRegistry()
