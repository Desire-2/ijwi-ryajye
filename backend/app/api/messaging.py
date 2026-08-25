import marshmallow as ma
from flask import request
from flask_jwt_extended import jwt_required

from extensions import db
from app.api.helpers import parse_body, query_params
from app.api.serializers import conversation_json
from app.errors import bad_request, not_found
from app.models.identity import User
from app.models.messaging import (
    Conversation,
    ConversationMember,
    MutedConversation,
    PinnedMessage,
    SavedMessage,
)
from app.services import messaging_service
from app.services.security import get_current_user


@jwt_required()
def list_conversations():
    user = get_current_user()
    member_rows = (
        ConversationMember.query.filter_by(user_id=user.id, left_at=None)
        .join(Conversation, Conversation.id == ConversationMember.conversation_id)
        .order_by(Conversation.last_message_at.desc().nullslast())
        .limit(200)
        .all()
    )
    convs = []
    for m in member_rows:
        conv = messaging_service.get_conversation_or_404(m.conversation_id)
        convs.append(conversation_json(conv, m))
    ftype = query_params().get("type")
    if ftype:
        convs = [c for c in convs if c["conversation_type"] == ftype.upper()]
    if query_params().get("unread") == "true":
        convs = [c for c in convs if c["unread_count"] > 0]
    return {"conversations": convs}


class StartConversationSchema(ma.Schema):
    with_user_id = ma.fields.String(required=True)
    context = ma.fields.String(missing="DIRECT", validate=ma.validate.OneOf(["DIRECT", "MARKETPLACE", "SUPPORT"]))
    listing_id = ma.fields.String()
    order_id = ma.fields.String()


@jwt_required()
def start_conversation():
    user = get_current_user()
    data = parse_body(StartConversationSchema)
    other = db.session.get(User, data["with_user_id"])
    if other is None:
        raise not_found("User not found")
    conv = messaging_service.create_direct_conversation(
        user, other, context_type=data["context"], listing_id=data.get("listing_id"))
    db.session.commit()
    return {"conversation": conversation_json(conv)}, 201


@jwt_required()
def get_conversation(conversation_id):
    user = get_current_user()
    conv = messaging_service.get_conversation_or_404(conversation_id)
    member = messaging_service.assert_membership(conv, user)
    return {"conversation": conversation_json(conv, member)}


class SendMessageSchema(ma.Schema):
    client_message_id = ma.fields.String(required=True)
    message_type = ma.fields.String(missing="text")
    body_text = ma.fields.String(missing="")
    reply_to_message_id = ma.fields.String()
    entity_ref_type = ma.fields.String()
    entity_ref_id = ma.fields.String()
    entity_snapshot = ma.fields.Dict()
    voice_duration_ms = ma.fields.Integer(missing=0)
    waveform = ma.fields.List(ma.fields.Integer())
    disappearing_seconds = ma.fields.Integer()
    attachments = ma.fields.List(ma.fields.Dict(), missing=[])


@jwt_required()
def send_message(conversation_id):
    user = get_current_user()
    data = parse_body(SendMessageSchema)
    message, duplicate = messaging_service.send_message(user, conversation_id, data)
    if not duplicate:
        from extensions import db as _db

        _db.session.commit()
    else:
        db.session.commit()
    from app.api.serializers import message_json

    return {"message": message_json(message), "duplicate": duplicate}, 201


@jwt_required()
def list_messages(conversation_id):
    user = get_current_user()
    before = query_params().get("before_sequence")
    after = query_params().get("after_sequence")
    limit = int(query_params().get("limit", 50))
    msgs = messaging_service.list_messages(user, conversation_id, before, after, limit)
    from app.api.serializers import message_json

    return {"messages": [message_json(m) for m in msgs]}


@jwt_required()
def mark_read(conversation_id):
    user = get_current_user()
    upto = query_params().get("upto_sequence")
    result = messaging_service.mark_read(user, conversation_id, upto)
    db.session.commit()
    return result


@jwt_required()
def react(message_id):
    user = get_current_user()
    data = parse_body(type("S", (ma.Schema,), {"emoji": ma.fields.String()})())
    result = messaging_service.react_to_message(user, message_id, data.get("emoji"))
    db.session.commit()
    return result


@jwt_required()
def edit_message(message_id):
    user = get_current_user()
    data = parse_body(type("S", (ma.Schema,), {"body_text": ma.fields.String(required=True)})())
    msg = messaging_service.edit_message(user, message_id, data["body_text"])
    db.session.commit()
    from app.api.serializers import message_json

    return {"message": message_json(msg)}


@jwt_required()
def delete_message_for_everyone(message_id):
    user = get_current_user()
    messaging_service.delete_for_everyone(user, message_id)
    db.session.commit()
    return {"deleted": True}


@jwt_required()
def delete_message_for_me(message_id):
    user = get_current_user()
    result = messaging_service.delete_for_me(user, message_id)
    db.session.commit()
    return result


class ForwardSchema(ma.Schema):
    message_ids = ma.fields.List(ma.fields.String(), required=True)
    target_conversation_id = ma.fields.String(required=True)


@jwt_required()
def forward_messages():
    user = get_current_user()
    data = parse_body(ForwardSchema)
    created = messaging_service.forward_messages(user, data["message_ids"], data["target_conversation_id"])
    db.session.commit()
    from app.api.serializers import message_json

    return {"forwarded": [message_json(m) for m in created], "count": len(created)}


@jwt_required()
def pin_message(conversation_id, message_id):
    user = get_current_user()
    unpin = query_params().get("unpin") == "true"
    result = messaging_service.pin_message(user, conversation_id, message_id, unpin=unpin)
    db.session.commit()
    return result


@jwt_required()
def pinned_messages(conversation_id):
    user = get_current_user()
    conv = messaging_service.get_conversation_or_404(conversation_id)
    messaging_service.assert_membership(conv, user)
    pins = PinnedMessage.query.filter_by(conversation_id=conv.id).all()
    from app.models.messaging import Message

    msgs = [db.session.get(Message, p.message_id) for p in pins]
    from app.api.serializers import message_json

    return {"pinned": [message_json(m) for m in msgs if m is not None]}


@jwt_required()
def save_message():
    user = get_current_user()
    data = parse_body(type("S", (ma.Schema,), {
        "message_id": ma.fields.String(required=True),
        "note": ma.fields.String(missing=""),
    })())
    saved = messaging_service.save_message(user, data["message_id"], data.get("note", ""))
    db.session.commit()
    return {"saved": True, "id": saved.id}


@jwt_required()
def list_saved():
    user = get_current_user()
    rows = SavedMessage.query.filter_by(user_id=user.id).order_by(SavedMessage.created_at.desc()).limit(200).all()
    from app.api.serializers import message_json

    out = []
    for r in rows:
        m = db.session.get(Message, r.message_id)
        if m is not None and not m.deleted_for_everyone:
            entry = message_json(m)
            entry["saved_note"] = r.note
            out.append(entry)
    return {"saved": out}


@jwt_required()
def typing(conversation_id):
    user = get_current_user()
    started = (request.get_json(silent=True) or {}).get("started", True)
    messaging_service.typing_signal(user, conversation_id, started=bool(started))
    return {"ok": True}


@jwt_required()
def set_disappearing(conversation_id):
    user = get_current_user()
    data = parse_body(type("S", (ma.Schema,), {"option": ma.fields.String(required=True,
                                      validate=ma.validate.OneOf(["off", "24h", "7d", "30d"]))})())
    conv = messaging_service.set_disappearing(user, conversation_id, data["option"])
    db.session.commit()
    return {"conversation": conversation_json(conv)}


@jwt_required()
def search_messages():
    user = get_current_user()
    q = query_params().get("q", "").strip()
    if len(q) < 2:
        raise bad_request("Query must be at least 2 characters")
    msgs = messaging_service.search_messages(user, q)
    from app.api.serializers import message_json

    return {"results": [message_json(m) for m in msgs[:30]]}


@jwt_required()
def mute_conversation(conversation_id):
    user = get_current_user()
    conv = messaging_service.get_conversation_or_404(conversation_id)
    messaging_service.assert_membership(conv, user)
    existing = MutedConversation.query.filter_by(user_id=user.id, conversation_id=conv.id).first()
    mute = query_params().get("mute", "true") == "true"
    if mute and existing is None:
        db.session.add(MutedConversation(user_id=user.id, conversation_id=conv.id))
        cm = messaging_service.get_member(conv.id, user.id)
        cm.muted = True
    elif not mute and existing is not None:
        db.session.delete(existing)
        cm = messaging_service.get_member(conv.id, user.id)
        if cm:
            cm.muted = False
    db.session.commit()
    return {"muted": mute}
