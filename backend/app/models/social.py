from datetime import datetime

from sqlalchemy import (
    BigInteger,
    Boolean,
    CheckConstraint,
    Column,
    Date,
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
from app.models.base import BaseModel, utcnow


class Poll(BaseModel):
    __tablename__ = "polls"
    group_id = db.Column(db.String(32), ForeignKey("groups.id"), index=True)
    community_id = db.Column(db.String(32), ForeignKey("communities.id"), index=True)
    conversation_id = db.Column(db.String(32), ForeignKey("conversations.id"), index=True)
    creator_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)
    question = db.Column(db.String(500), nullable=False)
    multiple_choice = db.Column(Boolean, default=False, nullable=False)
    anonymous = db.Column(Boolean, default=False, nullable=False)
    closes_at = db.Column(db.DateTime(timezone=True))
    closed = db.Column(Boolean, default=False, nullable=False)

    options = relationship("PollOption", back_populates="poll", lazy="selectin")


class PollOption(BaseModel):
    __tablename__ = "poll_options"
    poll_id = db.Column(db.String(32), ForeignKey("polls.id"), nullable=False, index=True)
    label = db.Column(db.String(255), nullable=False)
    position = db.Column(Integer, default=0)
    vote_count = db.Column(Integer, default=0, nullable=False)

    poll = relationship("Poll", back_populates="options")


class PollVote(BaseModel):
    __tablename__ = "poll_votes"
    __table_args__ = (
        UniqueConstraint("poll_id", "user_id", "poll_option_id", name="uq_poll_vote"),
    )

    poll_id = db.Column(db.String(32), ForeignKey("polls.id"), nullable=False, index=True)
    poll_option_id = db.Column(db.String(32), ForeignKey("poll_options.id"), nullable=False)
    user_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)
    voted_at = db.Column(db.DateTime(timezone=True), default=utcnow)


class Event(BaseModel):
    __tablename__ = "events"
    group_id = db.Column(db.String(32), ForeignKey("groups.id"), index=True)
    community_id = db.Column(db.String(32), ForeignKey("communities.id"), index=True)
    title = db.Column(db.String(255), nullable=False)
    description = db.Column(Text, default="")
    starts_at = db.Column(db.DateTime(timezone=True), nullable=False)
    ends_at = db.Column(db.DateTime(timezone=True))
    location_label = db.Column(db.String(255), default="")
    online_link = db.Column(db.String(500))
    organizer_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False)
    cancelled = db.Column(Boolean, default=False, nullable=False)

    __table_args__ = (Index("ix_events_group_starts", "group_id", "starts_at"),)


class EventParticipant(BaseModel):
    __tablename__ = "event_participants"
    __table_args__ = (UniqueConstraint("event_id", "user_id", name="uq_event_participant"),)

    event_id = db.Column(db.String(32), ForeignKey("events.id"), nullable=False, index=True)
    user_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)
    rsvp = db.Column(db.String(10), default="going", nullable=False)


class EventReminder(BaseModel):
    __tablename__ = "event_reminders"
    event_id = db.Column(db.String(32), ForeignKey("events.id"), nullable=False, index=True)
    user_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)
    remind_at = db.Column(db.DateTime(timezone=True), nullable=False)
    sent_at = db.Column(db.DateTime(timezone=True))


class Follow(BaseModel):
    # Legacy orphaned table. All new code writes to UserFollow in app.models.posts.
    __tablename__ = "follows"
    __table_args__ = (UniqueConstraint("follower_id", "followed_id", name="uq_follow_pair"),)

    follower_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)
    followed_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)


CONNECTION_STATUSES = ["PENDING", "ACCEPTED", "DECLINED"]


class Connection(BaseModel):
    """Mutual connection layer (the social graph for recommendations and chat).

    The pair is always stored normalized (lower id first) so a unique constraint
    guarantees at most one relationship per user pair.
    """

    __tablename__ = "connections"
    __table_args__ = (
        UniqueConstraint("user_a_id", "user_b_id", name="uq_connection_pair"),
        Index("ix_connections_user_a", "user_a_id", "status"),
        Index("ix_connections_user_b", "user_b_id", "status"),
    )

    user_a_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)
    user_b_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)
    status = db.Column(db.String(10), default="PENDING", nullable=False)
    requested_by = db.Column(db.String(32), ForeignKey("users.id"), nullable=False)
    responded_at = db.Column(db.DateTime(timezone=True))

    def other_id(self, user_id):
        return self.user_b_id if user_id == self.user_a_id else self.user_a_id
