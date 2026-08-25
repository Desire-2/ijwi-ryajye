from celery import Celery
from flask_bcrypt import Bcrypt
from flask_cors import CORS
from flask_jwt_extended import JWTManager
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address
from flask_migrate import Migrate
from flask_socketio import SocketIO
from flask_sqlalchemy import SQLAlchemy

db = SQLAlchemy()
migrate = Migrate()
bcrypt = Bcrypt()
jwt = JWTManager()
cors = CORS()
socketio = SocketIO(cors_allowed_origins="*", async_mode="threading", manage_session=False)

limiter = Limiter(key_func=get_remote_address, storage_uri="memory://")

celery = Celery(
    "ijwi",
    include=[
        "app.tasks.expiries",
        "app.tasks.notifications",
        "app.tasks.intelligence",
        "app.tasks.trust",
    ],
)


def configure_celery(app):
    celery.conf.update(
        broker_url=app.config.get("CELERY_BROKER_URL") or "memory://",
        result_backend=app.config.get("CELERY_RESULT_BACKEND") or "cache+memory://",
        task_always_eager=app.config.get("TESTING", False),
        task_eager_propagates=True,
        beat_schedule={
            "expire-marketplace-objects": {
                "task": "tasks.expire_marketplace_objects",
                "schedule": 60.0,
            },
            "dispatch-notification-batches": {
                "task": "tasks.dispatch_notification_batches",
                "schedule": 120.0,
            },
            "recompute-reputation": {"task": "tasks.recompute_reputation", "schedule": 3600.0},
        },
    )


class SocketIOEventEmitter:
    def __init__(self):
        self._socketio = None

    def bind(self, socketio):
        self._socketio = socketio

    def emit(self, event, payload, room=None):
        if self._socketio is None:
            return
        try:
            self._socketio.emit(event, payload, room=room)
        except Exception:
            pass

    def emit_to_user(self, user_id, event, payload):
        self.emit(event, payload, room=f"user:{user_id}")

    def emit_to_conversation(self, conversation_id, event, payload):
        self.emit(event, payload, room=f"conversation:{conversation_id}")


realtime = SocketIOEventEmitter()
