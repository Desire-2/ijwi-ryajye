import marshmallow as ma
from flask import request
from flask_jwt_extended import jwt_required

from extensions import db
from datetime import date

from app.api.helpers import parse_body
from app.errors import bad_request, forbidden, not_found
from app.models.catalog import Product
from app.models.farm import BusinessRecord, ExpenseRecord, Farm, FarmCrop, Livestock, ProductionPlan, ProductionRecord
from app.services.audit_service import record as audit
from app.services.security import get_current_user


class FarmSchema(ma.Schema):
    name = ma.fields.String(required=True, validate=ma.validate.Length(min=2))
    country_code = ma.fields.String(missing="RW")
    region = ma.fields.String()
    district = ma.fields.String()
    approx_lat = ma.fields.Float(validate=ma.validate.Range(-90, 90))
    approx_lng = ma.fields.Float(validate=ma.validate.Range(-180, 180))
    area_value = ma.fields.Float()
    area_unit = ma.fields.String(missing="ha")
    soil_type = ma.fields.String()
    irrigation = ma.fields.String()
    farming_method = ma.fields.String(missing="conventional")
    certification = ma.fields.String(missing="")
    capacity_notes = ma.fields.String(missing="")


def _owned_farm(user, farm_id):
    farm = db.session.get(Farm, farm_id)
    if farm is None or farm.is_deleted:
        raise not_found("Farm not found")
    if farm.owner_id != user.id and "ADMIN" not in user.role_codes():
        raise forbidden("You do not own this farm")
    return farm


@jwt_required()
def create_farm():
    user = get_current_user()
    data = parse_body(FarmSchema)
    farm = Farm(owner_id=user.id, **data)
    db.session.add(farm)
    db.session.flush()
    profile = user.farmer_profile or FarmerProfileFor(user)
    profile.farm_count += 1
    db.session.commit()
    audit(user, "farm.created", "farm", farm.id)
    return {"farm": farm.to_dict()}, 201


def FarmerProfileFor(user):
    from app.models.identity import FarmerProfile

    p = user.farmer_profile or FarmerProfile.query.filter_by(user_id=user.id).first()
    if p is None:
        p = FarmerProfile(user_id=user.id)
        db.session.add(p)
        db.session.flush()
    return p


@jwt_required()
def list_farms():
    user = get_current_user()
    farms = Farm.query.filter_by(owner_id=user.id, deleted_at=None).all()
    return {"farms": [f.to_dict() for f in farms]}


@jwt_required()
def get_farm(farm_id):
    user = get_current_user()
    farm = _owned_farm(user, farm_id)
    return {
        "farm": {
            **farm.to_dict(),
            "crops": [c.to_dict() for c in farm.crops],
            "livestock": [l.to_dict() for l in farm.livestock],
        }
    }


@jwt_required()
def patch_farm(farm_id):
    user = get_current_user()
    farm = _owned_farm(user, farm_id)
    body = request.get_json(silent=True) or {}
    allowed = {"name", "region", "district", "area_value", "area_unit", "soil_type",
               "irrigation", "farming_method", "certification", "capacity_notes"}
    applied = [k for k, v in body.items() if k in allowed]
    for k in applied:
        setattr(farm, k, body[k])
    db.session.commit()
    audit(user, "farm.updated", "farm", farm.id, {"fields": applied})
    return {"farm": farm.to_dict()}


@jwt_required()
def delete_farm(farm_id):
    from datetime import datetime, timezone

    user = get_current_user()
    farm = _owned_farm(user, farm_id)
    farm.deleted_at = datetime.now(timezone.utc)
    profile = FarmerProfileFor(user)
    profile.farm_count = max(0, profile.farm_count - 1)
    db.session.commit()
    audit(user, "farm.deleted", "farm", farm.id)
    return {"deleted": True}


class CropSchema(ma.Schema):
    product_id = ma.fields.String(required=True)
    variety = ma.fields.String(missing="")
    area_value = ma.fields.Float()
    area_unit = ma.fields.String(missing="ha")
    planting_date = ma.fields.Date()
    expected_harvest_date = ma.fields.Date()
    expected_quantity_value = ma.fields.Float()
    expected_quantity_unit = ma.fields.String(missing="kg")
    production_cost_minor = ma.fields.Integer(missing=0)
    currency_code = ma.fields.String(missing="RWF")
    state = ma.fields.String(missing="PLANNED")


@jwt_required()
def add_crop(farm_id):
    user = get_current_user()
    farm = _owned_farm(user, farm_id)
    data = parse_body(CropSchema)
    product = db.session.get(Product, data["product_id"])
    if product is None:
        raise not_found("Product not found")
    crop = FarmCrop(farm_id=farm.id, **data)
    db.session.add(crop)
    db.session.commit()
    audit(user, "farm.crop_added", "farm_crop", crop.id)
    return {"crop": crop.to_dict()}, 201


class LivestockSchema(ma.Schema):
    product_id = ma.fields.String(required=True)
    breed = ma.fields.String(missing="")
    head_count = ma.fields.Integer(required=True, validate=ma.validate.Range(min=0))
    avg_age_months = ma.fields.Integer()
    purpose = ma.fields.String(missing="meat")
    notes = ma.fields.String(missing="")


@jwt_required()
def add_livestock(farm_id):
    user = get_current_user()
    farm = _owned_farm(user, farm_id)
    data = parse_body(LivestockSchema)
    livestock = Livestock(farm_id=farm.id, **data)
    db.session.add(livestock)
    db.session.commit()
    return {"livestock": livestock.to_dict()}, 201


class ProductionRecordSchema(ma.Schema):
    event_type = ma.fields.String(required=True, validate=ma.validate.OneOf(
        ["PLANTED", "GROWING", "READY", "HARVESTED", "FAILED"]))
    occurred_on = ma.fields.Date()
    quantity_value = ma.fields.Float()
    quantity_unit = ma.fields.String(missing="kg")
    cost_minor = ma.fields.Integer(missing=0)
    farm_crop_id = ma.fields.String()
    livestock_id = ma.fields.String()


@jwt_required()
def record_production(farm_id):
    user = get_current_user()
    farm = _owned_farm(user, farm_id)
    data = parse_body(ProductionRecordSchema)
    rec = ProductionRecord(
        farm_id=farm.id,
        farm_crop_id=data.get("farm_crop_id"),
        livestock_id=data.get("livestock_id"),
        event_type=data["event_type"],
        occurred_on=data.get("occurred_on") or date.today(),
        quantity_value=data.get("quantity_value"),
        quantity_unit=data.get("quantity_unit", "kg"),
        cost_minor=data.get("cost_minor", 0),
    )
    db.session.add(rec)

    if data.get("farm_crop_id"):
        crop = db.session.get(FarmCrop, data["farm_crop_id"])
        if crop and crop.farm_id == farm.id:
            crop.state = data["event_type"]
    db.session.commit()
    return {"record": rec.to_dict()}, 201


class ExpenseSchema(ma.Schema):
    category = ma.fields.String(required=True)
    amount_minor = ma.fields.Integer(required=True, validate=ma.validate.Range(min=0))
    currency_code = ma.fields.String(missing="RWF")
    incurred_on = ma.fields.Date()
    note = ma.fields.String(missing="")


@jwt_required()
def record_expense(farm_id):
    user = get_current_user()
    farm = _owned_farm(user, farm_id)
    data = parse_body(ExpenseSchema)
    exp = ExpenseRecord(farm_id=farm.id, **data)
    db.session.add(exp)
    db.session.commit()
    return {"expense": exp.to_dict()}, 201


class PlanSchema(ma.Schema):
    crop_product_id = ma.fields.String(required=True)
    planting_date = ma.fields.Date()
    expected_harvest_date = ma.fields.Date()
    expected_quantity_value = ma.fields.Float(required=True)
    expected_quantity_unit = ma.fields.String(missing="kg")
    production_cost_minor = ma.fields.Integer(missing=0)
    expected_price_minor = ma.fields.Integer(missing=0)
    currency_code = ma.fields.String(missing="RWF")
    farm_crop_id = ma.fields.String()


@jwt_required()
def create_plan():
    user = get_current_user()
    data = parse_body(PlanSchema)
    qty = float(data["expected_quantity_value"])
    cost = int(data.get("production_cost_minor", 0))
    price = int(data.get("expected_price_minor", 0))

    plan = ProductionPlan(user_id=user.id, **data)
    revenue_est = int(qty * price)
    margin_est = revenue_est - cost

    db.session.add(plan)
    db.session.commit()

    return {
        "plan": plan.to_dict(),
        "projection": {
            "expected_revenue_minor": revenue_est,
            "expected_cost_minor": cost,
            "expected_margin_minor": margin_est,
            "disclaimer": "ESTIMATE ONLY — projections are not guaranteed income.",
        },
    }, 201


@jwt_required()
def business_records():
    user = get_current_user()
    rtype = request.args.get("type")
    q = BusinessRecord.query.filter_by(user_id=user.id)
    if rtype:
        q = q.filter_by(record_type=rtype.upper())
    rows = q.order_by(BusinessRecord.occurred_on.desc()).limit(200).all()
    totals = {}
    for r in rows:
        key = (r.record_type, r.currency_code)
        totals[key] = totals.get(key, 0) + r.amount_minor
    return {
        "records": [r.to_dict() for r in rows],
        "totals": [{"type": t[0], "currency": t[1], "total_minor": v} for t, v in totals.items()],
        "note": "Business records are separate from your platform wallet ledger.",
    }


class BusinessRecordSchema(ma.Schema):
    record_type = ma.fields.String(required=True, validate=ma.validate.OneOf(
        ["SALE", "EXPENSE", "LOAN", "LOAN_REPAYMENT", "INPUT_PURCHASE"]))
    counterparty_name = ma.fields.String()
    amount_minor = ma.fields.Integer(required=True)
    currency_code = ma.fields.String(missing="RWF")
    occurred_on = ma.fields.Date()
    reference = ma.fields.String(missing="")
    note = ma.fields.String(missing="")


@jwt_required()
def add_business_record():
    user = get_current_user()
    data = parse_body(BusinessRecordSchema)
    rec = BusinessRecord(user_id=user.id, **data)
    db.session.add(rec)
    db.session.commit()
    return {"record": rec.to_dict()}, 201

