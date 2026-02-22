#!/usr/bin/env python3
import asyncio
from app.database.session import AsyncSessionLocal
from app.database.models.models import TournamentTemplate, LeaderboardEntry
from app.services.tournaments import TournamentService

async def main():
    async with AsyncSessionLocal() as db:
        # Load all tournament templates
        result = await db.execute(TournamentTemplate.__table__.select())
        templates = result.scalars().all()

        for tmpl in templates:
            # Select top-rated players within rank range
            stmt = LeaderboardEntry.__table__\
                .select()\
                .order_by(LeaderboardEntry.rating.desc())\
                .limit(tmpl.max_participants)
            res2 = await db.execute(stmt)
            entries = res2.scalars().all()
            user_ids = [e.user_id for e in entries if tmpl.min_rank <= e.rating <= tmpl.max_participants]
            if not user_ids:
                continue
            # Create tournament instance
            await TournamentService(db).create_tournament(tmpl.id, user_ids)
            # Commit per template
            await db.commit()
        print("Tournaments scheduled for templates:", [t.id for t in templates])

if __name__ == "__main__":
    asyncio.run(main()) 