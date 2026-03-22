"""
Tests for hero v2 system — generation config, combat stats, and actions.
These are pure-logic unit tests that do NOT require a database.
"""
import pytest
import random

from app.core.hero_config import (
    MAX_HEROES, HERO_ROLES, ROLE_STAT_WEIGHTS,
    CORE_STATS, MAX_GENERATION_LAYERS,
)
from app.core.generation_config import (
    LAYER_SUCCESS_RATES, GENERATION_VERSION,
    BASE_STAT_RANGE, LAYER_STAT_BONUS_PCT,
)
from app.core.derived_stats import CoreStats, compute_derived
from app.services.actions import (
    _derive_combat_stats, _get_stat, _to_int, _to_float,
    _equipment_bonus, FighterState, _dodge_chance, _compute_damage,
    _select_target, _make_seed,
)
from app.services.combat import _hero_stats, _equipment_bonus as combat_equip_bonus


# ═══════════════════════════════════════════════════════════════════
# Config / Constants
# ═══════════════════════════════════════════════════════════════════

class TestHeroConfig:
    def test_max_heroes_is_five(self):
        assert MAX_HEROES == 5

    def test_five_roles_defined(self):
        assert len(HERO_ROLES) == 5
        assert set(HERO_ROLES) == {"VANGUARD", "STRIKER", "CONTROLLER", "SUPPORT", "TRANSFER"}

    def test_role_stat_weights_cover_all_roles(self):
        for role in HERO_ROLES:
            assert role in ROLE_STAT_WEIGHTS, f"Missing weights for role {role}"
            weights = ROLE_STAT_WEIGHTS[role]
            # Every core stat must have a weight
            for stat in CORE_STATS:
                assert stat in weights, f"Role {role} missing weight for stat {stat}"
                assert weights[stat] > 0, f"Role {role} has non-positive weight for {stat}"

    def test_max_generation_layers(self):
        assert MAX_GENERATION_LAYERS == 10


class TestGenerationConfig:
    def test_layer_rates_descend(self):
        rates = [LAYER_SUCCESS_RATES[i] for i in range(1, 11)]
        for i in range(len(rates) - 1):
            assert rates[i] >= rates[i + 1], f"Layer {i+1} rate not >= layer {i+2} rate"

    def test_layer_1_always_succeeds(self):
        assert LAYER_SUCCESS_RATES[1] == 1.0

    def test_generation_version(self):
        assert GENERATION_VERSION >= 2

    def test_base_stat_ranges_exist(self):
        assert len(BASE_STAT_RANGE) > 0
        for stat, (lo, hi) in BASE_STAT_RANGE.items():
            assert lo <= hi, f"Stat {stat}: low {lo} > high {hi}"

    def test_per_layer_bonus_exists(self):
        assert len(LAYER_STAT_BONUS_PCT) > 0


# ═══════════════════════════════════════════════════════════════════
# Derived stats
# ═══════════════════════════════════════════════════════════════════

class TestDerivedStats:
    def test_derived_stats_from_defaults(self):
        core = CoreStats()
        ds = compute_derived(core)
        assert ds.max_hp > 0
        assert ds.evasion >= 0
        assert ds.critical_chance >= 0

    def test_higher_health_gives_more_max_hp(self):
        core_low = CoreStats(health=50)
        core_high = CoreStats(health=200)
        ds_low = compute_derived(core_low)
        ds_high = compute_derived(core_high)
        assert ds_high.max_hp > ds_low.max_hp


# ═══════════════════════════════════════════════════════════════════
# Actions helpers
# ═══════════════════════════════════════════════════════════════════

class TestActionsHelpers:
    def test_to_int(self):
        assert _to_int("42") == 42
        assert _to_int("bad", 7) == 7
        assert _to_int(None, 3) == 3

    def test_to_float(self):
        assert _to_float("3.14") == pytest.approx(3.14)
        assert _to_float("bad", 1.0) == 1.0

    def test_get_stat_from_dict(self):
        entity = {"stats": {"health": 200, "defense": 15}}
        assert _get_stat(entity, "health") == 200
        assert _get_stat(entity, "defense") == 15
        assert _get_stat(entity, "nonexistent", 99) == 99

    def test_get_stat_from_int(self):
        assert _get_stat(42, "health") == 100
        assert _get_stat(42, "defense") == 0

    def test_derive_combat_stats_from_dict(self):
        entity = {
            "stats": {
                "health": 100, "stamina": 80, "defense": 12,
                "speed": 15, "agility": 14, "luck": 7, "willpower": 6,
            }
        }
        cs = _derive_combat_stats(entity)
        assert cs["max_hp"] >= 50
        assert cs["attack_power"] > 0
        assert cs["defense_power"] > 0
        assert cs["speed"] == 15.0

    def test_equipment_bonus_dict_entity_returns_zero(self):
        assert _equipment_bonus({"id": 1}, "attack") == 0.0
        assert _equipment_bonus(42, "defense") == 0.0

    def test_make_seed_deterministic(self):
        s1 = _make_seed("a", 1, 2)
        s2 = _make_seed("a", 1, 2)
        s3 = _make_seed("b", 1, 2)
        assert s1 == s2
        assert s1 != s3

    def test_dodge_chance_bounded(self):
        low = FighterState(
            entity={}, owner_id=None, entity_id=1, team="A",
            max_hp=100, current_hp=100,
            stats={"agility": 0.0, "dodge_bonus": 0.0, "speed": 10.0,
                   "attack_power": 10.0, "defense_power": 5.0,
                   "max_hp": 100.0, "luck": 0.0},
        )
        assert 0.02 <= _dodge_chance(low) <= 0.45

        high = FighterState(
            entity={}, owner_id=None, entity_id=2, team="A",
            max_hp=100, current_hp=100,
            stats={"agility": 999.0, "dodge_bonus": 999.0, "speed": 10.0,
                   "attack_power": 10.0, "defense_power": 5.0,
                   "max_hp": 100.0, "luck": 0.0},
        )
        assert _dodge_chance(high) == pytest.approx(0.45)

    def test_select_target_picks_lowest_hp(self):
        rng = random.Random(42)
        t1 = FighterState(
            entity={}, owner_id=None, entity_id=1, team="B",
            max_hp=100, current_hp=50,
            stats={"speed": 10},
        )
        t2 = FighterState(
            entity={}, owner_id=None, entity_id=2, team="B",
            max_hp=100, current_hp=20,
            stats={"speed": 10},
        )
        target = _select_target([t1, t2], rng)
        assert target is not None
        assert target.entity_id == 2  # lowest HP


# ═══════════════════════════════════════════════════════════════════
# Combat service helpers
# ═══════════════════════════════════════════════════════════════════

class TestCombatHeroStats:
    def test_hero_stats_returns_defaults_when_stats_none(self):
        class FakeHero:
            stats = None
        result = _hero_stats(FakeHero())
        assert result["health"] == 100
        assert result["defense"] == 10
        assert "stamina" in result

    def test_hero_stats_reads_from_stats_obj(self):
        class FakeStats:
            health = 250
            stamina = 120
            defense = 30
            speed = 20
            agility = 18
            luck = 12
            willpower = 15
            vision = 14
        class FakeHero:
            stats = FakeStats()
        result = _hero_stats(FakeHero())
        assert result["health"] == 250
        assert result["stamina"] == 120
        assert result["willpower"] == 15

    def test_combat_equip_bonus_no_equipment(self):
        class FakeHero:
            equipment_items = []
        result = combat_equip_bonus(FakeHero())
        assert result == {}  # no equipment → empty dict
