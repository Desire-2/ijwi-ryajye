import secrets
from datetime import timedelta

from extensions import db, realtime
from app.errors import bad_request, conflict, forbidden, not_found
from app.models.base import utcnow
from app.models.group import (
    DEFAULT_ROLE_PERMISSIONS,
    GROUP_PERMISSIONS,
    GROUP_ROLES,
    Group,
    GroupAnnouncement,
    GroupBan,
    GroupDocument,
    GroupInvite,
    GroupJoinRequest,
    GroupKnowledgeItem,
    GroupMember,
    GroupRole,
)
from app.services.audit_service import record as audit
from app.services.notification_service import notify

ADMIN_ROLES = ("ADMIN", "MODERATOR", "COOPERATIVE_LEADER")
DEFAULT_INVITE_TTL_DAYS = 7


def get_group_or_404(group_id):
    group = db.session.get(Group, group_id)
    if group is None or group.deleted_at is not None:
        raise not_found("Group not found")
    return group


def get_group_member(group_id, user_id):
    return GroupMember.query.filter_by(
        group_id=group_id, user_id=user_id, left_at=None
    ).first()


def role_permissions(group_id, role):
    perms = dict(DEFAULT_ROLE_PERMISSIONS.get(role, {}))
    override = GroupRole.query.filter_by(group_id=group_id, role=role).first()
    if override is not None and override.permissions_json:
        import json

        try:
            custom = json.loads(override.permissions_json)
            if isinstance(custom, dict):
                for key in GROUP_PERMISSIONS:
                    if key in custom:
                        perms[key] = bool(custom[key])
        except (ValueError, TypeError):
            pass
    return perms


def require_group_permission(group_id, actor, permission):
    member = get_group_member(group_id, actor.id)
    if member is None:
        ban = GroupBan.query.filter_by(group_id=group_id, user_id=actor.id).first()
        if ban is not None:
            raise forbidden("You are banned from this group", "GROUP_BANNED")
        raise forbidden("You are not a member of this group", "GROUP_PERMISSION_DENIED")
    if member.is_banned:
        raise forbidden("You are banned from this group", "GROUP_BANNED")
    perms = role_permissions(group_id, member.role)
    if not perms.get(permission, False):
        raise forbidden(
            f"Your role does not allow {permission}", "GROUP_PERMISSION_DENIED"
        )
    return member


def _ensure_group_conversation(actor, group):
    from app.models.messaging import Conversation, ConversationMember

    conv = Conversation.query.filter_by(group_id=group.id).first()
    if conv is None:
        conv = Conversation(
            conversation_type="GROUP",
            title=group.name,
            created_by_id=actor.id,
            group_id=group.id,
        )
        db.session.add(conv)
        db.session.flush()
        db.session.add(
            ConversationMember(conversation_id=conv.id, user_id=actor.id, role="admin")
        )
    return conv


def _attach_to_conversation(conv, user_id):
    from app.models.messaging import ConversationMember

    existing = ConversationMember.query.filter_by(
        conversation_id=conv.id, user_id=user_id
    ).first()
    if existing is None:
        db.session.add(
            ConversationMember(conversation_id=conv.id, user_id=user_id, role="member")
        )
    elif existing.left_at is not None:
        existing.left_at = None
        existing.joined_at = utcnow()


def create_group(creator, payload):
    if not payload.get("name") or len(payload["name"].strip()) < 2:
        raise bad_request("Group name must be at least 2 characters")

    role = (payload.get("creator_role") or "ADMIN").upper()
    if role not in GROUP_ROLES:
        raise bad_request(f"Invalid creator role {role}")

    group = Group(
        name=payload["name"].strip(),
        description=payload.get("description", ""),
        group_type=payload.get("group_type", "interest"),
        community_id=payload.get("community_id"),
        cooperative_id=payload.get("cooperative_id"),
        is_private=bool(payload.get("is_private", False)),
        require_approval=bool(payload.get("require_approval", True)),
        creator_id=creator.id,
        invite_code=secrets.token_urlsafe(12),
    )
    db.session.add(group)
    db.session.flush()

    for perm_key in GROUP_PERMISSIONS:
        pass  # per-group overrides live in group_roles; defaults come from code

    db.session.add(GroupRole(group_id=group.id, role=role))

    db.session.add(
        GroupMember(group_id=group.id, user_id=creator.id, role=role)
    )
    group.member_count = 1
    db.session.flush()

    conv = _ensure_group_conversation(creator, group)

    audit(creator, "group.created", "group", group.id, {"name": group.name})
    realtime.emit_to_user(creator.id, "group.updated", {"group_id": group.id, "action": "created"})
    return group


def add_members(actor, group, members):
    require_group_permission(group.id, actor, "can_add_members")
    added = []
    conv = _ensure_group_conversation(actor, group)
    from app.services.messaging_service import send_message

    for entry in members:
        target_user_id = entry.get("user_id")
        if not target_user_id:
            raise bad_request("Each member needs a user_id")
        role = (entry.get("role") or "FARMER").upper()
        if role not in GROUP_ROLES:
            raise bad_request(f"Invalid group role {role}")

        if GroupBan.query.filter_by(group_id=group.id, user_id=target_user_id).first() is not None:
            raise conflict("User is banned from this group", "USER_BANNED")

        gm = get_group_member(group.id, target_user_id)
        if gm is None:
            gm = GroupMember(group_id=group.id, user_id=target_user_id, role=role)
            db.session.add(gm)
            group.member_count = (group.member_count or 0) + 1
            _attach_to_conversation(conv, target_user_id)
            added.append((target_user_id, role))
            send_message(actor, conv.id, {
                "client_message_id": f"grp-{group.id}-joined-{target_user_id}",
                "body_text": "A new member joined the group",
                "message_type": "system",
            })
        elif role != gm.role:
            require_group_permission(group.id, actor, "can_edit_group")
            gm.role = role
            added.append((target_user_id, role))

    for uid, r in added:
        notify(uid, "GROUP_ACTIVITY", f"Added to {group.name}",
               f"Your role: {r.lower().replace('_', ' ')}",
               subject_type="group", subject_id=group.id)
        realtime.emit_to_user(uid, "group.member_joined", {"group_id": group.id})

    audit(actor, "group.members_added", "group", group.id, {"count": len(added)})
    return added


def remove_member(actor, group, target_user_id):
    require_group_permission(group.id, actor, "can_add_members")
    gm = get_group_member(group.id, target_user_id)
    if gm is None:
        raise not_found("Member not found")
    if gm.user_id == group.creator_id and gm.role == "ADMIN":
        raise conflict("The group creator cannot be removed", "CREATOR_PROTECTED")

    gm.left_at = utcnow()
    gm.is_banned = False
    group.member_count = max((group.member_count or 1) - 1, 0)

    from app.models.messaging import ConversationMember

    cm = ConversationMember.query.filter_by(
        conversation_id=_conversation_id(group), user_id=target_user_id
    ).first()
    if cm is not None:
        cm.left_at = utcnow()

    notify(target_user_id, "GROUP_ACTIVITY", f"Removed from {group.name}",
           "You are no longer a member of this group",
           subject_type="group", subject_id=group.id)
    realtime.emit_to_user(target_user_id, "group.member_removed", {"group_id": group.id})
    audit(actor, "group.member_removed", "group", group.id, {"user": target_user_id})


def _conversation_id(group):
    from app.models.messaging import Conversation

    conv = Conversation.query.filter_by(group_id=group.id).first()
    return conv.id if conv else None


def ban_member(actor, group, target_user_id, reason=""):
    require_group_permission(group.id, actor, "can_edit_group")
    ban = GroupBan.query.filter_by(group_id=group.id, user_id=target_user_id).first()
    if ban is None:
        ban = GroupBan(group_id=group.id, user_id=target_user_id,
                       reason=reason, banned_by=actor.id)
        db.session.add(ban)
    else:
        ban.reason = reason or ban.reason
    gm = get_group_member(group.id, target_user_id)
    if gm is not None:
        gm.is_banned = True
    remove_member(actor, group, target_user_id)
    audit(actor, "group.member_banned", "group", group.id,
          {"user": target_user_id, "reason": reason})
    return ban


def join_group(user, group):
    if GroupBan.query.filter_by(group_id=group.id, user_id=user.id).first() is not None:
        raise forbidden("You are banned from this group", "GROUP_BANNED")

    existing = get_group_member(group.id, user.id)
    if existing is not None:
        return {"joined": True, "state": "MEMBER"}

    if group.require_approval:
        req = GroupJoinRequest.query.filter_by(
            group_id=group.id, user_id=user.id
        ).first()
        if req is None:
            req = GroupJoinRequest(group_id=group.id, user_id=user.id)
            db.session.add(req)
            db.session.flush()
        elif req.state == "DENIED":
            req.state = "PENDING"
            req.reviewed_by = None
            db.session.flush()
        audit(user, "group.join_requested", "group", group.id)
        realtime.emit_to_user(group.creator_id, "group.join_requested",
                              {"group_id": group.id, "user_id": user.id})
        return {"joined": False, "state": "PENDING", "request_id": req.id}

    role = user.primary_role if user.primary_role in GROUP_ROLES else "GUEST"
    conv = _ensure_group_conversation(user, group)
    db.session.add(GroupMember(group_id=group.id, user_id=user.id, role=role))
    group.member_count = (group.member_count or 0) + 1
    _attach_to_conversation(conv, user.id)
    audit(user, "group.joined", "group", group.id)
    realtime.emit_to_user(user.id, "group.member_joined", {"group_id": group.id})
    return {"joined": True, "state": "MEMBER"}


def approve_join_request(actor, group, request_id, approve=True):
    member = get_group_member(group.id, actor.id)
    if member is None or member.role not in ADMIN_ROLES:
        raise forbidden("Only group admins can review join requests")

    req = GroupJoinRequest.query.filter_by(id=request_id, group_id=group.id).first()
    if req is None:
        raise not_found("Join request not found")
    if req.state != "PENDING":
        raise conflict("Join request already reviewed", "ALREADY_REVIEWED")

    req.state = "APPROVED" if approve else "DENIED"
    req.reviewed_by = actor.id

    if approve:
        if GroupBan.query.filter_by(group_id=group.id, user_id=req.user_id).first() is None:
            from app.models.identity import User

            role = "GUEST"
            target = db.session.get(User, req.user_id)
            if target is not None and target.primary_role in GROUP_ROLES:
                role = target.primary_role
            conv = _ensure_group_conversation(actor, group)
            if get_group_member(group.id, req.user_id) is None:
                db.session.add(GroupMember(group_id=group.id, user_id=req.user_id, role=role))
                group.member_count = (group.member_count or 0) + 1
                _attach_to_conversation(conv, req.user_id)

    notify(req.user_id, "GROUP_ACTIVITY",
           f"Join request {'approved' if approve else 'declined'}",
           f"{group.name}: your request was {'approved' if approve else 'declined'}",
           subject_type="group", subject_id=group.id)
    realtime.emit_to_user(req.user_id, "group.join_reviewed",
                          {"group_id": group.id, "state": req.state})
    audit(actor, "group.join_reviewed", "group", group.id,
          {"request": req.id, "state": req.state})
    return req


def create_invite(actor, group, ttl_days=DEFAULT_INVITE_TTL_DAYS):
    require_group_permission(group.id, actor, "can_invite")
    invite = GroupInvite(
        group_id=group.id,
        code=secrets.token_urlsafe(16),
        created_by=actor.id,
        expires_at=utcnow() + timedelta(days=ttl_days),
    )
    db.session.add(invite)
    group.invite_code = invite.code
    audit(actor, "group.invite_created", "group", group.id)
    return invite


def redeem_invite(user, group, code):
    invite = GroupInvite.query.filter_by(group_id=group.id, code=code).first()
    if invite is None or invite.revoked:
        raise not_found("Invite not found")
    if invite.expires_at is not None and invite.expires_at < utcnow():
        raise conflict("This invite has expired", "INVITE_EXPIRED")
    invite.use_count = (invite.use_count or 0) + 1
    return join_group(user, group)


def revoke_invite(actor, group, code):
    require_group_permission(group.id, actor, "can_invite")
    invite = GroupInvite.query.filter_by(group_id=group.id, code=code).first()
    if invite is None:
        raise not_found("Invite not found")
    invite.revoked = True
    if group.invite_code == code:
        group.invite_code = None
    audit(actor, "group.invite_revoked", "group", group.id, {"code": code})


def announce(actor, group, body_text, mention_all=False):
    require_group_permission(group.id, actor, "can_send_announcements")
    ann = GroupAnnouncement(
        group_id=group.id,
        author_id=actor.id,
        body_text=body_text,
        mention_all=bool(mention_all),
    )
    db.session.add(ann)
    db.session.flush()

    from app.services.messaging_service import send_message

    conv = _ensure_group_conversation(actor, group)
    send_message(actor, conv.id, {
        "client_message_id": f"ann-{ann.id}",
        "body_text": body_text,
        "message_type": "system",
    })

    if mention_all:
        members = GroupMember.query.filter_by(group_id=group.id, left_at=None).all()
        for m in members:
            if m.user_id != actor.id:
                notify(m.user_id, "GROUP_ANNOUNCEMENT",
                       f"Announcement in {group.name}",
                       body_text[:140], subject_type="group", subject_id=group.id)

    audit(actor, "group.announcement_created", "group", group.id)
    return ann


def add_knowledge_item(actor, group, title, content="", category="general"):
    require_group_permission(group.id, actor, "can_message")
    item = GroupKnowledgeItem(
        group_id=group.id,
        title=title,
        content=content,
        category=category or "general",
        author_id=actor.id,
    )
    db.session.add(item)
    db.session.flush()
    audit(actor, "group.knowledge_added", "group", group.id, {"title": title})
    return item


def add_document(actor, group, file_name, storage_key, mime_type="", size_bytes=0):
    require_group_permission(group.id, actor, "can_message")
    doc = GroupDocument(
        group_id=group.id,
        uploader_id=actor.id,
        file_name=file_name,
        storage_key=storage_key,
        mime_type=mime_type or "",
        size_bytes=int(size_bytes or 0),
    )
    db.session.add(doc)
    db.session.flush()
    audit(actor, "group.document_uploaded", "group", group.id, {"file": file_name})
    return doc
