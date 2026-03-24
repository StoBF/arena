"""
live_battle — real-time 5v5 MOBA simulation package.

Sub-modules
-----------
runtime      : Pure-Python dataclasses for in-memory battle state
arena        : Arena geometry, start zones, obstacle navigation
hero_ai      : Per-hero state machine and target-scoring AI
skill_resolver: Skill effect processing, control windows, kill-triggers
simulator    : Main tick-loop orchestrating all sub-systems
"""
from .simulator import LiveBattleSimulator, battle_registry

__all__ = ["LiveBattleSimulator", "battle_registry"]
