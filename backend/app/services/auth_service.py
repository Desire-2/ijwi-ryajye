import hashlib
import hmac
import secrets
from datetime import timedelta

import extensions
from extensions import db, jwt
from app.errors import bad_request, conflict, unauthorized
from app.models.identity import RefreshTokenRecord, User, Verification, utcnow


class SMSProvider:
    def send(self, phone, message):
        raise NotImplementedError


class ConsoleSMSProvider(SMSProvider):
    def send(self, phone, message):
        print(f"[sms] to={phone}: {message}")


class TestCaptureSMSProvider(ConsoleSMSProvider):
    outbox = []

    def send(self, phone, message):
        TestCaptureSMSProvider.outbox.append((phone, message))


class HttpSmsProvider(ConsoleSMSProvider):
    def __init__(self, endpoint, api_key):
        self.endpoint = endpoint
        self.api_key = api_key

    def send(self, phone, message):
        import requests

        requests.post(
            self.endpoint,
            json={"to": phone, "text": message},
            headers={"Authorization": f"Bearer {self.api_key}"},
            timeout=10,
        )


def sms_provider():
    from flask import current_app

    name = current_app.config["SMS_PROVIDER"]
    if name == "test-capture":
        return TestCaptureSMSProvider()
    endpoint = current_app.config.get("SMS_ENDPOINT")
    api_key = currentAppKey(current_app)
    if name and name not in ("console",) and endpoint and api_key:
        return HttpSmsProvider(endpoint, api_key)
    return ConsoleSMSProvider()


def currentAppKey(app):
    return app.config.get("SMS_API_KEY")


def hash_otp(code, phone):
    salt = "ijwi-otp"
    return hashlib.sha256(f"{salt}:{phone}:{code}".encode()).hexdigest()


def issue_otp(phone):
    code = f"{secrets.randbelow(900000) + 100000}"
    record = PhoneOtpStore.issue(phone, code)
    sms_provider().send(phone, f"Ijwi Ryajye verification code: {code}. Valid for 10 minutes.")
    return {"expires_in": record["expires_in"], "attempts_left": record["attempts_left"]}


def verify_otp(phone, code) -> bool:
    return PhoneOtpStore.verify(phone, code)


class PhoneOtpStore:
    _store = {}

    @classmethod
    def issue(cls, phone, code):
        cls._store[phone] = {
            "hash": hash_otp(code, phone),
            "expires_at": utcnow() + timedelta(seconds=600),
            "attempts_left": 5,
        }
        return {"expires_in": 600, "attempts_left": 5}

    @classmethod
    def verify(cls, phone, code):
        rec = cls._store.get(phone)
        if not rec:
            return False
        if utcnow() > rec["expires_at"]:
            del cls._store[phone]
            return False
        if rec["attempts_left"] <= 0:
            return False
        if not hmac.compare_digest(rec["hash"], hash_otp(code or "", phone)):
            rec["attempts_left"] -= 1
            return False
        del cls._store[phone]
        return True


def register_hooks(app):
    @jwt.user_identity_loader
    def _identity(user):
        return user.id

    @jwt.user_lookup_loader
    def _lookup(_header, payload):
        uid = payload["sub"] if isinstance(payload, dict) else getattr(payload, "sub", None)
        return db.session.get(User, uid) if uid else None

    @jwt.token_verification_failed_loader
    def _failed(_h, _p):
        return {"error": {"code": "UNAUTHORIZED", "message": "Invalid token"}}, 401

    @jwt.revoked_token_loader
    def _revoked(_h, _p):
        return {"error": {"code": "UNAUTHORIZED", "message": "Token revoked"}}, 401


def store_refresh_token(user, jti, expires_delta):
    rec = RefreshTokenRecord(
        jti=jti,
        user_id=user.id,
        expires_at=utcnow() + expires_delta,
    )
    db.session.add(rec)
    db.session.flush()
    return rec


def revoke_refresh_token(jti):
    rec = RefreshTokenRecord.query.filter_by(jti=jti).first()
    if not rec or rec.revoked:
        raise unauthorized("Refresh token invalid")
    rec.revoked = True
    db.session.commit()


def mark_phone_verified(user_id):
    user = db.session.get(User, user_id)
    user.phone_verified_at = utcnow()
    v = Verification.query.filter_by(user_id=user_id, level="PHONE").first()
    if v is None:
        v = Verification(user_id=user_id, level="PHONE", status="VERIFIED")
        db.session.add(v)
    else:
        v.status = "VERIFIED"
    db.session.commit()
