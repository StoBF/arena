"""
Daily Quest Service
====================
Manages daily/weekly quest assignment, progress tracking, streak rewards.

Design principles:
- 3 daily quests + 1 weekly quest assigned per player per cycle
- Progress increments via event hooks from battle/craft/social routers
- Completion automatically triggers reward grant
- Streak bonus: +25% rewards per 7-day quest streak
- Login streak: daily login bonus escalates for 7-day streaks
"""
from __future__ import annotations

import random
from datetime import datetime, date, timedelta
from typing import Any, Dict, List, Optional

from sqlalchemy import select, and_
from sqlalchemy.ext.asyncio import AsyncSession

from app.database.models.game_systems import (
    DailyQuestTemplate, PlayerDailyQuest, PlayerStreak, QuestFrequency,
)
from app.services.reward_distributor import RewardDistributor


# ── Pre-seeded quest templates ─────────────────────────────────────────────────
STARTER_QUESTS = [
    # Combat
    {"code": "win_3_battles",      "title": "Victor",
     "description": "Win 3 battles today.",
     "category": "combat",  "frequency": "daily",
     "task": {"action": "win_battles", "target": 3},
     "rewards": [{"type": "currency", "amount": 200}], "xp_reward": 150},

    {"code": "fight_5_battles",    "title": "Veteran",
     "description": "Participate in 5 battles (any outcome).",
     "category": "combat",  "frequency": "daily",
     "task": {"action": "participate_battles", "target": 5},
     "rewards": [{"type": "currency", "amount": 150}], "xp_reward": 100},

    {"code": "kill_2_heroes",      "title": "Hero Slayer",
     "description": "Kill 2 enemy heroes in battle.",
     "category": "combat",  "frequency": "daily",
     "task": {"action": "kill_heroes", "target": 2},
     "rewards": [{"type": "currency", "amount": 250},
                 {"type": "resource", "code": "battle_trophy", "qty": 1}],
     "xp_reward": 200},

    {"code": "survive_3_battles",  "title": "Survivor",
     "description": "Win 3 battles without any hero dying.",
     "category": "combat",  "frequency": "daily",
     "task": {"action": "win_no_deaths", "target": 3},
     "rewards": [{"type": "currency", "amount": 300}], "xp_reward": 200},

    # Economy
    {"code": "craft_1_item",       "title": "Craftsman",
     "description": "Craft at least 1 item today.",
     "category": "economy", "frequency": "daily",
     "task": {"action": "craft_items", "target": 1},
     "rewards": [{"type": "currency", "amount": 180}], "xp_reward": 120},

    {"code": "place_3_bids",       "title": "Market Player",
     "description": "Place 3 bids in the auction.",
     "category": "economy", "frequency": "daily",
     "task": {"action": "place_bids", "target": 3},
     "rewards": [{"type": "currency", "amount": 120}], "xp_reward": 80},

    {"code": "trade_1_item",       "title": "Trader",
     "description": "List 1 item for sale in the auction.",
     "category": "economy", "frequency": "daily",
     "task": {"action": "list_auction", "target": 1},
     "rewards": [{"type": "currency", "amount": 100}], "xp_reward": 60},

    # Social
    {"code": "chat_message",       "title": "Social",
     "description": "Send 1 message in clan chat.",
     "category": "social",  "frequency": "daily",
     "task": {"action": "send_clan_chat", "target": 1},
     "rewards": [{"type": "currency", "amount": 80}], "xp_reward": 50},

    {"code": "attend_meetup",      "title": "Real World",
     "description": "Scan a clan meetup QR code and attend an offline gathering.",
     "category": "social",  "frequency": "weekly",
     "task": {"action": "attend_meetup", "target": 1},
     "rewards": [{"type": "currency", "amount": 1500},
                 {"type": "resource", "code": "meetup_token", "qty": 3}],
     "xp_reward": 1000},

    # Raiding
    {"code": "raid_participate",   "title": "Raider",
     "description": "Participate in a raid boss fight.",
     "category": "raiding", "frequency": "daily",
     "task": {"action": "participate_raid", "target": 1},
     "rewards": [{"type": "currency", "amount": 300}], "xp_reward": 250},

    {"code": "deal_raid_damage",   "title": "Damage Dealer",
     "description": "Deal 5000+ damage in raids today.",
     "category": "raiding", "frequency": "daily",
     "task": {"action": "raid_damage", "target": 5000},
     "rewards": [{"type": "currency", "amount": 350},
                 {"type": "resource", "code": "raid_essence", "qty": 1}],
     "xp_reward": 300},

    # Weekly
    {"code": "win_10_battles_week","title": "Conqueror",
     "description": "Win 10 battles this week.",
     "category": "combat",  "frequency": "weekly",
     "task": {"action": "win_battles", "target": 10},
     "rewards": [{"type": "currency", "amount": 1000},
                 {"type": "resource", "code": "prestige_shard", "qty": 2}],
     "xp_reward": 800},
]


class DailyQuestService:
    def __init__(self, db: AsyncSession):
        self.db = db

    @property
    def DAILY_QUEST_COUNT(self) -> int:
        from app.core.game_config import cfg
        return cfg.quests.daily_quest_count

    @property
    def WEEKLY_QUEST_COUNT(self) -> int:
        from app.core.game_config import cfg
        return cfg.quests.weekly_quest_count

    # ── Seeding ───────────────────────────────────────────────────────────────
    async def seed_templates(self) -> int:
        result = await self.db.execute(select(DailyQuestTemplate))
        existing = {t.code for t in result.scalars().all()}
        added = 0
        for q in STARTER_QUESTS:
            if q["code"] in existing:
                continue
            self.db.add(DailyQuestTemplate(
                code        = q["code"],
                title       = q["title"],
                description = q["description"],
                category    = q["category"],
                frequency   = q["frequency"],
                task        = q["task"],
                rewards     = q["rewards"],
                xp_reward   = q["xp_reward"],
            ))
            added += 1
        await self.db.commit()
        return added

    # ── Assign quests to a player ─────────────────────────────────────────────
    async def assign_daily_quests(self, user_id: int) -> List[PlayerDailyQuest]:
        today_key   = f"daily_{date.today().isoformat()}"
        now         = datetime.utcnow()
        week        = now.isocalendar()[1]
        weekly_key  = f"weekly_{now.year}_W{week:02d}"

        # Check if already assigned today
        result = await self.db.execute(
            select(PlayerDailyQuest).where(
                and_(PlayerDailyQuest.user_id   == user_id,
                     PlayerDailyQuest.cycle_key == today_key)
            )
        )
        if result.scalars().first():
            return await self._get_player_quests(user_id, today_key)

        # Pick daily quests
        result = await self.db.execute(
            select(DailyQuestTemplate).where(
                and_(DailyQuestTemplate.is_active  == True,
                     DailyQuestTemplate.frequency  == QuestFrequency.daily)
            )
        )
        daily_pool = list(result.scalars().all())
        chosen     = random.sample(daily_pool, min(self.DAILY_QUEST_COUNT, len(daily_pool)))

        for t in chosen:
            target = t.task.get("target", 1)
            self.db.add(PlayerDailyQuest(
                user_id     = user_id,
                template_id = t.id,
                cycle_key   = today_key,
                progress    = 0,
                target      = target,
            ))

        # Pick weekly quest (if not already assigned this week)
        result_w = await self.db.execute(
            select(PlayerDailyQuest).where(
                and_(PlayerDailyQuest.user_id   == user_id,
                     PlayerDailyQuest.cycle_key == weekly_key)
            )
        )
        if not result_w.scalars().first():
            result_wt = await self.db.execute(
                select(DailyQuestTemplate).where(
                    and_(DailyQuestTemplate.is_active == True,
                         DailyQuestTemplate.frequency == QuestFrequency.weekly)
                )
            )
            weekly_pool = list(result_wt.scalars().all())
            if weekly_pool:
                wt = random.choice(weekly_pool)
                self.db.add(PlayerDailyQuest(
                    user_id     = user_id,
                    template_id = wt.id,
                    cycle_key   = weekly_key,
                    progress    = 0,
                    target      = wt.task.get("target", 1),
                ))

        await self.db.commit()
        return await self._get_player_quests(user_id, today_key)

    # ── Track login streak ────────────────────────────────────────────────────
    async def track_login(self, user_id: int) -> PlayerStreak:
        streak = await self._get_or_create_streak(user_id)
        today  = date.today().isoformat()

        if streak.last_login_date == today:
            return streak   # already logged in today

        yesterday = (date.today() - timedelta(days=1)).isoformat()
        if streak.last_login_date == yesterday:
            streak.login_streak += 1
        else:
            streak.login_streak = 1

        streak.max_login_streak = max(streak.max_login_streak, streak.login_streak)
        streak.last_login_date  = today
        streak.updated_at       = datetime.utcnow()

        await self.db.commit()
        await self.db.refresh(streak)
        return streak

    # ── Increment quest progress ──────────────────────────────────────────────
    async def record_action(
        self, user_id: int, action: str, amount: int = 1
    ) -> List[PlayerDailyQuest]:
        """
        Called by battle/craft/social routers to increment matching quest progress.
        Returns list of quests that were completed by this action.
        """
        today_key  = f"daily_{date.today().isoformat()}"
        now        = datetime.utcnow()
        week       = now.isocalendar()[1]
        weekly_key = f"weekly_{now.year}_W{week:02d}"

        result = await self.db.execute(
            select(PlayerDailyQuest).where(
                and_(
                    PlayerDailyQuest.user_id  == user_id,
                    PlayerDailyQuest.cycle_key.in_([today_key, weekly_key]),
                    PlayerDailyQuest.completed == False,
                )
            )
        )
        quests = list(result.scalars().all())
        newly_completed = []

        for q in quests:
            if not q.template:
                from sqlalchemy.orm import selectinload
                result2 = await self.db.execute(
                    select(DailyQuestTemplate).where(
                        DailyQuestTemplate.id == q.template_id
                    )
                )
                q.template = result2.scalar_one_or_none()

            if not q.template:
                continue

            if q.template.task.get("action") == action:
                q.progress    = min(q.progress + amount, q.target)
                if q.progress >= q.target:
                    q.completed    = True
                    q.completed_at = datetime.utcnow()
                    newly_completed.append(q)

        await self.db.commit()
        return newly_completed

    # ── Claim reward ──────────────────────────────────────────────────────────
    async def claim_reward(
        self, user_id: int, quest_id: int
    ) -> Dict[str, Any]:
        q = await self.db.get(PlayerDailyQuest, quest_id)
        if not q or q.user_id != user_id:
            raise ValueError("Quest not found")
        if not q.completed:
            raise ValueError("Quest not completed yet")
        if q.claimed:
            raise ValueError("Reward already claimed")

        template = await self.db.get(DailyQuestTemplate, q.template_id)
        streak   = await self._get_or_create_streak(user_id)

        # Streak multiplier (from game_config.yaml → quests.streak_mult_per_7days)
        from app.core.game_config import cfg as _cfg
        streak_mult = 1.0 + (streak.quest_streak // 7) * (_cfg.quests.streak_mult_per_7days - 1.0)
        streak_mult = max(1.0, min(streak_mult, 3.0))

        # Apply rewards
        rewards_given = []
        for reward in template.rewards:
            if reward["type"] == "currency":
                amount = int(reward["amount"] * streak_mult)
                from app.database.models.user import User
                user = await self.db.get(User, user_id)
                if user:
                    user.balance = float(user.balance or 0) + amount
                rewards_given.append({"type": "currency", "amount": amount})
            else:
                rewards_given.append(reward)

        q.claimed    = True
        q.claimed_at = datetime.utcnow()
        streak.total_quests_completed += 1

        # Check if all daily quests done today → quest streak
        today_key = f"daily_{date.today().isoformat()}"
        result = await self.db.execute(
            select(PlayerDailyQuest).where(
                and_(PlayerDailyQuest.user_id   == user_id,
                     PlayerDailyQuest.cycle_key == today_key)
            )
        )
        today_quests = list(result.scalars().all())
        if all(x.completed for x in today_quests):
            today_str = date.today().isoformat()
            if streak.last_quest_date != today_str:
                yesterday = (date.today() - timedelta(days=1)).isoformat()
                if streak.last_quest_date == yesterday:
                    streak.quest_streak += 1
                else:
                    streak.quest_streak = 1
                streak.max_quest_streak = max(streak.max_quest_streak, streak.quest_streak)
                streak.last_quest_date  = today_str

        await self.db.commit()
        return {
            "rewards":       rewards_given,
            "xp":            int(template.xp_reward * streak_mult),
            "streak_mult":   streak_mult,
            "quest_streak":  streak.quest_streak,
        }

    # ── Helpers ───────────────────────────────────────────────────────────────
    async def _get_player_quests(
        self, user_id: int, cycle_key: str
    ) -> List[PlayerDailyQuest]:
        result = await self.db.execute(
            select(PlayerDailyQuest).where(
                and_(PlayerDailyQuest.user_id   == user_id,
                     PlayerDailyQuest.cycle_key == cycle_key)
            )
        )
        return list(result.scalars().all())

    async def _get_or_create_streak(self, user_id: int) -> PlayerStreak:
        result = await self.db.execute(
            select(PlayerStreak).where(PlayerStreak.user_id == user_id)
        )
        s = result.scalar_one_or_none()
        if not s:
            s = PlayerStreak(user_id=user_id)
            self.db.add(s)
            await self.db.flush()
        return s

    async def get_player_status(self, user_id: int) -> Dict:
        today_key  = f"daily_{date.today().isoformat()}"
        now        = datetime.utcnow()
        week       = now.isocalendar()[1]
        weekly_key = f"weekly_{now.year}_W{week:02d}"

        daily_result = await self.db.execute(
            select(PlayerDailyQuest).where(
                and_(PlayerDailyQuest.user_id   == user_id,
                     PlayerDailyQuest.cycle_key == today_key)
            )
        )
        weekly_result = await self.db.execute(
            select(PlayerDailyQuest).where(
                and_(PlayerDailyQuest.user_id   == user_id,
                     PlayerDailyQuest.cycle_key == weekly_key)
            )
        )
        streak = await self._get_or_create_streak(user_id)

        return {
            "daily_quests":  [_quest_dict(q) for q in daily_result.scalars().all()],
            "weekly_quests": [_quest_dict(q) for q in weekly_result.scalars().all()],
            "streak": {
                "login_streak": streak.login_streak,
                "quest_streak": streak.quest_streak,
                "total_completed": streak.total_quests_completed,
            },
        }


def _quest_dict(q: PlayerDailyQuest) -> Dict:
    return {
        "id":          q.id,
        "template_id": q.template_id,
        "cycle_key":   q.cycle_key,
        "progress":    q.progress,
        "target":      q.target,
        "completed":   q.completed,
        "claimed":     q.claimed,
        "completed_at": q.completed_at.isoformat() if q.completed_at else None,
    }
