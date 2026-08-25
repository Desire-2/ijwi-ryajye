from datetime import datetime, timezone

from app.errors import new_id
from extensions import db


def utcnow():
    return datetime.now(timezone.utc)


class BaseMixin:
    id = db.Column(db.String(32), primary_key=True, default=new_id, nullable=False)
    created_at = db.Column(db.DateTime(timezone=True), default=utcnow, nullable=False, index=True)
    updated_at = db.Column(
        db.DateTime(timezone=True), default=utcnow, onupdate=utcnow, nullable=False
    )

    def to_dict(self, exclude=()):
        out = {}
        for c in self.__table__.columns:
            if c.name in exclude:
                continue
            v = getattr(self, c.name)
            if isinstance(v, datetime):
                v = v.isoformat()
            out[c.name] = v
        return out


class SoftDeleteMixin:
    deleted_at = db.Column(db.DateTime(timezone=True), nullable=True, index=True)

    @property
    def is_deleted(self):
        return self.deleted_at is not None


class BaseModel(BaseMixin, db.Model):
    __abstract__ = True


class SoftDeleteModel(BaseModel, SoftDeleteMixin):
    __abstract__ = True
