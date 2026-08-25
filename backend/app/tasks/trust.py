from extensions import celery


@celery.task(name="trust.schedule_reputation_update")
def schedule_reputation_update(*user_ids):
    from app.services.reputation_service import recompute_farmer_reputation

    with __import__("flask").current_app.app_context():
        for uid in user_ids:
            recompute_farmer_reputation(uid)
        __import__("extensions").db.session.commit()
        return {"updated": len(user_ids)}
