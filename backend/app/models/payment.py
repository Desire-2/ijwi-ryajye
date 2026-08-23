from sqlalchemy import (
    BigInteger,
    Boolean,
    CheckConstraint,
    Column,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    Numeric,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.orm import relationship

from extensions import db
from app.models.base import BaseModel, utcnow

PAYMENT_STATES = ["INITIATED", "PENDING_PROVIDER", "PROCESSING", "SUCCEEDED", "FAILED", "REFUNDED", "CANCELLED"]
PAYMENT_DIRECTIONS = ["COLLECTION", "PAYOUT", "REFUND"]
LEDGER_ENTRY_TYPES = ["CREDIT", "DEBIT"]
LEDGER_REASONS = [
    "ORDER_PAYMENT_RECEIVED", "PLATFORM_FEE", "SALE_EARNING",
    "WITHDRAWAL", "WITHDRAWAL_REFUND", "REFUND_TO_BUYER",
    "COOP_SETTLEMENT_IN", "COOP_SETTLEMENT_OUT", "ADJUSTMENT", "ESCROW_HOLD", "ESCROW_RELEASE",
]
WITHDRAWAL_STATES = ["REQUESTED", "APPROVED", "PROCESSING", "COMPLETED", "FAILED", "REJECTED"]
FEE_SCOPES = ["MARKETPLACE_SALE", "LOGISTICS_JOB", "WITHDRAWAL", "LISTING_PROMOTION", "SUBSCRIPTION_PREMIUM_FARMER"]


class PaymentTransaction(BaseModel):
    __tablename__ = "payment_transactions"
    __table_args__ = (
        UniqueConstraint("provider", "provider_reference", name="uq_provider_reference"),
        CheckConstraint("amount_minor > 0", name="ck_payment_amount"),
        Index("ix_payments_order_state", "order_id", "state"),
        Index("ix_payments_user_created", "user_id", "created_at"),
    )

    order_id = db.Column(db.String(32), ForeignKey("orders.id"), index=True)
    user_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)
    direction = db.Column(db.String(20), default="COLLECTION", nullable=False)
    provider = db.Column(db.String(30), nullable=False)
    provider_reference = db.Column(db.String(120), nullable=True)
    provider_memo = db.Column(db.String(255), default="")
    method = db.Column(db.String(30), nullable=False)
    state = db.Column(db.String(20), default="INITIATED", nullable=False, index=True)
    amount_minor = db.Column(BigInteger, nullable=False)
    fee_minor = db.Column(BigInteger, default=0)
    currency_code = db.Column(db.String(3), nullable=False)
    failure_reason = db.Column(db.String(255))
    idempotency_key = db.Column(db.String(80), unique=True, nullable=True)
    completed_at = db.Column(db.DateTime(timezone=True))

    def to_public_dict(self):
        return {
            "id": self.id,
            "order_id": self.order_id,
            "direction": self.direction,
            "state": self.state,
            "method": self.method,
            "provider_reference": self.provider_reference,
            "amount_minor": self.amount_minor,
            "currency_code": self.currency_code,
            "completed_at": self.completed_at.isoformat() if self.completed_at else None,
        }


class PaymentWebhookEvent(BaseModel):
    __tablename__ = "payment_webhook_events"
    __table_args__ = (
        UniqueConstraint("provider", "event_id", name="uq_webhook_event"),
    )

    provider = db.Column(db.String(30), nullable=False)
    event_id = db.Column(db.String(160), nullable=False)
    signature_valid = db.Column(Boolean, nullable=False, default=False)
    processed = db.Column(Boolean, nullable=False, default=False)
    payload_json = db.Column(Text, default="")
    processing_error = db.Column(db.Text)


class Wallet(BaseModel):
    __tablename__ = "wallets"
    user_id = db.Column(db.String(32), ForeignKey("users.id"), unique=True, nullable=False, index=True)
    cooperative_id = db.Column(db.String(32), ForeignKey("cooperatives.id"), index=True)
    currency_code = db.Column(db.String(3), nullable=False, default="RWF")
    available_balance_minor = db.Column(BigInteger, nullable=False, default=0)
    pending_balance_minor = db.Column(BigInteger, nullable=False, default=0)
    total_earned_minor = db.Column(BigInteger, nullable=False, default=0)
    total_withdrawn_minor = db.Column(BigInteger, nullable=False, default=0)

    __table_args__ = (
        CheckConstraint("available_balance_minor >= 0", name="ck_wallet_available_nonneg"),
        CheckConstraint("pending_balance_minor >= 0", name="ck_wallet_pending_nonneg"),
    )


class WalletLedgerEntry(BaseModel):
    __tablename__ = "wallet_ledger_entries"
    __table_args__ = (
        CheckConstraint("amount_minor != 0", name="ck_ledger_amount_nonzero"),
        Index("ix_ledger_wallet_created", "wallet_id", "created_at"),
        UniqueConstraint("idempotency_key", name="uq_ledger_idempotency"),
    )

    wallet_id = db.Column(db.String(32), ForeignKey("wallets.id"), nullable=False, index=True)
    entry_type = db.Column(db.String(10), nullable=False)
    reason_code = db.Column(db.String(40), nullable=False)
    amount_minor = db.Column(BigInteger, nullable=False)
    balance_after_minor = db.Column(BigInteger, nullable=False)
    pending_delta_minor = db.Column(BigInteger, default=0)
    pending_balance_after_minor = db.Column(BigInteger, default=0)
    currency_code = db.Column(db.String(3), nullable=False)
    reference_type = db.Column(db.String(40), default="")
    reference_id = db.Column(db.String(32), default="", index=True)
    description = db.Column(db.String(255), default="")
    idempotency_key = db.Column(db.String(120), nullable=True)


class Withdrawal(BaseModel):
    __tablename__ = "withdrawals"
    user_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)
    wallet_id = db.Column(db.String(32), ForeignKey("wallets.id"), nullable=False)
    amount_minor = db.Column(BigInteger, nullable=False)
    fee_minor = db.Column(BigInteger, default=0)
    currency_code = db.Column(db.String(3), nullable=False)
    destination_method = db.Column(db.String(30), nullable=False)
    destination_detail = db.Column(db.String(255), default="")
    state = db.Column(db.String(20), default="REQUESTED", nullable=False, index=True)
    provider_reference = db.Column(db.String(120))
    failure_reason = db.Column(db.String(255))
    completed_at = db.Column(db.DateTime(timezone=True))

    __table_args__ = (CheckConstraint("amount_minor > 0", name="ck_withdrawal_amount"),)


class PlatformFee(BaseModel):
    __tablename__ = "platform_fees"
    scope = db.Column(db.String(40), nullable=False, unique=True, index=True)
    bps = db.Column(Integer, nullable=False, default=250)
    min_fee_minor = db.Column(BigInteger, default=0)
    max_fee_minor = db.Column(BigInteger)
    active = db.Column(Boolean, default=True, nullable=False)

    __table_args__ = (CheckConstraint("bps BETWEEN 0 AND 5000", name="ck_fee_bps"),)


class SubscriptionPlan(BaseModel):
    __tablename__ = "subscription_plans"
    code = db.Column(db.String(60), unique=True, nullable=False)
    name = db.Column(db.String(120), nullable=False)
    audience_role = db.Column(db.String(40), default="FARMER")
    price_minor = db.Column(BigInteger, default=0)
    billing_period = db.Column(db.String(20), default="monthly")
    features_json = db.Column(Text, default="{}")
    active = db.Column(Boolean, default=True, nullable=False)


class UserSubscription(BaseModel):
    __tablename__ = "user_subscriptions"
    user_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)
    plan_id = db.Column(db.String(32), ForeignKey("subscription_plans.id"), nullable=False)
    starts_at = db.Column(db.DateTime(timezone=True), default=utcnow)
    ends_at = db.Column(db.DateTime(timezone=True))
    active = db.Column(Boolean, default=True, nullable=False)
