import json
from datetime import timedelta

from flask import current_app

from extensions import db, limiter, realtime
from app.errors import forbidden
from app.models.admin import RiskEvent
from app.models.identity import User
from app.models.notifications import Notification, NotificationBatch, NotificationPreference
from app.models.base import utcnow


class PushAdapter:
    def send(self, device_token, title, body, data=None):
        raise NotImplementedError


class ConsolePushAdapter(PushAdapter):
    def send(self, device_token, title, body, data=None):
        print(f"[push] token={device_token[:12]}…: {title} | {body}")


class FcmPushAdapter(PushAdapter):
    def __init__(self, server_key):
        self.server_key = server_key

    def send(self, device_token, title, body, data=None):
        import requests

        requests.post(
            "https://fcm.googleapis.com/fcm/send",
            json={
                "to": device_token,
                "notification": {"title": title, "body": body},
                "data": {k: str(v) for k, v in (data or {}).items()},
            },
            headers={"Authorization": f"key={self.server_key}"},
            timeout=10,
        )


def push_adapter():
    key = current_app.config.get("PUSH_NOTIFICATION_KEYS")
    if key and not key.startswith(("changeme", "")):
        return FcmPushAdapter(key)
    return ConsolePushAdapter()


def notify(
    user_id,
    notification_type,
    title,
    body="",
    subject_type=None,
    subject_id=None,
    batch_key=None,
    commit=True,
):
    pref = NotificationPreference.query.filter_by(
        user_id=user_id, notification_type=notification_type
    ).first()
    if pref is not None:
        if not pref.enabled:
            return None

    if batch_key:
        batch = NotificationBatch.query.filter_by(user_id=user_id, batch_key=batch_key).first()
        if batch is None:
            batch = NotificationBatch(user_id=user_id, batch_key=batch_key, count=0)
            db.session.add(batch)
            db.session.flush()
        batch.count += 1
        batch.summary_title = f"{batch.count or 1} new {batch_key.replace('_', ' ')} updates"

    notification = Notification(
        user_id=user_id,
        notification_type=notification_type,
        title=title,
        body=body,
        subject_type=subject_type,
        subject_id=str(subject_id) if subject_id else None,
        batch_key=batch_key,
    )
    db.session.add(notification)
    db.session.flush()
    realtime.emit_to_user(
        user_id,
        "notification.created",
        {
            "id": notification.id,
            "type": notification_type,
            "title": title,
            "body": body,
            "subject_type": subject_type,
            "subject_id": subject_id,
            "created_at": notification.created_at.isoformat(),
        },
    )
    if commit:
        db.session.commit()
    return notification


def dispatch_push_for(notification):
    from app.models.identity import DeviceToken

    tokens = DeviceToken.query.filter_by(user_id=notification.user_id).all()
    adapter = push_adapter()
    for t in tokens:
        try:
            adapter.send(t.token, notification.title, notification.body, {"nid": notification.id})
        except Exception:
            current_app.logger.warning("push dispatch failed for %s", t.token[:8])
    notification.pushed_at = utcnow()
