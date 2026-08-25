#!/usr/bin/env bash
set -e

if [ -f .env ]; then
  set -a; source .env; set +a
fi

echo "Running database migrations..."
flask --app wsgi:app db upgrade

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
