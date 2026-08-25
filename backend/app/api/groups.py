import marshmallow as ma
from flask import request
from flask_jwt_extended import jwt_required

from extensions import db
from app.api.helpers import parse_body, query_params
from app.api.serializers import group_json
from app.errors import bad_request, forbidden, not_found
from app.models.group import (
    Group,
    GroupAnnouncement,
    GroupBan,
    GroupDocument,
    GroupInvite,
    GroupJoinRequest,
    GroupKnowledgeItem,
    GroupMember,
)
from app.services import group_service
from app.services.security import get_current_user


@jwt_required()
def create_group():
    user = get_current_user()
    data = parse_body(type("S", (ma.Schema,), {
        "name": ma.fields.String(required=True, validate=ma.validate.Length(min=2)),
        "description": ma.fields.String(missing=""),
        "group_type": ma.fields.String(missing="interest"),
        "is_private": ma.fields.Boolean(missing=False),
        "require_approval": ma.fields.Boolean(missing=True),
        "community_id": ma.fields.String(),
        "cooperative_id": ma.fields.String(),
        "creator_role": ma.fields.String(missing="ADMIN"),
    })())
    group = group_service.create_group(user, data)
    db.session.commit()
    return {"group": group_json(group)}, 201


def list_groups():
    user = None
    try:
        user = get_current_user(required=False)
    except Exception:
        pass
    q = Group.query.filter(Group.deleted_at.is_(None))
    search = query_params().get("q")
    if search:
        q = q.filter(Group.name.ilike(f"%{search}%"))
    groups = q.order_by(Group.member_count.desc()).limit(100).all()
    my_roles = {}
    if user is not None:
        for m in GroupMember.query.filter_by(user_id=user.id, left_at=None).all():
            my_roles[m.group_id] = m.role
    return {"groups": [group_json(g, my_roles.get(g.id)) for g in groups]}


@jwt_required()
def get_group(group_id):
    user = get_current_user()
    group = group_service.get_group_or_404(group_id)
    member = group_service.get_group_member(group.id, user.id)
    return {"group": group_json(group, member.role if member else None)}


class AddMembersSchema(ma.Schema):
    members = ma.fields.List(ma.fields.Dict(), required=True)


@jwt_required()
def add_members(group_id):
    user = get_current_user()
    group = group_service.get_group_or_404(group_id)
    data = parse_body(AddMembersSchema)
    added = group_service.add_members(user, group, data["members"])
    db.session.commit()
    return {"added": [{"user_id": uid, "role": role} for uid, role in added]}


@jwt_required()
def remove_member(group_id, user_id):
    actor = get_current_user()
    group = group_service.get_group_or_404(group_id)
    group_service.remove_member(actor, group, user_id)
    db.session.commit()
    return {"removed": True}


@jwt_required()
def ban_member(group_id, user_id):
    actor = get_current_user()
    group = group_service.get_group_or_404(group_id)
    reason = (request.get_json(silent=True) or {}).get("reason", "")
    group_service.ban_member(actor, group, user_id, reason)
    db.session.commit()
    return {"banned": True}


@jwt_required()
def join_group(group_id):
    user = get_current_user()
    group = group_service.get_group_or_404(group_id)
    result = group_service.join_group(user, group)
    db.session.commit()
    return result


@jwt_required()
def list_join_requests(group_id):
    user = get_current_user()
    group = group_service.get_group_or_404(group_id)
    member = group_service.get_group_member(group.id, user.id)
    if member is None or member.role not in ("ADMIN", "MODERATOR", "COOPERATIVE_LEADER"):
        raise forbidden("Only group admins can view join requests")
    rows = GroupJoinRequest.query.filter_by(group_id=group.id, state="PENDING").all()
    return {"requests": [{"id": r.id, "user_id": r.user_id, "message": r.message} for r in rows]}


class ReviewJoinSchema(ma.Schema):
    approve = ma.fields.Boolean(required=True)


@jwt_required()
def review_join_request(group_id, request_id):
    user = get_current_user()
    group = group_service.get_group_or_404(group_id)
    data = parse_body(ReviewJoinSchema)
    req = group_service.approve_join_request(user, group, request_id, approve=data["approve"])
    db.session.commit()
    return {"state": req.state}


@jwt_required()
def create_invite(group_id):
    user = get_current_user()
    group = group_service.get_group_or_404(group_id)
    invite = group_service.create_invite(user, group)
    db.session.commit()
    return {"invite_code": invite.code, "expires_at": None}


@jwt_required()
def revoke_invite(group_id, code):
    user = get_current_user()
    group = group_service.get_group_or_404(group_id)
    group_service.revoke_invite(user, group, code)
    db.session.commit()
    return {"revoked": True}


@jwt_required()
def announce(group_id):
    user = get_current_user()
    group = group_service.get_group_or_404(group_id)
    data = parse_body(type("S", (ma.Schema,), {
        "body_text": ma.fields.String(required=True),
        "mention_all": ma.fields.Boolean(missing=False),
    })())
    ann = group_service.announce(user, group, data["body_text"], mention_all=data["mention_all"])
    db.session.commit()
    return {"announcement": ann.to_dict()}, 201


@jwt_required()
def knowledge_items(group_id):
    user = get_current_user()
    group = group_service.get_group_or_404(group_id)
    group_service.require_group_permission(group.id, user, "can_message")
    rows = GroupKnowledgeItem.query.filter_by(group_id=group.id).order_by(
        GroupKnowledgeItem.pinned.desc(), GroupKnowledgeItem.created_at.desc()).limit(200).all()
    return {"items": [i.to_dict() for i in rows]}


class KnowledgeSchema(ma.Schema):
    title = ma.fields.String(required=True)
    content = ma.fields.String(missing="")
    category = ma.fields.String(missing="general")


@jwt_required()
def add_knowledge(group_id):
    user = get_current_user()
    group = group_service.get_group_or_404(group_id)
    data = parse_body(KnowledgeSchema)
    item = group_service.add_knowledge_item(user, group, data["title"], data["content"], data["category"])
    db.session.commit()
    return {"item": item.to_dict()}, 201


@jwt_required()
def documents(group_id):
    user = get_current_user()
    group = group_service.get_group_or_404(group_id)
    group_service.require_group_permission(group.id, user, "can_message")
    rows = GroupDocument.query.filter_by(group_id=group.id).limit(200).all()
    return {"documents": [d.to_dict() for d in rows]}


@jwt_required()
def upload_document(group_id):
    from app.services.storage_service import store_upload

    user = get_current_user()
    group = group_service.get_group_or_404(group_id)
    file = request.files.get("file")
    if file is None:
        raise bad_request("A file part named 'file' is required")
    stored = store_upload(user, file, "document")
    doc = group_service.add_document(user, group, file.filename or "document",
                                     stored["storage_key"], stored["content_type"], stored["size_bytes"])
    db.session.commit()
    return {"document": doc.to_dict()}, 201
