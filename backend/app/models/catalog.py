from sqlalchemy import Boolean, Column, ForeignKey, Integer, String, Text, UniqueConstraint
from sqlalchemy.orm import relationship

from extensions import db
from app.models.base import BaseModel, SoftDeleteModel


class ProductCategory(BaseModel):
    __tablename__ = "product_categories"
    name = db.Column(db.String(120), nullable=False, unique=True)
    slug = db.Column(db.String(120), nullable=False, unique=True, index=True)
    parent_id = db.Column(db.String(32), ForeignKey("product_categories.id"), index=True)
    icon = db.Column(db.String(30), default="")
    description = db.Column(db.Text, default="")


class Product(SoftDeleteModel):
    __tablename__ = "products"
    category_id = db.Column(db.String(32), ForeignKey("product_categories.id"), nullable=False, index=True)
    name = db.Column(db.String(160), nullable=False)
    slug = db.Column(db.String(160), nullable=False, unique=True, index=True)
    default_unit = db.Column(db.String(20), default="kg", nullable=False)
    perishable = db.Column(Boolean, default=False)
    emoji = db.Column(db.String(16), default="")
    description = db.Column(db.Text, default="")

    category = relationship("ProductCategory")


class UnitOfMeasure(BaseModel):
    __tablename__ = "units_of_measure"
    code = db.Column(db.String(20), nullable=False, unique=True)
    label = db.Column(db.String(60), nullable=False)
    dimension = db.Column(db.String(20), default="mass")
    convertible_to_base_factor = db.Column(String, default=None)
