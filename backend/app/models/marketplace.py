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
    Numeric,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.orm import relationship

from extensions import db
from app.models.base import BaseModel, SoftDeleteModel, utcnow

LISTING_TYPES = ["FIXED_PRICE", "NEGOTIABLE", "AUCTION", "FORWARD_CONTRACT", "GROUP_SALE"]
LISTING_STATES = [
    "DRAFT", "ACTIVE", "PAUSED", "CLOSED", "EXPIRED", "SOLD_OUT",
]
QUALITY_GRADES = ["PREMIUM", "GRADE_A", "GRADE_B", "STANDARD", "UNGRADED"]
PRICE_TYPES = ["PER_UNIT", "TOTAL", "NEGOTIABLE"]
DELIVERY_OPTIONS = ["PICKUP", "SELLER_DELIVERY", "BUYER_ARRANGES", "NEGOTIABLE"]
INVENTORY_STATES = [
    "AVAILABLE", "RESERVED", "SOLD", "IN_TRANSIT", "DAMAGED", "EXPIRED",
]
BUYER_REQUEST_STATES = ["OPEN", "MATCHING", "FULFILLED", "CANCELLED", "EXPIRED"]


class Inventory(BaseModel):
    __tablename__ = "inventories"
    __table_args__ = (
        CheckConstraint("quantity_total >= 0", name="ck_inv_total"),
        CheckConstraint("quantity_reserved >= 0", name="ck_inv_reserved"),
        CheckConstraint("quantity_sold >= 0", name="ck_inv_sold"),
        CheckConstraint("quantity_total - quantity_reserved - quantity_sold >= 0", name="ck_inv_nonneg"),
        UniqueConstraint("owner_id", "product_id", "farm_id", "batch_ref", name="uq_inventory_batch"),
        Index("ix_inventories_owner_product_state", "owner_id", "product_id", "state"),
    )

    owner_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)
    farm_id = db.Column(db.String(32), ForeignKey("farms.id"), index=True)
    product_id = db.Column(db.String(32), ForeignKey("products.id"), nullable=False)
    batch_ref = db.Column(db.String(80), default="default")
    state = db.Column(db.String(20), default="AVAILABLE", nullable=False, index=True)
    quantity_value = db.Column(Numeric(14, 3), nullable=False, default=0)
    unit_code = db.Column(db.String(20), nullable=False, default="kg")
    quantity_total = db.Column(Numeric(14, 3), nullable=False, default=0)
    quantity_reserved = db.Column(Numeric(14, 3), nullable=False, default=0)
    quantity_sold = db.Column(Numeric(14, 3), nullable=False, default=0)

    product = relationship("Product")

    @property
    def available(self):
        return float(self.quantity_total) - float(self.quantity_reserved) - float(self.quantity_sold)


class InventoryReservation(BaseModel):
    __tablename__ = "inventory_reservations"
    inventory_id = db.Column(db.String(32), ForeignKey("inventories.id"), nullable=False, index=True)
    order_id = db.Column(db.String(32), ForeignKey("orders.id"), index=True)
    offer_id = db.Column(db.String(32), ForeignKey("offers.id"), index=True)
    bid_id = db.Column(db.String(32), ForeignKey("bids.id"), index=True)
    listing_id = db.Column(db.String(32), ForeignKey("listings.id"), index=True)
    buyer_request_id = db.Column(db.String(32), ForeignKey("buyer_requests.id"), index=True)
    quantity_value = db.Column(Numeric(14, 3), nullable=False)
    unit_code = db.Column(db.String(20), nullable=False, default="kg")
    status = db.Column(db.String(20), default="ACTIVE", nullable=False, index=True)
    released_at = db.Column(db.DateTime(timezone=True))
    expires_at = db.Column(db.DateTime(timezone=True))

    __table_args__ = (
        CheckConstraint("quantity_value > 0", name="ck_res_qty_positive"),
    )


class Listing(SoftDeleteModel):
    __tablename__ = "listings"

    seller_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)
    farm_id = db.Column(db.String(32), ForeignKey("farms.id"), index=True)
    cooperative_id = db.Column(db.String(32), ForeignKey("cooperatives.id"), index=True)
    group_id = db.Column(db.String(32), ForeignKey("groups.id"), index=True)
    product_id = db.Column(db.String(32), ForeignKey("products.id"), nullable=False, index=True)
    variety = db.Column(db.String(120), default="")
    title = db.Column(db.String(255), nullable=False)
    description = db.Column(db.Text, default="")
    listing_type = db.Column(db.String(30), default="FIXED_PRICE", nullable=False)
    state = db.Column(db.String(20), default="ACTIVE", nullable=False, index=True)

    quantity_value = db.Column(Numeric(14, 3), nullable=False)
    available_quantity = db.Column(Numeric(14, 3), nullable=False)
    unit_code = db.Column(db.String(20), nullable=False, default="kg")
    expected_harvest_date = db.Column(Date)
    available_from = db.Column(Date)

    quality_grade = db.Column(db.String(20), default="UNGRADED")
    production_method = db.Column(db.String(30))
    certification = db.Column(db.String(255), default="")
    location_region = db.Column(db.String(120))
    location_district = db.Column(db.String(120))

    price_minor = db.Column(BigInteger)
    currency_code = db.Column(db.String(3), default="RWF", nullable=False)
    price_type = db.Column(db.String(20), default="PER_UNIT")
    negotiable = db.Column(Boolean, default=False)
    minimum_order_value = db.Column(Numeric(14, 3), default=0)
    maximum_order_value = db.Column(Numeric(14, 3))

    auction_start_at = db.Column(db.DateTime(timezone=True))
    auction_end_at = db.Column(db.DateTime(timezone=True))
    reserve_price_minor = db.Column(BigInteger)
    min_bid_increment_minor = db.Column(BigInteger, default=100)

    delivery_options = db.Column(db.String(120), default="PICKUP,NEGOTIABLE")
    promoted_until = db.Column(db.DateTime(timezone=True))
    view_count = db.Column(Integer, default=0)
    expires_at = db.Column(db.DateTime(timezone=True))
    sold_quantity = db.Column(Numeric(14, 3), default=0)

    product = relationship("Product")

    __table_args__ = (
        CheckConstraint("quantity_value > 0", name="ck_listing_qty_positive"),
        CheckConstraint(
            "(price_minor IS NULL AND price_type = 'NEGOTIABLE') OR price_minor >= 0",
            name="ck_listing_price",
        ),
        CheckConstraint("available_quantity <= quantity_value", name="ck_listing_avail_lte"),
        Index("ix_listings_product_state_price", "product_id", "state", "price_minor"),
        Index("ix_listings_seller_state", "seller_id", "state"),
        Index("ix_listings_auction_end", "auction_end_at"),
    )

    @property
    def is_auction_active(self):
        now = utcnow()
        return (
            self.listing_type == "AUCTION"
            and self.state == "ACTIVE"
            and self.auction_start_at is not None
            and self.auction_start_at <= now
            and self.auction_end_at is not None
            and self.auction_end_at > now
        )


class ListingMedia(BaseModel):
    __tablename__ = "listing_media"
    listing_id = db.Column(db.String(32), ForeignKey("listings.id"), nullable=False, index=True)
    media_type = db.Column(db.String(10), default="image", nullable=False)
    storage_key = db.Column(db.String(500), nullable=False)
    position = db.Column(Integer, default=0)
    caption = db.Column(db.String(255), default="")


class BuyerRequest(BaseModel):
    __tablename__ = "buyer_requests"

    buyer_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)
    product_id = db.Column(db.String(32), ForeignKey("products.id"), nullable=False, index=True)
    title = db.Column(db.String(255), nullable=False)
    description = db.Column(db.Text, default="")
    quantity_value = db.Column(Numeric(14, 3), nullable=False)
    unit_code = db.Column(db.String(20), nullable=False, default="kg")
    quality_grade = db.Column(db.String(20), default="UNGRADED")
    destination_region = db.Column(db.String(120))
    destination_district = db.Column(db.String(120))
    required_by_date = db.Column(Date)
    budget_min_minor = db.Column(BigInteger)
    budget_max_minor = db.Column(BigInteger)
    currency_code = db.Column(db.String(3), default="RWF", nullable=False)
    state = db.Column(db.String(20), default="OPEN", nullable=False, index=True)
    expires_at = db.Column(db.DateTime(timezone=True))
    visible_to_groups = db.Column(db.Text, default="")

    product = relationship("Product")


class Promotion(BaseModel):
    __tablename__ = "promotions"
    subject_type = db.Column(db.String(20), nullable=False, index=True)
    subject_id = db.Column(db.String(32), nullable=False, index=True)
    purchaser_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False)
    promotion_type = db.Column(db.String(30), default="BOOST_LISTING")
    starts_at = db.Column(db.DateTime(timezone=True), default=utcnow)
    ends_at = db.Column(db.DateTime(timezone=True), nullable=False)
    price_paid_minor = db.Column(BigInteger, default=0)
    currency_code = db.Column(db.String(3), default="RWF")
    active = db.Column(Boolean, default=True, nullable=False)


class Favorite(BaseModel):
    __tablename__ = "favorites"
    __table_args__ = (UniqueConstraint("user_id", "subject_type", "subject_id", name="uq_favorite"),)

    user_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)
    subject_type = db.Column(db.String(30), nullable=False)
    subject_id = db.Column(db.String(32), nullable=False)


class SavedSearch(BaseModel):
    __tablename__ = "saved_searches"
    user_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)
    label = db.Column(db.String(120), default="")
    query_json = db.Column(Text, nullable=False)
    notify_on_new_matches = db.Column(Boolean, default=True, nullable=False)
