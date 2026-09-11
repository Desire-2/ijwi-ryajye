"""Regression tests for the seller catalogue-contribution flow.

Root cause of the P0 "No items in this category yet" bug: the catalogue was
empty and the wizard had no way to grow it. These tests lock in the fix:

1. any authenticated seller can contribute a catalogue product
   (`POST /api/v1/catalog/products`), find-or-create by slug;
2. the contributed product is a real catalogue row immediately usable by the
   listing wizard, including filtering (`category`, `q`);
3. unknown-category filters fail open with an empty page (no crash);
4. unauthenticated requests are rejected.
"""
from tests.conftest import auth_headers


def _create_product(client, token, name="Hass Avocado", category="crops",
                    unit="kg"):
    return client.post("/api/v1/catalog/products", json={
        "name": name, "category_slug": category, "default_unit": unit,
    }, headers=auth_headers(token))


def test_requires_authentication(client):
    r = client.post("/api/v1/catalog/products", json={"name": "Cabbage"})
    assert r.status_code in (401, 403), r.get_json()


def test_rejects_missing_category(client, farmer):
    r = _create_product(client, farmer, category="does-not-exist")
    assert r.status_code == 400, r.get_json()


def test_seller_can_contribute_and_use_product(client, farmer, buyer):
    # 1. Contribute a brand-new catalogue product as a seller.
    r = _create_product(client, farmer, name="Hass Avocado", unit="piece")
    assert r.status_code == 201, r.get_json()
    product = r.get_json()
    assert product["name"] == "Hass Avocado"
    assert product["slug"] == "hass-avocado"
    assert product["default_unit"] == "piece"
    assert product["category"]["slug"] == "crops"

    # 2. It is immediately visible in the listing catalogue (and filterable).
    items = client.get("/api/v1/products", query_string={
        "category": "crops", "q": "hass"}).get_json()["items"]
    assert any(p["id"] == product["id"] for p in items), items

    # 3. It can drive the whole listing wizard flow (DRAFT -> publish).
    draft = client.post("/api/v1/listings", json={
        "state": "DRAFT", "product_id": product["id"],
        "title": "Hass avocados", "quantity_value": 20,
        "unit_code": "piece", "location_region": "Eastern",
    }, headers=auth_headers(farmer))
    assert draft.status_code == 201, draft.get_json()
    listing_id = draft.get_json()["listing"]["id"]

    r = client.patch(f"/api/v1/listings/{listing_id}", json={
        "price_minor": 150000, "currency_code": "RWF", "price_type": "PER_UNIT",
        "available_quantity": 20,
    }, headers=auth_headers(farmer))
    assert r.status_code == 200, r.get_json()

    r = client.post(f"/api/v1/listings/{listing_id}/publish",
                    headers=auth_headers(farmer))
    assert r.status_code == 200, r.get_json()
    assert r.get_json()["listing"]["state"] == "ACTIVE"

    # It is on the public market.
    market = client.get("/api/v1/listings").get_json()["items"]
    assert any(l["id"] == listing_id for l in market)


def test_find_or_create_is_idempotent(client, farmer):
    first = _create_product(client, farmer, name="Ankole Heifer")
    assert first.status_code == 201, first.get_json()
    second = _create_product(client, farmer, name="ankole heifer",
                             category="livestock", unit="animal")
    # Same slug (case-insensitive) -> the existing row is returned.
    assert second.status_code in (200, 201), second.get_json()
    assert second.get_json()["id"] == first.get_json()["id"]


def test_products_endpoint_category_and_search_filters(client, farmer):
    items = client.get("/api/v1/products",
                       query_string={"category": "rentals"}).get_json()["items"]
    assert items and all(p["category"]["slug"] == "rentals" for p in items)

    maize = client.get("/api/v1/products",
                       query_string={"q": "maize"}).get_json()["items"]
    assert any(p["slug"] == "maize" for p in maize)

    # An unknown category fails open with an empty page, not a 500.
    empty = client.get("/api/v1/products",
                       query_string={"category": "not-a-category"})
    assert empty.status_code == 200
    assert empty.get_json()["items"] == []