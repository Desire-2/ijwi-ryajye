"""Shared fixtures: app against a dedicated Postgres test DB, clean tables per test."""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "backend"))

os.environ.setdefault("DATABASE_URL", "postgresql+psycopg2://ijwi:ijwi_dev@127.0.0.1:5433/ijwi_test")
os.environ.setdefault("SMS_PROVIDER", "test-capture")

import pytest  # noqa: E402

from app.app import create_app  # noqa: E402
from extensions import db as _db  # noqa: E402


def _truncate_all(engine):
    from sqlalchemy import text

    with engine.connect() as conn:
        rows = conn.execute(text(
            "SELECT tablename FROM pg_tables WHERE schemaname='public'")).fetchall()
        if not rows:
            return
        tables = ", ".join(f'"{r[0]}"' for r in rows)
        conn.execute(text("SET CONSTRAINTS ALL DEFERRED"))
        conn.execute(text(f"TRUNCATE TABLE {tables} RESTART IDENTITY CASCADE"))
        conn.commit()


def _seed_essentials(app):
    """Catalog, fees and system rows needed by API flows."""
    with app.app_context():
        from app.models.catalog import Product, ProductCategory
        from app.services.fee_service import ensure_default_fees

        if Product.query.count() == 0:
            crops = ProductCategory(name="Crops", slug="crops", icon="🌾")
            _db.session.add(crops)
            _db.session.flush()
            for name, slug in [("Maize", "maize"), ("Beans", "beans"), ("Rice", "rice"),
                               ("Irish Potatoes", "irish-potatoes"), ("Bananas", "bananas")]:
                _db.session.add(Product(name=name, slug=slug, category_id=crops.id))
            ensure_default_fees()
            from app.models.identity import User

            if User.query.get("platform-fee-sink") is None:
                _db.session.add(User(
                    id="platform-fee-sink", phone="+250000000000",
                    username="platform-fee-sink", full_name="Platform Fees (system)",
                    primary_role="SYSTEM", is_active=True))
            _db.session.commit()


@pytest.fixture(scope="session")
def app():
    application = create_app("testing")
    with application.app_context():
        _db.create_all()
        _seed_essentials(application)
    yield application


@pytest.fixture(autouse=True)
def clean_db(app):
    yield
    _db.session.remove()
    _truncate_all(_db.engine)
    _seed_essentials(app)


@pytest.fixture()
def client(app):
    return app.test_client()


# ---------- helpers ----------

def register_and_verify(client, phone, username, password="secret123", role="BUYER"):
    from app.services import auth_service

    r = client.post("/api/v1/auth/register", json={
        "phone": phone, "full_name": username.title(), "username": username,
        "password": password, "role": role})
    assert r.status_code == 201, r.get_json()
    sms = auth_service.TestCaptureSMSProvider.outbox[-1][1]
    import re

    code = re.search(r"code: (\d{6})", sms).group(1)
    r = client.post("/api/v1/auth/otp/verify", json={"phone": phone, "code": code})
    assert r.status_code == 200, r.get_json()
    tokens = r.get_json()["tokens"]
    return {"id": r0_user_id(client, tokens), **tokens}


def r0_user_id(client, tokens):
    h = {"Authorization": f"Bearer {tokens['access_token']}"}
    return client.get("/api/v1/users/me", headers=h).get_json()["user"]["id"]


def auth_headers(tokens):
    return {"Authorization": f"Bearer {tokens['access_token']}"}


@pytest.fixture()
def buyer(client):
    import uuid

    suffix = uuid.uuid4().hex[:8]
    return register_and_verify(client, f"+2507{uuid.uuid4().hex[:9]}", f"buyer{suffix}")


@pytest.fixture()
def farmer(client):
    import uuid

    suffix = uuid.uuid4().hex[:8]
    return register_and_verify(client, f"+2507{uuid.uuid4().hex[:9]}", f"farmer{suffix}", role="FARMER")
