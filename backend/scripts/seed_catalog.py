"""Idempotent catalogue seed (categories, products, units).

Production-safe: creates ONLY the marketplace catalogue and units of measure.
It never touches users, listings, orders, wallet, posts or any other data.

Usage:
    python scripts/seed_catalog.py        # uses DATABASE_URL / development default
    DATABASE_URL=postgresql://... python scripts/seed_catalog.py

Safe to re-run: existing rows are left untouched.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


# (slug, name, icon, products)  product tuple: (name, slug, emoji, default_unit)
CATALOG = [
    ("crops", "Crops", "🌾", [
        ("Maize", "maize", "🌽", "kg"),
        ("Beans", "beans", "🫘", "kg"),
        ("Rice", "rice", "🍚", "kg"),
        ("Irish Potatoes", "irish-potatoes", "🥔", "kg"),
        ("Sweet Potatoes", "sweet-potatoes", "🍠", "kg"),
        ("Bananas", "bananas", "🍌", "kg"),
        ("Coffee", "coffee", "☕", "kg"),
        ("Cassava", "cassava", "🍠", "kg"),
        ("Tomatoes", "tomatoes", "🍅", "kg"),
        ("Onions", "onions", "🧅", "kg"),
        ("Carrots", "carrots", "🥕", "kg"),
        ("Cabbage", "cabbage", "🥬", "kg"),
        ("Avocado", "avocado", "🥑", "kg"),
        ("Passion Fruit", "passion-fruit", "🍋", "kg"),
        ("Pineapple", "pineapple", "🍍", "piece"),
        ("Soybeans", "soybeans", "🫘", "kg"),
    ]),
    ("livestock", "Livestock", "🐄", [
        ("Cattle", "cattle", "🐄", "piece"),
        ("Goats", "goats", "🐐", "piece"),
        ("Sheep", "sheep", "🐑", "piece"),
        ("Pigs", "pigs", "🐖", "piece"),
        ("Chickens", "chickens", "🐔", "piece"),
        ("Rabbits", "rabbits", "🐇", "piece"),
    ]),
    ("animal-products", "Animal Products", "🥛", [
        ("Fresh Milk", "fresh-milk", "🥛", "L"),
        ("Eggs", "eggs", "🥚", "crate"),
        ("Honey", "honey", "🍯", "kg"),
        ("Cheese", "cheese", "🧀", "kg"),
        ("Wool", "wool", "🧶", "kg"),
    ]),
    ("seeds-inputs", "Seeds & Inputs", "🌱", [
        ("Maize Seeds", "maize-seeds", "🌽", "kg"),
        ("Bean Seeds", "bean-seeds", "🫘", "kg"),
        ("Vegetable Seeds (mixed)", "vegetable-seeds", "🥦", "pack"),
        ("Fertilizer NPK", "fertilizer-npk", "🧪", "bag"),
        ("Fertilizer UREA", "fertilizer-urea", "🧪", "bag"),
        ("Organic Manure", "organic-manure", "💩", "bag"),
        ("Herbicide", "herbicide", "🧴", "L"),
        ("Pesticide", "pesticide", "🧴", "L"),
    ]),
    ("processed-products", "Processed Products", "📦", [
        ("Cassava Flour", "cassava-flour", "🍞", "bag"),
        ("Maize Flour", "maize-flour", "🌽", "bag"),
        ("Rice Flour", "rice-flour", "🍚", "bag"),
        ("Peanut Butter", "peanut-butter", "🥜", "jar"),
        ("Banana Juice", "banana-juice", "🍹", "L"),
    ]),
    ("farm-equipment", "Farm Equipment", "🚜", [
        ("Tractor", "tractor", "🚜", "piece"),
        ("Power Tiller", "power-tiller", "🚜", "piece"),
        ("Water Pump", "water-pump", "💧", "piece"),
        ("Knapsack Sprayer", "knapsack-sprayer", "🌿", "piece"),
        ("Maize Sheller", "maize-sheller", "🌽", "piece"),
        ("Milking Machine", "milking-machine", "🥛", "piece"),
    ]),
    ("rentals", "Rentals & Hired Tools", "🔧", [
        ("Tractor Hire", "tractor-hire", "🚜", "day"),
        ("Power Tiller Hire", "power-tiller-hire", "🚜", "day"),
        ("Water Pump Hire", "water-pump-hire", "💧", "day"),
        ("Land Preparation (hire)", "land-preparation", "🌱", "ha"),
    ]),
    ("farm-services", "Farm Services", "🧑‍🌾", [
        ("Ploughing Service", "ploughing-service", "🧑‍🌾", "ha"),
        ("Spraying Service", "spraying-service", "🌿", "ha"),
        ("Planting Service", "planting-service", "🌱", "ha"),
        ("Harvesting Service", "harvesting-service", "🌾", "day"),
        ("Vet Consultation", "vet-consultation", "🩺", "visit"),
    ]),
    ("logistics-transport", "Logistics & Transport", "🚚", [
        ("Farm Transport", "farm-transport", "🚚", "trip"),
        ("Fridge Truck Hire", "fridge-truck-hire", "🚛", "trip"),
    ]),
    ("storage-facilities", "Storage & Facilities", "🏠", [
        ("Cold Storage Space", "cold-storage-space", "🧊", "day"),
        ("Dry Warehouse Space", "dry-warehouse", "🏚️", "month"),
    ]),
]

UNITS = [
    ("kg", "Kilogram", "mass"), ("g", "Gram", "mass"),
    ("t", "Metric tonne", "mass"), ("L", "Litre", "volume"),
    ("ml", "Millilitre", "volume"), ("piece", "Piece", "count"),
    ("animal", "Animal", "count"), ("head", "Head", "count"),
    ("crate", "Crate", "count"), ("bag", "Bag (50kg)", "count"),
    ("pack", "Pack", "count"), ("jar", "Jar", "count"),
    ("day", "Day", "time"), ("hour", "Hour", "time"),
    ("week", "Week", "time"), ("month", "Month", "time"),
    ("ha", "Hectare", "area"), ("trip", "Trip", "service"),
    ("visit", "Visit", "service"),
]


def seed_catalog(app):
    from extensions import db as _db
    from app.models.catalog import Product, ProductCategory, UnitOfMeasure

    seeded_categories = 0
    seeded_products = 0
    seeded_units = 0

    for slug, name, icon, products in CATALOG:
        cat = ProductCategory.query.filter_by(slug=slug).first()
        if cat is None:
            cat = ProductCategory(name=name, slug=slug, icon=icon)
            _db.session.add(cat)
            _db.session.flush()
            seeded_categories += 1
        for pname, pslug, emoji, unit in products:
            if Product.query.filter_by(slug=pslug).first() is None:
                _db.session.add(Product(
                    name=pname, slug=pslug, category_id=cat.id,
                    emoji=emoji, default_unit=unit))
                seeded_products += 1

    for code, label, dimension in UNITS:
        if UnitOfMeasure.query.filter_by(code=code).first() is None:
            _db.session.add(UnitOfMeasure(code=code, label=label,
                                          dimension=dimension))
            seeded_units += 1

    _db.session.commit()
    print(f"catalog: +{seeded_categories} categories, +{seeded_products} products, "
          f"+{seeded_units} units")
    print(f"totals: {len(CATALOG)} categories, "
          f"{Product.query.filter(Product.deleted_at.is_(None)).count()} products, "
          f"{UnitOfMeasure.query.count()} units")


if __name__ == "__main__":
    import flask
    from extensions import db as _ext_db
    from app.models import catalog as _catalog  # noqa: F401 - register tables

    app = flask.Flask(__name__)
    app.config["SQLALCHEMY_DATABASE_URI"] = os.environ.get(
        "DATABASE_URL",
        "postgresql+psycopg2://ijwi:ijwi_dev@127.0.0.1:5432/ijwi_ryajye",
    )
    app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False
    _ext_db.init_app(app)
    with app.app_context():
        _ext_db.create_all()
        seed_catalog(app)