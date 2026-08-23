from sqlalchemy import (
    BigInteger,
    Boolean,
    CheckConstraint,
    Column,
    Date,
    DateTime,
    ForeignKey,
    Index,
    Numeric,
    String,
    Text,
)
from sqlalchemy.orm import relationship

from extensions import db
from app.models.base import BaseModel, utcnow

DELIVERY_REQUEST_STATES = ["REQUESTED", "QUOTED", "MATCHED", "CANCELLED", "EXPIRED"]
DELIVERY_STATES = [
    "ACCEPTED", "PICKUP_SCHEDULED", "PICKED_UP", "IN_TRANSIT", "DELIVERED", "CONFIRMED", "FAILED",
]
VEHICLE_TYPES = [
    "motorcycle", "pickup", "van", "truck_small", "truck_medium", "truck_large", "refrigerated",
]


class Vehicle(BaseModel):
    __tablename__ = "vehicles"
    owner_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)
    vehicle_type = db.Column(db.String(30), nullable=False)
    plate_number = db.Column(db.String(30), nullable=False, unique=True)
    capacity_value = db.Column(Numeric(12, 3), default=0)
    capacity_unit = db.Column(db.String(20), default="kg")
    model = db.Column(db.String(120), default="")
    active = db.Column(Boolean, default=True, nullable=False)

    __table_args__ = (CheckConstraint("capacity_value >= 0", name="ck_vehicle_capacity"),)


class DeliveryRequest(BaseModel):
    __tablename__ = "delivery_requests"
    requester_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)
    order_id = db.Column(db.String(32), ForeignKey("orders.id"), index=True)
    pickup_region = db.Column(db.String(120), nullable=False)
    pickup_district = db.Column(db.String(120))
    destination_region = db.Column(db.String(120), nullable=False)
    destination_district = db.Column(db.String(120))
    product_description = db.Column(db.String(255), default="")
    quantity_value = db.Column(Numeric(14, 3), nullable=False)
    unit_code = db.Column(db.String(20), nullable=False, default="kg")
    vehicle_type_required = db.Column(db.String(30))
    requested_pickup_date = db.Column(Date)
    state = db.Column(db.String(20), default="REQUESTED", nullable=False, index=True)
    budget_minor = db.Column(BigInteger)
    currency_code = db.Column(db.String(3), default="RWF")

    __table_args__ = (CheckConstraint("quantity_value > 0", name="ck_delreq_qty"),)


class DeliveryQuote(BaseModel):
    __tablename__ = "delivery_quotes"
    __table_args__ = (
        CheckConstraint("price_minor >= 0", name="ck_quote_price"),
    )
    delivery_request_id = db.Column(
        db.String(32), ForeignKey("delivery_requests.id"), nullable=False, index=True
    )
    provider_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)
    vehicle_id = db.Column(db.String(32), ForeignKey("vehicles.id"))
    price_minor = db.Column(BigInteger, nullable=False)
    currency_code = db.Column(db.String(3), nullable=False)
    eta_hours = db.Column(Numeric(6, 1))
    message = db.Column(db.String(255), default="")
    state = db.Column(db.String(20), default="SUBMITTED", nullable=False)


class Delivery(BaseModel):
    __tablename__ = "deliveries"
    delivery_request_id = db.Column(
        db.String(32), ForeignKey("delivery_requests.id"), index=True
    )
    order_id = db.Column(db.String(32), ForeignKey("orders.id"), index=True)
    provider_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)
    vehicle_id = db.Column(db.String(32), ForeignKey("vehicles.id"))
    state = db.Column(db.String(20), default="ACCEPTED", nullable=False, index=True)
    agreed_price_minor = db.Column(BigInteger, nullable=False)
    platform_fee_minor = db.Column(BigInteger, default=0)
    currency_code = db.Column(db.String(3), nullable=False)
    picked_up_at = db.Column(db.DateTime(timezone=True))
    delivered_at = db.Column(db.DateTime(timezone=True))
    confirmed_at = db.Column(db.DateTime(timezone=True))
    proof_of_delivery_keys = db.Column(db.Text, default="")
    delivery_notes = db.Column(db.Text, default="")


class DeliveryEvent(BaseModel):
    __tablename__ = "delivery_events"
    delivery_id = db.Column(db.String(32), ForeignKey("deliveries.id"), nullable=False, index=True)
    actor_id = db.Column(db.String(32), ForeignKey("users.id"))
    event_type = db.Column(db.String(40), nullable=False)
    detail_json = db.Column(Text, default="{}")
