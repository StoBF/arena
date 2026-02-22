from sqlalchemy.future import select
from fastapi import HTTPException
from app.database.models.models import Equipment, Stash, Item, SlotType
from app.services.base_service import BaseService

class EquipmentService(BaseService):
    async def equip_item(self, hero_id: int, user_id: int, item_id: int, slot: SlotType):
        """
        Equip item to hero with atomic transaction.
        Handles auto-swap of old equipment atomically.
        """
        async with self.session.begin():
            # Lock stash entry to check availability
            stash_result = await self.session.execute(
                select(Stash)
                .where(Stash.user_id == user_id, Stash.item_id == item_id)
                .with_for_update()  # Lock stash
            )
            stash_entry = stash_result.scalars().first()
            if not stash_entry or stash_entry.quantity < 1:
                raise HTTPException(400, "Item not in user's stash")
            
            # Validate item properties
            item_result = await self.session.execute(
                select(Item).where(Item.id == item_id)
            )
            item = item_result.scalars().first()
            if not item or item.slot_type != slot:
                raise HTTPException(400, "Item cannot be equipped to this slot")
            
            # Check for existing equipment in slot (and lock if exists)
            old_eq_result = await self.session.execute(
                select(Equipment)
                .where(Equipment.hero_id == hero_id, Equipment.slot == slot)
                .with_for_update()  # Lock old equipment if exists
            )
            old_eq = old_eq_result.scalars().first()
            
            if old_eq:
                # Auto-swap: remove old equipment, return to stash
                old_item_id = old_eq.item_id
                await self.session.delete(old_eq)
                
                # Add old item back to stash (within transaction)
                old_stash_result = await self.session.execute(
                    select(Stash)
                    .where(Stash.user_id == user_id, Stash.item_id == old_item_id)
                    .with_for_update()  # Lock old stash entry
                )
                old_stash = old_stash_result.scalars().first()
                if old_stash:
                    old_stash.quantity += 1
                else:
                    self.session.add(Stash(user_id=user_id, item_id=old_item_id, quantity=1))
            
            # Reduce new item quantity or remove from stash (within transaction)
            if stash_entry.quantity > 1:
                stash_entry.quantity -= 1
            else:
                await self.session.delete(stash_entry)
            
            # Create new equipment record (within transaction)
            equipment = Equipment(hero_id=hero_id, item_id=item_id, slot=slot)
            self.session.add(equipment)
            await self.session.flush()
            # Transaction auto-commits
        
        await self.session.refresh(equipment)
        return equipment

    async def unequip_item(self, hero_id: int, user_id: int, slot: SlotType):
        """
        Unequip item from hero with atomic transaction.
        Ensures equipment and stash stay synchronized.
        """
        async with self.session.begin():
            # Lock equipment for the slot (if exists)
            equipment_result = await self.session.execute(
                select(Equipment)
                .where(Equipment.hero_id == hero_id, Equipment.slot == slot)
                .with_for_update()  # Lock equipment
            )
            equipment = equipment_result.scalars().first()
            if not equipment:
                raise HTTPException(404, "Nothing to unequip in this slot")
            
            item_id = equipment.item_id
            
            # Delete equipment (within transaction)
            await self.session.delete(equipment)
            
            # Return item to stash (within transaction)
            stash_result = await self.session.execute(
                select(Stash)
                .where(Stash.user_id == user_id, Stash.item_id == item_id)
                .with_for_update()  # Lock stash
            )
            stash_entry = stash_result.scalars().first()
            if stash_entry:
                stash_entry.quantity += 1
            else:
                self.session.add(Stash(user_id=user_id, item_id=item_id, quantity=1))
            # Transaction auto-commits
        
        return True

    async def get_equipment(self, hero_id: int):
        result = await self.session.execute(
            select(Equipment).where(Equipment.hero_id == hero_id)
        )
        return result.scalars().all()

    async def list_equipment(self, hero_ids: list):
        result = await self.session.execute(
            select(Equipment).where(Equipment.hero_id.in_(hero_ids))
        )
        return result.scalars().all() 