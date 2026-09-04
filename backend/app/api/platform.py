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
                .filter(User.full_name.ilike(f"%{q}%"), User.deleted_at.is_(None))
                .order_by(User.created_at.desc()).limit(15).all())
        results["farmers"] = [{"id": u.id, "full_name": u.full_name} for u in rows]
    if scope in ("all", "groups"):
        from app.models.group import Group

        rows = Group.query.filter(Group.name.ilike(f"%{q}%"), Group.deleted_at.is_(None)).limit(15).all()
        results["groups"] = [{"id": g.id, "name": g.name, "member_count": g.member_count} for g in rows]
    results["query"] = q
    return results


FAVORITE_SUBJECT_TYPES = ("listing", "farmer", "buyer_request")


@jwt_required()
def add_favorite():
    user = get_current_user()
    data = parse_body(type("S", (ma.Schema,), {
        "listing_id": ma.fields.String(required=True),
        "subject_type": ma.fields.String(missing="listing"),
        "subject_id": ma.fields.String()})())
    subject_type = data["subject_type"]
    if subject_type not in FAVORITE_SUBJECT_TYPES:
        raise bad_request("subject_type must be one of " + ",".join(FAVORITE_SUBJECT_TYPES))
    # Backwards compatible: favourites keyed by subject; when only listing_id is
    # sent we store it as a listing favourite.
    subject_id = data.get("subject_id") or data["listing_id"]
    if subject_type == "listing":
        listing = db.session.get(Listing, subject_id)
        if listing is None or listing.deleted_at is not None:
            raise not_found("Listing not found")
    existing = Favorite.query.filter_by(
        user_id=user.id, subject_type=subject_type, subject_id=subject_id).first()
    if existing is None:
        db.session.add(Favorite(user_id=user.id, subject_type=subject_type, subject_id=subject_id))
        db.session.commit()
    return {"favorited": True, "subject_type": subject_type, "subject_id": subject_id}


@jwt_required()
def remove_favorite(listing_id):
    user = get_current_user()
    fav = Favorite.query.filter_by(user_id=user.id, subject_type="listing", subject_id=listing_id).first()
    if fav is not None:
        db.session.delete(fav)
        db.session.commit()
    # Also drop any other subject favourites pointing at the same id.
    for other in Favorite.query.filter_by(user_id=user.id, subject_id=listing_id).all():
        db.session.delete(other)
        db.session.commit()
    return {"favorited": False}


@jwt_required()
def list_favorites():
    user = get_current_user()
    favs = Favorite.query.filter_by(user_id=user.id, subject_type="listing").order_by(
        Favorite.created_at.desc()).limit(100).all()
    out = []
    for f in favs:
        l = db.session.get(Listing, f.subject_id)
        if l is not None and l.deleted_at is None and l.state == "ACTIVE":
            seller = db.session.get(User, l.seller_id)
            out.append(listing_json(l, seller))
    return {"favorites": out}


class SavedSearchSchema(ma.Schema):
    name = ma.fields.String(missing="")
    label = ma.fields.String(missing="")
    query_json = ma.fields.Dict(required=True)
    notify = ma.fields.Boolean(missing=True)


@jwt_required()
def create_saved_search():
    import json

    user = get_current_user()
    data = parse_body(SavedSearchSchema)
    label = data.get("name") or data.get("label") or "Search"
    notify = bool(data.get("notify", True))
    ss = SavedSearch(user_id=user.id, label=label,
                     query_json=json.dumps(data["query_json"]),
                     notify_on_new_matches=notify)
    db.session.add(ss)
    db.session.commit()
    return {"saved_search": {"id": ss.id, "label": ss.label, "notify": ss.notify_on_new_matches}}, 201


@jwt_required()
def list_saved_searches():
    import json

    user = get_current_user()
    rows = SavedSearch.query.filter_by(user_id=user.id).all()
    out = []
    for s in rows:
        try:
            query = json.loads(s.query_json) if s.query_json else {}
        except (ValueError, TypeError):
            query = {}
        out.append({"id": s.id, "label": s.label, "query": query,
                    "notify": s.notify_on_new_matches,
                    "created_at": s.created_at.isoformat()})
    return {"saved_searches": out}


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
