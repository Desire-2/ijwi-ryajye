"""Full API smoke test: auth → browse → offer → accept → pay → deliver."""
import os
import re
import sys
import uuid

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ.setdefault("DATABASE_URL", "postgresql+psycopg2://ijwi:ijwi_dev@127.0.0.1:5433/ijwi_ryajye")

from app.app import create_app
from app.services import auth_service

app = create_app("development")
c = app.test_client()

phone = f"+25078{uuid.uuid4().hex[:8]}"
r = c.post("/api/v1/auth/register", json={
    "phone": phone, "full_name": "Smoke Buyer", "username": f"smoke{uuid.uuid4().hex[:6]}",
    "password": "secret123", "role": "BUYER"})
print("register:", r.status_code)
import io
import contextlib

buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    r2 = c.post("/api/v1/auth/otp/request", json={"phone": phone})
sms = buf.getvalue()
otp = re.search(r"code: (\d{6})", sms).group(1)
r = c.post("/api/v1/auth/otp/verify", json={"phone": phone, "code": otp})
print("verify otp:", r.status_code)
access = r.get_json()["tokens"]["access_token"]
H = {"Authorization": f"Bearer {access}"}

r = c.get("/api/v1/users/me", headers=H)
print("me:", r.status_code, r.get_json()["user"]["full_name"])

r = c.get("/api/v1/listings")
print("listings:", r.status_code, len(r.get_json().get("items", [])))
listing = [l for l in r.get_json()["items"] if l["title"].startswith("Fresh Maize")][0]

# seller login (seeded farmer claudine)
r = c.post("/api/v1/auth/login", json={"username": "claudine", "password": "farmer123"})
print("seller login:", r.status_code)
seller_H = {"Authorization": f"Bearer {r.get_json()['access_token']}"}

r = c.post("/api/v1/offers", json={
    "listing_id": listing["id"], "quantity_value": 10,
    "price_minor": listing["price_minor"], "delivery_option": "PICKUP"}, headers=H)
print("offer:", r.status_code, str(r.get_json())[:150])
offer_id = r.get_json()["offer"]["id"]

r = c.post(f"/api/v1/offers/{offer_id}/accept", headers=seller_H)
print("accept:", r.status_code, str(r.get_json())[:200])
order_id = r.get_json()["order"]["id"]

# initiate payment with mock provider
r = c.post(f"/api/v1/orders/{order_id}/payments", json={
    "provider": "mock", "method": "mobile_money", "phone": phone}, headers=H)
print("initiate payment:", r.status_code, str(r.get_json())[:150])
txn = r.get_json()["payment"]

# simulate provider webhook
import hashlib
import hmac
import time

body = f'{{"event_type":"transaction.succeeded","event_id":"evt-{uuid.uuid4().hex[:10]}","reference":"{txn["provider_reference"]}","amount_minor":{txn["amount_minor"]},"currency_code":"RWF"}}'
ts = str(int(time.time()))
secret = os.environ.get("PAYMENT_WEBHOOK_SECRETS", "mock:dev-webhook-secret").split(";")[0].split(":", 1)[1].encode()
sig = hmac.new(secret, ts.encode() + b"." + body.encode(), hashlib.sha256).hexdigest()
wh = c.post("/api/v1/payments/webhook/mock", data=body,
            content_type="application/json",
            headers={"X-Ijwi-Timestamp": ts, "X-Ijwi-Signature": sig})
print("webhook:", wh.status_code, wh.get_json())

r = c.post(f"/api/v1/orders/{order_id}/transition", json={"state": "PROCESSING"}, headers=seller_H)
print("-> PROCESSING:", r.status_code)
r = c.post(f"/api/v1/orders/{order_id}/transition", json={"state": "READY_FOR_PICKUP"}, headers=seller_H)
print("-> READY_FOR_PICKUP:", r.status_code)

# delivery flow
r = c.post("/api/v1/delivery-requests", json={
    "order_id": order_id, "pickup_region": "Northern", "destination_region": "Kigali",
    "quantity_value": 10, "unit_code": "kg"}, headers=H)
print("delivery request:", r.status_code, str(r.get_json())[:120])
dr_id = r.get_json()["delivery_request"]["id"]

r = c.post("/api/v1/auth/login", json={"username": "eric", "password": "logistics1"})
logistics_H = {"Authorization": f"Bearer {r.get_json()['access_token']}"}
r = c.post(f"/api/v1/delivery-requests/{dr_id}/quotes",
           json={"price_minor": 5000}, headers=logistics_H)
print("quote:", r.status_code, str(r.get_json())[:120])
quote_id = r.get_json()["quote"]["id"]
r = c.post(f"/api/v1/quotes/{quote_id}/accept", headers=H)
print("accept quote:", r.status_code)
delivery_id = r.get_json()["delivery"]["id"]

for state in ("PICKUP_SCHEDULED", "PICKED_UP", "IN_TRANSIT", "DELIVERED"):
    r = c.post(f"/api/v1/deliveries/{delivery_id}/advance", json={"state": state}, headers=logistics_H)
    print(f"delivery -> {state}:", r.status_code)

r = c.post(f"/api/v1/orders/{order_id}/transition", json={"state": "COMPLETED"}, headers=H)
print("-> COMPLETED:", r.status_code, str(r.get_json())[:100])

# reviews + wallet
r = c.post(f"/api/v1/orders/{order_id}/reviews", json={
    "subject_role": "farmer", "overall_rating": 5, "comment": "Great maize!"}, headers=H)
print("review:", r.status_code)

r = c.get("/api/v1/wallet", headers=seller_H)
print("seller wallet:", r.status_code, r.get_json())

print("\nSMOKE COMPLETE")
