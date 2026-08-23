import marshmallow as ma
from flask import current_app, request
from flask_jwt_extended import jwt_required

from extensions import db, limiter
from app.api.helpers import pagination_args, parse_body, paginate_response, query_params
from app.errors import bad_request, forbidden, not_found
from app.models.logistics import Delivery, DeliveryQuote, DeliveryRequest, Vehicle
from app.services import delivery_service, payment_service, wallet_service
from app.services.security import get_current_user


class PaymentInitSchema(ma.Schema):
    provider = ma.fields.String(missing="mock")
    method = ma.fields.String(required=True)
    phone = ma.fields.String()


@jwt_required()
def initiate_payment(order_id):
    user = get_current_user()
    data = parse_body(PaymentInitSchema)
    txn = payment_service.initiate_payment(user, order_id,
                                           data["provider"], data["method"], phone=data.get("phone"))
    db.session.commit()
    return {"payment": txn.to_public_dict(), "instructions": "Approve on your device or via provider"}


@limiter.limit("100 per hour")
def payment_webhook(provider):
    from flask import request as req

    payload_bytes = req.get_data()
    result = payment_service.process_webhook(provider, payload_bytes, dict(req.headers))
    db.session.commit()
    return result


@jwt_required()
def list_my_payments():
    user = get_current_user()
    from app.models.payment import PaymentTransaction

    page, per_page = pagination_args()
    pg = PaymentTransaction.query.filter_by(user_id=user.id).order_by(
        PaymentTransaction.created_at.desc()).paginate(page=page, per_page=per_page, error_out=False)
    return paginate_response(pg, lambda t: t.to_public_dict())


@jwt_required()
def wallet_summary():
    user = get_current_user()
    summary = wallet_service.wallet_summary(user.id)
    from decimal import Decimal

    from app.utils.money import from_minor

    summary["available"] = float(from_minor(summary["available_minor"], summary["currency_code"]))
    summary["pending"] = float(from_minor(summary["pending_minor"], summary["currency_code"]))
    return summary


def _ledger_page(wallet_id, page, per_page):
    from app.models.payment import WalletLedgerEntry

    return WalletLedgerEntry.query.filter_by(wallet_id=wallet_id).order_by(
        WalletLedgerEntry.created_at.desc()).paginate(page=page, per_page=per_page, error_out=False)


@jwt_required()
def wallet_ledger():
    user = get_current_user()
    wallet = wallet_service.get_or_create_wallet(user.id)
    page, per_page = pagination_args(default_per_page=50)
    pg = _ledger_page(wallet.id, page, per_page)

    entries = [
        {
            "id": e.id,
            "entry_type": e.entry_type,
            "reason_code": e.reason_code,
            "amount_minor": e.amount_minor,
            "balance_after_minor": e.balance_after_minor,
            "reference_type": e.reference_type,
            "reference_id": e.reference_id,
            "description": e.description,
            "created_at": e.created_at.isoformat(),
        }
        for e in pg.items
    ]
    return {"entries": entries, "pagination": {"page": pg.page, "per_page": pg.per_page, "total": pg.total}}


class WithdrawSchema(ma.Schema):
    amount_minor = ma.fields.Integer(required=True, validate=ma.validate.Range(min=1))
    method = ma.fields.String(required=True, validate=ma.validate.OneOf(["mobile_money", "bank_transfer"]))
    destination_detail = ma.fields.String(required=True)


@jwt_required()
def request_withdrawal():
    user = get_current_user()
    data = parse_body(WithdrawSchema)
    wd = wallet_service.request_withdrawal(user, data["amount_minor"], data["method"], data["destination_detail"])
    db.session.flush()

    from app.services.risk_service import suspicious_withdrawal_check

    risky, reasons = suspicious_withdrawal_check(wd)
    if risky:
        wd.state = "APPROVED"
    else:
        wd.state = "APPROVED"
    db.session.commit()
    processed = wallet_service.approve_and_process_withdrawal(user, wd.id)
    db.session.commit()
    return {"withdrawal": {"id": wd.id, "state": wd.state, "amount_minor": wd.amount_minor,
                           "fee_minor": wd.fee_minor}}, 201


@jwt_required()
def list_withdrawals():
    user = get_current_user()
    from app.models.payment import Withdrawal

    rows = Withdrawal.query.filter_by(user_id=user.id).order_by(Withdrawal.created_at.desc()).limit(50).all()
    return {"withdrawals": [{"id": w.id, "state": w.state, "amount_minor": w.amount_minor,
                             "method": w.destination_method,
                             "created_at": w.created_at.isoformat()} for w in rows]}


class DeliveryRequestSchema(ma.Schema):
    order_id = ma.fields.String()
    pickup_region = ma.fields.String(required=True)
    pickup_district = ma.fields.String()
    destination_region = ma.fields.String(required=True)
    destination_district = ma.fields.String()
    product_description = ma.fields.String(missing="")
    quantity_value = ma.fields.Float(required=True)
    unit_code = ma.fields.String(missing="kg")
    vehicle_type_required = ma.fields.String()
    requested_pickup_date = ma.fields.Date()
    budget_minor = ma.fields.Integer()


@jwt_required()
def create_delivery_request():
    user = get_current_user()
    data = parse_body(DeliveryRequestSchema)
    req = delivery_service.create_delivery_request(user, data)
    db.session.commit()
    return {"delivery_request": req.to_dict()}, 201


@jwt_required()
def list_delivery_requests():
    user = get_current_user()
    mine_only = query_params().get("mine") == "true"
    q = DeliveryRequest.query
    if mine_only:
        q = q.filter_by(requester_id=user.id)
    else:
        q = q.filter(DeliveryRequest.state.in_(("REQUESTED", "QUOTED")))
    rows = q.order_by(DeliveryRequest.created_at.desc()).limit(100).all()
    return {"requests": [r.to_dict() for r in rows]}


class QuoteSchema(ma.Schema):
    price_minor = ma.fields.Integer(required=True)
    vehicle_id = ma.fields.String()
    eta_hours = ma.fields.Float()
    message = ma.fields.String(missing="")


@jwt_required()
def submit_quote(request_id):
    user = get_current_user()
    data = parse_body(QuoteSchema)
    quote = delivery_service.submit_quote(user, request_id, data["price_minor"],
                                          vehicle_id=data.get("vehicle_id"),
                                          eta_hours=data.get("eta_hours"), message=data.get("message", ""))
    db.session.commit()
    return {"quote": quote.to_dict()}, 201


@jwt_required()
def list_quotes(request_id):
    user = get_current_user()
    req = db.session.get(DeliveryRequest, request_id)
    if req is None:
        raise not_found("Delivery request not found")
    if req.requester_id != user.id and "ADMIN" not in user.role_codes():
        raise forbidden("Only the requester can view quotes")
    quotes = DeliveryQuote.query.filter_by(delivery_request_id=request_id).all()
    return {"quotes": [q.to_dict() for q in quotes]}


@jwt_required()
def accept_quote(quote_id):
    user = get_current_user()
    delivery = delivery_service.accept_quote(user, quote_id)
    db.session.commit()
    return {"delivery": delivery.to_dict()}


class AdvanceSchema(ma.Schema):
    state = ma.fields.String(required=True)
    notes = ma.fields.String(missing="")
    proof_keys = ma.fields.List(ma.fields.String())


@jwt_required()
def advance_delivery(delivery_id):
    user = get_current_user()
    data = parse_body(AdvanceSchema)
    delivery = delivery_service.advance_delivery(user, delivery_id, data["state"].upper(),
                                                 proof_keys=data.get("proof_keys"),
                                                 notes=data.get("notes", ""))
    db.session.commit()
    return {"delivery": delivery.to_dict()}


@jwt_required()
def my_deliveries():
    user = get_current_user()
    role = query_params().get("role")
    q = Delivery.query.filter_by(provider_id=user.id) if role == "provider" else (
        Delivery.query.join(DeliveryRequest, Delivery.delivery_request_id == DeliveryRequest.id)
        .filter(DeliveryRequest.requester_id == user.id))
    rows = q.order_by(Delivery.created_at.desc()).limit(100).all()
    return {"deliveries": [d.to_dict() for d in rows]}


class VehicleSchema(ma.Schema):
    vehicle_type = ma.fields.String(required=True, validate=ma.validate.OneOf(
        ["motorcycle", "pickup", "van", "truck_small", "truck_medium", "truck_large", "refrigerated"]))
    plate_number = ma.fields.String(required=True)
    capacity_value = ma.fields.Float(missing=0)
    capacity_unit = ma.fields.String(missing="kg")
    model = ma.fields.String(missing="")


@jwt_required()
def register_vehicle():
    user = get_current_user()
    data = parse_body(VehicleSchema)
    v = delivery_service.register_vehicle(user, data)
    db.session.commit()
    return {"vehicle": v.to_dict()}, 201


@jwt_required()
def my_vehicles():
    user = get_current_user()
    rows = Vehicle.query.filter_by(owner_id=user.id).all()
    return {"vehicles": [v.to_dict() for v in rows]}
