from extensions import db
from app.models.payment import PlatformFee

FALLBACK_BPS = {
    "MARKETPLACE_SALE": 250,
    "LOGISTICS_JOB": 100,
    "WITHDRAWAL": 0,
    "LISTING_PROMOTION": 0,
}


def get_fee_row(scope):
    return PlatformFee.query.filter_by(scope=scope, active=True).first()


def fee_for_scope(total_minor, scope):
    from app.utils.money import fee_for

    row = get_fee_row(scope)
    return fee_for(int(total_minor), row, default_bps=FALLBACK_BPS.get(scope, 0))


def ensure_default_fees():
    for scope, bps in FALLBACK_BPS.items():
        row = PlatformFee.query.filter_by(scope=scope).first()
        if row is None:
            db.session.add(PlatformFee(scope=scope, bps=bps))
    db.session.commit()
