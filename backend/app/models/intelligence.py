from sqlalchemy import (
    BigInteger,
    Boolean,
    CheckConstraint,
    Column,
    Date,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    Numeric,
    String,
    Text,
    UniqueConstraint,
)
from extensions import db
from app.models.base import BaseModel, utcnow

ADVISORY_TOPICS = [
    "crop_production", "pest_management", "disease_management", "soil", "irrigation",
    "livestock", "post_harvest", "climate_smart", "organic", "business", "export_readiness",
]
ADVISORY_FORMATS = ["article", "video", "audio", "image", "lesson", "expert_answer"]
DISPUTE_TYPES = [
    "wrong_quantity", "wrong_quality", "late_delivery", "non_payment",
    "damaged_produce", "fraud", "misrepresentation",
]
DISPUTE_STATES = [
    "OPEN", "EVIDENCE_REQUESTED", "UNDER_REVIEW", "RESOLUTION_PROPOSED",
    "RESOLVED", "ESCALATED", "CLOSED",
]
FARMER_VOICE_TOPICS = [
    "market_issues", "price_problems", "input_problems", "transport_challenges",
    "weather_damage", "buyer_problems", "opportunities", "policy_concerns",
]
ALERT_KINDS = [
    "weather_warning", "flood_warning", "fire", "pest_outbreak",
    "livestock_disease", "government_agricultural",
]


class MarketPriceSource(BaseModel):
    __tablename__ = "market_price_sources"
    name = db.Column(db.String(160), nullable=False)
    provider_code = db.Column(db.String(60), unique=True, nullable=False)
    reliability_note = db.Column(db.String(255), default="")
    active = db.Column(Boolean, default=True, nullable=False)


class MarketPrice(BaseModel):
    __tablename__ = "market_prices"
    __table_args__ = (
        Index("ix_marketprices_product_region_date", "product_id", "region", "observed_on"),
        CheckConstraint("price_low_minor <= price_high_minor OR price_high_minor IS NULL", name="ck_price_range"),
    )

    product_id = db.Column(db.String(32), ForeignKey("products.id"), nullable=False, index=True)
    source_id = db.Column(db.String(32), ForeignKey("market_price_sources.id"), nullable=False)
    region = db.Column(db.String(120), nullable=False)
    district = db.Column(db.String(120))
    market_name = db.Column(db.String(160))
    observed_on = db.Column(Date, nullable=False)
    currency_code = db.Column(db.String(3), nullable=False, default="RWF")
    unit_code = db.Column(db.String(20), nullable=False, default="kg")
    price_low_minor = db.Column(BigInteger, nullable=True)
    price_mid_minor = db.Column(BigInteger, nullable=True)
    price_high_minor = db.Column(BigInteger, nullable=True)
    demand_level = db.Column(db.String(20))
    supply_level = db.Column(db.String(20))


class WeatherRecord(BaseModel):
    __tablename__ = "weather_records"
    __table_args__ = (
        Index("ix_weather_location_time", "country_code", "region", "district", "recorded_at"),
    )
    country_code = db.Column(db.String(2), nullable=False)
    region = db.Column(db.String(120), nullable=False)
    district = db.Column(db.String(120))
    recorded_at = db.Column(db.DateTime(timezone=True), default=utcnow)
    provider = db.Column(db.String(40), nullable=False)
    condition_summary = db.Column(db.String(255))
    temperature_c = db.Column(Numeric(5, 1))
    rain_probability_pct = db.Column(Integer)
    wind_kph = db.Column(Numeric(6, 1))
    humidity_pct = db.Column(Integer)
    forecast_json = db.Column(Text, default="{}")


class AdvisoryArticle(BaseModel):
    __tablename__ = "advisory_articles"
    title = db.Column(db.String(255), nullable=False)
    topic = db.Column(db.String(60), nullable=False, index=True)
    format = db.Column(db.String(20), default="article", nullable=False)
    language = db.Column(db.String(8), default="en", nullable=False)
    body_text = db.Column(Text, default="")
    media_key = db.Column(db.String(500))
    author_id = db.Column(db.String(32), ForeignKey("users.id"))
    published = db.Column(Boolean, default=False, nullable=False, index=True)
    view_count = db.Column(Integer, default=0)


class AdvisoryQuestion(BaseModel):
    __tablename__ = "advisory_questions"
    farmer_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)
    expert_id = db.Column(db.String(32), ForeignKey("users.id"), index=True)
    question_text = db.Column(Text, nullable=False)
    image_keys = db.Column(db.Text, default="")
    topic = db.Column(db.String(60))
    answer_text = db.Column(Text)
    ai_draft_answer = db.Column(Text)
    answered_at = db.Column(db.DateTime(timezone=True))
    escalated_from_ai = db.Column(Boolean, default=False, nullable=False)
    state = db.Column(db.String(20), default="OPEN", nullable=False, index=True)


class FarmerVoiceReport(BaseModel):
    __tablename__ = "farmer_voice_reports"
    reporter_id = db.Column(db.String(32), ForeignKey("users.id"), nullable=False, index=True)
    topic = db.Column(db.String(40), nullable=False)
    body_text = db.Column(Text, default="")
    anonymous_aggregation_ok = db.Column(Boolean, default=True, nullable=False)
    region = db.Column(db.String(120))
    status = db.Column(db.String(20), default="RECEIVED", nullable=False)

    __table_args__ = (
        CheckConstraint("topic IN ('market_issues','price_problems','input_problems','transport_challenges','weather_damage','buyer_problems','opportunities','policy_concerns')", name="ck_voice_topic"),
    )


class EmergencyAlert(BaseModel):
    __tablename__ = "emergency_alerts"
    alert_kind = db.Column(db.String(40), nullable=False)
    severity = db.Column(db.String(20), default="warning", nullable=False)
    title = db.Column(db.String(255), nullable=False)
    message = db.Column(Text, nullable=False)
    country_code = db.Column(db.String(2), nullable=False, default="RW")
    region = db.Column(db.String(120))
    district = db.Column(db.String(120))
    issued_by = db.Column(db.String(32), ForeignKey("users.id"))
    issued_at = db.Column(db.DateTime(timezone=True), default=utcnow)
    expires_at = db.Column(db.DateTime(timezone=True))

    __table_args__ = (Index("ix_alerts_geo_issued", "country_code", "region", "issued_at"),)
