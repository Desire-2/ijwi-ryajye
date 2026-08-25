from decimal import Decimal

from extensions import db, realtime
from app.errors import bad_request, conflict, forbidden, not_found
from app.models.base import utcnow
from app.models.logistics import (
    DELIVERY_STATES,
    Delivery,
    DeliveryEvent,
    DeliveryQuote,
    DeliveryRequest,
    Vehicle,
)
from app.services.audit_service import record as audit
from app.services.notification_service import notify
from app.utils.money import validate_positive_quantity


def create_delivery_request(user, payload):
    qty = validate_positive_quantity(payload["quantity_value"])
    req = DeliveryRequest(
        requester_id=user.id,
        order_id=payload.get("order_id"),
        pickup_region=payload["pickup_region"],
        pickup_district=payload.get("pickup_district"),
        destination_region=payload["destination_region"],
        destination_district=payload.get("destination_district"),
        product_description=payload.get("product_description", ""),
        quantity_value=qty,
        unit_code=payload.get("unit_code", "kg"),
        vehicle_type_required=payload.get("vehicle_type_required"),
        requested_pickup_date=payload.get("requested_pickup_date"),
        budget_minor=int(payload["budget_minor"]) if payload.get("budget_minor") else None,
    )
    db.session.add(req)
    db.session.flush()
    audit(user, "delivery_request.created", "delivery_request", req.id)
    return req


def submit_quote(provider_user, delivery_request_id, price_minor, vehicle_id=None, eta_hours=None, message=""):
    from app.models.identity import LogisticsProfile

    profile = LogisticsProfile.query.filter_by(user_id=provider_user.id).first()
    if profile is None:
        raise forbidden("Only registered logistics providers can quote")
    req = db.session.get(DeliveryRequest, delivery_request_id)
    if req is None:
        raise not_found("Delivery request not found")
    if req.state not in ("REQUESTED", "QUOTED"):
        raise conflict(f"Request is {req.state.lower()}")

    if int(price_minor) < 0:
        raise bad_request("Price cannot be negative")

    quote = DeliveryQuote(
        delivery_request_id=req.id,
        provider_id=provider_user.id,
        vehicle_id=vehicle_id,
        price_minor=int(price_minor),
        currency_code=req.currency_code,
        eta_hours=eta_hours,
        message=message,
        state="SUBMITTED",
    )
    db.session.add(quote)
    if req.state == "REQUESTED":
        req.state = "QUOTED"
    db.session.flush()

    notify(req.requester_id, "DELIVERY_UPDATE", "New transport quote received",
           f"Quote for {float(req.quantity_value):g} {req.unit_code} {req.pickup_region} → {req.destination_region}",
           subject_type="delivery_request", subject_id=req.id)
    audit(provider_user, "delivery_quote.submitted", "delivery_quote", quote.id)
    return quote


def accept_quote(requester_user, quote_id):
    quote = db.session.get(DeliveryQuote, quote_id)
    if quote is None:
        raise not_found("Quote not found")
    req = db.session.get(DeliveryRequest, quote.delivery_request_id)
    if req.requester_id != requester_user.id:
        raise forbidden("Only the requester can accept quotes")
    if quote.state != "SUBMITTED" or req.state not in ("REQUESTED", "QUOTED"):
        raise conflict("This quote is no longer available")

    from app.services.fee_service import fee_for_scope

    fee = fee_for_scope(int(quote.price_minor), "LOGISTICS_JOB")

    delivery = Delivery(
        delivery_request_id=req.id,
        order_id=req.order_id,
        provider_id=quote.provider_id,
        vehicle_id=quote.vehicle_id,
        state="ACCEPTED",
        agreed_price_minor=quote.price_minor,
        platform_fee_minor=fee,
        currency_code=quote.currency_code,
    )
    db.session.add(delivery)
    db.session.flush()
    _add_event(delivery.id, req.requester_id, "ACCEPTED")

    quote.state = "ACCEPTED"
    other_quotes = DeliveryQuote.query.filter(
        DeliveryQuote.delivery_request_id == req.id,
        DeliveryQuote.id != quote.id,
        DeliveryQuote.state == "SUBMITTED",
    ).all()
    for q in other_quotes:
        q.state = "DECLINED"

    req.state = "MATCHED"
    if req.order_id:
        from app.services.order_service import get_order_or_404, transition_order
        order = get_order_or_404(req.order_id)
        order.delivery_id = delivery.id
        if order.state in ("PAID",):
            transition_order(requester_user, order, "PROCESSING", reason="Transport arranged")
            transition_order(requester_user, order, "READY_FOR_PICKUP", reason="Transport accepted")
    else:
        pass

    notify(quote.provider_id, "DELIVERY_UPDATE", "Your quote was accepted",
           f"Job {req.pickup_region} → {req.destination_region} confirmed.", subject_type="delivery", subject_id=delivery.id)
    for uid in {req.requester_id, quote.provider_id}:
        realtime.emit_to_user(uid, "order.updated", {"delivery_id": delivery.id, "state": "ACCEPTED"})
    return delivery


def advance_delivery(actor, delivery_id, new_state, proof_keys=None, notes=""):
    delivery = db.session.get(Delivery, delivery_id)
    if delivery is None:
        raise not_found("Delivery not found")
    if new_state not in DELIVERY_STATES:
        raise bad_request(f"Invalid delivery state {new_state}")

    is_provider = delivery.provider_id == actor.id
    is_requester = False
    req = db.session.get(DeliveryRequest, delivery.delivery_request_id) if delivery.delivery_request_id else None
    if req:
        is_requester = req.requester_id == actor.id

    allowed_map = {
        "PICKUP_SCHEDULED": [is_provider],
        "PICKED_UP": [is_provider],
        "IN_TRANSIT": [is_provider],
        "DELIVERED": [is_provider],
        "CONFIRMED": [is_requester],
        "FAILED": [is_provider, is_requester],
    }
    checks = allowed_map.get(new_state, [])
    if checks and not any(checks):
        raise forbidden(f"Only the authorized party can move delivery to {new_state}")

    flow_order = ["ACCEPTED", "PICKUP_SCHEDULED", "PICKED_UP", "IN_TRANSIT", "DELIVERED", "CONFIRMED"]
    current_idx = flow_order.index(delivery.state) if delivery.state in flow_order else 0
    target_idx = flow_order.index(new_state) if new_state in flow_order else -1

    if new_state in flow_order:
        expected_next = flow_order[current_idx + 1] if current_idx + 1 < len(flow_order) else None
        if new_state != "CONFIRMED" and expected_next != new_state and target_idx != current_idx + 1:
            raise conflict(
                f"Invalid delivery transition: {delivery.state} → {new_state}",
                code="INVALID_DELIVERY_TRANSITION",
                details={"current_state": delivery.state},
            )
        if new_state == "CONFIRMED" and delivery.state != "DELIVERED":
            raise conflict("Delivery must be marked DELIVERED before confirmation")

    prev_state = delivery.state
    delivery.state = new_state
    now = utcnow()
    if new_state == "PICKED_UP":
        delivery.picked_up_at = now
    elif new_state == "DELIVERED":
        delivery.delivered_at = now
    elif new_state == "CONFIRMED":
        delivery.confirmed_at = now

    if proof_keys:
        existing = (delivery.proof_of_delivery_keys or "").split(",") if delivery.proof_of_delivery_keys else []
        delivery.proof_of_delivery_keys = ",".join([e for e in existing if e] + list(proof_keys))
    if notes:
        delivery.delivery_notes = (delivery.delivery_notes + "\n" + notes).strip()

    _add_event(delivery.id, actor.id, new_state, {"notes": notes, "prev": prev_state})

    if delivery.order_id and new_state == "IN_TRANSIT":
        from app.services.order_service import get_order_or_404, transition_order
        try:
            order = get_order_or_404(delivery.order_id)
            if order.state == "READY_FOR_PICKUP":
                transition_order(actor, order, "IN_TRANSIT", reason="Transport picked up produce")
        except Exception:
            pass
    if delivery.order_id and new_state == "DELIVERED":
        from app.services.order_service import get_order_or_404, transition_order
        try:
            order = get_order_or_404(delivery.order_id)
            if order.state == "IN_TRANSIT":
                transition_order(actor, order, "DELIVERED", reason="Transport delivered produce")
        except Exception:
            pass

    parties = {delivery.provider_id}
    if req:
        parties.add(req.requester_id)
    if delivery.order_id:
        o = db.session.get(__import__("app.models.order", fromlist=["Order"]).Order, delivery.order_id)
        if o:
            parties |= {o.buyer_id, o.seller_id}
    for uid in parties:
        realtime.emit_to_user(uid, "delivery.updated", {"delivery_id": delivery.id, "state": new_state})
    return delivery


def _add_event(delivery_id, actor_id, event_type, detail=None):
    import json

    db.session.add(DeliveryEvent(delivery_id=delivery_id, actor_id=actor_id, event_type=event_type,
                                 detail_json=json.dumps(detail or {})))


def register_vehicle(user, payload):
    capacity = Decimal(str(payload.get("capacity_value", 0)))
    v = Vehicle(
        owner_id=user.id,
        vehicle_type=payload["vehicle_type"],
        plate_number=payload["plate_number"].upper().strip(),
        capacity_value=capacity,
        capacity_unit=payload.get("capacity_unit", "kg"),
        model=payload.get("model", ""),
    )
    db.session.add(v)
    db.session.flush()
    audit(user, "vehicle.registered", "vehicle", v.id)
    return v


def rate_delivery(reviewer, delivery, rating_values, comment=""):
    subject_role = "logistics"
    review = __import__("app.models.order", fromlist=["Review"]).Review(
        delivery_id=None,
        order_id=delivery.order_id,
        reviewer_id=reviewer.id,
        subject_id=delivery.provider_id,
        subject_role=subject_role,
        overall_rating=int(rating_values.get("overall_rating", 5)),
        communication_rating=rating_values.get("communication_rating"),
        accuracy_rating=rating_values.get("accuracy_rating"),
        reliability_rating=rating_values.get("reliability_rating"),
        payment_rating=rating_values.get("payment_rating"),
        delivery_rating=rating_values.get("delivery_rating"),
        comment=comment,
        verified_transaction=True,
    )
    db.session.add(review)
    db.session.flush()
    from app.services.reputation_service import apply_review_to_profile
    apply_review_to_profile(review)
    return review
