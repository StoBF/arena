import pytest
import asyncio
from decimal import Decimal
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker
from app.database.session import Base
from app.database.models.models import Item, Stash, Auction, AuctionLot, Bid, AutoBid
from app.database.models.user import User
from app.database.models.hero import Hero
from app.services.auction import AuctionService
from app.services.auction_lot import AuctionLotService
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
    user1 = User(username="seller", email="seller@example.com", balance=Decimal("1000"), reserved=Decimal("0"))
    user2 = User(username="buyer", email="buyer@example.com", balance=Decimal("2000"), reserved=Decimal("0"))
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
    auction = await service.create_auction(seller_id=user1.id, item_id=item.id, start_price=Decimal("100"), duration=1, quantity=3)
    assert auction.quantity == 3
    # duration clamp check: passing >24 should raise via validator
    with pytest.raises(Exception):
        await service.create_auction(seller_id=user1.id, item_id=item.id, start_price=Decimal("100"), duration=48, quantity=1)
    # Ставка
    bid_service = BidService(db)
    bid = await bid_service.place_bid(bidder_id=user2.id, auction_id=auction.id, amount=Decimal("150"))
    assert bid.amount == Decimal("150")
    # Закриття аукціону
    closed = await service.close_auction(auction.id)
    # status changed to the enum value FINISHED
    assert closed.status == "finished"
    # Перевірка передачі предмета
    stash_buyer = await db.get(Stash, 1)
    assert stash_buyer is not None
    # Перевірка балансу
    await db.refresh(user2)
    await db.refresh(user1)
    assert user2.reserved == Decimal("0")
    assert user1.balance > Decimal("1000")

@pytest.mark.asyncio
async def test_auctionlot_and_bid(db):
    user1 = User(username="hero_seller", email="hero_seller@example.com", balance=Decimal("1000"), reserved=Decimal("0"))
    user2 = User(username="hero_buyer", email="hero_buyer@example.com", balance=Decimal("2000"), reserved=Decimal("0"))
    db.add_all([user1, user2])
    await db.commit()
    await db.refresh(user1)
    await db.refresh(user2)
    hero = Hero(name="TestHero", generation=1, nickname="TH", strength=1, agility=1, endurance=1, speed=1, health=1, defense=1, luck=1, field_of_view=1, level=1, experience=0, locale="en", owner_id=user1.id, gold=Decimal("0"))
    db.add(hero)
    await db.commit()
    await db.refresh(hero)
    service = AuctionLotService(db)
    lot = await service.create_auction_lot(hero_id=hero.id, seller_id=user1.id, starting_price=Decimal("500"), duration=1)
    assert lot.hero_id == hero.id
    # Ставка
    bid_service = BidService(db)
    bid = await bid_service.place_lot_bid(bidder_id=user2.id, lot_id=lot.id, amount=Decimal("600"))
    assert bid.amount == Decimal("600")
    # clamp on lot duration
    with pytest.raises(Exception):
        await AuctionLotService(db).create_auction_lot(hero_id=hero.id, seller_id=user1.id, starting_price=Decimal("500"), duration=72)
    # Закриття лота
    closed = await service.close_auction_lot(lot.id)
    # auction lots also transition to finished when closed
    assert closed.status == "finished"
    # Перевірка передачі героя
    await db.refresh(hero)
    assert hero.owner_id == user2.id
    # Перевірка балансу
    await db.refresh(user2)
    await db.refresh(user1)
    assert user2.reserved == Decimal("0")
    assert user1.balance > Decimal("1000")

@pytest.mark.asyncio
async def test_autobid(db):
    user1 = User(username="auto1", email="auto1@example.com", balance=Decimal("5000"), reserved=Decimal("0"))
    user2 = User(username="auto2", email="auto2@example.com", balance=Decimal("5000"), reserved=Decimal("0"))
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
    auction = await service.create_auction(seller_id=user1.id, item_id=item.id, start_price=Decimal("100"), duration=1, quantity=1)
    bid_service = BidService(db)
    autobid1 = await bid_service.set_auto_bid(user_id=user2.id, auction_id=auction.id, max_amount=Decimal("1000"))
    assert autobid1.max_amount == Decimal("1000")
    # (Тут можна додати логіку proxy-bid, якщо реалізовано)

@pytest.mark.asyncio
async def test_bid_edge_cases(db):
    user1 = User(username="fail1", email="fail1@example.com", balance=Decimal("100"), reserved=Decimal("0"))
    user2 = User(username="fail2", email="fail2@example.com", balance=Decimal("100"), reserved=Decimal("0"))
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
    auction = await service.create_auction(seller_id=user1.id, item_id=item.id, start_price=Decimal("100"), duration=1, quantity=1)
    bid_service = BidService(db)
    # Недостатньо коштів
    with pytest.raises(HTTPException):
        await bid_service.place_bid(bidder_id=user2.id, auction_id=auction.id, amount=Decimal("200"))
    # Не можна ставити на свій лот
    with pytest.raises(HTTPException):
        await bid_service.place_bid(bidder_id=user1.id, auction_id=auction.id, amount=Decimal("110")) 

@pytest.mark.asyncio
async def test_cache_event_emitted(db):
    # verify that creating/cancelling auctions fires the cache invalidation event
    from app.core.events import subscribe, clear_subscribers
    keys = []
    async def handler(key):
        keys.append(key)

    clear_subscribers()
    subscribe("cache_invalidate", handler)

    user = User(username="cacheuser", email="cache@example.com", balance=Decimal("1000"), reserved=Decimal("0"))
    db.add(user)
    await db.commit()
    await db.refresh(user)
    item = Item(name="CacheItem", description="", type="resource", slot_type="gadget")
    db.add(item)
    await db.commit()
    await db.refresh(item)
    stash = Stash(user_id=user.id, item_id=item.id, quantity=1)
    db.add(stash)
    await db.commit()

    service = AuctionService(db)
    auction = await service.create_auction(seller_id=user.id, item_id=item.id, start_price=Decimal("10"), duration=1, quantity=1)
    assert keys == ["auctions:active*"]
    keys.clear()

    # cancelling should also emit
    await service.cancel_auction(auction.id, seller_id=user.id)
    assert keys == ["auctions:active*"]
    keys.clear()

    # closing finished auction should emit (we need a fresh one)
    auction2 = await service.create_auction(seller_id=user.id, item_id=item.id, start_price=Decimal("5"), duration=1, quantity=1)
    await service.close_auction(auction2.id)
    assert keys == ["auctions:active*"]
    keys.clear()

    # hero lot operations via AuctionLotService
    lot_service = AuctionLotService(db)
    hero = Hero(name="CacheHero", generation=1, nickname="CH", strength=1, agility=1, endurance=1, speed=1, health=1, defense=1, luck=1, field_of_view=1, level=1, experience=0, locale="en", owner_id=user.id, gold=Decimal("0"))
    db.add(hero)
    await db.commit()
    await db.refresh(hero)

    lot = await lot_service.create_auction_lot(hero_id=hero.id, seller_id=user.id, starting_price=Decimal("20"), duration=1)
    assert keys == ["auctions:active*"]
    keys.clear()

    # delete lot should emit
    await lot_service.delete_auction_lot(lot.id, seller_id=user.id)
    assert keys == ["auctions:active*"]
    keys.clear()

    # create again and close
    lot2 = await lot_service.create_auction_lot(hero_id=hero.id, seller_id=user.id, starting_price=Decimal("20"), duration=1)
    await lot_service.close_auction_lot(lot2.id)
    assert keys == ["auctions:active*"]
    keys.clear()


@pytest.mark.asyncio
async def test_expired_auction_sweep(db):
    # create basic auction then backdate its end_time
    user = User(username="sweep", email="sweep@example.com", balance=Decimal("1000"), reserved=Decimal("0"))
    db.add(user)
    await db.commit()
    await db.refresh(user)
    item = Item(name="SweepItem", description="", type="resource", slot_type="gadget")
    db.add(item)
    await db.commit()
    await db.refresh(item)
    stash = Stash(user_id=user.id, item_id=item.id, quantity=1)
    db.add(stash)
    await db.commit()

    service = AuctionService(db)
    auction = await service.create_auction(seller_id=user.id, item_id=item.id, start_price=Decimal("10"), duration=1, quantity=1)
    # artificially expire
    auction.end_time = datetime.utcnow() - timedelta(seconds=1)
    await db.commit()

    # run sweep
    await service.close_expired_auctions()
    await db.refresh(auction)
    assert auction.status == "finished"

    # lots: reuse same service to ensure both branches are covered
    hero = Hero(name="SweepHero", generation=1, nickname="SH", strength=1, agility=1, endurance=1, speed=1, health=1, defense=1, luck=1, field_of_view=1, level=1, experience=0, locale="en", owner_id=user.id, gold=Decimal("0"))
    db.add(hero)
    await db.commit()
    await db.refresh(hero)
    lot = await AuctionLotService(db).create_auction_lot(hero_id=hero.id, seller_id=user.id, starting_price=Decimal("100"), duration=1)
    lot.end_time = datetime.utcnow() - timedelta(seconds=1)
    await db.commit()
    await service.close_expired_auctions()
    await db.refresh(lot)
    assert lot.status == "finished"


@pytest.mark.asyncio
async def test_bid_idempotency(db):
    user1 = User(username="seller2", email="seller2@example.com", balance=Decimal("1000"), reserved=Decimal("0"))
    user2 = User(username="buyer2", email="buyer2@example.com", balance=Decimal("2000"), reserved=Decimal("0"))
    db.add_all([user1, user2])
    await db.commit()
    await db.refresh(user1)
    await db.refresh(user2)
    item = Item(name="Item2", description="", type="resource", slot_type="gadget")
    db.add(item)
    await db.commit()
    await db.refresh(item)
    stash = Stash(user_id=user1.id, item_id=item.id, quantity=1)
    db.add(stash)
    await db.commit()

    auction_svc = AuctionService(db)
    auction = await auction_svc.create_auction(seller_id=user1.id, item_id=item.id, start_price=Decimal("50"), duration=1, quantity=1)
    bid_svc = BidService(db)
    req_id = "abc-123"
    bid1 = await bid_svc.place_bid(bidder_id=user2.id, auction_id=auction.id, amount=Decimal("60"), request_id=req_id)
    # repeat with same request_id should return same object
    bid2 = await bid_svc.place_bid(bidder_id=user2.id, auction_id=auction.id, amount=Decimal("60"), request_id=req_id)
    assert bid1.id == bid2.id
    # and user2 reserved should only reflect single bid
    await db.refresh(user2)
    assert user2.reserved == Decimal("60")
