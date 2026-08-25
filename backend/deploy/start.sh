#!/usr/bin/env bash
set -e

echo "Running database migrations..."
flask --app wsgi:app db upgrade

echo "Starting API server..."
exec gunicorn -w 4 -k gthread --threads 8 -b "0.0.0.0:${PORT:-5000}" \
  --access-logfile - wsgi:app
