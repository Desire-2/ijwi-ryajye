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

RISK_EVENT_TYPES = [
    "MULTI_ACCOUNT", "SELF_TRADING", "FAKE_REVIEW", "BID_MANIPULATION",
    "PAYMENT_ABUSE", "SUSPICIOUS_WITHDRAWAL", "ACCOUNT_TAKEOVER",
    "FAKE_LISTING", "REPEATED_CANCELLATION", "SPAM_BEHAVIOR", "REPORT_ABUSE",
]


class AuditLog(BaseModel):
    __tablename__ = "audit_logs"
    __table_args__ = (
        Index("ix_auditlog_actor_created", "actor_id", "created_at"),
        Index("ix_auditlog_subject", "subject_type", "subject_id"),
    )

    actor_id = db.Column(db.String(32), ForeignKey("users.id"), index=True)
    actor_role = db.Column(db.String(40))
    action = db.Column(db.String(80), nullable=False)
    subject_type = db.Column(db.String(40), nullable=False)
    subject_id = db.Column(db.String(32), nullable=False)
    metadata_json = db.Column(Text, default="{}")
    ip_address = db.Column(db.String(64))
    request_id = db.Column(db.String(64))


class RiskEvent(BaseModel):
    __tablename__ = "risk_events"
    __table_args__ = (Index("ix_riskevents_user_created", "user_id", "created_at"),)

    user_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)
    event_type = db.Column(db.String(40), nullable=False)
    score_delta = db.Column(Integer, default=0, nullable=False)
    detail_json = db.Column(Text, default="{}")
    flagged_for_review = db.Column(Boolean, default=False, nullable=False)


class Dispute(BaseModel):
    __tablename__ = "disputes"
    order_id = db.Column(db.String(32), ForeignKey("orders.id"), nullable=False, index=True)
    opened_by = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)
    against_user_id = db.Column(db.String(32), ForeignKey("users.id"))
    dispute_type = db.Column(db.String(40), nullable=False)
    state = db.Column(db.String(30), default="OPEN", nullable=False, index=True)
    description = db.Column(Text, default="")
    resolution_note = db.Column(Text)
    resolved_at = db.Column(db.DateTime(timezone=True))
    assigned_admin_id = db.Column(db.String(32), ForeignKey("users.id"))


class DisputeEvidence(BaseModel):
    __tablename__ = "dispute_evidence"
    dispute_id = db.Column(db.String(32), ForeignKey("disputes.id"), nullable=False, index=True)
    submitted_by = db.Column(db.String(32), ForeignKey("users.id"), nullable=False)
    evidence_type = db.Column(db.String(20), nullable=False)
    storage_key = db.Column(db.String(500))
    message_id = db.Column(db.String(32), ForeignKey("messages.id"))
    payment_transaction_id = db.Column(db.String(32), ForeignKey("payment_transactions.id"))
    description = db.Column(db.String(500), default="")


class SyncOperation(BaseModel):
    __tablename__ = "sync_operations"
    __table_args__ = (
        UniqueConstraint("client_op_id", name="uq_sync_client_op"),
        Index("ix_syncops_user_created", "user_id", "created_at"),
    )
    user_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)
    client_op_id = db.Column(db.String(80), nullable=False)
    op_type = db.Column(db.String(60), nullable=False)
    payload_json = db.Column(Text, default="{}")
    result_state = db.Column(db.String(20), default="APPLIED", nullable=False)
    server_ref_type = db.Column(db.String(40))
    server_ref_id = db.Column(db.String(32))


class ExportRequest(BaseModel):
    __tablename__ = "export_requests"
    user_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)
    state = db.Column(db.String(20), default="PENDING", nullable=False)
    download_key = db.Column(db.String(500))
    completed_at = db.Column(db.DateTime(timezone=True))


class DeletionRequest(BaseModel):
    __tablename__ = "deletion_requests"
    user_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, unique=True, index=True)
    reason = db.Column(db.Text, default="")
    state = db.Column(db.String(20), default="REQUESTED", nullable=False)
    processed_at = db.Column(db.DateTime(timezone=True))
