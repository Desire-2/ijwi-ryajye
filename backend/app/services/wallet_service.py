from decimal import Decimal

from sqlalchemy import text

from extensions import db, realtime
from app.errors import bad_request, conflict, not_found
from app.models.base import utcnow
from app.models.payment import Wallet, WalletLedgerEntry, Withdrawal


def get_or_create_wallet(user_id, currency="RWF", cooperative_id=None):
    wallet = Wallet.query.filter_by(user_id=user_id).first()
    if wallet is None:
        wallet = Wallet(user_id=user_id, currency_code=currency, cooperative_id=cooperative_id)
        db.session.add(wallet)
        db.session.flush()
    return wallet


def _lock_wallet(wallet_id) -> Wallet:
    if db.engine.dialect.name == "sqlite":
        wallet = db.session.get(Wallet, wallet_id)
        if wallet is None:
            raise not_found("Wallet not found")
        return wallet
    row = db.session.execute(
        text("SELECT id FROM wallets WHERE id = :id FOR UPDATE"), {"id": wallet_id}
    ).fetchone()
    if row is None:
        raise not_found("Wallet not found")
    return db.session.get(Wallet, wallet_id)


def post_entry(
    user_id,
    entry_type,
    reason_code,
    amount_minor,
    reference_type="",
    reference_id="",
    description="",
    idempotency_key=None,
    pending_delta_minor=0,
    currency=None,
):
    if amount_minor == 0 and pending_delta_minor == 0:
        raise bad_request("Ledger entry cannot be zero")

    if idempotency_key:
        existing = WalletLedgerEntry.query.filter_by(idempotency_key=idempotency_key).first()
        if existing is not None:
            return existing

    wallet = get_or_create_wallet(user_id)
    wallet = _lock_wallet(wallet.id)

    available = int(wallet.available_balance_minor)
    pending = int(wallet.pending_balance_minor)

    new_pending = pending + int(pending_delta_minor)
    new_available = available + int(amount_minor)

    if new_available < 0:
        raise conflict(
            f"Insufficient funds: balance {available}, attempted {int(amount_minor)}",
            code="INSUFFICIENT_FUNDS",
            details={"balance": available, "amount": int(amount_minor)},
        )

    wallet.available_balance_minor = new_available
    wallet.pending_balance_minor = new_pending

    if reason_code == "SALE_EARNING":
        wallet.total_earned_minor = int(wallet.total_earned_minor) + int(amount_minor)
    if reason_code == "WITHDRAWAL":
        wallet.total_withdrawn_minor = int(wallet.total_withdrawn_minor) + (-int(amount_minor))

    entry = WalletLedgerEntry(
        wallet_id=wallet.id,
        entry_type=entry_type,
        reason_code=reason_code,
        amount_minor=int(amount_minor),
        balance_after_minor=new_available,
        pending_delta_minor=int(pending_delta_minor),
        pending_balance_after_minor=new_pending,
        currency_code=currency or wallet.currency_code,
        reference_type=reference_type,
        reference_id=str(reference_id),
        description=description,
        idempotency_key=idempotency_key,
    )
    db.session.add(entry)
    db.session.flush()
    realtime.emit_to_user(user_id, "wallet.updated", {
        "wallet_id": wallet.id,
        "available_minor": new_available,
        "pending_minor": new_pending,
        "entry_type": entry_type,
        "reason_code": reason_code,
        "reference_type": reference_type,
        "reference_id": str(reference_id),
    })
    return entry


def credit_sale_proceeds(seller_user_id, order, idempotency_key):
    net = int(order.total_amount_minor) - int(order.platform_fee_minor or 0)
    return post_entry(
        seller_user_id,
        "CREDIT",
        "SALE_EARNING",
        net,
        reference_type="order",
        reference_id=order.id,
        description=f"Net proceeds for order {order.order_number}",
        idempotency_key=f"{idempotency_key}:net",
    )


def record_platform_fee_earned(order, idempotency_key):
    return post_entry(
        PLATFORM_FEE_SINK_USER_ID,
        "CREDIT",
        "PLATFORM_FEE",
        int(order.platform_fee_minor or 0),
        reference_type="order",
        reference_id=order.id,
        description=f"Platform fee for order {order.order_number}",
        idempotency_key=f"{idempotency_key}:fee",
    )


PLATFORM_FEE_SINK_USER_ID = "platform-fee-sink"


def request_withdrawal(user, amount_minor, method, destination_detail):
    from app.services.fee_service import fee_for_scope

    amount = int(amount_minor)
    if amount <= 0:
        raise bad_request("Withdrawal amount must be positive")
    fee = fee_for_scope(amount, "WITHDRAWAL")
    wallet = get_or_create_wallet(user.id)

    wd = Withdrawal(
        user_id=user.id,
        wallet_id=wallet.id,
        amount_minor=amount,
        fee_minor=fee,
        currency_code=wallet.currency_code,
        destination_method=method,
        destination_detail=destination_detail,
        state="REQUESTED",
    )
    db.session.add(wd)
    db.session.flush()
    return wd


def approve_and_process_withdrawal(admin_or_system, withdrawal_id):
    wd = db.session.get(Withdrawal, withdrawal_id)
    if wd is None:
        raise not_found("Withdrawal not found")
    if wd.state != "REQUESTED":
        raise conflict(f"Withdrawal is {wd.state.lower()}")

    wallet = _lock_wallet(wd.wallet_id)
    total_debit = int(wd.amount_minor) + int(wd.fee_minor or 0)
    if int(wallet.available_balance_minor) < total_debit:
        raise conflict("Insufficient funds for this withdrawal", "INSUFFICIENT_FUNDS")

    entry = post_entry(
        wd.user_id,
        "DEBIT",
        "WITHDRAWAL",
        -total_debit,
        reference_type="withdrawal",
        reference_id=wd.id,
        description=f"Withdrawal via {wd.destination_method}",
        idempotency_key=f"withdrawal:{wd.id}:debit",
    )

    wd.state = "PROCESSING"
    provider_ref = f"po_{wd.id[:12]}"
    wd.provider_reference = provider_ref
    wd.state = "COMPLETED"
    wd.completed_at = utcnow()
    _audit_wd(admin_or_system, wd)
    return wd


def _audit_wd(actor, wd):
    from app.services.audit_service import record as audit
    audit(actor, "withdrawal.processed", "withdrawal", wd.id, {"amount": wd.amount_minor})
    return None


def fail_withdrawal(actor, withdrawal_id, reason):
    wd = db.session.get(Withdrawal, withdrawal_id)
    wd.state = "FAILED"
    wd.failure_reason = reason
    return wd


def wallet_summary(user_id):
    wallet = get_or_create_wallet(user_id)
    return {
        "wallet_id": wallet.id,
        "currency_code": wallet.currency_code,
        "available_minor": int(wallet.available_balance_minor),
        "pending_minor": int(wallet.pending_balance_minor),
        "total_earned_minor": int(wallet.total_earned_minor),
        "total_withdrawn_minor": int(wallet.total_withdrawn_minor),
    }
