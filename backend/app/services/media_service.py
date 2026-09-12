"""Core media service: recording assets, thumbnail processing, serving with
context-aware access control, attaching to feature contexts and orphan cleanup.

All media in the app flows through this module so upload/processing/serving
behaviour stays consistent across community, chat, status, listings, profile
and group/document features.
"""

import io
import secrets
from datetime import timedelta

from flask import current_app, request

from extensions import db
from app.errors import bad_request, forbidden, not_found
from app.models.base import utcnow
from app.models.media import CONTEXT_TYPES, MEDIA_TYPES, MediaAsset
from app.services import storage_service

_IMG_EXT = {"image/jpeg": ".jpg", "image/png": ".png", "image/webp": ".webp"}


# ---------------------------------------------------------------- helpers

def _content_to_media_type(content_type, category=""):
    ct = (content_type or "").lower()
    if ct.startswith("image/"):
        return "IMAGE"
    if ct.startswith("video/"):
        return "VIDEO"
    if ct.startswith("audio/"):
        return "AUDIO"
    if ct in ("application/pdf",) or "document" in ct or "spreadsheet" in ct or "word" in ct:
        return "DOCUMENT"
    if category in ("voice",):
        return "AUDIO"
    return "OTHER"


def _extract_image_meta(data: bytes):
    """Return (width, height) from image bytes without keeping EXIF (privacy)."""
    from PIL import Image, ImageOps

    try:
        with Image.open(io.BytesIO(data)) as img:
            width, height = ImageOps.exif_transpose(img).size
            return int(width), int(height)
    except Exception:
        return None, None


def _make_thumbnail(data: bytes, content_type: str):
    """Produce a JPEG thumbnail for images under an edge limit. Returns bytes or None."""
    from PIL import Image, ImageOps

    try:
        with Image.open(io.BytesIO(data)) as img:
            img = ImageOps.exif_transpose(img)
            img = img.convert("RGB")
            edge = int(current_app.config.get("MEDIA_THUMBNAIL_EDGE", 480))
            img.thumbnail((edge, edge), Image.LANCZOS)
            buf = io.BytesIO()
            quality = int(current_app.config.get("MEDIA_THUMBNAIL_QUALITY", 82))
            img.save(buf, "JPEG", quality=quality, optimize=True)
            return buf.getvalue()
    except Exception:
        return None


def _checksum(data: bytes):
    import hashlib

    return hashlib.sha256(data).hexdigest()


def _asset_json(asset, thumb=True):
    base = _base_url()
    data = {
        "id": asset.id,
        "owner_id": asset.owner_id,
        "category": asset.category,
        "media_type": asset.media_type,
        "file_name": asset.file_name,
        "storage_key": asset.storage_key,
        "content_type": asset.content_type,
        "size_bytes": asset.size_bytes,
        "width": asset.width,
        "height": asset.height,
        "duration_ms": asset.duration_ms,
        "status": asset.status,
        "context_type": asset.context_type,
        "context_id": asset.context_id,
        "url": f"{base}media/serve/{asset.storage_key}",
        "created_at": asset.created_at.isoformat() if asset.created_at else None,
    }
    if thumb and asset.thumbnail_key:
        data["thumbnail_url"] = f"{base}media/serve/{asset.thumbnail_key}"
    return data


def _base_url():
    try:
        return request.host_url
    except Exception:
        return "/"


# ---------------------------------------------------------------- lifecycle

def record_upload(user, storage_key, content_type="", category="image",
                  file_name="", size_bytes=0, duration_ms=0, checksum="",
                  status="READY"):
    """Persist a MediaAsset row for an already-stored file and generate a thumbnail."""
    media_type = _content_to_media_type(content_type, category)

    asset = MediaAsset(
        owner_id=user.id,
        category=category,
        media_type=media_type,
        file_name=(file_name or storage_key.split("/")[-1])[:255],
        storage_key=storage_key,
        content_type=content_type or "",
        size_bytes=size_bytes or 0,
        duration_ms=duration_ms or 0,
        checksum=checksum or "",
        status=status,
    )
    db.session.add(asset)

    if media_type == "IMAGE":
        try:
            data = storage_service._driver().get(storage_key)
        except Exception:
            data = None
        width, height = _extract_image_meta(data) if data else (None, None)
        asset.width, asset.height = width, height
        thumb = _make_thumbnail(data, content_type) if data else None
        if thumb:
            thumb_key = f"{category}s/{user.id}/thumb_{secrets.token_hex(8)}.jpg"
            try:
                storage_service._driver().put(thumb_key, thumb, "image/jpeg")
                asset.thumbnail_key = thumb_key
            except Exception:
                thumb_key = None

    db.session.flush()
    return asset


def get_asset_or_404(asset_id):
    asset = db.session.get(MediaAsset, asset_id)
    if asset is None or asset.is_deleted:
        raise not_found("Media asset not found")
    return asset


def find_asset_by_key(storage_key):
    if not storage_key:
        return None
    return MediaAsset.query.filter_by(storage_key=storage_key, deleted_at=None).first()


def delete_asset(user, asset_id, hard=False):
    asset = get_asset_or_404(asset_id)
    if asset.owner_id != user.id and "ADMIN" not in user.role_codes():
        raise forbidden("You can only delete media you own")
    if hard:
        _purge_storage(asset)
        db.session.delete(asset)
    else:
        asset.deleted_at = utcnow()
    db.session.flush()
    return asset


def _purge_storage(asset):
    driver = storage_service._driver()
    for key in (asset.storage_key, asset.thumbnail_key):
        if key:
            try:
                driver.delete(key)
            except Exception:
                pass


# ---------------------------------------------------------------- attach

def attach_asset(user, asset_id, context_type, context_id):
    if context_type not in CONTEXT_TYPES:
        raise bad_request(f"Unsupported context {context_type}. Allowed: {CONTEXT_TYPES}")
    if not context_id:
        raise bad_request("context_id is required")
    asset = get_asset_or_404(asset_id)
    if asset.owner_id != user.id and "ADMIN" not in user.role_codes():
        raise forbidden("You can only attach media you own")
    asset.context_type = context_type
    asset.context_id = context_id
    asset.expires_at = None
    db.session.flush()
    return asset


def resolve_keys(user, storage_keys):
    """Turn raw storage keys (new or legacy) into asset JSON entries."""
    if not storage_keys:
        return []
    out = []
    for key in storage_keys:
        if not key:
            continue
        asset = MediaAsset.query.filter_by(storage_key=key).first()
        if asset is not None and not asset.is_deleted:
            out.append(_asset_json(asset))
        else:
            out.append({"storage_key": key, "url": f"{_base_url()}media/serve/{key}"})
    return out


# ---------------------------------------------------------------- access control

def can_view(user, asset) -> bool:
    if asset.is_deleted:
        return False
    if user is not None and asset.owner_id == user.id:
        return True
    ctx_type = asset.context_type
    if ctx_type in ("LISTING", "POST", "POST_COMMENT", "CHANNEL_POST", "STATUS",
                    "PROFILE", "PRODUCT", "EVENT", "DELIVERY"):
        return True
    if ctx_type in ("MESSAGE", "CONVERSATION"):
        if user is None:
            return False
        from app.services.messaging_service import get_member

        return get_member(asset.context_id or asset.storage_key, user.id) is not None
    if ctx_type in ("GROUP", "GROUP_DOC"):
        if user is None:
            return False
        from app.models.group import GroupMember

        return GroupMember.query.filter_by(
            group_id=asset.context_id, user_id=user.id, left_at=None
        ).first() is not None
    if ctx_type == "COMMUNITY":
        if user is None:
            return False
        from app.models.community import CommunityMember

        return CommunityMember.query.filter_by(community_id=asset.context_id, user_id=user.id).first() is not None
    if ctx_type is None:
        # Detached assets are only visible to their owner until attached.
        return False
    return user is not None


def serve(user, storage_key, as_attachment=False):
    """Resolve a storage key to bytes with ACL; legacy keys are viewable by any
    authenticated user (matching current key-knowledge behaviour)."""
    asset = MediaAsset.query.filter(
        (MediaAsset.storage_key == storage_key) | (MediaAsset.thumbnail_key == storage_key)
    ).first()
    is_thumb = asset is not None and asset.thumbnail_key == storage_key
    if asset is not None and asset.is_deleted:
        raise not_found("Media not found")
    if asset is None:
        if user is None:
            raise forbidden("Authentication required")
        key = storage_key
        content_type = ""
    else:
        if not can_view(user, asset):
            raise forbidden("You do not have access to this media")
        key = storage_key
        content_type = "image/jpeg" if is_thumb else (asset.content_type or "")
    try:
        data = storage_service._driver().get(key)
    except FileNotFoundError:
        raise not_found("Media file not found")
    except Exception:
        raise not_found("Media file not found")
    if not content_type:
        for ct, magic in storage_service.ALLOWED_IMAGE.items():
            if data[:len(magic)] == magic:
                content_type = ct
                break
    return data, content_type or "application/octet-stream"


# ---------------------------------------------------------------- maintenance

def cleanup_orphans(grace_hours=None, commit=True):
    """Hard-delete unattached temporary media past their TTL, plus soft-deleted
    assets past the same grace period. Returns the number of rows removed."""
    grace = grace_hours or int(current_app.config.get("TEMP_MEDIA_TTL_HOURS", 24))
    cutoff = utcnow() - timedelta(hours=grace)
    row_count = 0
    driver = storage_service._driver()

    candidates = MediaAsset.query.filter(
        MediaAsset.deleted_at.isnot(None),
        MediaAsset.deleted_at < cutoff,
    ).all()
    for asset in candidates:
        for key in (asset.storage_key, asset.thumbnail_key):
            if key:
                try:
                    driver.delete(key)
                except Exception:
                    pass
        db.session.delete(asset)
        row_count += 1

    orphans = MediaAsset.query.filter(
        MediaAsset.deleted_at.is_(None),
        MediaAsset.context_type.is_(None),
        MediaAsset.context_id.is_(None),
        MediaAsset.expires_at.isnot(None),
        MediaAsset.expires_at < utcnow(),
    ).all()
    for asset in orphans:
        for key in (asset.storage_key, asset.thumbnail_key):
            if key:
                try:
                    driver.delete(key)
                except Exception:
                    pass
        db.session.delete(asset)
        row_count += 1

    if commit and row_count:
        db.session.commit()
    return row_count


def expire_detached(expires_at=None):
    """Mark never-attached uploads with an expiry so cleanup can reclaim them."""
    ts = expires_at or (utcnow() + timedelta(
        hours=int(current_app.config.get("TEMP_MEDIA_TTL_HOURS", 24))))
    MediaAsset.query.filter(
        MediaAsset.deleted_at.is_(None),
        MediaAsset.context_type.is_(None),
        MediaAsset.context_id.is_(None),
        MediaAsset.expires_at.is_(None),
    ).update({"expires_at": ts}, synchronize_session=False)
    db.session.flush()
    return True