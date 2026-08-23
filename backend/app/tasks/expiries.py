from extensions import celery, db
from flask import current_app


@celery.task(name="tasks.expire_marketplace_objects")
def expire_marketplace_objects():
    from app.services.bid_service import expire_auctions
    from app.services.listing_expiry import expire_listings
    from app.services.offer_service import expire_stale_offers
    from app.services.status_service import expire_statuses

    with current_app.app_context():
        return {
            "auctions": expire_auctions(),
            "offers": expire_stale_offers(),
            "statuses": expire_statuses(),
            "listings": expire_listings(),
        }


@celery.task(name="tasks.dispatch_notification_batches")
def dispatch_notification_batches():
    from datetime import timedelta

    from app.models.base import utcnow
    from app.models.notifications import NotificationBatch
    from app.services.notification_service import dispatch_push_for

    with current_app.app_context():
        cutoff = utcnow() - timedelta(minutes=5)
        pending = (
            db.session.query(NotificationBatch)
            .filter(NotificationBatch.flushed.is_(False), NotificationBatch.created_at < cutoff)
            .limit(500)
            .all()
        )
        flushed = 0
        for batch in pending:
            notifications = (
                __import__("app.models.notifications", fromlist=["Notification"]).Notification.query
                .filter_by(user_id=batch.user_id, batch_key=batch.batch_key, pushed_at=None)
                .order_by(Notification.created_at.desc())
                .limit(10)
                .all()
            )
            if notifications:
                dispatch_push_for(notifications[0])
            batch.flushed = True
            flushed += 1
        db.session.commit()
        return {"batches_flushed": flushed}


@celery.task(name="tasks.recompute_reputation")
def recompute_reputation():
    from app.models.identity import FarmerProfile
    from app.services.reputation_service import recompute_farmer_reputation

    with current_app.app_context():
        profiles = FarmerProfile.query.limit(2000).all()
        updated = 0
        for p in profiles:
            if recompute_farmer_reputation(p.user_id):
                updated += 1
        db.session.commit()
        return {"profiles_updated": updated}
