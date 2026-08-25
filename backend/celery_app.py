"""Celery entrypoint: `celery -A celery_app.celery worker` / `... beat`."""
import os

from app.app import create_app
from extensions import celery

app = create_app(os.environ.get("FLASK_ENV", "production"))


class ContextTask(celery.Task):
    def __call__(self, *args, **kwargs):
        with app.app_context():
            return self.run(*args, **kwargs)


celery.Task = ContextTask
