from decimal import ROUND_HALF_UP, Decimal

from app.errors import bad_request

CURRENCY_DECIMALS = {"RWF": 0, "USD": 2, "EUR": 2, "KES": 2, "UGX": 0, "TZS": 2, "XOF": 0}


def to_minor(amount, currency):
    decimals = CURRENCY_DECIMALS.get(currency)
    if decimals is None:
        raise bad_request(f"Unsupported currency: {currency}", "UNSUPPORTED_CURRENCY")
    try:
        d = Decimal(str(amount))
    except Exception:
        raise bad_request("Invalid amount", "INVALID_AMOUNT")
    factor = Decimal(10) ** decimals
    return int((d * factor).quantize(Decimal("1"), rounding=ROUND_HALF_UP))


def from_minor(minor_amount, currency):
    decimals = CURRENCY_DECIMALS.get(currency, 2)
    return Decimal(minor_amount) / (Decimal(10) ** decimals)


def fee_for(total_minor, fee_row, default_bps=250):
    bps = fee_row.bps if fee_row is not None else default_bps
    fee = (Decimal(total_minor) * Decimal(bps)) / Decimal(10000)
    fee_int = int(fee.quantize(Decimal("1"), rounding=ROUND_HALF_UP))
    if fee_row is not None:
        if fee_row.min_fee_minor and fee_int < fee_row.min_fee_minor:
            fee_int = fee_row.min_fee_minor
        if fee_row.max_fee_minor and fee_int > fee_row.max_fee_minor:
            fee_int = fee_row.max_fee_minor
    return fee_int


def validate_positive_quantity(value, field="quantity"):
    from decimal import InvalidOperation

    try:
        q = Decimal(str(value))
    except InvalidOperation:
        raise bad_request(f"{field} must be a number", "INVALID_QUANTITY")
    if q <= 0:
        raise bad_request(f"{field} must be greater than zero", "INVALID_QUANTITY")
    return q
