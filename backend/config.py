import os
from datetime import timedelta


def _bool(name, default="false"):
    return os.environ.get(name, default).strip().lower() in ("1", "true", "yes", "on")


class BaseConfig:
    APP_NAME = "Ijwi Ryajye"
    API_VERSION = "v1"

    SECRET_KEY = os.environ.get("SECRET_KEY", "dev-only-change-me")
    JWT_SECRET_KEY = os.environ.get("JWT_SECRET_KEY", SECRET_KEY)
    JWT_ACCESS_TOKEN_EXPIRES = timedelta(seconds=int(os.environ.get("JWT_ACCESS_TTL", "3600")))
    JWT_REFRESH_TOKEN_EXPIRES = timedelta(seconds=int(os.environ.get("JWT_REFRESH_TTL", "1209600")))

    SQLALCHEMY_DATABASE_URI = os.environ.get(
        "DATABASE_URL",
        "postgresql+psycopg2://ijwi:ijwi_dev@127.0.0.1:5433/ijwi_ryajye",
    )
    SQLALCHEMY_TRACK_MODIFICATIONS = False
    SQLALCHEMY_ENGINE_OPTIONS = {"pool_pre_ping": True, "pool_size": 10, "max_overflow": 20}

    REDIS_URL = os.environ.get("REDIS_URL", "")
    RATELIMIT_STORAGE_URI = os.environ.get("REDIS_URL") or "memory://"
    RATELIMIT_DEFAULT = os.environ.get("RATELIMIT_DEFAULT", "300 per minute")

    CELERY_BROKER_URL = os.environ.get("CELERY_BROKER_URL") or os.environ.get("REDIS_URL", "")
    CELERY_RESULT_BACKEND = os.environ.get("CELERY_RESULT_BACKEND") or os.environ.get("REDIS_URL", "")

    CORS_ORIGINS = [o for o in os.environ.get("CORS_ORIGINS", "*").split(",") if o]

    STORAGE_DRIVER = os.environ.get("STORAGE_DRIVER", "local")
    STORAGE_BUCKET = os.environ.get("STORAGE_BUCKET", "ijwi-media")
    STORAGE_LOCAL_ROOT = os.environ.get("STORAGE_LOCAL_ROOT", "/tmp/opencode/ijwi-storage")
    S3_ENDPOINT_URL = os.environ.get("S3_ENDPOINT_URL", "")
    AWS_ACCESS_KEY_ID = os.environ.get("AWS_ACCESS_KEY_ID", "")
    AWS_SECRET_ACCESS_KEY = os.environ.get("AWS_SECRET_ACCESS_KEY", "")
    AWS_REGION = os.environ.get("AWS_REGION", "af-south-1")
    MAX_UPLOAD_BYTES = int(os.environ.get("MAX_UPLOAD_BYTES", str(25 * 1024 * 1024)))

    SMS_PROVIDER = os.environ.get("SMS_PROVIDER", "console")
    SMS_SENDER_ID = os.environ.get("SMS_SENDER_ID", "IJWI")

    PAYMENT_PROVIDERS = os.environ.get("PAYMENT_PROVIDERS", "mock")
    PAYMENT_WEBHOOK_SECRETS = os.environ.get("PAYMENT_WEBHOOK_SECRETS", "mock:dev-webhook-secret")
    PLATFORM_BASE_FEE_BPS = int(os.environ.get("PLATFORM_BASE_FEE_BPS", "250"))
    CONTRACT_THRESHOLD_MINOR = int(os.environ.get("CONTRACT_THRESHOLD_MINOR", "50000000"))

    WEATHER_PROVIDER = os.environ.get("WEATHER_PROVIDER", "")
    WEATHER_API_KEY = os.environ.get("WEATHER_API_KEY", "")

    AI_PROVIDER_BASE_URL = os.environ.get("AI_PROVIDER_BASE_URL", "")
    AI_API_KEY = os.environ.get("AI_API_KEY", "")
    AI_MODEL = os.environ.get("AI_MODEL", "")

    PUSH_NOTIFICATION_KEYS = os.environ.get("PUSH_NOTIFICATION_KEYS", "")
    RTC_PROVIDER = os.environ.get("RTC_PROVIDER", "webrtc-direct")

    DEFAULT_CURRENCY = os.environ.get("DEFAULT_CURRENCY", "RWF")
    SUPPORTED_LANGUAGES = ["en", "rw", "fr", "sw"]
    OTP_TTL_SECONDS = int(os.environ.get("OTP_TTL_SECONDS", "600"))
    OTP_MAX_ATTEMPTS = int(os.environ.get("OTP_MAX_ATTEMPTS", "5"))

    STATUS_TTL_HOURS = int(os.environ.get("STATUS_TTL_HOURS", "24"))
    AUCTION_ANTI_SNIPE_SECONDS = int(os.environ.get("AUCTION_ANTI_SNIPE_SECONDS", "120"))
    MESSAGE_RATE_PER_MINUTE = int(os.environ.get("MESSAGE_RATE_PER_MINUTE", "60"))
    FORWARD_RATE_PER_HOUR = int(os.environ.get("FORWARD_RATE_PER_HOUR", "100"))

    PROPAGATE_EXCEPTIONS = True
    DEBUG = False
    TESTING = False


class DevelopmentConfig(BaseConfig):
    DEBUG = True
    ENV_NAME = "development"


class TestingConfig(BaseConfig):
    TESTING = True
    ENV_NAME = "testing"
    SMS_PROVIDER = "test-capture"
    PAYMENT_WEBHOOK_SECRETS = "mock:test-webhook-secret"
    STORAGE_LOCAL_ROOT = os.environ.get("STORAGE_LOCAL_ROOT", "/tmp/opencode/ijwi-test-storage")


class ProductionConfig(BaseConfig):
    ENV_NAME = "production"

    def __init__(self):
        missing = [
            name
            for name in ("SECRET_KEY", "JWT_SECRET_KEY", "DATABASE_URL")
            if not os.environ.get(name)
        ]
        if missing:
            raise RuntimeError(f"Missing required production environment variables: {missing}")


CONFIG_BY_ENV = {
    "development": DevelopmentConfig,
    "testing": TestingConfig,
    "production": ProductionConfig,
}


def get_config(name=None):
    env = os.environ.get("APP_ENV", "development").strip().lower()
    return CONFIG_BY_ENV.get(env, DevelopmentConfig)
