import hashlib
import hmac
import json
import time
import uuid

from tests.conftest import auth_headers


def _webhook_sig(secret: bytes, ts: str, body: str) -> str:
    return hmac.new(secret, ts.encode() + b"." + body.encode(), hashlib.sha256).hexdigest()


def test_offer_accept_pay_webhook_credits_wallet(client, buyer, farmer):
    app = client.application

    # farmer creates a listing (with inventory batch)
    r = client.post("/api/v1/farms", json={"name": "Hill Farm", "region": "Northern"},
                    headers=auth_headers(farmer))
    assert r.status_code == 201, r.get_json()
    farm_id = r.get_json()["farm"]["id"]

    pr = client.get("/api/v1/products")
    assert pr.status_code == 200, pr.get_json()
    maize = [p for p in pr.get_json()["items"] if p["slug"] == "maize"][0]

    r = client.post("/api/v1/listings", json={
        "farm_id": farm_id, "product_id": maize["id"], "title": "Test Maize",
        "description": "desc", "quantity_value": 100, "unit_code": "kg",
        "price_minor": 50000, "listing_type": "FIXED_PRICE"}, headers=auth_headers(farmer))
    assert r.status_code == 201, r.get_json()
    listing = r.get_json()["listing"]

    # buyer makes offer; seller accepts -> order PAYMENT_PENDING/ACCEPTED
    r = client.post("/api/v1/offers", json={
        "listing_id": listing["id"], "quantity_value": 10,
        "price_minor": 50000}, headers=auth_headers(buyer))
    assert r.status_code == 201, r.get_json()
    offer_id = r.get_json()["offer"]["id"]

    r = client.post(f"/api/v1/offers/{offer_id}/accept", headers=auth_headers(farmer))
    assert r.status_code == 201, r.get_json()
    order = r.get_json()["order"]
    order_id = order["id"]

    # initiate payment with mock provider
    r = client.post(f"/api/v1/orders/{order_id}/payments",
                    json={"provider": "mock", "method": "mobile_money"},
                    headers=auth_headers(buyer))
    assert r.status_code == 200, r.get_json()
    txn = r.get_json()["payment"]

    secret = app.config["PAYMENT_WEBHOOK_SECRETS"].split(";")[0].split(":", 1)[1].encode()
    event_id = f"evt-{uuid.uuid4().hex[:10]}"
    body = json.dumps({"event_type": "transaction.succeeded", "event_id": event_id,
                       "reference": txn["provider_reference"]})
    ts = str(int(time.time()))
    sig = _webhook_sig(secret, ts, body)
    r = client.post("/api/v1/payments/webhook/mock", data=body,
                    content_type="application/json",
                    headers={"X-Ijwi-Timestamp": ts, "X-Ijwi-Signature": sig})
    assert r.status_code == 200, r.get_json()
    assert r.get_json()["payment_state"] == "SUCCEEDED"

    # wallet credited: total 500000 minor - fee 2.5% => 487500
    r = client.get("/api/v1/wallet", headers=auth_headers(farmer))
    assert r.status_code == 200
    assert r.get_json()["available_minor"] == 487_500

    # duplicate webhook is idempotent
    r2 = client.post("/api/v1/payments/webhook/mock", data=body,
                     content_type="application/json",
                     headers={"X-Ijwi-Timestamp": ts, "X-Ijwi-Signature": sig})
    assert r2.status_code in (200, 409)

    r = client.get("/api/v1/wallet", headers=auth_headers(farmer))
    assert r.get_json()["available_minor"] == 487_500

    # invalid signature rejected
    bad_body = json.dumps({"event_type": "transaction.succeeded", "event_id": f"evt-{uuid.uuid4().hex[:6]}",
                           "reference": txn["provider_reference"]})
    r = client.post("/api/v1/payments/webhook/mock", data=bad_body,
                    content_type="application/json",
                    headers={"X-Ijwi-Timestamp": ts, "X-Ijwi-Signature": _webhook_sig(b"wrong", ts, bad_body)})
    assert r.status_code == 400
    assert r.get_json()["error"]["code"] == "INVALID_WEBHOOK_SIGNATURE"


def test_order_state_guards(client, buyer, farmer):
    r = client.post("/api/v1/farms", json={"name": "F2", "region": "Southern"},
                    headers=auth_headers(farmer))
    farm_id = r.get_json()["farm"]["id"]
    pr = client.get("/api/v1/products")
    assert pr.status_code == 200, pr.get_json()
    beans = [p for p in pr.get_json()["items"] if p["slug"] == "beans"][0]
    assert beans
    r = client.post("/api/v1/listings", json={
        "farm_id": farm_id, "product_id": beans["id"], "title": "Beans Lot",
        "quantity_value": 50, "unit_code": "kg", "price_minor": 80000,
        "listing_type": "FIXED_PRICE"}, headers=auth_headers(farmer))
    listing = r.get_json()["listing"]
    r = client.post("/api/v1/offers", json={
        "listing_id": listing["id"], "quantity_value": 5, "price_minor": 80000},
        headers=auth_headers(buyer))
    offer_id = r.get_json()["offer"]["id"]
    r = client.post(f"/api/v1/offers/{offer_id}/accept", headers=auth_headers(farmer))
    order_id = r.get_json()["order"]["id"]

    # buyer cannot jump straight to COMPLETED
    r = client.post(f"/api/v1/orders/{order_id}/transition", json={"state": "COMPLETED"},
                    headers=auth_headers(buyer))
    assert r.status_code == 409
    assert r.get_json()["error"]["code"] in ("INVALID_ORDER_TRANSITION", "FORBIDDEN")

    # PAID cannot be set manually - payment system only
    r = client.post(f"/api/v1/orders/{order_id}/transition", json={"state": "PAID"},
                    headers=auth_headers(farmer))
    assert r.status_code == 403
    assert r.get_json()["error"]["code"] == "PAYMENT_SYSTEM_ONLY"
