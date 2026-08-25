import marshmallow as ma
from flask import request
from flask_jwt_extended import jwt_required

from extensions import db
from app.api.helpers import pagination_args, parse_body, paginate_response, query_params
from app.api.serializers import bid_json, offer_json, order_json
from app.errors import bad_request, forbidden, not_found
from app.models.marketplace import BuyerRequest, Listing
from app.models.order import Order
from app.models.trade import Bid, Offer
from app.services import bid_service, offer_service, order_service
from app.services.security import get_current_user


class OfferSchema(ma.Schema):
    listing_id = ma.fields.String()
    buyer_request_id = ma.fields.String()
    quantity_value = ma.fields.Float(required=True)
    unit_code = ma.fields.String(missing="kg")
    price_minor = ma.fields.Integer(required=True)
    currency_code = ma.fields.String()
    delivery_option = ma.fields.String(missing="PICKUP")
    payment_terms = ma.fields.String(missing="")
    message = ma.fields.String(missing="")
    expires_in_hours = ma.fields.Integer(missing=48)


@jwt_required()
def create_offer():
    user = get_current_user()
    data = parse_body(OfferSchema)
    if "currency_code" not in data:
        from flask import current_app

        data["currency_code"] = current_app.config["DEFAULT_CURRENCY"]
    offer = offer_service.create_offer(user, data)
    db.session.commit()
    return {"offer": offer_json(offer)}, 201


@jwt_required()
def counter_offer(offer_id):
    user = get_current_user()
    body = parse_body(type("S", (ma.Schema,), {
        "price_minor": ma.fields.Integer(required=True),
        "quantity_value": ma.fields.Float(),
        "message": ma.fields.String(missing=""),
    })())
    counter = offer_service.counter_offer(
        user, offer_id, body["price_minor"],
        new_quantity=body.get("quantity_value"), message=body.get("message", ""))
    db.session.commit()
    return {"offer": offer_json(counter)}


@jwt_required()
def accept_offer(offer_id):
    user = get_current_user()
    order = offer_service.accept_offer(user, offer_id)
    db.session.commit()
    return {"order": order_json(order, user.id)}, 201


@jwt_required()
def reject_offer(offer_id):
    user = get_current_user()
    offer = offer_service.reject_offer(user, offer_id)
    db.session.commit()
    return {"offer": offer_json(offer)}


@jwt_required()
def withdraw_offer(offer_id):
    user = get_current_user()
    offer = offer_service.withdraw_offer(user, offer_id)
    db.session.commit()
    return {"offer": offer_json(offer)}


@jwt_required()
def list_listing_offers(listing_id):
    user = get_current_user()
    listing = db.session.get(Listing, listing_id)
    if listing is None:
        raise not_found("Listing not found")
    if listing.seller_id != user.id and "ADMIN" not in user.role_codes():
        offers = Offer.query.filter(Offer.listing_id == listing.id, Offer.buyer_id == user.id).all()
    else:
        offers = Offer.query.filter_by(listing_id=listing.id).all()
    return {"offers": [offer_json(o) for o in offers]}


@jwt_required()
def list_my_offers():
    user = get_current_user()
    role = query_params().get("role", "buyer")
    state = query_params().get("state")
    q = Offer.query.filter_by(buyer_id=user.id) if role == "buyer" else Offer.query.filter_by(seller_id=user.id)
    if state:
        q = q.filter_by(state=state.upper())
    page, per_page = pagination_args()
    pg = q.order_by(Offer.created_at.desc()).paginate(page=page, per_page=per_page, error_out=False)
    return paginate_response(pg, offer_json)


class BidSchema(ma.Schema):
    listing_id = ma.fields.String(required=True)
    amount_minor = ma.fields.Integer(required=True)
    quantity_value = ma.fields.Float(required=True)


@jwt_required()
def place_bid():
    user = get_current_user()
    data = parse_body(BidSchema)
    bid = bid_service.place_bid(user, data)
    db.session.commit()
    return {"bid": bid_json(bid)}, 201


@jwt_required()
def retract_bid(bid_id):
    user = get_current_user()
    bid = bid_service.retract_bid(user, bid_id)
    db.session.commit()
    return {"bid": bid_json(bid)}


@jwt_required()
def accept_bid(bid_id):
    user = get_current_user()
    order = bid_service.accept_bid(user, bid_id)
    db.session.commit()
    return {"order": order_json(order, user.id)}, 201


@jwt_required()
def accept_winning_bid(listing_id):
    user = get_current_user()
    listing = db.session.get(Listing, listing_id)
    if listing is None:
        raise not_found("Listing not found")
    order = bid_service.accept_winning_bid(user, listing)
    db.session.commit()
    return {"order": order_json(order, user.id)}, 201


@jwt_required()
def list_bids(listing_id):
    user = get_current_user()
    listing = db.session.get(Listing, listing_id)
    if listing is None:
        raise not_found("Listing not found")
    bids = Bid.query.filter_by(listing_id=listing.id).order_by(Bid.amount_minor.desc()).limit(100).all()
    return {"bids": [bid_json(b) for b in bids]}


@jwt_required()
def create_order_draft():
    user = get_current_user()
    data = parse_body(type("S", (ma.Schema,), {
        "listing_id": ma.fields.String(required=True),
        "quantity_value": ma.fields.Float(required=True),
    })())
    from decimal import Decimal

    listing = db.session.get(Listing, data["listing_id"])
    if listing is None:
        raise not_found("Listing not found")
    qty = Decimal(str(data["quantity_value"]))
    if qty <= 0 or qty > Decimal(str(listing.available_quantity)):
        raise bad_request("Invalid quantity for this listing")

    class _Proxy:
        pass

    proxy = _Proxy()
    proxy.listing_id = listing.id
    proxy.quantity_value = qty
    proxy.unit_code = listing.unit_code
    proxy.price_minor = listing.price_minor or 0
    proxy.currency_code = listing.currency_code
    proxy.delivery_option = (listing.delivery_options or "PICKUP").split(",")[0]
    proxy.payment_terms = ""

    order = order_service.create_order_from_accepted_offer(
        actor=user, offer=proxy, seller_id=listing.seller_id, buyer_id=user.id,
        product_id=listing.product_id, reservation_ids=[], delivery_option=proxy.delivery_option,
        source="DIRECT_ORDER",
    )
    from app.services.inventory_service import reserve

    reservations = reserve(
        owner_id=listing.seller_id, product_id=listing.product_id,
        quantity_value=float(qty), unit_code=listing.unit_code,
        order_id=order.id, farm_id=listing.farm_id)
    for r in reservations:
        r.order_id = order.id

    order.state = "PAYMENT_PENDING"
    from app.models.order import OrderEvent

    db.session.add(OrderEvent(
        order_id=order.id, actor_id=user.id, event_type="STATE_TRANSITION",
        from_state="ACCEPTED", to_state="PAYMENT_PENDING"))
    db.session.commit()
    return {"order": order_json(order, user.id)}, 201


@jwt_required()
def list_orders():
    user = get_current_user()
    page, per_page = pagination_args()
    pg = order_service.list_orders_for(user, state=query_params().get("state"),
                                       role=query_params().get("role"), page=page, per_page=per_page)
    return paginate_response(pg, lambda o: order_json(o, user.id))


@jwt_required()
def get_order(order_id):
    user = get_current_user()
    order = order_service.get_order_or_404(order_id)
    order_service.assert_order_party(order, user)
    events = _order_events(order)
    return {"order": {**order_json(order, user.id), "events": events}}


def _order_events(order):
    from app.models.order import OrderEvent

    rows = OrderEvent.query.filter_by(order_id=order.id).order_by(OrderEvent.created_at.asc()).all()
    return [
        {"event_type": e.event_type, "from_state": e.from_state, "to_state": e.to_state,
         "at": e.created_at.isoformat()}
        for e in rows
    ]


@jwt_required()
def transition_order(order_id):
    user = get_current_user()
    data = parse_body(type("S", (ma.Schema,), {
        "state": ma.fields.String(required=True),
        "reason": ma.fields.String(missing=""),
    })())
    order = order_service.get_order_or_404(order_id)
    order_service.assert_order_party(order, user)

    target = data["state"].upper()
    if target == "PAID":
        raise forbidden("Payments are confirmed by the payment system via verified provider webhooks",
                        "PAYMENT_SYSTEM_ONLY")
    order_service.transition_order(user, order, target, reason=data.get("reason", ""))

    if target == "COMPLETED":
        from app.models.identity import BuyerProfile, FarmerProfile

        bp = BuyerProfile.query.filter_by(user_id=order.buyer_id).first()
        fp = FarmerProfile.query.filter_by(user_id=order.seller_id).first()
        if bp:
            bp.completed_purchases += 1
        if fp:
            fp.completed_transactions += 1
    db.session.commit()
    return {"order": order_json(order, user.id)}


@jwt_required()
def cancel_order(order_id):
    user = get_current_user()
    data = parse_body(type("S", (ma.Schema,), {"reason": ma.fields.String(missing="")})())
    order = order_service.get_order_or_404(order_id)
    order_service.assert_order_party(order, user)
    order_service.cancel_order(user, order, data.get("reason", ""))
    db.session.commit()
    return {"order": order_json(order, user.id)}
