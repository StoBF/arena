# app/database/models/__init__.py
# This package initializer ensures all sub-modules (models) are imported,
# so that SQLAlchemy's metadata includes every model.
from app.database.base import Base
from .hero import Hero, HeroPerk
from .user import User
from .perk import Perk
from .resource import GameResource
from .craft import CraftRecipe, CraftRecipeResource, CraftedItem, CraftQueue
from .pve import MobTemplate, BossPerk, MobPerk, RaidArenaInstance, PvEBattleLog
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
from . import quantum_models  # noqa: F401 – registers quantum_* tables 