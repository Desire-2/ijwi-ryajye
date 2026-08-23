from datetime import timedelta

from extensions import db
from app.models.base import utcnow
from app.models.admin import RiskEvent
from app.models.identity import User
from app.models.order import Order, Review

SCORE_THRESHOLDS = {"review": 30, "suspend_review": 50}


def note_event(user_id, event_type, score_delta, detail=None, flag=False):
    recent = (
        RiskEvent.query.filter(
            RiskEvent.user_id == user_id,
            RiskEvent.created_at > utcnow() - timedelta(days=30),
        ).all()
    )
    total = sum(e.score_delta for e in recent) + score_delta
    flag = flag or total >= SCORE_THRESHOLDS["review"]
    event = RiskEvent(
        user_id=user_id,
        event_type=event_type,
        score_delta=score_delta,
        detail_json=__import__("json").dumps(detail or {}),
        flagged_for_review=flag,
    )
    db.session.add(event)
    db.session.flush()
    return event


def risk_score(user_id):
    since = utcnow() - timedelta(days=90)
    events = RiskEvent.query.filter(RiskEvent.user_id == user_id, RiskEvent.created_at > since).all()
    return sum(e.score_delta for e in events)


def detect_self_trading(order):
    if order.buyer_id == order.seller_id:
        note_event(order.buyer_id, "SELF_TRADING", 25, {"order": order.order_number}, flag=True)
        return True
    same_device_hint = False
    return same_device_hint


def detect_fake_reviews(reviewer_id, subject_id, order):
    if reviewer_id == subject_id:
        note_event(reviewer_id, "FAKE_REVIEW", 30, {}, flag=True)
        return True
    prior = Review.query.filter(
        Review.reviewer_id == reviewer_id,
        Review.created_at > utcnow() - timedelta(hours=1),
    ).count()
    if prior >= 5:
        note_event(reviewer_id, "FAKE_REVIEW", 10, {"burst": prior})
        return False
    return False


def check_multi_account_signals(new_user_phone, new_user_email, device_fingerprint=None):
    signals = []
    if new_user_phone:
        similar = User.query.filter(User.phone != new_user_phone).limit(0).all()
    return signals


def suspicious_withdrawal_check(withdrawal):
    from app.services.wallet_service import get_or_create_wallet

    wallet = get_or_create_wallet(withdrawal.user_id)
    account_age_hours = None
    user = db.session.get(User, withdrawal.user_id)
    if user:
        account_age_hours = (utcnow() - user.created_at).total_seconds() / 3600
    risky = False
    reasons = []
    if account_age_hours is not None and account_age_hours < 24 and withdrawal.amount_minor > 100000:
        risky = True
        reasons.append("large_withdrawal_new_account")
    if risk_score(withdrawal.user_id) >= SCORE_THRESHOLDS["review"]:
        risky = True
        reasons.append("elevated_risk_score")
    if risky:
        note_event(withdrawal.user_id, "SUSPICIOUS_WITHDRAWAL", 15,
                   {"withdrawal": withdrawal.id, "reasons": reasons}, flag=True)
    return risky, reasons
