#!/usr/bin/env bash
set -e

echo "Running database migrations..."
flask --app wsgi:app db upgrade

echo "Starting API server..."
exec gunicorn -w 2 -k gthread --threads 4 --worker-tmp-dir /dev/shm -b "0.0.0.0:${PORT:-5000}" \
  --access-logfile - wsgi:app
