from datetime import timedelta

from extensions import db, realtime
from app.errors import bad_request, conflict, forbidden, not_found
from app.models.base import utcnow
from app.models.social import Event, EventParticipant, EventReminder, Poll, PollOption, PollVote


def create_poll(creator, payload):
    options = payload.get("options", [])
    if len(options) < 2:
        raise bad_request("Polls require at least two options")

    poll = Poll(
        group_id=payload.get("group_id"),
        community_id=payload.get("community_id"),
        conversation_id=payload.get("conversation_id"),
        creator_id=creator.id,
        question=payload["question"],
        multiple_choice=bool(payload.get("multiple_choice", False)),
        anonymous=bool(payload.get("anonymous", False)),
        closes_at=utcnow() + timedelta(hours=int(payload.get("ttl_hours", 48))),
    )
    db.session.add(poll)
    db.session.flush()

    for i, label in enumerate(options):
        db.session.add(PollOption(poll_id=poll.id, label=label[:255], position=i))

    if poll.group_id:
        from app.services.group_service import require_group_permission

        require_group_permission(poll.group_id, creator, "can_create_polls")

    if poll.conversation_id:
        from app.services.messaging_service import send_message

        send_message(creator, poll.conversation_id, {
            "client_message_id": f"poll-{poll.id}",
            "message_type": "poll_card",
            "entity_ref_type": "poll",
            "entity_ref_id": poll.id,
            "body_text": poll.question,
            "entity_snapshot": {"question": poll.question, "options": options},
        })

    _broadcast_poll(poll)
    return poll


def vote(user, poll_id, option_ids):
    poll = db.session.get(Poll, poll_id)
    if poll is None:
        raise not_found("Poll not found")
    if poll.closed or (poll.closes_at and utcnow() > poll.closes_at):
        raise conflict("This poll has closed")
    if not isinstance(option_ids, list) or not option_ids:
        raise bad_request("Provide at least one option to vote for")
    if not poll.multiple_choice and len(option_ids) > 1:
        raise bad_request("This poll allows a single choice only")

    valid_options = {o.id: o for o in PollOption.query.filter(PollOption.poll_id == poll.id).all()}
    for oid in option_ids:
        if oid not in valid_options:
            raise bad_request("Invalid poll option")

    existing_votes = PollVote.query.filter_by(poll_id=poll.id, user_id=user.id).all()
    existing_option_ids = {v.poll_option_id for v in existing_votes}

    for v in existing_votes:
        opt = db.session.get(PollOption, v.poll_option_id)
        if opt and v.poll_option_id not in set(option_ids):
            opt.vote_count = max(0, opt.vote_count - 1)
            db.session.delete(v)

    for oid in option_ids:
        if oid not in existing_option_ids:
            db.session.add(PollVote(poll_id=poll.id, poll_option_id=oid, user_id=user.id))
            valid_options[oid].vote_count += 1

    db.session.flush()
    _broadcast_poll(poll)
    return {"voted_options": option_ids}


def close_poll(actor, poll_id):
    poll = db.session.get(Poll, poll_id)
    if poll is None:
        raise not_found("Poll not found")
    if poll.creator_id != actor.id and "ADMIN" not in actor.role_codes():
        if poll.group_id:
            from app.services.group_service import get_group_member
            from app.models.group import GroupMember

            gm = get_group_member(poll.group_id, actor.id)
            if gm is None or gm.role not in ("ADMIN", "MODERATOR"):
                raise forbidden("Only the poll creator or group admins can close this poll")
        else:
            raise forbidden("Only the poll creator can close this poll")
    poll.closed = True
    _broadcast_poll(poll)
    return poll


def poll_results(poll):
    total = sum(o.vote_count for o in poll.options)
    return {
        "poll_id": poll.id,
        "question": poll.question,
        "closed": poll.closed,
        "multiple_choice": poll.multiple_choice,
        "anonymous": poll.anonymous,
        "total_votes": total,
        "options": [
            {
                "id": o.id,
                "label": o.label,
                "votes": o.vote_count,
                "percent": round(o.vote_count / total * 100) if total else 0,
            }
            for o in sorted(poll.options, key=lambda x: x.position)
        ],
    }


def _broadcast_poll(poll):
    data = poll_results(poll)
    if poll.group_id:
        realtime.emit("poll.updated", data)
    if poll.conversation_id:
        realtime.emit_to_conversation(poll.conversation_id, "poll.updated", data)


def create_event(organizer, payload):
    if payload.get("group_id"):
        from app.services.group_service import require_group_permission

        require_group_permission(payload["group_id"], organizer, "can_create_events")

    event = Event(
        group_id=payload.get("group_id"),
        community_id=payload.get("community_id"),
        title=payload["title"],
        description=payload.get("description", ""),
        starts_at=payload["starts_at"],
        ends_at=payload.get("ends_at"),
        location_label=payload.get("location_label", ""),
        online_link=payload.get("online_link"),
        organizer_id=organizer.id,
    )
    db.session.add(event)
    db.session.flush()

    if event.group_id:
        from app.services.messaging_service import send_message
        from app.models.messaging import Conversation

        conv = Conversation.query.filter_by(group_id=event.group_id).first()
        if conv:
            send_message(organizer, conv.id, {
                "client_message_id": f"event-{event.id}",
                "message_type": "event_card",
                "entity_ref_type": "event",
                "entity_ref_id": event.id,
                "body_text": f"📅 {event.title}",
                "entity_snapshot": {"title": event.title, "starts_at": event.starts_at.isoformat(),
                                    "location": event.location_label},
            })
        realtime.emit("event.updated", {"event_id": event.id, "action": "created"})
    return event


def rsvp(user, event_id, response):
    if response not in ("going", "maybe", "not_going"):
        raise bad_request("RSVP must be going/maybe/not_going")
    event = db.session.get(Event, event_id)
    if event is None:
        raise not_found("Event not found")
    p = EventParticipant.query.filter_by(event_id=event.id, user_id=user.id).first()
    if p is None:
        p = EventParticipant(event_id=event.id, user_id=user.id, rsvp=response)
        db.session.add(p)
    else:
        p.rsvp = response

    remind_at = event.starts_at - timedelta(hours=2)
    if response == "going" and remind_at > utcnow():
        exists = EventReminder.query.filter_by(event_id=event.id, user_id=user.id).first()
        if exists is None:
            db.session.add(EventReminder(event_id=event.id, user_id=user.id, remind_at=remind_at))

    realtime.emit("event.updated", {
        "event_id": event.id, "user_id": user.id, "rsvp": response})
    return p


def dispatch_event_reminders():
    due = EventReminder.query.filter(
        EventReminder.remind_at <= utcnow(), EventReminder.sent_at.is_(None)
    ).limit(500).all()
    sent = 0
    for r in due:
        event = db.session.get(Event, r.event_id)
        if event and not event.cancelled:
            from app.services.notification_service import notify

            notify(r.user_id, "EVENT_REMINDER", f"Starting soon: {event.title}",
                   event.location_label or "", subject_type="event", subject_id=event.id)
        r.sent_at = utcnow()
        sent += 1
    if due:
        db.session.commit()
    return sent
