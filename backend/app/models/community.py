from sqlalchemy import (
    Boolean,
    Column,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.orm import relationship

from extensions import db
from app.models.base import BaseMixin, BaseModel, SoftDeleteMixin, SoftDeleteModel, utcnow

STATUS_TYPES = ["text", "photo", "video", "voice", "harvest", "farm_update", "product", "opportunity", "event"]
AUDIENCE_SCOPES = ["EVERYONE", "FOLLOWERS", "COMMUNITIES", "SELECTED_USERS", "PRIVATE"]


class Community(BaseModel):
    __tablename__ = "communities"
    name = db.Column(db.String(255), nullable=False)
    slug = db.Column(db.String(255), unique=True, nullable=False, index=True)
    description = db.Column(Text, default="")
    icon_emoji = db.Column(db.String(16), default="🌍")
    community_type = db.Column(db.String(30), default="crop")
    creator_id = db.Column(db.String(32), ForeignKey("users.id"), index=True)
    is_private = db.Column(Boolean, default=False, nullable=False)
    member_count = db.Column(Integer, default=0, nullable=False)
    verified_experts_count = db.Column(Integer, default=0, nullable=False)


class CommunityMember(BaseModel):
    __tablename__ = "community_members"
    __table_args__ = (UniqueConstraint("community_id", "user_id", name="uq_community_member"),)

    community_id = db.Column(db.String(32), ForeignKey("communities.id"), nullable=False, index=True)
    user_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)
    role = db.Column(db.String(30), default="member", nullable=False)
    joined_at = db.Column(db.DateTime(timezone=True), default=utcnow)

    community = relationship("Community")


class CommunityGroup(BaseModel):
    __tablename__ = "community_groups"
    __table_args__ = (UniqueConstraint("community_id", "group_id", name="uq_community_group"),)

    community_id = db.Column(db.String(32), ForeignKey("communities.id"), nullable=False, index=True)
    group_id = db.Column(db.String(32), ForeignKey("groups.id"), nullable=False)
    space_type = db.Column(
        db.String(30), default="discussion"
    )
    position = db.Column(Integer, default=0)


class CommunityAnnouncement(BaseModel):
    __tablename__ = "community_announcements"
    community_id = db.Column(db.String(32), ForeignKey("communities.id"), nullable=False, index=True)
    author_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False)
    title = db.Column(db.String(255), default="")
    body_text = db.Column(Text, nullable=False)
    pinned = db.Column(Boolean, default=False, nullable=False)


class Channel(BaseModel):
    __tablename__ = "channels"
    name = db.Column(db.String(255), nullable=False)
    slug = db.Column(db.String(255), unique=True, nullable=False, index=True)
    description = db.Column(Text, default="")
    channel_type = db.Column(db.String(40), default="broadcast")
    creator_id = db.Column(db.String(32), ForeignKey("users.id"), index=True)
    subscriber_count = db.Column(Integer, default=0, nullable=False)
    requires_admin_post = db.Column(Boolean, default=True, nullable=False)
    subscription_configurable = db.Column(Boolean, default=True, nullable=False)


class ChannelFollower(BaseModel):
    __tablename__ = "channel_followers"
    __table_args__ = (UniqueConstraint("channel_id", "user_id", name="uq_channel_follower"),)

    channel_id = db.Column(db.String(32), ForeignKey("channels.id"), nullable=False, index=True)
    user_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)
    notify_level = db.Column(db.String(20), default="all")
    followed_at = db.Column(db.DateTime(timezone=True), default=utcnow)


class ChannelPost(BaseModel):
    __tablename__ = "channel_posts"
    channel_id = db.Column(db.String(32), ForeignKey("channels.id"), nullable=False, index=True)
    author_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False)
    title = db.Column(db.String(255), default="")
    body_text = db.Column(Text, default="")
    media_keys = db.Column(db.Text, default="")
    entity_ref_type = db.Column(db.String(40))
    entity_ref_id = db.Column(db.String(32))
    reaction_count = db.Column(Integer, default=0, nullable=False)
    forwarded_count = db.Column(Integer, default=0, nullable=False)


class Status(SoftDeleteModel):
    __tablename__ = "statuses"

    author_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)
    status_type = db.Column(db.String(20), default="text", nullable=False)
    body_text = db.Column(Text, default="")
    media_key = db.Column(db.String(500))
    template_kind = db.Column(db.String(30))
    listing_id = db.Column(db.String(32), ForeignKey("listings.id"), index=True)
    product_id = db.Column(db.String(32), ForeignKey("products.id"), index=True)
    quantity_label = db.Column(db.String(80), default="")
    expires_at = db.Column(db.DateTime(timezone=True), nullable=False, index=True)

    viewers = relationship("StatusView", back_populates="status", lazy="selectin")

    __table_args__ = (
        Index("ix_statuses_author_expires", "author_id", "expires_at"),
    )


class StatusAudience(BaseModel):
    __tablename__ = "status_audiences"
    status_id = db.Column(db.String(32), ForeignKey("statuses.id"), nullable=False, index=True)
    scope = db.Column(db.String(20), default="EVERYONE", nullable=False)
    target_user_id = db.Column(db.String(32), ForeignKey("users.id"))
    target_community_id = db.Column(db.String(32), ForeignKey("communities.id"))


class StatusView(BaseModel):
    __tablename__ = "status_views"
    __table_args__ = (UniqueConstraint("status_id", "viewer_id", name="uq_status_view"),)

    status_id = db.Column(db.String(32), ForeignKey("statuses.id"), nullable=False, index=True)
    viewer_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)
    viewed_at = db.Column(db.DateTime(timezone=True), default=utcnow)

    status = relationship("Status", back_populates="viewers")


class StatusReaction(BaseModel):
    __tablename__ = "status_reactions"
    __table_args__ = (UniqueConstraint("status_id", "user_id", name="uq_status_reaction"),)

    status_id = db.Column(db.String(32), ForeignKey("statuses.id"), nullable=False, index=True)
    user_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)
    emoji = db.Column(db.String(16), nullable=False)
