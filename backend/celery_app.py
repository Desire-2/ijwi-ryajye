"""Celery entrypoint: `celery -A celery_app.celery worker` / `... beat`."""
import os
from pathlib import Path

from dotenv import load_dotenv

load_dotenv(Path(__file__).resolve().parent / ".env")

from app.app import create_app  # noqa: E402
from extensions import celery  # noqa: E402

app = create_app(os.environ.get("FLASK_ENV", "production"))


class ContextTask(celery.Task):
    def __call__(self, *args, **kwargs):
        with app.app_context():
            return self.run(*args, **kwargs)


celery.Task = ContextTask
