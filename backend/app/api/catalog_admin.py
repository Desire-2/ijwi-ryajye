"""Admin catalogue management.

Lets platform admins add and edit the marketplace catalogue (categories,
products, units) through the API — no code or DB access required. Every
mutation is audit-logged; the catalogue stays authoritative on the backend
and the Create Listing wizard renders it dynamically.
"""
import re

import marshmallow as ma
from flask_jwt_extended import jwt_required

from extensions import db
from app.api.helpers import parse_body
from app.errors import bad_request, conflict, not_found
from app.models.catalog import Product, ProductCategory, UnitOfMeasure
from app.services import audit_service
from app.services.security import get_current_user, require_admin


def _slugify(name):
    slug = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")
    if not slug:
        raise bad_request("Could not build a slug from that name.")
    return slug


# --------------------------------------------------------------- categories


class CategorySchema(ma.Schema):
    name = ma.fields.String(required=True, validate=ma.validate.Length(min=2, max=120))
    slug = ma.fields.String()
    icon = ma.fields.String(missing="")
    description = ma.fields.String(missing="")
    parent_id = ma.fields.String()


class CategoryUpdateSchema(ma.Schema):
    name = ma.fields.String(validate=ma.validate.Length(min=2, max=120))
    slug = ma.fields.String()
    icon = ma.fields.String()
    description = ma.fields.String()
    parent_id = ma.fields.String()


@jwt_required()
def create_category():
    require_admin(get_current_user())
    data = parse_body(CategorySchema)
    name = data["name"].strip()
    if ProductCategory.query.filter_by(name=name).first():
        raise conflict("A category with that name already exists.")
    slug = (data.get("slug") or _slugify(name)).strip().lower()
    if ProductCategory.query.filter_by(slug=slug).first():
        raise conflict("A category with that slug already exists.")
    parent_id = data.get("parent_id")
    if parent_id:
        if db.session.get(ProductCategory, parent_id) is None:
            raise not_found("Parent category not found")
    cat = ProductCategory(
        name=name, slug=slug, icon=data.get("icon") or "",
        description=data.get("description") or "", parent_id=parent_id)
    db.session.add(cat)
    db.session.flush()
    audit_service.record(get_current_user(), "catalog.category.created",
                         "product_category", cat.id, {"name": name})
    db.session.commit()
    return _category_json(cat), 201


@jwt_required()
def update_category(category_id):
    admin = get_current_user()
    require_admin(admin)
    cat = db.session.get(ProductCategory, category_id)
    if cat is None:
        raise not_found("Category not found")
    data = parse_body(CategoryUpdateSchema)
    if data.get("name") is not None:
        name = data["name"].strip()
        dup = ProductCategory.query.filter(
            ProductCategory.name == name, ProductCategory.id != category_id).first()
        if dup:
            raise conflict("A category with that name already exists.")
        cat.name = name
    if data.get("slug") is not None:
        slug = data["slug"].strip().lower()
        dup = ProductCategory.query.filter(
            ProductCategory.slug == slug, ProductCategory.id != category_id).first()
        if dup:
            raise conflict("A category with that slug already exists.")
        cat.slug = slug
    if data.get("icon") is not None:
        cat.icon = data["icon"]
    if data.get("description") is not None:
        cat.description = data["description"]
    if data.get("parent_id") is not None:
        if data["parent_id"] and db.session.get(ProductCategory, data["parent_id"]) is None:
            raise not_found("Parent category not found")
        cat.parent_id = data["parent_id"] or None
    audit_service.record(admin, "catalog.category.updated",
                         "product_category", category_id)
    db.session.commit()
    return _category_json(cat)


def _category_json(cat):
    return {
        "id": cat.id, "name": cat.name, "slug": cat.slug,
        "icon": cat.icon or "", "description": cat.description or "",
        "parent_id": cat.parent_id,
    }


# ----------------------------------------------------------------- products


class ProductSchema(ma.Schema):
    name = ma.fields.String(required=True, validate=ma.validate.Length(min=2, max=160))
    slug = ma.fields.String()
    category_id = ma.fields.String(required=True)
    default_unit = ma.fields.String(missing="kg")
    emoji = ma.fields.String(missing="")
    perishable = ma.fields.Boolean(missing=False)
    description = ma.fields.String(missing="")


class ProductUpdateSchema(ma.Schema):
    name = ma.fields.String(validate=ma.validate.Length(min=2, max=160))
    slug = ma.fields.String()
    category_id = ma.fields.String()
    default_unit = ma.fields.String()
    emoji = ma.fields.String()
    perishable = ma.fields.Boolean()
    description = ma.fields.String()


@jwt_required()
def create_product():
    admin = get_current_user()
    require_admin(admin)
    data = parse_body(ProductSchema)
    if db.session.get(ProductCategory, data["category_id"]) is None:
        raise not_found("Category not found")
    name = data["name"].strip()
    if Product.query.filter_by(slug=data.get("slug") or _slugify(name)).first():
        raise conflict("A product with that slug already exists.")
    slug = (data.get("slug") or _slugify(name)).strip().lower()
    product = Product(
        name=name, slug=slug, category_id=data["category_id"],
        default_unit=data.get("default_unit") or "kg",
        emoji=data.get("emoji") or "", perishable=data.get("perishable", False),
        description=data.get("description") or "")
    db.session.add(product)
    db.session.flush()
    audit_service.record(admin, "catalog.product.created", "product",
                         product.id, {"name": name, "slug": slug})
    db.session.commit()
    return _product_json(product), 201


@jwt_required()
def update_product(product_id):
    admin = get_current_user()
    require_admin(admin)
    product = db.session.get(Product, product_id)
    if product is None:
        raise not_found("Product not found")
    data = parse_body(ProductUpdateSchema)
    if data.get("name") is not None:
        product.name = data["name"].strip()
    if data.get("slug") is not None:
        slug = data["slug"].strip().lower()
        dup = Product.query.filter(
            Product.slug == slug, Product.id != product_id).first()
        if dup:
            raise conflict("A product with that slug already exists.")
        product.slug = slug
    if data.get("category_id") is not None:
        if db.session.get(ProductCategory, data["category_id"]) is None:
            raise not_found("Category not found")
        product.category_id = data["category_id"]
    if data.get("default_unit") is not None:
        product.default_unit = data["default_unit"]
    if data.get("emoji") is not None:
        product.emoji = data["emoji"]
    if data.get("perishable") is not None:
        product.perishable = data["perishable"]
    if data.get("description") is not None:
        product.description = data["description"]
    audit_service.record(admin, "catalog.product.updated", "product", product_id)
    db.session.commit()
    return _product_json(product)


def _product_json(p):
    return {
        "id": p.id, "name": p.name, "slug": p.slug,
        "category_id": p.category_id,
        "category": {"id": p.category.id, "name": p.category.name,
                     "slug": p.category.slug} if p.category else None,
        "default_unit": p.default_unit, "emoji": p.emoji or "",
        "perishable": p.perishable, "description": p.description or "",
    }


# -------------------------------------------------------------------- units


class UnitSchema(ma.Schema):
    code = ma.fields.String(required=True,
                            validate=ma.validate.Length(min=1, max=20))
    label = ma.fields.String(required=True,
                             validate=ma.validate.Length(min=2, max=60))


class UnitUpdateSchema(ma.Schema):
    label = ma.fields.String(validate=ma.validate.Length(min=2, max=60))


@jwt_required()
def create_unit():
    admin = get_current_user()
    require_admin(admin)
    data = parse_body(UnitSchema)
    code = data["code"].strip()
    if UnitOfMeasure.query.filter_by(code=code).first():
        raise conflict("A unit with that code already exists.")
    unit = UnitOfMeasure(code=code, label=data["label"].strip())
    db.session.add(unit)
    db.session.flush()
    audit_service.record(admin, "catalog.unit.created", "unit_of_measure",
                         code, {"label": unit.label})
    db.session.commit()
    return _unit_json(unit), 201


@jwt_required()
def update_unit(unit_code):
    admin = get_current_user()
    require_admin(admin)
    unit = UnitOfMeasure.query.filter_by(code=unit_code).first()
    if unit is None:
        raise not_found("Unit not found")
    data = parse_body(UnitUpdateSchema)
    if data.get("label") is not None:
        unit.label = data["label"].strip()
    audit_service.record(admin, "catalog.unit.updated", "unit_of_measure",
                         unit.code)
    db.session.commit()
    return _unit_json(unit)


def _unit_json(u):
    return {"code": u.code, "label": u.label,
            "dimension": u.dimension or "", "factor": u.convertible_to_base_factor}
