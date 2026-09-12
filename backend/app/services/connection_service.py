"""Mutual connections, blocking and people discovery.

This is the single social-connection layer for the Community ecosystem:
connection requests, acceptance/decline, the connection graph that powers
recommended connections and people-nearby, plus explicit user blocking.

Privacy rules (per product spec):
- Nearby people are surfaced at district/region granularity only. Exact
  coordinates are never exposed. A user's district is only shown to others
  when they have enabled visibility_location_exact.
- Recommendations are explainable (same crop, same district, mutual friends).
"""
from extensions import db
from app.errors import bad_request, conflict, forbidden, not_found
from app.models.base import utcnow
from app.models.identity import BlockedUser, FarmerProfile, User
from app.models.social import Connection

CONNECTIONS_PER_PAGE_DEFAULT = 50


def _normalize_pair(a_id, b_id):
    if a_id < b_id:
        return a_id, b_id
    return b_id, a_id


def get_connection_row(a_id, b_id):
    ua, ub = _normalize_pair(a_id, b_id)
    return Connection.query.filter_by(user_a_id=ua, user_b_id=ub).first()


def _assert_can_connect(actor_id, other_id):
    if actor_id == other_id:
        raise bad_request("You cannot connect with yourself")
    target = db.session.get(User, other_id)
    if target is None:
        raise not_found("User not found")
    blocked = BlockedUser.query.filter(
        ((BlockedUser.blocker_id == actor_id) & (BlockedUser.blocked_id == other_id))
        | ((BlockedUser.blocker_id == other_id) & (BlockedUser.blocked_id == actor_id))
    ).first()
    if blocked is not None:
        raise forbidden("You cannot connect with this user", "USER_BLOCKED")


def request_connection(actor, other_id):
    _assert_can_connect(actor.id, other_id)
    row = get_connection_row(actor.id, other_id)
    if row is not None:
        if row.status == "ACCEPTED":
            raise conflict("You are already connected")
        if row.status == "PENDING":
            raise conflict("A connection request is already pending")
        # Declined earlier: allow the request to be reopened by either party.
        row.status = "PENDING"
        row.requested_by = actor.id
        row.responded_at = None
        db.session.flush()
        _notify_request(other_id, actor)
        return row
    ua, ub = _normalize_pair(actor.id, other_id)
    row = Connection(user_a_id=ua, user_b_id=ub, status="PENDING", requested_by=actor.id)
    db.session.add(row)
    db.session.flush()
    _notify_request(other_id, actor)
    return row


def _notify_request(target_id, actor):
    from app.services.notification_service import notify

    notify(target_id, "CONNECTION_REQUEST", f"{actor.full_name} sent you a connection request",
           actor.full_name or "", subject_type="user", subject_id=actor.id, batch_key="connection_requests")


def _assert_is_target(actor, row):
    """Only one of the two users - and specifically the request target -
    may accept or decline."""
    if actor.id not in (row.user_a_id, row.user_b_id):
        raise forbidden("Not part of this connection")
    if row.requested_by == actor.id:
        raise conflict("You can only accept requests sent to you")


def accept_connection(actor, connection_id):
    row = db.session.get(Connection, connection_id)
    if row is None:
        raise not_found("Connection request not found")
    _assert_is_target(actor, row)
    if row.status == "ACCEPTED":
        return row
    row.status = "ACCEPTED"
    row.responded_at = utcnow()
    db.session.flush()
    from app.services.notification_service import notify

    notify(row.requested_by, "CONNECTION_ACCEPTED",
           f"{actor.full_name} accepted your connection request",
           subject_type="user", subject_id=actor.id, batch_key="connection_accepts")
    return row


def decline_connection(actor, connection_id):
    row = db.session.get(Connection, connection_id)
    if row is None:
        raise not_found("Connection request not found")
    _assert_is_target(actor, row)
    if row.status != "PENDING":
        return row
    row.status = "DECLINED"
    row.responded_at = utcnow()
    db.session.flush()
    return row


def cancel_connection(actor, connection_id):
    """Requester retracts a pending request (or an admin cleans up)."""
    row = db.session.get(Connection, connection_id)
    if row is None:
        raise not_found("Connection request not found")
    if row.requested_by != actor.id and "ADMIN" not in actor.role_codes():
        raise forbidden("You can only cancel your own requests")
    db.session.delete(row)
    db.session.flush()
    return {"removed": True}


def remove_connection(actor, other_id):
    """Sever an accepted connection with another user."""
    row = get_connection_row(actor.id, other_id)
    if row is None:
        return {"removed": False}
    db.session.delete(row)
    db.session.flush()
    return {"removed": True}


def list_connections(user, status=None, page=1, per_page=CONNECTIONS_PER_PAGE_DEFAULT):
    from app.models.posts import UserFollow

    rows = Connection.query.filter(
        db.or_(Connection.user_a_id == user.id, Connection.user_b_id == user.id)
    )
    if status:
        rows = rows.filter(Connection.status == status.upper())
    rows = rows.order_by(Connection.created_at.desc())
    pagination = rows.paginate(page=page, per_page=per_page, error_out=False)
    out = []
    for row in pagination.items:
        other = db.session.get(User, row.other_id(user.id))
        if other is None:
            continue
        item = _user_card(other)
        item["status"] = row.status
        item["requested_by"] = row.requested_by
        item["connection_id"] = row.id
        item["direction"] = "outgoing" if row.requested_by == user.id else "incoming"
        item["is_following_me"] = UserFollow.query.filter_by(
            follower_id=other.id, followed_id=user.id).first() is not None
        item["i_am_following"] = UserFollow.query.filter_by(
            follower_id=user.id, followed_id=other.id).first() is not None
        out.append(item)
    return {
        "items": out,
        "pagination": {
            "page": pagination.page,
            "per_page": pagination.per_page,
            "total": pagination.total,
            "total_pages": (pagination.total + pagination.per_page - 1) // pagination.per_page
            if pagination.per_page else 0,
        },
    }


def pending_requests(user, page=1, per_page=CONNECTIONS_PER_PAGE_DEFAULT):
    rows = Connection.query.filter(
        db.or_(Connection.user_a_id == user.id, Connection.user_b_id == user.id),
        Connection.status == "PENDING",
        Connection.requested_by != user.id,
    ).order_by(Connection.created_at.desc())
    pagination = rows.paginate(page=page, per_page=per_page, error_out=False)
    out = []
    for row in pagination.items:
        other = db.session.get(User, row.other_id(user.id))
        if other is None:
            continue
        item = _user_card(other)
        item["status"] = row.status
        item["requested_by"] = row.requested_by
        item["connection_id"] = row.id
        item["direction"] = "incoming"
        out.append(item)
    return {
        "items": out,
        "pagination": {
            "page": pagination.page,
            "per_page": pagination.per_page,
            "total": pagination.total,
            "total_pages": (pagination.total + pagination.per_page - 1) // pagination.per_page
            if pagination.per_page else 0,
        },
    }


def connection_status_between(viewer_id, other_id):
    """Public helper used by serializers: None | pending_sent | pending_received | connected."""
    if viewer_id == other_id:
        return None
    row = get_connection_row(viewer_id, other_id)
    if row is None:
        return None
    if row.status == "ACCEPTED":
        return "connected"
    if row.status == "PENDING":
        return "pending_sent" if row.requested_by == viewer_id else "pending_received"
    return None


def block_user(actor, other_id):
    if actor.id == other_id:
        raise bad_request("You cannot block yourself")
    target = db.session.get(User, other_id)
    if target is None:
        raise not_found("User not found")
    existing = BlockedUser.query.filter_by(blocker_id=actor.id, blocked_id=other_id).first()
    if existing is None:
        db.session.add(BlockedUser(blocker_id=actor.id, blocked_id=other_id))
    # Blocking also severs any connection and both follow directions.
    row = get_connection_row(actor.id, other_id)
    if row is not None:
        db.session.delete(row)
    from app.models.posts import UserFollow

    UserFollow.query.filter(
        db.or_(
            db.and_(UserFollow.follower_id == actor.id, UserFollow.followed_id == other_id),
            db.and_(UserFollow.follower_id == other_id, UserFollow.followed_id == actor.id),
        )
    ).delete(synchronize_session=False)
    db.session.flush()
    return {"blocked": True}


def unblock_user(actor, other_id):
    BlockedUser.query.filter_by(blocker_id=actor.id, blocked_id=other_id).delete(
        synchronize_session=False)
    db.session.flush()
    return {"blocked": False}


def my_blocked(actor, page=1, per_page=CONNECTIONS_PER_PAGE_DEFAULT):
    rows = BlockedUser.query.filter_by(blocker_id=actor.id) \
        .order_by(BlockedUser.created_at.desc())
    pagination = rows.paginate(page=page, per_page=per_page, error_out=False)
    out = []
    for b in pagination.items:
        other = db.session.get(User, b.blocked_id)
        if other is not None:
            item = _user_card(other)
            item["blocked_at"] = b.created_at.isoformat() if b.created_at else None
            out.append(item)
    return {
        "items": out,
        "pagination": {
            "page": pagination.page,
            "per_page": pagination.per_page,
            "total": pagination.total,
            "total_pages": (pagination.total + pagination.per_page - 1) // pagination.per_page
            if pagination.per_page else 0,
        },
    }


def _user_card(user):
    return {
        "id": user.id,
        "username": user.username,
        "full_name": user.full_name,
        "region": user.region,
        "district": user.district if user.visibility_location_exact else None,
        "profile_photo_url": (
            f"media/serve/{user.profile_photo_key}" if user.profile_photo_key else None),
        "main_crops": [c for c in (user.farmer_profile.main_crops or "").split(",") if c]
        if user.farmer_profile else [],
        "years_experience": user.farmer_profile.years_experience if user.farmer_profile else 0,
        "rating_avg": float(user.farmer_profile.rating_avg or 0) if user.farmer_profile else 0,
        "rating_count": user.farmer_profile.rating_count if user.farmer_profile else 0,
        "completed_transactions": user.farmer_profile.completed_transactions
        if user.farmer_profile else 0,
        "reputation_tier": user.farmer_profile.reputation_tier
        if user.farmer_profile else "NEW_MEMBER",
        "primary_role": user.primary_role,
    }


def recommended_connections(actor, limit=20):
    """Explainable people suggestions: same district, same crops, mutual
    follow/connection, shared communities/cooperative. Never empty as a black
    box; every suggestion carries a human-readable reason."""
    from app.models.community import CommunityMember
    from app.models.posts import UserFollow

    # People already connected, pending, or followed by us are excluded.
    connected_pairs = Connection.query.filter(
        db.or_(Connection.user_a_id == actor.id, Connection.user_b_id == actor.id)
    ).all()
    excluded = {actor.id}
    for row in connected_pairs:
        excluded.add(row.other_id(actor.id))
    followed = {f.followed_id for f in UserFollow.query.filter_by(follower_id=actor.id).all()}
    excluded |= followed
    blocked_ids = {b.blocked_id for b in BlockedUser.query.filter_by(blocker_id=actor.id).all()}
    excluded |= blocked_ids

    # Candidate pool: users other than the excluded ones. Cheap breadth first,
    # bounded; precise ranking computed in Python for explainable reasons.
    candidates = User.query.filter(User.id.notin_(excluded)).limit(500).all()

    my_profile = actor.farmer_profile
    my_region = (actor.region or "").strip().lower()
    my_district = (actor.district or "").strip().lower()
    my_crops = {c.strip().lower() for c in (my_profile.main_crops or "").split(",") if c.strip()} \
        if my_profile else set()
    my_coop = my_profile.cooperative_id if my_profile else None
    my_communities = {m.community_id for m in
                      CommunityMember.query.filter_by(user_id=actor.id).all()}
    my_followers = {f.follower_id for f in UserFollow.query.filter_by(followed_id=actor.id).all()}
    my_connections = {row.other_id(actor.id) for row in
                      Connection.query.filter(
                          db.or_(Connection.user_a_id == actor.id, Connection.user_b_id == actor.id),
                          Connection.status == "ACCEPTED").all()}

    def _score(u):
        score = 0
        reasons = []
        profile = u.farmer_profile
        crops = {c.strip().lower() for c in (profile.main_crops or "").split(",") if c.strip()} \
            if profile else set()
        shared_crops = my_crops & crops
        if shared_crops:
            score += 2 * len(shared_crops)
            reasons.append(f"Grows {', '.join(sorted(shared_crops)[:2]).title()} like you")
        if u.district and my_district and u.district.strip().lower() == my_district:
            score += 3
            reasons.append("Same district")
        elif u.region and my_region and u.region.strip().lower() == my_region:
            score += 1
            reasons.append("Same region")
        if u.id in my_connections:
            score += 4
            reasons.append("A close connection of someone you know")
        if u.id in my_followers:
            score += 2
            reasons.append("Follows you")
        if profile and my_coop and profile.cooperative_id == my_coop:
            score += 3
            reasons.append("Same cooperative")
        their_communities = {m.community_id for m in
                             CommunityMember.query.filter_by(user_id=u.id).all()}
        shared_comms = my_communities & their_communities
        if shared_comms:
            score += 2 * len(shared_comms)
            reasons.append("Member of the same community")
        return score, reasons[:3]

    ranked = []
    for u in candidates:
        score, reasons = _score(u)
        if score > 0:
            ranked.append((u, score, reasons))
    ranked.sort(key=lambda x: -x[1])
    out = []
    for u, score, reasons in ranked[:limit]:
        item = _user_card(u)
        item["reason"] = reasons[0] if reasons else "In your network"
        item["score"] = score
        out.append(item)
    return out


def nearby_people(actor, limit=50):
    """People in the same region/district (approximate only, no coordinates).
    District-level precision only when both users opted into visibility_location_exact."""
    from app.models.posts import UserFollow

    blocked_ids = {b.blocked_id for b in BlockedUser.query.filter_by(blocker_id=actor.id).all()}
    blocked_ids.add(actor.id)

    same_district = []
    same_region = []
    if actor.district and actor.visibility_location_exact:
        q = User.query.filter(
            User.id.notin_(blocked_ids),
            User.district == actor.district,
            User.visibility_location_exact.is_(True),
        ).limit(limit)
        for u in q.all():
            same_district.append((u, "district"))
    if actor.region:
        q = User.query.filter(
            User.id.notin_(blocked_ids),
            User.region == actor.region,
        ).limit(limit)
        for u in q.all():
            if any(existing.id == u.id for existing, _ in same_district):
                continue
            same_region.append((u, "region"))

    out = []
    for u, relation in [*same_district, *same_region]:
        if len(out) >= limit:
            break
        item = _user_card(u)
        item["relation"] = relation
        item["distance_label"] = (
            "Same district" if relation == "district" else "Same region")
        item["connection_status"] = connection_status_between(actor.id, u.id)
        item["is_following_me"] = UserFollow.query.filter_by(
            follower_id=u.id, followed_id=actor.id).first() is not None
        out.append(item)
    return out