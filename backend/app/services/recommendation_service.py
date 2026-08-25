from extensions import db
from app.models.catalog import Product
from app.models.identity import BuyerProfile, FarmerProfile
from app.models.marketplace import Listing


def recommend_buyer_requests_for_farmer(farmer, limit=10):
    from app.services.matching_engine import opportunities_for_farmer

    return opportunities_for_farmer(farmer, limit=limit)


def recommend_suppliers_for_buyer(buyer, product_id=None, limit=10):
    q = Listing.query.filter(Listing.state == "ACTIVE", Listing.available_quantity > 0)
    if product_id:
        q = q.filter(Listing.product_id == product_id)
    listings = q.order_by(Listing.created_at.desc()).limit(200).all()

    scored = []
    seen_sellers = set()
    for l in listings:
        if l.seller_id in seen_sellers:
            continue
        seen_sellers.add(l.seller_id)
        profile = FarmerProfile.query.filter_by(user_id=l.seller_id).first()
        completed = profile.completed_transactions if profile else 0
        reasons = []
        score = 0.4
        if completed > 0:
            score += min(completed / 50.0, 0.3)
            reasons.append(f"{completed} verified transactions")
        else:
            reasons.append("New seller on the platform")
        if l.certification:
            score += 0.15
            reasons.append("Certified produce")
        if l.location_region and l.location_region == buyer.region:
            score += 0.15
            reasons.append("Same region as you")
        scored.append({
            "listing_id": l.id,
            "seller_id": l.seller_id,
            "score": round(score, 2),
            "reasons": reasons or ["Recently listed supply"],
        })
        if len(scored) >= limit:
            break
    return sorted(scored, key=lambda x: x["score"], reverse=True)


def explain_recommendation(rec_type, subject_id, reasons):
    return {
        "type": rec_type,
        "subject_id": subject_id,
        "recommended_because": reasons,
        "explainable": True,
    }
