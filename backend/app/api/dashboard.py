"""Seller dashboard: aggregated, real metrics from the current user's own marketplace data.

Single GET endpoint so the app can render KPIs, listing performance, recent offers and
recent orders without downloading several paginated lists and computing totals client-side.
Every number here is computed server-side from the seller's own rows only.
"""
from flask_jwt_extended import jwt_required
from sqlalchemy import func

from extensions import db
from app.api.serializers import listing_json, offer_json, order_json
from app.models.identity import FarmerProfile, User
from app.models.marketplace import Listing
from app.models.order import Order
from app.models.trade import Offer
from app.services.security import get_current_user
from app.services.wallet_service import wallet_summary

# States in which money has actually moved / the sale is being fulfilled.
_MONETIZED = ("PAID", "PROCESSING", "READY_FOR_PICKUP", "IN_TRANSIT", "DELIVERED", "COMPLETED")
# States that still need seller (or counterparty) action.
_OPEN = ("PAID", "PROCESSING", "READY_FOR_PICKUP", "IN_TRANSIT", "DELIVERED")
_CLOSED_OUT = ("CANCELLED", "REFUNDED", "DISPUTED")


@jwt_required()
def seller_dashboard():
    user = get_current_user()
    seller_id = user.id

    listings = (
        Listing.query.filter(Listing.seller_id == seller_id, Listing.deleted_at.is_(None))
        .order_by(Listing.created_at.desc())
        .limit(500)
        .all()
    )

    # ---- Aggregates per listing (grouped once, not N+1) ----
    offer_counts = {
        (listing_id, state): count
        for listing_id, state, count in db.session.query(
            Offer.listing_id, Offer.state, func.count()
        )
        .filter(Offer.seller_id == seller_id)
        .group_by(Offer.listing_id, Offer.state)
        .all()
    }
    order_rows = db.session.query(
        Order.listing_id,
        Order.state,
        func.count(),
        func.coalesce(func.sum(Order.total_amount_minor), 0),
        func.coalesce(func.sum(Order.platform_fee_minor), 0),
    ).filter(Order.seller_id == seller_id).group_by(Order.listing_id, Order.state).all()

    order_agg = {}
    for listing_id, state, count, total, fee in order_rows:
        order_agg[(listing_id, state)] = (count, int(total), int(fee))

    def _per_listing(listing):
        total, sold_value, fees = 0, 0, 0
        offers_pending = 0
        for (lid, state), count in offer_counts.items():
            if lid == listing.id and state == "PENDING":
                offers_pending = count
        for (lid, state), (count, ttl, fee) in order_agg.items():
            if lid != listing.id:
                continue
            total += count
            if state in _MONETIZED:
                sold_value += ttl
                fees += fee
        return {
            "view_count": listing.view_count or 0,
            "offers_pending": offers_pending,
            "orders_total": total,
            "sold_value_minor": sold_value,
            "fees_minor": fees,
        }

    # ---- Summary across everything ----
    offers_total = sum(offer_counts.values())
    offers_pending = sum(c for (_, state), c in offer_counts.items() if state == "PENDING")
    order_totals = [v for _, v in order_agg.items()]
    orders_total = sum(v[0] for v in order_totals)
    orders_open = sum(v[0] for (_, state), v in order_agg.items() if state in _OPEN)
    orders_completed = sum(
        v[0] for (_, state), v in order_agg.items() if state == "COMPLETED"
    )
    orders_closed_out = sum(
        v[0] for (_, state), v in order_agg.items() if state in _CLOSED_OUT
    )
    gross_sales = sum(
        v[1] for (_, state), v in order_agg.items() if state in _MONETIZED
    )
    fees_total = sum(v[2] for (_, state), v in order_agg.items() if state in _MONETIZED)

    profile = FarmerProfile.query.filter_by(user_id=seller_id).first()
    wallet = wallet_summary(seller_id)

    return {
        "summary": {
            "listings_total": len(listings),
            "listings_active": sum(1 for l in listings if l.state == "ACTIVE"),
            "total_views": sum(l.view_count or 0 for l in listings),
            "offers_total": offers_total,
            "offers_pending": offers_pending,
            "orders_total": orders_total,
            "orders_open": orders_open,
            "orders_completed": orders_completed,
            "orders_closed_out": orders_closed_out,
            "gross_sales_minor": gross_sales,
            "fees_minor": fees_total,
            "net_revenue_minor": gross_sales - fees_total,
            "rating_avg": float(profile.rating_avg or 0) if profile else 0.0,
            "rating_count": profile.rating_count if profile else 0,
            "reputation_tier": profile.reputation_tier if profile else "NEW_MEMBER",
            "completed_transactions": profile.completed_transactions if profile else 0,
            "response_rate_bps": profile.response_rate_bps if profile else 0,
        },
        "wallet": wallet,
        "listings": [
            {**listing_json(l, user), **_per_listing(l)}
            for l in listings
        ],
        "recent_offers": _recent_offers(seller_id),
        "recent_orders": _recent_orders(seller_id),
    }


def _recent_offers(seller_id, limit=8):
    rows = (
        Offer.query.filter(Offer.seller_id == seller_id)
        .order_by(Offer.created_at.desc())
        .limit(limit)
        .all()
    )
    if not rows:
        return []
    buyers = {
        u.id: {"id": u.id, "full_name": u.full_name, "username": u.username}
        for u in User.query.filter(User.id.in_({r.buyer_id for r in rows})).all()
    }
    listings = {
        l.id: {"id": l.id, "title": l.title, "product": l.product.name}
        for l in Listing.query.filter(Listing.id.in_({r.listing_id for r in rows})).all()
    }
    return [
        {
            **offer_json(r),
            "buyer": buyers.get(r.buyer_id),
            "listing": listings.get(r.listing_id),
        }
        for r in rows
    ]


def _recent_orders(seller_id, limit=8):
    rows = (
        Order.query.filter(Order.seller_id == seller_id, Order.state != "DRAFT")
        .order_by(Order.created_at.desc())
        .limit(limit)
        .all()
    )
    if not rows:
        return []
    buyers = {
        u.id: {"id": u.id, "full_name": u.full_name, "username": u.username}
        for u in User.query.filter(User.id.in_({r.buyer_id for r in rows})).all()
    }
    listings = {
        l.id: {"id": l.id, "title": l.title, "product": l.product.name}
        for l in Listing.query.filter(Listing.id.in_({r.listing_id for r in rows})).all()
    }
    return [
        {
            **order_json(r, seller_id),
            "buyer": buyers.get(r.buyer_id),
            "listing": listings.get(r.listing_id),
        }
        for r in rows
    ]
