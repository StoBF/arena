"""
arena.py — Skirmish arena geometry and navigation helpers.

The arena is a flat 2D plane (X / Z axes).
No complex pathfinding — heroes move in straight lines, with simple obstacle
avoidance that nudges them around rectangular blockers.

Coordinate system
-----------------
  Team A spawns at z ≈ -20 (south)
  Team B spawns at z ≈ +20 (north)
  Centre is (0, 0)
  Arena runs roughly x: -25..+25 / z: -25..+25
"""
from __future__ import annotations

import math
import random
from dataclasses import dataclass, field
from typing import List, Optional, Tuple

from .runtime import Vec2

# ── Arena constants ───────────────────────────────────────────────────────────

ARENA_HALF_X = 25.0
ARENA_HALF_Z = 25.0

TEAM_A_SPAWN_Z = -20.0   # south
TEAM_B_SPAWN_Z =  20.0   # north
SPAWN_X_SPREAD =   3.0   # spacing between heroes on spawn line

# Preferred combat ranges per role (units from enemy)
ROLE_PREFERRED_RANGE = {
    "VANGUARD":   1.5,
    "STRIKER":    2.0,
    "CONTROLLER": 8.0,
    "SUPPORT":   10.0,
    "TRANSFER":   7.0,
}

# Role movement speed modifiers (base speed = hero.speed)
ROLE_SPEED_MOD = {
    "VANGUARD":   1.1,
    "STRIKER":    1.2,
    "CONTROLLER": 0.9,
    "SUPPORT":    0.85,
    "TRANSFER":   0.95,
}

# ── Obstacle definition ───────────────────────────────────────────────────────

@dataclass
class Rect2:
    """Axis-aligned rectangle obstacle (centre, half-extents)."""
    cx: float
    cz: float
    hw: float   # half-width  (X)
    hd: float   # half-depth  (Z)

    def contains(self, p: Vec2) -> bool:
        return abs(p.x - self.cx) < self.hw and abs(p.z - self.cz) < self.hd

    def closest_point(self, p: Vec2) -> Vec2:
        cx = max(self.cx - self.hw, min(p.x, self.cx + self.hw))
        cz = max(self.cz - self.hd, min(p.z, self.cz + self.hd))
        return Vec2(cx, cz)

# Skirmish map has 4 pillars / columns as obstacles
ARENA_OBSTACLES: List[Rect2] = [
    Rect2( 10.0,  10.0, 2.5, 2.5),
    Rect2(-10.0,  10.0, 2.5, 2.5),
    Rect2( 10.0, -10.0, 2.5, 2.5),
    Rect2(-10.0, -10.0, 2.5, 2.5),
]

# ── Spawn positions ───────────────────────────────────────────────────────────

def spawn_positions_team_a(n: int = 5) -> List[Vec2]:
    """Evenly spaced across the south spawn line."""
    return _spawn_line(TEAM_A_SPAWN_Z, n)

def spawn_positions_team_b(n: int = 5) -> List[Vec2]:
    """Evenly spaced across the north spawn line."""
    return _spawn_line(TEAM_B_SPAWN_Z, n)

def _spawn_line(z: float, n: int) -> List[Vec2]:
    if n == 1:
        return [Vec2(0.0, z)]
    half = (n - 1) * SPAWN_X_SPREAD / 2.0
    return [Vec2(-half + i * SPAWN_X_SPREAD, z) for i in range(n)]

# ── Preferred engagement positions ───────────────────────────────────────────

def desired_engagement_pos(
    attacker_pos: Vec2,
    target_pos:   Vec2,
    preferred_range: float,
) -> Vec2:
    """
    Return the point that is exactly `preferred_range` units from the target,
    on the line from attacker → target.  If attacker is already inside the
    preferred_range, return a position slightly behind (kite-back).
    """
    dist = attacker_pos.distance_to(target_pos)
    if dist < 0.01:
        return Vec2(attacker_pos.x + 0.1, attacker_pos.z)

    dx = target_pos.x - attacker_pos.x
    dz = target_pos.z - attacker_pos.z

    # Desired point = target - (preferred_range / dist) * direction
    ratio = preferred_range / dist
    px = target_pos.x - dx * ratio
    pz = target_pos.z - dz * ratio
    return clamp_to_arena(Vec2(px, pz))

def kite_position(attacker_pos: Vec2, target_pos: Vec2, retreat_dist: float = 4.0) -> Vec2:
    """Move away from target by retreat_dist units, clamped to arena."""
    dist = attacker_pos.distance_to(target_pos)
    if dist < 0.01:
        return Vec2(attacker_pos.x, attacker_pos.z - retreat_dist)
    dx = (attacker_pos.x - target_pos.x) / dist
    dz = (attacker_pos.z - target_pos.z) / dist
    return clamp_to_arena(Vec2(attacker_pos.x + dx * retreat_dist,
                               attacker_pos.z + dz * retreat_dist))

def retreat_position(hero_pos: Vec2, team_id: str) -> Vec2:
    """Move toward own team's back line."""
    safe_z = TEAM_A_SPAWN_Z + 4.0 if team_id == "A" else TEAM_B_SPAWN_Z - 4.0
    return clamp_to_arena(Vec2(hero_pos.x * 0.5, safe_z))

def jitter(pos: Vec2, radius: float = 0.4) -> Vec2:
    """Add small random displacement so heroes don't perfectly stack."""
    angle = random.uniform(0, 2 * math.pi)
    r = random.uniform(0, radius)
    return clamp_to_arena(Vec2(pos.x + math.cos(angle) * r,
                               pos.z + math.sin(angle) * r))

# ── Obstacle avoidance ────────────────────────────────────────────────────────

def navigate(from_pos: Vec2, to_pos: Vec2, step: float) -> Vec2:
    """
    Move one step from from_pos toward to_pos, steering around obstacles.
    Simple iterative steering — good enough for 10 tick/s.
    """
    next_pos = from_pos.move_toward(to_pos, step)
    for obs in ARENA_OBSTACLES:
        if obs.contains(next_pos):
            # Push out of obstacle
            closest = obs.closest_point(from_pos)
            dx = from_pos.x - closest.x
            dz = from_pos.z - closest.z
            norm = (dx * dx + dz * dz) ** 0.5 or 0.01
            side = Vec2(from_pos.x + (dz / norm) * step,
                        from_pos.z - (dx / norm) * step)
            next_pos = clamp_to_arena(side)
            break
    return next_pos

# ── Arena boundary ────────────────────────────────────────────────────────────

def clamp_to_arena(pos: Vec2) -> Vec2:
    return Vec2(
        max(-ARENA_HALF_X, min(pos.x, ARENA_HALF_X)),
        max(-ARENA_HALF_Z, min(pos.z, ARENA_HALF_Z)),
    )

def facing_angle(from_pos: Vec2, to_pos: Vec2) -> float:
    """Return angle in radians for hero to face target."""
    return math.atan2(to_pos.x - from_pos.x, to_pos.z - from_pos.z)
