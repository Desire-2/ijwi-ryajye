from extensions import celery


@celery.task(name="tasks.send_event_reminders")
def send_event_reminders():
    from app.services.social_service import dispatch_event_reminders

    with __import__("flask").current_app.app_context():
        return {"reminders_sent": dispatch_event_reminders()}
