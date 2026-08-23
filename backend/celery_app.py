"""Celery entrypoint: `celery -A celery_app.celery worker` / `... beat`."""
import os

from app.app import create_app
from extensions import celery

create_app(os.environ.get("FLASK_ENV", "production"))
