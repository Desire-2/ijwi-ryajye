"""Media backbone integration tests: generic upload, thumbnails, ACL serving,
attach, delete and legacy /uploads route."""
import io

from tests.conftest import auth_headers


def _png_bytes():
    from PIL import Image

    buf = io.BytesIO()
    Image.new("RGB", (120, 80), (220, 120, 60)).save(buf, "PNG")
    return buf.getvalue()


PNG_1PX = _png_bytes()


def _upload(client, tokens, category="image", name="photo.png", extra=None):
    headers = auth_headers(tokens)
    form = {"category": category}
    if extra:
        form.update(extra)
    return client.post(
        "/api/v1/media/upload",
        data={**form, "file": (io.BytesIO(PNG_1PX), name)},
        content_type="multipart/form-data",
        headers=headers,
    )


def test_upload_creates_asset_with_thumbnail(client, buyer):
    r = _upload(client, buyer)
    assert r.status_code == 201, r.get_json()
    body = r.get_json()
    assert body["media_type"] == "IMAGE"
    assert body["storage_key"].startswith("images/")
    assert body["url"].endswith(body["storage_key"])
    assert body["thumbnail_url"], "image upload should generate a thumbnail"
    assert body["width"] == 120 and body["height"] == 80
    h = auth_headers(buyer)

    meta = client.get(f"/api/v1/media/{body['id']}", headers=h)
    assert meta.status_code == 200
    assert meta.get_json()["id"] == body["id"]

    thumb_key = body["thumbnail_url"].split("/media/serve/")[-1]
    thumb = client.get(f"/api/v1/media/serve/{thumb_key}", headers=h)
    assert thumb.status_code == 200
    assert thumb.content_type.startswith("image/jpeg")


def test_upload_attaches_context_inline(client, buyer):
    r = _upload(client, buyer, extra={"context_type": "POST", "context_id": "p123"})
    assert r.status_code == 201
    assert r.get_json()["context_type"] == "POST"
    assert r.get_json()["context_id"] == "p123"


def test_serve_acl_denies_foreign_private_and_allows_public(client, buyer, farmer):
    r = _upload(client, buyer, extra={"context_type": "POST", "context_id": "pub1"})
    key = r.get_json()["storage_key"]
    assert client.get(f"/api/v1/media/serve/{key}", headers=auth_headers(farmer)).status_code == 200
    # not attached -> auth required view (owner only effectively)
    r2 = _upload(client, buyer)
    key2 = r2.get_json()["storage_key"]
    assert client.get(f"/api/v1/media/serve/{key2}", headers=auth_headers(farmer)).status_code == 403


def test_attach_and_delete(client, buyer):
    r = _upload(client, buyer)
    asset_id = r.get_json()["id"]
    h = auth_headers(buyer)
    att = client.post(f"/api/v1/media/{asset_id}/attach", json={
        "context_type": "LISTING", "context_id": "L-1"}, headers=h)
    assert att.status_code == 200
    assert att.get_json()["context_type"] == "LISTING"
    d = client.delete(f"/api/v1/media/{asset_id}", headers=h)
    assert d.status_code == 200
    assert client.get(f"/api/v1/media/{asset_id}", headers=h).status_code == 404


def test_legacy_upload_route_still_works_and_records_asset(client, buyer):
    h = auth_headers(buyer)
    r = client.post(
        "/api/v1/uploads/image",
        data={"file": (io.BytesIO(PNG_1PX), "legacy.png")},
        content_type="multipart/form-data",
        headers=h,
    )
    assert r.status_code == 201, r.get_json()
    body = r.get_json()
    assert "storage_key" in body and body["id"]
    assert body["thumbnail_url"]
    assert client.get(f"/api/v1/media/serve/{body['storage_key']}", headers=h).status_code == 200


def test_cleanup_removes_expired_orphans(client, buyer, app):
    r = _upload(client, buyer)
    asset_id = r.get_json()["id"]
    from datetime import timedelta

    from extensions import db
    from app.models.base import utcnow
    from app.models.media import MediaAsset
    from app.services import media_service

    with app.app_context():
        asset = db.session.get(MediaAsset, asset_id)
        asset.expires_at = utcnow() - timedelta(hours=1)
        db.session.commit()
        removed = media_service.cleanup_orphans()
    assert removed >= 1
    with app.app_context():
        assert db.session.get(MediaAsset, asset_id) is None


def test_unsupported_category_and_bad_magic(client, buyer):
    r = client.post(
        "/api/v1/media/upload",
        data={"category": "bogus", "file": (io.BytesIO(b"nope\n"), "x.bin")},
        content_type="multipart/form-data",
        headers=auth_headers(buyer),
    )
    assert r.status_code == 400
    r2 = client.post(
        "/api/v1/media/upload",
        data={"category": "image", "file": (io.BytesIO(b"not-an-image"), "x.png")},
        content_type="multipart/form-data",
        headers=auth_headers(buyer),
    )
    assert r2.status_code == 400