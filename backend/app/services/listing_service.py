from datetime import timedelta
from decimal import Decimal

from flask import current_app

from extensions import db, realtime
from app.errors import bad_request, forbidden, not_found
from app.models.base import utcnow
from app.models.catalog import Product
from app.models.intelligence import MarketPrice
from app.models.marketplace import Listing, ListingMedia
from app.services.audit_service import record as audit


def create_listing(seller, payload):
    from app.utils.money import validate_positive_quantity
    from app.models.identity import Verification

    product = db.session.get(Product, payload["product_id"])
    if product is None or product.is_deleted:
        raise not_found("Product not found")

    listing_type = payload.get("listing_type", "FIXED_PRICE")
    if listing_type not in ("FIXED_PRICE", "NEGOTIABLE", "AUCTION", "FORWARD_CONTRACT", "GROUP_SALE"):
        raise bad_request("Invalid listing type")

    quantity = validate_positive_quantity(payload["quantity_value"])
    available = Decimal(str(payload.get("available_quantity") or quantity))
    if available <= 0 or available > quantity:
        raise bad_request("available_quantity must be between 0 and total quantity")

    price_minor = payload.get("price_minor")
    currency = payload.get("currency_code", current_app.config["DEFAULT_CURRENCY"])
    if listing_type == "AUCTION":
        if not payload.get("auction_end_at"):
            raise bad_request("Auction listings require auction_end_at")
    elif price_minor is None:
        raise bad_request("price is required for this listing type")
    if price_minor is not None and int(price_minor) < 0:
        raise bad_request("Price cannot be negative")
    if listing_type in ("FIXED_PRICE", "FORWARD_CONTRACT", "GROUP_SALE") and price_minor is not None and price_minor == 0:
        raise bad_request("Price must be greater than zero for fixed-price sales")

    listing = Listing(
        seller_id=seller.id,
        farm_id=payload.get("farm_id"),
        cooperative_id=payload.get("cooperative_id"),
        group_id=payload.get("group_id"),
        product_id=product.id,
        variety=payload.get("variety", ""),
        title=payload.get("title") or f"{product.name} — {quantity} {payload.get('unit_code', 'kg')}",
        description=payload.get("description", ""),
        listing_type=listing_type,
        state="ACTIVE",
        quantity_value=quantity,
        available_quantity=available,
        unit_code=payload.get("unit_code", "kg"),
        expected_harvest_date=payload.get("expected_harvest_date"),
        available_from=payload.get("available_from"),
        quality_grade=payload.get("quality_grade", "UNGRADED"),
        production_method=payload.get("production_method"),
        certification=payload.get("certification", ""),
        location_region=payload.get("location_region") or seller.region,
        location_district=payload.get("location_district") or seller.district,
        price_minor=int(price_minor) if price_minor is not None else None,
        currency_code=currency,
        price_type=payload.get("price_type", "PER_UNIT"),
        negotiable=bool(payload.get("negotiable", False)),
        minimum_order_value=Decimal(str(payload.get("minimum_order_value", 0))),
        maximum_order_value=Decimal(str(payload["maximum_order_value"])) if payload.get("maximum_order_value") else None,
        delivery_options=payload.get("delivery_options", "PICKUP,NEGOTIABLE"),
    )

    if listing_type == "AUCTION":
        listing.auction_start_at = payload.get("auction_start_at") or utcnow()
        listing.auction_end_at = payload["auction_end_at"]
        listing.reserve_price_minor = payload.get("reserve_price_minor")
        listing.min_bid_increment_minor = int(payload.get("min_bid_increment_minor", 100))

    ttl_hours = current_app.config.get("LISTING_TTL_HOURS", 720)
    listing.expires_at = utcnow() + timedelta(hours=ttl_hours)

    db.session.add(listing)
    db.session.flush()

    for i, media in enumerate(payload.get("media", [])):
        db.session.add(
            ListingMedia(
                listing_id=listing.id,
                media_type=media.get("type", "image"),
                storage_key=media["storage_key"],
                position=i,
                caption=media.get("caption", ""),
            )
        )
    db.session.flush()

    audit(seller, "listing.created", "listing", listing.id, {"product": product.slug})
    realtime.emit("listing.created", {"id": listing.id, "product_id": product.id})
    return listing


def update_listing(user, listing_id, patch):
    listing = get_listing_or_404(listing_id)
    if listing.seller_id != user.id and "ADMIN" not in user.role_codes():
        raise forbidden("You can only edit your own listings.")
    allowed = {
        "description", "variety", "title", "quality_grade", "certification",
        "delivery_options", "negotiable", "minimum_order_value", "maximum_order_value",
        "expected_harvest_date", "available_from", "production_method",
    }
    for key, value in patch.items():
        if key in allowed:
            setattr(listing, key, value)
    if "state" in patch:
        new_state = patch["state"]
        if new_state not in ("ACTIVE", "PAUSED", "CLOSED"):
            raise bad_request("Invalid target state")
        if listing.state not in ("EXPIRED", "SOLD_OUT"):
            listing.state = new_state
        else:
            raise bad_request(f"Cannot change state of a {listing.state.lower()} listing")
    if "price_minor" in patch and patch["price_minor"] is not None:
        if listing.listing_type == "AUCTION":
            raise bad_request("Cannot change auction price; manage reserve instead")
        if int(patch["price_minor"]) < 0:
            raise bad_request("Price cannot be negative")
        listing.price_minor = int(patch["price_minor"])
    db.session.commit()
    audit(user, "listing.updated", "listing", listing.id, {"fields": list(patch.keys())})
    return listing


def get_listing_or_404(listing_id):
    listing = Listing.query.filter(Listing.id == listing_id, Listing.deleted_at.is_(None)).first()
    if listing is None:
        raise not_found("Listing not found")
    return listing


def price_advisor(product_id, region, price_minor, unit_code="kg", currency="RWF"):
    rows = (
        MarketPrice.query.filter_by(product_id=product_id, region=region)
        .order_by(MarketPrice.observed_on.desc())
        .limit(10)
        .all()
    )
    mids = [r.price_mid_minor for r in rows if r.price_mid_minor]
    lows = [r.price_low_minor for r in rows if r.price_low_minor] or mids
    highs = [r.price_high_minor for r in rows if r.price_high_minor] or mids
    result = {
        "is_estimate": True,
        "observations_counted": len(mids),
        "source_note": "Recent observed market reports" if mids else None,
        "unit_code": unit_code,
        "currency_code": currency,
        "observed_range_minor": None,
        "suggestion": None,
    }
    if not mids:
        return result
    low = min(lows + mids)
    high = max(highs + mids)
    result["observed_range_minor"] = [int(low), int(high)]
    p = int(price_minor or 0)
    if p < low:
        result["suggestion"] = "Your price is below recent observations. Consider raising it."
    elif p > high:
        result["suggestion"] = "Your price is above recent observations. It may sell slower."
    else:
        result["suggestion"] = "Your price is within the recently observed range."
    return result
