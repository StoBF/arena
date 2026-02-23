from datetime import datetime, timedelta
from typing import List, Dict, Any
import random
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select  # for stash queries

from app.database.models.craft import CraftRecipe, CraftedItem, CraftQueue
from app.database.models.models import Stash
from app.core.config import settings
from app.database.models.craft import CraftRecipeResource

# Configurable constants, with sane defaults
MUTATION_CHANCE = getattr(settings, "CRAFT_MUTATION_CHANCE", 0.005)
DISENCHANT_RETURN_RATE = getattr(settings, "DISENCHANT_RETURN_RATE", 0.5)
EPIC_CRAFT_GRADE = getattr(settings, "EPIC_CRAFT_GRADE", 4)
LEGENDARY_CRAFT_GRADE = getattr(settings, "LEGENDARY_CRAFT_GRADE", 5)

class CraftService:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def get_recipes(self) -> List[CraftRecipe]:
        # use ORM select so we return `CraftRecipe` instances rather than raw
        # primary key values (table select returns scalar id by default)
        result = await self.db.execute(select(CraftRecipe))
        return result.scalars().all()

    async def can_craft(self, user_id: int, recipe: CraftRecipe | int) -> bool:
        # Ensure user has required ingredients.  Accept either full recipe object
        # or its id (some callers simply pass the integer).
        recipe_id = recipe.id if hasattr(recipe, "id") else recipe
        result = await self.db.execute(
            select(CraftRecipeResource).where(CraftRecipeResource.recipe_id == recipe_id)
        )
        comps = result.scalars().all()
        for comp in comps:
            stash_res = await self.db.execute(
                select(Stash).where(Stash.user_id == user_id, Stash.item_id == comp.resource_id)
            )
            stash = stash_res.scalars().first()
            if not stash or stash.quantity < comp.quantity:
                return False
        return True

    async def start_craft(self, user_id: int, recipe_id: int) -> CraftQueue:
        recipe = await self.db.get(CraftRecipe, recipe_id)
        if not recipe:
            raise ValueError("Recipe not found")
        # Grade limit check (daily cap for epic/legendary)
        if recipe.grade >= EPIC_CRAFT_GRADE:
            today = datetime.utcnow().date()
            count = await self.db.execute(
                CraftedItem.__table__
                .select()
                .where(
                    CraftedItem.user_id == user_id,
                    CraftedItem.grade == recipe.grade,
                    CraftedItem.created_at >= datetime(today.year, today.month, today.day)
                )
            )
            if len(count.scalars().all()) >= 1:
                raise ValueError("Daily craft limit reached for this grade")
        # Check and deduct ingredients
        if not await self.can_craft(user_id, recipe):
            raise ValueError("Insufficient materials")
        # reload components
        res = await self.db.execute(
            select(CraftRecipeResource).where(CraftRecipeResource.recipe_id == recipe.id)
        )
        comps = res.scalars().all()
        for comp in comps:
            stash_q = await self.db.execute(
                select(Stash).where(Stash.user_id == user_id, Stash.item_id == comp.resource_id)
            )
            stash = stash_q.scalars().first()
            stash.quantity -= comp.quantity
        # Enqueue
        now = datetime.utcnow()
        ready_at = now + timedelta(seconds=recipe.craft_time_sec)
        queue = CraftQueue(user_id=user_id, recipe_id=recipe_id, ready_at=ready_at)
        self.db.add(queue)
        await self.db.commit()
        return queue

    async def finish_craft(self, queue_id: int) -> CraftedItem:
        queue = await self.db.get(CraftQueue, queue_id)
        if not queue or queue.ready_at > datetime.utcnow():
            raise ValueError("Craft not ready")
        # Remove the finished craft job first
        await self.db.delete(queue)
        # Create the crafted item
        recipe = await self.db.get(CraftRecipe, queue.recipe_id)
        is_mutated = random.random() < MUTATION_CHANCE
        crafted = CraftedItem(
            user_id=queue.user_id,
            result_item_id=recipe.result_item_id,
            item_type=recipe.item_type,
            grade=recipe.grade,
            is_mutated=is_mutated,
            recipe_id=recipe.id
        )
        self.db.add(crafted)
        # Commit and refresh to load generated attributes
        await self.db.commit()
        await self.db.refresh(crafted)
        return crafted

    async def disenchant_item(self, user_id: int, crafted_id: int) -> Dict[str, Any]:
        crafted = await self.db.get(CraftedItem, crafted_id)
        if not crafted or crafted.user_id != user_id:
            raise ValueError("Item not found or unauthorized")
        recipe = await self.db.get(CraftRecipe, crafted.recipe_id)
        returned: Dict[str, Any] = {}
        # reload components
        comp_res = await self.db.execute(
            select(CraftRecipeResource).where(CraftRecipeResource.recipe_id == recipe.id)
        )
        comps = comp_res.scalars().all()
        for comp in comps:
            qty = int(comp.quantity * DISENCHANT_RETURN_RATE)
            if qty <= 0:
                continue
            stash_q = await self.db.execute(
                select(Stash).where(Stash.user_id == user_id, Stash.item_id == comp.resource_id)
            )
            stash = stash_q.scalars().first()
            if stash:
                stash.quantity += qty
            else:
                self.db.add(Stash(user_id=user_id, item_id=comp.resource_id, quantity=qty))
            returned[comp.resource_id] = qty
        await self.db.delete(crafted)
        await self.db.commit()
        return returned 