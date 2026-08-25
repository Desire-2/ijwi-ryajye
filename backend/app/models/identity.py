from sqlalchemy import (
    Boolean,
    CheckConstraint,
    Column,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    Numeric,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.orm import relationship

from extensions import db
from app.models.base import BaseModel, SoftDeleteModel, utcnow

ROLES = [
    "FARMER",
    "BUYER",
    "COOPERATIVE_ADMIN",
    "SUPPLIER",
    "LOGISTICS_PROVIDER",
    "EXPERT",
    "ADMIN",
]

BUYER_TYPES = [
    "individual", "trader", "wholesaler", "retailer", "restaurant",
    "hotel", "processor", "exporter", "importer", "institution",
]

VERIFICATION_LEVELS = ["PHONE", "IDENTITY", "FARM", "BUSINESS", "CERTIFICATION", "TRANSACTION"]


class User(BaseModel):
    __tablename__ = "users"

    phone = db.Column(db.String(32), unique=True, index=True, nullable=True)
    email = db.Column(db.String(255), unique=True, index=True, nullable=True)
    username = db.Column(db.String(64), unique=True, index=True, nullable=False)
    password_hash = db.Column(db.String(255), nullable=True)
    full_name = db.Column(db.String(255), nullable=False)
    profile_photo_key = db.Column(db.String(500))
    country_code = db.Column(db.String(2), nullable=False, default="RW")
    region = db.Column(db.String(120))
    district = db.Column(db.String(120))
    languages = db.Column(db.String(255), default="rw")
    primary_role = db.Column(db.String(40), nullable=False, default="FARMER")
    is_active = db.Column(Boolean, nullable=False, default=True)
    is_suspended = db.Column(Boolean, nullable=False, default=False)
    suspended_reason = db.Column(db.Text)
    phone_verified_at = db.Column(db.DateTime(timezone=True))
    transcription_opt_in = db.Column(Boolean, nullable=False, default=True)
    translation_pref = db.Column(db.String(8), default="en")
    data_saver = db.Column(Boolean, nullable=False, default=False)
    visibility_phone = db.Column(Boolean, nullable=False, default=False)
    visibility_location_exact = db.Column(Boolean, nullable=False, default=False)
    visibility_farm_details = db.Column(Boolean, nullable=False, default=True)
    last_seen_at = db.Column(db.DateTime(timezone=True))
    deleted_at = db.Column(db.DateTime(timezone=True))

    roles = relationship("UserRole", back_populates="user", lazy="selectin")
    farmer_profile = relationship("FarmerProfile", back_populates="user", uselist=False, lazy="joined")

    __table_args__ = (
        CheckConstraint("length(username) >= 3", name="ck_users_username_len"),
        Index("ix_users_country_region", "country_code", "region"),
    )

    def role_codes(self):
        codes = {r.role for r in self.roles}
        codes.add(self.primary_role)
        return codes


class UserRole(BaseModel):
    __tablename__ = "user_roles"
    __table_args__ = (UniqueConstraint("user_id", "role", name="uq_user_role"),)

    user_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)
    role = db.Column(db.String(40), nullable=False)

    user = relationship("User", back_populates="roles")


class FarmerProfile(BaseModel):
    __tablename__ = "farmer_profiles"
    user_id = db.Column(
        db.String(32), ForeignKey("users.id"), unique=True, nullable=False, index=True
    )
    years_experience = db.Column(Integer, default=0)
    farm_count = db.Column(Integer, default=0)
    total_area_value = db.Column(Numeric(14, 2), default=0)
    total_area_unit = db.Column(db.String(20), default="ha")
    main_crops = db.Column(db.String(500), default="")
    livestock_summary = db.Column(db.String(500), default="")
    certifications = db.Column(db.String(500), default="")
    story = db.Column(db.Text, default="")
    response_rate_bps = db.Column(Integer, default=0)
    completed_transactions = db.Column(Integer, default=0)
    cancelled_transactions = db.Column(Integer, default=0)
    disputes_lost = db.Column(Integer, default=0)
    rating_avg = db.Column(Numeric(3, 2), default=0)
    rating_count = db.Column(Integer, default=0)
    reputation_tier = db.Column(db.String(32), default="NEW_MEMBER", nullable=False)
    reputation_score = db.Column(Integer, default=0)
    cooperative_id = db.Column(db.String(32), ForeignKey("cooperatives.id"), index=True)

    user = relationship("User", back_populates="farmer_profile")


class BuyerProfile(BaseModel):
    __tablename__ = "buyer_profiles"
    user_id = db.Column(
        db.String(32), ForeignKey("users.id"), unique=True, nullable=False, index=True
    )
    buyer_type = db.Column(db.String(30), nullable=False, default="individual")
    organization_name = db.Column(db.String(255))
    preferred_products = db.Column(db.String(500), default="")
    rating_avg = db.Column(Numeric(3, 2), default=0)
    rating_count = db.Column(Integer, default=0)
    completed_purchases = db.Column(Integer, default=0)


class Cooperative(BaseModel):
    __tablename__ = "cooperatives"
    name = db.Column(db.String(255), nullable=False)
    registration_number = db.Column(db.String(100), index=True)
    admin_user_id = db.Column(db.String(32), ForeignKey("users.id"), index=True)
    country_code = db.Column(db.String(2), default="RW")
    region = db.Column(db.String(120))
    district = db.Column(db.String(120))
    description = db.Column(db.Text, default="")
    member_count = db.Column(Integer, default=0)
    verified = db.Column(Boolean, default=False)
    collection_points = db.Column(db.Text, default="")


class CooperativeMember(BaseModel):
    __tablename__ = "cooperative_members"
    __table_args__ = (UniqueConstraint("cooperative_id", "user_id", name="uq_coop_member"),)

    cooperative_id = db.Column(
        db.String(32), ForeignKey("cooperatives.id"), nullable=False, index=True
    )
    user_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)
    role = db.Column(db.String(30), default="member", nullable=False)
    joined_at = db.Column(db.DateTime(timezone=True), default=utcnow)


class SupplierProfile(BaseModel):
    __tablename__ = "supplier_profiles"
    user_id = db.Column(
        db.String(32), ForeignKey("users.id"), unique=True, nullable=False, index=True
    )
    business_name = db.Column(db.String(255), nullable=False)
    categories = db.Column(db.String(300), default="")
    verified = db.Column(Boolean, default=False)


class LogisticsProfile(BaseModel):
    __tablename__ = "logistics_profiles"
    user_id = db.Column(
        db.String(32), ForeignKey("users.id"), unique=True, nullable=False, index=True
    )
    company_name = db.Column(db.String(255), nullable=False)
    service_areas = db.Column(db.String(500), default="")
    verified = db.Column(Boolean, default=False)
    rating_avg = db.Column(Numeric(3, 2), default=0)
    rating_count = db.Column(Integer, default=0)
    completed_deliveries = db.Column(Integer, default=0)


class ExpertProfile(BaseModel):
    __tablename__ = "expert_profiles"
    user_id = db.Column(
        db.String(32), ForeignKey("users.id"), unique=True, nullable=False, index=True
    )
    specialization = db.Column(db.String(255), default="")
    credentials = db.Column(db.String(500), default="")
    verified = db.Column(Boolean, default=False)
    answers_count = db.Column(Integer, default=0)
    bio = db.Column(db.Text, default="")


class Verification(BaseModel):
    __tablename__ = "verifications"
    __table_args__ = (UniqueConstraint("user_id", "level", "status", name="uq_verification_row"),)

    user_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)
    level = db.Column(db.String(30), nullable=False)
    status = db.Column(db.String(20), nullable=False, default="PENDING", index=True)
    document_keys = db.Column(db.Text, default="")
    reviewed_by = db.Column(db.String(32), ForeignKey("users.id"))
    review_note = db.Column(db.Text)
    reviewed_at = db.Column(db.DateTime(timezone=True))


class Certification(BaseModel):
    __tablename__ = "certifications"
    user_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)
    farm_id = db.Column(db.String(32), ForeignKey("farms.id"), index=True)
    name = db.Column(db.String(255), nullable=False)
    issuer = db.Column(db.String(255))
    certificate_key = db.Column(db.String(500))
    expires_on = db.Column(db.Date)
    verified = db.Column(Boolean, default=False)


class BlockedUser(BaseModel):
    __tablename__ = "blocked_users"
    __table_args__ = (UniqueConstraint("blocker_id", "blocked_id", name="uq_block_pair"),)

    blocker_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)
    blocked_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)


class DeviceToken(BaseModel):
    __tablename__ = "device_tokens"
    token = db.Column(db.String(255), unique=True, nullable=False)
    user_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)
    platform = db.Column(db.String(10), default="android")
    last_active_at = db.Column(db.DateTime(timezone=True), default=utcnow)


class RefreshTokenRecord(BaseModel):
    __tablename__ = "refresh_tokens"
    jti = db.Column(db.String(64), unique=True, nullable=False, index=True)
    user_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)
    revoked = db.Column(Boolean, default=False, nullable=False)
    expires_at = db.Column(db.DateTime(timezone=True), nullable=False)
