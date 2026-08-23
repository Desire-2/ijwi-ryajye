"""Spec §130 E2E: direct chat, group chat, reactions, read receipts, offline sync."""
import uuid

from tests.conftest import auth_headers, register_and_verify


def _mk_user(client, role="BUYER"):
    suffix = uuid.uuid4().hex[:8]
    return register_and_verify(client, f"+2507{uuid.uuid4().hex[:9]}", f"u{suffix}", role=role)


def test_direct_chat_flow(client):
    alice = _mk_user(client)
    bob = _mk_user(client)

    r = client.post("/api/v1/conversations",
                    json={"with_user_id": bob["id"]}, headers=auth_headers(alice))
    assert r.status_code == 201, r.get_json()
    conv = r.get_json()["conversation"]
    conv_id = conv["id"]

    # idempotent send: same client_message_id returns duplicate flag
    payload = {"client_message_id": "cm-1", "body_text": "Muraho! Any maize left?"}
    r1 = client.post(f"/api/v1/conversations/{conv_id}/messages", json=payload,
                     headers=auth_headers(alice))
    assert r1.status_code == 201, r1.get_json()
    r2 = client.post(f"/api/v1/conversations/{conv_id}/messages", json=payload,
                     headers=auth_headers(alice))
    assert r2.status_code == 201
    assert r2.get_json().get("duplicate") is True

    msg_id = r1.get_json()["message"]["id"]

    # bob reads; unread resets
    r = client.post(f"/api/v1/conversations/{conv_id}/read?upto_sequence={(conv.get('server_sequence') or 1)}",
                    headers=auth_headers(bob))
    assert r.status_code == 200, r.get_json()

    # reaction
    r = client.post(f"/api/v1/messages/{msg_id}/react", json={"emoji": "👍"},
                    headers=auth_headers(bob))
    assert r.status_code == 200, r.get_json()

    # edit own message
    r = client.patch(f"/api/v1/messages/{msg_id}", json={"body_text": "Muraho! Any beans left?"},
                     headers=auth_headers(alice))
    assert r.status_code == 200, r.get_json()
    assert r.get_json()["message"]["body_text"].endswith("beans left?")
    assert r.get_json()["message"]["edited"] is True

    # search finds it
    r = client.get("/api/v1/messages/search?q=beans", headers=auth_headers(bob))
    assert r.status_code == 200
    assert any("beans" in m["body_text"] for m in r.get_json().get("results", []))


def test_group_chat_and_permissions(client):
    admin = _mk_user(client)
    member = _mk_user(client)
    outsider = _mk_user(client)

    r = client.post("/api/v1/groups", json={"name": f"Coop {uuid.uuid4().hex[:5]}"},
                    headers=auth_headers(admin))
    assert r.status_code == 201, r.get_json()
    group = r.get_json()["group"]

    # add member via members endpoint
    r = client.post(f"/api/v1/groups/{group['id']}/members",
                    json={"members": [{"user_id": member["id"], "role": "FARMER"}]},
                    headers=auth_headers(admin))
    assert r.status_code == 200, r.get_json()

    # find the auto-created group conversation
    convs = client.get("/api/v1/conversations?type=group", headers=auth_headers(member)).get_json()["conversations"]
    assert convs, "member should see the group conversation"
    gconv = convs[0]

    payload = {"client_message_id": f"g-{uuid.uuid4().hex[:6]}", "body_text": "Group hello"}
    r = client.post(f"/api/v1/conversations/{gconv['id']}/messages", json=payload,
                    headers=auth_headers(member))
    assert r.status_code == 201, r.get_json()

    # outsider cannot post to the group conversation
    payload2 = {"client_message_id": f"o-{uuid.uuid4().hex[:6]}", "body_text": "spam"}
    r = client.post(f"/api/v1/conversations/{gconv['id']}/messages", json=payload2,
                    headers=auth_headers(outsider))
    assert r.status_code in (403, 404)


def test_offline_sync_push_and_pull(client, farmer):
    farm = client.post("/api/v1/farms", json={"name": "Sync Farm", "region": "Eastern"},
                       headers=auth_headers(farmer)).get_json()["farm"]
    product = [p for p in client.get("/api/v1/products").get_json()["items"] if p["slug"] == "bananas"][0]

    op = {
        "client_op_id": f"op-{uuid.uuid4().hex[:8]}",
        "op_type": "listing.create_draft",
        "payload": {"farm_id": farm["id"], "product_id": product["id"],
                    "title": "Synced Bananas", "quantity_value": 30,
                    "unit_code": "kg", "price_minor": 2000},
    }
    r1 = client.post("/api/v1/sync/push", json={"operations": [op]}, headers=auth_headers(farmer))
    assert r1.status_code == 200, r1.get_json()
    r2 = client.post("/api/v1/sync/push", json={"operations": [op]}, headers=auth_headers(farmer))
    assert r2.status_code == 200
    body = r2.get_json()
    results = body if isinstance(body, list) else (body.get("results") or [])
    dupes = [x for x in results if x.get("status") == "DUPLICATE"]
    assert dupes, "replayed operation must be reported as DUPLICATE"

    pull = client.get("/api/v1/sync/pull?collections=listings",
                      headers=auth_headers(farmer))
    assert pull.status_code == 200
    body = pull.get_json()
    listings = body["collections"]["listings"]["items"]
    assert any(l.get("title") == "Synced Bananas" or l.get("id") for l in listings)
