"""
Game Config Loader
===================
Завантажує game_config.yaml при старті сервера.
Надає типізований доступ до всіх ігрових параметрів.

Використання:
    from app.core.game_config import cfg

    duration = cfg.healing.durations_sec["injured"]["head"]  # 3600
    chance   = cfg.crafting.success_chances["phoenix_core"]   # 0.05
    packages = cfg.currency_shop.packages                      # list[dict]

Щоб застосувати зміни в game_config.yaml: перезапустіть сервер.
"""
from __future__ import annotations

import os
from pathlib import Path
from typing import Any, Dict, List, Optional

import yaml


_CONFIG_PATH = Path(__file__).parent.parent.parent / "config" / "game_config.yaml"


def _load() -> Dict[str, Any]:
    path = _CONFIG_PATH
    if not path.exists():
        raise FileNotFoundError(f"game_config.yaml not found at {path}")
    with open(path, encoding="utf-8") as f:
        return yaml.safe_load(f)


class _HeroGenCfg:
    def __init__(self, d: Dict):
        self.base_power_min_pct:   float = d["base_power_min_pct"]
        self.base_power_max_pct:   float = d["base_power_max_pct"]
        self.tier_boost:           Dict  = d["tier_boost"]
        self.hidden_trait_chance:  float = d["hidden_trait_chance"]
        self.legendary_trait_chance: float = d["legendary_trait_chance"]

    def tier_cost(self, tier: int) -> int:
        return self.tier_boost[f"tier{tier}"]["cost_gold"]

    def tier_power_boost(self, tier: int) -> float:
        return self.tier_boost[f"tier{tier}"]["power_boost_pct"]


class _ResurrectionCfg:
    def __init__(self, d: Dict):
        self.window_days:               int   = d["window_days"]
        self.base_success_chance:       float = d["base_success_chance"]
        self.post_revival_hp_pct:       float = d["post_revival_hp_pct"]
        self.base_materials:            Dict  = d["base_materials"]
        self.base_gold_cost:            int   = d["base_gold_cost"]
        self.cost_escalation_per_revival: float = d["cost_escalation_per_revival"]


class _HealingCfg:
    def __init__(self, d: Dict):
        self.durations_sec:         Dict  = d["durations_sec"]
        self.cost_gold:             Dict  = d["cost_gold"]
        self.speedup_gold_per_hour: int   = d["speedup_gold_per_hour"]

    def duration(self, severity: str, part: str) -> int:
        return self.durations_sec.get(severity, {}).get(part, 3600)

    def cost(self, severity: str, part: str) -> int:
        return self.cost_gold.get(severity, {}).get(part, 50)

    def speedup_cost(self, remaining_sec: float) -> int:
        """Gold cost to skip remaining_sec of heal time."""
        import math
        hours = math.ceil(remaining_sec / 3600)
        return hours * self.speedup_gold_per_hour


class _BettingCfg:
    def __init__(self, d: Dict):
        self.house_edge_pct: float = d["house_edge_pct"]
        self.min_bet_gold:   int   = d["min_bet_gold"]
        self.max_bet_gold:   int   = d["max_bet_gold"]


class _QuestsCfg:
    def __init__(self, d: Dict):
        self.daily_quest_count:          int   = d["daily_quest_count"]
        self.weekly_quest_count:         int   = d["weekly_quest_count"]
        self.streak_mult_per_7days:      float = d["streak_mult_per_7days"]
        self.login_bonus_per_7days_gold: int   = d["login_bonus_per_7days_gold"]


class _AllianceCfg:
    def __init__(self, d: Dict):
        self.max_clans:       int   = d["max_clans"]
        self.max_members:     int   = d["max_members"]
        self.upkeep_per_clan: int   = d["upkeep_per_clan"]
        self.size_income_penalty_pct: Dict[int, float] = {
            int(k): v for k, v in d["size_income_penalty_pct"].items()
        }
        thresholds = d["rank_xp_thresholds"]
        self.rank_xp_thresholds: Dict[str, int] = thresholds

    def size_penalty(self, num_clans: int) -> float:
        return self.size_income_penalty_pct.get(num_clans, 0.12)

    def weekly_upkeep(self, num_clans: int) -> int:
        return self.upkeep_per_clan * num_clans


class _RaidsCfg:
    def __init__(self, d: Dict):
        self.tier1_drop_chance:     float = d["tier1_drop_chance"]
        self.tier2_drop_chance:     float = d["tier2_drop_chance"]
        self.tier3_drop_chance:     float = d["tier3_drop_chance"]
        self.min_contribution_pct:  float = d["min_contribution_pct"]
        self.xp_base_scale:         float = d["xp_base_scale"]
        self.xp_resistance_factor_max: float = d["xp_resistance_factor_max"]
        self.xp_antiabuse_floor:    float = d["xp_antiabuse_floor"]


class _CraftingCfg:
    def __init__(self, d: Dict):
        self.queue_max_slots:       int   = d["queue_max_slots"]
        self.speedup_gold_per_hour: int   = d["speedup_gold_per_hour"]
        self.success_chances:       Dict  = d["success_chances"]
        self.recipes:               Dict  = d.get("recipes", {})

    def success_chance(self, recipe_code: str) -> float:
        return self.success_chances.get(recipe_code, 1.0)

    def recipe_materials(self, recipe_code: str) -> Dict[str, int]:
        return self.recipes.get(recipe_code, {})


class _CurrencyShopCfg:
    def __init__(self, d: Dict):
        self.packages: List[Dict] = d["packages"]

    def get_package(self, package_id: str) -> Optional[Dict]:
        return next((p for p in self.packages if p["id"] == package_id), None)


class _PvPCfg:
    def __init__(self, d: Dict):
        self.elo_k_factor:      int = d["elo_k_factor"]
        self.winner_gold_base:  int = d["winner_gold_base"]
        self.loser_gold_base:   int = d["loser_gold_base"]


class _AuctionCfg:
    def __init__(self, d: Dict):
        self.listing_fee_pct:          float = d["listing_fee_pct"]
        self.sale_commission_pct:      float = d["sale_commission_pct"]
        self.max_listing_duration_days: int  = d["max_listing_duration_days"]
        self.min_listing_duration_hours: int = d["min_listing_duration_hours"]


class _EconomyCfg:
    def __init__(self, d: Dict):
        self.daily_tax_on_idle_gold_pct: float = d["daily_tax_on_idle_gold_pct"]
        self.clan_treasury_sink_pct:     float = d["clan_treasury_sink_pct"]
        self.max_player_gold:            int   = d["max_player_gold"]


class GameConfig:
    """
    Typed wrapper around game_config.yaml.
    Singleton, loaded once at import time.
    """
    def __init__(self, data: Dict):
        self.hero_generation: _HeroGenCfg      = _HeroGenCfg(data["hero_generation"])
        self.resurrection:    _ResurrectionCfg = _ResurrectionCfg(data["resurrection"])
        self.healing:         _HealingCfg      = _HealingCfg(data["healing"])
        self.betting:         _BettingCfg      = _BettingCfg(data["betting"])
        self.quests:          _QuestsCfg       = _QuestsCfg(data["quests"])
        self.alliance:        _AllianceCfg     = _AllianceCfg(data["alliance"])
        self.raids:           _RaidsCfg        = _RaidsCfg(data["raids"])
        self.crafting:        _CraftingCfg     = _CraftingCfg(data["crafting"])
        self.currency_shop:   _CurrencyShopCfg = _CurrencyShopCfg(data["currency_shop"])
        self.pvp:             _PvPCfg          = _PvPCfg(data["pvp"])
        self.auction:         _AuctionCfg      = _AuctionCfg(data["auction"])
        self.economy:         _EconomyCfg      = _EconomyCfg(data["economy"])
        self._raw = data

    def reload(self) -> None:
        """Hot-reload config from disk (admin endpoint)."""
        data = _load()
        self.__init__(data)


# ── Singleton ─────────────────────────────────────────────────
cfg: GameConfig = GameConfig(_load())
