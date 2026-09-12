import marshmallow as ma
from flask_jwt_extended import jwt_required

from extensions import db
from app.api.helpers import parse_body, query_params
from app.errors import not_found
from app.services import social_service, status_service
from app.services.security import get_current_user


class StatusSchema(ma.Schema):
    status_type = ma.fields.String(missing="text", validate=ma.validate.OneOf(
        ["text", "image", "voice", "listing_share"]))
    body_text = ma.fields.String(missing="")
    media_keys = ma.fields.List(ma.fields.String())
    media_key = ma.fields.String()
    background = ma.fields.String(missing="")
    duration_seconds = ma.fields.Integer(missing=0)
    audience_scope = ma.fields.String(missing="EVERYONE", validate=ma.validate.OneOf(
        ["EVERYONE", "FOLLOWERS", "COMMUNITIES", "SELECTED_USERS", "PRIVATE"]))
    selected_user_ids = ma.fields.List(ma.fields.String())
    community_ids = ma.fields.List(ma.fields.String())
    listing_id = ma.fields.String()


@jwt_required()
def create_status():
    user = get_current_user()
    data = parse_body(StatusSchema)
    status = status_service.create_status(user, data)
    db.session.commit()
    return {"status": status_service.status_json(status)}, 201


@jwt_required()
def list_statuses():
    user = get_current_user()
    rows = status_service.visible_statuses(user)
    return {"statuses": [status_service.status_json(s) for s in rows]}


@jwt_required()
def view_status(status_id):
    user = get_current_user()
    result = status_service.view_status(user, status_id)
    db.session.commit()
    return result


@jwt_required()
def react_status(status_id):
    user = get_current_user()
    emoji = (parse_body(type("S", (ma.Schema,), {"emoji": ma.fields.String()})())).get("emoji")
    result = status_service.react_status(user, status_id, emoji)
    db.session.commit()
    return result


@jwt_required()
def convert_listing_to_status():
    user = get_current_user()
    data = parse_body(type("S", (ma.Schema,), {
        "listing_id": ma.fields.String(required=True),
        "caption": ma.fields.String(missing=""),
        "audience_scope": ma.fields.String(missing="EVERYONE"),
    })())
    status = status_service.convert_listing_to_status(user, data["listing_id"],
                                                      caption=data.get("caption", ""),
                                                      audience_scope=data["audience_scope"])
    db.session.commit()
    return {"status": status.to_dict()}, 201


@jwt_required()
def expire_statuses():
    count = status_service.expire_statuses()
    db.session.commit()
    return {"expired": count}


class PollSchema(ma.Schema):
    question = ma.fields.String(required=True)
    options = ma.fields.List(ma.fields.String(), required=True, validate=ma.validate.Length(min=2, max=10))
    multiple_choice = ma.fields.Boolean(missing=False)
    anonymous = ma.fields.Boolean(missing=False)
    closes_in_hours = ma.fields.Integer(missing=48)
    ttl_hours = ma.fields.Integer()
    group_id = ma.fields.String()
    community_id = ma.fields.String()
    conversation_id = ma.fields.String()


@jwt_required()
def create_poll():
    user = get_current_user()
    data = parse_body(PollSchema)
    poll = social_service.create_poll(user, {
        "question": data["question"],
        "options": data["options"],
        "multiple_choice": data.get("multiple_choice", False),
        "anonymous": data.get("anonymous", False),
        "ttl_hours": data.get("ttl_hours") or data.get("closes_in_hours") or 48,
        "group_id": data.get("group_id"),
        "community_id": data.get("community_id"),
        "conversation_id": data.get("conversation_id"),
    })
    db.session.commit()
    return {"poll": {**poll.to_dict(), "results": social_service.poll_results(poll)}}, 201


@jwt_required()
def vote_poll(poll_id):
    user = get_current_user()
    data = parse_body(type("S", (ma.Schema,), {"option_ids": ma.fields.List(ma.fields.String(), required=True)})())
    social_service.vote(user, poll_id, data["option_ids"])
    db.session.commit()
    results = social_service.poll_results(poll_id)
    from extensions import realtime

    realtime.emit("poll.updated", {"poll_id": poll_id, "results": results}, room=f"poll:{poll_id}")
    return {"voted_option_ids": data["option_ids"], "results": results}


@jwt_required()
def close_poll(poll_id):
    user = get_current_user()
    poll = social_service.close_poll(user, poll_id)
    db.session.commit()
    return {"poll": {**poll.to_dict(), "results": social_service.poll_results(poll)}}


@jwt_required()
def poll_results(poll_id):
    return {"results": social_service.poll_results(poll_id)}


class EventSchema(ma.Schema):
    title = ma.fields.String(required=True)
    description = ma.fields.String(missing="")
    event_type = ma.fields.String(missing="community", validate=ma.validate.OneOf(
        ["training", "market_day", "cooperative_meeting", "auction", "community"]))
    location_label = ma.fields.String(missing="")
    online_link = ma.fields.String()
    starts_at = ma.fields.DateTime(required=True)
    ends_at = ma.fields.DateTime()
    group_id = ma.fields.String()
    community_id = ma.fields.String()


def _event_json(event):
    data = event.to_dict()
    data["going_count"] = _rsvp_counts(event.id)
    return data


def _rsvp_counts(event_id):
    from app.models.social import EventParticipant

    return EventParticipant.query.filter_by(event_id=event_id, rsvp="going").count()


@jwt_required()
def create_event():
    user = get_current_user()
    data = parse_body(EventSchema)
    event = social_service.create_event(user, data)
    db.session.commit()
    return {"event": _event_json(event)}, 201


@jwt_required()
def list_events():
    from app.models.social import Event
    from app.models.base import utcnow

    include_past = query_params().get("include_past") == "true"
    q = Event.query.filter(Event.cancelled.is_(False))
    if not include_past:
        q = q.filter(Event.starts_at >= utcnow())
    upcoming = q.order_by(Event.starts_at.asc()).limit(100).all()
    return {"events": [_event_json(e) for e in upcoming]}


@jwt_required()
def rsvp_event(event_id):
    from flask import request

    user = get_current_user()
    body = request.get_json(silent=True) or {}
    response = (query_params().get("response") or body.get("response") or "going").lower()
    response = {"yes": "going", "not_going": "not_going", "no": "not_going"}.get(response, response)
    participant = social_service.rsvp(user, event_id, response)
    db.session.commit()
    return {"response": participant.rsvp}


@jwt_required()
def dispatch_reminders():
    user = get_current_user()
    if "ADMIN" not in user.role_codes():
        from app.errors import forbidden

        raise forbidden("Admin only")
    sent = social_service.dispatch_event_reminders()
    db.session.commit()
    return {"reminders_sent": sent}
