from decimal import Decimal

from extensions import db
from app.errors import bad_request, conflict, forbidden, not_found
from app.models.base import utcnow
from app.models.identity import FarmerProfile, BuyerProfile, LogisticsProfile, User, Verification
from app.models.order import Order, Review


def apply_review_to_profile(review):
    if review.subject_role == "farmer":
        profile = FarmerProfile.query.filter_by(user_id=review.subject_id).first()
        if profile:
            _merge(profile, review)
    elif review.subject_role == "buyer":
        profile = BuyerProfile.query.filter_by(user_id=review.subject_id).first()
        if profile:
            _merge(profile, review)
    elif review.subject_role in ("logistics", "transporter"):
        profile = LogisticsProfile.query.filter_by(user_id=review.subject_id).first()
        if profile:
            _merge(profile, review)


def _merge(profile, review):
    count = int(profile.rating_count or 0)
    current_avg = Decimal(str(profile.rating_avg or 0))
    new_count = count + 1
    new_avg = ((current_avg * count) + Decimal(review.overall_rating)) / new_count
    profile.rating_avg = round(new_avg, 2)
    profile.rating_count = new_count
    db.session.flush()


def create_review(reviewer, order_id, payload):
    order = db.session.get(Order, order_id)
    if order is None:
        raise not_found("Order not found")
    if order.state != "COMPLETED":
        raise conflict("Reviews are only allowed for completed orders", "ORDER_NOT_COMPLETED")

    is_buyer = reviewer.id == order.buyer_id
    is_seller = reviewer.id == order.seller_id
    subject_role = payload.get("subject_role")

    if is_buyer and subject_role == "farmer":
        subject_id = order.seller_id
    elif is_seller and subject_role == "buyer":
        subject_id = order.buyer_id
    elif subject_role == "logistics" and (is_buyer or is_seller) and order.delivery_id:
        from app.models.logistics import Delivery

        delivery = db.session.get(Delivery, order.delivery_id)
        subject_id = delivery.provider_id
    else:
        raise forbidden("You cannot leave this review for this order")

    overall = int(payload.get("overall_rating", 5))
    if not 1 <= overall <= 5:
        raise bad_request("overall_rating must be between 1 and 5")

    from sqlalchemy.exc import IntegrityError

    review = Review(
        order_id=order.id,
        reviewer_id=reviewer.id,
        subject_id=subject_id,
        subject_role=subject_role,
        overall_rating=overall,
        communication_rating=payload.get("communication_rating"),
        accuracy_rating=payload.get("accuracy_rating"),
        reliability_rating=payload.get("reliability_rating"),
        payment_rating=payload.get("payment_rating"),
        delivery_rating=payload.get("delivery_rating"),
        comment=payload.get("comment", ""),
        verified_transaction=True,
    )
    try:
        db.session.add(review)
        db.session.flush()
    except IntegrityError:
        db.session.rollback()
        raise conflict("You have already reviewed this transaction", "DUPLICATE_REVIEW")

    apply_review_to_profile(review)
    from app.services.audit_service import record as audit

    audit(reviewer, "review.created", "review", review.id)
    return review


def recompute_farmer_reputation(user_id):
    profile = FarmerProfile.query.filter_by(user_id=user_id).first()
    user = db.session.get(User, user_id)
    if profile is None or user is None:
        return None

    sold = Order.query.filter(Order.seller_id == user_id).count()
    completed = Order.query.filter(Order.seller_id == user_id, Order.state == "COMPLETED").count()
    cancelled = Order.query.filter(Order.seller_id == user_id, Order.state == "CANCELLED").count()

    profile.completed_transactions = completed
    profile.cancelled_transactions = cancelled

    response_rate = _compute_response_rate(user_id)

    score = min(completed, 50) * 4
    score -= cancelled * 8
    score += int(float(profile.rating_avg or 0)) * 10
    score += response_rate // 20

    tier = "NEW_MEMBER"
    verified_levels = {
        v.level for v in Verification.query.filter_by(user_id=user_id, status="VERIFIED").all()
    }
    if completed >= 5 and "PHONE" in verified_levels:
        tier = "ESTABLISHED"
    if completed >= 25 and ("FARM" in verified_levels or "IDENTITY" in verified_levels):
        tier = "TRUSTED"
    if completed >= 100 and "BUSINESS" in verified_levels:
        tier = "PREMIUM_SELLER"

    profile.reputation_score = max(0, score)
    profile.reputation_tier = tier
    db.session.flush()
    return {"tier": tier, "score": profile.reputation_score}


def _compute_response_rate(user_id):
    from app.models.trade import Offer

    received = Offer.query.filter(Offer.seller_id == user_id, Offer.listing_id.isnot(None)).count()
    responded = Offer.query.filter(
        Offer.seller_id == user_id,
        Offer.responded_at.isnot(None),
        Offer.buyer_id != user_id,
    ).count() + Offer.query.filter(
        Offer.buyer_id == user_id,
        Offer.responded_at.isnot(None),
        Offer.parent_offer_id.is_(None) if hasattr(Offer, "parent_offer_id") else True,
    ).count()
    total_inbound = (
        db.session.query(__import__("sqlalchemy").func.count())
        .select_from(Offer)
        .filter(Offer.seller_id != user_id, Offer.buyer_id == user_id, Offer.responded_at.is_(None))
        .scalar() or 0
    )
    denominator = responded + total_inbound
    if denominator == 0:
        return 0
    return min(int(responded / denominator * 10000), 10000)


def reputation_summary(user_id):
    profile = FarmerProfile.query.filter_by(user_id=user_id).first()
    buyer = BuyerProfile.query.filter_by(user_id=user_id).first()
    logistics = LogisticsProfile.query.filter_by(user_id=user_id).first()
    out = {"tier": "NEW_MEMBER"}
    if profile:
        out = {
            "tier": profile.reputation_tier,
            "score": profile.reputation_score,
            "rating_avg": float(profile.rating_avg or 0),
            "rating_count": profile.rating_count,
            "completed_transactions": profile.completed_transactions,
            "cancelled": profile.cancelled_transactions,
        }
    elif buyer:
        out = {
            "tier": "BUYER",
            "rating_avg": float(buyer.rating_avg or 0),
            "rating_count": buyer.rating_count,
            "completed_purchases": buyer.completed_purchases,
        }
    elif logistics:
        out = {
            "tier": "LOGISTICS",
            "rating_avg": float(logistics.rating_avg or 0),
            "rating_count": logistics.rating_count,
            "completed_deliveries": logistics.completed_deliveries,
        }
    return out
