from sqlalchemy import (
    Boolean, CheckConstraint, Column, DateTime, ForeignKey, Index, Integer, String, Text, UniqueConstraint,
)
from sqlalchemy.orm import relationship
from extensions import db
from app.models.base import BaseModel, utcnow

POST_TYPES = ["text", "question", "farm_update", "harvest", "product", "opportunity", "event", "poll", "announcement"]
POST_AUDIENCES = ["PUBLIC", "FOLLOWERS", "COMMUNITY", "GROUP", "SELECTED"]
REACTION_TYPES = ["❤️", "👍", "👏", "🙏", "🌱", "🌾", "🚜", "💡", "🔥"]


class Post(BaseModel):
    __tablename__ = "posts"
    author_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)
    post_type = db.Column(db.String(20), default="text", nullable=False)
    title = db.Column(db.String(255), default="")
    body_text = db.Column(Text, default="")
    media_keys = db.Column(Text, default="")
    audience = db.Column(db.String(20), default="PUBLIC", nullable=False)
    community_id = db.Column(db.String(32), ForeignKey("communities.id"), index=True)
    group_id = db.Column(db.String(32), ForeignKey("groups.id"), index=True)
    channel_id = db.Column(db.String(32), ForeignKey("channels.id"), index=True)
    entity_ref_type = db.Column(db.String(40))
    entity_ref_id = db.Column(db.String(32), index=True)
    listing_id = db.Column(db.String(32), ForeignKey("listings.id"), index=True)
    topic_tags = db.Column(db.String(500), default="")
    location_label = db.Column(db.String(255), default="")
    is_pinned = db.Column(Boolean, default=False, nullable=False)
    is_featured = db.Column(Boolean, default=False, nullable=False)
    is_best_answer = db.Column(Boolean, default=False, nullable=False)
    best_answer_comment_id = db.Column(db.String(32), index=True)
    reply_count = db.Column(Integer, default=0, nullable=False)
    reaction_count = db.Column(Integer, default=0, nullable=False)
    share_count = db.Column(Integer, default=0, nullable=False)
    view_count = db.Column(Integer, default=0, nullable=False)
    author = relationship("User", foreign_keys=[author_id])

    __table_args__ = (
        Index("ix_posts_type_created", "post_type", "created_at"),
        Index("ix_posts_community_created", "community_id", "created_at"),
        Index("ix_posts_group_created", "group_id", "created_at"),
        Index("ix_posts_channel_created", "channel_id", "created_at"),
    )


class Comment(BaseModel):
    __tablename__ = "comments"
    post_id = db.Column(db.String(32), ForeignKey("posts.id"), nullable=False, index=True)
    author_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)
    parent_comment_id = db.Column(db.String(32), ForeignKey("comments.id"), index=True)
    body_text = db.Column(Text, nullable=False)
    media_key = db.Column(db.String(500))
    is_best_answer = db.Column(Boolean, default=False, nullable=False)
    reaction_count = db.Column(Integer, default=0, nullable=False)
    reply_count = db.Column(Integer, default=0, nullable=False)
    author = relationship("User", foreign_keys=[author_id])

    __table_args__ = (
        Index("ix_comments_post_created", "post_id", "created_at"),
    )


class PostReaction(BaseModel):
    __tablename__ = "post_reactions"
    __table_args__ = (UniqueConstraint("post_id", "user_id", name="uq_post_reaction"),)
    post_id = db.Column(db.String(32), ForeignKey("posts.id"), nullable=False, index=True)
    user_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)
    emoji = db.Column(db.String(16), nullable=False)


class CommentReaction(BaseModel):
    __tablename__ = "comment_reactions"
    __table_args__ = (UniqueConstraint("comment_id", "user_id", name="uq_comment_reaction"),)
    comment_id = db.Column(db.String(32), ForeignKey("comments.id"), nullable=False, index=True)
    user_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)
    emoji = db.Column(db.String(16), nullable=False)


class SavedPost(BaseModel):
    __tablename__ = "saved_posts"
    __table_args__ = (UniqueConstraint("user_id", "post_id", name="uq_saved_post"),)
    user_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)
    post_id = db.Column(db.String(32), ForeignKey("posts.id"), nullable=False, index=True)


class PostShare(BaseModel):
    __tablename__ = "post_shares"
    post_id = db.Column(db.String(32), ForeignKey("posts.id"), nullable=False, index=True)
    user_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)
    target_type = db.Column(db.String(20), nullable=False)
    target_id = db.Column(db.String(32))


class ContentReport(BaseModel):
    __tablename__ = "content_reports"
    reporter_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)
    subject_type = db.Column(db.String(20), nullable=False)
    subject_id = db.Column(db.String(32), nullable=False, index=True)
    reason = db.Column(db.String(60), nullable=False)
    details = db.Column(Text, default="")
    status = db.Column(db.String(20), default="OPEN", nullable=False)


class UserFollow(BaseModel):
    __tablename__ = "user_follows"
    __table_args__ = (UniqueConstraint("follower_id", "followed_id", name="uq_user_follow"),)
    follower_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)
    followed_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)
