import json

from extensions import db
from app.errors import bad_request, conflict, not_found
from app.models.base import utcnow
from app.models.order import Order, OrderEvent
from app.models.payment import (
    PaymentTransaction,
    PaymentWebhookEvent,
    WalletLedgerEntry,
    Withdrawal,
)
from app.payments.gateway import get_provider
from app.services import order_service, wallet_service
from app.services.audit_service import record as audit
from app.services.notification_service import notify


def initiate_payment(user, order_id, provider_name, method, phone=None):
    order = db.session.get(Order, order_id)
    if order is None:
        raise not_found("Order not found")
    if order.buyer_id != user.id:
        raise bad_request("Only the buyer can initiate payment for this order")
    if order.state not in ("ACCEPTED", "PAYMENT_PENDING"):
        raise conflict(f"Order in state {order.state} cannot be paid now")

    idempotency_key = f"payinit:{order.id}:{user.id}"
    existing = PaymentTransaction.query.filter_by(idempotency_key=idempotency_key).first()
    if existing is not None and existing.state not in ("FAILED", "CANCELLED"):
        return existing

    provider = get_provider(provider_name)
    result = provider.initiate_payment(
        order,
        int(order.total_amount_minor),
        order.currency_code,
        method,
        phone=phone or user.phone,
        idempotency_key=idempotency_key,
    )

    txn = PaymentTransaction(
        order_id=order.id,
        user_id=user.id,
        direction="COLLECTION",
        provider=provider.code,
        provider_reference=result.get("provider_reference"),
        method=method,
        state=result["state"],
        amount_minor=int(order.total_amount_minor),
        currency_code=order.currency_code,
        idempotency_key=None if existing is not None else idempotency_key,
    )
    db.session.add(txn)

    order_service.transition_order(
        user, order, "PAYMENT_PENDING", reason=f"Payment initiated via {provider.code}"
    )
    db.session.flush()
    audit(user, "payment.initiated", "payment", txn.id, {"provider": provider.code})
    return txn


def process_webhook(provider_code, payload_bytes, headers):
    provider = get_provider(provider_code)
    result = provider.verify_webhook(payload_bytes, headers)

    event = PaymentWebhookEvent.query.filter_by(
        provider=provider.code, event_id=result.event_id
    ).first()
    if event is not None:
        return {"status": "duplicate", "event_id": result.event_id}

    event = PaymentWebhookEvent(
        provider=provider.code,
        event_id=result.event_id or f"unsigned-{utcnow().timestamp()}",
        signature_valid=result.signature_valid,
        payload_json=payload_bytes.decode(errors="replace")[:20000],
    )
    db.session.add(event)
    db.session.flush()

    if not result.signature_valid:
        event.processing_error = "invalid signature"
        db.session.commit()
        raise bad_request("Webhook signature verification failed", "INVALID_WEBHOOK_SIGNATURE")

    if result.state in ("IGNORED", "PROCESSING"):
        event.processed = True
        db.session.commit()
        return {"status": "ignored", "state": result.state}

    txn = PaymentTransaction.query.filter_by(
        provider=provider.code, provider_reference=result.payment_reference
    ).first()

    if txn is None:
        event.processing_error = "no matching transaction"
        db.session.commit()
        raise not_found("No matching payment transaction for webhook reference")

    _apply_payment_state(txn, result.state, result.provider_metadata)

    event.processed = True
    audit(None, "payment.webhook_processed", "payment", txn.id, {"state": result.state})
    db.session.commit()
    return {"status": "processed", "payment_state": txn.state}


def _apply_payment_state(txn, new_state, metadata):
    order = db.session.get(Order, txn.order_id) if txn.order_id else None

    if new_state == "SUCCEEDED" and txn.state != "SUCCEEDED":
        txn.state = "SUCCEEDED"
        txn.completed_at = utcnow()
        if order is not None and txn.direction == "COLLECTION":
            order_service.mark_paid_system(order.id, txn)
            ledger_key = f"order:{order.id}:settlement:{txn.id}"
            wallet_service.credit_sale_proceeds(order.seller_id, order, ledger_key)
            wallet_service.record_platform_fee_earned(order, f"order:{order.id}:fee:{txn.id}")
            notify(order.seller_id, "PAYMENT", "Payment received",
                   f"Order {order.order_number} has been paid.", subject_type="order", subject_id=order.id)
            notify(order.buyer_id, "PAYMENT", "Payment confirmed",
                   f"Your payment for {order.order_number} succeeded.", subject_type="order", subject_id=order.id)

    elif new_state == "FAILED" and txn.state not in ("SUCCEEDED", "REFUNDED"):
        txn.state = "FAILED"
        txn.failure_reason = json.dumps(metadata)[:250]
        notify(txn.user_id, "PAYMENT", "Payment failed",
               "Your payment could not be completed. Please try again.", subject_type="payment", subject_id=txn.id)

    elif new_state == "REFUNDED" and txn.state == "SUCCEEDED":
        txn.state = "REFUNDED"

    db.session.flush()


def refund_order(order, admin_actor, reason):
    from app.services.wallet_service import get_or_create_wallet

    txns = PaymentTransaction.query.filter_by(order_id=order.id, direction="COLLECTION", state="SUCCEEDED").all()
    refunded_any = False
    for txn in txns:
        seller_wallet = get_or_create_wallet(order.seller_id)
        seller_net_entry = WalletLedgerEntry.query.filter(
            WalletLedgerEntry.reference_type == "order",
            WalletLedgerEntry.reference_id == order.id,
            WalletLedgerEntry.reason_code == "SALE_EARNING",
            WalletLedgerEntry.wallet_id == seller_wallet.id,
        ).first()
        if seller_net_entry is not None:
            wallet_service.post_entry(
                order.seller_id, "DEBIT", "REFUND_TO_BUYER",
                -int(seller_net_entry.amount_minor),
                reference_type="order", reference_id=order.id,
                description=f"Refund clawback for order {order.order_number}",
                idempotency_key=f"refund:{order.id}:seller",
            )
        fee_entry = WalletLedgerEntry.query.filter(
            WalletLedgerEntry.reference_id == order.id,
            WalletLedgerEntry.reason_code == "PLATFORM_FEE",
        ).first()
        if fee_entry is not None:
            wallet_service.post_entry(
                wallet_service.PLATFORM_FEE_SINK_USER_ID, "DEBIT", "PLATFORM_FEE",
                -int(fee_entry.amount_minor),
                reference_type="order", reference_id=order.id,
                description=f"Fee reversal for refunded order {order.order_number}",
                idempotency_key=f"refund:{order.id}:fee",
            )
        txn.state = "REFUNDED"
        refunded_any = True

    if not refunded_any:
        raise conflict("No successful payment found to refund for this order")

    audit(admin_actor, "payment.refunded", "order", order.id, {"reason": reason})
    return True
