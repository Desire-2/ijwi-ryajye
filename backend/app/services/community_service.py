from extensions import db, realtime
from app.errors import bad_request, forbidden, not_found
from app.models.base import utcnow
from app.models.community import (
    Community,
    CommunityAnnouncement,
    CommunityGroup,
    CommunityMember,
)
from app.services.audit_service import record as audit


def get_community_or_404(community_id):
    c = db.session.get(Community, community_id)
    if c is None:
        raise not_found("Community not found")
    return c


def join_community(user, community):
    existing = CommunityMember.query.filter_by(community_id=community.id, user_id=user.id).first()
    if existing:
        return existing
    member = CommunityMember(community_id=community.id, user_id=user.id)
    db.session.add(member)
    community.member_count += 1
    db.session.flush()
    audit(user, "community.joined", "community", community.id)
    return member


def attach_group(actor, community, group_id, space_type="discussion"):
    from app.models.group import Group

    group = db.session.get(Group, group_id)
    if group is None:
        raise not_found("Group not found")
    link = CommunityGroup.query.filter_by(community_id=community.id, group_id=group.id).first()
    if link is None:
        link = CommunityGroup(community_id=community.id, group_id=group.id, space_type=space_type)
        db.session.add(link)
        db.session.flush()
        group.community_id = community.id
    return link


def announce(actor, community, title, body, pinned=False):
    member = CommunityMember.query.filter_by(community_id=community.id, user_id=actor.id).first()
    is_admin = "ADMIN" in actor.role_codes() or (member and member.role == "admin")
    if not is_admin:
        raise forbidden("Only community admins can post announcements")

    ann = CommunityAnnouncement(
        community_id=community.id, author_id=actor.id, title=title, body_text=body, pinned=pinned
    )
    db.session.add(ann)

    members = CommunityMember.query.filter_by(community_id=community.id).all()
    from app.services.notification_service import notify

    for m in members:
        if m.user_id != actor.id:
            notify(m.user_id, "COMMUNITY_ANNOUNCEMENT", f"{community.name}: {title}",
                   body[:140], subject_type="community_announcement", subject_id=ann.id,
                   batch_key=f"ca_{community.id}", commit=False)
    audit(actor, "community.announcement", "community", community.id)
    return ann


def recommend_for_user(user, limit=10):
    joined_ids = [
        m.community_id for m in CommunityMember.query.filter_by(user_id=user.id).all()
    ]
    from app.models.farm import FarmCrop, Farm

    crops = (
        db.session.query(FarmCrop.product_id)
        .join(Farm, FarmCrop.farm_id == Farm.id)
        .filter(Farm.owner_id == user.id)
        .all()
    )
    crop_product_ids = {c[0] for c in crops}
    from app.models.catalog import Product

    slugs = []
    names = []
    for pid in crop_product_ids:
        p = db.session.get(Product, pid)
        if p:
            names.append(p.name.lower())
            slugs.append(p.slug.split("-")[0])

    candidates = Community.query.filter(~Community.id.in_(joined_ids or [""])).limit(50).all()

    def score(c):
        text = f"{c.name} {c.description}".lower()
        s = 0
        for n in names + slugs:
            if n and n in text:
                s += 2
        if c.community_type == "regional" and c.name.lower().find((user.country_code or "").lower()) >= 0:
            s += 1
        return s + min(c.member_count / 5000.0, 1.5)

    ranked = sorted(candidates, key=score, reverse=True)[:limit]
    return [
        {
            "community_id": c.id,
            "name": c.name,
            "slug": c.slug,
            "members": c.member_count,
            "why": "Matches your registered crops" if any(n and n in c.name.lower() for n in names) else "Popular among farmers like you",
        }
        for c in ranked
    ]
