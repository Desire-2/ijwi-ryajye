import secrets
from decimal import Decimal

from flask import current_app

from extensions import db, realtime
from app.errors import bad_request, conflict, forbidden, not_found
from app.models.base import utcnow
from app.models.marketplace import Listing
from app.models.order import (
    ALLOWED_ORDER_TRANSITIONS,
    ORDER_CANCELABLE_STATES,
    Order,
    OrderEvent,
    OrderItem,
)
from app.services.audit_service import record as audit
from app.services.notification_service import notify


def generate_order_number():
    while True:
        candidate = f"IRJ-{secrets.randbelow(900000) + 100000}"
        if not Order.query.filter_by(order_number=candidate).first():
            return candidate


def get_order_or_404(order_id):
    order = db.session.get(Order, order_id)
    if order is None:
        raise not_found("Order not found")
    return order


def assert_order_party(order, user):
    parties = {order.buyer_id, order.seller_id}
    if user.id not in parties and "ADMIN" not in user.role_codes():
        raise forbidden("You are not a party to this order")


def create_order_from_accepted_offer(actor, offer, seller_id, buyer_id, product_id, reservation_ids, delivery_option="PICKUP", source="OFFER", bid_id=None):
    quantity = Decimal(str(offer.quantity_value))
    unit_price = int(offer.price_minor)
    total = int((Decimal(unit_price) * quantity).to_integral_value())
    currency = offer.currency_code

    from app.services.fee_service import fee_for_scope

    fee = fee_for_scope(total, "MARKETPLACE_SALE")

    order = Order(
        order_number=generate_order_number(),
        listing_id=getattr(offer, "listing_id", None),
        buyer_request_id=getattr(offer, "buyer_request_id", None),
        bid_id=bid_id,
        buyer_id=buyer_id,
        seller_id=seller_id,
        state="ACCEPTED",
        quantity_value=quantity,
        unit_code=offer.unit_code,
        unit_price_minor=unit_price,
        total_amount_minor=total,
        platform_fee_minor=fee,
        currency_code=currency,
        delivery_option=delivery_option,
        payment_terms=getattr(offer, "payment_terms", ""),
    )
    db.session.add(order)
    db.session.flush()

    item = OrderItem(
        order_id=order.id,
        product_id=product_id,
        description=f"{quantity:g} {order.unit_code}",
        quantity_value=quantity,
        unit_code=order.unit_code,
        unit_price_minor=unit_price,
        line_total_minor=total,
    )
    db.session.add(item)
    db.session.add(
        OrderEvent(
            order_id=order.id,
            actor_id=actor.id,
            event_type="ORDER_CREATED",
            from_state=None,
            to_state="ACCEPTED",
            detail_json='{"source": "%s"}' % source,
        )
    )

    for rid in reservation_ids:
        from app.models.marketplace import InventoryReservation

        res = db.session.get(InventoryReservation, rid)
        if res:
            res.order_id = order.id
            res.listing_id = order.listing_id or res.listing_id

    _decrement_listing_available(order)

    from app.services.offer_service import maybe_create_contract
    contract = maybe_create_contract(order, actor)
    db.session.flush()
    return order


def _decrement_listing_available(order):
    listing = db.session.get(Listing, order.listing_id) if order.listing_id else None
    if listing is None:
        return
    listing.available_quantity = max(Decimal("0"), Decimal(str(listing.available_quantity)) - Decimal(str(order.quantity_value)))
    listing.sold_quantity = Decimal(str(listing.sold_quantity)) + Decimal(str(order.quantity_value))
    if listing.available_quantity <= 0:
        listing.state = "SOLD_OUT"


def transition_order(actor, order, new_state, reason=None, allow_admin_override=False):
    current = order.state
    if new_state not in ALLOWED_ORDER_TRANSITIONS.get(current, set()):
        raise conflict(
            f"Invalid order transition: {current} → {new_state}",
            code="INVALID_ORDER_TRANSITION",
            details={"current_state": current, "attempted_state": new_state},
        )
    _guard_transition(actor, order, new_state)
    order.state = new_state
    db.session.add(
        OrderEvent(
            order_id=order.id,
            actor_id=actor.id if actor else None,
            event_type="STATE_TRANSITION",
            from_state=current,
            to_state=new_state,
            detail_json=(reason or ""),
        )
    )

    if new_state == "COMPLETED":
        order.completed_at = utcnow()
        from app.tasks.trust import schedule_reputation_update
        try:
            schedule_reputation_update.delay(order.seller_id, order.buyer_id)
        except Exception:
            pass

    notify(order.buyer_id if actor.id == order.seller_id else order.seller_id,
           "ORDER_UPDATE", f"Order {order.order_number} update",
           f"Order moved to {new_state}", subject_type="order", subject_id=order.id)
    for uid in {order.buyer_id, order.seller_id}:
        realtime.emit_to_user(uid, "order.updated", {
            "order_id": order.id,
            "number": order.order_number,
            "state": new_state,
        })
    return order


def _guard_transition(actor, order, new_state):
    roles = actor.role_codes() if actor else set()
    admin = "ADMIN" in roles
    is_buyer = actor.id == order.buyer_id
    is_seller = actor.id == order.seller_id

    rules = {
        "PAYMENT_PENDING": lambda: True,
        "PAID": lambda: False,
        "PROCESSING": lambda: is_seller or admin,
        "READY_FOR_PICKUP": lambda: is_seller or admin,
        "IN_TRANSIT": lambda: is_seller or admin or _is_transporter(order, actor),
        "DELIVERED": lambda: is_seller or admin or _is_transporter(order, actor),
        "COMPLETED": lambda: is_buyer or admin,
        "CANCELLED": lambda: (is_buyer or is_seller or admin) and current_cancelable(order),
        "DISPUTED": lambda: is_buyer or is_seller or admin,
        "REFUNDED": lambda: admin,
    }
    check = rules.get(new_state)
    if check is None:
        return
    if check() is False:
        raise forbidden(f"Transition to {new_state} is performed by the payment system", "SYSTEM_ONLY")


def current_cancelable(order):
    return order.state in ORDER_CANCELABLE_STATES


def cancel_order(actor, order, reason):
    if order.state == "PAID":
        pass
    if order.state not in ORDER_CANCELABLE_STATES:
        raise conflict(f"Order in state {order.state} can no longer be cancelled")
    if order.state in ("PAID", "PROCESSING", "READY_FOR_PICKUP") and actor.id != order.seller_id and "ADMIN" not in actor.role_codes():
        from app.services.risk_service import note_event
        note_event(actor.id, "REPEATED_CANCELLATION", 2, {"order": order.order_number})
    transition_order(actor, order, "CANCELLED", reason=reason or "")
    order.cancelled_reason = reason

    from app.services import inventory_service
    from app.models.marketplace import InventoryReservation

    reservations = InventoryReservation.query.filter_by(order_id=order.id).all()
    for r in reservations:
        inventory_service.release_reservation(r.id)

    listing = db.session.get(Listing, order.listing_id) if order.listing_id else None
    if listing is not None:
        listing.available_quantity = min(Decimal(str(listing.quantity_value)), Decimal(str(listing.available_quantity)) + Decimal(str(order.quantity_value)))
        listing.sold_quantity = max(Decimal("0"), Decimal(str(listing.sold_quantity)) - Decimal(str(order.quantity_value)))
        if listing.state == "SOLD_OUT" and listing.available_quantity > 0:
            listing.state = "ACTIVE"
    audit(actor, "order.cancelled", "order", order.id, {"reason": reason})
    return order


def _is_transporter(order, actor):
    if not order.delivery_id:
        return False
    from app.models.logistics import Delivery

    d = db.session.get(Delivery, order.delivery_id)
    return d is not None and d.provider_id == actor.id


def list_orders_for(user, state=None, role=None, page=1, per_page=20):
    q = Order.query
    if state:
        q = q.filter(Order.state == state)
    if role == "buyer":
        q = q.filter(Order.buyer_id == user.id)
    elif role == "seller":
        q = q.filter(Order.seller_id == user.id)
    else:
        q = q.filter((Order.buyer_id == user.id) | (Order.seller_id == user.id))
    return q.order_by(Order.created_at.desc()).paginate(page=page, per_page=per_page, error_out=False)


def mark_paid_system(order_id, payment):
    order = get_order_or_404(order_id)
    if order.state == "PAYMENT_PENDING":
        order.state = "PAID"
        db.session.add(OrderEvent(order_id=order.id, actor_id=None, event_type="PAYMENT_CONFIRMED",
                                  from_state="PAYMENT_PENDING", to_state="PAID"))
    for uid in {order.buyer_id, order.seller_id}:
        realtime.emit_to_user(uid, "order.updated", {"order_id": order.id, "state": order.state})
