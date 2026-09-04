import marshmallow as ma
from flask_jwt_extended import jwt_required

from extensions import db
from app.api.helpers import parse_body, query_params
from app.errors import bad_request, conflict, forbidden, not_found
from app.models.identity import User, UserRole, Verification
from app.services import dispute_service, notification_service, risk_service
from app.services.security import get_current_user


@jwt_required()
def list_notifications():
    from app.api.helpers import pagination_args, paginate_response
    from app.models.notifications import Notification

    user = get_current_user()
    unread_only = query_params().get("unread") == "true"
    q = Notification.query.filter_by(user_id=user.id)
    if unread_only:
        q = q.filter_by(read_at=None)
    page, per_page = pagination_args()
    pg = q.order_by(Notification.created_at.desc()).paginate(page=page, per_page=per_page, error_out=False)
    return paginate_response(pg, lambda n: n.to_dict())


@jwt_required()
def mark_notification_read(notification_id):
    from app.models.notifications import Notification

    user = get_current_user()
    n = db.session.get(Notification, notification_id)
    if n is None or n.user_id != user.id:
        raise not_found("Notification not found")
    if n.read_at is None:
        from datetime import datetime, timezone

        n.read_at = datetime.now(timezone.utc)
        db.session.commit()
    return {"read": True}


@jwt_required()
def mark_all_notifications_read():
    from datetime import datetime, timezone

    from sqlalchemy import update

    from app.models.notifications import Notification

    user = get_current_user()
    db.session.execute(
        update(Notification)
        .where(Notification.user_id == user.id, Notification.read_at.is_(None))
        .values(read_at=datetime.now(timezone.utc))
    )
    db.session.commit()
    return {"ok": True}


@jwt_required()
def notification_preferences():
    from app.models.notifications import NotificationPreference

    user = get_current_user()
    prefs = NotificationPreference.query.filter_by(user_id=user.id).all()
    if not prefs:
        defaults = [
            ("ORDER_UPDATE", True), ("MESSAGE", True), ("OFFER", True), ("BID", True),
            ("MARKET_PRICE", True), ("WEATHER_ALERT", True), ("GROUP_MESSAGE", False),
            ("COMMUNITY_POST", False),
        ]
        prefs = [NotificationPreference(user_id=user.id, pref_type=t, in_app=True,
                                        push_enabled=e) for t, e in defaults]
        db.session.add_all(prefs)
        db.session.commit()
    return {"preferences": [{"pref_type": p.pref_type, "push_enabled": p.push_enabled} for p in prefs]}


@jwt_required()
def update_notification_preferences():
    from app.models.notifications import NotificationPreference

    user = get_current_user()
    data = parse_body(type("S", (ma.Schema,), {
        "preferences": ma.fields.List(ma.fields.Dict(), required=True),
    })())
    for item in data["preferences"]:
        ptype = item.get("type")
        if not ptype:
            continue
        row = NotificationPreference.query.filter_by(user_id=user.id, pref_type=ptype).first()
        if row is None:
            row = NotificationPreference(user_id=user.id, pref_type=ptype, in_app=True)
            db.session.add(row)
        row.push_enabled = bool(item.get("push_enabled", True))
    db.session.commit()
    return _prefs(user)


def _prefs(user):
    from app.models.notifications import NotificationPreference

    prefs = NotificationPreference.query.filter_by(user_id=user.id).all()
    return {"preferences": [{"pref_type": p.pref_type, "push_enabled": p.push_enabled} for p in prefs]}


class DeviceTokenSchema(ma.Schema):
    token = ma.fields.String(required=True)
    platform = ma.fields.String(missing="android")


@jwt_required()
def register_device_token():
    from app.models.identity import DeviceToken

    user = get_current_user()
    data = parse_body(DeviceTokenSchema)
    existing = DeviceToken.query.filter_by(user_id=user.id, token=data["token"]).first()
    if existing is None:
        db.session.add(DeviceToken(user_id=user.id, token=data["token"], platform=data["platform"]))
        db.session.commit()
    return {"registered": True}


class VerificationSubmitSchema(ma.Schema):
    level = ma.fields.String(required=True, validate=ma.validate.OneOf(
        ["PHONE_VERIFIED", "ID_BASIC", "FARMER_PLUS", "BUSINESS"]))
    document_keys = ma.fields.List(ma.fields.String(), missing=[])


@jwt_required()
def submit_verification():
    user = get_current_user()
    data = parse_body(VerificationSubmitSchema)
    existing_pending = Verification.query.filter_by(user_id=user.id, level=data["level"],
                                                    status="PENDING").first()
    if existing_pending:
        raise conflict("This verification level is already pending review")
    v = Verification(user_id=user.id, level=data["level"], status="PENDING",
                     document_keys=",".join(data["document_keys"]))
    db.session.add(v)
    db.session.commit()
    return {"verification": {"id": v.id, "level": v.level, "status": v.status}}, 201


@jwt_required()
def my_verifications():
    user = get_current_user()
    rows = Verification.query.filter_by(user_id=user.id).order_by(Verification.created_at.desc()).all()
    return {"verifications": [{"id": v.id, "level": v.level, "status": v.status,
                               "note": v.review_note} for v in rows],
            "current_level": max((v.level for v in rows if v.status == "APPROVED"), default=None)}


class ReviewSchema(ma.Schema):
    subject_role = ma.fields.String(required=True, validate=ma.validate.OneOf(["farmer", "buyer", "logistics"]))
    overall_rating = ma.fields.Integer(required=True, validate=ma.validate.Range(min=1, max=5))
    communication_rating = ma.fields.Integer(validate=ma.validate.Range(min=1, max=5))
    accuracy_rating = ma.fields.Integer(validate=ma.validate.Range(min=1, max=5))
    reliability_rating = ma.fields.Integer(validate=ma.validate.Range(min=1, max=5))
    payment_rating = ma.fields.Integer(validate=ma.validate.Range(min=1, max=5))
    delivery_rating = ma.fields.Integer(validate=ma.validate.Range(min=1, max=5))
    comment = ma.fields.String(missing="")


@jwt_required()
def create_review(order_id):
    from app.services import reputation_service

    user = get_current_user()
    data = parse_body(ReviewSchema)
    review = reputation_service.create_review(user, order_id, data)
    risk_service.detect_fake_reviews(user.id, review.subject_id, None)
    db.session.commit()
    return {"review": {"id": review.id, "overall_rating": review.overall_rating}}, 201


@jwt_required()
def order_reviews(order_id):
    from app.models.order import Review

    rows = Review.query.filter_by(order_id=order_id).all()

    def rj(r):
        return {"id": r.id, "reviewer_id": r.reviewer_id, "subject_role": r.subject_role,
                "overall_rating": r.overall_rating, "comment": r.comment,
                "verified_transaction": r.verified_transaction}

    return {"reviews": [rj(r) for r in rows]}


@jwt_required()
def reputation_summary():
    from app.services.reputation_service import recompute_farmer_reputation, reputation_summary as summary_fn

    user = get_current_user()
    recompute_farmer_reputation(user.id)
    db.session.commit()
    return summary_fn(user.id)


@jwt_required()
def user_reputation(user_id):
    from app.services.reputation_service import reputation_summary

    target = db.session.get(User, user_id)
    if target is None:
        raise not_found("User not found")
    return reputation_summary(target.id)


@jwt_required()
def user_reviews(user_id):
    """Public review history for a user (subject of the review).

    Used by farmer profiles and listing detail to show verified buyer/seller
    feedback. Rows carry reviewer + order/listing context for readable cards.
    """
    from app.models.marketplace import Listing
    from app.models.order import Order, Review

    target = db.session.get(User, user_id)
    if target is None:
        raise not_found("User not found")

    rows = (
        Review.query.filter_by(subject_id=target.id)
        .order_by(Review.created_at.desc())
        .limit(50)
        .all()
    )

    reviewers = {
        u.id: {"id": u.id, "full_name": u.full_name, "username": u.username}
        for u in User.query.filter(User.id.in_({r.reviewer_id for r in rows})).all()
    }
    orders = {
        o.id: o
        for o in Order.query.filter(Order.id.in_({r.order_id for r in rows})).all()
    }
    listings = {
        l.id: l
        for l in Listing.query.filter(
            Listing.id.in_({o.listing_id for o in orders.values() if o.listing_id})
        ).all()
    }

    def row_json(r):
        order = orders.get(r.order_id)
        listing = listings.get(order.listing_id) if order else None
        return {
            "id": r.id,
            "subject_role": r.subject_role,
            "overall_rating": r.overall_rating,
            "communication_rating": r.communication_rating,
            "accuracy_rating": r.accuracy_rating,
            "reliability_rating": r.reliability_rating,
            "payment_rating": r.payment_rating,
            "delivery_rating": r.delivery_rating,
            "comment": r.comment or "",
            "verified_transaction": bool(r.verified_transaction),
            "created_at": r.created_at.isoformat() if r.created_at else None,
            "reviewer": reviewers.get(r.reviewer_id),
            "order": {
                "id": order.id,
                "order_number": order.order_number,
                "quantity_value": float(order.quantity_value),
                "unit_code": order.unit_code,
            }
            if order
            else None,
            "listing": {
                "id": listing.id,
                "title": listing.title,
                "product": listing.product.name,
            }
            if listing
            else None,
        }

    return {"reviews": [row_json(r) for r in rows], "count": len(rows)}


class DisputeOpenSchema(ma.Schema):
    order_id = ma.fields.String(required=True)
    dispute_type = ma.fields.String(required=True)
    description = ma.fields.String(missing="")


@jwt_required()
def open_dispute():
    user = get_current_user()
    data = parse_body(DisputeOpenSchema)
    dispute = dispute_service.open_dispute(user, data["order_id"], {
        "dispute_type": data["dispute_type"], "description": data["description"]})
    db.session.commit()
    return {"dispute": {"id": dispute.id, "state": dispute.state, "dispute_type": dispute.dispute_type}}, 201


@jwt_required()
def add_dispute_evidence(dispute_id):
    user = get_current_user()
    data = parse_body(type("S", (ma.Schema,), {
        "evidence": ma.fields.List(ma.fields.Dict(), required=True)})())
    evidence_rows = dispute_service.add_evidence(user, dispute_id, data["evidence"])
    db.session.commit()
    return {"added": len(evidence_rows)}


@jwt_required()
def my_disputes():
    from app.models.admin import Dispute

    user = get_current_user()
    opened = Dispute.query.filter_by(opened_by=user.id).all()
    against = Dispute.query.filter_by(against_user_id=user.id).all()

    def dj(d):
        return {"id": d.id, "state": d.state, "dispute_type": d.dispute_type,
                "order_id": d.order_id, "opened_by": d.opened_by,
                "created_at": d.created_at.isoformat()}

    seen = set()
    out = []
    for d in opened + against:
        if d.id not in seen:
            seen.add(d.id)
            out.append(dj(d))
    return {"disputes": out}
