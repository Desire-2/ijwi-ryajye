"""Media API: generic upload, metadata, file/thumbnail serving with ACL,
attach-to-context, delete and media maintenance.

This is the single backbone for every media upload in the app. Feature
endpoints keep owning their feature payloads, but files flow through here.
"""

import hashlib
import io

from flask import request, send_file
from flask_jwt_extended import jwt_required

from extensions import db
from app.errors import bad_request, forbidden, not_found
from app.services import media_service, storage_service
from app.services.security import get_current_user

_EXT_HINT = {
    "image/jpeg": ".jpg", "image/png": ".png", "image/webp": ".webp",
    "application/pdf": ".pdf", "audio/mp4": ".m4a", "audio/mpeg": ".mp3",
    "video/mp4": ".mp4", "video/webm": ".webm",
}


@jwt_required()
def upload_media():
    user = get_current_user()
    file = request.files.get("file")
    if file is None or not file.filename:
        raise bad_request("A 'file' part is required")

    category = (request.form.get("category") or "image").strip()
    if category not in ("image", "video", "voice", "document", "audio", "other"):
        raise bad_request("Unsupported upload category")

    data = file.read()
    if not data:
        raise bad_request("Empty file")
    content_type = storage_service.validate_upload(data, file.mimetype or "", category)
    file.stream.seek(0)
    stored = storage_service.store_upload(user, file, category)
    asset = media_service.record_upload(
        user,
        storage_key=stored["storage_key"],
        content_type=content_type,
        category=category,
        file_name=file.filename or "",
        size_bytes=stored["size_bytes"],
        duration_ms=int(request.form.get("duration_ms") or 0),
        checksum=hashlib.sha256(data).hexdigest(),
    )
    context_type = (request.form.get("context_type") or "").strip().upper()
    context_id = (request.form.get("context_id") or "").strip()
    if context_type and context_id:
        media_service.attach_asset(user, asset.id, context_type, context_id)
    else:
        media_service.expire_detached()
    db.session.commit()
    return media_service._asset_json(asset), 201


@jwt_required()
def get_asset(asset_id):
    user = get_current_user()
    asset = media_service.get_asset_or_404(asset_id)
    if not media_service.can_view(user, asset):
        raise forbidden("You do not have access to this media")
    return media_service._asset_json(asset)


def _file_response(data, content_type, file_name=""):
    ext = content_type.split("/")[-1].split("+")[0] or "bin"
    name = f"ijwi-{hashlib.md5(data[:64]).hexdigest()[:8]}{_EXT_HINT.get(content_type, '.' + ext)}"
    if request.args.get("download") == "1":
        return send_file(
            io.BytesIO(data), mimetype=content_type, as_attachment=True,
            download_name=file_name or name,
        )
    return send_file(io.BytesIO(data), mimetype=content_type)


@jwt_required()
def get_asset_file(asset_id):
    user = get_current_user()
    asset = media_service.get_asset_or_404(asset_id)
    if not media_service.can_view(user, asset):
        raise forbidden("You do not have access to this media")
    try:
        data = storage_service._driver().get(asset.storage_key)
    except Exception:
        raise not_found("Media file not found")
    return _file_response(data, asset.content_type or "application/octet-stream", asset.file_name)


@jwt_required()
def get_asset_thumbnail(asset_id):
    user = get_current_user()
    asset = media_service.get_asset_or_404(asset_id)
    if not media_service.can_view(user, asset):
        raise forbidden("You do not have access to this media")
    if not asset.thumbnail_key:
        raise not_found("This media has no thumbnail")
    try:
        data = storage_service._driver().get(asset.thumbnail_key)
    except Exception:
        raise not_found("Thumbnail not found")
    return _file_response(data, "image/jpeg")


@jwt_required()
def attach_media(asset_id):
    user = get_current_user()
    data = request.get_json(silent=True) or {}
    context_type = (data.get("context_type") or "").strip().upper()
    context_id = data.get("context_id")
    asset = media_service.attach_asset(user, asset_id, context_type, str(context_id))
    db.session.commit()
    return media_service._asset_json(asset)


@jwt_required()
def delete_media(asset_id):
    user = get_current_user()
    asset = media_service.delete_asset(user, asset_id)
    db.session.commit()
    return {"deleted": asset.id}


@jwt_required()
def serve_media(storage_key):
    """Serve a file by raw storage key (thumbnails share this route). ACL is
    enforced for asset-backed keys; legacy keys require authentication."""
    user = get_current_user()
    data, content_type = media_service.serve(user, storage_key)
    return _file_response(data, content_type)


@jwt_required()
def cleanup_media():
    user = get_current_user()
    if "ADMIN" not in user.role_codes():
        raise forbidden("Admin access required")
    removed = media_service.cleanup_orphans(commit=False)
    db.session.commit()
    return {"removed": removed}