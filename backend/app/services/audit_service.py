from flask import current_app, g, request

from extensions import db
from app.models.admin import AuditLog, RiskEvent
from app.services.security import client_ip


def record(actor, action, subject_type, subject_id, metadata=None):
    entry = AuditLog(
        actor_id=actor.id if actor is not None else None,
        actor_role=actor.primary_role if actor is not None else "SYSTEM",
        action=action,
        subject_type=subject_type,
        subject_id=str(subject_id),
        metadata_json=__import__("json").dumps(metadata or {}, default=str),
        ip_address=client_ip() if request else None,
        request_id=getattr(g, "request_id", None) if request else None,
    )
    db.session.add(entry)
    return entry


def record_risk(user_id, event_type, score_delta, detail=None, flag=False):
    event = RiskEvent(
        user_id=user_id,
        event_type=event_type,
        score_delta=score_delta,
        detail_json=__import__("json").dumps(detail or {}, default=str),
        flagged_for_review=flag,
    )
    db.session.add(event)
    return event
