from extensions import celery, db


@celery.task(name="tasks.refresh_weather_cache")
def refresh_weather_cache():
    from app.models.base import utcnow
    from app.models.intelligence import WeatherRecord

    with __import__("flask").current_app.app_context():
        stale_cutoff = utcnow().replace(microsecond=0)
        recent = WeatherRecord.query.limit(1).count()
        return {"cached_regions": recent}
