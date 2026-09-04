"""Reviews surfaced on farmer profiles / listing detail: GET /users/<id>/reviews."""
from tests.conftest import auth_headers


def test_user_reviews_endpoint_returns_verified_reviews(client, buyer, farmer):
    farm = client.post("/api/v1/farms", json={"name": "Review Farm", "region": "Northern"},
                       headers=auth_headers(farmer)).get_json()["farm"]
    maize = [p for p in client.get("/api/v1/products").get_json()["items"] if p["slug"] == "maize"][0]
    listing = client.post("/api/v1/listings", json={
        "farm_id": farm["id"], "product_id": maize["id"], "title": "Review Maize",
        "quantity_value": 50, "unit_code": "kg", "price_minor": 50000,
        "listing_type": "FIXED_PRICE"}, headers=auth_headers(farmer)).get_json()["listing"]

    # No reviews yet: empty list, and farmer card shows zero rating count.
    r0 = client.get(f"/api/v1/users/{farmer['id']}/reviews",
                    headers=auth_headers(buyer)).get_json()
    assert r0["reviews"] == []
    card = client.get(f"/api/v1/users/{farmer['id']}",
                      headers=auth_headers(buyer)).get_json()
    assert card["rating_count"] == 0

    # Complete a transaction the seller must see on their profile.
    order_id = None
    # Buyer offers; farmer counters to a higher price the buyer accepts to keep flow simple.
    offer = client.post("/api/v1/offers", json={
        "listing_id": listing["id"], "quantity_value": 10, "price_minor": 50000},
        headers=auth_headers(buyer)).get_json()["offer"]

    # Direct full-loop helper: accept via buyer after farmer counter, then
    # simulate the delivery chain minimally (seller completion path needs
    # DELIVERED first) - so mirror e2e: mark PAID via webhook, then drive
    # through PROCESSING/READY_FOR_PICKUP and complete from buyer side after
    # delivery events are faked by the courier.
    # (Kept short: reuse of transitions that already exist in e2e tests.)
    import time
    import json as _json
    import hashlib
    import hmac
    import uuid

    app = client.application

    # Farmer rejects? No: buyer accepts own offer only if seller side accept is
    # done by seller. Here the *seller* accepts the buyer's offer.
    acc = client.post(f"/api/v1/offers/{offer['id']}/accept",
                      headers=auth_headers(farmer))
    assert acc.status_code == 201, acc.get_json()
    order_id = acc.get_json()["order"]["id"]

    pay = client.post(f"/api/v1/orders/{order_id}/payments",
                      json={"provider": "mock", "method": "mobile_money"},
                      headers=auth_headers(buyer)).get_json()["payment"]
    secret = app.config["PAYMENT_WEBHOOK_SECRETS"].split(";")[0].split(":", 1)[1].encode()
    body = _json.dumps({"event_id": f"evt-{uuid.uuid4().hex[:8]}",
                        "reference": pay["provider_reference"], "state": "SUCCEEDED"})
    ts = str(int(time.time()))
    wh = client.post("/api/v1/payments/webhook/mock", data=body,
                     content_type="application/json",
                     headers={"X-Ijwi-Timestamp": ts,
                              "X-Ijwi-Signature": hmac.new(
                                  secret, ts.encode() + b"." + body.encode(),
                                  hashlib.sha256).hexdigest()})
    assert wh.get_json().get("payment_state") == "SUCCEEDED"

    # Seller prepares the order before the courier chain (mirrors e2e).
    for state in ("PROCESSING", "READY_FOR_PICKUP"):
        r = client.post(f"/api/v1/orders/{order_id}/transition",
                        json={"state": state}, headers=auth_headers(farmer))
        assert r.status_code == 200, r.get_json()

    # Drive the order to COMPLETED via a courier delivery chain (mirrors e2e).
    import re as _re

    from app.services import auth_service

    phone = f"+2507{uuid.uuid4().hex[:9]}"
    reg = client.post("/api/v1/auth/register", json={
        "phone": phone, "full_name": "Courier", "username": f"log{uuid.uuid4().hex[:6]}",
        "password": "pw123456", "role": "LOGISTICS"})
    assert reg.status_code == 201, reg.get_json()
    sms = auth_service.TestCaptureSMSProvider.outbox[-1][1]
    code = _re.search(r"code: (\d{6})", sms).group(1)
    courier = client.post("/api/v1/auth/otp/verify",
                          json={"phone": phone, "code": code}).get_json()["tokens"]

    dr = client.post("/api/v1/delivery-requests", json={
        "order_id": order_id, "pickup_region": "Northern", "destination_region": "Kigali",
        "quantity_value": 10, "unit_code": "kg"}, headers=auth_headers(buyer))
    assert dr.status_code == 201
    dr_id = dr.get_json()["delivery_request"]["id"]
    quote = client.post(f"/api/v1/delivery-requests/{dr_id}/quotes",
                        json={"price_minor": 3000},
                        headers=auth_headers(courier)).get_json()["quote"]
    delivery = client.post(f"/api/v1/quotes/{quote['id']}/accept",
                           headers=auth_headers(buyer)).get_json()["delivery"]
    for state in ("PICKUP_SCHEDULED", "PICKED_UP", "IN_TRANSIT", "DELIVERED"):
        r = client.post(f"/api/v1/deliveries/{delivery['id']}/advance",
                        json={"state": state}, headers=auth_headers(courier))
        assert r.status_code == 200, r.get_json()

    done = client.post(f"/api/v1/orders/{order_id}/transition",
                       json={"state": "COMPLETED"}, headers=auth_headers(buyer))
    assert done.status_code == 200, done.get_json()

    rv = client.post(f"/api/v1/orders/{order_id}/reviews",
                     json={"subject_role": "farmer", "overall_rating": 5,
                           "comment": "Graded maize, on time"}, headers=auth_headers(buyer))
    assert rv.status_code == 201, rv.get_json()

    # Farmer card + reputation summary now carry the aggregate.
    card = client.get(f"/api/v1/users/{farmer['id']}",
                      headers=auth_headers(buyer)).get_json()
    assert card["rating_avg"] == 5.0 and card["rating_count"] == 1

    rep = client.get(f"/api/v1/reputation/users/{farmer['id']}",
                     headers=auth_headers(buyer)).get_json()
    assert rep["rating_avg"] == 5.0 and rep["rating_count"] == 1

    # The reviews endpoint returns the full review with context.
    got = client.get(f"/api/v1/users/{farmer['id']}/reviews",
                     headers=auth_headers(buyer)).get_json()
    assert got["count"] == 1
    rev = got["reviews"][0]
    assert rev["overall_rating"] == 5
    assert rev["comment"] == "Graded maize, on time"
    assert rev["verified_transaction"] is True
    assert rev["reviewer"]["id"] == buyer["id"]
    assert rev["listing"]["title"] == "Review Maize"
    assert rev["order"]["id"] == order_id
