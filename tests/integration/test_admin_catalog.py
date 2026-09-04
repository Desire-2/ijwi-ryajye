"""Admin catalogue management: POST/PATCH endpoints, admin-only auth, and
the catalogue changes become visible through the public read endpoints."""
from tests.conftest import auth_headers


def _make_admin(app, user_tokens):
    from extensions import db as _db
    from app.models.identity import User, UserRole

    with app.app_context():
        me = _db.session.get(User, user_tokens["id"])
        me.roles.append(UserRole(role="ADMIN"))
        _db.session.commit()
    # Drop the (possibly ambient, identity-mapped) session so later requests
    # reload the user and its roles from the database instead of stale state.
    _db.session.remove()


def test_non_admin_cannot_manage_catalogue(client, buyer):
    r = client.post("/api/v1/admin/catalog/categories",
                    json={"name": "Snacks", "icon": "🍿"},
                    headers=auth_headers(buyer))
    assert r.status_code == 403


def test_admin_can_create_and_edit_categories_products_units(client, buyer, app):
    _make_admin(app, buyer)
    h = auth_headers(buyer)

    # Category
    cat = client.post("/api/v1/admin/catalog/categories",
                      json={"name": "Packaged Foods", "icon": "📦"},
                      headers=h)
    assert cat.status_code == 201, cat.get_json()
    cat_id = cat.get_json()["id"]
    assert client.get("/api/v1/categories").get_json()["categories"] and any(
        c["slug"] == "packaged-foods"
        for c in client.get("/api/v1/categories").get_json()["categories"])

    # Duplicate category rejected
    dup = client.post("/api/v1/admin/catalog/categories",
                      json={"name": "Packaged Foods"}, headers=h)
    assert dup.status_code == 409

    patch = client.patch(f"/api/v1/admin/catalog/categories/{cat_id}",
                         json={"name": "Packaged Food", "icon": "🥫"}, headers=h)
    assert patch.status_code == 200
    assert patch.get_json()["name"] == "Packaged Food"

    # Product inside it
    prod = client.post("/api/v1/admin/catalog/products",
                       json={"name": "Cassava Flour", "category_id": cat_id,
                             "default_unit": "bag", "emoji": "🌾"},
                       headers=h)
    assert prod.status_code == 201, prod.get_json()
    prod_id = prod.get_json()["id"]
    public_items = client.get("/api/v1/products").get_json()["items"]
    assert any(p["id"] == prod_id for p in public_items)
    matched = [p for p in public_items if p["id"] == prod_id][0]
    assert matched["category"]["slug"] == "packaged-foods"
    assert matched["default_unit"] == "bag"

    # Slug conflicts are rejected
    dup_prod = client.post("/api/v1/admin/catalog/products",
                           json={"name": "Cassava Flour 2", "slug": "cassava-flour",
                                 "category_id": cat_id}, headers=h)
    assert dup_prod.status_code == 409

    move = client.patch(f"/api/v1/admin/catalog/products/{prod_id}",
                        json={"emoji": "🌾", "perishable": False}, headers=h)
    assert move.status_code == 200

    # Units
    unit = client.post("/api/v1/admin/catalog/units",
                       json={"code": "box", "label": "Box (20kg)"}, headers=h)
    assert unit.status_code == 201, unit.get_json()
    unit_patch = client.patch("/api/v1/admin/catalog/units/box",
                              json={"label": "Box (25kg)"}, headers=h)
    assert unit_patch.status_code == 200
    assert unit_patch.get_json()["label"] == "Box (25kg)"
    units = client.get("/api/v1/units").get_json()["units"]
    assert any(u["code"] == "box" and u["label"] == "Box (25kg)" for u in units)

    # Unknown targets 404
    assert client.patch("/api/v1/admin/catalog/categories/nope",
                        json={"name": "X"}, headers=h).status_code == 404
    assert client.patch("/api/v1/admin/catalog/units/nope",
                        json={"label": "X"}, headers=h).status_code == 404


def test_products_listing_wizard_can_use_new_catalogue(client, farmer, buyer, app):
    """A new category/product/unit is immediately usable when creating a listing."""
    _make_admin(app, buyer)
    h = auth_headers(buyer)
    cat = client.post("/api/v1/admin/catalog/categories",
                      json={"name": "Storage", "icon": "🏠"}, headers=h).get_json()
    prod = client.post("/api/v1/admin/catalog/products",
                       json={"name": "Cold Room Storage", "category_id": cat["id"],
                             "default_unit": "day", "emoji": "🧊"},
                       headers=h).get_json()

    farm = client.post("/api/v1/farms", json={"name": "Admin Farm", "region": "Kigali"},
                       headers=auth_headers(farmer)).get_json()["farm"]
    listing = client.post("/api/v1/listings", json={
        "farm_id": farm["id"], "product_id": prod["id"], "title": "Cold storage",
        "quantity_value": 10, "unit_code": "day", "price_minor": 50000,
        "listing_type": "FIXED_PRICE"}, headers=auth_headers(farmer))
    assert listing.status_code == 201, listing.get_json()
