# Deployment Guide

## Environments & config

Configuration lives in `backend/config.py`, selected by `FLASK_ENV`
(`development` | `testing` | `production`). Secrets come from environment
variables — never commit them. See [.env.example](../.env.example) for the full
list; the critical production ones:

| Variable | Notes |
| -------- | ----- |
| `SECRET_KEY`, `JWT_SECRET_KEY` | 32+ random bytes each (`openssl rand -hex 32`) |
| `DATABASE_URL` | `postgresql+psycopg2://…` |
| `REDIS_URL`, `CELERY_BROKER_URL` | broker + result backend |
| `SOCKET_MESSAGE_QUEUE` | `redis://…` so multiple realtime nodes can fan out |
| `PAYMENT_WEBHOOK_SECRETS` | `provider:secret` pairs, semicolon-separated |
| `SMS_PROVIDER` | `mock` (dev), or provider credentials |

## Docker Compose stack

```bash
cp .env.example .env    # fill secrets
make up                 # builds api, realtime, worker, beat, nginx, postgres, redis
docker compose exec api python3 scripts/seed_dev.py   # optional demo data
```

Topology:

- **nginx :80** → `/api/` → gunicorn API (4 workers × 8 threads)
  `/socket.io/` → dedicated eventlet realtime container
  `/uploads/` → shared uploads volume (immutable cache headers)
- **api** — stateless REST; scale horizontally behind the same upstream.
- **realtime** — single eventlet worker per container (sticky connections);
  scale with an ip_hash upstream and Redis message queue.
- **worker / beat** — Celery: escrow clearance, auction close, offer expiry,
  listing expiry, notification digests.

## Health probes

- Liveness: `GET /health`
- Readiness: `GET /ready` (checks DB + realtime wiring)

## Database migrations

Schema is created via SQLAlchemy in dev (`seed_dev.py` calls
`db.create_all()`). For production upgrades use Flask-Migrate:

```bash
cd backend
flask --app wsgi:app db init        # once
flask --app wsgi:app db migrate -m "baseline"
flask --app wsgi:app db upgrade     # on every deploy
```

## TLS

Terminate at your edge (cloud LB / certbot). Behind nginx set
`proxy_set_header X-Forwarded-Proto https` — the app already enables
ProxyFix. Serve the mobile clients with `https://` base URLs; cleartext HTTP
is blocked by Android/iOS release defaults.

## Backups

```bash
# nightly logical backup
docker compose exec postgres pg_dump -U ijwi ijwi_ryajye | gzip > backup-$(date +%F).sql.gz
```

Restore drill quarterly: spin up a scratch DB, restore, run smoke_e2e.py.

## Observability

- JSON access logs from gunicorn/nginx; structured request logs with
  `request_id` from the API middleware.
- Ship logs to your aggregator of choice; alert on 5xx rate,
  webhook signature failures, and ledger idempotency collisions.
