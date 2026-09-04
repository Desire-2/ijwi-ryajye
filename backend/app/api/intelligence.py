import marshmallow as ma
from flask import request
from flask_jwt_extended import jwt_required

from extensions import db, limiter
from app.api.helpers import pagination_args, parse_body, paginate_response, query_params
from app.errors import not_found
from app.models.catalog import Product
from app.services import ai_service, market_service
from app.services.security import get_current_user


def list_market_prices():
    product_slug = query_params().get("product")
    region = query_params().get("region")
    days = int(query_params().get("days", 30))
    prices = market_service.query_prices(product_slug=product_slug, region=region, days=days)
    return {"prices": prices}


@jwt_required()
def price_trend():
    product_slug = query_params().get("product", "")
    region = query_params().get("region")
    if not product_slug:
        raise not_found("A 'product' slug is required")
    return market_service.price_trend(product_slug, region)


@jwt_required()
@limiter.limit("10 per hour")
def weather():
    user = get_current_user()
    country = query_params().get("country") or user.country_code
    region = query_params().get("region") or user.region or "Kigali"
    district = query_params().get("district") or user.district
    return market_service.weather_for(country, region, district)


class PriceIngestSchema(ma.Schema):
    source_code = ma.fields.String(required=True)
    product_id = ma.fields.String(required=True)
    region = ma.fields.String(required=True)
    observed_on = ma.fields.Date(required=True)
    currency_code = ma.fields.String(missing="RWF")
    unit = ma.fields.String(missing="kg")
    low_minor = ma.fields.Integer()
    mid_minor = ma.fields.Integer()
    high_minor = ma.fields.Integer()
    market_name = ma.fields.String()


@jwt_required()
def ingest_price():
    user = get_current_user()
    data = parse_body(PriceIngestSchema)
    row = market_service.ingest_price(
        data["source_code"], data["product_id"], data["region"], data["observed_on"],
        data["currency_code"], data["unit"], low=data.get("low_minor"),
        mid=data.get("mid_minor"), high=data.get("high_minor"),
        market_name=data.get("market_name"))
    db.session.commit()
    from extensions.realtime import realtime

    realtime.emit("market.price_updated",
                  {"product_id": data["product_id"], "region": data["region"],
                   "price_mid_minor": data.get("mid_minor")},
                  room=f"product:{data['product_id']}")
    return {"price": row.to_dict()}, 201


def list_products_catalog():
    page, per_page = pagination_args(default_per_page=200)
    pg = Product.query.order_by(Product.name.asc()).paginate(page=page, per_page=per_page, error_out=False)

    def product_json(p):
        cat = p.category
        return {"id": p.id, "name": p.name, "slug": p.slug,
                "emoji": (p.emoji or (cat.icon if cat else "") or "🌾"),
                "default_unit": p.default_unit,
                "category": ({"id": cat.id, "name": cat.name,
                               "slug": cat.slug, "icon": cat.icon}
                              if cat else None)}

    return paginate_response(pg, product_json)


class AdvisoryAskSchema(ma.Schema):
    question_text = ma.fields.String(required=True)
    topic = ma.fields.String(missing="general")


@jwt_required()
def ask_expert():
    from app.errors import bad_request
    from app.models.intelligence import AdvisoryQuestion

    user = get_current_user()
    data = parse_body(AdvisoryAskSchema)
    if len(data["question_text"].strip()) < 5:
        raise bad_request("Please describe your question in more detail")
    q = AdvisoryQuestion(user_id=user.id, question_text=data["question_text"].strip(),
                         topic=data["topic"], state="OPEN")
    db.session.add(q)
    db.session.commit()
    from app.services.notification_service import notify

    notify(q.id, user.id, "ADVISORY_QUESTION_SUBMITTED", "Question submitted",
           "An expert will answer your question soon.", commit=False)
    return {"question": q.to_dict()}, 201


@jwt_required()
def my_advisory_questions():
    from app.models.intelligence import AdvisoryQuestion

    user = get_current_user()
    rows = AdvisoryQuestion.query.filter_by(user_id=user.id).order_by(
        AdvisoryQuestion.created_at.desc()).limit(50).all()
    return {"questions": [q.to_dict() for q in rows]}


@jwt_required()
def advisory_articles():
    from app.models.intelligence import AdvisoryArticle

    topic = query_params().get("topic")
    q = AdvisoryArticle.query.filter(AdvisoryArticle.deleted_at.is_(None))
    if topic:
        q = q.filter(AdvisoryArticle.topic == topic)
    rows = q.order_by(AdvisoryArticle.published_at.desc()).limit(100).all()
    return {"articles": [a.to_dict() for a in rows]}


@jwt_required()
def article_detail(article_id):
    from app.models.intelligence import AdvisoryArticle

    a = db.session.get(AdvisoryArticle, article_id)
    if a is None or a.deleted_at is not None:
        raise not_found("Article not found")
    d = a.to_dict()
    d.pop("body_markdown", None)
    d["content"] = a.body_markdown
    return {"article": d}


@jwt_required()
def report_voice():
    from app.models.intelligence import FarmerVoiceReport

    user = get_current_user()
    data = parse_body(type("S", (ma.Schema,), {
        "report_type": ma.fields.String(required=True),
        "message_text": ma.fields.String(missing=""),
        "media_keys": ma.fields.List(ma.fields.String()),
    })())
    report = FarmerVoiceReport(user_id=user.id, report_type=data["report_type"],
                               message_text=data.get("message_text", ""),
                               media_keys=data.get("media_keys"))
    db.session.add(report)
    db.session.commit()
    return {"report": report.to_dict()}, 201


@jwt_required()
def emergency_alerts():
    from app.models.intelligence import EmergencyAlert

    rows = EmergencyAlert.query.filter(EmergencyAlert.state.in_(("ACTIVE", "ACKNOWLEDGED"))) \
        .order_by(EmergencyAlert.created_at.desc()).limit(20).all()
    return {"alerts": [a.to_dict() for a in rows]}


class AssistantChatSchema(ma.Schema):
    messages = ma.fields.List(ma.fields.Dict(), required=True)


@jwt_required()
@limiter.limit("30 per hour")
def ai_assistant_chat():
    user = get_current_user()
    data = parse_body(AssistantChatSchema)
    reply = ai_service.assistant_chat(user, data["messages"])
    return {"reply": reply}


class ExtractListingSchema(ma.Schema):
    text = ma.fields.String(required=True)


@jwt_required()
@limiter.limit("20 per hour")
def ai_extract_listing():
    user = get_current_user()
    data = parse_body(ExtractListingSchema)
    draft = ai_service.extract_listing_draft(user, data["text"])
    return {"draft": draft, "requires_confirmation": True}


class TranslateSchema(ma.Schema):
    text = ma.fields.String(required=True)
    target_language = ma.fields.String(required=True, validate=ma.validate.OneOf(["en", "rw", "fr", "sw"]))


@jwt_required()
@limiter.limit("60 per hour")
def ai_translate():
    data = parse_body(TranslateSchema)
    result = ai_service.translate_text(data["text"], data["target_language"])
    result["target_language"] = data["target_language"]
    return result


@jwt_required()
@limiter.limit("10 per hour")
def ai_analyze_crop_image():
    from app.services.storage_service import store_upload

    user = get_current_user()
    file = request.files.get("image")
    if file is None:
        raise not_found("An 'image' file part is required")
    stored = store_upload(user, file, "crop_image")
    result = ai_service.analyze_crop_image(user, stored["storage_key"])
    return result


class SummarizeSchema(ma.Schema):
    texts = ma.fields.List(ma.fields.String(), required=True)
    kind = ma.fields.String(missing="summary", validate=ma.validate.OneOf(["summary", "decisions"]))


@jwt_required()
def ai_summarize_messages():
    data = parse_body(SummarizeSchema)
    result = ai_service.summarize_messages("\n".join(data["texts"]), kind=data["kind"])
    return result
