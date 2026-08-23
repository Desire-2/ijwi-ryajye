import os
import secrets

from flask import current_app

from app.errors import bad_request, not_configured

ALLOWED_IMAGE = {"image/jpeg": b"\xff\xd8\xff", "image/png": b"\x89PNG", "image/webp": b"RIFF"}
ALLOWED_DOC = {
    "application/pdf": b"%PDF",
    "application/msword": None,
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document": b"PK",
    "application/vnd.ms-excel": None,
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet": b"PK",
}
ALLOWED_AUDIO = {"audio/mp4": None, "audio/aac": b"\xff\xfb", "audio/mpeg": b"ID3", "audio/ogg": b"OggS", "audio/webm": b"RIFF"}

MAX_SIZES = {"image": 10 * 1024 * 1024, "document": 25 * 1024 * 1024, "voice": 15 * 1024 * 1024}


def _driver():
    driver = current_app.config.get("STORAGE_DRIVER", "local")
    if driver == "local":
        return LocalDriver(current_app.config["STORAGE_LOCAL_ROOT"])
    if driver in ("s3", "minio"):
        try:
            from S3Driver import S3Driver
        except ImportError:
            pass
        return _s3_driver()
    raise not_configured("Storage")


def _s3_driver():
    import boto3

    return S3Driver(
        boto3.client(
            "s3",
            endpoint_url=current_app.config.get("S3_ENDPOINT_URL") or None,
            aws_access_key_id=current_app.config["AWS_ACCESS_KEY_ID"],
            aws_secret_access_key=current_app.config["AWS_SECRET_ACCESS_KEY"],
            region_name=current_app.config.get("AWS_REGION", "us-east-1"),
        ),
        current_app.config["STORAGE_BUCKET"],
    )


class LocalDriver:
    def __init__(self, root):
        self.root = root

    def put(self, key, data: bytes, content_type=""):
        path = os.path.join(self.root, key)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as f:
            f.write(data)
        return key

    def get(self, key) -> bytes:
        path = os.path.join(self.root, key)
        with open(path, "rb") as f:
            return f.read()

    def exists(self, key) -> bool:
        return os.path.exists(os.path.join(self.root, key))

    def delete(self, key):
        path = os.path.join(self.root, key)
        if os.path.exists(path):
            os.remove(path)


class S3Driver:
    def __init__(self, client, bucket):
        self.client = client
        self.bucket = bucket

    def put(self, key, data: bytes, content_type=""):
        self.client.put_object(Bucket=self.bucket, Key=key, Body=data, ContentType=content_type)
        return key

    def get(self, key) -> bytes:
        resp = self.client.get_object(Bucket=self.bucket, Key=key)
        return resp["Body"].read()

    def exists(self, key) -> bool:
        try:
            self.client.head_object(Bucket=self.bucket, Key=key)
            return True
        except Exception:
            return False

    def delete(self, key):
        self.client.delete_object(Bucket=self.bucket, Key=key)


def validate_upload(data: bytes, declared_content_type: str, category: str):
    limit = MAX_SIZES.get(category, MAX_SIZES["document"])
    if len(data) > limit:
        raise bad_request(f"File exceeds the {limit // (1024*1024)}MB limit for {category}", "FILE_TOO_LARGE")
    if category == "image":
        allowed = ALLOWED_IMAGE
    elif category == "voice":
        allowed = ALLOWED_AUDIO
    else:
        allowed = {**ALLOWED_DOC, **ALLOWED_IMAGE}

    if declared_content_type in ("application/octet-stream", ""):
        for ct, magic in allowed.items():
            if magic and data[:len(magic)] == magic:
                return ct
        raise bad_request("Unsupported file format", "UNSUPPORTED_FILE_TYPE")

    if declared_content_type not in allowed:
        raise bad_request(f"Content type {declared_content_type} is not permitted", "UNSUPPORTED_FILE_TYPE")
    magic = allowed[declared_content_type]
    if magic is not None and not data.startswith(magic[:4]):
        raise bad_request("File content does not match its declared type", "CONTENT_TYPE_MISMATCH")
    return declared_content_type


def store_upload(user, file_storage, category):
    data = file_storage.read()
    if not data:
        raise bad_request("Empty file")
    content_type = validate_upload(data, file_storage.mimetype or "", category)
    ext = {
        "image/jpeg": ".jpg", "image/png": ".png", "image/webp": ".webp",
        "application/pdf": ".pdf", "audio/mp4": ".m4a", "audio/mpeg": ".mp3",
        "audio/ogg": ".ogg", "audio/webm": ".webm", "audio/aac": ".aac",
    }.get(content_type, "")
    key = f"{category}s/{user.id}/{secrets.token_hex(12)}{ext}"
    _driver().put(key, data, content_type)
    return {"storage_key": key, "content_type": content_type, "size_bytes": len(data)}
