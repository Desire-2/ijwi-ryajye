from sqlalchemy import (
    BigInteger,
    Boolean,
    CheckConstraint,
    Column,
    DateTime,
    Float,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.orm import relationship

from extensions import db
from app.models.base import BaseModel, SoftDeleteModel, utcnow

CONVERSATION_TYPES = ["DIRECT", "GROUP", "MARKETPLACE", "SUPPORT"]
MESSAGE_TYPES = [
    "text", "voice", "image", "video", "document", "location", "contact",
    "product_card", "listing_card", "order_card", "offer_card", "delivery_card",
    "farmer_card", "buyer_request_card", "poll_card", "event_card", "system",
]
REACTION_EMOJIS = ["❤️", "👍", "😂", "😮", "🙏", "👏", "🌱", "🌾", "🚜", "💰"]
DISAPPEARING_OPTIONS = {"off": None, "24h": 86400, "7d": 604800, "30d": 2592000}


class Conversation(BaseModel):
    __tablename__ = "conversations"

    conversation_type = db.Column(db.String(20), default="DIRECT", nullable=False, index=True)
    title = db.Column(db.String(255), default="")
    created_by_id = db.Column(db.String(32), ForeignKey("users.id"), index=True)
    group_id = db.Column(db.String(32), ForeignKey("groups.id"), index=True)
    community_id = db.Column(db.String(32), ForeignKey("communities.id"), index=True)
    listing_id = db.Column(db.String(32), ForeignKey("listings.id"), index=True)
    order_id = db.Column(db.String(32), ForeignKey("orders.id"), index=True)
    disappearing_seconds = db.Column(BigInteger, nullable=True)

    last_message_at = db.Column(db.DateTime(timezone=True), index=True)
    server_sequence = db.Column(BigInteger, nullable=False, default=0)

    members = relationship(
        "ConversationMember", back_populates="conversation", lazy="selectin"
    )

    direct_key = db.Column(db.String(80), unique=True, nullable=True, index=True)

    __table_args__ = (
        Index("ix_conversations_type_updated", "conversation_type", "last_message_at"),
    )


class ConversationMember(BaseModel):
    __tablename__ = "conversation_members"
    __table_args__ = (
        UniqueConstraint("conversation_id", "user_id", name="uq_conv_member"),
        Index("ix_convmem_user_unread", "user_id"),
    )

    conversation_id = db.Column(
        db.String(32), ForeignKey("conversations.id"), nullable=False, index=True
    )
    user_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)
    role = db.Column(db.String(20), default="member", nullable=False)
    joined_at = db.Column(db.DateTime(timezone=True), default=utcnow)
    left_at = db.Column(db.DateTime(timezone=True))
    muted = db.Column(Boolean, default=False, nullable=False)
    last_read_sequence = db.Column(BigInteger, default=0, nullable=False)
    archived = db.Column(Boolean, default=False, nullable=False)

    conversation = relationship("Conversation", back_populates="members")


class Message(BaseModel):
    __tablename__ = "messages"
    __table_args__ = (
        UniqueConstraint("conversation_id", "client_message_id", name="uq_message_client_id"),
        Index("ix_messages_conversation_seq", "conversation_id", "server_sequence"),
        Index("ix_messages_conversation_created", "conversation_id", "created_at"),
    )

    conversation_id = db.Column(
        db.String(32), ForeignKey("conversations.id"), nullable=False, index=True
    )
    sender_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)
    client_message_id = db.Column(db.String(80), nullable=False)
    server_sequence = db.Column(BigInteger, nullable=False)
    message_type = db.Column(db.String(20), default="text", nullable=False)
    body_text = db.Column(Text, default="")
    reply_to_message_id = db.Column(db.String(32), ForeignKey("messages.id"), index=True)
    forward_count = db.Column(Integer, default=0)

    entity_ref_type = db.Column(db.String(40))
    entity_ref_id = db.Column(db.String(32), index=True)
    entity_snapshot_json = db.Column(Text, default="")

    translated_message = db.Column(Text)
    source_language = db.Column(db.String(8))
    target_language = db.Column(db.String(8))
    transcription_text = db.Column(db.Text)
    transcription_language = db.Column(db.String(8))
    transcription_confidence = db.Column(Float)

    voice_duration_ms = db.Column(Integer, default=0)
    waveform_json = db.Column(Text)

    disappearing_seconds = db.Column(BigInteger, nullable=True)
    expires_at = db.Column(db.DateTime(timezone=True), index=True)
    edited = db.Column(Boolean, default=False, nullable=False)
    deleted_for_everyone = db.Column(Boolean, default=False, nullable=False)
    system_event_json = db.Column(Text)

    attachments = relationship(
        "MessageAttachment", back_populates="message", lazy="selectin"
    )


class MessageAttachment(BaseModel):
    __tablename__ = "message_attachments"
    message_id = db.Column(db.String(32), ForeignKey("messages.id"), nullable=False, index=True)
    attachment_type = db.Column(db.String(20), nullable=False)
    storage_key = db.Column(db.String(500), nullable=False)
    file_name = db.Column(db.String(255), default="")
    mime_type = db.Column(db.String(120), default="")
    size_bytes = db.Column(BigInteger, default=0)
    duration_ms = db.Column(Integer, default=0)
    width = db.Column(Integer)
    height = db.Column(Integer)
    thumbnail_key = db.Column(db.String(500))

    message = relationship("Message", back_populates="attachments")


class MessageReaction(BaseModel):
    __tablename__ = "message_reactions"
    __table_args__ = (
        UniqueConstraint("message_id", "user_id", name="uq_reaction_one_per_user"),
    )

    message_id = db.Column(db.String(32), ForeignKey("messages.id"), nullable=False, index=True)
    user_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)
    emoji = db.Column(db.String(16), nullable=False)


class MessageReadReceipt(BaseModel):
    __tablename__ = "message_read_receipts"
    __table_args__ = (UniqueConstraint("message_id", "user_id", name="uq_read_receipt"),)

    message_id = db.Column(db.String(32), ForeignKey("messages.id"), nullable=False, index=True)
    user_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)
    read_at = db.Column(db.DateTime(timezone=True), default=utcnow)


class MessageDeliveryReceipt(BaseModel):
    __tablename__ = "message_delivery_receipts"
    __table_args__ = (UniqueConstraint("message_id", "user_id", name="uq_delivery_receipt"),)

    message_id = db.Column(db.String(32), ForeignKey("messages.id"), nullable=False, index=True)
    user_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)
    delivered_at = db.Column(db.DateTime(timezone=True), default=utcnow)


class MessageEdit(BaseModel):
    __tablename__ = "message_edits"
    message_id = db.Column(db.String(32), ForeignKey("messages.id"), nullable=False, index=True)
    editor_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False)
    previous_body = db.Column(Text, default="")
    new_body = db.Column(Text, default="")


class MessageReport(BaseModel):
    __tablename__ = "message_reports"
    message_id = db.Column(db.String(32), ForeignKey("messages.id"), nullable=False, index=True)
    reporter_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)
    reason = db.Column(db.String(60), nullable=False)
    details = db.Column(Text, default="")
    status = db.Column(db.String(20), default="OPEN")


class MessageForward(BaseModel):
    __tablename__ = "message_forwards"
    original_message_id = db.Column(db.String(32), ForeignKey("messages.id"), index=True)
    forwarded_by = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)
    target_conversation_id = db.Column(
        db.String(32), ForeignKey("conversations.id"), nullable=False, index=True
    )
    new_message_id = db.Column(db.String(32), ForeignKey("messages.id"), index=True)


class SavedMessage(BaseModel):
    __tablename__ = "saved_messages"
    __table_args__ = (
        UniqueConstraint("user_id", "message_id", name="uq_saved_message"),
    )
    user_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)
    message_id = db.Column(db.String(32), ForeignKey("messages.id"), nullable=False)
    note = db.Column(db.String(255), default="")


class PinnedMessage(BaseModel):
    __tablename__ = "pinned_messages"
    __table_args__ = (UniqueConstraint("conversation_id", "message_id", name="uq_pinned"),)

    conversation_id = db.Column(db.String(32), ForeignKey("conversations.id"), nullable=False, index=True)
    message_id = db.Column(db.String(32), ForeignKey("messages.id"), nullable=False)
    pinned_by = db.Column(db.String(32), ForeignKey("users.id"))


class MutedConversation(BaseModel):
    __tablename__ = "muted_conversations"
    __table_args__ = (UniqueConstraint("user_id", "conversation_id", name="uq_muted_conv"),)

    user_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)
    conversation_id = db.Column(db.String(32), ForeignKey("conversations.id"), nullable=False)
    until = db.Column(db.DateTime(timezone=True))
