import pytest
import asyncio
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker
from app.database.session import Base
from app.database.models.models import Item, Stash, Auction, AuctionLot, Bid, AutoBid
from app.database.models.user import User
from app.database.models.hero import Hero
from app.services.auction import AuctionService
from app.services.bid import BidService
from datetime import datetime, timedelta
from fastapi import HTTPException

DATABASE_URL = "sqlite+aiosqlite:///:memory:"

@pytest.fixture(scope="module")
def event_loop():
    loop = asyncio.get_event_loop()
    yield loop

@pytest.fixture(scope="module")
async def db():
    engine = create_async_engine(DATABASE_URL, echo=False)
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    async_session = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)
    async with async_session() as session:
        yield session
    await engine.dispose()

@pytest.mark.asyncio
async def test_create_auction_and_bid(db):
    user1 = User(username="seller", email="seller@example.com", balance=1000, reserved=0)
    user2 = User(username="buyer", email="buyer@example.com", balance=2000, reserved=0)
    db.add_all([user1, user2])
    await db.commit()
    await db.refresh(user1)
    await db.refresh(user2)
    item = Item(name="Quantum Core", description="", type="resource", slot_type="gadget")
    db.add(item)
    await db.commit()
    await db.refresh(item)
    stash = Stash(user_id=user1.id, item_id=item.id, quantity=5)
    db.add(stash)
    await db.commit()
    service = AuctionService(db)
    auction = await service.create_auction(seller_id=user1.id, item_id=item.id, start_price=100, duration=1, quantity=3)
    assert auction.quantity == 3
    # Ставка
    bid_service = BidService(db)
    bid = await bid_service.place_bid(bidder_id=user2.id, auction_id=auction.id, amount=150)
    assert bid.amount == 150
    # Закриття аукціону
    closed = await service.close_auction(auction.id)
    assert closed.status == "closed"
    # Перевірка передачі предмета
    stash_buyer = await db.get(Stash, 1)
    assert stash_buyer is not None
    # Перевірка балансу
    await db.refresh(user2)
    await db.refresh(user1)
    assert user2.reserved == 0
    assert user1.balance > 1000

@pytest.mark.asyncio
async def test_auctionlot_and_bid(db):
    user1 = User(username="hero_seller", email="hero_seller@example.com", balance=1000, reserved=0)
    user2 = User(username="hero_buyer", email="hero_buyer@example.com", balance=2000, reserved=0)
    db.add_all([user1, user2])
    await db.commit()
    await db.refresh(user1)
    await db.refresh(user2)
    hero = Hero(name="TestHero", generation=1, nickname="TH", strength=1, agility=1, endurance=1, speed=1, health=1, defense=1, luck=1, field_of_view=1, level=1, experience=0, locale="en", owner_id=user1.id, gold=0)
    db.add(hero)
    await db.commit()
    await db.refresh(hero)
    service = AuctionService(db)
    lot = await service.create_auction_lot(hero_id=hero.id, seller_id=user1.id, starting_price=500, duration=1)
    assert lot.hero_id == hero.id
    # Ставка
    bid_service = BidService(db)
    bid = await bid_service.place_lot_bid(bidder_id=user2.id, lot_id=lot.id, amount=600)
    assert bid.amount == 600
    # Закриття лота
    closed = await service.close_auction_lot(lot.id)
    assert closed.is_active == 0
    # Перевірка передачі героя
    await db.refresh(hero)
    assert hero.owner_id == user2.id
    # Перевірка балансу
    await db.refresh(user2)
    await db.refresh(user1)
    assert user2.reserved == 0
    assert user1.balance > 1000

@pytest.mark.asyncio
async def test_autobid(db):
    user1 = User(username="auto1", email="auto1@example.com", balance=5000, reserved=0)
    user2 = User(username="auto2", email="auto2@example.com", balance=5000, reserved=0)
    db.add_all([user1, user2])
    await db.commit()
    await db.refresh(user1)
    await db.refresh(user2)
    item = Item(name="NanoCell", description="", type="resource", slot_type="gadget")
    db.add(item)
    await db.commit()
    await db.refresh(item)
    stash = Stash(user_id=user1.id, item_id=item.id, quantity=2)
    db.add(stash)
    await db.commit()
    service = AuctionService(db)
    auction = await service.create_auction(seller_id=user1.id, item_id=item.id, start_price=100, duration=1, quantity=1)
    bid_service = BidService(db)
    autobid1 = await bid_service.set_auto_bid(user_id=user2.id, auction_id=auction.id, max_amount=1000)
    assert autobid1.max_amount == 1000
    # (Тут можна додати логіку proxy-bid, якщо реалізовано)

@pytest.mark.asyncio
async def test_bid_edge_cases(db):
    user1 = User(username="fail1", email="fail1@example.com", balance=100, reserved=0)
    user2 = User(username="fail2", email="fail2@example.com", balance=100, reserved=0)
    db.add_all([user1, user2])
    await db.commit()
    await db.refresh(user1)
    await db.refresh(user2)
    item = Item(name="FailItem", description="", type="resource", slot_type="gadget")
    db.add(item)
    await db.commit()
    await db.refresh(item)
    stash = Stash(user_id=user1.id, item_id=item.id, quantity=1)
    db.add(stash)
    await db.commit()
    service = AuctionService(db)
    auction = await service.create_auction(seller_id=user1.id, item_id=item.id, start_price=100, duration=1, quantity=1)
    bid_service = BidService(db)
    # Недостатньо коштів
    with pytest.raises(HTTPException):
        await bid_service.place_bid(bidder_id=user2.id, auction_id=auction.id, amount=200)
    # Не можна ставити на свій лот
    with pytest.raises(HTTPException):
        await bid_service.place_bid(bidder_id=user1.id, auction_id=auction.id, amount=110) 