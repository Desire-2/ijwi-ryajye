import marshmallow as ma
from flask_jwt_extended import jwt_required

from app.api.helpers import parse_body, query_params
from app.errors import forbidden, not_found
from app.services import matching_engine, recommendation_service
from app.services.security import get_current_user


@jwt_required()
def farmer_opportunities():
    user = get_current_user()
    if not user.farmer_profile:
        raise forbidden("Farmer profile required", "FARMER_PROFILE_REQUIRED")
    limit = int(query_params().get("limit", 20))
    opportunities = matching_engine.opportunities_for_farmer(user.id, limit=limit)
    return {"opportunities": opportunities}


@jwt_required()
def buyer_request_matches(request_id):
    from extensions import db
    from app.models.marketplace import BuyerRequest

    user = get_current_user()
    req = db.session.get(BuyerRequest, request_id)
    if req is None:
        raise not_found("Buyer request not found")
    if req.buyer_id != user.id and "ADMIN" not in user.role_codes():
        raise forbidden("Only the request owner can view matches")
    listings = matching_engine.match_request_to_listings(req, limit=int(query_params().get("limit", 10)))
    return {"matches": listings}


@jwt_required()
def supplier_recommendations():
    user = get_current_user()
    data = parse_body(type("S", (ma.Schema,), {
        "product_id": ma.fields.String(),
        "region": ma.fields.String(),
    })())
    recs = recommendation_service.recommend_suppliers_for_buyer(
        user, product_id=data.get("product_id"), region=data.get("region"))
    return {"recommendations": recs}
