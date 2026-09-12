"""Integration coverage for the Community foundation fixes:
follows (feed), polls, events, message-context, connections, blocking and
people discovery."""
import uuid

from tests.conftest import auth_headers, register_and_verify


def _user(client, role="FARMER"):
    suffix = uuid.uuid4().hex[:8]
    return register_and_verify(client, f"+2507{uuid.uuid4().hex[:9]}", f"u{suffix}", role=role)


def _set_crops(client, user, crops, district="Rulindo", region="Northern"):
    r = client.patch("/api/v1/users/me", json={
        "main_crops": crops, "district": district, "region": region,
        "visibility_location_exact": True}, headers=auth_headers(user))
    assert r.status_code == 200, r.get_json()
    return r.get_json()


class TestFollowFeed:
    def test_followed_feed_includes_followers_audience_posts(self, client, farmer, buyer):
        # buyer follows farmer; farmer posts with FOLLOWERS audience.
        r = client.post(f"/api/v1/users/{farmer['id']}/follow",
                        headers=auth_headers(buyer))
        assert r.status_code == 200 and r.get_json()["following"] is True
        # Idempotent follow does not toggle off.
        r = client.post(f"/api/v1/users/{farmer['id']}/follow",
                        headers=auth_headers(buyer))
        assert r.get_json()["following"] is True

        post = client.post("/api/v1/posts", json={
            "post_type": "text", "body_text": "row for the followed feed",
            "audience": "FOLLOWERS"}, headers=auth_headers(farmer)).get_json()["post"]

        # Follower sees it in the personalized feed.
        feed = client.get("/api/v1/posts", query_string={"feed": "for_you"},
                          headers=auth_headers(buyer)).get_json()
        assert any(p["id"] == post["id"] for p in feed["items"])

        # A stranger does not see FOLLOWERS-audience posts.
        stranger = _user(client)
        feed2 = client.get("/api/v1/posts", query_string={"feed": "for_you"},
                           headers=auth_headers(stranger)).get_json()
        assert all(p["id"] != post["id"] for p in feed2["items"])

    def test_unfollow_is_idempotent_removal(self, client, farmer, buyer):
        client.post(f"/api/v1/users/{farmer['id']}/follow", headers=auth_headers(buyer))
        r = client.post(f"/api/v1/users/{farmer['id']}/unfollow", headers=auth_headers(buyer))
        assert r.status_code == 200 and r.get_json()["following"] is False
        # Second unfollow stays unfollowed (does not re-follow).
        r = client.post(f"/api/v1/users/{farmer['id']}/unfollow", headers=auth_headers(buyer))
        assert r.get_json()["following"] is False


class TestPolls:
    def test_poll_lifecycle_creates_feed_post(self, client, farmer, buyer):
        from app.models.posts import Post

        r = client.post("/api/v1/polls", json={
            "question": "Best harvest month?",
            "options": ["May", "June", "July"],
            "multiple_choice": False,
            "ttl_hours": 24,
        }, headers=auth_headers(farmer))
        assert r.status_code == 201, r.get_json()
        poll = r.get_json()["poll"]
        assert poll["results"]["options"]
        assert not poll["results"]["closed"]

        # Feeding post is mirrored with a poll entity reference.
        with client.application.app_context():
            feed = Post.query.filter_by(
                author_id=farmer["id"], post_type="poll",
                entity_ref_type="poll", entity_ref_id=poll["id"]).first()
            assert feed is not None, "poll must appear in the feed as a Post"

        opt_a, opt_b = poll["results"]["options"][0], poll["results"]["options"][1]
        r = client.post(f"/api/v1/polls/{poll['id']}/vote",
                        json={"option_ids": [opt_a["id"]]}, headers=auth_headers(buyer))
        assert r.status_code == 200, r.get_json()
        assert r.get_json()["voted_option_ids"] == [opt_a["id"]]

        res = client.get(f"/api/v1/polls/{poll['id']}/results",
                         headers=auth_headers(farmer)).get_json()["results"]
        by_id = {o["id"]: o for o in res["options"]}
        assert by_id[opt_a["id"]]["votes"] == 1
        assert by_id[opt_a["id"]]["percent"] == 100
        assert by_id[opt_b["id"]]["votes"] == 0

        # Serialized feed post carries the poll payload for rendering.
        post_json = client.get(
            f"/api/v1/posts?post_type=poll&author_id={farmer['id']}",
            headers=auth_headers(buyer)).get_json()
        assert post_json["items"], "poll feed post should be listed"
        item = post_json["items"][0]
        assert item["poll"]["total_votes"] == 1

    def test_poll_rejects_too_few_options(self, client, farmer):
        r = client.post("/api/v1/polls", json={"question": "q", "options": ["only one"]},
                        headers=auth_headers(farmer))
        assert r.status_code == 422


class TestEvents:
    def test_create_upcoming_rsvp_and_feed_post(self, client, farmer, buyer):
        from app.models.posts import Post

        starts = "2030-06-01T09:00:00Z"
        r = client.post("/api/v1/events", json={
            "title": "Harvest market day",
            "description": "Buyers welcome",
            "starts_at": starts,
            "ends_at": "2030-06-01T17:00:00Z",
            "location_label": "Rulindo market",
        }, headers=auth_headers(farmer))
        assert r.status_code == 201, r.get_json()
        event = r.get_json()["event"]
        assert event["going_count"] == 0

        with client.application.app_context():
            feed = Post.query.filter_by(
                author_id=farmer["id"], post_type="event",
                entity_ref_type="event", entity_ref_id=event["id"]).first()
            assert feed is not None

        listed = client.get("/api/v1/events", headers=auth_headers(buyer)).get_json()
        assert any(e["id"] == event["id"] for e in listed["events"])

        r = client.post(f"/api/v1/events/{event['id']}/rsvp",
                        json={"response": "going"}, headers=auth_headers(buyer))
        assert r.status_code == 200 and r.get_json()["response"] == "going"

        listed2 = client.get("/api/v1/events", headers=auth_headers(buyer)).get_json()
        target = [e for e in listed2["events"] if e["id"] == event["id"]][0]
        assert target["going_count"] == 1

        # Mapped 'yes' shorthand and post serializer event payload.
        r = client.post(f"/api/v1/events/{event['id']}/rsvp",
                        query_string={"response": "YES"}, headers=auth_headers(farmer))
        assert r.get_json()["response"] == "going"


class TestMessageContext:
    def test_listing_context_starts_marketplace_conversation(self, client, farmer, buyer):
        r = client.post("/api/v1/conversations", json={
            "with_user_id": farmer["id"], "context": "listing"}, headers=auth_headers(buyer))
        assert r.status_code == 201, r.get_json()
        conv = r.get_json()["conversation"]
        assert conv["conversation_type"] == "MARKETPLACE"

        # Calling again reuses the same direct conversation (no duplicates).
        r2 = client.post("/api/v1/conversations", json={
            "with_user_id": farmer["id"], "context": "DIRECT"}, headers=auth_headers(buyer))
        assert r2.get_json()["conversation"]["id"] == conv["id"]


class TestConnections:
    def test_request_accept_list_remove(self, client, buyer):
        a = _user(client)
        b = _user(client)
        r = client.post(f"/api/v1/users/{b['id']}/connect", headers=auth_headers(a))
        assert r.status_code == 201, r.get_json()
        conn_id = r.get_json()["connection_id"]

        # b sees an incoming pending request.
        pending = client.get("/api/v1/connections/pending", headers=auth_headers(b)).get_json()
        assert any(p["connection_id"] == conn_id and p["direction"] == "incoming"
                   for p in pending["items"])
        # a sees it under status=PENDING with outgoing direction.
        mine = client.get("/api/v1/connections", query_string={"status": "PENDING"},
                          headers=auth_headers(a)).get_json()
        assert any(i["connection_id"] == conn_id and i["direction"] == "outgoing"
                   for i in mine["items"])

        # Can't accept your own request.
        r = client.post(f"/api/v1/connections/{conn_id}/accept", headers=auth_headers(a))
        assert r.status_code == 409

        r = client.post(f"/api/v1/connections/{conn_id}/accept", headers=auth_headers(b))
        assert r.status_code == 200 and r.get_json()["status"] == "ACCEPTED"

        card = client.get(f"/api/v1/users/{a['id']}", headers=auth_headers(b)).get_json()
        assert card["connection_status"] == "connected"

        conns = client.get("/api/v1/connections", headers=auth_headers(a)).get_json()
        assert any(i["connection_id"] == conn_id and i["status"] == "ACCEPTED"
                   for i in conns["items"])

        # Remove (unconnect).
        r = client.delete(f"/api/v1/connections/{b['id']}", headers=auth_headers(a))
        assert r.status_code == 200 and r.get_json()["removed"] is True
        card = client.get(f"/api/v1/users/{a['id']}", headers=auth_headers(b)).get_json()
        assert card["connection_status"] is None

    def test_decline_and_block(self, client):
        a = _user(client)
        b = _user(client)
        conn_id = client.post(f"/api/v1/users/{b['id']}/connect",
                              headers=auth_headers(a)).get_json()["connection_id"]
        r = client.post(f"/api/v1/connections/{conn_id}/decline", headers=auth_headers(b))
        assert r.status_code == 200 and r.get_json()["status"] == "DECLINED"

        # A blocked user cannot connect and disappears from discovery.
        client.post(f"/api/v1/users/{b['id']}/block", headers=auth_headers(a))
        r = client.post(f"/api/v1/users/{a['id']}/connect", headers=auth_headers(b))
        assert r.status_code == 403
        blocked = client.get("/api/v1/connections/blocked", headers=auth_headers(a)).get_json()
        assert any(i["id"] == b["id"] for i in blocked["items"])
        client.post(f"/api/v1/users/{b['id']}/unblock", headers=auth_headers(a))
        blocked = client.get("/api/v1/connections/blocked", headers=auth_headers(a)).get_json()
        assert not any(i["id"] == b["id"] for i in blocked["items"])

    def test_recommended_and_nearby(self, client):
        a = _user(client)
        _set_crops(client, a, ["Maize", "Beans"])

        # A candidate sharing crops + district.
        c = _user(client)
        _set_crops(client, c, ["Maize"])  # same crop, same district by default
        # A second candidate sharing only the region (different district).
        d = _user(client)
        _set_crops(client, d, ["Sorghum"], district="Gicumbi")

        rec = client.get("/api/v1/connections/recommended", headers=auth_headers(a)).get_json()
        recs = rec["recommendations"]
        ids = [r["id"] for r in recs]
        assert c["id"] in ids, "same-crop/district candidate must be recommended"
        # Stronger matches (shared crop/district) rank above region-only matches.
        c_rank = ids.index(c["id"])
        d_rank = ids.index(d["id"]) if d["id"] in ids else len(ids)
        assert c_rank < d_rank, "same-crop/district candidate should rank above region-only"
        c_row = next(r for r in recs if r["id"] == c["id"])
        assert "Maize" in c_row["reason"] or "district" in c_row["reason"].lower()

        # Nearby: c in the same district, d in the same region.
        near = client.get("/api/v1/connections/nearby", headers=auth_headers(a)).get_json()
        people = near["people"]
        c_row = next((p for p in people if p["id"] == c["id"]), None)
        assert c_row is not None and c_row["relation"] == "district"
        assert c_row["district"] == "Rulindo"  # privacy opt-in shown
        d_row = next((p for p in people if p["id"] == d["id"]), None)
        assert d_row is not None and d_row["relation"] == "region"
        # Coordinates are never exposed.
        assert all("latitude" not in p and "longitude" not in p for p in people)

    def test_recommended_omits_connected_people(self, client):
        a = _user(client)
        _set_crops(client, a, ["Maize"])
        c = _user(client)
        _set_crops(client, c, ["Maize"])

        client.post(f"/api/v1/users/{c['id']}/connect", headers=auth_headers(a))
        rec = client.get("/api/v1/connections/recommended", headers=auth_headers(a)).get_json()
        assert c["id"] not in [r["id"] for r in rec["recommendations"]]