from decimal import Decimal

from sqlalchemy import text

from extensions import db
from app.errors import bad_request, conflict, not_found
from app.models.farm import Farm, INVENTORY_STATES
from app.models.marketplace import Inventory, InventoryReservation


def create_inventory(owner_id, product_id, quantity_value, unit_code="kg", farm_id=None, batch_ref="default"):
    qty = Decimal(str(quantity_value))
    if qty <= 0:
        raise bad_request("Inventory quantity must be greater than zero", "INVALID_QUANTITY")
    inv = Inventory(
        owner_id=owner_id,
        product_id=product_id,
        farm_id=farm_id,
        quantity_value=qty,
        quantity_total=qty,
        unit_code=unit_code,
        batch_ref=batch_ref or "default",
        state="AVAILABLE",
    )
    db.session.add(inv)
    db.session.flush()
    return inv


def add_stock(inventory_id, amount):
    inv = _lock(inventory_id)
    if inv.state not in ("AVAILABLE",):
        raise conflict("Cannot add stock to inventory in state " + inv.state)
    inv.quantity_total += Decimal(str(amount))
    db.session.flush()
    return inv


def _lock(inventory_id) -> Inventory:
    if db.engine.dialect.name == "sqlite":
        inv = db.session.get(Inventory, inventory_id)
        if inv is None:
            raise not_found("Inventory batch not found")
        return inv
    row = (
        db.session.execute(
            text("SELECT id FROM inventories WHERE id = :id FOR UPDATE"), {"id": inventory_id}
        ).fetchone()
    )
    if row is None:
        raise not_found("Inventory batch not found")
    return db.session.get(Inventory, inventory_id)


def available_quantity(inventory: Inventory) -> Decimal:
    return (
        Decimal(str(inventory.quantity_total))
        - Decimal(str(inventory.quantity_reserved))
        - Decimal(str(inventory.quantity_sold))
    )


def reserve(
    owner_id,
    product_id,
    quantity_value,
    unit_code,
    order_id=None,
    offer_id=None,
    bid_id=None,
    listing_id=None,
    buyer_request_id=None,
    farm_id=None,
):
    qty = Decimal(str(quantity_value))
    candidates = (
        Inventory.query.filter(
            Inventory.owner_id == owner_id,
            Inventory.product_id == product_id,
            Inventory.state == "AVAILABLE",
            Inventory.quantity_total - Inventory.quantity_reserved - Inventory.quantity_sold > 0,
        )
    )
    if farm_id:
        candidates = candidates.filter(Inventory.farm_id == farm_id)

    remaining = qty
    reservations = []
    # Lock candidate rows (in id order to avoid deadlocks) so two concurrent
    # reservations can never both read the same availability and oversell.
    query = candidates.order_by(Inventory.id)
    if db.engine.dialect.name != "sqlite":
        query = query.with_for_update()
    for inv in query.all():
        avail = available_quantity(inv)
        if avail <= 0:
            continue
        take = min(avail, remaining)
        inv.quantity_reserved = Decimal(str(inv.quantity_reserved)) + take
        res = InventoryReservation(
            inventory_id=inv.id,
            order_id=order_id,
            offer_id=offer_id,
            bid_id=bid_id,
            listing_id=listing_id,
            buyer_request_id=buyer_request_id,
            quantity_value=take,
            unit_code=unit_code,
            status="ACTIVE",
        )
        db.session.add(res)
        db.session.flush()
        reservations.append(res)
        remaining -= take
        if remaining <= 0:
            break

    if remaining > 0:
        raise conflict(
            f"Insufficient inventory: requested {qty} {unit_code}, short by {remaining}",
            "INSUFFICIENT_INVENTORY",
            {"requested": float(qty), "shortfall": float(remaining)},
        )
    return reservations


def release_reservation(reservation_id):
    res = db.session.get(InventoryReservation, reservation_id)
    if res is None or res.status != "ACTIVE":
        return None
    inv = _lock(res.inventory_id)
    inv.quantity_reserved = max(Decimal("0"), Decimal(str(inv.quantity_reserved)) - Decimal(str(res.quantity_value)))
    res.status = "RELEASED"
    res.released_at = utcnow()
    db.session.flush()
    return res


def convert_reservation_to_sale(reservation_id):
    res = db.session.get(InventoryReservation, reservation_id)
    if res is None or res.status != "ACTIVE":
        return None
    inv = _lock(res.inventory_id)
    inv.quantity_reserved = max(Decimal("0"), Decimal(str(inv.quantity_reserved)) - Decimal(str(res.quantity_value)))
    inv.quantity_sold = Decimal(str(inv.quantity_sold)) + Decimal(str(res.quantity_value))
    if available_quantity(inv) <= 0 and Decimal(str(inv.quantity_total)) <= Decimal(str(inv.quantity_sold)):
        inv.state = "SOLD"
    res.status = "CONVERTED_SALE"
    db.session.flush()
    return res


def set_state(inventory_id, new_state):
    if new_state not in INVENTORY_STATES:
        raise bad_request(f"Invalid inventory state {new_state}")
    inv = _lock(inventory_id)
    inv.state = new_state
    db.session.flush()
    return inv


from app.models.base import utcnow
