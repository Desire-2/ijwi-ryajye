"""Universal agricultural listing engine tests.

Covers the DRAFT lifecycle (create draft -> edit -> publish with one inventory
batch), flexible per-kind `attributes`, live-commercial validation on publish,
the catalog units endpoint, and multi-kind listings (equipment, services,
rentals) so the one engine serves the whole agricultural economy.
"""
from tests.conftest import auth_headers


def _product(client, slug):
    for p in client.get("/api/v1/products").get_json()["items"]:
        if p["slug"] == slug:
            return p
    raise AssertionError(f"product {slug} not seeded")


def _draft_listing(client, farmer, slug="cattle", extra=None):
    payload = {
        "state": "DRAFT", "product_id": _product(client, slug)["id"],
        "title": f"Draft {slug}", "quantity_value": 3, "unit_code": "piece",
        "location_region": "Northern",
    }
    if extra:
        payload.update(extra)
    r = client.post("/api/v1/listings", json=payload, headers=auth_headers(farmer))
    assert r.status_code == 201, r.get_json()
    return r.get_json()["listing"]


def test_draft_lifecycle_edit_publish_and_inventory(client, farmer):
    headers = auth_headers(farmer)
    listing = _draft_listing(client, farmer, extra={"attributes": {"breed": "Holstein"}})
    assert listing["state"] == "DRAFT"
    assert listing["price_minor"] is None  # a draft may be priced later
    assert listing["attributes"] == {"breed": "Holstein"}

    # Drafts stay off the public market.
    market = client.get("/api/v1/listings").get_json()["items"]
    assert all(l["id"] != listing["id"] for l in market)

    # Drafts are visible to the seller.
    mine = client.get("/api/v1/listings/mine", headers=headers).get_json()["items"]
    assert any(l["id"] == listing["id"] and l["state"] == "DRAFT" for l in mine)

    # Media can be attached to an existing draft (wizard photo step on edit).
    r = client.post(f"/api/v1/listings/{listing['id']}/media", json={
        "media": [{"storage_key": "images/me/draft-photo.jpg"}]}, headers=headers)
    assert r.status_code == 200 and r.get_json()["added"] == 1, r.get_json()

    # Edit the draft across creation fields (price, attributes, quantity...).
    r = client.patch(f"/api/v1/listings/{listing['id']}", json={
        "price_minor": 900000, "currency_code": "RWF", "price_type": "PER_UNIT",
        "quantity_value": 2, "available_quantity": 2,
        "attributes": {"breed": "Holstein", "sex": "Female", "age_years": 3,
                       "weight_kg": 450},
        "description": "Registered Holstein, fully vaccinated.",
    }, headers=headers)
    assert r.status_code == 200, r.get_json()
    updated = r.get_json()["listing"]
    assert updated["state"] == "DRAFT"
    assert updated["price_minor"] == 900000
    assert updated["quantity_value"] == 2
    assert updated["description"] == "Registered Holstein, fully vaccinated."
    assert updated["attributes"]["weight_kg"] == 450

    # A draft without a price cannot be published.
    no_price = _draft_listing(client, farmer, slug="cattle")
    r = client.post(f"/api/v1/listings/{no_price['id']}/publish", headers=headers)
    assert r.status_code == 400, r.get_json()

    # Publishing activates the listing and creates exactly one inventory batch.
    r = client.post(f"/api/v1/listings/{listing['id']}/publish", headers=headers)
    assert r.status_code == 200, r.get_json()
    assert r.get_json()["listing"]["state"] == "ACTIVE"

    market = client.get("/api/v1/listings").get_json()["items"]
    assert any(l["id"] == listing["id"] for l in market)

    # Double publish is a no-op (no duplicate inventory row).
    r = client.post(f"/api/v1/listings/{listing['id']}/publish", headers=headers)
    assert r.status_code == 200 and r.get_json()["listing"]["state"] == "ACTIVE"

    from extensions import db
    from app.models.marketplace import Inventory

    inv = Inventory.query.filter_by(owner_id=farmer["id"]).all()
    assert len(inv) == 1 and float(inv[0].quantity_total) == 2.0
    assert inv[0].batch_ref == f"listing-{listing['id'][:8]}"

    # Detail view round-trips description + attributes + availability + media.
    detail = client.get(f"/api/v1/listings/{listing['id']}",
                        headers=auth_headers(farmer)).get_json()["listing"]
    assert detail["description"].startswith("Registered Holstein")
    assert detail["attributes"]["sex"] == "Female"
    assert detail["available_from"] is None
    assert len(detail["media"]) == 1
    assert detail["media"][0]["storage_key"] == "images/me/draft-photo.jpg"


def test_invalid_attributes_and_quantity_rejected(client, farmer):
    headers = auth_headers(farmer)
    # Non-object attributes fail schema validation (422) before the service.
    r = client.post("/api/v1/listings", json={
        "state": "DRAFT", "product_id": _product(client, "cattle")["id"],
        "title": "Bad attrs", "quantity_value": 1, "unit_code": "piece",
        "attributes": "not-an-object"}, headers=headers)
    assert r.status_code == 422

    # Nested (non-scalar) attribute values are rejected by the service.
    r = client.post("/api/v1/listings", json={
        "state": "DRAFT", "product_id": _product(client, "cattle")["id"],
        "title": "Nested attrs", "quantity_value": 1, "unit_code": "piece",
        "attributes": {"badges": ["organic"]}}, headers=headers)
    assert r.status_code == 400, r.get_json()

    r = client.post("/api/v1/listings", json={
        "state": "DRAFT", "product_id": _product(client, "cattle")["id"],
        "title": "Neg qty", "quantity_value": -4, "unit_code": "piece"},
        headers=headers)
    assert r.status_code == 400


def test_publish_requires_ownership(client, buyer, farmer):
    listing = _draft_listing(client, farmer)
    r = client.post(f"/api/v1/listings/{listing['id']}/publish",
                    headers=auth_headers(buyer))
    assert r.status_code == 403, r.get_json()

    # Editing someone else's draft is forbidden too.
    r = client.patch(f"/api/v1/listings/{listing['id']}",
                     json={"price_minor": 100}, headers=auth_headers(buyer))
    assert r.status_code == 403, r.get_json()


def test_units_endpoint_and_kind_listings_go_live(client, farmer):
    headers = auth_headers(farmer)
    units = client.get("/api/v1/units").get_json()["units"]
    codes = {u["code"] for u in units}
    assert {"kg", "piece", "day", "ha"}.issubset(codes), codes

    # Equipment for sale: whole tractor, TOTAL price.
    tractor = _product(client, "tractor")
    r = client.post("/api/v1/listings", json={
        "product_id": tractor["id"], "title": "John Deere 5075E",
        "description": "2009 model, 3,200h, serviced.",
        "quantity_value": 1, "unit_code": "piece",
        "price_minor": 25000000, "price_type": "TOTAL",
        "listing_type": "FIXED_PRICE", "location_region": "Northern",
        "attributes": {"condition": "Used", "brand": "John Deere", "model": "5075E"},
    }, headers=headers)
    assert r.status_code == 201, r.get_json()
    eq = r.get_json()["listing"]
    assert eq["attributes"]["condition"] == "Used"

    # Service: ploughing priced per hectare.
    plough = _product(client, "ploughing-service")
    r = client.post("/api/v1/listings", json={
        "product_id": plough["id"], "title": "Tractor ploughing — Musanze",
        "quantity_value": 5, "unit_code": "ha",
        "price_minor": 5000000, "price_type": "PER_UNIT",
        "listing_type": "FIXED_PRICE", "location_region": "Northern",
        "attributes": {"operator_included": "Yes", "service_area": "Musanze, Burera"},
    }, headers=headers)
    assert r.status_code == 201, r.get_json()

    # Rental: tractor hire priced per day.
    hire = _product(client, "tractor-hire")
    r = client.post("/api/v1/listings", json={
        "product_id": hire["id"], "title": "Tractor hire with operator",
        "quantity_value": 1, "unit_code": "day",
        "price_minor": 1500000, "price_type": "PER_UNIT",
        "listing_type": "FIXED_PRICE", "location_region": "Northern",
        "attributes": {"deposit_minor": 1000000, "operator_included": "Yes"},
    }, headers=headers)
    assert r.status_code == 201, r.get_json()

    # Category filter discovers each kind in the public market.
    by_cat = client.get("/api/v1/listings",
                        query_string={"category": "farm-equipment"}).get_json()
    assert any(l["id"] == eq["id"] for l in by_cat["items"])
    svc = client.get("/api/v1/listings",
                     query_string={"category": "farm-services"}).get_json()
    assert len(svc["items"]) >= 1
    rnt = client.get("/api/v1/listings",
                     query_string={"category": "rentals"}).get_json()
    assert len(rnt["items"]) >= 1

    # A buyer can find the tractor by category search.
    r = client.get("/api/v1/search", query_string={"q": "John Deere", "scope": "listings"})
    assert any(l["id"] == eq["id"] for l in r.get_json()["listings"])
