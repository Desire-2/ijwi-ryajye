import marshmallow as ma
from flask_jwt_extended import jwt_required

from extensions import db
from app.api.helpers import pagination_args, parse_body, paginate_response, query_params
from app.api.serializers import farmer_card, user_private
from app.errors import bad_request, forbidden, not_found
from app.models.identity import BuyerProfile, FarmerProfile, User, UserRole
from app.services.audit_service import record as audit
from app.services.security import get_current_user


def list_farmers():
    page, per_page = pagination_args()
    q = FarmerProfile.query.join(User, User.id == FarmerProfile.user_id).filter(User.is_active.is_(True))
    region = query_params().get("region")
    crop = query_params().get("crop")
    if region:
        q = q.filter(User.region == region)
    if crop:
        q = q.filter(FarmerProfile.main_crops.ilike(f"%{crop}%"))
    pg = q.order_by(FarmerProfile.completed_transactions.desc()).paginate(page=page, per_page=per_page, error_out=False)
    items = []
    for profile in pg.items:
        user = db.session.get(User, profile.user_id)
        items.append(farmer_card(user, profile))
    return {
        "items": items,
        "pagination": {"page": pg.page, "per_page": pg.per_page, "total": pg.total},
    }


@jwt_required()
def get_farmer(farmer_id):
    user = db.session.get(User, farmer_id)
    if user is None:
        raise not_found("Farmer not found")
    profile = getattr(user, "farmer_profile", None)
    card = farmer_card(user, profile)
    viewer = get_current_user()
    is_self = viewer and viewer.id == user.id
    card["story"] = profile.story if (profile and is_self) else None
    return card


class PatchMeSchema(ma.Schema):
    full_name = ma.fields.String(validate=ma.validate.Length(min=2))
    bio_region = ma.fields.String(data_key="region")
    district = ma.fields.String()
    languages = ma.fields.String()
    visibility_phone = ma.fields.Boolean()
    visibility_location_exact = ma.fields.Boolean()
    visibility_farm_details = ma.fields.Boolean()
    data_saver = ma.fields.Boolean()
    transcription_opt_in = ma.fields.Boolean()
    translation_pref = ma.fields.String(validate=ma.validate.OneOf(["en", "rw", "fr", "sw"]))
    story = ma.fields.String()
    years_experience = ma.fields.Integer()
    main_crops = ma.fields.List(ma.fields.String())
    certifications = ma.fields.List(ma.fields.String())


@jwt_required()
def patch_me():
    user = get_current_user()
    data = parse_body(PatchMeSchema)

    for field in ("full_name", "district", "languages", "visibility_phone",
                  "visibility_location_exact", "visibility_farm_details", "data_saver",
                  "transcription_opt_in", "translation_pref"):
        if field in data:
            setattr(user, field, data[field])
    if "bio_region" in data:
        user.region = data["bio_region"]

    profile = user.farmer_profile or FarmerProfile.query.filter_by(user_id=user.id).first()
    if profile is None:
        profile = FarmerProfile(user_id=user.id)
        db.session.add(profile)
    for field in ("story", "years_experience"):
        if field in data:
            setattr(profile, field, data[field])
    if "main_crops" in data:
        profile.main_crops = ",".join(data["main_crops"])
    if "certifications" in data:
        profile.certifications = ",".join(data["certifications"])

    db.session.commit()
    audit(user, "profile.updated", "user", user.id)
    return {"user": user_private(user)}, 200


@jwt_required()
def me():
    user = get_current_user()
    from app.services.reputation_service import reputation_summary

    return {"user": user_private(user), "reputation": reputation_summary(user.id)}


@jwt_required()
def export_my_data():
    user = get_current_user()
    from app.models.farm import Farm
    from app.models.marketplace import Listing

    farms = [f.to_dict() for f in Farm.query.filter_by(owner_id=user.id).all()]
    listings = [l.to_dict() for l in Listing.query.filter_by(seller_id=user.id).all()]
    return {"user": user_private(user), "farms": farms, "listings": listings}


@jwt_required()
def request_account_deletion():
    user = get_current_user()
    from app.models.admin import DeletionRequest

    existing = DeletionRequest.query.filter_by(user_id=user.id).first()
    if existing is None:
        existing = DeletionRequest(user_id=user.id)
        db.session.add(existing)
    else:
        existing.state = "REQUESTED"
    db.session.commit()
    audit(user, "account.deletion_requested", "user", user.id)
    return {"state": "REQUESTED", "note": "Financial records are retained per audit requirements; your personal data will be removed."}
