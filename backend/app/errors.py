import uuid
from contextvars import ContextVar

request_id_var = ContextVar("request_id", default=None)


class ApiError(Exception):
    def __init__(self, http_status, code, message, details=None):
        super().__init__(message)
        self.http_status = http_status
        self.code = code
        self.message = message
        self.details = details or {}

    def to_dict(self):
        return {
            "error": {"code": self.code, "message": self.message, "details": self.details}
        }


def bad_request(message, code="BAD_REQUEST", details=None):
    return ApiError(400, code, message, details)


def unauthorized(message="Authentication required", code="UNAUTHORIZED"):
    return ApiError(401, code, message)


def forbidden(message="Not allowed", code="FORBIDDEN", details=None):
    return ApiError(403, code, message, details)


def not_found(message="Resource not found", code="NOT_FOUND"):
    return ApiError(404, code, message)


def conflict(message="Conflict", code="CONFLICT", details=None):
    return ApiError(409, code, message, details)


def unprocessable(message="Validation failed", code="VALIDATION_ERROR", details=None):
    return ApiError(422, code, message, details)


def not_configured(feature):
    return ApiError(
        501,
        "PROVIDER_NOT_CONFIGURED",
        f"{feature} provider is not configured on this deployment. Set the required environment variables.",
    )


def new_id():
    return uuid.uuid4().hex


def current_request_id():
    return request_id_var.get()
