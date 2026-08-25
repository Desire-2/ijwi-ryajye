from datetime import timedelta
from decimal import Decimal

from extensions import db, realtime
from app.errors import bad_request, conflict, forbidden, not_found, unprocessable
from app.models.base import utcnow
from app.models.marketplace import Listing
from app.models.trade import Bid
from app.services.audit_service import record as audit
from app.services.notification_service import notify


def place_bid(actor, payload):
    listing = db.session.get(Listing, payload.get("listing_id"))
    if listing is None:
        raise not_found("Listing not found")
    if listing.seller_id == actor.id:
        raise forbidden("You cannot bid on your own listing.", "SELF_BID")

    if not listing.is_auction_active:
        if listing.listing_type != "AUCTION":
            raise bad_request("This listing is not an auction", "NOT_AN_AUCTION")
        elif listing.state != "ACTIVE":
            raise conflict(f"Auction is {listing.state.lower()}", "AUCTION_NOT_ACTIVE")
        else:
            end = listing.auction_end_at
            if end and utcnow() < (listing.auction_start_at or utcnow()):
                raise conflict("Auction has not started yet", "AUCTION_NOT_STARTED")
            if listing.auction_start_at and utcnow() < listing.auction_start_at:
                raise conflict("Auction has not started yet", "AUCTION_NOT_STARTED")
            raise conflict("Auction has ended", "AUCTION_ENDED")

    amount_minor = int(payload["amount_minor"])
    quantity = Decimal(str(payload["quantity_value"]))
    if quantity <= 0:
        raise bad_request("Quantity must be greater than zero")
    if quantity > Decimal(str(listing.available_quantity)):
        raise bad_request(
            f"Bid quantity exceeds available {float(listing.available_quantity):g} {listing.unit_code}"
        )

    current_top = (
        Bid.query.filter_by(listing_id=listing.id, state="ACTIVE")
        .order_by(Bid.amount_minor.desc())
        .first()
    )

    floor_amount = int(listing.reserve_price_minor) if listing.reserve_price_minor else 0
    if current_top is not None:
        increment = int(listing.min_bid_increment_minor or 100)
        floor_amount = current_top.amount_minor + increment

    if amount_minor < floor_amount:
        raise unprocessable(
            f"Minimum bid is {floor_amount} minor units",
            code="BID_BELOW_MINIMUM",
            details={"minimum_bid_minor": floor_amount},
        )

    bid = Bid(
        listing_id=listing.id,
        bidder_id=actor.id,
        amount_minor=amount_minor,
        quantity_value=quantity,
        unit_code=listing.unit_code,
        currency_code=listing.currency_code,
        state="ACTIVE",
    )

    if current_top is not None:
        current_top.state = "OUTBID"
        current_top.is_winning = False
    bid.is_winning = True

    db.session.add(bid)
    db.session.flush()

    anti_snipe_seconds = 120
    from flask import current_app as app

    anti_snipe_seconds = int(app.config.get("AUCTION_ANTI_SNIPE_SECONDS", 120))
    if listing.auction_end_at and (listing.auction_end_at - utcnow()).total_seconds() < anti_snipe_seconds:
        listing.auction_end_at = utcnow() + timedelta(seconds=anti_snipe_seconds)

    _audit_bid(actor, bid)

    if current_top is not None and current_top.bidder_id != actor.id:
        notify(current_top.bidder_id, "MARKET_ALERT", "You have been outbid",
               f"New leading bid: {amount_minor}", subject_type="listing", subject_id=listing.id)
    notify(listing.seller_id, "MARKET_ALERT", "New bid on your auction",
           f"{quantity:g} {listing.unit_code} at {amount_minor}", subject_type="listing", subject_id=listing.id)

    realtime.emit("bid.placed", {
        "listing_id": listing.id,
        "bid_id": bid.id,
        "amount_minor": bid.amount_minor,
        "auction_end_at": listing.auction_end_at.isoformat(),
    })

    return bid


def _audit_bid(actor, bid):
    from extensions import db as _db
    from app.services.audit_service import record as audit
    audit(actor, "bid.placed", "bid", bid.id, {"amount_minor": bid.amount_minor})
    return None


def accept_winning_bid(actor, listing):
    if listing.seller_id != actor.id:
        raise forbidden("Only the seller can accept the winning bid")
    winning = (
        Bid.query.filter_by(listing_id=listing.id, state="ACTIVE")
        .order_by(Bid.amount_minor.desc())
        .first()
    )
    if winning is None:
        raise conflict("No active bids to accept", "NO_BIDS")
    return accept_bid(actor, winning.id)


def accept_bid(actor, bid_id):
    from app.services.order_service import create_order_from_accepted_offer
    from app.services import inventory_service

    bid = db.session.get(Bid, bid_id)
    if bid is None:
        raise not_found("Bid not found")
    listing = db.session.get(Listing, bid.listing_id)
    if listing.seller_id != actor.id and "ADMIN" not in actor.role_codes():
        raise forbidden("Only the seller can accept a bid")

    if bid.state in ("ACCEPTED", "RETRACTED"):
        raise conflict(f"Bid already {bid.state.lower()}")

    if listing.reserve_price_minor and bid.amount_minor < int(listing.reserve_price_minor):
        pass

    reservations = inventory_service.reserve(
        owner_id=listing.seller_id,
        product_id=listing.product_id,
        quantity_value=float(bid.quantity_value),
        unit_code=bid.unit_code,
        bid_id=bid.id,
        farm_id=listing.farm_id,
    )

    class _OfferLike:
        pass

    proxy = _OfferLike()
    proxy.id = None
    proxy.listing_id = listing.id
    proxy.buyer_id = bid.bidder_id
    proxy.quantity_value = bid.quantity_value
    proxy.unit_code = bid.unit_code
    proxy.price_minor = bid.amount_minor
    proxy.currency_code = bid.currency_code
    proxy.delivery_option = "PICKUP"
    proxy.payment_terms = ""

    order = create_order_from_accepted_offer(
        actor=actor,
        offer=proxy,
        seller_id=listing.seller_id,
        buyer_id=bid.bidder_id,
        product_id=listing.product_id,
        reservation_ids=[r.id for r in reservations],
        delivery_option="PICKUP",
        source="AUCTION_BID",
        bid_id=bid.id,
    )
    order.bid_id = bid.id
    db.session.flush()
    for r in reservations:
        r.order_id = order.id

    bid.state = "ACCEPTED"
    losing = Bid.query.filter(Bid.listing_id == listing.id, Bid.id != bid.id, Bid.state.in_(["ACTIVE", "OUTBID"])).all()
    for b in losing:
        b.state = "REJECTED"

    listing.state = "CLOSED" if Decimal(str(listing.available_quantity)) <= Decimal(str(bid.quantity_value)) else "ACTIVE"

    audit(actor, "bid.accepted", "bid", bid.id, {"order_number": order.order_number})
    notify(bid.bidder_id, "OFFER_ACCEPTED", "Your bid won!", f"Order {order.order_number} created", subject_type="order", subject_id=order.id)
    realtime.emit("bid.accepted", {"listing_id": listing.id, "bid_id": bid.id, "order_id": order.id})
    realtime.emit_to_user(bid.bidder_id, "order.updated", {"order_id": order.id, "state": order.state})
    return order


def retract_bid(actor, bid_id):
    bid = db.session.get(Bid, bid_id)
    if bid.bidder_id != actor.id:
        raise forbidden("You can only retract your own bid")
    if bid.state != "ACTIVE":
        raise conflict("Only active bids can be retracted")
    bid.state = "RETRACTED"
    bid.is_winning = False
    next_best = (
        Bid.query.filter_by(listing_id=bid.listing_id, state="ACTIVE")
        .order_by(Bid.amount_minor.desc())
        .first()
    )
    if next_best:
        next_best.is_winning = True
    audit(actor, "bid.retracted", "bid", bid.id)
    risk_flag_retract(actor, bid)
    return bid


def risk_flag_retract(actor, bid):
    from app.services.risk_service import note_event
    count = (
        db.session.query(__import__("sqlalchemy").func.count())
        .select_from(type(bid))
        .filter(type(bid).bidder_id == actor.id, type(bid).state == "RETRACTED")
        .scalar()
    )
    if count >= 3:
        note_event(actor.id, "BID_MANIPULATION", 10, {"retracted_bids": count}, flag=True)


def expire_auctions():
    now = utcnow()
    ended = Listing.query.filter(
        Listing.listing_type == "AUCTION",
        Listing.state == "ACTIVE",
        Listing.auction_end_at.isnot(None),
        Listing.auction_end_at <= now,
    ).all()
    closed = 0
    for listing in ended:
        winner = (
            Bid.query.filter_by(listing_id=listing.id, state="ACTIVE")
            .order_by(Bid.amount_minor.desc())
            .first()
        )
        if winner:
            winner.is_winning = True
            notify(winner.bidder_id, "OFFER_ACCEPTED", "Auction ended — your bid leads",
                   "The seller can now confirm your order.", subject_type="listing", subject_id=listing.id)
            notify(listing.seller_id, "ORDER_UPDATE", "Auction ended with a winning bid",
                   "Accept the winning bid to create an order.", subject_type="listing", subject_id=listing.id)
        else:
            listing.state = "EXPIRED"
        closed += 1
    if ended:
        db.session.commit()
    return closed
