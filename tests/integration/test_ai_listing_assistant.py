"""Contract test for POST /api/v1/ai/extract-listing.

The Create Listing wizard's AI assist sheet depends on the exact envelope
returned here (response.draft.draft carries the extracted fields), so this
pins the shape with a stubbed provider instead of requiring a live AI key.
"""
from tests.conftest import auth_headers


def test_ai_extract_listing_returns_reviewable_draft(client, farmer, monkeypatch):
    from app.services import ai_service

    class _FakeAI:
        name = "fake"

        def chat(self, system_prompt, user_content, temperature=0.2, json_mode=False):
            return (
                '{"title": "Fresh Tomatoes", "product_guess": "Tomatoes", '
                '"quantity_value": 500, "unit_code": "kg", '
                '"availability": "ready", "price_hint_minor": 45000, '
                '"currency_guess": "RWF"}'
            )

    monkeypatch.setattr(ai_service, "get_ai_provider", lambda: _FakeAI())

    r = client.post(
        "/api/v1/ai/extract-listing",
        json={"text": "I have 500 kg of fresh tomatoes in Huye, ready now"},
        headers=auth_headers(farmer),
    )
    assert r.status_code == 200, r.get_json()
    body = r.get_json()
    assert body["requires_confirmation"] is True
    # Envelope nesting: the service result sits under response.draft.
    draft = body["draft"]["draft"]
    assert draft["title"] == "Fresh Tomatoes"
    assert draft["product_guess"] == "Tomatoes"
    assert draft["quantity_value"] == 500
    assert draft["unit_code"] == "kg"
    assert draft["availability"] == "ready"
    assert draft["price_hint_minor"] == 45000
    assert draft["currency_guess"] == "RWF"
    assert body["draft"]["requires_user_confirmation"] is True


def test_ai_extract_listing_requires_auth_and_text(client, farmer):
    r = client.post("/api/v1/ai/extract-listing", json={"text": "hello"})
    assert r.status_code == 401

    r = client.post("/api/v1/ai/extract-listing", json={},
                    headers=auth_headers(farmer))
    assert r.status_code == 422
