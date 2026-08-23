import json
from datetime import timedelta

from sqlalchemy import func, text

from extensions import db, realtime
from app.errors import bad_request, conflict, forbidden, not_found, unprocessable
from app.models.base import utcnow
from app.models.identity import BlockedUser, User
from app.models.messaging import (
    CONVERSATION_TYPES,
    MESSAGE_TYPES,
    REACTION_EMOJIS,
    Conversation,
    ConversationMember,
    Message,
    MessageAttachment,
    MessageDeliveryReceipt,
    MessageReaction,
    MessageReadReceipt,
    MutedConversation,
    PinnedMessage,
    SavedMessage,
)
from app.services.audit_service import record as audit
from app.services.notification_service import notify
from app.services.security import assert_not_blocked_between


def get_conversation_or_404(conversation_id):
    conv = db.session.get(Conversation, conversation_id)
    if conv is None:
        raise not_found("Conversation not found")
    return conv


def get_member(conversation_id, user_id):
    return ConversationMember.query.filter_by(
        conversation_id=conversation_id, user_id=user_id, left_at=None
    ).first()


def assert_membership(conversation, user):
    if "ADMIN" in user.role_codes():
        return get_member(conversation.id, user.id)
    member = get_member(conversation.id, user.id)
    if member is None:
        raise forbidden("You are not a participant of this conversation")
    return member


def next_server_sequence(conversation) -> int:
    row = db.session.execute(
        text("SELECT server_sequence FROM conversations WHERE id = :id FOR UPDATE"),
        {"id": conversation.id},
    ).fetchone()
    conversation.server_sequence = int(row[0]) + 1
    db.session.flush()
    return conversation.server_sequence


def create_direct_conversation(user_a, user_b, context_type="DIRECT", listing_id=None, order_id=None):
    assert_not_blocked_between(user_a.id, user_b.id)
    key = "|".join(sorted([user_a.id, user_b.id]))
    existing = Conversation.query.filter_by(direct_key=key).first()
    if existing is not None:
        return existing
    conv = Conversation(
        conversation_type=context_type if context_type in ("DIRECT", "MARKETPLACE", "SUPPORT") else "DIRECT",
        created_by_id=user_a.id,
        listing_id=listing_id,
        order_id=order_id,
        direct_key=key,
    )
    db.session.add(conv)
    db.session.flush()
    for u in (user_a, user_b):
        db.session.add(ConversationMember(conversation_id=conv.id, user_id=u.id, role="member"))
    db.session.flush()
    return conv


def send_message(sender, conversation_id, payload):
    conv = get_conversation_or_404(conversation_id)
    member = assert_membership(conv, sender)

    if conv.conversation_type == "DIRECT":
        from app.models.identity import BlockedUser

        other_ids = [m.user_id for m in conv.members
                     if m.user_id != sender.id and m.left_at is None]
        if other_ids:
            pair = BlockedUser.query.filter(
                db.or_(
                    db.and_(BlockedUser.blocker_id == sender.id,
                            BlockedUser.blocked_id.in_(other_ids)),
                    db.and_(BlockedUser.blocker_id.in_(other_ids),
                            BlockedUser.blocked_id == sender.id),
                )
            ).first()
            if pair is not None:
                if pair.blocker_id == sender.id:
                    raise forbidden("You blocked this user. Unblock them to send messages",
                                    "YOU_BLOCKED_USER")
                raise forbidden("You cannot message this user", "BLOCKED_BY_USER")

    if conv.group_id:
        from app.services.group_service import require_group_permission
        from app.models.group import GroupBan, GroupMember

        gm = GroupMember.query.filter_by(group_id=conv.group_id, user_id=sender.id, left_at=None).first()
        if gm is None:
            if GroupBan.query.filter_by(group_id=conv.group_id, user_id=sender.id).first() is not None:
                raise forbidden("You are banned from this group", "GROUP_BANNED")
            raise forbidden("You are not a member of this group conversation", "GROUP_PERMISSION_DENIED")
        if gm.is_banned:
            raise forbidden("You are banned from this group", "GROUP_BANNED")
        require_group_permission(conv.group_id, sender, "can_message")

    client_message_id = payload.get("client_message_id")
    if not client_message_id:
        raise bad_request("client_message_id is required for reliable delivery")

    existing = Message.query.filter_by(
        conversation_id=conv.id, client_message_id=client_message_id
    ).first()
    if existing is not None:
        return existing, True

    msg_type = payload.get("message_type", "text")
    if msg_type not in MESSAGE_TYPES:
        raise bad_request(f"Unsupported message type {msg_type}")

    reply_to = payload.get("reply_to_message_id")
    if reply_to:
        target = db.session.get(Message, reply_to)
        if target is None or target.conversation_id != conv.id:
            raise bad_request("Reply target must be within the same conversation")

    disappearing_seconds = payload.get("disappearing_seconds")
    expires_at = (
        utcnow() + timedelta(seconds=int(disappearing_seconds))
        if disappearing_seconds
        else None
    )
    if msg_type in ("offer_card", "order_card") and expires_at is None:
        pass

    seq = next_server_sequence(conv)

    message = Message(
        conversation_id=conv.id,
        sender_id=sender.id,
        client_message_id=str(client_message_id),
        server_sequence=seq,
        message_type=msg_type,
        body_text=payload.get("body_text", ""),
        reply_to_message_id=reply_to,
        entity_ref_type=payload.get("entity_ref_type"),
        entity_ref_id=payload.get("entity_ref_id"),
        entity_snapshot_json=json.dumps(payload.get("entity_snapshot") or {}, default=str),
        voice_duration_ms=payload.get("voice_duration_ms", 0),
        waveform_json=json.dumps(payload.get("waveform")) if payload.get("waveform") else None,
        disappearing_seconds=int(disappearing_seconds) if disappearing_seconds else None,
        expires_at=expires_at,
    )

    if msg_type == "voice":
        atts = payload.get("attachments", [])
        if not atts:
            raise bad_request("Voice messages require an audio attachment")

    db.session.add(message)
    db.session.flush()

    for att in payload.get("attachments", []):
        db.session.add(
            MessageAttachment(
                message_id=message.id,
                attachment_type=att.get("type", msg_type),
                storage_key=att["storage_key"],
                file_name=att.get("file_name", ""),
                mime_type=att.get("mime_type", ""),
                size_bytes=int(att.get("size_bytes", 0)),
                duration_ms=int(att.get("duration_ms", 0)),
            )
        )

    conv.last_message_at = utcnow()

    for m in ConversationMember.query.filter_by(conversation_id=conv.id, left_at=None).all():
        if m.user_id != sender.id:
            realtime.emit_to_user(m.user_id, "message.delivered", {
                "conversation_id": conv.id,
                "message_id": message.id,
                "server_sequence": seq,
            })

    realtime.emit_to_conversation(conv.id, "message.created", _serialize(message))
    audit(sender, "message.sent", "conversation", conv.id, {"type": msg_type})

    if msg_type != "system" and conv.conversation_type in ("DIRECT", "MARKETPLACE"):
        others = [m.user_id for m in conv.members if m.user_id != sender.id and not m.muted]
        for uid in others:
            blocked_pair = BlockedUser.query.filter_by(blocker_id=uid, blocked_id=sender.id).first()
            if blocked_pair:
                continue
            preview = (payload.get("body_text") or f"[{msg_type}]")[:80]
            notify(uid, "MESSAGE", f"{sender.full_name}", preview,
                   subject_type="conversation", subject_id=conv.id, batch_key=f"chat_{sender.id}", commit=False)

    return message, False


def _serialize(message, include_members=False):
    data = {
        "id": message.id,
        "conversation_id": message.conversation_id,
        "sender_id": message.sender_id,
        "server_sequence": message.server_sequence,
        "message_type": message.message_type,
        "body_text": "" if message.deleted_for_everyone else message.body_text,
        "reply_to_message_id": message.reply_to_message_id,
        "created_at": message.created_at.isoformat(),
        "edited": message.edited,
        "deleted_for_everyone": message.deleted_for_everyone,
        "attachments": [
            {
                "id": a.id,
                "type": a.attachment_type,
                "storage_key": a.storage_key,
                "file_name": a.file_name,
                "size_bytes": a.size_bytes,
                "duration_ms": a.duration_ms,
            }
            for a in message.attachments
        ],
    }
    try:
        data["entity"] = json.loads(message.entity_snapshot_json or "{}")
        data["entity_ref_type"] = message.entity_ref_type
        data["entity_ref_id"] = message.entity_ref_id
    except Exception:
        pass
    return data


def mark_read(user, conversation_id, upto_sequence=None):
    conv = get_conversation_or_404(conversation_id)
    member = assert_membership(conv, user)
    q = Message.query.filter(
        Message.conversation_id == conv.id,
        Message.sender_id != user.id,
    )
    if upto_sequence:
        q = q.filter(Message.server_sequence <= upto_sequence)
    else:
        q = q.filter(Message.server_sequence > member.last_read_sequence)

    unread = q.all()
    now = utcnow()
    for m in unread:
        exists = MessageReadReceipt.query.filter_by(message_id=m.id, user_id=user.id).first()
        if not exists:
            db.session.add(MessageReadReceipt(message_id=m.id, user_id=user.id, read_at=now))

    top_seq = max((m.server_sequence for m in unread), default=member.last_read_sequence)
    member.last_read_sequence = max(member.last_read_sequence, top_seq)
    db.session.flush()

    for m in unread:
        realtime.emit_to_user(m.sender_id, "message.read", {
            "conversation_id": conv.id,
            "message_id": m.id,
            "user_id": user.id,
            "read_at": now.isoformat(),
        })
    return {"read_count": len(unread), "last_read_sequence": member.last_read_sequence}


def react_to_message(user, message_id, emoji):
    message = db.session.get(Message, message_id)
    if message is None:
        raise not_found("Message not found")
    conv = get_conversation_or_404(message.conversation_id)
    assert_membership(conv, user)

    if emoji and emoji not in REACTION_EMOJIS:
        raise bad_request(f"Unsupported reaction. Allowed: {REACTION_EMOJIS}")

    existing = MessageReaction.query.filter_by(message_id=message.id, user_id=user.id).first()
    if not emoji:
        if existing:
            db.session.delete(existing)
            realtime.emit_to_conversation(conv.id, "reaction.removed", {
                "message_id": message.id, "user_id": user.id})
        return {"reacted": False}
    if existing is not None:
        existing.emoji = emoji
    else:
        db.session.add(MessageReaction(message_id=message.id, user_id=user.id, emoji=emoji))
    db.session.flush()
    realtime.emit_to_conversation(conv.id, "reaction.added", {
        "message_id": message.id, "user_id": user.id, "emoji": emoji})
    return {"reacted": True, "emoji": emoji}


def edit_message(user, message_id, new_text):
    message = db.session.get(Message, message_id)
    if message.sender_id != user.id:
        raise forbidden("You can only edit your own messages")
    if message.message_type not in ("text",):
        raise bad_request("Only text messages can be edited")
    from app.models.messaging import MessageEdit

    db.session.add(MessageEdit(
        message_id=message.id, editor_id=user.id,
        previous_body=message.body_text, new_body=new_text))
    message.body_text = new_text
    message.edited = True
    db.session.flush()
    realtime.emit_to_conversation(message.conversation_id, "message.updated",
                                  {"id": message.id, "body_text": new_text, "edited": True})
    return message


def delete_for_everyone(user, message_id):
    message = db.session.get(Message, message_id)
    if message.sender_id != user.id and "ADMIN" not in user.role_codes():
        raise forbidden("Not allowed to delete this message for everyone")
    message.deleted_for_everyone = True
    message.body_text = ""
    db.session.flush()
    realtime.emit_to_conversation(message.conversation_id, "message.deleted",
                                  {"id": message.id})
    audit(user, "message.deleted_for_everyone", "message", message.id)
    return message


def delete_for_me(user, message_id):
    from app.models.messaging import MessageEdit as _ME
    conv = get_conversation_or_404(db.session.get(Message, message_id).conversation_id)
    member = get_member(conv.id, user.id)
    if member is None:
        raise forbidden("Not your conversation")
    hidden = SavedMessage.query.filter_by(user_id=user.id, message_id=message_id).all()
    for h in hidden:
        db.session.delete(h)
    return {"hidden_locally": True, "message_id": message_id}


def forward_messages(user, message_ids, target_conversation_id):
    from flask import current_app

    per_hour_limit = current_app.config["FORWARD_RATE_PER_HOUR"]
    recent = MessageForward.query.filter(
        MessageForward.forwarded_by == user.id,
        MessageForward.created_at > utcnow() - timedelta(hours=1),
    ).count()
    if recent + len(message_ids) > per_hour_limit:
        from app.services.risk_service import note_event

        note_event(user.id, "SPAM_BEHAVIOR", 5, {"forwards_last_hour": recent})
        raise conflict("Forwarding limit reached. Try again later.", code="RATE_LIMITED")

    created = []
    for mid in message_ids:
        original = db.session.get(Message, mid)
        if original is None:
            continue
        payload = {
            "client_message_id": f"fwd-{original.id[:16]}-{utcnow().timestamp()}",
            "message_type": original.message_type,
            "body_text": original.body_text,
            "entity_ref_type": original.entity_ref_type,
            "entity_ref_id": original.entity_ref_id,
            "entity_snapshot": json.loads(original.entity_snapshot_json or "{}"),
            "attachments": [
                {
                    "storage_key": a.storage_key,
                    "type": a.attachment_type,
                    "file_name": a.file_name,
                    "mime_type": a.mime_type,
                    "size_bytes": a.size_bytes,
                    "duration_ms": a.duration_ms,
                }
                for a in original.attachments
            ],
        }
        message, duplicate = send_message(user, target_conversation_id, payload)
        db.session.add(MessageForward(
            original_message_id=original.id,
            forwarded_by=user.id,
            target_conversation_id=target_conversation_id,
            new_message_id=message.id,
        ))
        original.forward_count += 1
        created.append(message)
    return created


def pin_message(user, conversation_id, message_id, unpin=False):
    conv = get_conversation_or_404(conversation_id)
    assert_membership(conv, user)
    pinned = PinnedMessage.query.filter_by(conversation_id=conv.id, message_id=message_id).first()
    if unpin:
        if pinned:
            db.session.delete(pinned)
        return {"pinned": False}
    if pinned is None:
        db.session.add(PinnedMessage(conversation_id=conv.id, message_id=message_id, pinned_by=user.id))
    return {"pinned": True}


def save_message(user, message_id, note=""):
    existing = SavedMessage.query.filter_by(user_id=user.id, message_id=message_id).first()
    if existing:
        return existing
    saved = SavedMessage(user_id=user.id, message_id=message_id, note=note)
    db.session.add(saved)
    db.session.flush()
    return saved


def list_messages(user, conversation_id, before_sequence=None, after_sequence=None, limit=50):
    conv = get_conversation_or_404(conversation_id)
    assert_membership(conv, user)
    q = Message.query.filter(Message.conversation_id == conv.id)
    if before_sequence:
        q = q.filter(Message.server_sequence < int(before_sequence))
    if after_sequence:
        q = q.filter(Message.server_sequence > int(after_sequence))
    msgs = q.order_by(Message.server_sequence.desc()).limit(min(limit, 200)).all()
    return list(reversed(msgs))


def search_messages(user, query, scope_types=None, limit=30):
    q = (
        Message.query.join(ConversationMember, ConversationMember.conversation_id == Message.conversation_id)
        .filter(
            ConversationMember.user_id == user.id,
            ConversationMember.left_at.is_(None),
            Message.body_text.ilike(f"%{query}%"),
            Message.deleted_for_everyone.is_(False),
        )
    )
    return q.order_by(Message.created_at.desc()).limit(limit).all()


def typing_signal(user, conversation_id, started=True):
    conv = get_conversation_or_404(conversation_id)
    assert_membership(conv, user)
    event = "typing.started" if started else "typing.stopped"
    for m in ConversationMember.query.filter(
        ConversationMember.conversation_id == conv.id,
        ConversationMember.left_at.is_(None),
        ConversationMember.user_id != user.id,
    ).all():
        realtime.emit_to_user(m.user_id, event, {
            "conversation_id": conv.id, "user_id": user.id})


def set_disappearing(user, conversation_id, option):
    conv = get_conversation_or_404(conversation_id)
    assert_membership(conv, user)
    from app.models.messaging import DISAPPEARING_OPTIONS

    if option not in DISAPPEARING_OPTIONS:
        raise bad_request("Disappearing option must be one of off/24h/7d/30d")
    seconds = DISAPPEARING_OPTIONS[option]
    conv.disappearing_seconds = seconds
    system_payload = {
        "client_message_id": f"sys-{conv.id}-{utcnow().timestamp()}",
        "message_type": "system",
        "body_text": f"Disappearing messages set to {option}",
    }
    send_message(user, conv.id, system_payload)
    return conv
