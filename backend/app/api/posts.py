from flask import request
from flask_jwt_extended import get_jwt_identity, jwt_required

from app.api.helpers import paginate_response, pagination_args, parse_body, query_params
from app.errors import not_found
from app.services import post_service
from app.services.security import get_current_user


@jwt_required()
def create_post():
    user = get_current_user()
    payload = parse_body()
    post = post_service.create_post(user, payload)
    return {"post": post_service.serialize_post(post, viewer=user)}, 201


def list_posts():
    try:
        user = get_current_user()
    except Exception:
        user = None
    params = query_params()
    page, per_page = pagination_args()

    pagination = post_service.list_posts(
        user=user,
        community_id=params.get("community_id"),
        group_id=params.get("group_id"),
        channel_id=params.get("channel_id"),
        post_type=params.get("post_type"),
        author_id=params.get("author_id"),
        topic=params.get("topic"),
        feed_for=params.get("feed") == "for_you" and user is not None,
        page=page,
        per_page=per_page,
    )
    return paginate_response(pagination, lambda p: post_service.serialize_post(p, viewer=user))


@jwt_required()
def post_detail(post_id):
    user = get_current_user()
    post = post_service.get_post(post_id, viewer=user)
    return {"post": post_service.serialize_post(post, viewer=user)}


@jwt_required()
def patch_post(post_id):
    user = get_current_user()
    payload = parse_body()
    post = post_service.edit_post(user, post_id, payload)
    return {"post": post_service.serialize_post(post, viewer=user)}


@jwt_required()
def delete_post(post_id):
    user = get_current_user()
    return post_service.delete_post(user, post_id)


@jwt_required()
def pin_post(post_id):
    user = get_current_user()
    return post_service.pin_post(user, post_id)


@jwt_required()
def mark_best_answer(post_id):
    user = get_current_user()
    payload = parse_body()
    comment_id = payload.get("comment_id")
    if not comment_id:
        from app.errors import bad_request
        raise bad_request("comment_id is required")
    return post_service.mark_best_answer(user, post_id, comment_id)


@jwt_required()
def list_comments(post_id):
    user = get_current_user()
    params = query_params()
    page, per_page = pagination_args()
    sort = params.get("sort", "newest")
    pagination = post_service.list_comments(post_id, page=page, per_page=per_page, sort=sort, user=user)
    items = [post_service.serialize_comment(c, viewer=user) for c in pagination.items]
    from app.api.helpers import paginate_response
    return {
        "items": items,
        "pagination": {
            "page": pagination.page,
            "per_page": pagination.per_page,
            "total": pagination.total,
            "total_pages": (pagination.total // pagination.per_page +
                            (1 if pagination.total % pagination.per_page else 0)),
        },
    }


@jwt_required()
def create_comment(post_id):
    user = get_current_user()
    payload = parse_body()
    comment = post_service.add_comment(user, post_id, payload)
    return {"comment": post_service.serialize_comment(comment, viewer=user)}, 201


@jwt_required()
def list_replies(comment_id):
    user = get_current_user()
    page, per_page = pagination_args()
    pagination = post_service.list_comment_replies(comment_id, page=page, per_page=per_page)
    return paginate_response(pagination, lambda c: post_service.serialize_comment(c, viewer=user))


@jwt_required()
def delete_comment(comment_id):
    user = get_current_user()
    comment = post_service.db.session.get(post_service.Comment, comment_id)
    if comment is None:
        raise not_found("Comment not found")
    if comment.author_id != user.id and "ADMIN" not in user.role_codes():
        from app.errors import forbidden
        raise forbidden("You can only delete your own comments")
    post_service.db.session.delete(comment)
    post = post_service.db.session.get(post_service.Post, comment.post_id)
    if post:
        post.reply_count = max(0, (post.reply_count or 0) - 1)
    post_service.db.session.flush()
    return {"deleted": True}


@jwt_required()
def react_post(post_id):
    user = get_current_user()
    payload = parse_body()
    emoji = payload.get("emoji")
    if not emoji:
        from app.errors import bad_request
        raise bad_request("emoji is required")
    return post_service.react_to_post(user, post_id, emoji)


@jwt_required()
def react_comment(comment_id):
    user = get_current_user()
    payload = parse_body()
    emoji = payload.get("emoji")
    if not emoji:
        from app.errors import bad_request
        raise bad_request("emoji is required")
    return post_service.react_to_comment(user, comment_id, emoji)


@jwt_required()
def save_post(post_id):
    user = get_current_user()
    return post_service.save_post(user, post_id)


@jwt_required()
def saved_posts():
    user = get_current_user()
    page, per_page = pagination_args()
    pagination = post_service.list_saved_posts(user, page=page, per_page=per_page)
    return paginate_response(pagination, lambda p: post_service.serialize_post(p, viewer=user))


@jwt_required()
def follow_user(user_id):
    user = get_current_user()
    return post_service.follow_user(user, user_id)


@jwt_required()
def unfollow_user(user_id):
    user = get_current_user()
    return post_service.follow_user(user, user_id)


@jwt_required()
def report_content():
    user = get_current_user()
    payload = parse_body()
    subject_type = payload.get("subject_type")
    subject_id = payload.get("subject_id")
    reason = payload.get("reason")
    if not subject_type or not subject_id or not reason:
        from app.errors import bad_request
        raise bad_request("subject_type, subject_id and reason are required")
    report = post_service.report_content(user, subject_type, subject_id, reason,
                                          payload.get("details", ""))
    return {"report": {"id": report.id, "status": report.status}}, 201
