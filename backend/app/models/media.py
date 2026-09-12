"""Canonical media asset model backing every upload in the app.

Feature surfaces (community posts, chat, status, listings, profile photos,
documents) attach to these rows via ``context_type``/``context_id``. The raw
storage_key remains available for backward compatibility with legacy payloads.
"""

from datetime import datetime

from extensions import db
from app.models.base import BaseModel, utcnow  # noqa: F401  (utcnow re-exported for callers)

MEDIA_TYPES = ("IMAGE", "VIDEO", "AUDIO", "DOCUMENT", "OTHER")
ASSET_STATUSES = ("PROCESSING", "READY", "FAILED")

# Context types that map to assets.
CONTEXT_TYPES = (
    "POST", "POST_COMMENT", "CHANNEL_POST", "STATUS", "LISTING",
    "MESSAGE", "CONVERSATION", "GROUP", "GROUP_DOC", "COMMUNITY",
    "PROFILE", "PRODUCT", "EVENT", "DELIVERY",
)


class MediaAsset(BaseModel):
    __tablename__ = "media_assets"
    __table_args__ = (
        db.Index("ix_media_assets_context", "context_type", "context_id"),
        db.Index("ix_media_assets_owner_created", "owner_id", "created_at"),
    )

    owner_id = db.Column(db.String(32), db.ForeignKey("users.id"), nullable=False, index=True)
    category = db.Column(db.String(20), default="image", nullable=False)
    media_type = db.Column(db.String(10), default="IMAGE", nullable=False)
    file_name = db.Column(db.String(255), default="")
    storage_key = db.Column(db.String(500), nullable=False, unique=True, index=True)
    thumbnail_key = db.Column(db.String(500))
    content_type = db.Column(db.String(120), default="")
    size_bytes = db.Column(db.BigInteger, default=0)
    width = db.Column(db.Integer)
    height = db.Column(db.Integer)
    duration_ms = db.Column(db.Integer, default=0)
    checksum = db.Column(db.String(64), default="")
    status = db.Column(db.String(16), default="READY", nullable=False)
    context_type = db.Column(db.String(24))
    context_id = db.Column(db.String(32))
    expires_at = db.Column(db.DateTime(timezone=True), index=True)
    deleted_at = db.Column(db.DateTime(timezone=True))

    @property
    def is_deleted(self):
        return self.deleted_at is not None

    @property
    def attached(self):
        return bool(self.context_type and self.context_id)

    def to_dict(self, exclude="deleted_at"):
        data = super().to_dict(exclude=exclude)
        if isinstance(data.get("expires_at"), datetime):
            data["expires_at"] = data["expires_at"].isoformat()
        return data