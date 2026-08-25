.PHONY: help install seed api test lint format db-reset smoke up down logs mobile-run

help:
	@echo "make install   - create venv + install backend deps"
	@echo "make seed      - create schema + demo data in the dev DB"
	@echo "make api       - run the REST API on :5000"
	@echo "make test      - run the full pytest suite (ijwi_test DB)"
	@echo "make smoke     - run scripts/smoke_e2e.py against the dev DB"
	@echo "make db-reset  - drop & recreate dev schema + reseed"
	@echo "make up/down   - start/stop the docker-compose stack"
	@echo "make mobile-run- run the Flutter client against localhost"

install:
	cd backend && python3 -m venv .venv && .venv/bin/pip install -r requirements.txt

seed:
	cd backend && python3 scripts/seed_dev.py

api:
	cd backend && python3 wsgi.py

realtime:
	cd backend && python3 realtime_server.py

worker:
	cd backend && celery -A celery_app.celery worker -l info -c 4

test:
	python3 -m pytest tests -q

smoke:
	cd backend && python3 scripts/smoke_e2e.py

db-reset:
	cd backend && python3 -c "\
from app.app import create_app; from extensions import db;\
app = create_app('development');\
with app.app_context():\
    db.drop_all(); db.create_all()\
" && $(MAKE) seed

up:
	docker compose up -d --build

down:
	docker compose down

logs:
	docker compose logs -f api realtime worker

mobile-run:
	cd mobile && flutter run --dart-define=API_BASE_URL=http://10.0.2.2:5000/api/v1 --dart-define=REALTIME_URL=http://10.0.2.2:5000
