from datetime import timedelta

from flask import current_app

from extensions import db, realtime
from app.errors import bad_request, forbidden, not_found
from app.models.base import utcnow
from app.models.community import (
    AUDIENCE_SCOPES,
    STATUS_TYPES,
    Status,
    StatusAudience,
    StatusReaction,
    StatusView,
)


def create_status(user, payload):
    status_type = payload.get("status_type", "text")
    if status_type not in STATUS_TYPES:
        raise bad_request(f"Unsupported status type. Allowed: {STATUS_TYPES}")

    ttl_hours = int(current_app.config.get("STATUS_TTL_HOURS", 24))
    expires_at = utcnow() + timedelta(hours=payload.get("ttl_hours", ttl_hours))

    status = Status(
        author_id=user.id,
        status_type=status_type,
        body_text=payload.get("body_text", ""),
        media_key=payload.get("media_key"),
        template_kind=payload.get("template_kind"),
        listing_id=payload.get("listing_id"),
        product_id=payload.get("product_id"),
        quantity_label=payload.get("quantity_label", ""),
        expires_at=expires_at,
    )
    db.session.add(status)
    db.session.flush()

    audience = payload.get("audience", {"scope": "EVERYONE"})
    scope = audience.get("scope", "EVERYONE")
    if scope not in AUDIENCE_SCOPES:
        raise bad_request("Invalid audience scope")
    db.session.add(StatusAudience(status_id=status.id, scope=scope))
    for uid in audience.get("user_ids", []) or []:
        db.session.add(StatusAudience(status_id=status.id, scope="SELECTED_USERS", target_user_id=uid))
    for cid in audience.get("community_ids", []) or []:
        db.session.add(StatusAudience(status_id=status.id, scope="COMMUNITIES", target_community_id=cid))

    db.session.flush()
    realtime.emit_to_user(user.id, "status.created", {"status_id": status.id})
    return status


def visible_statuses(viewer, author_ids=None):
    now = utcnow()
    q = Status.query.filter(
        Status.deleted_at.is_(None),
        Status.expires_at > now,
        Status.author_id != viewer.id,
    )
    if author_ids:
        q = q.filter(Status.author_id.in_(author_ids))

    statuses = q.order_by(Status.created_at.desc()).limit(100).all()
    out = []
    for s in statuses:
        audiences = StatusAudience.query.filter_by(status_id=s.id).all()
        scopes = {a.scope for a in audiences}
        allowed = False
        if "EVERYONE" in scopes:
            allowed = True
        elif "SELECTED_USERS" in scopes and any(a.target_user_id == viewer.id for a in audiences):
            allowed = True
        elif "FOLLOWERS" in scopes:
            from app.models.social import Follow

            allowed = Follow.query.filter_by(follower_id=s.author_id, followed_id=viewer.id).first() is not None
        elif "COMMUNITIES" in scopes:
            from app.models.community import CommunityMember

            shared = CommunityMember.query.filter(
                CommunityMember.user_id == viewer.id
            ).all()
            viewer_communities = {m.community_id for m in shared}
            allowed = any(a.target_community_id in viewer_communities for a in audiences if a.target_community_id)
        elif scopes == {"PRIVATE"}:
            allowed = False
        if allowed:
            out.append(s)
    return out


def view_status(viewer, status_id):
    status = db.session.get(Status, status_id)
    if status is None:
        raise not_found("Status not found")
    existing = StatusView.query.filter_by(status_id=status_id, viewer_id=viewer.id).first()
    if existing is None:
        db.session.add(StatusView(status_id=status_id, viewer_id=viewer.id))
    return {"viewers": status.viewers and len(status.viewers) or 0}


def react_status(user, status_id, emoji):
    from sqlalchemy.exc import IntegrityError

    status = db.session.get(Status, status_id)
    existing = StatusReaction.query.filter_by(status_id=status_id, user_id=user.id).first()
    if not emoji:
        if existing:
            db.session.delete(existing)
        return {"reacted": False}
    if existing is not None:
        existing.emoji = emoji
    else:
        try:
            db.session.add(StatusReaction(status_id=status_id, user_id=user.id, emoji=emoji))
            db.session.flush()
        except IntegrityError:
            db.session.rollback()
    return {"reacted": True, "emoji": emoji}


def expire_statuses():
    now = utcnow()
    expired = Status.query.filter(Status.expires_at <= now, Status.deleted_at.is_(None)).all()
    for s in expired:
        s.deleted_at = now
    if expired:
        db.session.commit()
    return len(expired)


def convert_listing_to_status(user, listing):
    payload = {
        "status_type": "product",
        "body_text": f"🌾 {listing.title}",
        "listing_id": listing.id,
        "product_id": listing.product_id,
        "quantity_label": f"{float(listing.available_quantity):g} {listing.unit_code} available",
        "template_kind": "HARVEST_READY" if listing.expected_harvest_date else "PRODUCT",
        "audience": {"scope": "EVERYONE"},
    }
    return create_status(user, payload)
