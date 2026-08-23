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
from app.models.base import BaseModel, utcnow

CALL_TYPES = ["VOICE", "VIDEO"]
CALL_STATES = ["RINGING", "ONGOING", "ENDED", "MISSED", "DECLINED", "FAILED"]
CALL_END_REASONS = ["normal", "declined", "missed", "failed", "busy"]
VOICE_ROOM_ROLES = ["HOST", "CO_HOST", "SPEAKER", "LISTENER"]


class Call(BaseModel):
    __tablename__ = "calls"
    call_type = db.Column(db.String(10), default="VOICE", nullable=False)
    initiator_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)
    state = db.Column(db.String(15), default="RINGING", nullable=False, index=True)
    started_at = db.Column(db.DateTime(timezone=True))
    ended_at = db.Column(db.DateTime(timezone=True))
    end_reason = db.Column(db.String(20))
    duration_seconds = db.Column(Integer, default=0)

    participants = relationship("CallParticipant", back_populates="call", lazy="selectin")


class CallParticipant(BaseModel):
    __tablename__ = "call_participants"
    __table_args__ = (UniqueConstraint("call_id", "user_id", name="uq_call_participant"),)

    call_id = db.Column(db.String(32), ForeignKey("calls.id"), nullable=False, index=True)
    user_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)
    joined_at = db.Column(db.DateTime(timezone=True))
    left_at = db.Column(db.DateTime(timezone=True))
    muted = db.Column(Boolean, default=False, nullable=False)

    call = relationship("Call", back_populates="participants")


class CallEvent(BaseModel):
    __tablename__ = "call_events"
    call_id = db.Column(db.String(32), ForeignKey("calls.id"), nullable=False, index=True)
    actor_id = db.Column(db.String(32), ForeignKey("users.id"))
    event_type = db.Column(db.String(40), nullable=False)
    detail_json = db.Column(Text, default="{}")


class VoiceRoom(BaseModel):
    __tablename__ = "voice_rooms"
    title = db.Column(db.String(255), nullable=False)
    topic = db.Column(db.String(500), default="")
    host_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)
    group_id = db.Column(db.String(32), ForeignKey("groups.id"), index=True)
    community_id = db.Column(db.String(32), ForeignKey("communities.id"), index=True)
    scheduled_at = db.Column(db.DateTime(timezone=True))
    started_at = db.Column(db.DateTime(timezone=True))
    ended_at = db.Column(db.DateTime(timezone=True))
    listener_count = db.Column(Integer, default=0, nullable=False)
    state = db.Column(db.String(20), default="SCHEDULED", nullable=False)


class VoiceRoomParticipant(BaseModel):
    __tablename__ = "voice_room_participants"
    __table_args__ = (UniqueConstraint("room_id", "user_id", name="uq_voice_room_participant"),)

    room_id = db.Column(db.String(32), ForeignKey("voice_rooms.id"), nullable=False, index=True)
    user_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)
    role = db.Column(db.String(15), default="LISTENER", nullable=False)
    joined_at = db.Column(db.DateTime(timezone=True), default=utcnow)
    left_at = db.Column(db.DateTime(timezone=True))


class VoiceRoomSpeakerRequest(BaseModel):
    __tablename__ = "voice_room_speaker_requests"
    __table_args__ = (UniqueConstraint("room_id", "user_id", name="uq_speaker_request"),)

    room_id = db.Column(db.String(32), ForeignKey("voice_rooms.id"), nullable=False, index=True)
    user_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)
    state = db.Column(db.String(20), default="PENDING", nullable=False)
