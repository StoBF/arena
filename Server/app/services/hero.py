# app/services/hero.py

from sqlalchemy.future import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import func
from datetime import datetime, timedelta
from fastapi import HTTPException
from app.database.models.hero import Hero, HeroPerk
from app.database.models.perk import Perk
from app.database.models.models import Auction
from app.database.models.user import User
from decimal import Decimal
from app.services.base_service import BaseService
from app.services.hero_generation import generate_hero
from app.schemas.hero import HeroCreate, HeroOut, HeroRead, HeroGenerateRequest, PerkOut
from app.auth import get_current_user
from app.database.session import get_session, AsyncSessionLocal
from app.core.hero_config import MAX_HEROES
import json
import asyncio
from app.services.auction import AuctionService
from app.services.message import MessageService
from fastapi import Depends
from sqlalchemy.orm import joinedload

class HeroService(BaseService):
    async def create_hero(self, name: str, owner_id: int):
        res = await self.session.execute(
            select(func.count()).select_from(Hero).where(Hero.owner_id == owner_id, Hero.is_deleted == False)
        )
        (count,) = res.one()
        if count >= MAX_HEROES:
            raise HTTPException(status_code=400, detail="Maximum heroes limit reached")
        hero = Hero(name=name, owner_id=owner_id, is_deleted=False)
        self.session.add(hero)
        await self.commit_or_rollback()
        await self.session.refresh(hero)
        return hero

    async def get_hero(
        self,
        hero_id: int,
        only_active: bool = True,
        load_perks: bool = False,
        load_equipment: bool = False,
    ):
        """Retrieve a hero optionally eager-loading relationships.

        The extra flags are useful in async code where lazy-loading would
        otherwise trigger I/O outside of a greenlet causing MissingGreenlet
        errors in tests.
        """
        query = select(Hero).where(Hero.id == hero_id)
        if only_active:
            query = query.where(Hero.is_deleted == False)
        if load_perks:
            query = query.options(joinedload(Hero.perks))
        if load_equipment:
            # import here to avoid circular import
            from app.database.models.models import Equipment

            query = query.options(
                joinedload(Hero.equipment_items).joinedload(Equipment.item)
            )
        result = await self.session.execute(query)
        return result.scalars().first()

    async def list_heroes(self, user_id: int = None, limit: int = 10, offset: int = 0):
        """
        List heroes with pagination support.
        
        Args:
            user_id: Filter by owner (optional)
            limit: Number of items to return (max 100)
            offset: Number of items to skip
            
        Returns:
            dict with items, total, limit, offset
        """
        from sqlalchemy.orm import joinedload
        
        # Enforce max limit
        if limit > 100:
            limit = 100
        if limit < 1:
            limit = 1
        if offset < 0:
            offset = 0
        
        # Get total count
        count_query = select(func.count()).select_from(Hero).where(Hero.is_deleted == False)
        if user_id is not None:
            count_query = count_query.where(Hero.owner_id == user_id)
        total_result = await self.session.execute(count_query)
        total = total_result.scalars().first() or 0
        
        # Get paginated items
        query = select(Hero).options(joinedload(Hero.perks), joinedload(Hero.equipment_items)).where(Hero.is_deleted == False)
        if user_id is not None:
            query = query.where(Hero.owner_id == user_id)
        query = query.limit(limit).offset(offset)
        result = await self.session.execute(query)
        items = result.unique().scalars().all()
        
        return {
            "items": items,
            "total": total,
            "limit": limit,
            "offset": offset
        }

    async def update_hero(self, hero_id: int, name: str, user_id: int):
        hero = await self.get_hero(hero_id)
        if not hero or hero.owner_id != user_id:
            raise HTTPException(status_code=404, detail="Hero not found")
        hero.name = name
        await self.commit_or_rollback()
        await self.session.refresh(hero)
        return hero

    async def delete_hero(self, hero_id: int, user_id: int):
        hero = await self.get_hero(hero_id, only_active=True)
        if not hero or hero.owner_id != user_id:
            raise HTTPException(status_code=404, detail="Hero not found or not yours")
        hero.is_deleted = True
        hero.deleted_at = datetime.utcnow()
        await self.commit_or_rollback()
        return hero

    async def restore_hero(self, hero_id: int, user_id: int):
        hero = await self.get_hero(hero_id, only_active=False)
        if not hero or not hero.is_deleted or hero.owner_id != user_id:
            raise HTTPException(status_code=404, detail="Hero not found or not yours")
        cutoff = datetime.utcnow() - timedelta(days=7)
        if not hero.deleted_at or hero.deleted_at < cutoff:
            raise HTTPException(status_code=404, detail="Restore period expired")
        hero.is_deleted = False
        hero.deleted_at = None
        await self.commit_or_rollback()
        return hero

    async def generate_and_store(self, owner_id: int, req: HeroGenerateRequest):
        """
        Generate and store hero with atomic transaction.
        CRITICAL: Combines user balance deduction and hero creation atomically.
        No partial commits: balance deducted AND hero created together, or neither.
        """
        async with self.session.begin():
            # Lock user row immediately to prevent concurrent hero creation
            user_result = await self.session.execute(
                select(User)
                .where(User.id == owner_id)
                .with_for_update()  # PESSIMISTIC LOCK ON USER
            )
            user = user_result.scalars().first()
            if not user:
                raise HTTPException(404, "User not found")
            
            # Check hero limit
            res = await self.session.execute(
                select(func.count()).select_from(Hero)
                .where(Hero.owner_id == owner_id, Hero.is_deleted == False)
            )
            (count,) = res.one()
            if count >= MAX_HEROES:
                raise HTTPException(400, "Maximum heroes limit reached")
            
            # Ensure currency is Decimal for safe arithmetic
            currency = Decimal(req.currency)
            # Generate hero data (generates attributes, perks, nickname)
            hero_data = await generate_hero(
                self.session,
                owner_id,
                req.generation,
                currency,
                req.locale
            )
            
            # Deduct currency from user balance (WITHIN TRANSACTION)
            # User is locked, so no race condition
            # Cost is 100 times the currency request (in Decimal for precision)
            cost = Decimal(100) * currency
            from app.services.accounting import AccountingService
            # adjust_balance will validate funds and record ledger entry
            await AccountingService(self.session).adjust_balance(owner_id, -cost, "hero_generation", reference_id=None, field="balance")
            
            # Create hero record (WITHIN TRANSACTION)
            new_hero = Hero(
                name=hero_data.name,
                owner_id=owner_id,
                generation=hero_data.generation,
                nickname=hero_data.nickname,
                strength=hero_data.strength,
                agility=hero_data.agility,
                intelligence=hero_data.intelligence,
                endurance=hero_data.endurance,
                speed=hero_data.speed,
                health=hero_data.health,
                defense=hero_data.defense,
                luck=hero_data.luck,
                field_of_view=hero_data.field_of_view,
                locale=hero_data.locale,
                is_deleted=False
            )
            self.session.add(new_hero)
            await self.session.flush()  # Ensure hero gets ID
            # Transaction auto-commits on success
        
        await self.session.refresh(new_hero)
        return new_hero

    async def send_offline_messages(self, user_id: int, websocket: str):
        from app.services.notification import NotificationService
        await NotificationService.send_offline_messages(user_id, websocket)

    async def add_experience(self, hero_id: int, amount: int):
        hero = await self.get_hero(hero_id)
        if not hero:
            raise HTTPException(status_code=404, detail="Hero not found")
        hero.experience += amount
        # Формула для наступного рівня: exp = 100 * (level ** 1.5)
        leveled_up = False
        while hero.experience >= int(100 * (hero.level ** 1.5)):
            hero.experience -= int(100 * (hero.level ** 1.5))
            hero.level += 1
            leveled_up = True
        await self.commit_or_rollback()
        await self.session.refresh(hero)
        return hero, leveled_up

    async def get_total_stats(self, hero_id: int):
        hero = await self.get_hero(hero_id)
        if not hero:
            raise HTTPException(status_code=404, detail="Hero not found")
        # Базові атрибути
        stats = {
            "strength": hero.strength,
            "agility": hero.agility,
            "intelligence": hero.intelligence,
            "endurance": hero.endurance,
            "speed": hero.speed,
            "health": hero.health,
            "defense": hero.defense,
            "luck": hero.luck,
            "field_of_view": hero.field_of_view,
        }
        # Додаємо бонуси від екіпіровки
        for eq in hero.equipment_items:
            item = eq.item
            stats["strength"] += getattr(item, "bonus_strength", 0)
            stats["agility"] += getattr(item, "bonus_agility", 0)
            stats["intelligence"] += getattr(item, "bonus_intelligence", 0)
            # Можна додати бонуси для інших атрибутів, якщо вони є у Item
        return stats

    def get_nickname(self, hero, perks=None, locale="en"):
        from app.core.hero_config import NICKNAME_MAP
        attrs = {
            "strength": hero.strength,
            "agility": hero.agility,
            "intelligence": hero.intelligence,
            "endurance": hero.endurance,
            "speed": hero.speed,
            "health": hero.health,
            "defense": hero.defense,
            "luck": hero.luck,
            "field_of_view": hero.field_of_view,
        }
        max_attr = max(attrs.items(), key=lambda x: x[1])
        trait_key = max_attr[0]
        if perks:
            max_perk = max(perks, key=lambda x: x[1]) if perks else (None, 0)
            if max_perk[1] >= 100 or (max_perk[1] > max_attr[1] + 10):
                trait_key = max_perk[0]
        return NICKNAME_MAP.get(locale, NICKNAME_MAP["en"]).get(trait_key, "the Hero")

    async def start_training(self, hero_id: int, duration_minutes: int = 60):
        hero = await self.get_hero(hero_id)
        if not hero:
            raise HTTPException(status_code=404, detail="Hero not found")
        if hero.is_training:
            raise HTTPException(status_code=400, detail="Hero is already training")
        hero.is_training = True
        hero.training_end_time = datetime.utcnow() + timedelta(minutes=duration_minutes)
        await self.commit_or_rollback()
        await self.session.refresh(hero)
        return hero

    async def complete_training(self, hero_id: int, xp_reward: int = 50):
        hero = await self.get_hero(hero_id)
        if not hero:
            raise HTTPException(status_code=404, detail="Hero not found")
        if not hero.is_training:
            raise HTTPException(status_code=400, detail="Hero is not in training")
        if not hero.training_end_time or hero.training_end_time > datetime.utcnow():
            raise HTTPException(status_code=400, detail="Training not finished yet")
        hero.is_training = False
        hero.training_end_time = None
        await self.add_experience(hero.id, xp_reward)
        await self.commit_or_rollback()
        await self.session.refresh(hero)
        return hero

    async def get_hero_with_perks(self, hero_id: int) -> HeroRead:
        # use helper that eagerly loads relationships so we can iterate safely
        hero = await self.get_hero(hero_id, load_perks=True)
        if not hero:
            raise HTTPException(status_code=404, detail="Hero not found")
        # perks list is already available thanks to joinedload
        perks = []
        for hp in hero.perks:
            perk = await self.session.get(Perk, hp.perk_id)
            if perk:
                perks.append(PerkOut(
                    id=perk.id,
                    name=perk.name,
                    description=perk.description,
                    effect_type=perk.effect_type,
                    max_level=perk.max_level,
                    modifiers=perk.modifiers or {},
                    affected=perk.affected or [],
                    perk_level=hp.perk_level
                ))
        hero_dict = HeroRead.model_validate(hero, from_attributes=True).model_dump()
        hero_dict["perks"] = perks
        return HeroRead(**hero_dict)

    async def upgrade_perk(self, hero_id: int, perk_id: int, user_id: int, max_level: int = 100):
        # first ensure the hero exists and belongs to the caller; we don't
        # need to load its perks here since we'll query them separately.
        hero = await self.get_hero(hero_id)
        if not hero or hero.owner_id != user_id:
            raise HTTPException(status_code=404, detail="Hero not found or not yours")
        # query specific hero perk row instead of iterating lazy-loaded list
        from app.database.models.hero import HeroPerk

        result = await self.session.execute(
            select(HeroPerk).where(
                HeroPerk.hero_id == hero_id,
                HeroPerk.perk_id == perk_id,
            )
        )
        perk = result.scalars().first()
        if not perk:
            raise HTTPException(status_code=404, detail="Perk not found for this hero")
        if perk.perk_level >= max_level:
            raise HTTPException(status_code=400, detail=f"Perk already at max level {max_level}")
        perk.perk_level += 1
        await self.commit_or_rollback()
        await self.session.refresh(perk)
        return perk
