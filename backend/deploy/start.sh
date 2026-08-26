#!/usr/bin/env bash
set -e

echo "Ensuring tables exist..."
python3 -c "
from wsgi import app
from extensions import db
with app.app_context():
    db.create_all()
"

echo "Starting API server..."
exec gunicorn -w 2 -k gthread --threads 4 --worker-tmp-dir /dev/shm -b "0.0.0.0:${PORT:-5000}" \
  --access-logfile - wsgi:app
