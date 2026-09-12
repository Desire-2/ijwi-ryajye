from flask_jwt_extended import jwt_required

from extensions import db
from app.api.helpers import pagination_args, query_params
from app.services import connection_service
from app.services.security import get_current_user


@jwt_required()
def request_connection(user_id):
    user = get_current_user()
    row = connection_service.request_connection(user, user_id)
    db.session.commit()
    return {"connection_id": row.id, "status": row.status}, 201


@jwt_required()
def accept_connection(connection_id):
    user = get_current_user()
    row = connection_service.accept_connection(user, connection_id)
    db.session.commit()
    return {"connection_id": row.id, "status": row.status}


@jwt_required()
def decline_connection(connection_id):
    user = get_current_user()
    row = connection_service.decline_connection(user, connection_id)
    db.session.commit()
    return {"connection_id": row.id, "status": row.status}


@jwt_required()
def cancel_connection(connection_id):
    user = get_current_user()
    result = connection_service.cancel_connection(user, connection_id)
    db.session.commit()
    return result


@jwt_required()
def remove_connection(user_id):
    user = get_current_user()
    result = connection_service.remove_connection(user, user_id)
    db.session.commit()
    return result


@jwt_required()
def list_connections():
    user = get_current_user()
    page, per_page = pagination_args(default_per_page=50, max_per_page=100)
    status = query_params().get("status")
    payload = connection_service.list_connections(user, status=status, page=page, per_page=per_page)
    return payload


@jwt_required()
def pending_requests():
    user = get_current_user()
    page, per_page = pagination_args(default_per_page=50, max_per_page=100)
    return connection_service.pending_requests(user, page=page, per_page=per_page)


@jwt_required()
def recommended():
    user = get_current_user()
    limit = min(int(query_params().get("limit", 20)), 50)
    return {"recommendations": connection_service.recommended_connections(user, limit=limit)}


@jwt_required()
def nearby():
    user = get_current_user()
    limit = min(int(query_params().get("limit", 50)), 100)
    return {"people": connection_service.nearby_people(user, limit=limit)}


@jwt_required()
def block_user(user_id):
    user = get_current_user()
    result = connection_service.block_user(user, user_id)
    db.session.commit()
    return result


@jwt_required()
def unblock_user(user_id):
    user = get_current_user()
    result = connection_service.unblock_user(user, user_id)
    db.session.commit()
    return result


@jwt_required()
def blocked_list():
    user = get_current_user()
    page, per_page = pagination_args(default_per_page=50, max_per_page=100)
    return connection_service.my_blocked(user, page=page, per_page=per_page)