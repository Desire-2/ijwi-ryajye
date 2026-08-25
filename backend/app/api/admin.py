import marshmallow as ma
from flask import request
from flask_jwt_extended import jwt_required

from extensions import db
from app.api.helpers import pagination_args, parse_body, paginate_response, query_params
from app.errors import bad_request, conflict, not_found
from app.models.admin import AuditLog, DeletionRequest, Dispute, DisputeEvidence, ExportRequest, RiskEvent, SyncOperation
from app.models.identity import User, UserRole, Verification
from app.models.notifications import NotificationBatch
from app.services import audit_service, dispute_service, fee_service, notification_service, risk_service, wallet_service
from app.services.security import get_current_user, require_admin


@jwt_required()
def list_users():
    admin = require_admin()
    page, per_page = pagination_args()
    q = User.query
    search = query_params().get("q")
    if search:
        q = q.filter((User.full_name.ilike(f"%{search}%")) | (User.phone.ilike(f"%{search}%"))
                     | (User.username.ilike(f"%{search}%")))
    state = query_params().get("state")
    if state == "suspended":
        q = q.filter(User.is_suspended.is_(True))
    elif state == "active":
        q = q.filter(User.is_suspended.is_(False), User.deleted_at.is_(None))
    pg = q.order_by(User.created_at.desc()).paginate(page=page, per_page=per_page, error_out=False)
    return paginate_response(pg, lambda u: {
        "id": u.id, "full_name": u.full_name, "phone": u.phone,
        "roles": u.role_codes(), "is_suspended": u.is_suspended,
        "verification_level": getattr(u, "verification_level", None),
        "risk_score": risk_service.risk_score(u.id),
        "created_at": u.created_at.isoformat(),
    })


@jwt_required()
def suspend_user(user_id):
    admin = get_current_user()
    if "ADMIN" not in admin.role_codes():
        from app.errors import forbidden

        raise forbidden("Admin only")
    target = db.session.get(User, user_id)
    if target is None:
        raise not_found("User not found")
    reason = (request.get_json(silent=True) or {}).get("reason", "")
    target.is_suspended = True
    audit_service.record(admin, "user.suspended", "user", user_id, {"reason": reason})
    notification_service.notify(user_id, "ACCOUNT_UPDATE", "Account suspended",
                                reason or "Contact support for details.", commit=False)
    db.session.commit()
    return {"suspended": True}


@jwt_required()
def unsuspend_user(user_id):
    admin = get_current_user()
    if "ADMIN" not in admin.role_codes():
        from app.errors import forbidden

        raise forbidden("Admin only")
    target = db.session.get(User, user_id)
    if target is None:
        raise not_found("User not found")
    target.is_suspended = False
    audit_service.record(admin, "user.unsuspended", "user", user_id)
    db.session.commit()
    return {"suspended": False}


class FeeSchema(ma.Schema):
    scope = ma.fields.String(required=True)
    bps = ma.fields.Integer(required=True, validate=ma.validate.Range(min=0, max=5000))


@jwt_required()
def set_fee():
    require_admin()
    data = parse_body(FeeSchema)
    row = fee_service.get_fee_row(data["scope"])
    if row is None:
        from app.models.payment import PlatformFee

        row = PlatformFee(scope=data["scope"], fee_bps=data["bps"])
        db.session.add(row)
    else:
        row.fee_bps = data["bps"]
    db.session.commit()
    return {"fee": {"scope": row.scope, "fee_bps": row.fee_bps}}


@jwt_required()
def list_fees():
    from app.models.payment import PlatformFee

    require_admin()
    rows = PlatformFee.query.all()
    return {"fees": [{"scope": f.scope, "fee_bps": f.fee_bps} for f in rows]}


@jwt_required()
def list_verifications():
    require_admin()
    state = query_params().get("state", "PENDING")
    rows = Verification.query.filter_by(status=state.upper()).limit(100).all()
    return {"verifications": [
        {"id": v.id, "user_id": v.user_id, "level": v.level, "status": v.status,
         "document_keys": [k for k in (v.document_keys or "").split(",") if k]}
        for v in rows
    ]}


class VerifyReviewSchema(ma.Schema):
    approve = ma.fields.Boolean(required=True)
    note = ma.fields.String(missing="")


@jwt_required()
def review_verification(verification_id):
    from datetime import datetime, timezone

    admin = require_admin()
    data = parse_body(VerifyReviewSchema)
    v = db.session.get(Verification, verification_id)
    if v is None:
        raise not_found("Verification not found")
    if v.status != "PENDING":
        raise conflict("Already reviewed")
    v.status = "APPROVED" if data["approve"] else "REJECTED"
    v.reviewed_by = admin.id
    v.review_note = data.get("note", "")
    v.reviewed_at = datetime.now(timezone.utc)

    target = db.session.get(User, v.user_id)
    if data["approve"]:
        levels = ["PHONE_VERIFIED", "ID_BASIC", "FARMER_PLUS", "BUSINESS"]
        idx = levels.index(v.level) if v.level in levels else -1
        current_idx = levels.index(getattr(target, "verification_level", None) or "") \
            if getattr(target, "verification_level", None) in levels else -1
        if idx > current_idx and hasattr(target, "verification_level"):
            target.verification_level = v.level
        fp = target.farmer_profile
        if fp and v.level == "FARMER_PLUS":
            fp.is_verified_farmer = True
    audit_service.record(admin, f"verification.{v.status.lower()}", "verification", v.id,
                         {"subject_user": v.user_id})
    notification_service.notify(v.user_id, "VERIFICATION_UPDATE",
                                f"Verification {v.status.lower()}",
                                data.get("note") or f"Your {v.level} verification was reviewed.",
                                commit=False)
    db.session.commit()
    return {"verification": {"id": v.id, "status": v.status}}


@jwt_required()
def review_dispute(dispute_id):
    admin = require_admin()
    data = parse_body(type("S", (ma.Schema,), {
        "state": ma.fields.String(required=True),
        "resolution_note": ma.fields.String(missing=""),
    })())
    dispute = dispute_service.transition_dispute(admin, dispute_id, data["state"].upper(),
                                                 resolution_note=data.get("resolution_note"))
    db.session.commit()
    return {"dispute": {"id": dispute.id, "state": dispute.state}}


@jwt_required()
def dispute_evidence(dispute_id):
    require_admin()
    rows = DisputeEvidence.query.filter_by(dispute_id=dispute_id).all()
    return {"evidence": [e.to_dict() for e in rows]}


@jwt_required()
def pending_withdrawals():
    require_admin()
    from app.models.payment import Withdrawal

    rows = Withdrawal.query.filter_by(state="REQUESTED").all()
    return {"withdrawals": [{"id": w.id, "user_id": w.user_id, "amount_minor": w.amount_minor,
                             "fee_minor": w.fee_minor, "method": w.destination_method,
                             "destination_detail": w.destination_detail} for w in rows]}


@jwt_required()
def process_withdrawal(withdrawal_id):
    admin = require_admin()
    action = (request.get_json(silent=True) or {}).get("action", "approve")
    if action == "approve":
        wd = wallet_service.approve_and_process_withdrawal(admin, withdrawal_id)
        db.session.commit()
        return {"withdrawal": {"id": wd.id, "state": wd.state}}
    wd = wallet_service.fail_withdrawal(admin, withdrawal_id)
    db.session.commit()
    return {"withdrawal": {"id": wd.id, "state": wd.state}}


class AlertSchema(ma.Schema):
    alert_type = ma.fields.String(required=True)
    severity = ma.fields.String(missing="WARNING")
    title = ma.fields.String(required=True)
    message_text = ma.fields.String(missing="")
    region = ma.fields.String()


@jwt_required()
def create_emergency_alert():
    from app.models.intelligence import EmergencyAlert
    from extensions.realtime import realtime

    admin = require_admin()
    data = parse_body(AlertSchema)
    alert = EmergencyAlert(alert_type=data["alert_type"], severity=data["severity"],
                           title=data["title"], message_text=data.get("message_text", ""),
                           region=data.get("region"), created_by=admin.id)
    db.session.add(alert)
    db.session.flush()

    users = User.query.filter(User.deleted_at.is_(None)).all() if not data.get("region") else []
    batch = NotificationBatch(batch_type="EMERGENCY_ALERT", total_count=len(users))
    db.session.add(batch)
    db.session.flush()
    for u in users:
        n = notification_service.notify(u.id, "EMERGENCY_ALERT", data["title"],
                                        data.get("message_text", ""), subject_type="emergency_alert",
                                        subject_id=alert.id, batch_key=batch.id, commit=False)
    realtime.emit("alert.broadcast", alert.to_dict(), room="alerts")
    db.session.commit()
    return {"alert": alert.to_dict(), "notified": len(users)}, 201


@jwt_required()
def resolve_alert(alert_id):
    require_admin()
    from app.models.intelligence import EmergencyAlert

    alert = db.session.get(EmergencyAlert, alert_id)
    if alert is None:
        raise not_found("Alert not found")
    alert.state = "RESOLVED"
    db.session.commit()
    return {"alert": alert.to_dict()}


@jwt_required()
def risk_events():
    require_admin()
    flagged_only = query_params().get("flagged") == "true"
    q = RiskEvent.query
    if flagged_only:
        q = q.filter(RiskEvent.flagged.is_(True))
    rows = q.order_by(RiskEvent.created_at.desc()).limit(200).all()
    return {"events": [e.to_dict() for e in rows]}


@jwt_required()
def audit_logs():
    require_admin()
    page, per_page = pagination_args(default_per_page=100)
    pg = AuditLog.query.order_by(AuditLog.created_at.desc()).paginate(page=page, per_page=per_page, error_out=False)
    return paginate_response(pg, lambda a: a.to_dict())


@jwt_required()
def export_requests():
    require_admin()
    rows = ExportRequest.query.filter_by(state="REQUESTED").order_by(ExportRequest.created_at.asc()).all()
    return {"requests": [{"id": r.id, "user_id": r.user_id, "requested_at": r.created_at.isoformat()}
                         for r in rows]}


@jwt_required()
def deletion_requests():
    require_admin()
    rows = DeletionRequest.query.order_by(DeletionRequest.requested_at.desc()).limit(100).all()
    return {"requests": [{"id": r.id, "user_id": r.user_id,
                          "requested_at": r.requested_at.isoformat()} for r in rows]}


@jwt_required()
def analytics_overview():
    require_admin()
    from sqlalchemy import func

    from app.models.order import Order
    from app.models.payment import PaymentTransaction, WalletLedgerEntry
    from app.models.marketplace import Listing

    gmv = db.session.query(func.coalesce(func.sum(Order.total_amount_minor), 0)) \
        .filter(Order.state.in_(("PAID", "PROCESSING", "READY_FOR_PICKUP", "IN_TRANSIT",
                                 "DELIVERED", "COMPLETED"))).scalar()
    fees = db.session.query(func.coalesce(func.sum(WalletLedgerEntry.amount_minor), 0)) \
        .filter(WalletLedgerEntry.entry_type == "CREDIT",
                WalletLedgerEntry.reason_code == "PLATFORM_FEE").scalar()
    active_listings = Listing.query.filter_by(state="ACTIVE").count()
    orders_total = Order.query.count()
    failed_payments = PaymentTransaction.query.filter_by(state="FAILED").count()
    return {
        "gmv_minor": int(gmv),
        "platform_fees_minor": int(fees),
        "active_listings": active_listings,
        "orders_total": orders_total,
        "failed_payments": failed_payments,
    }
