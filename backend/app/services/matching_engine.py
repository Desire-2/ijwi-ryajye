from datetime import date

from extensions import db
from app.errors import not_found
from app.models.farm import Farm
from app.models.identity import FarmerProfile, Verification
from app.models.marketplace import BuyerRequest, Listing
from app.models.order import Review

DEFAULT_WEIGHTS = {
    "product": 0.30,
    "quantity": 0.20,
    "quality": 0.10,
    "location": 0.15,
    "harvest_date": 0.05,
    "price": 0.10,
    "certification": 0.05,
    "reliability": 0.05,
}


def _score_component(weight_key):
    return DEFAULT_WEIGHTS[weight_key]


def match_request_to_listings(buyer_request, limit=20):
    weights = dict(DEFAULT_WEIGHTS)
    candidates = Listing.query.filter(
        Listing.state == "ACTIVE",
        Listing.available_quantity > 0,
        Listing.product_id == buyer_request.product_id,
    ).limit(500).all()

    scored = []
    for listing in candidates:
        breakdown = score_listing_for_request(listing, buyer_request, weights)
        if breakdown["total"] <= 0:
            continue
        scored.append((breakdown["total"], listing, breakdown))
    scored.sort(key=lambda t: t[0], reverse=True)
    results = []
    for total, listing, breakdown in scored[:limit]:
        results.append(
            {
                "listing_id": listing.id,
                "seller_id": listing.seller_id,
                "match_score": round(total * 100),
                "components": {k: round(v * 100) for k, v in breakdown["components"].items()},
                "reasons": breakdown["reasons"],
            }
        )
    return results


def score_listing_for_request(listing, request_, weights=None):
    weights = weights or DEFAULT_WEIGHTS
    components = {}
    reasons = []

    components["product"] = 1.0
    reasons.append("Product matches your request exactly.")

    req_qty = float(request_.quantity_value)
    avail = float(listing.available_quantity)
    ratio = min(avail / req_qty, 1.0)
    components["quantity"] = ratio
    if ratio >= 1:
        reasons.append(f"Can supply the full requested quantity ({req_qty:g} {request_.unit_code}).")
    else:
        reasons.append(f"Can supply part of your quantity ({avail:g} of {req_qty:g} {request_.unit_code}).")

    components["quality"] = 1.0 if (request_.quality_grade == "UNGRADED" or listing.quality_grade == request_.quality_grade) else 0.4
    if components["quality"] == 1.0:
        reasons.append(f"Quality grade {listing.quality_grade} meets your requirement.")

    same_region = (
        listing.location_region
        and request_.destination_region
        and listing.location_region == request_.destination_region
    )
    components["location"] = 1.0 if same_region else 0.6
    reasons.append(
        "Located in your destination region." if same_region else "Located outside your destination region; transport may be needed."
    )

    if request_.required_by_date and listing.expected_harvest_date:
        ok = listing.expected_harvest_date <= request_.required_by_date
        components["harvest_date"] = 1.0 if ok else 0.2
        if ok:
            reasons.append("Harvest is ready before your required-by date.")
        else:
            reasons.append("Harvest may arrive after your required-by date.")
    else:
        components["harvest_date"] = 0.7

    budget_max = request_.budget_max_minor or request_.budget_min_minor
    price = listing.price_minor
    if budget_max and price:
        unit_price = price
        within = unit_price <= int(budget_max)
        components["price"] = 1.0 if within else 0.3
        reasons.append(
            "Price is within your budget." if within else "Asking price is above your stated budget."
        )
    else:
        components["price"] = 0.7

    cert_ok = bool(listing.certification)
    components["certification"] = 1.0 if cert_ok else 0.5
    if cert_ok:
        reasons.append("Listing includes a certification.")

    profile = FarmerProfile.query.filter_by(user_id=listing.seller_id).first()
    completed = profile.completed_transactions if profile else 0
    reliability = min(completed / 25.0, 1.0)
    components["reliability"] = reliability
    if completed >= 5:
        reasons.append(f"Seller has {completed} completed transactions on Ijwi Ryajye.")
    else:
        reasons.append("Seller is new to the platform; reputation will build over time.")

    total = sum(components.get(k, 0) * weights[k] for k in weights)
    return {"total": total, "components": components, "reasons": reasons}


def opportunities_for_farmer(farmer_user, limit=20):
    farmer_listings = Listing.query.filter(
        Listing.seller_id == farmer_user.id, Listing.state == "ACTIVE"
    ).all()
    product_ids = {l.product_id for l in farmer_listings}
    from app.models.catalog import Product

    crops = db.session.query(FarmCrop_product_id_by_farmer(farmer_user.id)).all()
    for pid in crops:
        product_ids.add(pid[0])

    open_requests = (
        BuyerRequest.query.filter(BuyerRequest.state.in_(["OPEN", "MATCHING"]))
        .order_by(BuyerRequest.created_at.desc())
        .limit(200)
        .all()
    )
    out = []
    for br in open_requests:
        if br.buyer_id == farmer_user.id:
            continue
        direct = br.product_id in product_ids
        if not direct and len(out) >= limit:
            continue
        matched_qty = None
        for l in farmer_listings:
            if l.product_id == br.product_id:
                matched_qty = float(l.available_quantity)
                break
        out.append(
            {
                "buyer_request_id": br.id,
                "title": br.title,
                "product_id": br.product_id,
                "quantity": float(br.quantity_value),
                "unit_code": br.unit_code,
                "budget_range_minor": [br.budget_min_minor, br.budget_max_minor],
                "currency_code": br.currency_code,
                "destination_region": br.destination_region,
                "required_by_date": str(br.required_by_date) if br.required_by_date else None,
                "you_qualify": direct,
                "your_available_quantity": matched_qty,
                "why": [
                    "You have an active listing for this product."
                    if direct
                    else "Buyers near you are requesting this product."
                ],
            }
        )
        if len(out) >= limit:
            break
    return out


def FarmCrop_product_id_by_farmer(user_id):
    from sqlalchemy import select
    from app.models.farm import FarmCrop

    return select(FarmCrop.product_id).join(Farm, FarmCrop.farm_id == Farm.id).where(Farm.owner_id == user_id)
