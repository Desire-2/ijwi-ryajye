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
    Numeric,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.orm import relationship

from extensions import db
from app.models.base import BaseModel, utcnow

ORDER_STATES = [
    "DRAFT", "OFFERED", "NEGOTIATING", "ACCEPTED", "PAYMENT_PENDING", "PAID",
    "PROCESSING", "READY_FOR_PICKUP", "IN_TRANSIT", "DELIVERED", "COMPLETED",
    "CANCELLED", "DISPUTED", "REFUNDED",
]

ALLOWED_ORDER_TRANSITIONS = {
    "DRAFT": {"OFFERED", "NEGOTIATING", "ACCEPTED", "CANCELLED"},
    "OFFERED": {"NEGOTIATING", "ACCEPTED", "CANCELLED"},
    "NEGOTIATING": {"ACCEPTED", "CANCELLED"},
    "ACCEPTED": {"PAYMENT_PENDING", "PROCESSING", "CANCELLED"},
    "PAYMENT_PENDING": {"PAID", "CANCELLED"},
    "PAID": {"PROCESSING", "REFUNDED", "DISPUTED"},
    "PROCESSING": {"READY_FOR_PICKUP", "CANCELLED", "DISPUTED"},
    "READY_FOR_PICKUP": {"IN_TRANSIT", "CANCELLED", "DISPUTED"},
    "IN_TRANSIT": {"DELIVERED", "DISPUTED"},
    "DELIVERED": {"COMPLETED", "DISPUTED"},
    "COMPLETED": set(),
    "CANCELLED": set(),
    "DISPUTED": {"REFUNDED", "COMPLETED", "CANCELLED"},
    "REFUNDED": set(),
}

ORDER_CANCELABLE_STATES = {
    "DRAFT", "OFFERED", "NEGOTIATING", "ACCEPTED",
    "PAYMENT_PENDING", "PAID", "PROCESSING", "READY_FOR_PICKUP",
}


class Order(BaseModel):
    __tablename__ = "orders"

    order_number = db.Column(db.String(24), unique=True, nullable=False, index=True)
    listing_id = db.Column(db.String(32), ForeignKey("listings.id"), index=True)
    offer_id = db.Column(db.String(32), ForeignKey("offers.id"), index=True)
    bid_id = db.Column(db.String(32), ForeignKey("bids.id"), index=True)
    buyer_request_id = db.Column(db.String(32), ForeignKey("buyer_requests.id"), index=True)

    buyer_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)
    seller_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)
    state = db.Column(db.String(30), default="DRAFT", nullable=False, index=True)

    quantity_value = db.Column(Numeric(14, 3), nullable=False)
    unit_code = db.Column(db.String(20), nullable=False, default="kg")
    unit_price_minor = db.Column(BigInteger, nullable=False)
    total_amount_minor = db.Column(BigInteger, nullable=False)
    platform_fee_minor = db.Column(BigInteger, default=0)
    currency_code = db.Column(db.String(3), nullable=False)
    delivery_option = db.Column(db.String(30), default="PICKUP")
    delivery_address = db.Column(db.String(500), default="")
    payment_terms = db.Column(db.String(255), default="")
    cancelled_reason = db.Column(Text)
    completed_at = db.Column(db.DateTime(timezone=True))
    delivery_id = db.Column(db.String(32), ForeignKey("deliveries.id"), index=True)
    contract_id = db.Column(db.String(32), ForeignKey("contracts.id"), index=True)
    payout_released = db.Column(Boolean, default=False, nullable=False)

    items = relationship("OrderItem", back_populates="order", lazy="selectin")

    __table_args__ = (
        CheckConstraint("quantity_value > 0", name="ck_order_qty"),
        CheckConstraint("total_amount_minor >= 0", name="ck_order_total"),
        Index("ix_orders_buyer_state", "buyer_id", "state"),
        Index("ix_orders_seller_state", "seller_id", "state"),
    )


class OrderItem(BaseModel):
    __tablename__ = "order_items"
    order_id = db.Column(db.String(32), ForeignKey("orders.id"), nullable=False, index=True)
    product_id = db.Column(db.String(32), ForeignKey("products.id"), nullable=False)
    description = db.Column(db.String(255), default="")
    quantity_value = db.Column(Numeric(14, 3), nullable=False)
    unit_code = db.Column(db.String(20), nullable=False, default="kg")
    unit_price_minor = db.Column(BigInteger, nullable=False)
    line_total_minor = db.Column(BigInteger, nullable=False)
    quality_grade = db.Column(db.String(20), default="UNGRADED")

    order = relationship("Order", back_populates="items")


class OrderEvent(BaseModel):
    __tablename__ = "order_events"
    order_id = db.Column(db.String(32), ForeignKey("orders.id"), nullable=False, index=True)
    actor_id = db.Column(db.String(32), ForeignKey("users.id"))
    event_type = db.Column(db.String(40), nullable=False)
    from_state = db.Column(db.String(30))
    to_state = db.Column(db.String(30))
    detail_json = db.Column(Text, default="{}")


class Review(BaseModel):
    __tablename__ = "reviews"
    __table_args__ = (
        CheckConstraint("overall_rating BETWEEN 1 AND 5", name="ck_review_overall"),
        UniqueConstraint("order_id", "reviewer_id", "subject_role", name="uq_review_per_order"),
    )

    order_id = db.Column(db.String(32), ForeignKey("orders.id"), nullable=False, index=True)
    reviewer_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)
    subject_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)
    subject_role = db.Column(db.String(20), nullable=False)
    overall_rating = db.Column(Integer, nullable=False, default=5)
    communication_rating = db.Column(Integer)
    accuracy_rating = db.Column(Integer)
    reliability_rating = db.Column(Integer)
    payment_rating = db.Column(Integer)
    delivery_rating = db.Column(Integer)
    comment = db.Column(Text, default="")
    verified_transaction = db.Column(Boolean, default=True, nullable=False)
