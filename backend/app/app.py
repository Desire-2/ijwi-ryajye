"""Application factory for the Ijwi Ryajye API."""
import logging
import os

from flask import Flask, jsonify
from werkzeug.middleware.proxy_fix import ProxyFix

from config import get_config
from extensions import (
    bcrypt,
    celery,
    configure_celery,
    cors,
    db,
    jwt,
    limiter,
    migrate,
    socketio,
)


def create_app(config_name=None):
    config_name = config_name or os.environ.get("FLASK_ENV", "development")
    app = Flask(__name__)
    app.config.from_object(get_config(config_name))

    app.wsgi_app = ProxyFix(app.wsgi_app, x_for=1, x_proto=1)

    db.init_app(app)
    migrate.init_app(app, db, directory=os.path.join(os.path.dirname(__file__), "..", "migrations"))

    import app.models  # noqa: F401 – ensure all models are registered before create_all

    with app.app_context():
        db.create_all()

    bcrypt.init_app(app)
    jwt.init_app(app)
    cors.init_app(app, resources={r"/api/*": {"origins": app.config.get("CORS_ORIGINS", "*")}})
    socketio.init_app(app, cors_allowed_origins=app.config.get("CORS_ORIGINS", "*"),
                      async_mode="threading", logger=False, engineio_logger=False)
    limiter.init_app(app)

    from extensions import realtime

    realtime.bind(socketio)

    from app.services.auth_service import register_hooks

    register_hooks(app)

    from app.middleware import register_middleware

    register_middleware(app)

    from app.api import register_api

    register_api(app)

    from app.realtime.socket_server import register_socket_events

    register_socket_events(socketio)

    from app.payments.gateway import register_providers

    with app.app_context():
        register_providers(app)
        if app.config.get("ENSURE_DEFAULT_FEES", True):
            try:
                from app.services.fee_service import ensure_default_fees

                ensure_default_fees()
                db.session.commit()
            except Exception:
                db.session.rollback()

    configure_celery(app)

    @app.get("/health")
    def _health():
        return jsonify({"status": "ok", "service": "ijwi-ryajye-api"})

    return app


def create_wsgi_app():
    logging.basicConfig(level=logging.INFO)
    return create_app(os.environ.get("FLASK_ENV", "production"))


if __name__ == "__main__":
    application = create_app("development")
    socketio.run(application, host="0.0.0.0", port=int(os.environ.get("PORT", 8000)),
                 allow_unsafe_werkzeug=True)
