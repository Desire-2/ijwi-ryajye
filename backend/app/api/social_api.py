import marshmallow as ma
from flask import request
from flask_jwt_extended import jwt_required

from extensions import db
from app.api.helpers import parse_body, query_params
from app.errors import bad_request, not_found
from app.models.community import (
    Channel,
    ChannelFollower,
    ChannelPost,
    Community,
    CommunityAnnouncement,
    CommunityGroup,
    CommunityMember,
)
from app.services import channel_service, community_service
from app.services.security import get_current_user


def list_communities():
    user = None
    try:
        user = get_current_user(required=False)
    except Exception:
        pass
    ctype = query_params().get("type")
    q = Community.query
    if ctype:
        q = q.filter(Community.community_type == ctype)
    communities = q.order_by(Community.member_count.desc()).limit(100).all()
    joined = set()
    if user is not None:
        joined = {m.community_id for m in CommunityMember.query.filter_by(user_id=user.id).all()}
    return {
        "communities": [
            {"id": c.id, "name": c.name, "slug": c.slug, "description": c.description,
             "icon_emoji": c.icon_emoji, "community_type": c.community_type,
             "member_count": c.member_count, "verified_experts_count": c.verified_experts_count,
             "joined": c.id in joined}
            for c in communities
        ]
    }


@jwt_required()
def create_community():
    user = get_current_user()
    data = parse_body(type("S", (ma.Schema,), {
        "name": ma.fields.String(required=True),
        "description": ma.fields.String(missing=""),
        "icon_emoji": ma.fields.String(missing="🌍"),
        "community_type": ma.fields.String(missing="crop",
                                           validate=ma.validate.OneOf(["crop", "regional", "expert", "cooperative"])),
        "is_private": ma.fields.Boolean(missing=False),
    })())
    slug = data["name"].lower().replace(" ", "-")[:80]
    if Community.query.filter_by(slug=slug).first():
        from app.errors import conflict

        raise conflict("A community with this name exists")
    community = Community(
        name=data["name"], slug=slug, description=data["description"],
        icon_emoji=data["icon_emoji"], community_type=data["community_type"],
        creator_id=user.id, is_private=data["is_private"],
    )
    db.session.add(community)
    db.session.flush()
    db.session.add(CommunityMember(community_id=community.id, user_id=user.id, role="admin"))
    community.member_count = 1
    db.session.commit()
    return {"community": {"id": community.id, "name": community.name, "slug": community.slug}}, 201


@jwt_required()
def join_community(community_id):
    user = get_current_user()
    community = community_service.get_community_or_404(community_id)
    member = community_service.join_community(user, community)
    db.session.commit()
    return {"joined": True, "member_count": community.member_count}


@jwt_required()
def community_detail(community_id):
    user = get_current_user()
    community = community_service.get_community_or_404(community_id)
    from app.models.group import Group

    groups = CommunityGroup.query.filter_by(community_id=community.id).all()
    group_ids = [g.group_id for g in groups]
    group_rows = Group.query.filter(Group.id.in_(group_ids)).all() if group_ids else []
    announcements = CommunityAnnouncement.query.filter_by(community_id=community.id) \
        .order_by(CommunityAnnouncement.pinned.desc(), CommunityAnnouncement.created_at.desc()).limit(50).all()
    return {
        "community": {
            **{k: v for k, v in community.to_dict().items()},
            "groups": [{"id": gr.id, "name": gr.name, "space_type":
                        next((g.space_type for g in groups if g.group_id == gr.id), "discussion")}
                       for gr in group_rows],
            "announcements": [a.to_dict() for a in announcements],
        }
    }


@jwt_required()
def attach_group_to_community(community_id):
    user = get_current_user()
    community = community_service.get_community_or_404(community_id)
    data = parse_body(type("S", (ma.Schema,), {
        "group_id": ma.fields.String(required=True),
        "space_type": ma.fields.String(missing="discussion", validate=ma.validate.OneOf(
            ["announcements", "discussion", "marketplace", "expert", "regional", "leadership"])),
    })())
    link = community_service.attach_group(user, community, data["group_id"], data["space_type"])
    db.session.commit()
    return {"linked": True}


@jwt_required()
def community_announce(community_id):
    user = get_current_user()
    community = community_service.get_community_or_404(community_id)
    data = parse_body(type("S", (ma.Schema,), {
        "title": ma.fields.String(missing=""),
        "body_text": ma.fields.String(required=True),
        "pinned": ma.fields.Boolean(missing=False),
    })())
    ann = community_service.announce(user, community, data["title"], data["body_text"], pinned=data["pinned"])
    db.session.commit()
    return {"announcement": ann.to_dict()}, 201


@jwt_required()
def recommended_communities():
    user = get_current_user()
    recs = community_service.recommend_for_user(user)
    return {"recommendations": recs}


def list_channels():
    user = None
    try:
        user = get_current_user(required=False)
    except Exception:
        pass
    channels = Channel.query.order_by(Channel.subscriber_count.desc()).limit(100).all()
    following = set()
    if user is not None:
        following = {f.channel_id for f in ChannelFollower.query.filter_by(user_id=user.id).all()}
    return {
        "channels": [
            {"id": c.id, "name": c.name, "slug": c.slug, "description": c.description,
             "channel_type": c.channel_type, "subscriber_count": c.subscriber_count,
             "following": c.id in following}
            for c in channels
        ]
    }


@jwt_required()
def create_channel():
    user = get_current_user()
    data = parse_body(type("S", (ma.Schema,), {
        "name": ma.fields.String(required=True),
        "description": ma.fields.String(missing=""),
        "channel_type": ma.fields.String(missing="broadcast"),
        "requires_admin_post": ma.fields.Boolean(missing=True),
    })())
    slug = data["name"].lower().replace(" ", "-")[:80]
    from app.errors import conflict

    if Channel.query.filter_by(slug=slug).first():
        raise conflict("Channel already exists")
    channel = Channel(name=data["name"], slug=slug, description=data["description"],
                      channel_type=data["channel_type"], creator_id=user.id,
                      requires_admin_post=data["requires_admin_post"])
    db.session.add(channel)
    db.session.flush()
    db.session.add(ChannelFollower(channel_id=channel.id, user_id=user.id, notify_level="admin"))
    channel.subscriber_count = 1
    db.session.commit()
    return {"channel": {"id": channel.id, "name": channel.name}}, 201


@jwt_required()
def follow_channel(channel_id):
    user = get_current_user()
    channel = channel_service.get_channel_or_404(channel_id)
    f = channel_service.follow(user, channel)
    db.session.commit()
    return {"following": True, "notify_level": f.notify_level}


@jwt_required()
def unfollow_channel(channel_id):
    user = get_current_user()
    channel = channel_service.get_channel_or_404(channel_id)
    result = channel_service.unfollow(user, channel)
    db.session.commit()
    return result


@jwt_required()
def channel_posts(channel_id):
    channel = channel_service.get_channel_or_404(channel_id)
    posts = ChannelPost.query.filter_by(channel_id=channel.id) \
        .order_by(ChannelPost.created_at.desc()).limit(100).all()
    return {"posts": [
        {"id": p.id, "title": p.title, "body_text": p.body_text,
         "reaction_count": p.reaction_count, "created_at": p.created_at.isoformat(),
         "entity_ref_type": p.entity_ref_type, "entity_ref_id": p.entity_ref_id}
        for p in posts
    ]}


class PostSchema(ma.Schema):
    title = ma.fields.String(missing="")
    body_text = ma.fields.String(required=True)
    media_keys = ma.fields.List(ma.fields.String())
    entity_ref_type = ma.fields.String()
    entity_ref_id = ma.fields.String()


@jwt_required()
def create_channel_post(channel_id):
    user = get_current_user()
    channel = channel_service.get_channel_or_404(channel_id)
    data = parse_body(PostSchema)
    post = channel_service.post(user, channel, data["title"], data["body_text"],
                                media_keys=data.get("media_keys"),
                                entity_ref_type=data.get("entity_ref_type"),
                                entity_ref_id=data.get("entity_ref_id"))
    db.session.commit()
    return {"post": {"id": post.id}}, 201
