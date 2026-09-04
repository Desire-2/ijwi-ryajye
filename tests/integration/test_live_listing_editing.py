"""Live listing editing: price/quantity changes flow through the backend and
stay reconciled with the listing's inventory batch."""
from tests.conftest import auth_headers


def _product(client, slug):
    for p in client.get("/api/v1/products").get_json()["items"]:
        if p["slug"] == slug:
            return p
    raise AssertionError(f"product {slug} not seeded")


def _live_listing(client, farmer, qty=100, price=50000):
    maize = _product(client, "maize")
    r = client.post("/api/v1/listings", json={
        "product_id": maize["id"], "title": "Live Maize", "description": "Dry maize.",
        "quantity_value": qty, "available_quantity": qty, "unit_code": "kg",
        "price_minor": price, "listing_type": "FIXED_PRICE",
        "location_region": "Northern"}, headers=auth_headers(farmer))
    assert r.status_code == 201, r.get_json()
    return r.get_json()["listing"]


def test_live_price_and_quantity_edits(client, farmer):
    headers = auth_headers(farmer)
    listing = _live_listing(client, farmer, qty=100)

    # Price edit (whole flow allowed for live non-auction listings).
    r = client.patch(f"/api/v1/listings/{listing['id']}", json={
        "price_minor": 55000, "title": "Live Maize — new batch",
        "description": "Updated description.", "negotiable": True},
        headers=headers)
    assert r.status_code == 200, r.get_json()
    updated = r.get_json()["listing"]
    assert updated["price_minor"] == 55000
    assert updated["title"] == "Live Maize — new batch"
    assert updated["negotiable"] is True

    # Top up stock: +50 kg moves the inventory batch total with the listing.
    r = client.patch(f"/api/v1/listings/{listing['id']}", json={
        "available_quantity": 150}, headers=headers)
    assert r.status_code == 200, r.get_json()
    assert r.get_json()["listing"]["available_quantity"] == 150

    from extensions import db
    from app.models.marketplace import Inventory

    inv = Inventory.query.filter_by(owner_id=farmer["id"]).first()
    assert float(inv.quantity_total) == 150.0

    # Further top-ups above the original quantity grow the capacity (restock).
    r = client.patch(f"/api/v1/listings/{listing['id']}", json={
        "available_quantity": 300}, headers=headers)
    assert r.status_code == 200, r.get_json()
    assert r.get_json()["listing"]["available_quantity"] == 300

    # Negative availability is rejected.
    r = client.patch(f"/api/v1/listings/{listing['id']}", json={
        "available_quantity": -10}, headers=headers)
    assert r.status_code == 400

    # Running out marks the listing SOLD_OUT; restocking reopens it ACTIVE.
    r = client.patch(f"/api/v1/listings/{listing['id']}", json={
        "available_quantity": 0}, headers=headers)
    assert r.status_code == 200
    assert r.get_json()["listing"]["state"] == "SOLD_OUT"
    r = client.patch(f"/api/v1/listings/{listing['id']}", json={
        "available_quantity": 40}, headers=headers)
    assert r.status_code == 200
    assert r.get_json()["listing"]["state"] == "ACTIVE"
    assert r.get_json()["listing"]["available_quantity"] == 40

    inv = Inventory.query.filter_by(owner_id=farmer["id"]).first()
    assert float(inv.quantity_total) == 40.0
    assert inv.state == "AVAILABLE"

    # Sellers cannot edit a closed listing's quantity.
    client.post(f"/api/v1/listings/{listing['id']}/close", headers=headers)
    r = client.patch(f"/api/v1/listings/{listing['id']}", json={
        "available_quantity": 100}, headers=headers)
    assert r.status_code == 400


def test_live_edit_requires_ownership(client, buyer, farmer):
    listing = _live_listing(client, farmer)
    r = client.patch(f"/api/v1/listings/{listing['id']}", json={
        "price_minor": 1, "available_quantity": 0}, headers=auth_headers(buyer))
    assert r.status_code == 403, r.get_json()
