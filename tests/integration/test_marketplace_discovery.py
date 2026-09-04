"""Regression tests for marketplace discovery endpoints fixed/added in the
marketplace build-out: favorites, saved searches, global search, the listings
category filter and sort options, and the price-advisor route."""


def _seed_listing(client, farmer, product_slug="maize", price_minor=50000,
                  region="Northern", quality_grade="GRADE_A", listing_type="FIXED_PRICE"):
    farm = client.post("/api/v1/farms", json={"name": "Discovery Farm", "region": region},
                       headers=auth_headers(farmer)).get_json()["farm"]
    product = [p for p in client.get("/api/v1/products").get_json()["items"]
               if p["slug"] == product_slug][0]
    r = client.post("/api/v1/listings", json={
        "farm_id": farm["id"], "product_id": product["id"],
        "title": f"Discovery {product_slug}", "quantity_value": 100,
        "available_quantity": 80, "unit_code": "kg",
        "price_minor": price_minor, "listing_type": listing_type,
        "location_region": region, "quality_grade": quality_grade},
        headers=auth_headers(farmer))
    assert r.status_code == 201, r.get_json()
    return r.get_json()["listing"]


def test_favorites_round_trip(client, buyer, farmer):
    listing = _seed_listing(client, farmer)
    headers = auth_headers(buyer)

    r = client.post("/api/v1/favorites", json={"listing_id": listing["id"]}, headers=headers)
    assert r.status_code == 200 and r.get_json()["favorited"] is True

    favs = client.get("/api/v1/favorites", headers=headers).get_json()["favorites"]
    assert any(f["id"] == listing["id"] for f in favs), favs

    r = client.delete(f"/api/v1/favorites/{listing['id']}", headers=headers)
    assert r.status_code == 200 and r.get_json()["favorited"] is False
    favs = client.get("/api/v1/favorites", headers=headers).get_json()["favorites"]
    assert all(f["id"] != listing["id"] for f in favs)


def test_saved_search_round_trip(client, buyer):
    headers = auth_headers(buyer)
    r = client.post("/api/v1/saved-searches", json={
        "name": "Beans near Kigali", "query_json": {"q": "beans", "region": "Kigali"},
        "notify": True}, headers=headers)
    assert r.status_code == 201, r.get_json()
    ss = r.get_json()["saved_search"]
    assert ss["label"] == "Beans near Kigali"
    assert ss["notify"] is True

    rows = client.get("/api/v1/saved-searches", headers=headers).get_json()["saved_searches"]
    assert any(s["id"] == ss["id"] and s["label"] == "Beans near Kigali" for s in rows)

    r = client.delete(f"/api/v1/saved-searches/{ss['id']}", headers=headers)
    assert r.status_code == 200
    rows = client.get("/api/v1/saved-searches", headers=headers).get_json()["saved_searches"]
    assert all(s["id"] != ss["id"] for s in rows)


def test_global_search_includes_farmers(client, buyer, farmer):
    _seed_listing(client, farmer)
    me = client.get("/api/v1/users/me", headers=auth_headers(farmer)).get_json()["user"]
    res = client.get("/api/v1/search",
                     query_string={"q": me["full_name"][:6], "scope": "farmers"})
    assert res.status_code == 200, res.get_json()
    assert any(f["id"] == farmer["id"] for f in res.get_json().get("farmers", [])), res.get_json()


def test_listings_category_filter_and_sorts(client, farmer):
    _seed_listing(client, farmer, product_slug="maize", price_minor=50000)
    _seed_listing(client, farmer, product_slug="beans", price_minor=30000)

    res = client.get("/api/v1/listings", query_string={"category": "crops"}).get_json()
    assert len(res["items"]) >= 2

    by_price = client.get("/api/v1/listings", query_string={"sort": "price_asc"}).get_json()
    prices = [l["price_minor"] for l in by_price["items"] if l["price_minor"] is not None]
    assert prices == sorted(prices)

    by_qty = client.get("/api/v1/listings", query_string={"sort": "quantity_desc"}).get_json()
    qty = [l["available_quantity"] for l in by_qty["items"]]
    assert qty == sorted(qty, reverse=True)


def test_price_advice_route(client, farmer, buyer):
    product = [p for p in client.get("/api/v1/products").get_json()["items"]
               if p["slug"] == "maize"][0]
    res = client.get("/api/v1/price-advice", query_string={
        "product_id": product["id"], "price_minor": 40000, "unit_code": "kg"},
        headers=auth_headers(buyer))
    assert res.status_code == 200, res.get_json()
    advisor = res.get_json()["advisor"]
    assert "is_estimate" in advisor and advisor["observations_counted"] >= 0


from tests.conftest import auth_headers  # noqa: E402
