import marshmallow as ma
from flask import current_app, jsonify, request
from flask_jwt_extended import jwt_required

from extensions import db, limiter
from app.api.helpers import pagination_args, parse_body, paginate_response, query_params
from app.api.serializers import listing_json
from app.errors import bad_request, forbidden, not_found
from app.models.catalog import Product
from app.models.identity import User
from app.models.marketplace import Favorite, Listing, SavedSearch
from app.services import storage_service, sync_service
from app.services.security import get_current_user


@limiter.limit("60 per hour")
def global_search():
    q = (query_params().get("q") or "").strip()
    scope = query_params().get("scope", "all")
    if len(q) < 2:
        raise bad_request("Query must be at least 2 characters")
    results = {}
    if scope in ("all", "products"):
        rows = Product.query.filter(Product.name.ilike(f"%{q}%")).limit(15).all()
        results["products"] = [{"id": p.id, "name": p.name, "slug": p.slug} for p in rows]
    if scope in ("all", "listings"):
        pg = (Listing.query.filter(Listing.state.in_(["ACTIVE", "PENDING"]))
              .filter((Listing.title.ilike(f"%{q}%")) | (Listing.description.ilike(f"%{q}%")))
              .order_by(Listing.created_at.desc()).limit(25))
        results["listings"] = [listing_json(l) for l in pg.all()]
    if scope in ("all", "farmers"):
        from app.models.identity import FarmerProfile

        rows = (User.query.join(FarmerProfile, FarmerProfile.user_id == User.id)
                .filter(User.full_name.ilike(f"%{q}%"), User.deleted_at.is_(None),
                        FarmerProfile.is_searchable.is_(True)).limit(15).all())
        results["farmers"] = [{"id": u.id, "full_name": u.full_name} for u in rows]
    if scope in ("all", "groups"):
        from app.models.group import Group

        rows = Group.query.filter(Group.name.ilike(f"%{q}%"), Group.deleted_at.is_(None)).limit(15).all()
        results["groups"] = [{"id": g.id, "name": g.name, "member_count": g.member_count} for g in rows]
    results["query"] = q
    return results


@jwt_required()
def add_favorite():
    user = get_current_user()
    data = parse_body(type("S", (ma.Schema,), {
        "listing_id": ma.fields.String(required=True)})())
    listing = db.session.get(Listing, data["listing_id"])
    if listing is None:
        raise not_found("Listing not found")
    existing = Favorite.query.filter_by(user_id=user.id, listing_id=listing.id).first()
    if existing is None:
        db.session.add(Favorite(user_id=user.id, listing_id=listing.id))
        listing.favorite_count = (listing.favorite_count or 0) + 1
        db.session.commit()
    return {"favorited": True}


@jwt_required()
def remove_favorite(listing_id):
    user = get_current_user()
    fav = Favorite.query.filter_by(user_id=user.id, listing_id=listing_id).first()
    if fav is not None:
        db.session.delete(fav)
        listing = db.session.get(Listing, listing_id)
        if listing and listing.favorite_count:
            listing.favorite_count -= 1
        db.session.commit()
    return {"favorited": False}


@jwt_required()
def list_favorites():
    user = get_current_user()
    favs = Favorite.query.filter_by(user_id=user.id).order_by(Favorite.created_at.desc()).limit(100).all()
    out = []
    for f in favs:
        l = db.session.get(Listing, f.listing_id)
        if l is not None and l.state == "ACTIVE":
            out.append(listing_json(l))
    return {"favorites": out}


class SavedSearchSchema(ma.Schema):
    name = ma.fields.String(missing="")
    query_json = ma.fields.Dict(required=True)


@jwt_required()
def create_saved_search():
    user = get_current_user()
    data = parse_body(SavedSearchSchema)
    ss = SavedSearch(user_id=user.id, name=data.get("name") or "Search",
                     query_json=data["query_json"], notify_push=True)
    db.session.add(ss)
    db.session.commit()
    return {"saved_search": {"id": ss.id, "name": ss.name}}, 201


@jwt_required()
def list_saved_searches():
    user = get_current_user()
    rows = SavedSearch.query.filter_by(user_id=user.id).all()
    return {"saved_searches": [{"id": s.id, "name": s.name, "query": s.query_json,
                                "notify_push": s.notify_push} for s in rows]}


@jwt_required()
def delete_saved_search(search_id):
    user = get_current_user()
    ss = SavedSearch.query.filter_by(id=search_id, user_id=user.id).first()
    if ss is None:
        raise not_found("Saved search not found")
    db.session.delete(ss)
    db.session.commit()
    return {"deleted": True}


class SyncPushSchema(ma.Schema):
    operations = ma.fields.List(ma.fields.Dict(), required=True)


@jwt_required()
@limiter.limit("120 per hour")
def sync_push():
    user = get_current_user()
    data = parse_body(SyncPushSchema)
    result = sync_service.push_operations(user, data["operations"])
    db.session.commit()
    return result


@jwt_required()
def sync_pull():
    user = get_current_user()
    collections = query_params().get("collections", "").split(",")
    collections = [c.strip() for c in collections if c.strip()]
    cursors = {k: v for k, v in query_params().items() if k.endswith("_cursor")}
    result = sync_service.pull_updates(user, collections, cursors=cursors or None)
    return result


@limiter.limit("30 per minute")
def upload_file(category):
    user = get_current_user()
    file = request.files.get("file")
    if file is None:
        raise bad_request("A 'file' part is required")
    stored = storage_service.store_upload(user, file, category)
    db.session.commit()
    return stored, 201


def health():
    return jsonify({"status": "ok", "service": "ijwi-ryajye-api"})


def ready():
    checks = {}
    try:
        db.session.execute(db.text("SELECT 1"))
        checks["database"] = "ok"
    except Exception as exc:  # pragma: no cover - readiness probe
        checks["database"] = f"error: {type(exc).__name__}"
    try:
        from extensions import socketio

        checks["realtime"] = "ok"
    except Exception:
        checks["realtime"] = "error"
    status = "ok" if all(v == "ok" for v in checks.values()) else "degraded"
    return jsonify({"status": status, "checks": checks}), (200 if status == "ok" else 503)
