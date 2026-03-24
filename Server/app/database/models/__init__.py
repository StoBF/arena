# app/database/models/__init__.py
# This package initializer ensures all sub-modules (models) are imported,
# so that SQLAlchemy's metadata includes every model.
from app.database.base import Base
from .hero import (
    # ── Models ──────────────────────────────────────────────────────
    Hero, HeroStats, HeroGenerationLayer, HeroTag,
    SkillsCatalog, HeroSkill, HeroSkillEffect, HeroHiddenTrait,
    HeroBodyPart, HeroCombatStats, HeroTitle,
    HeroResurrectionEvent, HeroHistory,
    # ── Enums ───────────────────────────────────────────────────────
    HeroRole, SkillFamily, CastType, TargetType, TargetTeam,
    SkillSourceType, HeroCondition, BodyPartStatus,
)
from .user import User
from .perk import Perk
from .resource import GameResource
from .craft import CraftRecipe, CraftRecipeResource, CraftedItem, CraftQueue
from .pve import MobTemplate, RaidArenaInstance, PvEBattleLog
from .raid_boss import RaidBoss, RaidDropItem, RecipeDrop
from .tournament import TournamentTemplate, TournamentInstance
from .event import EventDefinition, EventInstance
from .currency_transaction import CurrencyTransaction
from .battle import BattleQueueEntry, BattleBet
from .models import (
    Item, Auction, AuctionLot, AutoBid, Bid, Announcement,
    ChatMessage, OfflineMessage, Equipment, Stash,
    PvPMatch, PvPBattleLog, LeaderboardEntry,
)
from .armor import ArmorItem, ArmorSetBonus, PlayerArmorInventory, ArmorSlot, ArmorSetType
from .battle_room import (
    BattleRoom, HeroOrder, BattleResult, PlayerResourceInventory,
    BattleRoomStatus, HeroStance,
)
from .clan import (
    Clan, ClanMember, ClanApplication, ClanActivityLog,
    ClanStorageItem, ClanStorageTransaction,
    ClanMeetup, ClanMeetupParticipant, ClanChatMessage,
    RaidTicket, RaidRegistration, RaidTournament, RaidTournamentMatch,
    ClanType, ClanMode, ClanRole, RecruitmentMode,
    ApplicationStatus, MeetupStatus, StorageAction, TicketOwnerType,
)
from .raid_v2 import (
    RaidBossTemplate, RaidBossSpawn, RaidBossProgress, RaidBossMutation,
    RaidBossPhase, RaidDropEntry,
    RaidRoom, RaidParticipant,
    RaidCoalition, RaidCoalitionClan,
    RaidAccessScore, RaidBattleLog, RaidContribution, RaidRewardRoll,
    RaidBossHistory,
)
from . import quantum_models  # noqa: F401 – registers quantum_* tables
from .game_systems import (
    DailyQuestTemplate, PlayerDailyQuest, PlayerStreak,
    BettingMarket, MatchBet,
    HeroHealOrder,
    ResurrectionAttempt,
    CurrencyPurchase,
    Alliance, AllianceMember, AllianceWarChest,
)