import marshmallow as ma
from flask import current_app, request
from flask_jwt_extended import create_access_token, create_refresh_token, get_jti, get_jwt, jwt_required

from extensions import db, limiter
from app.api.helpers import parse_body
from app.errors import bad_request, conflict, unauthorized
from app.models.identity import BuyerProfile, FarmerProfile, User, UserRole, Verification
from app.services import auth_service
from app.services.audit_service import record as audit
from werkzeug.security import check_password_hash, generate_password_hash


class RegisterSchema(ma.Schema):
    full_name = ma.fields.String(required=True, validate=ma.validate.Length(min=2, max=255))
    username = ma.fields.String(required=True, validate=ma.validate.Length(min=3, max=64))
    phone = ma.fields.String(required=True)
    password = ma.fields.String(load_only=True, validate=ma.validate.Length(min=8))
    country_code = ma.fields.String(missing="RW", validate=ma.validate.Length(equal=2))
    region = ma.fields.String()
    district = ma.fields.String()
    role = ma.fields.String(missing="FARMER")
    languages = ma.fields.String(missing="rw")


def _normalize_username(username):
    u = (username or "").strip().lstrip("@").lower()
    if not all(c.isalnum() or c == "_" for c in u):
        raise bad_request("Usernames may only contain letters, numbers and underscores")
    return u


def register():
    data = parse_body(RegisterSchema)

    from flask import current_app as app
    if data["role"] not in ("FARMER", "BUYER", "LOGISTICS"):
        raise bad_request("Initial role must be FARMER, BUYER or LOGISTICS")

    username = _normalize_username(data["username"])
    if User.query.filter_by(username=username).first():
        raise conflict("Username already taken", "USERNAME_TAKEN")
    phone = data["phone"].strip()
    if not phone.startswith("+"):
        raise bad_request("Phone must be in international format (+25...)")
    if User.query.filter_by(phone=phone).first():
        raise conflict("Phone number already registered", "PHONE_TAKEN")

    user = User(
        username=username,
        full_name=data["full_name"],
        phone=phone,
        password_hash=generate_password_hash(data["password"]) if data.get("password") else None,
        country_code=data["country_code"].upper(),
        region=data.get("region"),
        district=data.get("district"),
        languages=data.get("languages", "rw"),
        primary_role=data["role"],
    )
    db.session.add(user)
    db.session.flush()
    db.session.add(UserRole(user_id=user.id, role=data["role"]))
    if data["role"] == "FARMER":
        db.session.add(FarmerProfile(user_id=user.id))
    elif data["role"] == "LOGISTICS":
        from app.models.identity import LogisticsProfile

        db.session.add(LogisticsProfile(user_id=user.id, company_name=f"{data['full_name']}'s Logistics"))
    else:
        db.session.add(BuyerProfile(user_id=user.id))

    otp_info = auth_service.issue_otp(phone)
    db.session.add(Verification(user_id=user.id, level="PHONE", status="PENDING"))
    db.session.commit()

    audit(user, "user.registered", "user", user.id)
    response = {
        "user": {"id": user.id, "username": f"@{username}", "full_name": user.full_name},
        "otp_sent": True,
        **({"dev_otp_hint": "Check console output in development"} if app.config["SMS_PROVIDER"] != "test-capture" else {}),
    }
    return response, 201


class LoginSchema(ma.Schema):
    phone = ma.fields.String()
    username = ma.fields.String()
    password = ma.fields.String(load_only=True)


def login():
    data = parse_body(LoginSchema)
    user = None
    if data.get("phone"):
        user = User.query.filter_by(phone=data["phone"].strip()).first()
    elif data.get("username"):
        user = User.query.filter_by(username=_normalize_username(data["username"])).first()
    if user is None or not user.password_hash or not check_password_hash(user.password_hash, data.get("password") or ""):
        raise unauthorized("Invalid credentials")

    if user.is_suspended:
        raise forbidden_suspended()
    return _token_response(user), 200


def forbidden_suspended():
    from app.errors import ApiError

    return ApiError(403, "ACCOUNT_SUSPENDED", "This account is suspended. Contact support.")


def request_otp():
    data = parse_body(type("S", (ma.Schema,), {"phone": ma.fields.String(required=True)})())
    user = User.query.filter_by(phone=data["phone"].strip()).first()
    if user is None:
        raise unauthorized("No account with this phone number")
    info = auth_service.issue_otp(user.phone)
    return {"otp_sent": True, "expires_in": info["expires_in"]}


class VerifyOtpSchema(ma.Schema):
    phone = ma.fields.String(required=True)
    code = ma.fields.String(required=True)


def verify_otp():
    data = parse_body(VerifyOtpSchema)
    user = User.query.filter_by(phone=data["phone"].strip()).first()
    if user is None:
        raise unauthorized("No account with this phone number")
    ok = auth_service.verify_otp(user.phone, data["code"])
    if not ok:
        raise unauthorized("Invalid or expired verification code", code="INVALID_OTP")
    auth_service.mark_phone_verified(user.id)
    return {"verified": True, "tokens": _token_payload(user)}, 200


@jwt_required()
def refresh():
    identity = get_jwt()["sub"]
    user = db.session.get(User, identity)
    if user is None or not user.is_active:
        raise unauthorized("Account unavailable")
    access_token = create_access_token(identity=user)
    return {"access_token": access_token}, 200


@jwt_required(refresh=True)
def refresh_token_exchange():
    from flask_jwt_extended import get_jwt_identity

    jti = get_jwt()["jti"]
    user_id = get_jwt_identity()
    user = db.session.get(User, user_id)
    if user is None:
        raise unauthorized()
    auth_service.revoke_refresh_token(jti)
    new_refresh = create_refresh_token(identity=user)
    auth_service.store_refresh_token(user, get_jti(new_refresh),
                                     current_app.config["JWT_REFRESH_TOKEN_EXPIRES"])
    db.session.commit()
    return {
        "access_token": create_access_token(identity=user),
        "refresh_token": new_refresh,
        "token_type": "Bearer",
    }, 200


@jwt_required()
def logout():
    data = parse_body() if request.data else {}
    jti = (data or {}).get("refresh_jti")
    if jti:
        try:
            auth_service.revoke_refresh_token(jti)
        except Exception:
            pass
    return {"logged_out": True}, 200


def _token_response(user):
    tokens = _token_payload(user)
    return {
        **tokens,
        "user": {"id": user.id, "username": f"@{user.username}", "primary_role": user.primary_role,
                 "phone_verified": bool(user.phone_verified_at)},
    }


def _token_payload(user):
    access = create_access_token(identity=user)
    refresh_tok = create_refresh_token(identity=user)
    auth_service.store_refresh_token(
        user,
        get_jti(refresh_tok),
        current_app.config["JWT_REFRESH_TOKEN_EXPIRES"],
    )
    db.session.commit()
    return {"access_token": access, "refresh_token": refresh_tok, "token_type": "Bearer"}


register_auth_routes = {
    "register": register,
    "login": login,
    "request_otp": request_otp,
    "verify_otp": verify_otp,
    "refresh_token_exchange": refresh_token_exchange,
    "logout": logout,
}
