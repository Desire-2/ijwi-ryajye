import hashlib
import hmac
import json
import secrets
from abc import ABC, abstractmethod

from flask import current_app

from app.errors import not_configured


class WebhookResult:
    def __init__(self, event_id, payment_reference, state, provider_metadata=None, signature_valid=False):
        self.event_id = event_id
        self.payment_reference = payment_reference
        self.state = state
        self.provider_metadata = provider_metadata or {}
        self.signature_valid = signature_valid


class PaymentProvider(ABC):
    code = "abstract"

    @abstractmethod
    def initiate_payment(self, order, amount_minor, currency, method, phone=None, idempotency_key=None):
        ...

    @abstractmethod
    def verify_webhook(self, payload_bytes, headers) -> WebhookResult:
        ...

    def payout(self, withdrawal):
        raise NotImplementedError(f"{self.code} does not support payouts")

    def refund(self, transaction, amount_minor, reason=""):
        raise NotImplementedError(f"{self.code} does not support refunds")


class MockProvider(PaymentProvider):
    code = "mock"

    def __init__(self, webhook_secret):
        self.webhook_secret = webhook_secret.encode()

    def initiate_payment(self, order, amount_minor, currency, method, phone=None, idempotency_key=None):
        ref = f"MOCK-{secrets.randbelow(10**9):09d}"
        return {
            "provider": self.code,
            "provider_reference": ref,
            "state": "PENDING_PROVIDER",
            "instructions": f"Dial *182*8*1# and approve payment of {amount_minor} minor units for order {order.order_number}",
        }

    def _sign(self, body: bytes, timestamp: str) -> str:
        signed_payload = timestamp.encode() + b"." + body
        return hmac.new(self.webhook_secret, signed_payload, hashlib.sha256).hexdigest()

    def verify_webhook(self, payload_bytes, headers) -> WebhookResult:
        try:
            data = json.loads(payload_bytes)
        except Exception:
            return WebhookResult("unknown", None, "FAILED", signature_valid=False)

        sig = headers.get("X-Ijwi-Signature", "")
        ts = headers.get("X-Ijwi-Timestamp", "")
        expected = self._sign(payload_bytes, ts)
        valid = hmac.compare_digest(sig, expected) if (sig and ts) else False

        return WebhookResult(
            event_id=data.get("event_id", ""),
            payment_reference=data.get("reference"),
            state=data.get("state", "SUCCEEDED"),
            provider_metadata={"raw_state": data.get("state")},
            signature_valid=valid,
        )


class StripeProvider(PaymentProvider):
    code = "stripe"

    def __init__(self, secret_key, webhook_secret):
        import requests as _requests

        self.secret_key = secret_key
        self.webhook_secret = webhook_secret.encode()

    def initiate_payment(self, order, amount_minor, currency, method, phone=None, idempotency_key=None):
        import requests

        resp = requests.post(
            "https://api.stripe.com/v1/payment_intents",
            auth=(self.secret_key, ""),
            data={
                "amount": amount_minor,
                "currency": currency.lower(),
                "metadata[order_id]": order.id,
                "metadata[order_number]": order.order_number,
            },
            idempotency_key=idempotency_key or f"order:{order.id}",
            timeout=15,
        )
        resp.raise_for_status()
        data = resp.json()
        return {
            "provider": self.code,
            "provider_reference": data["id"],
            "state": "PENDING_PROVIDER",
            "client_secret": data.get("client_secret"),
        }

    def verify_webhook(self, payload_bytes, headers) -> WebhookResult:
        sig_header = headers.get("Stripe-Signature", "")
        try:
            parts = dict(p.split("=", 1) for p in sig_header.split(","))
            ts, v1 = parts.get("t", ""), parts.get("v1", "")
        except Exception:
            return WebhookResult("unknown", None, "INVALID", signature_valid=False)

        signed_payload = ts + b"." if isinstance(ts, bytes) else f"{ts}.".encode()
        expected = hmac.new(self.webhook_secret, signed_payload + payload_bytes, hashlib.sha256).hexdigest()
        valid = bool(v1) and hmac.compare_digest(v1, expected)
        try:
            data = json.loads(payload_bytes)
        except Exception:
            return WebhookResult("unknown", None, "INVALID", signature_valid=False)

        event_type = data.get("type", "")
        obj = data.get("data", {}).get("object", {})
        state_map = {
            "payment_intent.succeeded": "SUCCEEDED",
            "payment_intent.payment_failed": "FAILED",
            "charge.refunded": "REFUNDED",
        }
        return WebhookResult(
            event_id=data.get("id", ""),
            payment_reference=obj.get("id") or obj.get("payment_intent"),
            state=state_map.get(event_type, "IGNORED"),
            provider_metadata={"event_type": event_type},
            signature_valid=valid,
        )


class MtnMomoProvider(PaymentProvider):
    code = "mtn_momo"

    def __init__(self, subscription_key, api_user, api_key, target_env="sandbox"):
        import requests as _requests

        self.subscription_key = subscription_key
        self.api_user = api_user
        self.api_key = api_key
        self.target_env = target_env
        self.base = "https://sandbox.momodeveloper.mtn.com" if target_env == "sandbox" else "https://proxy.momoapi.mtn.com"

    def initiate_payment(self, order, amount_minor, currency, method, phone=None, idempotency_key=None):
        if not (self.subscription_key and self.api_key):
            raise not_configured("MTN MoMo")
        import requests

        token_resp = requests.post(
            f"{self.base}/collection/token/",
            headers={
                "Ocp-Apim-Subscription-Key": self.subscription_key,
            },
            auth=(self.api_user, self.api_key),
            timeout=15,
        )
        token_resp.raise_for_status()
        access_token = token_resp.json()["access_token"]

        reference_id = str(__import__("uuid").uuid4())
        resp = requests.post(
            f"{self.base}/collection/v1_0/requesttopay",
            headers={
                "Authorization": f"Bearer {access_token}",
                "X-Reference-Id": reference_id,
                "X-Target-Environment": self.target_env,
                "Ocp-Apim-Subscription-Key": self.subscription_key,
                "Content-Type": "application/json",
            },
            json={
                "amount": str(amount_minor),
                "currency": currency,
                "externalId": order.order_number,
                "payer": {"partyIdType": "MSISDN", "partyId": (phone or "").lstrip("+")},
                "payerMessage": f"Ijwi Ryajye order {order.order_number}",
                "payeeNote": f"Ijwi Ryajye order {order.order_number}",
            },
            timeout=20,
        )
        resp.raise_for_status()
        return {
            "provider": self.code,
            "provider_reference": reference_id,
            "state": "PENDING_PROVIDER",
            "instructions": "Approve the payment prompt on your phone.",
        }

    def verify_webhook(self, payload_bytes, headers) -> WebhookResult:
        try:
            data = json.loads(payload_bytes)
        except Exception:
            return WebhookResult("unknown", None, "INVALID", signature_valid=False)
        return WebhookResult(
            event_id=data.get("referenceId", "") or data.get("financialTransactionId", ""),
            payment_reference=data.get("referenceId"),
            state={"SUCCESSFUL": "SUCCEEDED", "FAILED": "FAILED"}.get(data.get("status"), "PROCESSING"),
            provider_metadata=data,
            signature_valid=True,
        )


_registry = {}


def register_providers(app):
    specs = app.config.get("PAYMENT_PROVIDERS", "mock").split(",")
    secrets_map = {}
    for pair in app.config.get("PAYMENT_WEBHOOK_SECRETS", "").split(";"):
        if ":" in pair:
            k, v = pair.split(":", 1)
            secrets_map[k.strip()] = v.strip()

    for name in specs:
        name = name.strip().lower()
        if name == "mock":
            _registry[name] = MockProvider(secrets_map.get("mock", "dev-webhook-secret"))
        elif name == "stripe":
            key = app.config.get("STRIPE_SECRET_KEY")
            ws = secrets_map.get("stripe")
            if key and ws:
                _registry[name] = StripeProvider(key, ws)
        elif name in ("mtn_momo", "mtn"):
            prov = MtnMomoProvider(
                app.config.get("MTN_SUBSCRIPTION_KEY", ""),
                app.config.get("MTN_API_USER", ""),
                app.config.get("MTN_API_KEY", ""),
                app.config.get("MTN_TARGET_ENV", "sandbox"),
            )
            _registry["mtn_momo"] = prov
    _registry.setdefault("mock", MockProvider(secrets_map.get("mock", "dev-webhook-secret")))


def get_provider(name):
    from app.errors import bad_request

    prov = _registry.get((name or "mock").lower())
    if prov is None:
        raise bad_request(f"Unknown payment provider '{name}'", "UNKNOWN_PROVIDER")
    return prov


def available_providers():
    return sorted(_registry.keys())
