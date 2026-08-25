"""Entrypoint for the dedicated realtime (Socket.IO) container.

Runs a single eventlet worker: WebSocket connections are sticky, so scale by
adding containers behind an ip_hash / sticky upstream and share state through
Redis (SOCKET_MESSAGE_QUEUE).
"""
import os

from app.app import create_app
from extensions import socketio

app = create_app(os.environ.get("FLASK_ENV", "production"))

if __name__ == "__main__":
    socketio.run(app, host="0.0.0.0", port=int(os.environ.get("PORT", 5001)))
