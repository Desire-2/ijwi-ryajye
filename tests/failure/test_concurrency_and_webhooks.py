import threading

from tests.conftest import auth_headers


def test_no_oversell_under_concurrency(client, buyer, farmer):
    """Two buyers racing for the last units: only one may win."""
    app = client.application

    r = client.post("/api/v1/farms", json={"name": "Race Farm", "region": "Eastern"},
                    headers=auth_headers(farmer))
    farm_id = r.get_json()["farm"]["id"]
    pr = client.get("/api/v1/products")
    assert pr.status_code == 200, pr.get_json()
    product = [p for p in pr.get_json()["items"] if p["slug"] == "rice"][0]
    assert product

    # seller creates listing + inventory of exactly 10 kg via API listing creation
    r = client.post("/api/v1/listings", json={
        "farm_id": farm_id, "product_id": product["id"], "title": "Rice Race",
        "quantity_value": 10, "unit_code": "kg", "price_minor": 10000,
        "listing_type": "FIXED_PRICE"}, headers=auth_headers(farmer))
    listing = r.get_json()["listing"]

    import uuid

    buyer2_phone = f"+2507{uuid.uuid4().hex[:9]}"
    from tests.conftest import register_and_verify

    buyer2 = register_and_verify(client, buyer2_phone, f"buyer2{uuid.uuid4().hex[:6]}")

    results = {}

    def make_offer(tag, tokens):
        c = app.test_client()
        resp = c.post("/api/v1/offers", json={
            "listing_id": listing["id"], "quantity_value": 10, "price_minor": 10000},
            headers=auth_headers(tokens))
        results[tag] = resp.status_code
        if resp.status_code == 201:
            oid = resp.get_json()["offer"]["id"]
            acc = c.post(f"/api/v1/offers/{oid}/accept", headers=auth_headers(farmer))
            results[tag + "_accept"] = acc.status_code

    t1 = threading.Thread(target=make_offer, args=("a", buyer))
    t2 = threading.Thread(target=make_offer, args=("b", buyer2))
    t1.start(); t2.start(); t1.join(); t2.join()

    accepts = [v for k, v in results.items() if k.endswith("_accept")]
    successes = sum(1 for s in accepts if s == 201)
    assert len(accepts) == 2
    assert successes <= 1, f"oversell detected! accept statuses: {accepts}"
