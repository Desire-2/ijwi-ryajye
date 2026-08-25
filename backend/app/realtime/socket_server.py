"""Socket.IO gateway: authenticated realtime channel for messaging, presence,
typing indicators, call signaling and live market updates."""
import logging

from flask import request
from flask_jwt_extended import decode_token
from jwt.exceptions import PyJWTError

log = logging.getLogger("ijwi.realtime")

_connected = {}


def _user_id_from_auth(auth):
    if not auth:
        return None
    token = None
    if isinstance(auth, dict):
        token = auth.get("token")
    elif isinstance(auth, (list, tuple)) and len(auth) == 2:
        token = auth[1].get("token") if isinstance(auth[1], dict) else auth[0]
    if not token:
        return None
    try:
        decoded = decode_token(token)
        return decoded.get("sub")
    except (PyJWTError, Exception):
        return None


def register_socket_events(socketio):
    @socketio.on("connect")
    def on_connect(auth):
        user_id = _user_id_from_auth(auth)
        if not user_id:
            log.info("socket rejected: unauthenticated client %s", request.sid)
            return False
        from app.models.identity import User

        from extensions import db

        user = db.session.get(User, user_id)
        if user is None or user.is_suspended or user.deleted_at is not None:
            return False
        _connected[user_id] = request.sid
        socketio.server.enter_room(request.sid, f"user:{user_id}")
        socketio.emit("presence.online", {"user_id": user_id}, room=f"user:{user_id}")

    @socketio.on("disconnect")
    def on_disconnect(_reason=None):
        for uid, sid in list(_connected.items()):
            if sid == request.sid:
                _connected.pop(uid, None)
                socketio.emit("presence.offline", {"user_id": uid}, room=f"user:{uid}")
                break

    @socketio.on("conversation.join")
    def on_conversation_join(data):
        conversation_id = (data or {}).get("conversation_id")
        if conversation_id:
            from app.services import messaging_service
            from app.services.security import get_current_user as _gcu

            uid = next((u for u, s in _connected.items() if s == request.sid), None)
            if uid is None:
                return {"ok": False}
            from extensions import db
            from app.models.identity import User

            user = db.session.get(User, uid)
            try:
                conv = messaging_service.get_conversation_or_404(conversation_id)
                messaging_service.assert_membership(conv, user)
            except Exception:
                return {"ok": False, "error": "NOT_A_MEMBER"}
            socketio.server.enter_room(request.sid, f"conversation:{conversation_id}")
            return {"ok": True}

    @socketio.on("conversation.leave")
    def on_conversation_leave(data):
        conversation_id = (data or {}).get("conversation_id")
        if conversation_id:
            socketio.server.leave_room(request.sid, f"conversation:{conversation_id}")

    @socketio.on("typing")
    def on_typing(data):
        conversation_id = (data or {}).get("conversation_id")
        started = bool((data or {}).get("started", True))
        uid = next((u for u, s in _connected.items() if s == request.sid), None)
        if conversation_id and uid:
            from app.services.messaging_service import typing_signal
            from extensions import db
            from app.models.identity import User

            user = db.session.get(User, uid)
            typing_signal(user, conversation_id, started)

    @socketio.on("message.read")
    def on_message_read(data):
        conversation_id = (data or {}).get("conversation_id")
        upto_sequence = (data or {}).get("upto_sequence")
        uid = next((u for u, s in _connected.items() if s == request.sid), None)
        if conversation_id and upto_sequence and uid:
            from extensions import db
            from app.models.identity import User
            from app.services import messaging_service

            user = db.session.get(User, uid)
            try:
                messaging_service.mark_read(user, conversation_id, int(upto_sequence))
                db.session.commit()
            except Exception:
                db.session.rollback()

    @socketio.on("call.signal")
    def on_call_signal(data):
        call_id = (data or {}).get("call_id")
        signal_type = (data or {}).get("signal_type")
        payload = (data or {}).get("payload") or {}
        uid = next((u for u, s in _connected.items() if s == request.sid), None)
        if call_id and signal_type and uid:
            from extensions import db
            from app.models.identity import User
            from app.services.call_service import relay_signal

            user = db.session.get(User, uid)
            relay_signal(user, call_id, signal_type, payload)

    @socketio.on("product.subscribe")
    def on_product_subscribe(data):
        product_id = (data or {}).get("product_id")
        if product_id:
            socketio.server.enter_room(request.sid, f"product:{product_id}")

    @socketio.on("alerts.subscribe")
    def on_alerts_subscribe(_data=None):
        socketio.server.enter_room(request.sid, "alerts")
