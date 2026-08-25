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
from extensions import db
from app.models.base import BaseModel, utcnow

NOTIFICATION_TYPES = [
    "NEW_OFFER", "OFFER_ACCEPTED", "OFFER_REJECTED", "PAYMENT", "ORDER_UPDATE",
    "DELIVERY_UPDATE", "MESSAGE", "MENTION", "GROUP_ACTIVITY", "COMMUNITY_ANNOUNCEMENT",
    "BUYER_OPPORTUNITY", "MARKET_ALERT", "WEATHER_ALERT", "EVENT_REMINDER",
    "POLL_INVITE", "EXPERT_RESPONSE", "EMERGENCY_ALERT", "VERIFICATION_UPDATE",
    "DISPUTE_UPDATE", "PAYOUT", "GROUP_ANNOUNCEMENT",
]


class Notification(BaseModel):
    __tablename__ = "notifications"
    __table_args__ = (Index("ix_notifications_user_read_created", "user_id", "read_at", "created_at"),)

    user_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)
    notification_type = db.Column(db.String(40), nullable=False)
    title = db.Column(db.String(255), nullable=False)
    body = db.Column(Text, default="")
    subject_type = db.Column(db.String(40))
    subject_id = db.Column(db.String(32))
    read_at = db.Column(db.DateTime(timezone=True))
    pushed_at = db.Column(db.DateTime(timezone=True))
    batch_key = db.Column(db.String(120), index=True)


class NotificationPreference(BaseModel):
    __tablename__ = "notification_preferences"
    __table_args__ = (
        UniqueConstraint("user_id", "notification_type", name="uq_notification_pref"),
    )
    user_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)
    notification_type = db.Column(db.String(40), nullable=False)
    enabled = db.Column(Boolean, default=True, nullable=False)
    push_enabled = db.Column(Boolean, default=True, nullable=False)


class NotificationBatch(BaseModel):
    __tablename__ = "notification_batches"
    __table_args__ = (UniqueConstraint("user_id", "batch_key", name="uq_notification_batch"),)

    user_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)
    batch_key = db.Column(db.String(120), nullable=False)
    count = db.Column(Integer, default=0, nullable=False)
    summary_title = db.Column(db.String(255), default="")
    flushed = db.Column(Boolean, default=False, nullable=False)
