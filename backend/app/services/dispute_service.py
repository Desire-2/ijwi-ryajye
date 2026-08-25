from extensions import db
from app.errors import bad_request, conflict, forbidden, not_found
from app.models.base import utcnow
from app.models.admin import Dispute, DisputeEvidence, RiskEvent
from app.models.identity import User

DISPUTE_TYPES = [
    "wrong_quantity", "wrong_quality", "late_delivery", "non_payment",
    "damaged_produce", "fraud", "misrepresentation",
]
DISPUTE_STATES = [
    "OPEN", "EVIDENCE_REQUESTED", "UNDER_REVIEW", "RESOLUTION_PROPOSED",
    "RESOLVED", "ESCALATED", "CLOSED",
]

ALLOWED_DISPUTE_TRANSITIONS = {
    "OPEN": {"EVIDENCE_REQUESTED", "UNDER_REVIEW", "RESOLUTION_PROPOSED"},
    "EVIDENCE_REQUESTED": {"UNDER_REVIEW", "ESCALATED"},
    "UNDER_REVIEW": {"RESOLUTION_PROPOSED", "ESCALATED"},
    "RESOLUTION_PROPOSED": {"RESOLVED", "ESCALATED", "UNDER_REVIEW"},
    "RESOLVED": {"CLOSED"},
    "ESCALATED": {"RESOLUTION_PROPOSED", "RESOLVED", "CLOSED"},
    "CLOSED": set(),
}


def open_dispute(actor, order_id, payload):
    from app.services.order_service import get_order_or_404, assert_order_party

    order = get_order_or_404(order_id)
    assert_order_party(order, actor)

    if order.state not in ("PAID", "PROCESSING", "READY_FOR_PICKUP", "IN_TRANSIT", "DELIVERED", "COMPLETED"):
        raise conflict(f"Disputes cannot be opened on orders in state {order.state}")

    dispute_type = payload.get("dispute_type")
    if dispute_type not in DISPUTE_TYPES:
        raise bad_request(f"dispute_type must be one of {DISPUTE_TYPES}")

    existing = Dispute.query.filter(
        Dispute.order_id == order.id,
        Dispute.state.notin_(("CLOSED", "RESOLVED")),
        (Dispute.opened_by == actor.id),
    ).first()
    if existing:
        raise conflict("You already have an open dispute for this order")

    dispute = Dispute(
        order_id=order.id,
        opened_by=actor.id,
        against_user_id=order.seller_id if actor.id == order.buyer_id else order.buyer_id,
        dispute_type=dispute_type,
        description=payload.get("description", ""),
    )
    db.session.add(dispute)
    db.session.flush()

    if actor.id == order.seller_id or actor.id == order.buyer_id:
        pass

    from app.models.order import ALLOWED_ORDER_TRANSITIONS

    if "DISPUTED" in ALLOWED_ORDER_TRANSITIONS.get(order.state, set()):
        order.state = "DISPUTED"

    from app.services.notification_service import notify

    notify(dispute.against_user_id or order.seller_id, "DISPUTE_UPDATE",
           f"Dispute opened on order {order.order_number}",
           payload.get("description", "")[:120], subject_type="dispute", subject_id=dispute.id)
    return dispute


def add_evidence(actor, dispute_id, evidence_payloads):
    dispute = _get_or_404(dispute_id)
    parties = {dispute.opened_by, dispute.against_user_id}
    if actor.id not in parties and "ADMIN" not in actor.role_codes():
        raise forbidden("Only dispute parties can submit evidence")

    added = []
    for ev in evidence_payloads:
        item = DisputeEvidence(
            dispute_id=dispute.id,
            submitted_by=actor.id,
            evidence_type=ev["evidence_type"],
            storage_key=ev.get("storage_key"),
            message_id=ev.get("message_id"),
            payment_transaction_id=ev.get("payment_transaction_id"),
            description=ev.get("description", ""),
        )
        db.session.add(item)
        added.append(item)
    db.session.flush()
    return added


def transition_dispute(admin_actor, dispute_id, new_state, resolution_note=None):
    dispute = _get_or_404(dispute_id)
    if new_state not in ALLOWED_DISPUTE_TRANSITIONS.get(dispute.state, set()):
        raise conflict(f"Invalid dispute transition: {dispute.state} → {new_state}")
    dispute.state = new_state
    if new_state in ("RESOLVED", "CLOSED"):
        dispute.resolved_at = utcnow()
    if resolution_note is not None:
        dispute.resolution_note = resolution_note

    from app.services.order_service import get_order_or_404
    from app.models.order import ALLOWED_ORDER_TRANSITIONS

    order = get_order_or_404(dispute.order_id)
    if new_state == "RESOLVED" and order.state == "DISPUTED":
        order.state = "COMPLETED"
    elif new_state == "RESOLVED" and resolution_note and "refund" in resolution_note.lower():
        if "REFUNDED" in ALLOWED_ORDER_TRANSITIONS.get(order.state, set()):
            order.state = "REFUNDED"

    return dispute


def _get_or_404(dispute_id):
    d = db.session.get(Dispute, dispute_id)
    if d is None:
        raise not_found("Dispute not found")
    return d
