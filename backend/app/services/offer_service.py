from datetime import timedelta
from decimal import Decimal

from flask import current_app

from extensions import db, realtime
from app.errors import bad_request, conflict, forbidden, not_found
from app.models.base import utcnow
from app.models.marketplace import BuyerRequest, Listing
from app.models.trade import Contract, Offer, OfferEvent
from app.services import inventory_service
from app.services.audit_service import record as audit
from app.services.notification_service import notify
import json


def _snapshot(offer):
    return json.dumps(
        {
            "quantity": float(offer.quantity_value),
            "unit": offer.unit_code,
            "price_minor": offer.price_minor,
            "currency": offer.currency_code,
        }
    )


def create_offer(actor, payload):
    listing_id = payload.get("listing_id")
    buyer_request_id = payload.get("buyer_request_id")
    if not (listing_id or buyer_request_id):
        raise bad_request("Offer must reference a listing or a buyer request")

    quantity = Decimal(str(payload["quantity_value"]))
    if quantity <= 0:
        raise bad_request("Quantity must be greater than zero")
    price_minor = int(payload["price_minor"])
    if price_minor < 0:
        raise bad_request("Price cannot be negative")
    currency = payload.get("currency_code", current_app.config["DEFAULT_CURRENCY"])

    offer = Offer(
        buyer_request_id=buyer_request_id,
        quantity_value=quantity,
        unit_code=payload.get("unit_code", "kg"),
        price_minor=price_minor,
        currency_code=currency,
        delivery_option=payload.get("delivery_option", "PICKUP"),
        payment_terms=payload.get("payment_terms", ""),
        message=payload.get("message", ""),
    )

    ttl_hours = int(payload.get("expires_in_hours", 48))
    offer.expires_at = utcnow() + timedelta(hours=ttl_hours)

    if listing_id:
        listing = db.session.get(Listing, listing_id)
        if listing is None:
            raise not_found("Listing not found")
        if listing.seller_id == actor.id:
            raise forbidden("You cannot make an offer on your own listing.", "SELF_OFFER")
        if listing.state != "ACTIVE":
            raise conflict(f"Listing is {listing.state.lower()}", "LISTING_NOT_ACTIVE")
        if listing.listing_type == "AUCTION":
            raise bad_request("Use bidding for auction listings", "USE_BIDDING")
        max_order = listing.maximum_order_value
        min_order = listing.minimum_order_value
        if min_order is not None and Decimal(str(min_order)) > 0 and quantity < Decimal(str(min_order)):
            raise bad_request(f"Minimum order for this listing is {min_order:g} {listing.unit_code}")
        if max_order is not None and quantity > Decimal(str(max_order)):
            raise bad_request(f"Maximum order for this listing is {max_order:g} {listing.unit_code}")
        if quantity > Decimal(str(listing.available_quantity)):
            raise conflict(
                f"Only {float(listing.available_quantity):g} {listing.unit_code} available",
                "QUANTITY_EXCEEDS_AVAILABLE",
            )
        offer.listing_id = listing.id
        offer.buyer_id = actor.id
        offer.seller_id = listing.seller_id
    else:
        br = db.session.get(BuyerRequest, buyer_request_id)
        if br is None:
            raise not_found("Buyer request not found")
        if br.buyer_id == actor.id:
            raise forbidden("You cannot respond to your own request.", "SELF_RESPONSE")
        if br.state not in ("OPEN", "MATCHING"):
            raise conflict("This request is no longer open", "REQUEST_CLOSED")
        if quantity > Decimal(str(br.quantity_value)):
            raise bad_request("Your offered quantity exceeds the requested amount")
        offer.buyer_request_id = br.id
        offer.seller_id = actor.id
        offer.buyer_id = br.buyer_id

    db.session.add(offer)
    db.session.flush()
    db.session.add(OfferEvent(offer_id=offer.id, actor_id=actor.id, event_type="CREATED", snapshot_json=_snapshot(offer)))

    audit(actor, "offer.created", "offer", offer.id)
    notify(
        offer.seller_id if listing_id else offer.buyer_id,
        "NEW_OFFER",
        "New offer received",
        f"{quantity:g} {offer.unit_code} at {price_minor} minor units",
        subject_type="offer",
        subject_id=offer.id,
    )
    realtime.emit_to_user(
        str(offer.seller_id) if listing_id else str(offer.buyer_id),
        "offer.created",
        {"offer_id": offer.id, "listing_id": offer.listing_id},
    )
    return offer


def counter_offer(actor, offer_id, new_price_minor, new_quantity=None, message=""):
    original = get_offer_or_404(offer_id)
    _assert_party(original, actor)

    if original.state in ("ACCEPTED", "WITHDRAWN", "EXPIRED", "CANCELLED"):
        raise conflict(f"Cannot counter an offer that is {original.state.lower()}")

    price_minor = int(new_price_minor)
    if price_minor < 0:
        raise bad_request("Price cannot be negative")

    if actor.id == original.buyer_id:
        new_buyer_id, new_seller_id = original.buyer_id, original.seller_id
    else:
        new_buyer_id, new_seller_id = original.buyer_id, actor.id
    counter = Offer(
        listing_id=original.listing_id,
        buyer_request_id=original.buyer_request_id,
        parent_offer_id=original.id,
        buyer_id=new_buyer_id,
        seller_id=new_seller_id,
        state="PENDING",
        quantity_value=Decimal(str(new_quantity)) if new_quantity else original.quantity_value,
        unit_code=original.unit_code,
        price_minor=price_minor,
        currency_code=original.currency_code,
        delivery_option=original.delivery_option,
        payment_terms=original.payment_terms,
        message=message,
        expires_at=utcnow() + timedelta(hours=48),
    )
    db.session.add(counter)
    db.session.flush()

    original.state = "COUNTERED"
    original.responded_at = utcnow()
    db.session.add(OfferEvent(offer_id=original.id, actor_id=actor.id, event_type="COUNTERED", snapshot_json=_snapshot(counter)))
    audit(actor, "offer.countered", "offer", original.id, {"counter_id": counter.id})

    other_party = counter.seller_id if actor.id == counter.buyer_id else counter.buyer_id
    notify(other_party, "NEW_OFFER", "Counteroffer received", f"New price proposed on an open negotiation", subject_type="offer", subject_id=counter.id)
    realtime.emit_to_user(other_party, "offer.updated", {"offer_id": counter.id, "state": "PENDING"})
    return counter


def accept_offer(actor, offer_id):
    from app.services.order_service import create_order_from_accepted_offer

    offer = get_offer_or_404(offer_id)
    _assert_party(offer, actor)

    if offer.expires_at and offer.expires_at < utcnow():
        offer.state = "EXPIRED"

    if offer.state != "PENDING":
        raise conflict(f"Cannot accept an offer in state {offer.state}")

    if offer.listing_id:
        listing = db.session.get(Listing, offer.listing_id)
        seller_id = listing.seller_id
        buyer_id = offer.buyer_id
        product_id = listing.product_id
        unit_code = offer.unit_code
        currency = offer.currency_code
        farm_id = listing.farm_id
        delivery_option = offer.delivery_option
    else:
        br = db.session.get(BuyerRequest, offer.buyer_request_id)
        seller_id = offer.seller_id
        buyer_id = br.buyer_id
        product_id = br.product_id
        unit_code = offer.unit_code
        currency = offer.currency_code
        farm_id = None
        delivery_option = offer.delivery_option

    if actor.id not in (seller_id, buyer_id):
        raise forbidden("Only the buyer or seller can act on this offer")

    reservations = inventory_service.reserve(
        owner_id=seller_id,
        product_id=product_id,
        quantity_value=float(offer.quantity_value),
        unit_code=unit_code,
        offer_id=offer.id,
        farm_id=farm_id,
    )

    order = create_order_from_accepted_offer(
        actor=actor,
        offer=offer,
        seller_id=seller_id,
        buyer_id=buyer_id,
        product_id=product_id,
        reservation_ids=[r.id for r in reservations],
        delivery_option=delivery_option,
    )

    offer.state = "ACCEPTED"
    offer.responded_at = utcnow()
    db.session.add(OfferEvent(offer_id=offer.id, actor_id=actor.id, event_type="ACCEPTED", snapshot_json=_snapshot(offer)))
    audit(actor, "offer.accepted", "offer", offer.id, {"order_id": order.order_number})

    total_major = float(order.total_amount_minor)
    notify(buyer_id if actor.id == seller_id else seller_id,
           "OFFER_ACCEPTED", "Offer accepted", f"Order {order.order_number} created", subject_type="order", subject_id=order.id)
    realtime.emit_to_user(seller_id, "offer.updated", {"offer_id": offer.id, "state": "ACCEPTED"})
    realtime.emit_to_user(buyer_id, "offer.accepted", {"offer_id": offer.id, "order_id": order.id})
    realtime.emit("order.created", {"order_id": order.id, "number": order.order_number})
    return order


def reject_offer(actor, offer_id):
    offer = get_offer_or_404(offer_id)
    _assert_party(offer, actor)
    if offer.state != "PENDING":
        raise conflict(f"Cannot reject an offer in state {offer.state}")
    offer.state = "REJECTED"
    offer.responded_at = utcnow()
    db.session.add(OfferEvent(offer_id=offer.id, actor_id=actor.id, event_type="REJECTED"))
    other = offer.seller_id if actor.id == offer.buyer_id else offer.buyer_id
    realtime.emit_to_user(other, "offer.updated", {"offer_id": offer.id, "state": "REJECTED"})
    return offer


def withdraw_offer(actor, offer_id):
    offer = get_offer_or_404(offer_id)
    if offer.buyer_id != actor.id:
        raise forbidden("Only the offer creator can withdraw it")
    if offer.state != "PENDING":
        raise conflict("Only pending offers can be withdrawn")
    offer.state = "WITHDRAWN"
    offer.responded_at = utcnow()
    db.session.add(OfferEvent(offer_id=offer.id, actor_id=actor.id, event_type="WITHDRAWN"))
    realtime.emit_to_user(offer.seller_id, "offer.updated", {"offer_id": offer.id, "state": "WITHDRAWN"})
    return offer


def expire_stale_offers():
    now = utcnow()
    stale = Offer.query.filter(Offer.state == "PENDING", Offer.expires_at.isnot(None), Offer.expires_at < now).all()
    for offer in stale:
        offer.state = "EXPIRED"
        db.session.add(OfferEvent(offer_id=offer.id, actor_id=None, event_type="EXPIRED"))
    if stale:
        db.session.commit()
    return len(stale)


def get_offer_or_404(offer_id):
    offer = db.session.get(Offer, offer_id)
    if offer is None:
        raise not_found("Offer not found")
    return offer


def _assert_party(offer, actor):
    parties = {offer.buyer_id, offer.seller_id}
    if actor.id not in parties and "ADMIN" not in actor.role_codes():
        raise forbidden("You are not part of this negotiation")


def maybe_create_contract(order, actor):
    threshold = current_app.config["CONTRACT_THRESHOLD_MINOR"]
    if order.total_amount_minor < threshold:
        return None
    terms = {
        "seller_id": order.seller_id,
        "buyer_id": order.buyer_id,
        "product_quantity": float(order.quantity_value),
        "unit": order.unit_code,
        "unit_price_minor": order.unit_price_minor,
        "total_amount_minor": order.total_amount_minor,
        "currency": order.currency_code,
        "delivery_option": order.delivery_option,
        "payment_terms": order.payment_terms or "Payment before dispatch unless agreed otherwise",
        "cancellation": "Cancellation allowed only before pickup; disputes resolved via platform dispute process",
        "dispute_rules": "Open a dispute within 72 hours of delivery with evidence",
    }
    contract = Contract(
        order_id=order.id,
        seller_id=order.seller_id,
        buyer_id=order.buyer_id,
        state="ACTIVE",
        terms_json=json.dumps(terms, default=str),
    )
    db.session.add(contract)
    db.session.flush()
    order.contract_id = contract.id
    audit(actor, "contract.created", "contract", contract.id, {"version": 1})
    return contract
