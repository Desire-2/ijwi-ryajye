from decimal import Decimal

from extensions import db
from app.errors import new_id
from app.errors import bad_request, conflict, forbidden, not_found
from app.models.base import utcnow
from app.models.identity import Cooperative, CooperativeMember, FarmerProfile, User
from app.models.marketplace import Listing
from app.services.audit_service import record as audit
from app.services.notification_service import notify


def create_cooperative(admin_user, payload):
    coop = Cooperative(
        name=payload["name"],
        registration_number=payload.get("registration_number"),
        admin_user_id=admin_user.id,
        country_code=payload.get("country_code", "RW"),
        region=payload.get("region"),
        district=payload.get("district"),
        description=payload.get("description", ""),
    )
    db.session.add(coop)
    db.session.flush()
    membership = CooperativeMember(
        cooperative_id=coop.id, user_id=admin_user.id, role="admin"
    )
    db.session.add(membership)
    coop.member_count = 1

    if "COOPERATIVE_ADMIN" not in admin_user.role_codes() and "ADMIN" not in admin_user.role_codes():
        from app.models.identity import UserRole

        db.session.add(UserRole(user_id=admin_user.id, role="COOPERATIVE_ADMIN"))
    if admin_user.farmer_profile:
        admin_user.farmer_profile.cooperative_id = coop.id
    db.session.flush()
    audit(admin_user, "cooperative.created", "cooperative", coop.id)
    return coop


def add_member(actor, coop, user_id):
    is_admin = actor.id == coop.admin_user_id or "ADMIN" in actor.role_codes()
    if not is_admin and actor.id != user_id:
        raise forbidden("Only cooperative admins can add other members")
    existing = CooperativeMember.query.filter_by(cooperative_id=coop.id, user_id=user_id).first()
    if existing:
        return existing
    member = CooperativeMember(cooperative_id=coop.id, user_id=user_id)
    db.session.add(member)
    coop.member_count += 1
    profile = FarmerProfile.query.filter_by(user_id=user_id).first()
    if profile is None:
        profile = FarmerProfile(user_id=user_id)
        db.session.add(profile)
        db.session.flush()
    profile.cooperative_id = coop.id
    notify(user_id, "GROUP_ACTIVITY", f"Joined {coop.name}", "Welcome to your cooperative space",
           subject_type="cooperative", subject_id=coop.id)
    return member


def create_aggregation_lot(actor, coop, payload):
    from app.models.catalog import Product
    from app.models.marketplace import Inventory

    product = db.session.get(Product, payload["product_id"])
    if product is None:
        raise not_found("Product not found")

    listing = Listing(
        seller_id=actor.id,
        cooperative_id=coop.id,
        group_id=None,
        product_id=product.id,
        title=payload.get("title") or f"{product.name} — {coop.name} bulk sale",
        description=payload.get("description", ""),
        listing_type="GROUP_SALE",
        state="ACTIVE",
        quantity_value=Decimal("0"),
        available_quantity=Decimal("0"),
        unit_code=payload.get("unit_code", "kg"),
        price_minor=int(payload["price_minor"]) if payload.get("price_minor") else None,
        price_type="NEGOTIABLE" if not payload.get("price_minor") else "PER_UNIT",
        currency_code=payload.get("currency_code", "RWF"),
        quality_grade=payload.get("quality_grade", "UNGRADED"),
        location_region=coop.region,
        location_district=coop.district,
        minimum_order_value=Decimal(str(payload.get("minimum_order_value", 0))),
    )
    db.session.add(listing)
    db.session.flush()

    inv = Inventory(
        owner_id=actor.id,
        farm_id=None,
        product_id=product.id,
        batch_ref=f"coop-{listing.id[:8]}",
        quantity_value=Decimal("0"),
        quantity_total=Decimal("0"),
        unit_code=listing.unit_code,
    )
    db.session.add(inv)
    db.session.flush()
    audit(actor, "cooperative.lot_created", "listing", listing.id)
    return {"listing": listing, "inventory": inv}


def contribute_to_lot(farmer, lot_listing, quantity_value, unit_code):
    if lot_listing.listing_type != "GROUP_SALE":
        raise bad_request("Contributions are only for group-sale lots")
    member = CooperativeMember.query.filter_by(
        cooperative_id=lot_listing.cooperative_id, user_id=farmer.id
    ).first()
    if member is None:
        raise forbidden("Only cooperative members can contribute to this lot")
    qty = Decimal(str(quantity_value))
    if qty <= 0:
        raise bad_request("Contribution must be positive")

    reservations = _reserve_from_farmer_inventory(farmer.id, lot_listing.product_id, qty, unit_code)

    contribution = LotContribution(
        listing_id=lot_listing.id,
        farmer_id=farmer.id,
        quantity_value=qty,
        unit_code=unit_code,
    )
    db.session.add(contribution)

    lot_listing.quantity_value = Decimal(str(lot_listing.quantity_value)) + qty
    lot_listing.available_quantity = Decimal(str(lot_listing.available_quantity)) + qty

    from app.models.marketplace import Inventory

    inv = Inventory.query.filter(
        Inventory.owner_id == lot_listing.seller_id,
        Inventory.batch_ref == f"coop-{lot_listing.id[:8]}",
    ).first()
    if inv:
        inv.quantity_total = Decimal(str(inv.quantity_total)) + qty
        inv.quantity_value = Decimal(str(inv.quantity_value)) + qty
    db.session.flush()

    audit(farmer, "cooperative.contribution", "listing", lot_listing.id, {"quantity": float(qty)})
    return contribution


def _reserve_from_farmer_inventory(owner_id, product_id, qty, unit):
    from app.services import inventory_service

    try:
        return inventory_service.reserve(owner_id=owner_id, product_id=product_id,
                                         quantity_value=float(qty), unit_code=unit)
    except Exception as exc:
        if "INSUFFICIENT_INVENTORY" in str(getattr(exc, "code", "")):
            raise forbidden("You do not have enough recorded inventory to contribute this amount. Record your stock first.")
        raise


def settle_lot(lot_listing, sale_order, actor):
    contributions = LotContribution.query.filter_by(listing_id=lot_listing.id).all()
    total_qty = sum(Decimal(str(c.quantity_value)) for c in contributions)
    if total_qty <= 0:
        raise conflict("No contributions recorded on this lot")

    from app.models.payment import WalletLedgerEntry
    from app.services import wallet_service
    from app.services.fee_service import fee_for_scope

    gross = int(sale_order.total_amount_minor)
    platform_fee = int(sale_order.platform_fee_minor or 0)
    distributable = gross - platform_fee

    allocations = []
    for c in contributions:
        share = Decimal(str(c.quantity_value)) / total_qty
        amount = int((Decimal(distributable) * share).to_integral_value())
        allocations.append((c, amount))

    rounding_residual = distributable - sum(a for _, a in allocations)
    if allocations and rounding_residual != 0:
        first_c, first_amt = allocations[0]
        allocations[0] = (first_c, first_amt + rounding_residual)

    for c, amount in allocations:
        wallet_service.post_entry(
            c.farmer_id, "CREDIT", "COOP_SETTLEMENT_IN", amount,
            reference_type="order", reference_id=sale_order.id,
            description=f"Cooperative settlement for {sale_order.order_number}",
            idempotency_key=f"coop:{sale_order.id}:{c.id}",
        )
        notify(c.farmer_id, "PAYOUT", "Cooperative payout received",
               f"Your share of order {sale_order.order_number}", subject_type="order", subject_id=sale_order.id)

    audit(actor, "cooperative.settled", "order", sale_order.id, {"allocations": len(allocations)})
    return [
        {"contribution_id": c.id, "farmer_id": c.farmer_id, "amount_minor": amt}
        for c, amt in allocations
    ]


class LotContribution(db.Model):
    __tablename__ = "lot_contributions"
    id = db.Column(db.String(32), primary_key=True, default=new_id)
    created_at = db.Column(db.DateTime(timezone=True), default=utcnow, nullable=False)
    listing_id = db.Column(db.String(32), db.ForeignKey("listings.id"), nullable=False, index=True)
    farmer_id = db.Column(db.String(32), db.ForeignKey("users.id"), nullable=False, index=True)
    quantity_value = db.Column(db.Numeric(14, 3), nullable=False)
    unit_code = db.Column(db.String(20), nullable=False, default="kg")
