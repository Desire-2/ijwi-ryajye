import math

from flask import request
from marshmallow import EXCLUDE, RAISE, Schema, ValidationError

from app.errors import unprocessable


def parse_body(schema_class=None, partial=False):
    from flask import request as req

    if schema_class is None:
        body = req.get_json(silent=True)
        if body is None:
            raise unprocessable("A JSON body is required", "INVALID_JSON")
        return body
    try:
        schema = schema_class() if isinstance(schema_class, type) else schema_class
        return schema.load(req.get_json(silent=True) or {}, unknown=EXCLUDE, partial=partial)
    except ValidationError as err:
        raise unprocessable("Validation failed", "VALIDATION_ERROR", details=err.messages)


def query_params():
    return request.args


def pagination_args(default_per_page=20, max_per_page=100):
    try:
        page = max(1, int(request.args.get("page", 1)))
        per_page = min(max(1, int(request.args.get("per_page", default_per_page))), max_per_page)
    except ValueError:
        raise unprocessable("page and per_page must be integers", "VALIDATION_ERROR")
    return page, per_page


def paginate_response(pagination, serializer):
    items = [serializer(i) for i in pagination.items]
    total_pages = math.ceil(pagination.total / pagination.per_page) if pagination.per_page else 0
    return {
        "items": items,
        "pagination": {
            "page": pagination.page,
            "per_page": pagination.per_page,
            "total": pagination.total,
            "total_pages": total_pages,
        },
    }
