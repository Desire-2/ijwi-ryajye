"""Public catalogue: listing-flow product creation.

Lets any authenticated seller add a new product to the catalogue during
listing creation.  The endpoint is *not* admin-only: every JWT user may
contribute a product (slug-uniqueness is enforced), which keeps the
marketplace catalogue growing organically while preventing duplicates.
"""
import re

import marshmallow as ma
from flask_jwt_extended import jwt_required

from extensions import db
from app.api.helpers import parse_body
from app.errors import bad_request, not_found
from app.models.catalog import Product, ProductCategory
from app.services import audit_service
from app.services.security import get_current_user


def _slugify(name):
    slug = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")
    if not slug:
        raise bad_request("Could not build a slug from that name.")
    return slug


class CreateCatalogProductSchema(ma.Schema):
    name = ma.fields.String(required=True, validate=ma.validate.Length(min=2, max=160))
    category_id = ma.fields.String()
    category_slug = ma.fields.String()
    default_unit = ma.fields.String(missing="kg")
    emoji = ma.fields.String(missing="")


def _product_json(p):
    cat = p.category
    return {
        "id": p.id, "name": p.name, "slug": p.slug,
        "emoji": p.emoji or (cat.icon if cat else "") or "🌾",
        "default_unit": p.default_unit,
        "category": (
            {"id": cat.id, "name": cat.name, "slug": cat.slug, "icon": cat.icon}
            if cat else None
        ),
    }


@jwt_required()
def create_listing_product():
    """Find-or-create a catalog product for the listing wizard.

    Returns the existing product (200) when a product with the same slug
    already exists and is not soft-deleted, or creates a new one (201).
    """
    user = get_current_user()
    data = parse_body(CreateCatalogProductSchema)

    # Resolve category
    cat = None
    if data.get("category_id"):
        cat = db.session.get(ProductCategory, data["category_id"])
    elif data.get("category_slug"):
        cat = ProductCategory.query.filter_by(slug=data["category_slug"]).first()
    if cat is None:
        raise bad_request("A valid category is required. "
                          "Please select a category first.")

    name = data["name"].strip()
    if len(name) < 2:
        raise bad_request("Product name must be at least 2 characters.")

    slug = _slugify(name)

    # Find-or-create: reuse an active product with the same slug. If a matching
    # row was soft-deleted, revive it (slugs are unique even when deleted, so a
    # fresh insert would otherwise hit the unique constraint and 500).
    existing = Product.query.filter(Product.slug == slug).first()
    if existing is not None:
        if existing.deleted_at is not None:
            existing.deleted_at = None
            existing.category_id = cat.id
        existing.name = name
        existing.default_unit = data.get("default_unit") or existing.default_unit or "kg"
        if data.get("emoji"):
            existing.emoji = data["emoji"]
        db.session.commit()
        return _product_json(existing)

    created = Product(
        name=name,
        slug=slug,
        category_id=cat.id,
        default_unit=data.get("default_unit") or "kg",
        emoji=data.get("emoji") or "",
    )
    db.session.add(created)
    db.session.flush()
    audit_service.record(
        user, "catalog.product.created_by_seller",
        "product", created.id, {"name": name, "category_slug": cat.slug},
    )
    db.session.commit()
    return _product_json(created), 201
