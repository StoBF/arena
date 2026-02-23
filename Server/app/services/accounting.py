from decimal import Decimal
from sqlalchemy.future import select
from sqlalchemy import func
from app.services.base_service import BaseService
from app.database.models.user import User
from app.database.models.currency_transaction import CurrencyTransaction
from fastapi import HTTPException
from typing import Optional

class AccountingService(BaseService):
    async def adjust_balance(self, user_id: int, amount: Decimal, tx_type: str, reference_id: Optional[int] = None, field: str = "balance"):
        """
        Adjust user's `balance` or `reserved` and record a ledger entry.
        This helper **never** begins its own transaction; the caller should manage
        transactions.  It simply locks the user row, updates the field, and adds
        a `CurrencyTransaction` record.  Removing its own transaction prevents
        nested transaction errors in tests where a surrounding transaction is
        already active.
        """
        amount = Decimal(amount)

        # Lock user row
        result = await self.session.execute(
            select(User).where(User.id == user_id).with_for_update()
        )
        user = result.scalars().first()
        if not user:
            raise HTTPException(404, "User not found for balance adjustment")

        if field == "balance":
            new_val = (user.balance + amount).quantize(Decimal('0.01'))
            if new_val < 0:
                raise HTTPException(400, "Insufficient funds")
            user.balance = new_val
        elif field == "reserved":
            new_val = (user.reserved + amount).quantize(Decimal('0.01'))
            if new_val < 0:
                raise HTTPException(400, "Reserved balance cannot be negative")
            user.reserved = new_val
        else:
            raise HTTPException(400, f"Unknown field '{field}'")

        # Record transaction
        tx = CurrencyTransaction(
            user_id=user_id,
            amount=amount.quantize(Decimal('0.01')),
            type=tx_type,
            reference_id=reference_id
        )
        self.session.add(tx)
        await self.session.flush()
        return tx
