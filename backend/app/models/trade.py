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
)
from sqlalchemy.orm import relationship

from extensions import db
from app.models.base import BaseModel, utcnow

OFFER_STATES = [
    "PENDING", "COUNTERED", "ACCEPTED", "REJECTED", "WITHDRAWN", "EXPIRED", "CANCELLED",
]
BID_STATES = ["ACTIVE", "WINNING", "OUTBID", "ACCEPTED", "REJECTED", "RETRACTED"]
CONTRACT_STATES = ["DRAFT", "ACTIVE", "COMPLETED", "TERMINATED"]


class Offer(BaseModel):
    __tablename__ = "offers"

    listing_id = db.Column(db.String(32), ForeignKey("listings.id"), index=True)
    buyer_request_id = db.Column(db.String(32), ForeignKey("buyer_requests.id"), index=True)
    buyer_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)
    seller_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)
    parent_offer_id = db.Column(db.String(32), ForeignKey("offers.id"), index=True)
    state = db.Column(db.String(20), default="PENDING", nullable=False, index=True)

    quantity_value = db.Column(Numeric(14, 3), nullable=False)
    unit_code = db.Column(db.String(20), nullable=False, default="kg")
    price_minor = db.Column(BigInteger, nullable=False)
    currency_code = db.Column(db.String(3), nullable=False)
    delivery_option = db.Column(db.String(30), default="PICKUP")
    payment_terms = db.Column(db.String(255), default="")
    message = db.Column(Text, default="")
    expires_at = db.Column(db.DateTime(timezone=True))
    responded_at = db.Column(db.DateTime(timezone=True))

    __table_args__ = (
        CheckConstraint("quantity_value > 0", name="ck_offer_qty"),
        CheckConstraint("price_minor >= 0", name="ck_offer_price"),
        Index("ix_offers_listing_state", "listing_id", "state"),
        Index("ix_offers_seller_state", "seller_id", "state"),
    )


class OfferEvent(BaseModel):
    __tablename__ = "offer_events"
    offer_id = db.Column(db.String(32), ForeignKey("offers.id"), nullable=False, index=True)
    actor_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False)
    event_type = db.Column(db.String(30), nullable=False)
    snapshot_json = db.Column(Text, default="{}")


class Bid(BaseModel):
    __tablename__ = "bids"

    listing_id = db.Column(db.String(32), ForeignKey("listings.id"), nullable=False, index=True)
    bidder_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)
    amount_minor = db.Column(BigInteger, nullable=False)
    quantity_value = db.Column(Numeric(14, 3), nullable=False)
    unit_code = db.Column(db.String(20), nullable=False, default="kg")
    currency_code = db.Column(db.String(3), nullable=False)
    state = db.Column(db.String(20), default="ACTIVE", nullable=False, index=True)
    is_winning = db.Column(Boolean, default=False, nullable=False)
    placed_at = db.Column(db.DateTime(timezone=True), default=utcnow, nullable=False)

    __table_args__ = (
        CheckConstraint("amount_minor >= 0", name="ck_bid_amount"),
        CheckConstraint("quantity_value > 0", name="ck_bid_qty"),
        Index("ix_bids_listing_state_amount", "listing_id", "state", "amount_minor"),
    )


class Contract(BaseModel):
    __tablename__ = "contracts"
    version = db.Column(Integer, default=1, nullable=False)
    supersedes_id = db.Column(db.String(32), ForeignKey("contracts.id"), index=True)
    order_id = db.Column(db.String(32), ForeignKey("orders.id"), index=True)
    seller_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)
    buyer_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)
    state = db.Column(db.String(20), default="DRAFT", nullable=False)
    terms_json = db.Column(Text, nullable=False)
    document_key = db.Column(db.String(500))

    __table_args__ = (
        Index("ix_contracts_parties", "seller_id", "buyer_id"),
    )
