"""Spec §129 E2E: browse → offer → negotiate → accept → pay → deliver → review → wallet."""
import hashlib
import hmac
import json
import time
import uuid

from tests.conftest import auth_headers


def _sig(secret, ts, body):
    return hmac.new(secret, ts.encode() + b"." + body.encode(), hashlib.sha256).hexdigest()


def test_full_marketplace_loop(client, buyer, farmer):
    app = client.application

    farm = client.post("/api/v1/farms", json={"name": "Loop Farm", "region": "Northern"},
                       headers=auth_headers(farmer)).get_json()["farm"]
    maize = [p for p in client.get("/api/v1/products").get_json()["items"] if p["slug"] == "maize"][0]
    listing = client.post("/api/v1/listings", json={
        "farm_id": farm["id"], "product_id": maize["id"], "title": "Loop Maize",
        "quantity_value": 100, "unit_code": "kg", "price_minor": 50000,
        "listing_type": "FIXED_PRICE"}, headers=auth_headers(farmer)).get_json()["listing"]

    offer = client.post("/api/v1/offers", json={
        "listing_id": listing["id"], "quantity_value": 20, "price_minor": 45000},
        headers=auth_headers(buyer)).get_json()["offer"]
    counter = client.post(f"/api/v1/offers/{offer['id']}/counter",
                          json={"price_minor": 48000}, headers=auth_headers(farmer)).get_json()["offer"]
    assert counter["state"] == "COUNTERED" or counter["price_minor"] == 48000

    order = client.post(f"/api/v1/offers/{counter['id']}/accept",
                        headers=auth_headers(buyer))
    assert order.status_code == 201, order.get_json()
    order_id = order.get_json()["order"]["id"]

    pay_resp = client.post(f"/api/v1/orders/{order_id}/payments",
                           json={"provider": "mock", "method": "mobile_money"},
                           headers=auth_headers(buyer))
    assert pay_resp.status_code == 200, pay_resp.get_json()
    txn = pay_resp.get_json()["payment"]

    secret = app.config["PAYMENT_WEBHOOK_SECRETS"].split(";")[0].split(":", 1)[1].encode()
    body = json.dumps({"event_id": f"evt-{uuid.uuid4().hex[:8]}",
                       "reference": txn["provider_reference"], "state": "SUCCEEDED"})
    ts = str(int(time.time()))
    wh = client.post("/api/v1/payments/webhook/mock", data=body,
                     content_type="application/json",
                     headers={"X-Ijwi-Timestamp": ts, "X-Ijwi-Signature": _sig(secret, ts, body)})
    assert wh.get_json().get("payment_state") == "SUCCEEDED"

    for state in ("PROCESSING", "READY_FOR_PICKUP"):
        r = client.post(f"/api/v1/orders/{order_id}/transition", json={"state": state},
                        headers=auth_headers(farmer))
        assert r.status_code == 200, r.get_json()

    dr = client.post("/api/v1/delivery-requests", json={
        "order_id": order_id, "pickup_region": "Northern", "destination_region": "Kigali",
        "quantity_value": 20, "unit_code": "kg"}, headers=auth_headers(buyer))
    assert dr.status_code == 201
    dr_id = dr.get_json()["delivery_request"]["id"]

    import re as _re

    from app.services import auth_service

    phone = f"+2507{uuid.uuid4().hex[:9]}"
    username_suffix = uuid.uuid4().hex[:6]
    reg = client.post("/api/v1/auth/register", json={
        "phone": phone, "full_name": "Courier", "username": f"log{username_suffix}",
        "password": "pw123456", "role": "LOGISTICS"})
    assert reg.status_code == 201, reg.get_json()
    sms = auth_service.TestCaptureSMSProvider.outbox[-1][1]
    code = _re.search(r"code: (\d{6})", sms).group(1)
    courier = client.post("/api/v1/auth/otp/verify", json={"phone": phone, "code": code}).get_json()["tokens"]

    quote = client.post(f"/api/v1/delivery-requests/{dr_id}/quotes",
                        json={"price_minor": 3000}, headers=auth_headers(courier)).get_json()["quote"]
    delivery = client.post(f"/api/v1/quotes/{quote['id']}/accept",
                           headers=auth_headers(buyer)).get_json()["delivery"]
    d_id = delivery["id"]
    for state in ("PICKUP_SCHEDULED", "PICKED_UP", "IN_TRANSIT", "DELIVERED"):
        r = client.post(f"/api/v1/deliveries/{d_id}/advance", json={"state": state},
                        headers=auth_headers(courier))
        assert r.status_code == 200, r.get_json()

    done = client.post(f"/api/v1/orders/{order_id}/transition", json={"state": "COMPLETED"},
                       headers=auth_headers(buyer))
    assert done.status_code == 200, done.get_json()

    rv = client.post(f"/api/v1/orders/{order_id}/reviews",
                     json={"subject_role": "farmer", "overall_rating": 5,
                           "comment": "excellent"},
                     headers=auth_headers(buyer))
    assert rv.status_code == 201

    wallet = client.get("/api/v1/wallet", headers=auth_headers(farmer)).get_json()
    assert wallet["available_minor"] == 936_000  # 960000 minus 2.5% fee

    rep = client.get("/api/v1/reputation/me", headers=auth_headers(farmer))
    assert rep.status_code == 200, rep.get_json()
