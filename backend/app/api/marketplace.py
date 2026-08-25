import marshmallow as ma
from flask import request
from flask_jwt_extended import jwt_required

from extensions import db
from app.api.helpers import pagination_args, parse_body, paginate_response, query_params
from app.api.serializers import buyer_request_json, listing_json
from app.errors import bad_request, not_found
from app.models.catalog import Product, ProductCategory, UnitOfMeasure
from app.models.identity import BuyerProfile, User
from app.models.marketplace import BuyerRequest, Inventory, Listing, ListingMedia
from app.services import inventory_service, listing_service
from app.services.audit_service import record as audit
from app.services.listing_service import price_advisor
from app.services.security import get_current_user


def list_products():
    q = Product.query.filter(Product.deleted_at.is_(None))
    category = query_params().get("category")
    search = query_params().get("q")
    if category:
        cat = ProductCategory.query.filter_by(slug=category).first()
        if cat:
            q = q.filter(Product.category_id == cat.id)
    if search:
        q = q.filter(Product.name.ilike(f"%{search}%"))
    products = q.order_by(Product.name).limit(300).all()
    return {
        "products": [
            {"id": p.id, "name": p.name, "slug": p.slug, "default_unit": p.default_unit,
             "emoji": p.emoji, "category": p.category.slug if p.category else None}
            for p in products
        ]
    }


def list_categories():
    cats = ProductCategory.query.order_by(ProductCategory.name).all()
    return {"categories": [{"id": c.id, "name": c.name, "slug": c.slug, "icon": c.icon} for c in cats]}


class CreateListingSchema(ma.Schema):
    product_id = ma.fields.String(required=True)
    title = ma.fields.String()
    description = ma.fields.String(missing="")
    listing_type = ma.fields.String(missing="FIXED_PRICE")
    quantity_value = ma.fields.Float(required=True)
    available_quantity = ma.fields.Float()
    unit_code = ma.fields.String(missing="kg")
    expected_harvest_date = ma.fields.Date()
    available_from = ma.fields.Date()
    quality_grade = ma.fields.String(missing="UNGRADED")
    production_method = ma.fields.String()
    certification = ma.fields.String(missing="")
    location_region = ma.fields.String()
    location_district = ma.fields.String()
    price_minor = ma.fields.Integer()
    currency_code = ma.fields.String()
    price_type = ma.fields.String(missing="PER_UNIT")
    negotiable = ma.fields.Boolean(missing=False)
    minimum_order_value = ma.fields.Float(missing=0)
    maximum_order_value = ma.fields.Float()
    delivery_options = ma.fields.String(missing="PICKUP,NEGOTIABLE")
    farm_id = ma.fields.String()
    cooperative_id = ma.fields.String()
    group_id = ma.fields.String()
    auction_start_at = ma.fields.DateTime()
    auction_end_at = ma.fields.DateTime()
    reserve_price_minor = ma.fields.Integer()
    min_bid_increment_minor = ma.fields.Integer()
    media = ma.fields.List(ma.fields.Dict(), missing=[])


@jwt_required()
def create_listing():
    user = get_current_user()
    data = parse_body(CreateListingSchema)
    if "currency_code" not in data:
        from flask import current_app

        data["currency_code"] = current_app.config["DEFAULT_CURRENCY"]
    listing = listing_service.create_listing(user, data)

    inventory_service.create_inventory(
        owner_id=user.id,
        product_id=data["product_id"],
        quantity_value=data["quantity_value"],
        unit_code=data.get("unit_code", "kg"),
        farm_id=data.get("farm_id"),
        batch_ref=f"listing-{listing.id[:8]}",
    )
    db.session.commit()

    from extensions import realtime

    realtime.emit("listing.created", {"listing_id": listing.id})
    return {"listing": listing_json(listing)}, 201


@jwt_required()
def my_listings():
    user = get_current_user()
    page, per_page = pagination_args()
    pg = (
        Listing.query.filter(Listing.seller_id == user.id, Listing.deleted_at.is_(None))
        .order_by(Listing.created_at.desc())
        .paginate(page=page, per_page=per_page, error_out=False)
    )
    return paginate_response(pg, lambda l: listing_json(l, user))


def list_listings():
    page, per_page = pagination_args()
    args = query_params()
    q = Listing.query.filter(Listing.state == "ACTIVE", Listing.deleted_at.is_(None))

    product = args.get("product")
    if product:
        prod = Product.query.filter(
            (Product.slug == product) | (Product.name.ilike(f"%{product}%"))
        ).first()
        if prod is None:
            return {"items": [], "pagination": {"page": page, "per_page": per_page, "total": 0}}
        q = q.filter(Listing.product_id == prod.id)

    for field in ("region", "quality_grade", "listing_type"):
        if args.get(field):
            col = getattr(Listing, f"location_{field}" if field == "region" else field)
            q = q.filter(col == args[field])

    if args.get("min_quantity"):
        try:
            q = q.filter(Listing.available_quantity >= float(args["min_quantity"]))
        except ValueError:
            raise bad_request("min_quantity must be a number")

    sort = args.get("sort", "recent")
    if sort == "price_asc":
        q = q.order_by(Listing.price_minor.asc().nullslast())
    elif sort == "price_desc":
        q = q.order_by(Listing.price_minor.desc().nullslast())
    else:
        q = q.order_by(Listing.created_at.desc())

    pg = q.paginate(page=page, per_page=per_page, error_out=False)
    items = []
    for l in pg.items:
        seller = db.session.get(User, l.seller_id)
        items.append(listing_json(l, seller))
    return paginate_response(pg, lambda l: listing_json(l, db.session.get(User, l.seller_id)))


@jwt_required()
def get_listing(listing_id):
    listing = listing_service.get_listing_or_404(listing_id)
    listing.view_count += 1
    db.session.commit()
    seller = db.session.get(User, listing.seller_id)
    data = listing_json(listing, seller)
    data["media"] = [
        {"type": m.media_type, "storage_key": m.storage_key, "caption": m.caption}
        for m in ListingMedia.query.filter_by(listing_id=listing.id).all()
    ]
    return {"listing": data}


class BuyerRequestSchema(ma.Schema):
    product_id = ma.fields.String(required=True)
    title = ma.fields.String(required=True)
    description = ma.fields.String(missing="")
    quantity_value = ma.fields.Float(required=True)
    unit_code = ma.fields.String(missing="kg")
    quality_grade = ma.fields.String(missing="UNGRADED")
    destination_region = ma.fields.String()
    destination_district = ma.fields.String()
    required_by_date = ma.fields.Date()
    budget_min_minor = ma.fields.Integer()
    budget_max_minor = ma.fields.Integer()
    currency_code = ma.fields.String()


@jwt_required()
def create_buyer_request():
    user = get_current_user()
    data = parse_body(BuyerRequestSchema)
    if "currency_code" not in data:
        from flask import current_app

        data["currency_code"] = current_app.config["DEFAULT_CURRENCY"]
    br = BuyerRequest(buyer_id=user.id, state="OPEN", **data)
    db.session.add(br)
    db.session.commit()
    audit(user, "buyer_request.created", "buyer_request", br.id)
    return {"request": buyer_request_json(br)}, 201


def list_buyer_requests():
    page, per_page = pagination_args()
    pg = BuyerRequest.query.filter(BuyerRequest.state.in_(["OPEN", "MATCHING"])) \
        .order_by(BuyerRequest.created_at.desc()) \
        .paginate(page=page, per_page=per_page, error_out=False)
    return paginate_response(pg, buyer_request_json)


@jwt_required()
def request_matches(request_id):
    user = get_current_user()
    br = db.session.get(BuyerRequest, request_id)
    if br is None:
        raise not_found("Buyer request not found")
    if br.buyer_id != user.id and "ADMIN" not in user.role_codes():
        raise bad_request("Only the requester can view matches")
    from app.services.matching_engine import match_request_to_listings

    matches = match_request_to_listings(br)
    return {"matches": matches}


@jwt_required()
def listing_price_advisor(listing_id=None):
    user = get_current_user()
    body = request.get_json(silent=True) or {}
    product_id = body.get("product_id")
    region = body.get("region") or user.region
    price_minor = int(body.get("price_minor", 0))
    if not product_id or not region:
        raise bad_request("product_id and region are required")
    advice = price_advisor(product_id, region, price_minor,
                           body.get("unit_code", "kg"), body.get("currency_code", "RWF"))
    return {"advisor": advice}


class UpdateListingSchema(ma.Schema):
    title = ma.fields.String()
    description = ma.fields.String()
    variety = ma.fields.String()
    quality_grade = ma.fields.String(missing="", allow_none=True)
    certification = ma.fields.String(missing="", allow_none=True)
    delivery_options = ma.fields.List(ma.fields.String())
    negotiable = ma.fields.Boolean()
    minimum_order_value = ma.fields.Float(allow_none=True)
    maximum_order_value = ma.fields.Float(allow_none=True)
    state = ma.fields.String(validate=ma.validate.OneOf(["ACTIVE", "PAUSED", "CLOSED"]))


@jwt_required()
def patch_listing(listing_id):
    user = get_current_user()
    data = parse_body(UpdateListingSchema)
    listing = listing_service.update_listing(user, listing_id, data)
    db.session.commit()
    return {"listing": listing_json(listing)}


@jwt_required()
def close_listing(listing_id):
    user = get_current_user()
    listing = listing_service.update_listing(user, listing_id, {"state": "CLOSED"})
    db.session.commit()
    return {"listing": listing_json(listing)}
