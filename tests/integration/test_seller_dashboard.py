"""Seller dashboard endpoint: every metric must come from the seller's own real rows."""
import hashlib
import hmac
import json
import time
import uuid

from tests.conftest import auth_headers


def _sig(secret, ts, body):
    return hmac.new(secret, ts.encode() + b"." + body.encode(), hashlib.sha256).hexdigest()


def test_seller_dashboard_reflects_real_activity(client, buyer, farmer):
    app = client.application

    # Fresh dashboard is all zeros.
    dash = client.get("/api/v1/seller/dashboard", headers=auth_headers(farmer)).get_json()
    assert dash["summary"]["listings_total"] == 0
    assert dash["summary"]["total_views"] == 0
    assert dash["wallet"]["available_minor"] == 0

    farm = client.post("/api/v1/farms", json={"name": "Dash Farm", "region": "Northern"},
                       headers=auth_headers(farmer)).get_json()["farm"]
    maize = [p for p in client.get("/api/v1/products").get_json()["items"] if p["slug"] == "maize"][0]
    listing = client.post("/api/v1/listings", json={
        "farm_id": farm["id"], "product_id": maize["id"], "title": "Dash Maize",
        "quantity_value": 100, "unit_code": "kg", "price_minor": 50000,
        "listing_type": "FIXED_PRICE"}, headers=auth_headers(farmer)).get_json()["listing"]

    # Buyer views the listing detail -> real view count.
    assert client.get(f"/api/v1/listings/{listing['id']}",
                      headers=auth_headers(buyer)).status_code == 200

    # Buyer offers 20 kg @ 45000; farmer counters @ 48000 -> one offer stays pending.
    offer = client.post("/api/v1/offers", json={
        "listing_id": listing["id"], "quantity_value": 20, "price_minor": 45000},
        headers=auth_headers(buyer)).get_json()["offer"]
    counter = client.post(f"/api/v1/offers/{offer['id']}/counter",
                          json={"price_minor": 48000},
                          headers=auth_headers(farmer)).get_json()["offer"]

    dash = client.get("/api/v1/seller/dashboard", headers=auth_headers(farmer)).get_json()
    s = dash["summary"]
    assert s["listings_total"] == 1 and s["listings_active"] == 1
    assert s["total_views"] == 1  # buyer's listing view counted
    assert s["offers_total"] == 2  # original + counter
    assert s["offers_pending"] == 1
    assert s["orders_total"] == 0 and s["gross_sales_minor"] == 0

    row = dash["listings"][0]
    assert row["id"] == listing["id"]
    assert row["view_count"] == 1
    assert row["offers_pending"] == 1
    assert row["orders_total"] == 0

    ro = dash["recent_offers"]
    assert len(ro) == 2
    assert any(o["id"] == counter["id"] for o in ro)
    assert ro[0]["listing"]["id"] == listing["id"]
    assert ro[0]["buyer"]["id"] == buyer["id"]

    # Buyer accepts the counter -> order created and paid -> revenue lands.
    order = client.post(f"/api/v1/offers/{counter['id']}/accept",
                        headers=auth_headers(buyer))
    assert order.status_code == 201, order.get_json()
    order_id = order.get_json()["order"]["id"]

    pay = client.post(f"/api/v1/orders/{order_id}/payments",
                      json={"provider": "mock", "method": "mobile_money"},
                      headers=auth_headers(buyer)).get_json()["payment"]
    secret = app.config["PAYMENT_WEBHOOK_SECRETS"].split(";")[0].split(":", 1)[1].encode()
    body = json.dumps({"event_id": f"evt-{uuid.uuid4().hex[:8]}",
                       "reference": pay["provider_reference"], "state": "SUCCEEDED"})
    ts = str(int(time.time()))
    wh = client.post("/api/v1/payments/webhook/mock", data=body,
                     content_type="application/json",
                     headers={"X-Ijwi-Timestamp": ts, "X-Ijwi-Signature": _sig(secret, ts, body)})
    assert wh.get_json().get("payment_state") == "SUCCEEDED"

    dash = client.get("/api/v1/seller/dashboard", headers=auth_headers(farmer)).get_json()
    s = dash["summary"]
    total = 20 * 48_000  # 20 kg at the countered 48,000/kg
    fee = round(total * 0.025)  # default 250 bps platform fee
    assert s["offers_pending"] == 0
    assert s["orders_total"] == 1 and s["orders_open"] == 1
    assert s["gross_sales_minor"] == total
    assert s["fees_minor"] == fee
    assert s["net_revenue_minor"] == total - fee

    assert dash["listings"][0]["orders_total"] == 1
    assert dash["listings"][0]["sold_value_minor"] == total

    # Seller was credited net proceeds in escrow/release.
    assert dash["wallet"]["total_earned_minor"] == total - fee
    assert dash["wallet"]["available_minor"] == total - fee

    rord = dash["recent_orders"]
    assert len(rord) == 1
    assert rord[0]["id"] == order_id
    assert rord[0]["buyer"]["id"] == buyer["id"]
    assert rord[0]["listing"]["id"] == listing["id"]
    assert rord[0]["state"] == "PAID"
