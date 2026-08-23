"""Failure paths: expired auctions, blocked users, banned members, self-trading, spam."""
import uuid
from datetime import timedelta

from tests.conftest import auth_headers, register_and_verify


def _mk_user(client, role="BUYER"):
    suffix = uuid.uuid4().hex[:8]
    return register_and_verify(client, f"+2507{uuid.uuid4().hex[:9]}", f"u{suffix}", role=role)


def _listing(client, farmer, product_slug="maize", qty=100, price=50000):
    fr = client.post("/api/v1/farms", json={"name": "Test Farm", "region": "Kigali"},
                     headers=auth_headers(farmer))
    assert fr.status_code == 201, fr.get_json()
    farm = fr.get_json()["farm"]
    product = [p for p in client.get("/api/v1/products").get_json()["items"]
               if p["slug"] == product_slug][0]
    r = client.post("/api/v1/listings", json={
        "farm_id": farm["id"], "product_id": product["id"],
        "title": f"L-{uuid.uuid4().hex[:6]}", "quantity_value": qty,
        "unit_code": "kg", "price_minor": price, "listing_type": "FIXED_PRICE"},
        headers=auth_headers(farmer))
    assert r.status_code == 201, r.get_json()
    return r.get_json()["listing"]


def test_bid_on_fixed_price_listing_rejected(client, buyer, farmer):
    listing = _listing(client, farmer)
    r = client.post("/api/v1/bids", json={
        "listing_id": listing["id"], "amount_minor": 50000, "quantity_value": 5},
        headers=auth_headers(buyer))
    assert r.status_code in (400, 409)
    assert r.get_json()["error"]["code"] in ("USE_BIDDING", "NOT_AN_AUCTION", "BAD_REQUEST", "CONFLICT")


def test_offer_on_own_listing_rejected(client, farmer):
    listing = _listing(client, farmer)
    r = client.post("/api/v1/offers", json={
        "listing_id": listing["id"], "quantity_value": 5, "price_minor": 50000},
        headers=auth_headers(farmer))
    assert r.status_code == 403
    assert r.get_json()["error"]["code"] == "SELF_OFFER"


def test_blocked_users_cannot_message(client):
    alice = _mk_user(client)
    mallory = _mk_user(client)

    # find or create a direct conversation between them
    conv = client.post("/api/v1/conversations",
                       json={"with_user_id": mallory["id"]},
                       headers=auth_headers(alice)).get_json()["conversation"]

    # alice blocks mallory
    from extensions import db
    from app.models.identity import BlockedUser
    from app.app import create_app as _ca  # noqa: F401

    app = client.application
    with app.app_context():
        db.session.add(BlockedUser(blocker_id=alice["id"], blocked_id=mallory["id"]))
        db.session.commit()

    payload = {"client_message_id": f"b-{uuid.uuid4().hex[:6]}", "body_text": "hello?"}
    r = client.post(f"/api/v1/conversations/{conv['id']}/messages", json=payload,
                    headers=auth_headers(mallory))
    assert r.status_code in (403, 400)


def test_banned_group_member_cannot_post(client):
    admin = _mk_user(client, role="FARMER")
    member = _mk_user(client)

    group = client.post("/api/v1/groups", json={"name": f"G{uuid.uuid4().hex[:5]}"},
                        headers=auth_headers(admin)).get_json()["group"]
    client.post(f"/api/v1/groups/{group['id']}/members",
                json={"members": [{"user_id": member["id"], "role": "BUYER"}]},
                headers=auth_headers(admin))

    convs = client.get("/api/v1/conversations?type=group",
                       headers=auth_headers(member)).get_json()["conversations"]
    gconv = convs[0]

    # ban the member
    r = client.post(f"/api/v1/groups/{group['id']}/members/{member['id']}/ban",
                    json={"reason": "spam"}, headers=auth_headers(admin))
    assert r.status_code == 200

    r = client.post(f"/api/v1/conversations/{gconv['id']}/messages",
                    json={"client_message_id": f"x-{uuid.uuid4().hex[:6]}",
                          "body_text": "still here?"},
                    headers=auth_headers(member))
    assert r.status_code in (403, 400)
    assert "ban" in r.get_json()["error"]["message"].lower() or \
        r.get_json()["error"]["code"] in ("FORBIDDEN", "GROUP_PERMISSION_DENIED")


def test_duplicate_webhook_events_are_idempotent(client, buyer, farmer):
    """Same event_id replayed must not double-credit the wallet."""
    import hashlib
    import hmac
    import json
    import time

    app = client.application
    listing = _listing(client, farmer, qty=10)
    offer = client.post("/api/v1/offers", json={
        "listing_id": listing["id"], "quantity_value": 10,
        "price_minor": listing["price_minor"]}, headers=auth_headers(buyer)).get_json()["offer"]
    order = client.post(f"/api/v1/offers/{offer['id']}/accept",
                        headers=auth_headers(farmer)).get_json()["order"]

    pay = client.post(f"/api/v1/orders/{order['id']}/payments",
                      json={"provider": "mock", "method": "mobile_money"},
                      headers=auth_headers(buyer)).get_json()["payment"]
    secret = app.config["PAYMENT_WEBHOOK_SECRETS"].split(";")[0].split(":", 1)[1].encode()
    body = json.dumps({"event_id": "evt-dup-test", "reference": pay["provider_reference"]})
    ts = str(int(time.time()))
    sig = hmac.new(secret, ts.encode() + b"." + body.encode(), hashlib.sha256).hexdigest()
    for _ in range(2):
        client.post("/api/v1/payments/webhook/mock", data=body,
                    content_type="application/json",
                    headers={"X-Ijwi-Timestamp": ts, "X-Ijwi-Signature": sig})
    wallet = client.get("/api/v1/wallet", headers=auth_headers(farmer)).get_json()
    net = 10 * listing["price_minor"]
    assert wallet["available_minor"] == int(net * 0.975)
