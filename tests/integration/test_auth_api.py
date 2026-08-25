import re
import uuid

from tests.conftest import auth_headers, register_and_verify


def test_register_issues_otp(client):
    phone = f"+2507{uuid.uuid4().hex[:9]}"
    r = client.post("/api/v1/auth/register", json={
        "phone": phone, "full_name": "Test", "username": f"u{uuid.uuid4().hex[:6]}",
        "password": "pw123456", "role": "BUYER"})
    assert r.status_code == 201
    body = r.get_json()
    assert body["otp_sent"] is True


def test_wrong_otp_rejected_then_correct_works(client):
    from app.services import auth_service

    phone = f"+2507{uuid.uuid4().hex[:9]}"
    client.post("/api/v1/auth/register", json={
        "phone": phone, "full_name": "Test", "username": f"u{uuid.uuid4().hex[:6]}",
        "password": "pw123456", "role": "BUYER"})
    sms = auth_service.TestCaptureSMSProvider.outbox[-1][1]
    code = re.search(r"code: (\d{6})", sms).group(1)
    r = client.post("/api/v1/auth/otp/verify", json={"phone": phone, "code": "000000"})
    assert r.status_code == 401
    r = client.post("/api/v1/auth/otp/verify", json={"phone": phone, "code": code})
    assert r.status_code == 200


def test_me_requires_jwt(client):
    assert client.get("/api/v1/users/me").status_code == 401


def test_refresh_rotation(client, buyer):
    r = client.post("/api/v1/auth/refresh",
                    headers={"Authorization": f"Bearer {buyer['refresh_token']}"})
    assert r.status_code == 200, r.get_json()
    body = r.get_json()
    assert "access_token" in body and "refresh_token" in body


def test_login_with_username(client):
    import uuid

    username = f"log{uuid.uuid4().hex[:6]}"
    tokens = register_and_verify.__wrapped__(client) if False else None
    phone = f"+2507{uuid.uuid4().hex[:9]}"
    client.post("/api/v1/auth/register", json={
        "phone": phone, "full_name": "Login User", "username": username,
        "password": "pw123456", "role": "FARMER"})
    r = client.post("/api/v1/auth/login", json={"username": username, "password": "pw123456"})
    assert r.status_code == 200
    assert "access_token" in r.get_json()
