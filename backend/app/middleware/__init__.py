import json
import logging
import time
import uuid

from flask import g, request
from werkzeug.exceptions import HTTPException

from app.errors import ApiError, request_id_var

logger = logging.getLogger("ijwi.request")


def register_middleware(app):
    @app.before_request
    def _begin():
        rid = request.headers.get("X-Request-ID") or uuid.uuid4().hex
        request_id_var.set(rid)
        g.request_id = rid
        g.start_time = time.time()

    @app.after_request
    def _finish(response):
        response.headers["X-Request-ID"] = getattr(g, "request_id", "") or ""
        duration_ms = int((time.time() - getattr(g, "start_time", time.time())) * 1000)
        logger.info(
            json.dumps(
                {
                    "event": "http_request",
                    "method": request.method,
                    "path": request.path,
                    "status": response.status_code,
                    "duration_ms": duration_ms,
                    "request_id": getattr(g, "request_id", None),
                }
            )
        )
        return response

    @app.errorhandler(ApiError)
    def _api_error(err):
        response = err.to_dict()
        response["error"]["request_id"] = getattr(g, "request_id", None)
        return response, err.http_status

    @app.errorhandler(HTTPException)
    def _http_error(err):
        return (
            {
                "error": {
                    "code": err.code if isinstance(err.code, str) else f"HTTP_{err.code}",
                    "message": err.description,
                    "request_id": getattr(g, "request_id", None),
                }
            },
            err.code or 500,
        )

    @app.errorhandler(Exception)
    def _unhandled(err):
        logger.exception(
            json.dumps(
                {"event": "unhandled_error", "request_id": getattr(g, "request_id", None)}
            )
        )
        from app.errors import conflict

        if isinstance(err, conflict("").__class__):
            raise err
        return (
            {
                "error": {
                    "code": "INTERNAL_ERROR",
                    "message": "An unexpected error occurred.",
                    "request_id": getattr(g, "request_id", None),
                }
            },
            500,
        )
