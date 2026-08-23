import json

from flask import current_app

from extensions import db
from app.errors import bad_request, not_found
from app.models.base import utcnow
from app.models.admin import SyncOperation


def push_operations(user, operations):
    results = []
    for op in operations:
        client_op_id = op.get("client_op_id")
        if not client_op_id:
            raise bad_request("Each operation needs a client_op_id for idempotency")

        existing = SyncOperation.query.filter_by(client_op_id=client_op_id, user_id=user.id).first()
        if existing is not None:
            results.append({
                "client_op_id": client_op_id,
                "status": "DUPLICATE",
                "server_ref_type": existing.server_ref_type,
                "server_ref_id": existing.server_ref_id,
            })
            continue

        outcome = _apply_op(user, op)
        record = SyncOperation(
            user_id=user.id,
            client_op_id=str(client_op_id),
            op_type=op.get("op_type", "unknown"),
            payload_json=json.dumps(op.get("payload", {}), default=str)[:20000],
            result_state="APPLIED",
            server_ref_type=outcome.get("ref_type"),
            server_ref_id=outcome.get("ref_id"),
        )
        db.session.add(record)
        results.append({
            "client_op_id": client_op_id,
            "status": "APPLIED",
            **outcome,
        })
    return results


def _apply_op(user, op):
    from datetime import datetime

    def parse_dt(v):
        if isinstance(v, str) and v:
            try:
                return datetime.fromisoformat(v.replace("Z", "+00:00"))
            except Exception:
                return None
        return v

    op_type = op.get("op_type", "")
    payload = op.get("payload", {})

    if op_type == "message.send":
        from app.services.messaging_service import send_message

        message, duplicate = send_message(user, payload["conversation_id"], {
            "client_message_id": payload.get("client_message_id"),
            "message_type": payload.get("message_type", "text"),
            "body_text": payload.get("body_text", ""),
            "reply_to_message_id": payload.get("reply_to_message_id"),
            "entity_ref_type": payload.get("entity_ref_type"),
            "entity_ref_id": payload.get("entity_ref_id"),
            "attachments": payload.get("attachments", []),
        })
        return {"ref_type": "message", "ref_id": message.id}

    if op_type == "listing.create_draft":
        from app.services.listing_service import create_listing

        listing = create_listing(user, {**payload, "state": "ACTIVE"})
        return {"ref_type": "listing", "ref_id": listing.id}

    if op_type == "status.create":
        from app.services.status_service import create_status

        status = create_status(user, payload)
        return {"ref_type": "status", "ref_id": status.id}

    if op_type == "farm.crop.record":
        from app.models.farm import ProductionRecord

        rec = ProductionRecord(
            farm_id=payload["farm_id"],
            farm_crop_id=payload.get("farm_crop_id"),
            event_type=payload.get("event_type", "HARVESTED"),
            occurred_on=parse_dt(payload.get("occurred_on")) or datetime.now(),
            quantity_value=payload.get("quantity_value"),
            quantity_unit=payload.get("quantity_unit", "kg"),
            notes="synced offline" if payload.pop("offline_created", False) else "",
        )
        db.session.add(rec)
        db.session.flush()
        return {"ref_type": "production_record", "ref_id": rec.id}

    raise bad_request(f"Unsupported sync operation: {op_type}", "UNSUPPORTED_SYNC_OP")


def pull_updates(user, collections, cursors=None, limit=200):
    from app.models.intelligence import AdvisoryArticle, MarketPrice
    from app.models.marketplace import Listing
    from app.models.messaging import Conversation
    from app.models.notifications import Notification
    from app.models.order import Order

    cursors = cursors or {}
    out = {}

    fetchers = {
        "listings": lambda since: _updated(Listing, since, lambda q: q.filter(Listing.deleted_at.is_(None))),
        "conversations": lambda since: _updated(Conversation, since, None),
        "orders": lambda since: _updated(Order, since, None),
        "notifications": lambda since: _updated(Notification, since, None),
        "market_prices": lambda since: _updated(MarketPrice, since, None),
        "advisory": lambda since: _updated(AdvisoryArticle, since, None),
    }

    new_cursors = {}
    for collection in collections:
        fetcher = fetchers.get(collection)
        if fetcher is None:
            out[collection] = {"error": "unknown_collection"}
            continue
        since = cursors.get(collection)
        items = fetcher(since)
        max_ts = max((i.updated_at for i in items), default=None)
        out[collection] = {
            "items": [_slim(c) for c in items[:limit]],
            "count": len(items[:limit]),
            "truncated": len(items) > limit,
        }
        new_cursors[collection] = (max_ts.isoformat() if max_ts else (since or utcnow().isoformat()))

    return {"collections": out, "cursors": new_cursors, "server_time": utcnow().isoformat()}


def _updated(model, since_iso, extra_filter=None):
    from sqlalchemy import inspect as sa_inspect

    q = model.query
    if extra_filter:
        q = extra_filter(q)
    if since_iso:
        try:
            from datetime import datetime

            since = datetime.fromisoformat(since_iso.replace("Z", "+00:00"))
            q = q.filter(model.updated_at > since)
        except Exception:
            pass
    return q.order_by(model.updated_at.desc()).limit(500).all()


_SLIM_FIELDS = {
    "Listing": ["id", "title", "product_id", "price_minor", "currency_code", "available_quantity", "unit_code", "state"],
    "Conversation": ["id", "conversation_type", "title", "last_message_at", "server_sequence"],
    "Order": ["id", "order_number", "state", "total_amount_minor", "currency_code"],
    "Notification": ["id", "notification_type", "title", "body", "read_at", "subject_type", "subject_id"],
    "MarketPrice": ["id", "product_id", "region", "observed_on", "price_mid_minor", "unit_code", "currency_code"],
    "AdvisoryArticle": ["id", "title", "topic", "format", "language"],
}


def _slim(obj):
    fields = _SLIM_FIELDS.get(type(obj).__name__)
    data = obj.to_dict()
    if fields:
        return {k: data[k] for k in fields if k in data}
    return data
