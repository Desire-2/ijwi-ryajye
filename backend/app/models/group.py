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
from app.models.base import BaseModel, SoftDeleteModel, utcnow

GROUP_ROLES = [
    "ADMIN", "MODERATOR", "FARMER", "BUYER", "EXPERT",
    "COOPERATIVE_LEADER", "SUPPLIER", "LOGISTICS", "GUEST",
]
GROUP_PERMISSIONS = [
    "can_message", "can_add_members", "can_edit_group", "can_create_polls",
    "can_create_events", "can_start_calls", "can_send_announcements", "can_invite",
]

DEFAULT_ROLE_PERMISSIONS = {
    "ADMIN": {p: True for p in GROUP_PERMISSIONS},
    "MODERATOR": {
        "can_message": True, "can_add_members": True, "can_edit_group": False,
        "can_create_polls": True, "can_create_events": True, "can_start_calls": True,
        "can_send_announcements": True, "can_invite": True,
    },
    "COOPERATIVE_LEADER": {
        "can_message": True, "can_add_members": True, "can_edit_group": False,
        "can_create_polls": True, "can_create_events": True, "can_start_calls": True,
        "can_send_announcements": True, "can_invite": True,
    },
    "EXPERT": {
        "can_message": True, "can_add_members": False, "can_edit_group": False,
        "can_create_polls": True, "can_create_events": True, "can_start_calls": False,
        "can_send_announcements": False, "can_invite": True,
    },
    "FARMER": {
        "can_message": True, "can_add_members": False, "can_edit_group": False,
        "can_create_polls": False, "can_create_events": False, "can_start_calls": False,
        "can_send_announcements": False, "can_invite": True,
    },
    "BUYER": {
        "can_message": True, "can_add_members": False, "can_edit_group": False,
        "can_create_polls": False, "can_create_events": False, "can_start_calls": False,
        "can_send_announcements": False, "can_invite": False,
    },
    "SUPPLIER": {
        "can_message": True, "can_add_members": False, "can_edit_group": False,
        "can_create_polls": False, "can_create_events": False, "can_start_calls": False,
        "can_send_announcements": False, "can_invite": False,
    },
    "LOGISTICS": {
        "can_message": True, "can_add_members": False, "can_edit_group": False,
        "can_create_polls": False, "can_create_events": False, "can_start_calls": False,
        "can_send_announcements": False, "can_invite": False,
    },
    "GUEST": {
        "can_message": False, "can_add_members": False, "can_edit_group": False,
        "can_create_polls": False, "can_create_events": False, "can_start_calls": False,
        "can_send_announcements": False, "can_invite": False,
    },
}


class Group(SoftDeleteModel):
    __tablename__ = "groups"

    name = db.Column(db.String(255), nullable=False)
    description = db.Column(Text, default="")
    photo_key = db.Column(db.String(500))
    creator_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)
    group_type = db.Column(db.String(30), default="interest")
    community_id = db.Column(db.String(32), ForeignKey("communities.id"), index=True)
    cooperative_id = db.Column(db.String(32), ForeignKey("cooperatives.id"), index=True)
    is_private = db.Column(Boolean, default=False, nullable=False)
    require_approval = db.Column(Boolean, default=True, nullable=False)
    member_count = db.Column(Integer, default=0, nullable=False)
    invite_code = db.Column(db.String(40), unique=True, nullable=True, index=True)

    members = relationship("GroupMember", back_populates="group", lazy="selectin")


class GroupMember(BaseModel):
    __tablename__ = "group_members"
    __table_args__ = (
        UniqueConstraint("group_id", "user_id", name="uq_group_member"),
    )

    group_id = db.Column(db.String(32), ForeignKey("groups.id"), nullable=False, index=True)
    user_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)
    role = db.Column(db.String(30), default="FARMER", nullable=False, index=True)
    joined_at = db.Column(db.DateTime(timezone=True), default=utcnow)
    left_at = db.Column(db.DateTime(timezone=True))
    is_banned = db.Column(Boolean, default=False, nullable=False)
    banned_reason = db.Column(db.String(255), default="")

    group = relationship("Group", back_populates="members")


class GroupRole(BaseModel):
    __tablename__ = "group_roles"
    __table_args__ = (UniqueConstraint("group_id", "role", name="uq_group_role_def"),)

    group_id = db.Column(db.String(32), ForeignKey("groups.id"), nullable=False, index=True)
    role = db.Column(db.String(30), nullable=False)
    permissions_json = db.Column(Text, default="{}")


class GroupPermission(BaseModel):
    __tablename__ = "group_permissions"
    __table_args__ = (UniqueConstraint("group_id", "permission_key", name="uq_group_permission"),)

    group_id = db.Column(db.String(32), ForeignKey("groups.id"), nullable=False, index=True)
    permission_key = db.Column(db.String(40), nullable=False)
    allowed_roles_json = db.Column(Text, default='["ADMIN"]')


class GroupInvite(BaseModel):
    __tablename__ = "group_invites"
    group_id = db.Column(db.String(32), ForeignKey("groups.id"), nullable=False, index=True)
    code = db.Column(db.String(40), unique=True, nullable=False, index=True)
    created_by = db.Column(db.String(32), ForeignKey("users.id"), nullable=False)
    expires_at = db.Column(db.DateTime(timezone=True))
    revoked = db.Column(Boolean, default=False, nullable=False)
    use_count = db.Column(Integer, default=0)


class GroupJoinRequest(BaseModel):
    __tablename__ = "group_join_requests"
    __table_args__ = (
        UniqueConstraint("group_id", "user_id", name="uq_group_join_request"),
    )
    group_id = db.Column(db.String(32), ForeignKey("groups.id"), nullable=False, index=True)
    user_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)
    message = db.Column(db.String(255), default="")
    state = db.Column(db.String(20), default="PENDING", nullable=False)
    reviewed_by = db.Column(db.String(32), ForeignKey("users.id"))


class GroupAnnouncement(BaseModel):
    __tablename__ = "group_announcements"
    group_id = db.Column(db.String(32), ForeignKey("groups.id"), nullable=False, index=True)
    author_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False)
    body_text = db.Column(Text, nullable=False)
    mention_all = db.Column(Boolean, default=False, nullable=False)
    pinned = db.Column(Boolean, default=False, nullable=False)


class GroupBan(BaseModel):
    __tablename__ = "group_bans"
    __table_args__ = (UniqueConstraint("group_id", "user_id", name="uq_group_ban"),)

    group_id = db.Column(db.String(32), ForeignKey("groups.id"), nullable=False, index=True)
    user_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)
    reason = db.Column(db.String(255), default="")
    banned_by = db.Column(db.String(32), ForeignKey("users.id"))


class GroupKnowledgeItem(BaseModel):
    __tablename__ = "group_knowledge_items"
    group_id = db.Column(db.String(32), ForeignKey("groups.id"), nullable=False, index=True)
    title = db.Column(db.String(255), nullable=False)
    content = db.Column(Text, default="")
    category = db.Column(db.String(60), default="general")
    author_id = db.Column(db.String(32), ForeignKey("users.id"))
    pinned = db.Column(Boolean, default=False, nullable=False)


class GroupDocument(BaseModel):
    __tablename__ = "group_documents"
    group_id = db.Column(db.String(32), ForeignKey("groups.id"), nullable=False, index=True)
    uploader_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False)
    file_name = db.Column(db.String(255), nullable=False)
    storage_key = db.Column(db.String(500), nullable=False)
    mime_type = db.Column(db.String(120), default="")
    size_bytes = db.Column(Integer, default=0)
    category = db.Column(db.String(60), default="shared")


class ModerationAction(BaseModel):
    __tablename__ = "moderation_actions"
    actor_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)
    action = db.Column(db.String(40), nullable=False)
    subject_user_id = db.Column(db.String(32), ForeignKey("users.id"), index=True)
    scope_type = db.Column(db.String(30), default="platform")
    scope_id = db.Column(db.String(32))
    reason = db.Column(db.String(255), default="")
