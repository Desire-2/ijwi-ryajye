from flask import request
from flask_jwt_extended import current_user, verify_jwt_in_request

import extensions
from app.errors import forbidden, unauthorized
from app.models.identity import BlockedUser


def get_current_user(required=True):
    try:
        verify_jwt_in_request(optional=not required)
    except Exception:
        if required:
            raise unauthorized()
        return None
    return current_user if current_user else (None if not required else (_ for _ in ()).throw(unauthorized()))


def require_roles(user, *roles):
    codes = user.role_codes() if user else set()
    if not codes.intersection(set(roles)):
        raise forbidden("Your account does not have the required role.", "ROLE_REQUIRED", {"required": list(roles)})


def require_admin(user):
    require_roles(user, "ADMIN")


def assert_not_blocked_between(a_id, b_id):
    pair = (
        BlockedUser.query.filter(
            ((BlockedUser.blocker_id == a_id) & (BlockedUser.blocked_id == b_id))
            | ((BlockedUser.blocker_id == b_id) & (BlockedUser.blocked_id == a_id))
        ).first()
    )
    if pair:
        raise forbidden("Communication is blocked between these users.", "USER_BLOCKED")


def client_ip():
    return request.headers.get("X-Forwarded-For", request.remote_addr or "")
