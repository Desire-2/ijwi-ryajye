import os
from pathlib import Path

from dotenv import load_dotenv

load_dotenv(Path(__file__).resolve().parent / ".env")

from app.app import create_wsgi_app  # noqa: E402

application = create_wsgi_app()
app = application

if __name__ == "__main__":
    application.run(host="0.0.0.0", port=8000)
