import json
from datetime import timedelta
from decimal import Decimal

from flask import current_app

from extensions import db
from app.errors import bad_request, forbidden, not_found
from app.models.base import utcnow
from app.models.catalog import Product
from app.models.intelligence import MarketPrice
from app.models.marketplace import Listing, ListingMedia
from app.services.audit_service import record as audit

LISTING_TYPES = ("FIXED_PRICE", "NEGOTIABLE", "AUCTION", "FORWARD_CONTRACT", "GROUP_SALE")


def _normalize_attributes(payload):
    """Validate + serialize the flexible per-category attributes dict."""
    attrs = payload.get("attributes")
    if attrs is None:
        return None
    if not isinstance(attrs, dict):
        raise bad_request("attributes must be an object", "INVALID_ATTRIBUTE")
    cleaned = {}
    for key, value in attrs.items():
        if not isinstance(key, str) or not key.strip():
            continue
        if isinstance(value, (dict, list)):
            raise bad_request("Attribute values must be simple values", "INVALID_ATTRIBUTE")
        cleaned[key.strip()] = value
    return json.dumps(cleaned, ensure_ascii=False) if cleaned else None


def _validate_commercial(listing_type, price_minor, payload):
    """Pricing rules that apply once a listing goes live (create ACTIVE / publish)."""
    if listing_type == "AUCTION":
        if not payload.get("auction_end_at"):
            raise bad_request("Auction listings require auction_end_at")
    elif price_minor is None:
        raise bad_request("price is required for this listing type")
    if price_minor is not None and int(price_minor) < 0:
        raise bad_request("Price cannot be negative")
    if listing_type in ("FIXED_PRICE", "FORWARD_CONTRACT", "GROUP_SALE") and price_minor is not None and price_minor == 0:
        raise bad_request("Price must be greater than zero for fixed-price sales")


def create_listing(seller, payload):
    from app.utils.money import validate_positive_quantity

    product = db.session.get(Product, payload["product_id"])
    if product is None or product.is_deleted:
        raise not_found("Product not found")

    listing_type = payload.get("listing_type", "FIXED_PRICE")
    if listing_type not in LISTING_TYPES:
        raise bad_request("Invalid listing type")
    state = payload.get("state", "ACTIVE")
    if state not in ("DRAFT", "ACTIVE"):
        raise bad_request("state must be DRAFT or ACTIVE")

    quantity = validate_positive_quantity(payload["quantity_value"])
    available = Decimal(str(payload.get("available_quantity") or quantity))
    if available <= 0 or available > quantity:
        raise bad_request("available_quantity must be between 0 and total quantity")

    price_minor = payload.get("price_minor")
    currency = payload.get("currency_code", current_app.config["DEFAULT_CURRENCY"])
    if state == "ACTIVE":
        _validate_commercial(listing_type, price_minor, payload)

    price_type = payload.get("price_type", "PER_UNIT")
    if price_type not in ("PER_UNIT", "TOTAL", "NEGOTIABLE"):
        raise bad_request("Invalid price type")
    # A draft may legitimately have no price yet; the schema then records it as
    # "price on request" until the seller sets one before publishing.
    if state == "DRAFT" and price_minor is None and listing_type != "AUCTION":
        price_type = "NEGOTIABLE"

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
        state=state,
        quantity_value=quantity,
        available_quantity=available,
        unit_code=payload.get("unit_code", "kg"),
        expected_harvest_date=payload.get("expected_harvest_date"),
        available_from=payload.get("available_from"),
        quality_grade=payload.get("quality_grade", "UNGRADED"),
        production_method=payload.get("production_method"),
        certification=payload.get("certification", ""),
        attributes_json=_normalize_attributes(payload),
        location_region=payload.get("location_region") or seller.region,
        location_district=payload.get("location_district") or seller.district,
        price_minor=int(price_minor) if price_minor is not None else None,
        currency_code=currency,
        price_type=price_type,
        negotiable=bool(payload.get("negotiable", False)),
        minimum_order_value=Decimal(str(payload.get("minimum_order_value", 0))),
        maximum_order_value=Decimal(str(payload["maximum_order_value"])) if payload.get("maximum_order_value") else None,
        delivery_options=payload.get("delivery_options", "PICKUP,NEGOTIABLE"),
    )

    if listing_type == "AUCTION":
        listing.auction_start_at = payload.get("auction_start_at") or utcnow()
        listing.auction_end_at = payload.get("auction_end_at")
        listing.reserve_price_minor = payload.get("reserve_price_minor")
        listing.min_bid_increment_minor = int(payload.get("min_bid_increment_minor", 100))

    # Only live listings expire; a draft stays editable until the seller publishes.
    if state == "ACTIVE":
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

    audit(seller, "listing.created", "listing", listing.id,
          {"product": product.slug, "state": state})
    return listing


def add_listing_media(user, listing_id, media_items):
    """Attach already-uploaded media to a listing the user owns."""
    listing = get_listing_or_404(listing_id)
    if listing.seller_id != user.id and "ADMIN" not in user.role_codes():
        raise forbidden("You can only add media to your own listings.")
    if not media_items:
        return 0
    existing = ListingMedia.query.filter_by(listing_id=listing.id).count()
    for i, media in enumerate(media_items):
        storage_key = media.get("storage_key") if isinstance(media, dict) else None
        if not storage_key:
            raise bad_request("Each media item needs a storage_key")
        db.session.add(ListingMedia(
            listing_id=listing.id,
            media_type=media.get("type", "image"),
            storage_key=storage_key,
            position=existing + i,
            caption=media.get("caption", ""),
        ))
    db.session.flush()
    return len(media_items)


def publish_listing(user, listing_id):
    """Transition a seller's draft to ACTIVE, enforcing the live-commercial rules.

    Inventory is created by the caller (route) once per listing batch, so this
    function stays a pure state transition.
    """
    listing = _lock_listing_row(listing_id)
    if listing.seller_id != user.id and "ADMIN" not in user.role_codes():
        raise forbidden("You can only publish your own listings.")
    if listing.state == "ACTIVE":
        return listing
    if listing.state != "DRAFT":
        raise bad_request(f"Cannot publish a {listing.state.lower()} listing")

    _validate_commercial(listing.listing_type, listing.price_minor,
                         {"auction_end_at": listing.auction_end_at})
    if listing.price_minor is not None and listing.price_type == "NEGOTIABLE":
        listing.price_type = "PER_UNIT"

    listing.state = "ACTIVE"
    ttl_hours = current_app.config.get("LISTING_TTL_HOURS", 720)
    listing.expires_at = utcnow() + timedelta(hours=ttl_hours)
    db.session.flush()
    audit(user, "listing.published", "listing", listing.id,
          {"product": listing.product.slug})
    return listing


def update_listing(user, listing_id, patch):
    listing = get_listing_or_404(listing_id)
    if listing.seller_id != user.id and "ADMIN" not in user.role_codes():
        raise forbidden("You can only edit your own listings.")
    if listing.state == "DRAFT":
        return _update_draft(listing, patch, user)
    _apply_live_restricted(listing, patch, user)
    return listing


def _lock_listing_row(listing_id):
    """Serialize concurrent publishers on the same listing row."""
    if db.engine.dialect.name != "sqlite":
        db.session.execute(
            db.text("SELECT id FROM listings WHERE id = :id FOR UPDATE"),
            {"id": listing_id},
        )
    return get_listing_or_404(listing_id)


def _apply_delivery(value):
    if isinstance(value, (list, tuple)):
        return ",".join(str(v).strip() for v in value if str(v).strip())
    return value


def _apply_live_restricted(listing, patch, user):
    """Live (non-draft) listings accept only presentation/availability edits."""
    allowed = {
        "description", "variety", "title", "quality_grade", "certification",
        "delivery_options", "negotiable", "minimum_order_value", "maximum_order_value",
        "expected_harvest_date", "available_from", "production_method",
    }
    for key, value in patch.items():
        if key in allowed:
            setattr(listing, key, _apply_delivery(value) if key == "delivery_options" else value)
    if "attributes" in patch:
        listing.attributes_json = _normalize_attributes({"attributes": patch["attributes"]})
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


def _update_draft(listing, patch, user):
    """Drafts are freely editable until published — every creation field applies."""
    from app.utils.money import validate_positive_quantity

    if patch.get("state") == "ACTIVE":
        raise bad_request("Use the publish endpoint to activate a draft listing")

    direct = {
        "product_id", "title", "description", "variety", "listing_type",
        "unit_code", "expected_harvest_date", "available_from", "quality_grade",
        "production_method", "certification", "location_region", "location_district",
        "currency_code", "price_type", "negotiable", "farm_id",
        "auction_start_at", "auction_end_at", "reserve_price_minor",
        "min_bid_increment_minor",
    }
    for key in direct:
        if key in patch:
            setattr(listing, key, patch[key])
    if "delivery_options" in patch:
        listing.delivery_options = _apply_delivery(patch["delivery_options"])
    if "quantity_value" in patch or "available_quantity" in patch:
        qty = validate_positive_quantity(patch.get("quantity_value", listing.quantity_value))
        listing.quantity_value = qty
        avail = Decimal(str(patch.get("available_quantity", listing.available_quantity)))
        if avail <= 0 or avail > listing.quantity_value:
            raise bad_request("available_quantity must be between 0 and total quantity")
        listing.available_quantity = avail
    if "minimum_order_value" in patch:
        listing.minimum_order_value = Decimal(str(patch["minimum_order_value"] or 0))
    if "maximum_order_value" in patch:
        listing.maximum_order_value = (
            Decimal(str(patch["maximum_order_value"])) if patch["maximum_order_value"] else None)
    if "price_minor" in patch:
        pm = patch["price_minor"]
        if pm is not None and int(pm) < 0:
            raise bad_request("Price cannot be negative")
        listing.price_minor = int(pm) if pm is not None else None
    if "attributes" in patch:
        listing.attributes_json = _normalize_attributes({"attributes": patch["attributes"]})
    if listing.listing_type == "AUCTION" and not listing.auction_end_at:
        # allowed while drafting; re-validated on publish
        pass
    db.session.commit()
    audit(user, "listing.updated", "listing", listing.id,
          {"fields": list(patch.keys()), "state": listing.state})
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
