from extensions import db, realtime
from app.errors import bad_request, forbidden, not_found
from app.models.base import utcnow
from app.models.community import Channel, ChannelFollower, ChannelPost


def get_channel_or_404(channel_id):
    c = db.session.get(Channel, channel_id)
    if c is None:
        raise not_found("Channel not found")
    return c


def follow(user, channel, notify_level="all"):
    f = ChannelFollower.query.filter_by(channel_id=channel.id, user_id=user.id).first()
    if f is None:
        f = ChannelFollower(channel_id=channel.id, user_id=user.id, notify_level=notify_level)
        db.session.add(f)
        channel.subscriber_count += 1
        db.session.flush()
    else:
        f.notify_level = notify_level
    return f


def unfollow(user, channel):
    f = ChannelFollower.query.filter_by(channel_id=channel.id, user_id=user.id).first()
    if f:
        db.session.delete(f)
        channel.subscriber_count = max(0, channel.subscriber_count - 1)
        db.session.flush()
    return {"following": False}


def post(actor, channel, title, body, media_keys=None, entity_ref_type=None, entity_ref_id=None):
    follower = ChannelFollower.query.filter_by(channel_id=channel.id, user_id=actor.id).first()
    is_admin = "ADMIN" in actor.role_codes() or (follower and follower.notify_level == "admin")
    if not is_admin and channel.requires_admin_post:
        raise forbidden("Only channel administrators can post to this channel")

    post_ = ChannelPost(
        channel_id=channel.id,
        author_id=actor.id,
        title=title,
        body_text=body,
        media_keys=",".join(media_keys or []),
        entity_ref_type=entity_ref_type,
        entity_ref_id=entity_ref_id,
    )
    db.session.add(post_)
    db.session.flush()

    from app.services.notification_service import notify

    followers = ChannelFollower.query.filter(
        ChannelFollower.channel_id == channel.id,
        ChannelFollower.user_id != actor.id,
        ChannelFollower.notify_level != "none",
    ).all()
    for f in followers:
        notify(f.user_id, "MARKET_ALERT", f"{channel.name}: {title}" if title else channel.name,
               (body or "")[:140], subject_type="channel_post", subject_id=post_.id,
               batch_key=f"channel_{channel.id}", commit=False)

    realtime.emit("channel.post_created", {
        "channel_id": channel.id, "post_id": post_.id, "title": title})
    return post_
