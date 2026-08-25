from datetime import timedelta

from extensions import db
from app.models.base import utcnow
from app.models.marketplace import Listing


def expire_listings():
    now = utcnow()
    expired = Listing.query.filter(
        Listing.state == "ACTIVE",
        Listing.expires_at.isnot(None),
        Listing.expires_at <= now,
    ).limit(500).all()
    count = 0
    for listing in expired:
        listing.state = "EXPIRED"
        count += 1
    if expired:
        db.session.commit()
    return count
