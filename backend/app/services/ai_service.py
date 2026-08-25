import json

from flask import current_app, has_app_context


class AIProvider:
    name = "abstract"

    def chat(self, system_prompt, user_content, temperature=0.2, json_mode=False):
        raise NotImplementedError


class OpenAICompatibleProvider(AIProvider):
    name = "openai_compatible"

    def __init__(self, base_url, api_key, model):
        self.base_url = base_url.rstrip("/")
        self.api_key = api_key
        self.model = model

    def chat(self, system_prompt, user_content, temperature=0.2, json_mode=False):
        import requests

        body = {
            "model": self.model,
            "temperature": temperature,
            "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_content},
            ],
        }
        if json_mode:
            body["response_format"] = {"type": "json_object"}
        resp = requests.post(
            f"{self.base_url}/chat/completions",
            headers={"Authorization": f"Bearer {self.api_key}"},
            json=body,
            timeout=60,
        )
        resp.raise_for_status()
        data = resp.json()
        return data["choices"][0]["message"]["content"]


def get_ai_provider():
    cfg = current_app.config
    if cfg.get("AI_PROVIDER_BASE_URL") and cfg.get("AI_API_KEY") and cfg.get("AI_MODEL"):
        return OpenAICompatibleProvider(
            cfg["AI_PROVIDER_BASE_URL"], cfg["AI_API_KEY"], cfg["AI_MODEL"]
        )
    return None


def _require_provider():
    provider = get_ai_provider()
    if provider is None:
        from app.errors import not_configured

        raise not_configured("AI")
    return provider


ASSISTANT_SYSTEM_PROMPT = """You are Ijwi AI, an agricultural assistant inside the Ijwi Ryajye farmer platform.
Rules:
- Never fabricate market prices, regulations or agricultural facts. If unknown, say so.
- Clearly classify statements as one of: VERIFIED_INFO, USER_DATA, ESTIMATE, RECOMMENDATION.
- Be concise and practical for farmers with limited literacy. Prefer short sentences.
- Respond in the language of the user's message unless asked otherwise."""


def assistant_chat(user, messages):
    provider = _require_provider()
    context_parts = []
    if has_app_context():
        from app.models.farm import Farm

        farms = Farm.query.filter_by(owner_id=user.id).limit(5).all()
        if farms:
            context_parts.append("User farms: " + "; ".join(f"{f.name} ({f.region}, {f.area_value}{f.area_unit})" for f in farms))
    context = ("\n\nContext about this user (USER_DATA):\n" + "\n".join(context_parts)) if context_parts else ""
    transcript = "\n".join(f"{m['role']}: {m['content']}" for m in messages[-10:])
    answer = provider.chat(ASSISTANT_SYSTEM_PROMPT + context, transcript)
    return {"answer": answer, "ai_generated": True, "provider": provider.name}


LISTING_EXTRACTION_PROMPT = """Extract a marketplace listing draft from the farmer's message.
Return strict JSON with keys: title, product_guess, quantity_value (number), unit_code, availability ("ready"|"future"), price_hint_minor (nullable), currency_guess.
If information is missing use null. Do not invent numbers."""


def extract_listing_draft(user, text):
    provider = _require_provider()
    raw = provider.chat(LISTING_EXTRACTION_PROMPT, text, json_mode=True)
    try:
        draft = json.loads(raw)
    except Exception:
        draft = {"parse_error": True}
    return {
        "draft": draft,
        "ai_generated": True,
        "requires_user_confirmation": True,
        "note": "Review every field before publishing.",
    }


TRANSLATE_PROMPT = """Translate the user's text to {target}. Return JSON: {{"translation": "...", "detected_language": "..."}}"""


def translate_text(text, target_language):
    provider = _require_provider()
    if target_language not in ("en", "rw", "fr", "sw"):
        from app.errors import bad_request

        raise bad_request("Supported languages: en, rw, fr, sw")
    raw = provider.chat(TRANSLATE_PROMPT.format(target=target_language.upper()), text, json_mode=True)
    try:
        out = json.loads(raw)
    except Exception:
        out = {"translation": None}
    return {
        "original_message": text,
        "translated_message": out.get("translation"),
        "source_language": out.get("detected_language"),
        "target_language": target_language,
        "ai_generated": True,
    }


CROP_IMAGE_PROMPT = """Analyze this crop image for possible disease/pest/nutrition issues.
Return JSON: {"possible_issues": [{"name": "...", "confidence": 0-100}], "recommended_actions": ["..."], "needs_expert": true|false}.
Never claim certainty; confidence must reflect real uncertainty."""


def analyze_crop_image(user, storage_key):
    provider = _require_provider()
    vision_capable = getattr(provider, "supports_vision", False) or "gpt-4" in (current_app.config.get("AI_MODEL") or "")
    if not vision_capable:
        from app.errors import not_configured

        raise not_configured("Vision-capable AI")
    raw = provider.chat(CROP_IMAGE_PROMPT, f"[image at storage key {storage_key}]", json_mode=True)
    try:
        result = json.loads(raw)
    except Exception:
        result = {"possible_issues": [], "needs_expert": True,
                  "recommended_actions": []}
    result["ai_generated"] = True
    result["disclaimer"] = "This is an automated estimate, not a diagnosis."
    if result.get("needs_expert"):
        question = _create_escalation_question(user, storage_key, result)
        result["escalated_to_experts"] = bool(question)
    return result


def _create_escalation_question(user, storage_key, analysis):
    from app.models.intelligence import AdvisoryQuestion

    q = AdvisoryQuestion(
        farmer_id=user.id,
        question_text="Automated crop check flagged this image for expert review.",
        image_keys=storage_key,
        escalated_from_ai=True,
        topic="disease_management",
    )
    db.session.add(q)
    db.session.flush()
    return q


GROUP_SUMMARY_PROMPT = """Summarize this group discussion for a farmer who was offline.
Return short bullet points with emoji prefixes, then a line "Decisions:" and a line "Action items:".
Do not invent content absent from the messages."""

DECISIONS_PROMPT = """List decisions and action items from these messages as JSON:
{"decisions": [...], "action_items": [...]}. Only include what is actually stated."""


def summarize_messages(messages_text, kind="summary"):
    provider = _require_provider()
    prompt = GROUP_SUMMARY_PROMPT if kind == "summary" else DECISIONS_PROMPT
    answer = provider.chat(prompt, messages_text[:15000], json_mode=(kind != "summary"))
    return {"result": answer, "ai_generated": True}
