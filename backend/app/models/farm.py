from datetime import date

from sqlalchemy import (
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
)
from sqlalchemy.orm import relationship

from extensions import db
from app.models.base import BaseModel, SoftDeleteModel, utcnow

FARMING_METHODS = ["conventional", "organic", "mixed", "regenerative"]
SOIL_TYPES = ["clay", "sandy", "loam", "silt", "volcanic", "other"]
IRRIGATION_TYPES = ["rainfed", "drip", "sprinkler", "flood", "other"]

PRODUCTION_STATES = [
    "PLANNED", "PLANTED", "GROWING", "READY", "HARVESTED", "FAILED",
]
INVENTORY_STATES = [
    "AVAILABLE", "RESERVED", "SOLD", "IN_TRANSIT", "DAMAGED", "EXPIRED",
]


class Farm(SoftDeleteModel):
    __tablename__ = "farms"

    owner_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)
    cooperative_id = db.Column(db.String(32), ForeignKey("cooperatives.id"), index=True)
    name = db.Column(db.String(255), nullable=False)
    country_code = db.Column(db.String(2), nullable=False, default="RW")
    region = db.Column(db.String(120))
    district = db.Column(db.String(120))
    approx_lat = db.Column(Numeric(9, 6))
    approx_lng = db.Column(Numeric(9, 6))
    area_value = db.Column(Numeric(14, 2))
    area_unit = db.Column(db.String(20), default="ha")
    soil_type = db.Column(db.String(20))
    irrigation = db.Column(db.String(20))
    farming_method = db.Column(db.String(20), default="conventional")
    certification = db.Column(db.String(255), default="")
    capacity_notes = db.Column(db.Text, default="")
    media_keys = db.Column(db.Text, default="")
    verified = db.Column(Boolean, default=False)

    crops = relationship("FarmCrop", back_populates="farm", lazy="selectin")
    livestock = relationship("Livestock", back_populates="farm", lazy="selectin")

    __table_args__ = (
        CheckConstraint("area_value IS NULL OR area_value >= 0", name="ck_farms_area"),
        Index("ix_farms_location", "country_code", "region", "district"),
    )


class FarmCrop(BaseModel):
    __tablename__ = "farm_crops"
    farm_id = db.Column(db.String(32), ForeignKey("farms.id"), nullable=False, index=True)
    product_id = db.Column(db.String(32), ForeignKey("products.id"), nullable=False, index=True)
    variety = db.Column(db.String(120), default="")
    area_value = db.Column(Numeric(14, 2))
    area_unit = db.Column(db.String(20), default="ha")
    planting_date = db.Column(Date)
    expected_harvest_date = db.Column(Date)
    expected_quantity_value = db.Column(Numeric(14, 3))
    expected_quantity_unit = db.Column(db.String(20), default="kg")
    production_cost_minor = db.Column(db.BigInteger, default=0)
    currency_code = db.Column(db.String(3), default="RWF")
    state = db.Column(db.String(20), default="PLANNED", nullable=False)
    notes = db.Column(db.Text, default="")

    farm = relationship("Farm", back_populates="crops")
    product = relationship("Product")


class Livestock(BaseModel):
    __tablename__ = "livestock"
    farm_id = db.Column(db.String(32), ForeignKey("farms.id"), nullable=False, index=True)
    product_id = db.Column(db.String(32), ForeignKey("products.id"), nullable=False, index=True)
    breed = db.Column(db.String(120), default="")
    head_count = db.Column(Integer, nullable=False, default=0)
    avg_age_months = db.Column(Integer)
    purpose = db.Column(db.String(40), default="meat")
    notes = db.Column(db.Text, default="")

    farm = relationship("Farm", back_populates="livestock")
    product = relationship("Product")

    __table_args__ = (CheckConstraint("head_count >= 0", name="ck_livestock_head"),)


class ProductionRecord(BaseModel):
    __tablename__ = "production_records"
    farm_crop_id = db.Column(db.String(32), ForeignKey("farm_crops.id"), index=True)
    livestock_id = db.Column(db.String(32), ForeignKey("livestock.id"), index=True)
    farm_id = db.Column(db.String(32), ForeignKey("farms.id"), nullable=False, index=True)
    event_type = db.Column(db.String(30), nullable=False)
    occurred_on = db.Column(Date, nullable=False, default=date.today)
    quantity_value = db.Column(Numeric(14, 3))
    quantity_unit = db.Column(db.String(20), default="kg")
    cost_minor = db.Column(db.BigInteger, default=0)
    currency_code = db.Column(db.String(3), default="RWF")
    notes = db.Column(db.Text, default="")


class ExpenseRecord(BaseModel):
    __tablename__ = "expense_records"
    farm_id = db.Column(db.String(32), ForeignKey("farms.id"), nullable=False, index=True)
    category = db.Column(db.String(60), nullable=False)
    amount_minor = db.Column(db.BigInteger, nullable=False)
    currency_code = db.Column(db.String(3), nullable=False)
    incurred_on = db.Column(Date, nullable=False, default=date.today)
    note = db.Column(db.Text, default="")

    __table_args__ = (CheckConstraint("amount_minor >= 0", name="ck_expense_amount"),)


class BusinessRecord(BaseModel):
    __tablename__ = "business_records"
    user_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)
    record_type = db.Column(
        db.String(30), nullable=False
    )
    counterparty_name = db.Column(db.String(255))
    amount_minor = db.Column(db.BigInteger, nullable=False)
    currency_code = db.Column(db.String(3), nullable=False)
    occurred_on = db.Column(Date, nullable=False, default=date.today)
    reference = db.Column(db.String(255), default="")
    note = db.Column(db.Text, default="")


class ProductionPlan(BaseModel):
    __tablename__ = "production_plans"
    user_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)
    farm_crop_id = db.Column(db.String(32), ForeignKey("farm_crops.id"), index=True)
    crop_product_id = db.Column(db.String(32), ForeignKey("products.id"), nullable=False)
    planting_date = db.Column(Date)
    expected_harvest_date = db.Column(Date)
    expected_quantity_value = db.Column(Numeric(14, 3), nullable=False)
    expected_quantity_unit = db.Column(db.String(20), default="kg")
    production_cost_minor = db.Column(db.BigInteger, default=0)
    expected_price_minor = db.Column(db.BigInteger, default=0)
    currency_code = db.Column(db.String(3), nullable=False)
    is_estimate = db.Column(Boolean, nullable=False, default=True, server_default="true")
