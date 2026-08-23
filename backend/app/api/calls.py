import marshmallow as ma
from flask_jwt_extended import jwt_required

from app.api.helpers import parse_body, query_params
from app.errors import not_found
from app.services import call_service
from app.services.security import get_current_user


class CallStartSchema(ma.Schema):
    callee_id = ma.fields.String(required=True)
    call_type = ma.fields.String(missing="voice", validate=ma.validate.OneOf(["voice", "video"]))


@jwt_required()
def start_call():
    user = get_current_user()
    data = parse_body(CallStartSchema)
    call = call_service.start_call(user, data["callee_id"], data["call_type"])
    return {"call": call.to_dict()}, 201


@jwt_required()
def answer_call(call_id):
    user = get_current_user()
    call = call_service.answer_call(user, call_id)
    return {"call": call.to_dict()}


@jwt_required()
def end_call(call_id):
    user = get_current_user()
    data = parse_body(type("S", (ma.Schema,), {"reason": ma.fields.String(missing="")})())
    call = call_service.decline_or_end_call(user, call_id, data.get("reason", ""))
    return {"call": call.to_dict()}


@jwt_required()
def relay_signal(call_id):
    user = get_current_user()
    payload = parse_body(type("S", (ma.Schema,), {
        "signal_type": ma.fields.String(required=True),
        "payload": ma.fields.Dict(),
    })())
    call_service.relay_signal(user, call_id, payload["signal_type"], payload.get("payload"))
    return {"relayed": True}


class VoiceRoomSchema(ma.Schema):
    title = ma.fields.String(required=True)
    topic = ma.fields.String(missing="")
    community_id = ma.fields.String()


@jwt_required()
def create_voice_room():
    user = get_current_user()
    data = parse_body(VoiceRoomSchema)
    room = call_service.create_voice_room(user, data)
    return {"room": room.to_dict()}, 201


@jwt_required()
def list_voice_rooms():
    from app.models.call import VoiceRoom

    rooms = VoiceRoom.query.filter_by(state="LIVE").order_by(VoiceRoom.created_at.desc()).limit(50).all()
    return {"rooms": [r.to_dict() for r in rooms]}


@jwt_required()
def join_voice_room(room_id):
    user = get_current_user()
    room = call_service.join_voice_room(user, room_id)
    return {"room": room.to_dict()}


@jwt_required()
def request_speaker(room_id):
    user = get_current_user()
    result = call_service.request_speaker(user, room_id)
    return result


@jwt_required()
def decide_speaker(room_id):
    user = get_current_user()
    data = parse_body(type("S", (ma.Schema,), {
        "request_id": ma.fields.String(required=True),
        "approve": ma.fields.Boolean(required=True),
    })())
    result = call_service.decide_speaker(user, data["request_id"], approve=data["approve"])
    return result


@jwt_required()
def end_voice_room(room_id):
    user = get_current_user()
    room = call_service.end_voice_room(user, room_id)
    return {"room": room.to_dict()}
