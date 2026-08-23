from app.app import create_wsgi_app

application = create_wsgi_app()

if __name__ == "__main__":
    application.run(host="0.0.0.0", port=8000)
