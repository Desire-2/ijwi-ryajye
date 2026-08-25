from extensions import db, realtime
from app.errors import bad_request, conflict, forbidden, not_found
from app.models.base import utcnow
from app.models.call import (
    Call,
    CallEvent,
    CallParticipant,
    VoiceRoom,
    VoiceRoomParticipant,
    VoiceRoomSpeakerRequest,
)
from app.services.security import assert_not_blocked_between


def start_call(initiator, callee_id, call_type="VOICE"):
    from app.models.identity import User

    if call_type not in ("VOICE", "VIDEO"):
        raise bad_request("call_type must be VOICE or VIDEO")
    callee = db.session.get(User, callee_id)
    if callee is None:
        raise not_found("Callee not found")
    if callee.id == initiator.id:
        raise bad_request("Cannot call yourself")
    assert_not_blocked_between(initiator.id, callee.id)

    call = Call(call_type=call_type, initiator_id=initiator.id, state="RINGING")
    db.session.add(call)
    db.session.flush()
    for u in (initiator, callee):
        db.session.add(CallParticipant(call_id=call.id, user_id=u.id))
    db.session.add(CallEvent(call_id=call.id, actor_id=initiator.id, event_type="INITIATED"))
    db.session.flush()

    realtime.emit_to_user(callee.id, "call.started", {
        "call_id": call.id,
        "call_type": call_type,
        "from": {"id": initiator.id, "name": initiator.full_name},
    })
    return call


def answer_call(actor, call_id):
    call = _participant_call(actor, call_id)
    if call.state != "RINGING":
        raise conflict(f"Call is {call.state.lower()}")
    call.state = "ONGOING"
    call.started_at = utcnow()
    p = CallParticipant.query.filter_by(call_id=call.id, user_id=actor.id).first()
    p.joined_at = utcnow()
    db.session.add(CallEvent(call_id=call.id, actor_id=actor.id, event_type="ANSWERED"))

    other = [p.user_id for p in call.participants if p.user_id != actor.id]
    for uid in other:
        realtime.emit_to_user(uid, "call.answered", {"call_id": call.id})
    return call


def decline_or_end_call(actor, call_id, reason="normal"):
    call = _participant_call(actor, call_id)
    ended_states = ("ENDED", "MISSED", "DECLINED", "FAILED")
    if call.state in ended_states:
        return call

    now = utcnow()
    p = CallParticipant.query.filter_by(call_id=call.id, user_id=actor.id).first()
    if reason == "declined" and call.state == "RINGING":
        call.state = "DECLINED"
    else:
        call.state = "ENDED"
        if call.started_at:
            call.duration_seconds = int((now - call.started_at).total_seconds())
        else:
            call.state = "MISSED"
    call.ended_at = now
    call.end_reason = reason
    if p:
        p.left_at = now
    db.session.add(CallEvent(call_id=call.id, actor_id=actor.id, event_type=f"ENDED:{reason}"))

    others = [p2.user_id for p2 in call.participants if p2.user_id != actor.id]
    for uid in others:
        realtime.emit_to_user(uid, "call.ended", {"call_id": call.id, "reason": reason})
    return call


def relay_signal(actor, payload):
    call = _participant_call(actor, payload["call_id"])
    target_uid = payload.get("to")
    p = CallParticipant.query.filter_by(call_id=call.id, user_id=target_uid).first()
    if p is None:
        raise forbidden("Signal target is not in this call")
    realtime.emit_to_user(target_uid, "call.signal", {
        "call_id": call.id,
        "from": actor.id,
        "kind": payload.get("kind"),
        "data": payload.get("data"),
    })
    return {"relayed": True}


def _participant_call(actor, call_id):
    call = db.session.get(Call, call_id)
    if call is None:
        raise not_found("Call not found")
    p = CallParticipant.query.filter_by(call_id=call.id, user_id=actor.id).first()
    if p is None and "ADMIN" not in actor.role_codes():
        raise forbidden("You are not a participant of this call")
    return call


def create_voice_room(host, title, topic="", group_id=None, community_id=None, scheduled_at=None):
    room = VoiceRoom(
        title=title,
        topic=topic,
        host_id=host.id,
        group_id=group_id,
        community_id=community_id,
        scheduled_at=scheduled_at,
        state="SCHEDULED" if scheduled_at else "LIVE",
    )
    if not scheduled_at:
        room.started_at = utcnow()
    db.session.add(room)
    db.session.flush()
    db.session.add(VoiceRoomParticipant(room_id=room.id, user_id=host.id, role="HOST"))
    realtime.emit("voice_room.created", {
        "room_id": room.id, "title": title,
        "host": {"id": host.id, "name": host.full_name}})
    return room


def join_voice_room(user, room_id):
    room = db.session.get(VoiceRoom, room_id)
    if room is None:
        raise not_found("Voice room not found")
    if room.state == "ENDED":
        raise conflict("This Farm Talk session has ended")

    p = VoiceRoomParticipant.query.filter_by(room_id=room.id, user_id=user.id).first()
    if p is None:
        is_host = room.host_id == user.id
        p = VoiceRoomParticipant(
            room_id=room.id, user_id=user.id,
            role="HOST" if is_host else "LISTENER",
            joined_at=utcnow(),
        )
        db.session.add(p)
    elif p.left_at:
        p.left_at = None

    room.listener_count += 1
    realtime.emit("voice_room.updated", {
        "room_id": room.id,
        "listener_count": room.listener_count,
        "event": f"{user.full_name} joined",
    })
    return p


def request_speaker(user, room_id):
    room = db.session.get(VoiceRoom, room_id)
    existing = VoiceRoomSpeakerRequest.query.filter_by(room_id=room_id, user_id=user.id).first()
    if existing and existing.state == "PENDING":
        return existing
    req = VoiceRoomSpeakerRequest(room_id=room_id, user_id=user.id)
    db.session.add(req)
    db.session.flush()

    realtime.emit_to_user(room.host_id, "voice_room.speaker_requested", {
        "room_id": room_id, "user": {"id": user.id, "name": user.full_name}})
    return req


def decide_speaker(host, room_id, request_id, approve=True):
    room = _assert_host(host, room_id)
    req = db.session.get(VoiceRoomSpeakerRequest, request_id)
    if req is None or str(req.room_id) != str(room_id):
        raise not_found("Speaker request not found")
    req.state = "APPROVED" if approve else "DENIED"
    if approve:
        p = VoiceRoomParticipant.query.filter_by(room_id=room.id, user_id=req.user_id).first()
        if p is None:
            p = VoiceRoomParticipant(room_id=room.id, user_id=req.user_id, joined_at=utcnow())
            db.session.add(p)
        p.role = "SPEAKER"
        realtime.emit_to_user(req.user_id, "voice_room.promoted", {"room_id": room.id})
    return req


def end_voice_room(host, room_id):
    room = _assert_host(host, room_id)
    room.state = "ENDED"
    room.ended_at = utcnow()
    realtime.emit("voice_room.updated", {"room_id": room.id, "state": "ENDED"})
    return room


def _assert_host(actor, room_id):
    from app.errors import forbidden as _forbidden

    room = db.session.get(VoiceRoom, room_id)
    if room is None:
        raise not_found("Voice room not found")
    if room.host_id != actor.id and "ADMIN" not in actor.role_codes():
        p = VoiceRoomParticipant.query.filter_by(room_id=room.id, user_id=actor.id).first()
        if p is None or p.role != "CO_HOST":
            raise _forbidden("Only the host or co-host can do this")
    return room
