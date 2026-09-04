import json
from extensions import db, realtime
from app.errors import bad_request, conflict, forbidden, not_found
from app.models.base import utcnow
from app.models.posts import (
    Comment, CommentReaction, ContentReport, Post, PostReaction, PostShare,
    SavedPost, UserFollow, REACTION_TYPES,
)


def get_post_or_404(post_id):
    post = db.session.get(Post, post_id)
    if post is None:
        raise not_found("Post not found")
    return post


def create_post(author, payload):
    post_type = payload.get("post_type", "text")
    body_text = payload.get("body_text", "")
    if post_type != "poll" and not body_text.strip():
        raise bad_request("Post content is required")

    media = payload.get("media_keys", "")
    if isinstance(media, list):
        media = ",".join(media)

    post = Post(
        author_id=author.id,
        post_type=post_type,
        title=payload.get("title", ""),
        body_text=body_text,
        media_keys=media,
        audience=payload.get("audience", "PUBLIC"),
        community_id=payload.get("community_id"),
        group_id=payload.get("group_id"),
        channel_id=payload.get("channel_id"),
        entity_ref_type=payload.get("entity_ref_type"),
        entity_ref_id=payload.get("entity_ref_id"),
        listing_id=payload.get("listing_id"),
        topic_tags=payload.get("topic_tags", ""),
        location_label=payload.get("location_label", ""),
    )
    db.session.add(post)
    db.session.flush()

    realtime.emit_to_user(author.id, "post.created", {"post_id": post.id})
    return post


def list_posts(user=None, community_id=None, group_id=None, channel_id=None,
               post_type=None, author_id=None, topic=None,
               feed_for=None, page=1, per_page=20):
    q = Post.query
    if community_id:
        q = q.filter(Post.community_id == community_id)
    if group_id:
        q = q.filter(Post.group_id == group_id)
    if channel_id:
        q = q.filter(Post.channel_id == channel_id)
    if post_type:
        q = q.filter(Post.post_type == post_type)
    if author_id:
        q = q.filter(Post.author_id == author_id)
    if topic:
        q = q.filter(Post.topic_tags.ilike(f"%{topic}%"))

    if feed_for and user:
        from app.models.social import Follow
        from app.models.community import CommunityMember
        followed_ids = [f.followed_id for f in Follow.query.filter_by(follower_id=user.id).all()]
        joined_community_ids = [m.community_id for m in CommunityMember.query.filter_by(user_id=user.id).all()]
        from sqlalchemy import or_
        q = q.filter(or_(
            Post.author_id.in_(followed_ids),
            Post.community_id.in_(joined_community_ids),
            Post.audience == "PUBLIC",
        ))

    q = q.order_by(Post.is_pinned.desc(), Post.created_at.desc())
    pagination = q.paginate(page=page, per_page=per_page, error_out=False)
    return pagination


def get_post(post_id, viewer=None):
    post = get_post_or_404(post_id)
    post.view_count = (post.view_count or 0) + 1
    db.session.flush()
    return post


def edit_post(actor, post_id, payload):
    post = get_post_or_404(post_id)
    if post.author_id != actor.id and "ADMIN" not in actor.role_codes():
        raise forbidden("You can only edit your own posts")
    if payload.get("body_text") is not None:
        post.body_text = payload["body_text"]
    if payload.get("title") is not None:
        post.title = payload["title"]
    if payload.get("topic_tags") is not None:
        post.topic_tags = payload["topic_tags"]
    if payload.get("media_keys") is not None:
        media = payload["media_keys"]
        if isinstance(media, list):
            media = ",".join(media)
        post.media_keys = media
    db.session.flush()
    return post


def delete_post(actor, post_id):
    post = get_post_or_404(post_id)
    if post.author_id != actor.id and "ADMIN" not in actor.role_codes():
        raise forbidden("You can only delete your own posts")
    db.session.delete(post)
    db.session.flush()
    return {"deleted": True}


def pin_post(actor, post_id):
    post = get_post_or_404(post_id)
    post.is_pinned = not post.is_pinned
    db.session.flush()
    return {"pinned": post.is_pinned}


def mark_best_answer(actor, post_id, comment_id):
    post = get_post_or_404(post_id)
    if post.author_id != actor.id and "ADMIN" not in actor.role_codes():
        raise forbidden("Only the post author or an admin can mark best answer")
    comment = db.session.get(Comment, comment_id)
    if comment is None or comment.post_id != post.id:
        raise not_found("Comment not found on this post")

    old_best = Comment.query.filter_by(post_id=post.id, is_best_answer=True).first()
    if old_best:
        old_best.is_best_answer = False

    comment.is_best_answer = True
    post.is_best_answer = True
    post.best_answer_comment_id = comment_id
    db.session.flush()
    return {"best_answer_id": comment_id}


def add_comment(author, post_id, payload):
    post = get_post_or_404(post_id)
    body_text = payload.get("body_text", "").strip()
    if not body_text:
        raise bad_request("Comment content is required")

    comment = Comment(
        post_id=post_id,
        author_id=author.id,
        parent_comment_id=payload.get("parent_comment_id"),
        body_text=body_text,
        media_key=payload.get("media_key", ""),
    )
    db.session.add(comment)
    post.reply_count = (post.reply_count or 0) + 1

    if post.author_id != author.id:
        from app.services.notification_service import notify
        notify(post.author_id, "MENTION", f"New comment on your post",
               body_text[:140], subject_type="comment", subject_id=comment.id,
               batch_key=f"post_{post.id}_comments")

    db.session.flush()
    realtime.emit_to_user(post.author_id, "comment.created", {
        "post_id": post_id, "comment_id": comment.id, "author_id": author.id,
    })
    return comment


def list_comments(post_id, page=1, per_page=20, sort="newest", user=None):
    post = get_post_or_404(post_id)
    q = Comment.query.filter_by(post_id=post_id, parent_comment_id=None)
    if sort == "top":
        q = q.order_by(Comment.reaction_count.desc(), Comment.created_at.desc())
    elif sort == "oldest":
        q = q.order_by(Comment.created_at.asc())
    else:
        q = q.order_by(Comment.created_at.desc())
    return q.paginate(page=page, per_page=per_page, error_out=False)


def list_comment_replies(comment_id, page=1, per_page=20):
    comment = db.session.get(Comment, comment_id)
    if comment is None:
        raise not_found("Comment not found")
    q = Comment.query.filter_by(parent_comment_id=comment_id).order_by(Comment.created_at.asc())
    return q.paginate(page=page, per_page=per_page, error_out=False)


def react_to_post(user, post_id, emoji):
    if emoji not in REACTION_TYPES:
        raise bad_request(f"Invalid reaction. Allowed: {', '.join(REACTION_TYPES)}")
    post = get_post_or_404(post_id)
    existing = PostReaction.query.filter_by(post_id=post_id, user_id=user.id).first()
    if existing:
        if existing.emoji == emoji:
            db.session.delete(existing)
            post.reaction_count = max(0, (post.reaction_count or 0) - 1)
            db.session.flush()
            return {"removed": True}
        else:
            existing.emoji = emoji
            db.session.flush()
            return {"emoji": emoji}
    else:
        db.session.add(PostReaction(post_id=post_id, user_id=user.id, emoji=emoji))
        post.reaction_count = (post.reaction_count or 0) + 1
        db.session.flush()
        if post.author_id != user.id:
            from app.services.notification_service import notify
            notify(post.author_id, "MENTION", f"Someone reacted {emoji} to your post",
                   subject_type="post", subject_id=post.id,
                   batch_key=f"post_{post.id}_reactions")
        return {"emoji": emoji}


def react_to_comment(user, comment_id, emoji):
    if emoji not in REACTION_TYPES:
        raise bad_request(f"Invalid reaction. Allowed: {', '.join(REACTION_TYPES)}")
    comment = db.session.get(Comment, comment_id)
    if comment is None:
        raise not_found("Comment not found")
    existing = CommentReaction.query.filter_by(comment_id=comment_id, user_id=user.id).first()
    if existing:
        if existing.emoji == emoji:
            db.session.delete(existing)
            comment.reaction_count = max(0, (comment.reaction_count or 0) - 1)
            db.session.flush()
            return {"removed": True}
        else:
            existing.emoji = emoji
            db.session.flush()
            return {"emoji": emoji}
    else:
        db.session.add(CommentReaction(comment_id=comment_id, user_id=user.id, emoji=emoji))
        comment.reaction_count = (comment.reaction_count or 0) + 1
        db.session.flush()
        return {"emoji": emoji}


def save_post(user, post_id):
    post = get_post_or_404(post_id)
    existing = SavedPost.query.filter_by(user_id=user.id, post_id=post_id).first()
    if existing:
        db.session.delete(existing)
        db.session.flush()
        return {"saved": False}
    db.session.add(SavedPost(user_id=user.id, post_id=post_id))
    db.session.flush()
    return {"saved": True}


def list_saved_posts(user, page=1, per_page=20):
    q = (db.session.query(Post)
         .join(SavedPost, SavedPost.post_id == Post.id)
         .filter(SavedPost.user_id == user.id)
         .order_by(SavedPost.created_at.desc()))
    return q.paginate(page=page, per_page=per_page, error_out=False)


def follow_user(follower, followed_id):
    if follower.id == followed_id:
        raise bad_request("You cannot follow yourself")
    from app.models.identity import User
    target = db.session.get(User, followed_id)
    if target is None:
        raise not_found("User not found")
    existing = UserFollow.query.filter_by(follower_id=follower.id, followed_id=followed_id).first()
    if existing:
        db.session.delete(existing)
        db.session.flush()
        return {"following": False}
    db.session.add(UserFollow(follower_id=follower.id, followed_id=followed_id))
    db.session.flush()
    from app.services.notification_service import notify
    notify(followed_id, "MENTION", f"{follower.full_name} started following you",
           subject_type="user", subject_id=follower.id)
    return {"following": True}


def is_following(follower_id, followed_id):
    return UserFollow.query.filter_by(follower_id=follower_id, followed_id=followed_id).first() is not None


def get_follow_counts(user_id):
    followers = UserFollow.query.filter_by(followed_id=user_id).count()
    following = UserFollow.query.filter_by(follower_id=user_id).count()
    return {"followers": followers, "following": following}


def report_content(reporter, subject_type, subject_id, reason, details=""):
    existing = ContentReport.query.filter_by(
        reporter_id=reporter.id, subject_type=subject_type, subject_id=subject_id, status="OPEN"
    ).first()
    if existing:
        raise conflict("You have already reported this content")
    report = ContentReport(
        reporter_id=reporter.id, subject_type=subject_type, subject_id=subject_id,
        reason=reason, details=details,
    )
    db.session.add(report)
    db.session.flush()
    return report


def get_post_reactions(post_id):
    reactions = PostReaction.query.filter_by(post_id=post_id).all()
    counts = {}
    for r in reactions:
        counts[r.emoji] = counts.get(r.emoji, 0) + 1
    return [{"emoji": e, "count": c} for e, c in sorted(counts.items(), key=lambda x: -x[1])]


def get_user_reaction_on_post(user_id, post_id):
    r = PostReaction.query.filter_by(post_id=post_id, user_id=user_id).first()
    return r.emoji if r else None


def get_user_reaction_on_comment(user_id, comment_id):
    r = CommentReaction.query.filter_by(comment_id=comment_id, user_id=user_id).first()
    return r.emoji if r else None


def serialize_post(post, viewer=None):
    from app.api.serializers import farmer_card
    author_data = farmer_card(post.author) if post.author else {"id": post.author_id}
    data = {
        "id": post.id,
        "author": author_data,
        "post_type": post.post_type,
        "title": post.title,
        "body_text": post.body_text,
        "media_keys": post.media_keys.split(",") if post.media_keys else [],
        "audience": post.audience,
        "community_id": post.community_id,
        "group_id": post.group_id,
        "channel_id": post.channel_id,
        "entity_ref_type": post.entity_ref_type,
        "entity_ref_id": post.entity_ref_id,
        "listing_id": post.listing_id,
        "topic_tags": [t.strip() for t in post.topic_tags.split(",") if t.strip()] if post.topic_tags else [],
        "location_label": post.location_label,
        "is_pinned": post.is_pinned,
        "is_featured": post.is_featured,
        "is_best_answer": post.is_best_answer,
        "best_answer_comment_id": post.best_answer_comment_id,
        "reply_count": post.reply_count or 0,
        "reaction_count": post.reaction_count or 0,
        "share_count": post.share_count or 0,
        "view_count": post.view_count or 0,
        "created_at": post.created_at.isoformat() if post.created_at else None,
    }
    if viewer:
        data["my_reaction"] = get_user_reaction_on_post(viewer.id, post.id)
        data["saved"] = SavedPost.query.filter_by(user_id=viewer.id, post_id=post.id).first() is not None
        from app.models.social import Follow
        data["author_followed"] = is_following(viewer.id, post.author_id)
    return data


def serialize_comment(comment, viewer=None):
    from app.api.serializers import farmer_card
    author_data = farmer_card(comment.author) if comment.author else {"id": comment.author_id}
    data = {
        "id": comment.id,
        "post_id": comment.post_id,
        "author": author_data,
        "parent_comment_id": comment.parent_comment_id,
        "body_text": comment.body_text,
        "media_key": comment.media_key,
        "is_best_answer": comment.is_best_answer,
        "reaction_count": comment.reaction_count or 0,
        "reply_count": comment.reply_count or 0,
        "created_at": comment.created_at.isoformat() if comment.created_at else None,
    }
    if viewer:
        data["my_reaction"] = get_user_reaction_on_comment(viewer.id, comment.id)
    return data
